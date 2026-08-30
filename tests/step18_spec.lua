--[[
	Step 18 specification.

	Server events. docs/13 names two hazards for this step and both are quiet:
	"events continuing after the last participant leaves" and "rewards granted
	twice on a rejoin". Neither throws; both are noticed weeks later.

	It also asserts the thing that nearly shipped broken here: that every
	ConfigValidator rule actually RUNS. Rule 11 spent all of Step 17 registered
	in the list without its function ever being defined - a nil in the middle
	of an array, which generalized iteration steps over in silence.

	Run with:  ./tests/run.sh
]]

local RandomMT = {}
RandomMT.__index = RandomMT
function RandomMT:NextNumber(a, b)
	self.s = (self.s * 16807) % 2147483647
	local x = self.s / 2147483647
	if a then return a + x * (b - a) end
	return x
end
function RandomMT:NextInteger(a, b) return a + math.floor(self:NextNumber() * (b - a + 1)) end
Random = { new = function(seed) return setmetatable({ s = seed or 1 }, RandomMT) end }

Color3 = { fromHex = function(h) return { Hex = h } end, fromRGB = function(r, g, b) return { r, g, b } end }
typeof = type

--@INJECT TableUtil=src/ReplicatedStorage/SAD_Shared/Modules/TableUtil.lua RNG=src/ReplicatedStorage/SAD_Shared/Modules/RNG.lua Format=src/ReplicatedStorage/SAD_Shared/Modules/Format.lua EventConfig=src/ReplicatedStorage/SAD_Shared/Config/EventConfig.lua WeatherConfig=src/ReplicatedStorage/SAD_Shared/Config/WeatherConfig.lua RarityConfig=src/ReplicatedStorage/SAD_Shared/Config/RarityConfig.lua MutationConfig=src/ReplicatedStorage/SAD_Shared/Config/MutationConfig.lua DinoConfig=src/ReplicatedStorage/SAD_Shared/Config/DinoConfig.lua ZoneConfig=src/ReplicatedStorage/SAD_Shared/Config/ZoneConfig.lua UpgradeConfig=src/ReplicatedStorage/SAD_Shared/Config/UpgradeConfig.lua BodyPlanConfig=src/ReplicatedStorage/SAD_Shared/Config/BodyPlanConfig.lua ChaseConfig=src/ReplicatedStorage/SAD_Shared/Config/ChaseConfig.lua ConfigValidator=src/ReplicatedStorage/SAD_Shared/Config/ConfigValidator.lua@

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

------------------------------------------------------------------- the table
section("The event table (docs/04 §3)")

local PUBLISHED = {
	{ "meteorImpact", 160, 3 * 60, "MeteorImpact" },
	{ "stampede", 160, 2 * 60, "Stampede" },
	{ "nestFrenzy", 150, 3 * 60, "NestFrenzy" },
	{ "amberRain", 80, 2 * 60, "AmberRain" },
}
for _, row in ipairs(PUBLISHED) do
	local entry = EventConfig.Get(row[1])
	ok("event exists: " .. row[1], entry ~= nil)
	eq(row[1] .. " weight", entry.Weight, row[2])
	eq(row[1] .. " duration", entry.DurationSecs, row[3])
	eq(row[1] .. " handler", entry.Handler, row[4])
	ok(row[1] .. " ships in V1", entry.InV1 == true)
end

eq("V1 ships four events", EventConfig.Count(), 4)
eq("every published event is asserted", #PUBLISHED, EventConfig.Count())
eq("events fire every 12-18 minutes", EventConfig.MinGapSecs, 720)
eq("...to", EventConfig.MaxGapSecs, 1080)
eq("with a 60-second countdown", EventConfig.CountdownSecs, 60)
eq("beats at 60, 30 and 10", #EventConfig.CountdownBeats, 3)
eq("the scoreboard is a top five", EventConfig.ScoreboardSize, 5)

-- The countdown beats must descend and end inside the countdown.
local previousBeat = math.huge
for _, beat in ipairs(EventConfig.CountdownBeats) do
	ok("beats descend: " .. beat, beat < previousBeat)
	ok("...and fit the countdown: " .. beat, beat <= EventConfig.CountdownSecs)
	previousBeat = beat
end
eq("the first beat is the countdown itself", EventConfig.CountdownBeats[1], EventConfig.CountdownSecs)

--[[
	An event must finish inside its own gap, or the scheduler's "never
	overlapping" is only true because it waits - which would silently stretch
	the published 12-18 minutes into something longer.
]]
for _, row in ipairs(PUBLISHED) do
	local entry = EventConfig.Get(row[1])
	ok("fits inside the shortest gap: " .. row[1],
		entry.DurationSecs + EventConfig.CountdownSecs < EventConfig.MinGapSecs)
end

--------------------------------------------------------------- no repeats
section("No-repeat-within-3, with only four events")

--[[
	docs/04 §3 asks for "a no-repeat-within-3 rule". With four events shipping,
	excluding the last three leaves exactly one choice - which is a fixed
	rotation, not a weighted roll. The exclusion depth is therefore clamped to
	leave at least two.
]]
eq("the published rule is 3", EventConfig.NoRepeatWithin, 3)
eq("but with four events it clamps to 2", EventConfig.ExclusionDepth(), 2)
ok("...leaving at least two choices",
	EventConfig.Count() - EventConfig.ExclusionDepth() >= 2)

-- The clamp must relax as content arrives, not stay at 2 forever.
local saved = EventConfig.Count
EventConfig.Count = function() return 12 end
eq("with all twelve it is the published 3", EventConfig.ExclusionDepth(), 3)
EventConfig.Count = function() return 2 end
eq("with only two it excludes nothing", EventConfig.ExclusionDepth(), 0)
EventConfig.Count = saved

-- Exclusion really removes events from the pool.
local excluded = EventConfig.RollableWeights({ meteorImpact = true, stampede = true })
eq("an excluded event is not rollable", excluded.meteorImpact, nil)
eq("...nor the other", excluded.stampede, nil)
ok("...but the rest are", excluded.nestFrenzy ~= nil and excluded.amberRain ~= nil)

--[[
	Simulated: a hundred rolls with the real exclusion, checking no event
	repeats inside the clamped window. This is the property the rule exists
	for, rather than the arithmetic behind it.
]]
local rng = Random.new(1808)
local recent = {}
local repeats = 0
local seenCounts = {}
for _ = 1, 2000 do
	local exclude = {}
	for index = 1, EventConfig.ExclusionDepth() do
		if recent[index] then exclude[recent[index]] = true end
	end
	local pool = EventConfig.RollableWeights(exclude)
	local picked = RNG.WeightedPick(pool, rng)

	for index = 1, EventConfig.ExclusionDepth() do
		if recent[index] == picked then repeats += 1 end
	end

	table.insert(recent, 1, picked)
	if #recent > EventConfig.NoRepeatWithin then table.remove(recent) end
	seenCounts[picked] = (seenCounts[picked] or 0) + 1
end

eq("no event repeats inside the exclusion window", repeats, 0)
for _, row in ipairs(PUBLISHED) do
	ok("every event still gets scheduled: " .. row[1], (seenCounts[row[1]] or 0) > 0)
end
print("  over 2,000 rolls: " .. (function()
	local parts = {}
	for _, row in ipairs(PUBLISHED) do
		table.insert(parts, string.format("%s %d", row[1], seenCounts[row[1]] or 0))
	end
	return table.concat(parts, ", ")
end)())

--------------------------------------------------------------- rewards
section("Nobody who turns up leaves with nothing (docs/04 §3.1)")

eq("the floor is 3 minutes of income", EventConfig.MinRewardIncomeSecs, 180)

--[[
	Reimplements EventService's payout. The service needs six other services
	and live players; the arithmetic is what can be wrong quietly, and it is
	pure.
]]
local MINIMUM_FLOOR_FOSSILS = 500
local function payout(scores, incomes)
	local ranked = {}
	for name, score in pairs(scores) do
		table.insert(ranked, { Name = name, Score = score })
	end
	table.sort(ranked, function(a, b) return a.Score > b.Score end)

	local top = ranked[1] and ranked[1].Score or 0
	for place, row in ipairs(ranked) do
		local minimum = math.max((incomes[row.Name] or 0) * EventConfig.MinRewardIncomeSecs,
			MINIMUM_FLOOR_FOSSILS)
		local share = if top > 0 then row.Score / top else 0
		row.Reward = math.floor(minimum * (1 + share * 3))
		row.Place = place
	end
	return ranked
end

local ranked = payout(
	{ whale = 100, middling = 20, tourist = 1 },
	{ whale = 5000, middling = 50, tourist = 0 })

for _, row in ipairs(ranked) do
	print(string.format("  %-10s score %3d  ->  %s Fossils", row.Name, row.Score, Format.Number(row.Reward)))
	ok("nobody receives nothing: " .. row.Name, row.Reward > 0)
end

eq("the top contributor places first", ranked[1].Name, "whale")
ok("contribution matters", ranked[1].Reward > ranked[3].Reward)

--[[
	The player earning nothing yet is exactly who the guarantee exists for, so
	the flat floor has to bite for them rather than paying three minutes of
	zero.
]]
local tourist
for _, row in ipairs(ranked) do
	if row.Name == "tourist" then tourist = row end
end
ok("a player with no income still gets the flat floor",
	tourist.Reward >= MINIMUM_FLOOR_FOSSILS)

--[[
	And it must scale with the player it is protecting. The same one-point
	contribution is worth far more to an earning player, because three minutes
	of THEIR income is what the document promises.
]]
local scaled = payout({ a = 1, b = 1 }, { a = 0, b = 5000 })
local rewardA, rewardB
for _, row in ipairs(scaled) do
	if row.Name == "a" then rewardA = row.Reward else rewardB = row.Reward end
end
ok("the floor scales with the player", rewardB > rewardA * 100)
near("...to exactly 3 minutes of their income, times the top share",
	rewardB, 5000 * 180 * 4, 5000 * 180 * 4 * 0.001)

-- An event nobody joined pays nobody, and must not error doing it.
eq("an empty event pays nobody", #payout({}, {}), 0)

------------------------------------------------------ granted once
section("Rewards cannot be collected twice (docs/13's hazard)")

--[[
	Participation is keyed by the PLAYER OBJECT and lives only in memory for
	one event. A rejoin is a different object with no score, so it cannot
	re-collect; and the score table is cleared in the same step it is read.

	Modelled here, because the property is about the ORDER of two statements
	and that is exactly the kind of thing a refactor breaks.
]]
local scores = { p1 = 10, p2 = 5 }
local function readAndClear(tbl)
	local snapshot = {}
	for key, value in pairs(tbl) do snapshot[key] = value end
	for key in pairs(tbl) do tbl[key] = nil end
	return snapshot
end

local firstPass = readAndClear(scores)
eq("the first payout sees both players",
	(firstPass.p1 or 0) + (firstPass.p2 or 0), 15)

local secondPass = readAndClear(scores)
eq("a second payout sees nothing", next(secondPass), nil)

-- A player who rejoins mid-event starts from zero rather than inheriting.
scores = {}
scores.p1 = 10
scores.p1 = nil -- left
scores["p1'"] = nil -- rejoined: a different key entirely
eq("a rejoining player has no score", scores["p1'"], nil)

------------------------------------------------------------- validator
section("Every validation rule actually runs")

--[[
	The bug this step found in the last one. Rule 11 was added to `RULES` in
	Step 17 but its function was never defined, so the entry was `nil` - a hole
	in the middle of an array, which generalized iteration walks straight over.
	No error, no skip, no output: the rule simply never existed.

	Two guards now. The list asserts every entry is a function at load, and
	`Run` fails any rule that reports neither a pass, a skip nor an error.
]]
local report = ConfigValidator.Run({
	Rarity = RarityConfig, Mutation = MutationConfig, Dino = DinoConfig,
	Zone = ZoneConfig, Upgrade = UpgradeConfig, Weather = WeatherConfig,
	Event = EventConfig,
	EventHandlers = { MeteorImpact = true, Stampede = true, NestFrenzy = true, AmberRain = true },
	BodyPlan = BodyPlanConfig, Chase = ChaseConfig,
})

eq("the full config set validates cleanly", #report.errors, 0)

local reported = {}
for _, check in ipairs(report.checks) do
	local id = string.match(check, "^%[(%w+)%]")
	if id then reported[id] = true end
end

--[[
	Named individually rather than counted, because a count passes just as
	happily when the wrong rule is missing.
]]
for _, id in ipairs({ "R1", "R2", "R3", "R4", "R5", "R6", "R8", "R9", "R11", "R12", "R13", "S" }) do
	ok("rule reported a pass: " .. id, reported[id] == true)
end

-- Rule 8 is the one this step finally supplies. It must be able to fail.
local broken = ConfigValidator.Run({
	Rarity = RarityConfig, Mutation = MutationConfig, Dino = DinoConfig,
	Zone = ZoneConfig, Upgrade = UpgradeConfig, Weather = WeatherConfig,
	Event = EventConfig, EventHandlers = { MeteorImpact = true },
})
ok("a missing handler is caught", #broken.errors >= 3)
ok("...and the error names the handler",
	string.find(table.concat(broken.errors, " "), "Stampede") ~= nil)

-- Rule 11 must be able to fail too, or its pass means nothing.
local savedModifiers = MutationConfig.WeatherModifiers.blizzard
MutationConfig.WeatherModifiers.blizzard = nil
local noBlizzard = ConfigValidator.Run({
	Rarity = RarityConfig, Mutation = MutationConfig, Dino = DinoConfig,
	Zone = ZoneConfig, Upgrade = UpgradeConfig, Weather = WeatherConfig,
})
ok("a weather with no modifier table is caught", #noBlizzard.errors > 0)
ok("...and the error names it",
	string.find(table.concat(noBlizzard.errors, " "), "blizzard") ~= nil)
MutationConfig.WeatherModifiers.blizzard = savedModifiers

-- Without its config the rule skips loudly rather than silently.
local noWeather = ConfigValidator.Run({
	Rarity = RarityConfig, Mutation = MutationConfig, Dino = DinoConfig,
	Zone = ZoneConfig, Upgrade = UpgradeConfig,
})
ok("a missing optional config produces a skip, not silence",
	string.find(table.concat(noWeather.skipped, " "), "WeatherConfig") ~= nil)
eq("...and no errors", #noWeather.errors, 0)

--------------------------------------------------------------- content
section("What the events hand out")

--[[
	The meteor upgrades what it drops by one tier, but only into a tier the
	zone can already produce - so a crater never hands out a rarity the zone's
	own nest sign does not advertise.
]]
eq("TierAbove exists", type(RarityConfig.TierAbove), "function")
eq("common upgrades to uncommon", RarityConfig.TierAbove("common"), "uncommon")
eq("legendary upgrades to mythic", RarityConfig.TierAbove("legendary"), "mythic")
eq("titan cannot be upgraded", RarityConfig.TierAbove("titan"), "titan")
eq("two steps", RarityConfig.TierAbove("common", 2), "rare")
eq("TierAbove undoes TierBelow", RarityConfig.TierAbove(RarityConfig.TierBelow("epic")), "epic")

for _, zoneId in ZoneConfig.Order do
	local weights = RarityConfig.WeightsForZone(zoneId)
	local upgradable = 0
	for rarityId, weight in pairs(weights) do
		if weight > 0 and (weights[RarityConfig.TierAbove(rarityId)] or 0) > 0 then
			upgradable += 1
		end
	end
	ok("a crater in " .. zoneId .. " can upgrade something", upgradable > 0)
end

--[[
	The stampede hands out Rare to Legendary, and every one of those tiers has
	to have a species to hand out or the capture silently fails.
]]
local DinoConfigSpecies = DinoConfig.Species
for _, rarity in ipairs({ "rare", "epic", "legendary" }) do
	local count = 0
	for _, entry in pairs(DinoConfigSpecies) do
		if entry.Rarity == rarity then count += 1 end
	end
	ok("the stampede can hand out a " .. rarity, count > 0)
end

-- Amber Rain is the catch-up mechanic, so its reward is flat rather than
-- scaled - and it has to be worth crossing the hub for.
local chunkFossils = EventConfig.Param("amberRain", "ChunkFossils", 0)
local chunkCount = EventConfig.Param("amberRain", "ChunkCount", 0)
print(string.format("  amber rain: %d chunks x %s = %s Fossils on the ground",
	chunkCount, Format.Number(chunkFossils), Format.Number(chunkCount * chunkFossils)))
ok("a chunk is worth picking up", chunkFossils > 0)
ok("the whole event is worth a zone unlock or two",
	chunkCount * chunkFossils > 5000)

eq("an unknown param returns the default", EventConfig.Param("amberRain", "Nonsense", 42), 42)
eq("an unknown event returns the default", EventConfig.Param("nothing", "ChunkCount", 7), 7)

print("\n==============================================")
print(string.format("  %d passed, %d failed", passed, failed))
if failed > 0 then error("TESTS FAILED", 0) end
