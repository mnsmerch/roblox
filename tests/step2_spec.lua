--[[
	Step 2 specification.

	Covers the two things that can silently destroy a player's save:
	  * the profile template drifting out of sync with the schema, and
	  * the migration chain misbehaving.

	Both are verified offline, with fixtures, before any of it touches a real
	DataStore. ProfileStore itself is not covered here - it needs Roblox - so
	the in-Studio test list in docs/13-build-order.md Step 2 is not optional.

	Run with:  ./tests/run.sh
]]

-- ── Roblox shims ────────────────────────────────────────────────────────────
-- ProfileTemplate and Migrations both reach for ReplicatedStorage/SAD_Shared.
-- Build a fake tree whose leaves ARE the loaded module tables, and make
-- require() the identity function so `require(Shared.Config.GameConfig)`
-- resolves to the table we put there.

local _shared = { Config = {}, Modules = {} }

game = {
	GetService = function(_, _name)
		return { WaitForChild = function(_, _child) return _shared end }
	end,
}

local _realRequire = require
require = function(target)
	if type(target) == "table" then
		return target
	end
	return _realRequire(target)
end

--@INJECT GameConfig=src/ReplicatedStorage/SAD_Shared/Config/GameConfig.lua TableUtil=src/ReplicatedStorage/SAD_Shared/Modules/TableUtil.lua@

_shared.Config.GameConfig = GameConfig
_shared.Modules.TableUtil = TableUtil

--@INJECT ProfileTemplate=src/ServerScriptService/SAD_Server/Services/DataService/ProfileTemplate.lua Migrations=src/ServerScriptService/SAD_Server/Services/DataService/Migrations.lua@

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

------------------------------------------------------------------ template
section("ProfileTemplate")

-- Independent key list. Deliberately NOT derived from the template, so adding
-- a field to one and not the other fails here.
local EXPECTED = {
	"SchemaVersion",
	"Fossils", "DNA",
	"Rebirths", "ZonesUnlocked", "Shrines", "Upgrades", "Defences", "LuckNodes", "BonusDinoSlots", "BonusVaultSlots", "Titles",
	"Dinos", "Eggs", "Incubators",
	"Index", "IndexMilestones",
	"Boosts", "Items", "StealCooldowns", "RevengeMarks", "RobbedAt", "GlobalStealAt", "ShieldUntil", "ShieldBankSecs",
	"Daily", "Quests", "Tutorial",
	"Gamepasses", "ProcessedReceipts", "RobuxSpent",
	"Settings", "Stats",
	"LastSeen", "BankedFossils", "BankedAt", "BankedRate", "FirstJoinAt", "NewPlayerProtectionDone",
}

local expectedSet = {}
for _, k in ipairs(EXPECTED) do expectedSet[k] = true end

for _, key in ipairs(EXPECTED) do
	ok("template has " .. key, ProfileTemplate[key] ~= nil)
end
for key in pairs(ProfileTemplate) do
	ok("template key '" .. key .. "' is expected", expectedSet[key] == true)
end

-- Everything in the template is persisted to every player's save, so a stray
-- function or helper list here would be written to 24 DataStore keys per server.
local function assertNoFunctions(t, path)
	for k, v in pairs(t) do
		local where = path .. "." .. tostring(k)
		ok("no function at " .. where, type(v) ~= "function")
		if type(v) == "table" then assertNoFunctions(v, where) end
	end
end
assertNoFunctions(ProfileTemplate, "template")

eq("schema version is 1", ProfileTemplate.SchemaVersion, 1)
eq("starts with 0 Fossils", ProfileTemplate.Fossils, 0)
eq("Zone 1 unlocked by default", ProfileTemplate.ZonesUnlocked.plains, true)
eq("only Zone 1 unlocked", TableUtil.Count(ProfileTemplate.ZonesUnlocked), 1)
eq("FirstJoinAt 0 marks a new player", ProfileTemplate.FirstJoinAt, 0)
ok("owned dicts start empty",
	TableUtil.IsEmpty(ProfileTemplate.Dinos)
	and TableUtil.IsEmpty(ProfileTemplate.Eggs)
	and TableUtil.IsEmpty(ProfileTemplate.Index)
	and TableUtil.IsEmpty(ProfileTemplate.Incubators))
eq("default music volume", ProfileTemplate.Settings.MusicVolume, 60)
eq("default particles", ProfileTemplate.Settings.Particles, "High")
eq("stats start at zero", ProfileTemplate.Stats.EggsStolen, 0)
eq("rarest rarity seed", ProfileTemplate.Stats.RarestRarity, "common")

-- The invariant DataService asserts at boot.
eq("template version matches migration chain",
	ProfileTemplate.SchemaVersion, Migrations.CurrentVersion())

------------------------------------------------------------------ migrations
section("Migrations - guards")

eq("empty chain -> version 1", Migrations.CurrentVersion(), 1)

local fresh = TableUtil.DeepCopy(ProfileTemplate)
local out, steps, err = Migrations.Apply(fresh)
eq("current profile needs 0 steps", steps, 0)
eq("current profile has no error", err, nil)
ok("current profile passes through", out.SchemaVersion == 1)

-- The rollback guard: a profile saved by a NEWER server must be refused, never
-- silently downgraded. Overwriting newer data with older code is the one
-- unrecoverable data bug.
local future = TableUtil.DeepCopy(ProfileTemplate)
future.SchemaVersion = 99
local _, futureSteps, futureErr = Migrations.Apply(future)
ok("future profile is refused", futureErr ~= nil)
eq("future profile applies nothing", futureSteps, 0)
ok("future error names the versions", string.find(futureErr, "99") ~= nil)

local bad = TableUtil.DeepCopy(ProfileTemplate)
bad.SchemaVersion = "1"
local _, _, badErr = Migrations.Apply(bad)
ok("non-number version is refused", badErr ~= nil)

local zero = TableUtil.DeepCopy(ProfileTemplate)
zero.SchemaVersion = 0
local _, _, zeroErr = Migrations.Apply(zero)
ok("version 0 is refused", zeroErr ~= nil)

section("Migrations - synthetic chain")

-- Install a two-step chain and verify the machinery end to end.
Migrations.Chain[1] = function(data)
	local copy = TableUtil.DeepCopy(data)
	copy.Renamed = copy.OldField
	copy.OldField = nil
	copy.SchemaVersion = 2
	return copy
end
Migrations.Chain[2] = function(data)
	local copy = TableUtil.DeepCopy(data)
	copy.Fossils = copy.Fossils * 10 -- e.g. a currency unit change
	copy.SchemaVersion = 3
	return copy
end

eq("chain of 2 -> version 3", Migrations.CurrentVersion(), 3)

local old = { SchemaVersion = 1, Fossils = 500, OldField = "carried", Dinos = { a = { x = 1 } } }
local migrated, appliedSteps, migErr = Migrations.Apply(old)
eq("applied both steps", appliedSteps, 2)
eq("no error", migErr, nil)
eq("landed on v3", migrated.SchemaVersion, 3)
eq("field renamed", migrated.Renamed, "carried")
eq("old field removed", migrated.OldField, nil)
eq("value transformed", migrated.Fossils, 5000)
ok("player content survived", migrated.Dinos.a.x == 1)

-- Purity: migrations must not touch the input.
eq("input untouched (version)", old.SchemaVersion, 1)
eq("input untouched (value)", old.Fossils, 500)
eq("input untouched (field)", old.OldField, "carried")

-- Starting mid-chain runs only the remaining steps.
local midway = { SchemaVersion = 2, Fossils = 7, Renamed = "x" }
local _, midSteps = Migrations.Apply(midway)
eq("mid-chain applies 1 step", midSteps, 1)

section("Migrations - failure modes")

-- A migration that forgets to bump SchemaVersion would loop forever. It must
-- be caught, not survived.
Migrations.Chain[2] = function(data)
	local copy = TableUtil.DeepCopy(data)
	copy.Fossils = copy.Fossils * 10
	return copy -- BUG: no SchemaVersion bump
end
local _, forgotSteps, forgotErr = Migrations.Apply({ SchemaVersion = 1, Fossils = 1, OldField = "z" })
ok("no version bump is caught", forgotErr ~= nil)
eq("stopped after the good step", forgotSteps, 1)
ok("error explains why", string.find(forgotErr, "SchemaVersion") ~= nil)

-- A throwing migration must be reported, not propagated.
Migrations.Chain[2] = function()
	error("boom")
end
local _, _, threwErr = Migrations.Apply({ SchemaVersion = 1, Fossils = 1, OldField = "z" })
ok("throwing migration is caught", threwErr ~= nil)
ok("error mentions the failure", string.find(threwErr, "boom") ~= nil)

-- A gap in the chain strands every migration past it: those profiles would
-- load claiming an old version while the code assumed the new shape. Validate()
-- is what DataService asserts at boot so this can never reach players.
ok("well-formed chain validates", Migrations.Validate() == nil)

Migrations.Chain[2] = nil
Migrations.Chain[3] = function(data)
	local copy = TableUtil.DeepCopy(data); copy.SchemaVersion = 4; return copy
end
local gapErr = Migrations.Validate()
ok("gap in the chain is caught", gapErr ~= nil)
ok("gap error names the index", gapErr ~= nil and string.find(gapErr, "3") ~= nil)
eq("length stops at the gap", Migrations.ContiguousLength(), 1)

Migrations.Chain[3] = nil
Migrations.Chain[2] = "not a function"
ok("non-function entry is caught", Migrations.Validate() ~= nil)
Migrations.Chain[2] = nil

-- Reset for the remaining sections.
Migrations.Chain[1] = nil
eq("chain reset", Migrations.CurrentVersion(), 1)
ok("empty chain validates", Migrations.Validate() == nil)

------------------------------------------------------------------ write-in-place
section("Migrations.WriteInPlace")

local live = { a = 1, b = 2, nested = { keep = true } }
local identity = live
local source = { a = 9, c = 3, nested = { keep = false, added = 1 } }
Migrations.WriteInPlace(live, source)

ok("table identity preserved", live == identity)
eq("existing key updated", live.a, 9)
eq("absent key removed", live.b, nil)
eq("new key added", live.c, 3)
eq("nested replaced", live.nested.keep, false)
eq("nested addition", live.nested.added, 1)

-- Nested tables must be copies, not shared references with the source.
source.nested.added = 999
eq("nested is a deep copy", live.nested.added, 1)

------------------------------------------------------------------ integration
section("Load path: migrate -> reconcile -> write in place")

-- A realistic old save: a real player's progress, missing everything added to
-- the schema since. This is the exact path DataService.prepareData runs.
local saved = {
	SchemaVersion = 1,
	Fossils = 125000,
	Rebirths = 3,
	Dinos = {
		aa11bb22 = { SpeciesId = "trex", Rarity = "legendary", Mutation = "golden", Stars = 2, Locked = true },
		cc33dd44 = { SpeciesId = "velociraptor", Rarity = "rare", Stars = 1 },
	},
	ZonesUnlocked = { plains = true, canyon = true, swamp = true },
	Settings = { MusicVolume = 15 }, -- they turned the music down; keep it
	Stats = { EggsStolen = 940 },
}
local liveTable = saved
local before = liveTable

local prepared, _, prepErr = Migrations.Apply(liveTable)
eq("no migration error", prepErr, nil)
local reconciled = TableUtil.Reconcile(prepared, ProfileTemplate)
Migrations.WriteInPlace(liveTable, reconciled)

ok("profile table identity preserved", liveTable == before)

for _, key in ipairs(EXPECTED) do
	ok("loaded profile has " .. key, liveTable[key] ~= nil)
end

eq("kept Fossils", liveTable.Fossils, 125000)
eq("kept Rebirths", liveTable.Rebirths, 3)
eq("kept both dinosaurs", TableUtil.Count(liveTable.Dinos), 2)
eq("kept dinosaur detail", liveTable.Dinos.aa11bb22.Mutation, "golden")
eq("kept 3 zones", TableUtil.Count(liveTable.ZonesUnlocked), 3)
eq("kept their music setting", liveTable.Settings.MusicVolume, 15)
eq("filled the missing setting", liveTable.Settings.SfxVolume, 80)
eq("kept their stat", liveTable.Stats.EggsStolen, 940)
eq("filled missing stats", liveTable.Stats.DinosFused, 0)
eq("filled new currency", liveTable.DNA, 0)
ok("filled empty owned dicts", TableUtil.IsEmpty(liveTable.Index) and TableUtil.IsEmpty(liveTable.Eggs))
ok("did not inherit template content", TableUtil.Count(liveTable.Dinos) == 2)

-- Reconcile must never mutate the shared template.
eq("template untouched: Fossils", ProfileTemplate.Fossils, 0)
eq("template untouched: Dinos", TableUtil.Count(ProfileTemplate.Dinos), 0)
eq("template untouched: MusicVolume", ProfileTemplate.Settings.MusicVolume, 60)

print(string.format("\n%s\n  %d passed, %d failed\n", string.rep("=", 46), passed, failed))
if failed > 0 then error("TESTS FAILED") end
