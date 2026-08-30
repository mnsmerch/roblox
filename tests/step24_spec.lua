--[[
	Step 24 specification.

	Polish, analytics and hardening — the last step, so this spec has two jobs.

	The first is Step 24's own work: docs/14's event catalogue asserted line by
	line, the three-custom-field limit that silently drops a fourth, the
	sampling rule, and the settings menu proven to be generated from the same
	schema the server validates against.

	The second is docs/12 §4's launch gates. Four of the nine can be decided
	offline; five need a playtest or a device. This spec decides the four and
	says plainly which five it cannot — a checklist that quietly marks
	unmeasured things green is worse than no checklist.

	Run with:  ./tests/run.sh
]]

Color3 = {
	fromHex = function(h) return { Hex = h } end,
	fromRGB = function(r, g, b) return { R = r, G = g, B = b } end,
}
typeof = type

-- Theme builds UDim and Enum values at load; the gate asserts on numbers.
UDim = { new = function(scale, offset) return { Scale = scale, Offset = offset } end }
Enum = setmetatable({}, {
	__index = function(_, group)
		return setmetatable({}, { __index = function(_, item) return group .. "." .. item end })
	end,
})

local Vector3MT = {}
Vector3MT.__index = Vector3MT
local function v3(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, Vector3MT) end
Vector3MT.__add = function(a, b) return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
Vector3MT.__sub = function(a, b) return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
Vector3MT.__mul = function(a, b)
	if type(b) == "number" then return v3(a.X * b, a.Y * b, a.Z * b) end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
Vector3MT.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
Vector3 = { new = v3, zero = v3(0, 0, 0), yAxis = v3(0, 1, 0) }
CFrame = {
	lookAt = function(from, to) return { Position = from, LookAt = to } end,
	new = function(x, y, z) return { Position = v3(x, y, z) } end,
}

local _shared = { Config = {}, Modules = {} }

--[[
	`Net` is injected here so the remote inventory can be asserted directly, and
	it is the first module in any spec that needs more than `WaitForChild` from
	a service: it reads `RunService:IsServer()` at load and requires `Log` as a
	sibling. Both are stubbed rather than the assertions being weakened to
	reading the source as text.
]]
local _services = {
	RunService = {
		IsServer = function() return true end,
		IsStudio = function() return false end,
		IsClient = function() return false end,
	},
	Players = { PlayerRemoving = { Connect = function() end } },
}
game = {
	GetService = function(_, name)
		local stub = _services[name]
		if stub then return stub end
		return { WaitForChild = function() return _shared end }
	end,
}
script = { Parent = { Log = { debug = function() end, info = function() end,
	warn = function() end, error = function() end } } }

local _realRequire = require
require = function(t) if type(t) == "table" then return t end return _realRequire(t) end

--@INJECT GameConfig=src/ReplicatedStorage/SAD_Shared/Config/GameConfig.lua RarityConfig=src/ReplicatedStorage/SAD_Shared/Config/RarityConfig.lua MutationConfig=src/ReplicatedStorage/SAD_Shared/Config/MutationConfig.lua DinoConfig=src/ReplicatedStorage/SAD_Shared/Config/DinoConfig.lua UpgradeConfig=src/ReplicatedStorage/SAD_Shared/Config/UpgradeConfig.lua RebirthConfig=src/ReplicatedStorage/SAD_Shared/Config/RebirthConfig.lua DailyConfig=src/ReplicatedStorage/SAD_Shared/Config/DailyConfig.lua ProductConfig=src/ReplicatedStorage/SAD_Shared/Config/ProductConfig.lua ZoneConfig=src/ReplicatedStorage/SAD_Shared/Config/ZoneConfig.lua ParkConfig=src/ReplicatedStorage/SAD_Shared/Config/ParkConfig.lua TutorialConfig=src/ReplicatedStorage/SAD_Shared/Config/TutorialConfig.lua AnalyticsConfig=src/ReplicatedStorage/SAD_Shared/Config/AnalyticsConfig.lua LeaderboardConfig=src/ReplicatedStorage/SAD_Shared/Config/LeaderboardConfig.lua Format=src/ReplicatedStorage/SAD_Shared/Modules/Format.lua TableUtil=src/ReplicatedStorage/SAD_Shared/Modules/TableUtil.lua@

for name, mod in pairs({ GameConfig = GameConfig, RarityConfig = RarityConfig,
	MutationConfig = MutationConfig, DinoConfig = DinoConfig, UpgradeConfig = UpgradeConfig,
	RebirthConfig = RebirthConfig, DailyConfig = DailyConfig, ProductConfig = ProductConfig,
	ZoneConfig = ZoneConfig, ParkConfig = ParkConfig, TutorialConfig = TutorialConfig,
	AnalyticsConfig = AnalyticsConfig, LeaderboardConfig = LeaderboardConfig }) do
	_shared.Config[name] = mod
end

_shared.Modules.TableUtil = TableUtil
_shared.Modules.Log = { debug = function() end, info = function() end,
	warn = function() end, error = function() end }

--@INJECT Stats=src/ReplicatedStorage/SAD_Shared/Modules/Stats.lua@
_shared.Modules.Stats = Stats

--@INJECT Economy=src/ReplicatedStorage/SAD_Shared/Modules/Economy.lua@
--@INJECT ProfileTemplate=src/ServerScriptService/SAD_Server/Services/DataService/ProfileTemplate.lua@
--@INJECT Migrations=src/ServerScriptService/SAD_Server/Services/DataService/Migrations.lua@
--@INJECT Net=src/ReplicatedStorage/SAD_Shared/Modules/Net.lua@
--@INJECT Theme=src/StarterPlayer/StarterPlayerScripts/SAD_Client/UI/Theme.lua@
--@SOURCE AnalyticsSource=src/ServerScriptService/SAD_Server/Services/AnalyticsService/init.lua@

local passed, failed = 0, 0
local function eq(label, got, want)
	if got == want then passed = passed + 1
	else failed = failed + 1; print(string.format("  FAIL %-52s got %s want %s", label, tostring(got), tostring(want))) end
end
local function near(label, got, want, tol)
	if math.abs(got - want) <= tol then passed = passed + 1
	else failed = failed + 1; print(string.format("  FAIL %-52s got %.4f want ~%.4f", label, got, want)) end
end
local function ok(label, cond)
	if cond then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. label) end
end
local function section(name) print("\n== " .. name) end

------------------------------------------------------------ the catalogue
section("docs/14 §1's event catalogue")

--[[
	Every event docs/14 names, by name. Written out rather than counted, because
	the failure this guards against is a MISSING event and a count would pass
	while the catalogue held the wrong fifty.
]]
local DOCS14 = {
	loop = { "EggStolen", "EggLost", "ChaseStarted", "ChaseEscaped", "ChaseCaught",
		"EggDeposited", "IncubationStarted", "EggHatched", "DinoPlaced", "DinoStored",
		"DinoSold", "DinoFused" },
	pvp = { "StealAttempted", "StealCompleted", "StealFailed", "PlayerRobbed",
		"RaidSurvived", "ShieldActivated", "MercyShieldTriggered", "VaultUsed",
		"RevengeMarkUsed" },
	content = { "ZoneEntered", "ServerEventStarted", "ServerEventJoined",
		"ServerEventReward", "WeatherStarted", "QuestCompleted", "DailyClaimed",
		"IndexDiscovered" },
	money = { "ShopOpened", "GamepassPromptShown", "GamepassPurchased",
		"ProductPromptShown", "ProductPurchased", "ServerBoostPurchased", "ThanksSent" },
	health = { "SessionStart", "SessionEnd", "DataLoadFailed", "DataSaveFailed",
		"SchemaMigrated", "ExploitFlag", "SuspiciousMovement", "ConfigValidationFailed",
		"FrameTimeSample", "EconomySnapshot" },
}

local expected = 0
for group, names in pairs(DOCS14) do
	for _, name in ipairs(names) do
		expected += 1
		local entry = AnalyticsConfig.Get(name)
		ok("docs/14 lists, and the catalogue holds: " .. name, entry ~= nil)
		if entry then
			eq("...in the right group: " .. name, entry.Group, group)
		end
	end
end
eq("the catalogue holds exactly docs/14's events", AnalyticsConfig.CountCustom(), expected)
print(string.format("  %d custom events across %d groups", expected, 5))

-- And nothing extra: an event the catalogue holds but docs/14 does not name is
-- one nobody agreed to collect.
do
	local named = {}
	for _, names in pairs(DOCS14) do
		for _, name in ipairs(names) do named[name] = true end
	end
	for _, name in ipairs(AnalyticsConfig.CustomOrder) do
		ok("nothing collected that docs/14 does not name: " .. name, named[name] == true)
	end
end

------------------------------------------------------- the three-field limit
section("Three custom fields. Three.")

--[[
	═══ THE SILENT ONE ═════════════════════════════════════════════════════════
	Roblox carries exactly three custom fields per event, keyed by
	`Enum.AnalyticsCustomFieldKeys`. A fourth is not an error - it is dropped,
	and the dashboard shows an event that looks complete and is missing a
	dimension nobody notices for a month.

	docs/14 lists `EggHatched` with six attributes. Something had to give, and
	the point of this section is that the giving was a decision rather than an
	accident.
	═══════════════════════════════════════════════════════════════════════════
]]
eq("the limit is three", AnalyticsConfig.MaxCustomFields, 3)
eq("and there are three keys", #AnalyticsConfig.FieldKeys, 3)

for _, name in ipairs(AnalyticsConfig.CustomOrder) do
	local entry = AnalyticsConfig.Get(name)
	ok("declares at most three fields: " .. name, #entry.Fields <= 3)
	local seen = {}
	for _, field in ipairs(entry.Fields) do
		ok(name .. " does not declare " .. field .. " twice", seen[field] == nil)
		seen[field] = true
	end
end

-- docs/14 names six attributes for EggHatched; three survive, and which three
-- is the decision worth pinning down.
do
	local hatched = AnalyticsConfig.Get("EggHatched")
	eq("EggHatched carries three", #hatched.Fields, 3)
	eq("...rarity first", hatched.Fields[1], "rarity")
	eq("...then species", hatched.Fields[2], "species")
	eq("...then the mutation, which is the reveal players chase", hatched.Fields[3], "mutation")
end

-- BuildFields must never produce a fourth key, whatever it is handed.
do
	local fields = AnalyticsConfig.BuildFields("EggHatched", {
		rarity = "epic", species = "trex", mutation = "golden",
		mutation2 = "electric", wasPrime = true, weather = "storm",
	})
	local count = 0
	for key in pairs(fields) do
		count += 1
		ok("only documented keys are used: " .. key,
			key == "CustomField01" or key == "CustomField02" or key == "CustomField03")
	end
	eq("three fields out, six in", count, 3)
	eq("values are stringified", fields.CustomField01, "epic")
end

-- An event with no declared fields must send nil, not an empty table.
eq("no fields means nil", AnalyticsConfig.BuildFields("RaidSurvived", { anything = 1 }), nil)
eq("no attributes means nil", AnalyticsConfig.BuildFields("EggHatched", nil), nil)
eq("an unknown event means nil", AnalyticsConfig.BuildFields("NotAnEvent", { a = 1 }), nil)

--[[
	═══ COVERAGE, ASSERTED AGAINST THE SERVICE'S SOURCE ════════════════════════
	`AnalyticsService.ValidateCoverage` reports any catalogue event nothing
	fires. Its first version marked an event as covered inside `emit`, which
	runs when the event ACTUALLY FIRES - so at boot it reported 22 of 46 as
	having no source, every one of which was wired correctly and had simply not
	happened yet.

	No offline spec caught that, because none of them could: the wiring lives in
	`Start`, which needs a Roblox server. So this reads the service's SOURCE and
	checks the two lists agree - crude, and the only thing here that would have
	caught it before the first Studio run did.
	═══════════════════════════════════════════════════════════════════════════
]]
section("Every catalogue event is declared by the service")

do
	local declared = {}
	for block in AnalyticsSource:gmatch("declare%\(([^)]*)%\)") do
		for name in block:gmatch('"(%w+)"') do
			declared[name] = true
		end
	end

	local missing = {}
	for _, name in ipairs(AnalyticsConfig.CustomOrder) do
		if not declared[name] then
			table.insert(missing, name)
		end
	end
	if #missing > 0 then
		table.sort(missing)
		print("  events with no declare(): " .. table.concat(missing, ", "))
	end
	eq("every catalogue event has a source", #missing, 0)

	local extra = {}
	for name in pairs(declared) do
		if not AnalyticsConfig.Get(name) then
			table.insert(extra, name)
		end
	end
	if #extra > 0 then
		table.sort(extra)
		print("  declared but not in the catalogue: " .. table.concat(extra, ", "))
	end
	eq("nothing is declared that the catalogue does not hold", #extra, 0)

	print(string.format("  %d catalogue events, all declared at subscription time",
		AnalyticsConfig.CountCustom()))
end

--------------------------------------------------------------- the funnel
section("The onboarding funnel (docs/14's most valuable number)")

eq("ten steps", #AnalyticsConfig.Onboarding, 10)

local FUNNEL = { "TutorialStarted", "TutorialReachedZone", "TutorialEggStolen",
	"TutorialEscaped", "TutorialEggDeposited", "TutorialHatched", "TutorialDinoPlaced",
	"TutorialIncomeCollected", "TutorialUpgradeBought", "TutorialCompleted" }
for step, name in ipairs(FUNNEL) do
	local entry = AnalyticsConfig.Onboarding[step]
	eq(string.format("step %d is %s", step, name), entry.Name, name)
	eq("...numbered to match", entry.Step, step)
end

--[[
	Ten funnel steps against twelve tutorial beats. Every step must map to a
	beat that EXISTS, or the funnel has a step nothing can ever fire and the
	drop-off report shows a cliff that is not real.
]]
for _, entry in ipairs(AnalyticsConfig.Onboarding) do
	ok(entry.Name .. " maps to a real beat",
		entry.Beat >= 1 and entry.Beat <= TutorialConfig.StepCount)
	ok("...and the beat exists", TutorialConfig.Get(entry.Beat) ~= nil)
end

-- Beats must map forward: a funnel that can go backwards is not a funnel.
do
	local previous = 0
	for _, entry in ipairs(AnalyticsConfig.Onboarding) do
		ok("the funnel moves forward at " .. entry.Name, entry.Beat > previous)
		previous = entry.Beat
	end
end

-- And two funnel steps cannot share a beat, or one of them never fires.
do
	local seen = {}
	for _, entry in ipairs(AnalyticsConfig.Onboarding) do
		ok("one funnel step per beat: " .. entry.Name, seen[entry.Beat] == nil)
		seen[entry.Beat] = true
	end
	local unmapped = {}
	for step = 1, TutorialConfig.StepCount do
		if not seen[step] then table.insert(unmapped, step) end
	end
	print(string.format("  beats with no funnel step: %s (reading beats, deliberately)",
		table.concat(unmapped, ", ")))
end

------------------------------------------------------------- economy tags
section("Every Fossil flow is tagged (docs/14 §1)")

local TAGS = { "income_collect", "income_offline", "quest", "daily", "event", "sell",
	"upgrade", "defence", "zone_unlock", "reroll", "fuse", "auction", "robux_pack",
	"insurance", "rebirth_reset" }
for _, tag in ipairs(TAGS) do
	ok("docs/14's tag exists: " .. tag, AnalyticsConfig.IsSink(tag) ~= nil)
end
eq("fifteen tags, no more", (function()
	local n = 0
	for _ in pairs(AnalyticsConfig.EconomyTags) do n += 1 end
	return n
end)(), #TAGS)

-- Direction matters: a sink logged as a source doubles apparent income on
-- every economy report built from this.
ok("collecting income is a source", AnalyticsConfig.IsSink("income_collect") == false)
ok("buying an upgrade is a sink", AnalyticsConfig.IsSink("upgrade") == true)
ok("a rebirth reset is a sink", AnalyticsConfig.IsSink("rebirth_reset") == true)
ok("a Robux pack is a source", AnalyticsConfig.IsSink("robux_pack") == false)
eq("an untagged flow is refused, not bucketed", AnalyticsConfig.IsSink("mystery"), nil)

----------------------------------------------------------------- sampling
section("Sampling (docs/14 §4)")

near("10%", AnalyticsConfig.SampleRate, 0.10, 0.0001)

--[[
	docs/14: the two heavy events are sampled, "high-frequency loop events are
	logged in full - they're the core dataset". Asserted in both directions.
]]
for _, name in ipairs({ "FrameTimeSample", "EconomySnapshot" }) do
	ok(name .. " is sampled", AnalyticsConfig.Get(name).Sampled == true)
end
for _, name in ipairs({ "EggStolen", "EggHatched", "ChaseEscaped", "SessionStart" }) do
	ok(name .. " is logged in full", AnalyticsConfig.Get(name).Sampled == false)
	ok("...for every player", AnalyticsConfig.IsSampled(12345, name))
end

--[[
	Sampling is keyed on the USER ID, not rolled per event. A per-event roll
	would give 10% of everybody's snapshots, which cannot be joined into a
	per-player series - and a series is the whole point of EconomySnapshot.
]]
do
	local sampled, total = 0, 20000
	for userId = 1, total do
		if AnalyticsConfig.IsSampled(userId, "EconomySnapshot") then
			sampled += 1
		end
	end
	local rate = sampled / total
	print(string.format("  %d of %d players sampled (%.1f%%, want ~10%%)", sampled, total, rate * 100))
	near("the sample lands near 10%", rate, 0.10, 0.005)

	-- The same player must give the same answer every time, or the series has
	-- holes in it.
	local first = AnalyticsConfig.IsSampled(4242, "EconomySnapshot")
	local stable = true
	for _ = 1, 100 do
		if AnalyticsConfig.IsSampled(4242, "EconomySnapshot") ~= first then
			stable = false
		end
	end
	ok("a sampled player stays sampled", stable)
end

------------------------------------------------------- the settings menu
section("The settings menu is generated from the schema the server validates")

--[[
	═══ WHY THIS IS AN ASSERTION AND NOT A CODE REVIEW ═════════════════════════
	A hand-written menu and a server-side schema drift the first time a setting
	is added: the menu shows a control for a key the server drops, or hides one
	the schema accepts. Both are silent.

	`SettingsController` builds every row from `GameConfig.SettingsSchema`, and
	what is asserted here is the schema itself - that every key has a type the
	menu knows how to render, and that every rendered type is one the server
	validates.
	═══════════════════════════════════════════════════════════════════════════
]]
local RENDERABLE = { boolean = true, number = true, string = true }
local settingCount = 0
for key, schema in pairs(GameConfig.SettingsSchema) do
	settingCount += 1
	ok("has a type the menu can render: " .. key, RENDERABLE[schema.Type] == true)
	if schema.Type == "number" then
		ok(key .. " has bounds, or the stepper is unbounded",
			schema.Min ~= nil and schema.Max ~= nil)
		ok(key .. "'s bounds are the right way round", schema.Min < schema.Max)
	end
	if schema.Type == "string" then
		ok(key .. " has options, or the cycler has nothing to cycle",
			type(schema.OneOf) == "table" and #schema.OneOf > 0)
	end
end
print(string.format("  %d settings, all renderable", settingCount))

--[[
	The schema and the profile template must hold the same keys. A schema key
	with no default is a control that reads nil; a default with no schema entry
	is a setting the server refuses to write.
]]
for key in pairs(GameConfig.SettingsSchema) do
	ok("the template has a default for " .. key, ProfileTemplate.Settings[key] ~= nil)
end
for key in pairs(ProfileTemplate.Settings) do
	ok("the schema validates " .. key, GameConfig.SettingsSchema[key] ~= nil)
end

-- Defaults must satisfy their own schema, or a fresh profile is invalid.
for key, schema in pairs(GameConfig.SettingsSchema) do
	local default = ProfileTemplate.Settings[key]
	eq("the default's type matches the schema: " .. key, type(default), schema.Type)
	if schema.Type == "number" then
		ok(key .. "'s default is in range", default >= schema.Min and default <= schema.Max)
	elseif schema.Type == "string" then
		local found = false
		for _, option in ipairs(schema.OneOf) do
			if option == default then found = true end
		end
		ok(key .. "'s default is one of its options", found)
	end
end

---------------------------------------------------------- the launch gates
section("docs/12 §4's launch gates")

eq("nine gates", #AnalyticsConfig.LaunchGates, 9)

--[[
	Four can be decided here; five need a playtest, a device or a soak. Saying
	which is which is the honest half of a checklist - one that quietly marks
	unmeasured things green is worse than no checklist at all.
]]
local offline, live = 0, 0
for _, gate in ipairs(AnalyticsConfig.LaunchGates) do
	if gate.Offline then offline += 1 else live += 1 end
	ok("the gate names its threshold: " .. gate.Id, type(gate.Threshold) == "string")
end
print(string.format("  %d gates decidable offline, %d need a playtest or a device", offline, live))
eq("four are decidable here", offline, 4)

--- GATE: save/load round-trip across all migrations.
do
	local problem = Migrations.Validate()
	eq("the migration chain is contiguous and valid", problem, nil)

	local version = Migrations.CurrentVersion()
	ok("the template declares the current version", ProfileTemplate.SchemaVersion == version)
	print(string.format("  save/load: schema v%d, %d migration(s) in the chain",
		version, Migrations.ContiguousLength()))

	--[[
		Round-trip: an old save through the whole chain must come out valid.
		Driven for every version the chain knows about, not just the newest,
		because the gate says "across all migrations".
	]]
	for from = 0, version - 1 do
		local old = { SchemaVersion = from, Fossils = 500 }
		local migrated = true
		for step = from + 1, version do
			local fn = Migrations.Chain[step]
			if fn then
				local okCall = pcall(fn, old)
				if not okCall then migrated = false end
			end
		end
		ok(string.format("a v%d save migrates to v%d without throwing", from, version), migrated)
	end
end

--- GATE: economy day-1 curve within ±20% of docs/05 §8.
do
	--[[
		docs/05 §8's published rows. The check that matters is REACHABILITY -
		that some park a player could plausibly hold at that timestamp produces
		the number the document prints. `step12_spec` proves this in detail; the
		gate needs the verdict, so it is restated here as a gate rather than
		re-derived.
	]]
	local function parkOf(speciesId, count, rarity)
		local data = { Upgrades = {}, Defences = {}, Dinos = {}, Eggs = {}, Index = {},
			Gamepasses = {}, Boosts = {}, Rebirths = 0, Fossils = 0,
			Stats = { RarestRarity = "common" } }
		for index = 1, count do
			data.Dinos["d" .. index] = {
				SpeciesId = speciesId, Rarity = rarity, Stars = 0, Placed = true,
			}
		end
		return data
	end

	local ROWS = { { mins = 5, want = 6 }, { mins = 20, want = 45 }, { mins = 60, want = 380 } }
	local reachable = 0
	for _, row in ipairs(ROWS) do
		--[[
			Search for a plausible park that lands within 20%: any count of one
			species at any rarity a player could hold by then.

			The space is what an hour of play can produce - docs/06 §5's slot
			track reaches sixteen placements inside an hour. The 60-minute row
			is not reachable at all without Epics, which is itself worth
			knowing: docs/05 §8's hour is an hour in which a Rare has stopped
			being the best thing you own.
		]]
		local best, bestErr = nil, math.huge
		for _, rarity in ipairs({ "common", "uncommon", "rare", "epic" }) do
			for count = 1, 16 do
				local rate = Economy.ParkIncomeRate(parkOf("dryosaurus", count, rarity))
				local err = math.abs(rate - row.want) / row.want
				if err < bestErr then
					best, bestErr = { rate = rate, count = count, rarity = rarity }, err
				end
			end
		end
		local within = bestErr <= 0.20
		if within then reachable += 1 end
		print(string.format("  economy: docs/05's %2d-min row (%d F/s) reachable with %d %s (%.0f F/s, %.0f%% off)",
			row.mins, row.want, best.count, best.rarity, best.rate, bestErr * 100))
		ok(string.format("the %d-minute row is reachable within 20%%", row.mins), within)
	end
	eq("all three published rows are reachable", reachable, #ROWS)
end

--- GATE: mobile UI, every action one-thumbed on a 5.5".
do
	--[[
		`step5_spec` proves the 64px touch-target guarantee across twelve real
		viewports. The gate's other half is REACH: on a 5.5" phone held in one
		hand, the controls a player uses constantly must be in the bottom
		portion of the screen, not the top.
	]]
	local phoneHeight = 640 -- logical pixels, a 5.5" phone in landscape
	local thumbReach = phoneHeight * 0.45 -- the bottom 45%, generously

	local bottomBar = Theme.Size.BottomBarHeight
	ok("the bottom bar is inside thumb reach", bottomBar <= thumbReach)

	--[[
		And the action prompt - the button used for every steal in the game -
		sits above the bottom bar, so it has to be inside reach too.
	]]
	local promptTop = bottomBar + Theme.Size.MinTouchTarget
	print(string.format("  mobile: bottom bar %dpx, action prompt reaches %dpx; thumb reach is %dpx",
		bottomBar, promptTop, thumbReach))
	ok("the action prompt is inside thumb reach", promptTop <= thumbReach)

	--[[
		And the guarantee `step5_spec` proves across twelve viewports, restated
		here as the gate: a bottom-bar button is never below 64 real pixels.
	]]
	eq("the touch-target floor is 64px", Theme.Size.MinTouchTarget, 64)
end

--- GATE: no unfiltered user text anywhere.
do
	--[[
		The gate is about what the game DISPLAYS. V1 ships no player-authored
		text at all: no park naming (V1.4), no trading messages (V1.5), no
		custom nametags. The only player-derived strings shown are Roblox
		DISPLAY NAMES, which Roblox filters at the source.

		Asserted as a property of the shipped feature set rather than as a code
		scan, and re-checked the day park naming ships - which is what the
		comment in docs/12 §4 is for.
	]]
	ok("park naming is not in V1", ParkConfig.AllowCustomNames ~= true)
	ok("trading is not in V1", GameConfig.TradingEnabled ~= true)
end

------------------------------------------------------- the exploit surface
section("The exploit sweep has something to sweep")

--[[
	`DebugExploitClient` fires every client->server remote. What can be checked
	here is that the inventory it sweeps is complete and that no remote has
	quietly appeared without an argument contract - an `args`-less remote is one
	`Net` cannot validate, and validation is the first of the five layers.
]]
local c2s, s2c = 0, 0
for name, definition in pairs(Net.Events) do
	if definition.dir == "c2s" then
		c2s += 1
		ok("declares an argument contract: " .. name, type(definition.args) == "table")
		ok("declares a rate limit: " .. name,
			type(definition.rate) == "number" and definition.rate > 0)
		ok("declares a burst: " .. name,
			type(definition.burst) == "number" and definition.burst >= 1)
		--[[
			A burst below the rate would make the limiter tighter than its own
			published figure, which is a silent throttle on legitimate play.
		]]
		ok("burst is at least the rate: " .. name, definition.burst >= definition.rate)
	else
		s2c += 1
	end
end
print(string.format("  %d client->server remotes to sweep, %d server->client", c2s, s2c))

--[[
	Every RemoteFunction must be read-only by Net's own rule, which cannot be
	asserted from here - but its rate limit can, and a function is the one thing
	a client can make the server YIELD on.
]]
for name, definition in pairs(Net.Functions) do
	ok("the function is rate-limited: " .. name,
		type(definition.rate) == "number" and definition.rate > 0)
end

print("\n==============================================")
print(string.format("  %d passed, %d failed", passed, failed))
if failed > 0 then error("TESTS FAILED", 0) end
