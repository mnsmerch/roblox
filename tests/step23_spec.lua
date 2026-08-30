--[[
	Step 23 specification.

	The tutorial. docs/13 names one hazard and it is not a bug, it is a shape:
	"the tutorial fighting the real systems (it must DRIVE them, never bypass
	them)."

	That is testable. Each of the four bends is a pure function of the profile,
	so the spec can prove each one is a NO-OP for everybody who is not mid-
	tutorial - which is the difference between a modifier and a fork.

	The other half is the advance check, driven as a state machine: every beat
	refused without its condition, every beat allowed with it, and the two ways
	a client would try to cheat (jump ahead, replay) refused.

	Run with:  ./tests/run.sh
]]

Color3 = { fromHex = function(h) return { Hex = h } end }
typeof = type

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

-- ZoneConfig.OriginOf builds a CFrame; only its position is measured here.
CFrame = {
	lookAt = function(from, to) return { Position = from, LookAt = to } end,
	new = function(x, y, z) return { Position = v3(x, y, z) } end,
}

local _shared = { Config = {}, Modules = {} }
game = { GetService = function(_, _n) return { WaitForChild = function() return _shared end } end }
local _realRequire = require
require = function(t) if type(t) == "table" then return t end return _realRequire(t) end

--@INJECT GameConfig=src/ReplicatedStorage/SAD_Shared/Config/GameConfig.lua RarityConfig=src/ReplicatedStorage/SAD_Shared/Config/RarityConfig.lua MutationConfig=src/ReplicatedStorage/SAD_Shared/Config/MutationConfig.lua DinoConfig=src/ReplicatedStorage/SAD_Shared/Config/DinoConfig.lua UpgradeConfig=src/ReplicatedStorage/SAD_Shared/Config/UpgradeConfig.lua RebirthConfig=src/ReplicatedStorage/SAD_Shared/Config/RebirthConfig.lua DailyConfig=src/ReplicatedStorage/SAD_Shared/Config/DailyConfig.lua ProductConfig=src/ReplicatedStorage/SAD_Shared/Config/ProductConfig.lua ZoneConfig=src/ReplicatedStorage/SAD_Shared/Config/ZoneConfig.lua ParkConfig=src/ReplicatedStorage/SAD_Shared/Config/ParkConfig.lua ChaseConfig=src/ReplicatedStorage/SAD_Shared/Config/ChaseConfig.lua TutorialConfig=src/ReplicatedStorage/SAD_Shared/Config/TutorialConfig.lua Format=src/ReplicatedStorage/SAD_Shared/Modules/Format.lua@

for name, mod in pairs({ GameConfig = GameConfig, RarityConfig = RarityConfig,
	MutationConfig = MutationConfig, DinoConfig = DinoConfig, UpgradeConfig = UpgradeConfig,
	RebirthConfig = RebirthConfig, DailyConfig = DailyConfig, ProductConfig = ProductConfig,
	ZoneConfig = ZoneConfig, ParkConfig = ParkConfig, ChaseConfig = ChaseConfig,
	TutorialConfig = TutorialConfig }) do
	_shared.Config[name] = mod
end

--@INJECT Stats=src/ReplicatedStorage/SAD_Shared/Modules/Stats.lua@
_shared.Modules.Stats = Stats

--@INJECT Economy=src/ReplicatedStorage/SAD_Shared/Modules/Economy.lua@

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

--- A profile mid-tutorial at `step`, or finished if `step` is nil.
local function profile(overrides)
	local data = { Upgrades = {}, Defences = {}, Dinos = {}, Eggs = {}, Index = {},
		Incubators = {}, Gamepasses = {}, Boosts = {}, Items = {}, Rebirths = 0,
		Fossils = 0, DNA = 0, LuckNodes = 0, BonusDinoSlots = 0, BonusVaultSlots = 0,
		ProcessedReceipts = {}, RobuxSpent = 0, LastSeen = 0, BankedFossils = 0,
		BankedAt = 0, BankedRate = 0,
		Tutorial = { Step = 1, Completed = false, SkippedAt = nil },
		Stats = { RarestRarity = "common" } }
	for k, v in pairs(overrides or {}) do data[k] = v end
	return data
end

local function atStep(n)
	return profile({ Tutorial = { Step = n, Completed = false, SkippedAt = nil } })
end

local function graduated()
	return profile({ Tutorial = { Step = 12, Completed = true, SkippedAt = nil } })
end

------------------------------------------------------------------ the beats
section("docs/00 §3's twelve beats")

eq("twelve beats", TutorialConfig.StepCount, 12)

--[[
	docs/00 §3's table, by what each beat teaches. Asserted by id and order so a
	reshuffle has to be deliberate - the FTUE's whole job is that the reveals
	land in the order the design chose.
]]
local ORDER = { "park", "leave", "findEgg", "takeEgg", "run", "safe",
	"incubate", "hatch", "place", "collect", "upgrade", "farewell" }
for index, id in ipairs(ORDER) do
	local beat = TutorialConfig.Get(index)
	eq(string.format("beat %d is %s", index, id), beat and beat.Id, id)
	eq(string.format("...and knows its own number", index), beat.Step, index)
end

-- docs/00 §3: "speaks in <= 8-word speech bubbles" and "Total forced reading:
-- under 60 words". Both are asserted at require time; measured here.
local longest, longestText = 0, ""
for _, beat in ipairs(TutorialConfig.Beats) do
	local words = select(2, beat.Text:gsub("%S+", ""))
	if words > longest then longest, longestText = words, beat.Text end
	ok("<= 8 words: " .. beat.Id, words <= 8)
	ok("has an objective line: " .. beat.Id, type(beat.Objective) == "string")
	ok("teaches something named: " .. beat.Id, type(beat.Teaches) == "string")
end
print(string.format("  %d words in total, longest bubble %d words (%s)",
	TutorialConfig.TotalWords, longest, longestText))
ok("under 60 words of forced reading", TutorialConfig.TotalWords < 60)

--[[
	docs/00 §3: Rok "disappears permanently after step 10", and beat 11 is the
	one menu the FTUE opens. He must leave BEFORE it, or he is standing in
	front of the board the player is being asked to read.
]]
eq("Rok leaves after step 10", TutorialConfig.RokLeavesAfterStep, 10)
ok("...which is before the upgrade beat", TutorialConfig.RokLeavesAfterStep < 11)
ok("the upgrade beat is the one that opens a menu",
	TutorialConfig.Get(11).OpensShop == true)

-- docs/00 §3's rule: "No menu is opened for the player during the FTUE except
-- the upgrade board." Exactly one beat may set OpensShop.
local opens = 0
for _, beat in ipairs(TutorialConfig.Beats) do
	if beat.OpensShop then opens += 1 end
end
eq("exactly one beat opens a menu", opens, 1)

-- docs/08 §6's two timeouts.
eq("hint at 25 seconds", TutorialConfig.HintAfterSecs, 25)
eq("auto-advance at 60 seconds", TutorialConfig.AutoAdvanceAfterSecs, 60)
ok("the hint arrives before the auto-advance",
	TutorialConfig.HintAfterSecs < TutorialConfig.AutoAdvanceAfterSecs)

------------------------------------------------- the four bends are no-ops
section("Every bend is a no-op for everybody past the tutorial")

--[[
	═══ THE WHOLE POINT OF THIS SECTION ════════════════════════════════════════
	docs/13: the tutorial "must DRIVE them, never bypass them". A bend that
	leaks past the tutorial is not a tutorial any more - it is a permanent
	change to the game wearing a tutorial's name.

	So each of the four is asserted nil/zero for a graduate, for a skipper, and
	for a profile that has no tutorial state at all.
	═══════════════════════════════════════════════════════════════════════════
]]
local skipped = profile({ Tutorial = { Step = 4, Completed = false, SkippedAt = 1000 } })

--[[
	A profile with NO tutorial table at all - an old save from before the field
	existed, reaching a server mid-Reconcile. Built by deleting the key rather
	than passing nil in the overrides, because `pairs` skips a nil value and the
	first version of this fixture was quietly a step-1 profile that passed
	nothing it claimed to.
]]
local stateless = profile()
stateless.Tutorial = nil

for label, data in pairs({ graduate = graduated(), skipper = skipped, stateless = stateless }) do
	eq("no forced rarity for a " .. label, TutorialConfig.ForcedRarity(data), nil)
	eq("no forced hatch for a " .. label, TutorialConfig.ForcedHatchSecs(data), nil)
	eq("no chase cap for a " .. label, TutorialConfig.ChaseSpeedCap(data, 20), nil)
	eq("no top-up for a " .. label, TutorialConfig.TopUpFor(data, 800), 0)
	eq("not active: " .. label, TutorialConfig.IsActive(data), false)
end

-- And nil data must not throw. The write loop can race a leaving player.
for _, fn in ipairs({ "ForcedRarity", "ForcedHatchSecs", "IsActive" }) do
	local called = pcall(TutorialConfig[fn], nil)
	ok("survives a nil profile: " .. fn, called)
end
ok("survives a nil profile: ChaseSpeedCap", pcall(TutorialConfig.ChaseSpeedCap, nil, 20))
eq("no top-up without a profile", TutorialConfig.TopUpFor(nil, 800), 0)

--------------------------------------------------------------- bend by bend
section("Beat 4: the first egg is always Common (Reveal #1)")

eq("forced on beat 1", TutorialConfig.ForcedRarity(atStep(1)), "common")
eq("forced on beat 4", TutorialConfig.ForcedRarity(atStep(4)), "common")

--[[
	And released the moment the beat is behind them. A tutorial that kept
	forcing Common would be a player whose second egg is also Common, which is
	the odds not working rather than the tutorial working.
]]
eq("released on beat 5", TutorialConfig.ForcedRarity(atStep(5)), nil)
for step = 5, 12 do
	eq(string.format("still released at beat %d", step), TutorialConfig.ForcedRarity(atStep(step)), nil)
end
ok("and the forced rarity is one that exists",
	RarityConfig.Tiers[TutorialConfig.ForcedFirstRarity] ~= nil)
eq("...and it is the bottom tier, so nothing is given away",
	RarityConfig.RankOf(TutorialConfig.ForcedFirstRarity), 1)

section("Beat 8: the tutorial egg hatches in ten seconds")

eq("ten seconds", TutorialConfig.HatchSecs, 10)
eq("forced on beat 8", TutorialConfig.ForcedHatchSecs(atStep(8)), 10)
eq("released on beat 9", TutorialConfig.ForcedHatchSecs(atStep(9)), nil)

--[[
	Ten seconds has to be FASTER than the real Common time, or the "forced" ten
	seconds is a punishment. Measured against the real ladder.
]]
local commonSecs = RarityConfig.Tiers.common.IncubationSecs
print(string.format("  a real Common takes %ds; the tutorial's takes %d",
	commonSecs, TutorialConfig.HatchSecs))
ok("the forced hatch is faster than the real one", TutorialConfig.HatchSecs < commonSecs)

section("Beat 5: the first chase cannot be lost")

--[[
	docs/00 §3: "The guardian's speed is capped below the player's."
	A cap, not a speed - so it can only ever make a chase easier.
]]
local THIEF = 20
local cap = TutorialConfig.ChaseSpeedCap(atStep(5), THIEF)
ok("there is a cap on beat 5", cap ~= nil)
ok("...and it is below the thief's own speed", cap < THIEF)
print(string.format("  a thief at %.0f is chased at no more than %.1f (%.0f%%)",
	THIEF, cap, cap / THIEF * 100))

--[[
	Every archetype, capped, against the thief. This is the assertion that makes
	"unlosable" a fact rather than a hope: the fastest guardian in the game must
	still be slower than a player standing still on beat 5.
]]
local fastest, fastestId = 0, ""
for id, archetype in pairs(ChaseConfig.Archetypes) do
	local real = ChaseConfig.SpeedFor(id, THIEF, 0)
	local capped = math.min(real, TutorialConfig.ChaseSpeedCap(atStep(5), THIEF))
	if real > fastest then fastest, fastestId = real, id end
	ok("capped below the thief: " .. id, capped < THIEF)
	ok("...and never sped UP by the cap: " .. id, capped <= real)
end
print(string.format("  the fastest archetype (%s) runs at %.1f uncapped", fastestId, fastest))
ok("...which would have caught the player without the cap", fastest > THIEF)

-- The cap covers beat 5 AND beat 6, because the chase does not end at the beat
-- boundary - the run home is the same chase.
ok("the cap covers the run home too", TutorialConfig.ChaseSpeedCap(atStep(6), THIEF) ~= nil)
eq("and is gone by the incubator beat", TutorialConfig.ChaseSpeedCap(atStep(7), THIEF), nil)

section("Beat 11: the first upgrade is exactly affordable")

--[[
	docs/00's beat 10 shows "+120 Fossils!" and beat 11 says the upgrade "costs
	exactly what you now have". The cheapest track is 800, so those two cannot
	both be literally true - the top-up is what makes the second one true.
]]
local FIRST = TutorialConfig.FirstUpgradeId
local cost = UpgradeConfig.CostOf(FIRST, 1)
print(string.format("  the highlighted upgrade (%s) costs %d", FIRST, cost))

-- It has to be the cheapest thing in the game, or a cheaper one is sitting
-- next to it unhighlighted and the player buys that instead.
for id in pairs(UpgradeConfig.Tracks) do
	ok("no track is cheaper than the highlighted one: " .. id,
		UpgradeConfig.CostOf(id, 1) >= cost)
end

local broke = atStep(11)
eq("a player with nothing is topped up to the price",
	TutorialConfig.TopUpFor(broke, cost), cost)

local partway = atStep(11)
partway.Fossils = 700
eq("a player with 700 is topped up by 100", TutorialConfig.TopUpFor(partway, cost), 100)

local rich = atStep(11)
rich.Fossils = 5000
eq("a player who is already rich is not topped up",
	TutorialConfig.TopUpFor(rich, cost), 0)
ok("...and is certainly never taken down to the price",
	TutorialConfig.TopUpFor(rich, cost) >= 0)

-- Paid on entering beat 11 and not before: a beat-3 player with 800 Fossils
-- would otherwise be a beat-3 player who can buy the upgrade early.
eq("nothing before beat 10", TutorialConfig.TopUpFor(atStep(9), cost), 0)
ok("paid from beat 10", TutorialConfig.TopUpFor(atStep(10), cost) > 0)

----------------------------------------------------------- the advance check
section("The server owns the step number")

--[[
	═══ MODELLED AS THE STATE MACHINE IT IS ════════════════════════════════════
	`RequestTutorialStep` carries a number and nothing else. Everything below
	drives `CanAdvance` directly, which is the function the remote handler
	calls - so what is asserted here is what a modified client actually meets.
	═══════════════════════════════════════════════════════════════════════════
]]
local ALL_FACTS = { inZone = true, carrying = true, chased = true, home = true,
	incubating = true, hatched = true, placed = true, collected = true, upgraded = true }

-- Every beat advances when its own condition is met.
for step = 1, TutorialConfig.StepCount - 1 do
	local allowed = TutorialConfig.CanAdvance(atStep(step), step + 1, ALL_FACTS)
	ok(string.format("beat %d advances with its condition met", step), allowed)
end

-- And every beat that HAS a condition refuses without it.
local gated = 0
for step = 1, TutorialConfig.StepCount - 1 do
	local beat = TutorialConfig.Get(step)
	if beat.Requires ~= "none" then
		gated += 1
		local allowed, reason = TutorialConfig.CanAdvance(atStep(step), step + 1, {})
		ok(string.format("beat %d refuses without '%s'", step, beat.Requires), not allowed)
		ok("...and says which one", (reason or ""):find(beat.Requires) ~= nil)
	end
end
print(string.format("  %d of %d beats are gated on real state",
	gated, TutorialConfig.StepCount - 1))
ok("most of the tutorial is gated, not on a timer", gated >= 7)

--[[
	The condition belongs to the beat being LEFT, not the one being entered.
	Getting that backwards means beat 4 (take the egg) is gated on whether a
	chase has started - which happens after.
]]
do
	local takeEgg = 4
	local onlyCarrying = { carrying = true }
	ok("leaving beat 4 needs the egg in hand",
		TutorialConfig.CanAdvance(atStep(takeEgg), takeEgg + 1, onlyCarrying))
	ok("...and not the chase that follows it",
		TutorialConfig.CanAdvance(atStep(takeEgg), takeEgg + 1, { chased = true }) == false)
end

------------------------------------------------------------- the two cheats
section("The two ways a client would cheat")

--[[
	Cheat 1: ask for the last step. `Tutorial.Completed` is the metric docs/00
	targets at >80%, and beat 11 pays a Fossil top-up, so a jump is both free
	money and a corrupted number.
]]
for _, jump in ipairs({ 3, 5, 11, 12 }) do
	local allowed, reason = TutorialConfig.CanAdvance(atStep(1), jump, ALL_FACTS)
	ok(string.format("cannot jump from 1 to %d", jump), not allowed)
	eq("...and is told why", reason, "not the next step")
end

-- Cheat 2: replay a step you already passed, to collect its grant twice.
local allowedBack, backReason = TutorialConfig.CanAdvance(atStep(6), 6, ALL_FACTS)
ok("cannot re-ask for the step you are on", not allowedBack)
eq("...same reason", backReason, "not the next step")
ok("cannot go backwards", not TutorialConfig.CanAdvance(atStep(6), 3, ALL_FACTS))

-- Past the end.
ok("cannot advance past the last beat",
	not TutorialConfig.CanAdvance(atStep(12), 13, ALL_FACTS))

-- And a finished tutorial cannot be restarted into, which would re-arm every
-- bend above for a player who has already graduated.
do
	local done = graduated()
	local allowed, reason = TutorialConfig.CanAdvance(done, 1, ALL_FACTS)
	ok("a graduate cannot re-enter", not allowed)
	eq("...and is told why", reason, "already finished")

	local skipper = profile({ Tutorial = { Step = 4, Completed = false, SkippedAt = 99 } })
	local allowedSkip, skipReason = TutorialConfig.CanAdvance(skipper, 5, ALL_FACTS)
	ok("a skipper cannot re-enter", not allowedSkip)
	eq("...and is told why", skipReason, "skipped")
end

--------------------------------------------------------------- no deadlocks
section("No beat can deadlock")

--[[
	A beat requiring something the server never computes would sit there until
	the auto-advance asked forever and was refused forever. This is the same
	coverage discipline the replication allowlist and RebirthConfig's three
	lists use, and `TutorialService.ValidateFacts` asserts it at boot.
]]
local KNOWN = { inZone = true, carrying = true, chased = true, home = true,
	incubating = true, hatched = true, placed = true, collected = true, upgraded = true }
local complete, problem = TutorialConfig.ValidateRequirements(KNOWN)
ok("every requirement is one the server computes", complete)
eq("...with no problem to report", problem, nil)

-- Driven to a real failure, so the guard is proven to work rather than assumed.
do
	local missing = {}
	for key in pairs(KNOWN) do missing[key] = true end
	missing.carrying = nil
	local passes, why = TutorialConfig.ValidateRequirements(missing)
	ok("a missing fact is caught", not passes)
	ok("...and the message names the beat and the fact",
		(why or ""):find("carrying") ~= nil and (why or ""):find("deadlock") ~= nil)
end

------------------------------------------------------------------- the walk
section("The distances docs/00 §3 asks a new player to walk")

--[[
	docs/00 beat 2: "Arrow points out the gate to Jurassic Plains (25 studs
	away)". The blockout says otherwise, and the number matters because the
	FTUE budgets 15 seconds for that walk.
]]
local plotCentre = ParkConfig.RingRadius()
local zoneEdge = ZoneConfig.RingRadius - ZoneConfig.ZoneSize * 0.5

--[[
	Worst case: a park directly opposite zone 1. Best case: a park on the same
	spoke. Both are measured because a player does not choose their plot.
]]
local best = math.abs(zoneEdge - plotCentre)
local worst = zoneEdge + plotCentre

local walkSpeed = GameConfig.BaseWalkSpeed
print(string.format("  park ring %.0f, zone 1 edge %.0f", plotCentre, zoneEdge))
print(string.format("  nearest park: %.0f studs (%.0fs at %d walkspeed)",
	best, best / walkSpeed, walkSpeed))
print(string.format("  furthest park: %.0f studs (%.0fs)", worst, worst / walkSpeed))

ok("beat 2 is not 25 studs, whatever docs/00 says", best > 25)

--[[
	Which is why plots are claimed nearest-the-free-zone-first rather than in
	index order. Measured across every plot in claim order: the walk a player
	actually gets, by how many people are already on the server.
]]
do
	local firstZone = ZoneConfig.Zones[ZoneConfig.Order[1]]
	local order = ParkConfig.PlotSearchOrder(firstZone.RingSlot, ZoneConfig.SlotCount)
	eq("every plot is still claimable", #order, ParkConfig.PlotCount)

	local seen = {}
	for _, index in ipairs(order) do
		ok("claim order lists plot " .. index .. " once", seen[index] == nil)
		seen[index] = true
	end

	local function walkFor(plotIndex)
		local angle = (plotIndex - 1) / ParkConfig.PlotCount * math.pi * 2
		local px, pz = math.cos(angle) * plotCentre, math.sin(angle) * plotCentre
		local zoneAngle = (firstZone.RingSlot - 1) / ZoneConfig.SlotCount * math.pi * 2
		local zx, zz = math.cos(zoneAngle) * zoneEdge, math.sin(zoneAngle) * zoneEdge
		return math.sqrt((px - zx) ^ 2 + (pz - zz) ^ 2)
	end

	local sorted, unsorted = walkFor(order[1]), walkFor(1)
	ok("the first plot handed out is the closest one to the free zone",
		sorted <= unsorted + 1e-6)

	--[[
		Zone 1 and plot 1 happen to share a ring angle, so the FIRST player is
		unaffected. The gain is everybody after them: index order marches
		steadily away from the zone and reaches the far side by the twelfth
		joiner, while the sort alternates either side of it.
	]]
	print("  joiner   sorted walk   index-order walk")
	local sortedTotal, indexTotal = 0, 0
	for joiner = 1, ParkConfig.PlotCount do
		local a, b = walkFor(order[joiner]), walkFor(joiner)
		sortedTotal += a
		indexTotal += b
		if joiner == 1 or joiner == 6 or joiner == 12 or joiner == ParkConfig.PlotCount then
			print(string.format("  %6d   %8.0f (%2.0fs)   %8.0f (%2.0fs)",
				joiner, a, a / walkSpeed, b, b / walkSpeed))
		end
		--[[
			Not asserted per joiner: the late ones are deliberately worse off,
			because the short walks were handed to the people who joined first.
			The property that matters is the average over the first N, below.
		]]
	end
	--[[
		Over the WHOLE ring the two are identical, and they have to be: a full
		server hands out all 24 plots either way, so the same set of walks
		happens in a different order. The sort does not reduce walking - it
		front-loads the short walks, which is what matters because servers are
		rarely full and a new player joins into whatever is free.

		So the metric is the average over the first N joiners, not over all 24.
	]]
	near("a full server walks the same total either way",
		sortedTotal, indexTotal, 1)

	local function averageOverFirst(n, list)
		local total = 0
		for joiner = 1, n do
			total += walkFor(list and list[joiner] or joiner)
		end
		return total / n
	end

	--[[
		Sample sizes derived from the ring rather than written out. They were
		{4, 8, 12}, which asked about a twelfth joiner on a six-plot server -
		the spec measuring players who cannot exist.
	]]
	local samples = {}
	for _, fraction in ipairs({ 0.34, 0.5, 0.84 }) do
		local n = math.max(2, math.floor(ParkConfig.PlotCount * fraction))
		if n < ParkConfig.PlotCount then
			table.insert(samples, n)
		end
	end
	--[[
		Two claims, and the difference matters.

		NEVER WORSE holds for every N: sorting cannot send an early joiner
		further than index order would.

		STRICTLY BETTER does not hold for every N, and asserting it did was
		wrong. On a six-plot ring the first two joiners tie - plots 1 and 2 in
		index order happen to be as close to the free zone as the sorted pick.
		That is a fact about a small ring, not a broken sort, and the spec said
		FAIL for it until the claim was made precise.
	]]
	local improvedSomewhere = false
	for _, n in ipairs(samples) do
		local withSort = averageOverFirst(n, order)
		local without = averageOverFirst(n, nil)
		print(string.format("  first %2d joiners average %.0f studs sorted vs %.0f in index order (%.0f%% shorter)",
			n, withSort, without, (1 - withSort / without) * 100))
		ok(string.format("the first %d joiners are never sent further than index order", n),
			withSort <= without + 1e-6)
		if withSort < without - 1e-6 then
			improvedSomewhere = true
		end
	end
	ok("...and are measurably better somewhere, or the sort earns nothing",
		improvedSomewhere)

	--[[
		The order must be monotonic: each plot handed out is no closer than the
		last. Otherwise "nearest first" is a name rather than a property.
	]]
	local monotonic = true
	for index = 2, #order do
		if walkFor(order[index]) < walkFor(order[index - 1]) - 1e-6 then
			monotonic = false
		end
	end
	ok("plots fill outward from the free zone", monotonic)

	--[[
		And the worst case is unchanged, which is the honest half: a full
		server's last joiner still walks the long way, and no ordering fixes
		that. Recorded as finding 42 rather than papered over.
	]]
	near("the longest walk is the same as it ever was", walkFor(order[#order]), worst, 1)
end

--[[
	The FTUE targets 2m30. If the walk alone eats most of that, the design's
	own budget is wrong rather than the blockout being wrong - recorded either
	way.
]]
ok("even the furthest park reaches zone 1 inside the FTUE budget",
	worst / walkSpeed < TutorialConfig.TargetSecs * 0.5)

eq("the FTUE target is docs/00's 2m30", TutorialConfig.TargetSecs, 150)

--[[
	And the sum of the auto-advance timeouts must exceed the target, or a player
	who does nothing at all finishes faster than one who plays - which would make
	the completion metric meaningless.
]]
local worstCase = TutorialConfig.AutoAdvanceAfterSecs * TutorialConfig.StepCount
print(string.format("  a player who does nothing takes at least %.0fs (%.1f minutes)",
	worstCase, worstCase / 60))
ok("idling is slower than playing", worstCase > TutorialConfig.TargetSecs)

print("\n==============================================")
print(string.format("  %d passed, %d failed", passed, failed))
if failed > 0 then error("TESTS FAILED", 0) end
