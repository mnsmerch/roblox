--[[
	Step 4 specification.

	The property that matters: for any two states, applying Diff(a, b) to a copy
	of `a` must produce exactly `b`. If that ever fails, a player's inventory
	silently disagrees with the server and it looks like a gameplay bug.

	Also covers the replication security boundary - every profile field must be
	explicitly replicated or explicitly withheld - by loading the real
	Replication module against the real ProfileTemplate.

	Run with:  ./tests/run.sh
]]

-- ── Roblox shims ────────────────────────────────────────────────────────────
local _shared = { Config = {}, Modules = {} }
local _services = {}

game = {
	GetService = function(_, name)
		return _services[name]
	end,
}

_services.RunService = { IsServer = function() return true end, IsStudio = function() return false end }
_services.Players = {
	PlayerRemoving = { Connect = function() end },
	PlayerAdded = { Connect = function() end },
	GetPlayers = function() return {} end,
}
_services.ReplicatedStorage = {
	WaitForChild = function() return _shared end,
	FindFirstChild = function() return nil end,
}

local _realRequire = require
require = function(target)
	if type(target) == "table" then return target end
	return _realRequire(target)
end

--@INJECT GameConfig=src/ReplicatedStorage/SAD_Shared/Config/GameConfig.lua TableUtil=src/ReplicatedStorage/SAD_Shared/Modules/TableUtil.lua@

_shared.Config.GameConfig = GameConfig
_shared.Modules.TableUtil = TableUtil

-- Patch requires script.Parent.TableUtil, so `script` points at the Modules folder.
script = _shared.Modules
script.Parent = _shared.Modules

--@INJECT Patch=src/ReplicatedStorage/SAD_Shared/Modules/Patch.lua ProfileTemplate=src/ServerScriptService/SAD_Server/Services/DataService/ProfileTemplate.lua@

_shared.Modules.Patch = Patch
_shared.Modules.Log = { debug = function() end, info = function() end, warn = function() end, error = function() end }
_shared.Modules.Net = { FireClient = function() end, OnInvoke = function() end, OnEvent = function() end }

-- Replication reaches for script.Parent (its owning PlayerDataService, hoisted
-- in Init) and script.Parent.Parent.DataService.ProfileTemplate.
local _templateHolder = { ProfileTemplate = ProfileTemplate }
local _ownerStub = {
	Get = function() return nil end,
	Parent = { DataService = _templateHolder },
}
script = { Parent = _ownerStub }

--@INJECT Replication=src/ServerScriptService/SAD_Server/Services/PlayerDataService/Replication.lua@

-- ── Harness ─────────────────────────────────────────────────────────────────
local passed, failed = 0, 0
local function eq(label, got, want)
	if got == want then passed = passed + 1
	else failed = failed + 1; print(string.format("  FAIL %-46s got %s want %s", label, tostring(got), tostring(want))) end
end
local function ok(label, cond)
	if cond then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. label) end
end
local function section(name) print("\n== " .. name) end

--[[
	The core property, used everywhere below.

	Diff emits ABSOLUTE paths including basePath, so when a basePath is given
	the patches have to be applied to a tree that actually has that prefix -
	applying them to the bare `before` table would write a parallel branch and
	compare two unrelated things.
]]
local function roundTrip(label, before, after, basePath)
	basePath = basePath or {}
	local patches = Patch.Diff(before, after, basePath)

	local live, result
	if #basePath == 0 then
		live = TableUtil.DeepCopy(before)
		Patch.ApplyAll(live, patches)
		result = live
	else
		live = {}
		Patch.Apply(live, { Path = basePath, Value = TableUtil.DeepCopy(before) })
		Patch.ApplyAll(live, patches)
		result = Patch.Read(live, basePath)
	end

	local matched = TableUtil.DeepEquals(result, after)
	if matched then passed = passed + 1
	else
		failed = failed + 1
		print("  FAIL round trip: " .. label .. " (" .. #patches .. " patches)")
	end
	return patches
end

------------------------------------------------------------------ diff basics
section("Patch.Diff - scalars")

eq("identical scalars produce nothing", #Patch.Diff(5, 5, { "Fossils" }), 0)
eq("identical strings produce nothing", #Patch.Diff("a", "a", { "x" }), 0)
eq("a changed scalar is one patch", #Patch.Diff(5, 9, { "Fossils" }), 1)
eq("the patch carries the new value", Patch.Diff(5, 9, { "Fossils" })[1].Value, 9)
eq("the patch carries the path", Patch.Diff(5, 9, { "Fossils" })[1].Path[1], "Fossils")
ok("nil -> value is a set", Patch.Diff(nil, 9, { "x" })[1].Value == 9)
ok("value -> nil is a remove", Patch.Diff(9, nil, { "x" })[1].Remove == true)
ok("false is a value, not a removal", Patch.Diff(true, false, { "x" })[1].Remove == nil)
eq("false round trips as false", Patch.Diff(true, false, { "x" })[1].Value, false)

section("Patch.Diff - tables")

eq("identical tables produce nothing", #Patch.Diff({ a = 1 }, { a = 1 }, { "t" }), 0)
eq("one changed field is one patch", #Patch.Diff({ a = 1, b = 2 }, { a = 1, b = 3 }, { "t" }), 1)
eq("a deleted key is one patch", #Patch.Diff({ a = 1, b = 2 }, { a = 1 }, { "t" }), 1)
ok("the deletion is a removal", Patch.Diff({ a = 1, b = 2 }, { a = 1 }, { "t" })[1].Remove == true)
eq("an added key is one patch", #Patch.Diff({ a = 1 }, { a = 1, b = 2 }, { "t" }), 1)

-- Numeric keys must survive as numbers. Stringifying them would make the
-- client write Incubators["1"] where the server meant Incubators[1].
local numericPatch = Patch.Diff({}, { [1] = { EggUid = "abc" } }, { "Incubators" })[1]
eq("numeric key stays a number", type(numericPatch.Path[2]), "number")
eq("numeric key value", numericPatch.Path[2], 1)

section("Patch.Diff - depth")

-- Depth 3 gives per-field granularity for Dinos -> uid -> field.
local dinoBefore = { ab12 = { SpeciesId = "trex", Stars = 1, Placed = false } }
local dinoAfter = { ab12 = { SpeciesId = "trex", Stars = 2, Placed = false } }
local dinoPatches = Patch.Diff(dinoBefore, dinoAfter, { "Dinos" })
eq("one field change is one patch", #dinoPatches, 1)
eq("path reaches the field", #dinoPatches[1].Path, 3)
eq("path names the field", dinoPatches[1].Path[3], "Stars")
eq("only the new value is sent", dinoPatches[1].Value, 2)

-- Past the depth limit, the subtree ships wholesale rather than per leaf.
local deepBefore = { a = { b = { c = { d = 1 } } } }
local deepAfter = { a = { b = { c = { d = 2 } } } }
local deepPatches = Patch.Diff(deepBefore, deepAfter, { "root" })
eq("depth-limited patch count", #deepPatches, 1)
ok("subtree sent wholesale at the limit", type(deepPatches[1].Value) == "table")
roundTrip("beyond max depth", deepBefore, deepAfter, { "root" })

-- A brand-new record ships whole.
local addPatches = Patch.Diff({}, { cd34 = { SpeciesId = "velociraptor", Stars = 1 } }, { "Dinos" })
eq("a new record is one patch", #addPatches, 1)
ok("the whole record is sent", addPatches[1].Value.SpeciesId == "velociraptor")

section("Patch.Diff - deep copies, no shared references")

-- Diff descends one level here, so the patch is at {"t","nested"} carrying a
-- copy of that subtree. Mutating the source afterwards must not touch it.
local source = { nested = { value = 1 } }
local copyPatches = Patch.Diff({}, source, { "t" })
eq("patch path descends one level", copyPatches[1].Path[2], "nested")
source.nested.value = 999
eq("patch holds a copy, not a reference", copyPatches[1].Value.value, 1)

------------------------------------------------------------------ round trip
section("Round trip: apply(Diff(a, b), a) == b")

roundTrip("empty to empty", {}, {})
roundTrip("empty to populated", {}, { Fossils = 100, DNA = 5 })
roundTrip("populated to empty", { Fossils = 100, DNA = 5 }, {})
roundTrip("scalar change", { Fossils = 100 }, { Fossils = 250 })
roundTrip("nested change", { Settings = { MusicVolume = 60 } }, { Settings = { MusicVolume = 15 } })
roundTrip("key added", { a = 1 }, { a = 1, b = 2 })
roundTrip("key removed", { a = 1, b = 2 }, { a = 1 })
roundTrip("type change: number to table", { x = 1 }, { x = { y = 2 } })
roundTrip("type change: table to number", { x = { y = 2 } }, { x = 1 })
roundTrip("nil to false", { x = nil }, { x = false })
roundTrip("false to nil", { x = false }, { x = nil })
roundTrip("numeric keys", { [1] = "a", [2] = "b" }, { [1] = "a", [3] = "c" })
roundTrip("mixed key types", { [1] = "a", b = 2 }, { [1] = "z", b = 2, [3] = "c" })

-- A realistic profile slice moving through a real gameplay moment.
local profileBefore = {
	Fossils = 125000, DNA = 40, Rebirths = 3,
	ZonesUnlocked = { plains = true, canyon = true },
	Upgrades = { feedingTrough = 4, eggSense = 2 },
	Dinos = {
		ab12 = { SpeciesId = "trex", Rarity = "legendary", Stars = 1, Placed = true, TileX = 2, TileZ = 3 },
		cd34 = { SpeciesId = "velociraptor", Rarity = "rare", Stars = 1, Placed = false },
	},
	Incubators = { [1] = { EggUid = "e1", HatchAt = 1000 } },
	Settings = { MusicVolume = 60, SfxVolume = 80, Particles = "High" },
	Stats = { EggsStolen = 940, EggsHatched = 800 },
}
local profileAfter = TableUtil.DeepCopy(profileBefore)
profileAfter.Fossils = 138500                                   -- collected income
profileAfter.Dinos.cd34.Placed = true                           -- placed a dinosaur
profileAfter.Dinos.cd34.TileX = 5
profileAfter.Dinos.cd34.TileZ = 1
profileAfter.Dinos.ef56 = { SpeciesId = "glitchcompy", Rarity = "secret", Stars = 1, Placed = false }
profileAfter.Incubators[1] = nil                                -- it hatched
profileAfter.ZonesUnlocked.swamp = true                         -- unlocked a zone
profileAfter.Upgrades.feedingTrough = 5
profileAfter.Settings.MusicVolume = 15
profileAfter.Stats.EggsHatched = 801

local realPatches = roundTrip("a realistic gameplay tick", profileBefore, profileAfter)
ok("a busy tick stays under 15 patches", #realPatches < 15)
print(string.format("  (a realistic tick produced %d patches)", #realPatches))

-- Untouched subtrees must contribute nothing.
local untouched = Patch.Diff(profileBefore.Stats, profileBefore.Stats, { "Stats" })
eq("an untouched subtree is silent", #untouched, 0)

section("Patch.Apply - robustness")

local root = {}
Patch.Apply(root, { Path = { "a", "b", "c" }, Value = 1 })
eq("creates intermediate tables", root.a.b.c, 1)

local overwrite = { a = 5 }
Patch.Apply(overwrite, { Path = { "a", "b" }, Value = 1 })
eq("replaces a scalar with a table when needed", overwrite.a.b, 1)

ok("an empty path is rejected", Patch.Apply({}, { Path = {}, Value = 1 }) == false)
ok("a non-table path is rejected", Patch.Apply({}, { Path = "nope", Value = 1 }) == false)

local removal = { a = { b = 1, c = 2 } }
Patch.Apply(removal, { Path = { "a", "b" }, Remove = true })
eq("removal deletes", removal.a.b, nil)
eq("removal leaves siblings", removal.a.c, 2)

eq("ApplyAll reports the count", Patch.ApplyAll({}, {
	{ Path = { "a" }, Value = 1 },
	{ Path = { "b" }, Value = 2 },
	{ Path = {}, Value = 3 },
}), 2)

section("Patch.Read and PathsOverlap")

local tree = { Dinos = { ab12 = { Stars = 3 } } }
eq("reads a deep value", Patch.Read(tree, { "Dinos", "ab12", "Stars" }), 3)
eq("missing path reads nil", Patch.Read(tree, { "Dinos", "zz99", "Stars" }), nil)
eq("reading through a scalar is nil", Patch.Read({ a = 1 }, { "a", "b" }), nil)
eq("empty path reads the root", Patch.Read(tree, {}), tree)

ok("identical paths overlap", Patch.PathsOverlap({ "Dinos" }, { "Dinos" }))
ok("watcher above the change", Patch.PathsOverlap({ "Dinos" }, { "Dinos", "ab12", "Stars" }))
ok("watcher below the change", Patch.PathsOverlap({ "Dinos", "ab12", "Stars" }, { "Dinos" }))
ok("siblings do not overlap", not Patch.PathsOverlap({ "Fossils" }, { "DNA" }))
ok("different records do not overlap", not Patch.PathsOverlap({ "Dinos", "ab12" }, { "Dinos", "cd34" }))

------------------------------------------------------------------ boundary
section("Replication security boundary")

local REPLICATED, WITHHELD = Replication._REPLICATED, Replication._WITHHELD

-- Every profile field must be an explicit decision, in exactly one direction.
for key in pairs(ProfileTemplate) do
	local isReplicated = REPLICATED[key] ~= nil
	local isWithheld = WITHHELD[key] ~= nil
	ok("declared exactly once: " .. key, (isReplicated or isWithheld) and not (isReplicated and isWithheld))
end

-- Nothing declared that is not in the schema.
for key in pairs(REPLICATED) do
	ok("replicated field is real: " .. key, ProfileTemplate[key] ~= nil)
end
for key in pairs(WITHHELD) do
	ok("withheld field is real: " .. key, ProfileTemplate[key] ~= nil)
end

-- The fields that must never reach a client, named explicitly so removing one
-- from WITHHELD fails here rather than shipping quietly.
for _, key in ipairs({ "ProcessedReceipts", "RobuxSpent", "LastSeen", "FirstJoinAt", "SchemaVersion" }) do
	ok("never replicated: " .. key, WITHHELD[key] ~= nil and REPLICATED[key] == nil)
end

-- The fields the HUD cannot work without.
for _, key in ipairs({ "Fossils", "DNA", "Rebirths", "Dinos", "Eggs", "Incubators",
	"Settings", "ShieldUntil", "Boosts", "Tutorial" }) do
	ok("replicated: " .. key, REPLICATED[key] == true)
end

-- Init asserts the partition at boot. It must pass on the real schema...
ok("Init accepts the real schema", pcall(Replication.Init, {}))

-- ...and refuse a schema with an undeclared field.
local extended = TableUtil.DeepCopy(ProfileTemplate)
extended.SomeNewFieldNobodyDeclared = 0
_templateHolder.ProfileTemplate = extended
local declaredOk, declaredErr = pcall(Replication.Init, {})
ok("Init rejects an undeclared field", not declaredOk)
ok("the error names the field",
	not declaredOk and string.find(tostring(declaredErr), "SomeNewFieldNobodyDeclared") ~= nil)

-- ...and refuse a declaration for a field that no longer exists.
local shrunk = TableUtil.DeepCopy(ProfileTemplate)
shrunk.RobuxSpent = nil
_templateHolder.ProfileTemplate = shrunk
local staleOk, staleErr = pcall(Replication.Init, {})
ok("Init rejects a stale declaration", not staleOk)
ok("the stale error names the field",
	not staleOk and string.find(tostring(staleErr), "RobuxSpent") ~= nil)

_templateHolder.ProfileTemplate = ProfileTemplate

------------------------------------------------------------------ settings
section("Settings schema")

local schema = GameConfig.SettingsSchema
for key, value in pairs(ProfileTemplate.Settings) do
	ok("settable setting has a schema: " .. key, schema[key] ~= nil)
	eq("schema type matches the default: " .. key, schema[key].Type, typeof(value))
end
for key in pairs(schema) do
	ok("schema entry is a real setting: " .. key, ProfileTemplate.Settings[key] ~= nil)
end

for key, rule in pairs(schema) do
	if rule.Type == "number" then
		ok("numeric setting has bounds: " .. key, rule.Min ~= nil and rule.Max ~= nil and rule.Min < rule.Max)
		local default = ProfileTemplate.Settings[key]
		ok("default is inside its bounds: " .. key, default >= rule.Min and default <= rule.Max)
	elseif rule.Type == "string" then
		ok("string setting has options: " .. key, type(rule.OneOf) == "table" and #rule.OneOf > 0)
		local default, found = ProfileTemplate.Settings[key], false
		for _, option in ipairs(rule.OneOf) do
			if option == default then found = true break end
		end
		ok("default is an allowed option: " .. key, found)
	end
end

print(string.format("\n%s\n  %d passed, %d failed\n", string.rep("=", 46), passed, failed))
if failed > 0 then error("TESTS FAILED") end
