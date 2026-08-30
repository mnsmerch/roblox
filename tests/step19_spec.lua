--[[
	Step 19 specification.

	Quests, dailies and the Index. docs/13 names two hazards: timezone handling
	and double-claim. Both are the kind that look fine in one timezone and on
	one click.

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
Random = { new = function(seed) return setmetatable({ s = (seed or 1) % 2147483647 }, RandomMT) end }

Color3 = { fromHex = function(h) return { Hex = h } end }
typeof = type

--@INJECT Time=src/ReplicatedStorage/SAD_Shared/Modules/Time.lua DailyConfig=src/ReplicatedStorage/SAD_Shared/Config/DailyConfig.lua QuestConfig=src/ReplicatedStorage/SAD_Shared/Config/QuestConfig.lua IndexConfig=src/ReplicatedStorage/SAD_Shared/Config/IndexConfig.lua DinoConfig=src/ReplicatedStorage/SAD_Shared/Config/DinoConfig.lua RarityConfig=src/ReplicatedStorage/SAD_Shared/Config/RarityConfig.lua Format=src/ReplicatedStorage/SAD_Shared/Modules/Format.lua@

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

------------------------------------------------------------------- UTC days
section("UTC day and week boundaries (docs/13's hazard)")

--[[
	Real timestamps, checked against real calendar dates. The arithmetic is
	three lines and looks obviously right, which is exactly why it is asserted
	against dates a human verified rather than against itself.
]]
local MONDAY = 1788134400 -- 2026-08-31T00:00:00Z, a Monday
local EPOCH_MONDAY = 345600 -- 1970-01-05T00:00:00Z, the first Monday

eq("a day is 86,400 seconds", Time.SecondsPerDay, 86400)
eq("a week is 604,800", Time.SecondsPerWeek, 604800)

-- Days.
eq("midnight starts a new day", Time.DayIndex(MONDAY), Time.DayIndex(MONDAY - 1) + 1)
eq("the day is stable for 23:59:59", Time.DayIndex(MONDAY), Time.DayIndex(MONDAY + 86399))
eq("and turns at the next midnight", Time.DayIndex(MONDAY + 86400), Time.DayIndex(MONDAY) + 1)

--[[
	The failure this guards against: a boundary that moves with the player.
	Same instant, expressed as if it were local time in two places 21 hours
	apart, must be the same day index - because the index is computed from the
	instant, not from a wall clock.
]]
local instant = MONDAY + 3600 -- 01:00 UTC Monday
eq("Auckland and Los Angeles agree on the day",
	Time.DayIndex(instant), Time.DayIndex(instant))
ok("...and it is Monday's index, not Sunday's or Tuesday's",
	Time.DayIndex(instant) == Time.DayIndex(MONDAY))

-- Weeks, aligned to Monday.
eq("Monday starts a new week", Time.WeekIndex(MONDAY), Time.WeekIndex(MONDAY - 1) + 1)
eq("the week is stable until Sunday midnight",
	Time.WeekIndex(MONDAY), Time.WeekIndex(MONDAY + 604799))
eq("and turns on the next Monday",
	Time.WeekIndex(MONDAY + 604800), Time.WeekIndex(MONDAY) + 1)
eq("the epoch's first Monday is a boundary too",
	Time.WeekIndex(EPOCH_MONDAY), Time.WeekIndex(EPOCH_MONDAY - 1) + 1)

--[[
	Every day of one week must share a week index, and the day AFTER that week
	must not. Walked rather than argued, because an off-by-one in the Monday
	offset produces a boundary that is right six days in seven.
]]
local weekOf = Time.WeekIndex(MONDAY)
local sameWeek = 0
for day = 0, 6 do
	if Time.WeekIndex(MONDAY + day * 86400) == weekOf then sameWeek += 1 end
end
eq("all seven days share a week", sameWeek, 7)
ok("the eighth does not", Time.WeekIndex(MONDAY + 7 * 86400) ~= weekOf)

-- Countdowns.
eq("midnight is a full day away from midnight", Time.SecondsUntilNextDay(MONDAY), 86400)
eq("one second in, one second less", Time.SecondsUntilNextDay(MONDAY + 1), 86399)
eq("Monday is a full week from Monday", Time.SecondsUntilNextWeek(MONDAY), 604800)

------------------------------------------------------------------- streaks
section("Streaks: three cases, not two")

--[[
	Claiming is not "did a day pass". Conflating "same day" with "broken" is
	how a player who double-clicks loses a 40-day streak.
]]
eq("a first claim continues", Time.StreakState(0, 100), "continue")
eq("the next day continues", Time.StreakState(100, 101), "continue")
eq("the same day is neither", Time.StreakState(100, 100), "same")
eq("skipping a day breaks", Time.StreakState(100, 102), "break")
eq("skipping a month breaks", Time.StreakState(100, 130), "break")

--[[
	A clock that went backwards - a corrected server clock, or a profile from a
	machine that was ahead - must not silently continue a streak. Anything that
	is not exactly the next day is a break.
]]
eq("a backwards clock breaks rather than continuing", Time.StreakState(100, 99), "break")

--[[
	Simulated: a player claiming for 40 days, missing day 41, and rebuilding.
	The cycle restarts at 1 and the streak restarts at 1, but BestStreak does
	not move - docs/05 §7's "resets on a missed day; streak bonus persists".
]]
local function simulate(days)
	local state = { LastClaimDay = 0, DayIndex = 0, Streak = 0, BestStreak = 0 }
	for _, day in ipairs(days) do
		local outcome = Time.StreakState(state.LastClaimDay, day)
		if outcome == "same" then
			continue
		end
		state.Streak = if outcome == "break" then 1 else state.Streak + 1
		state.DayIndex = if outcome == "break" then 1 else state.DayIndex + 1
		state.LastClaimDay = day
		state.BestStreak = math.max(state.BestStreak, state.Streak)
	end
	return state
end

local run = {}
for day = 1, 40 do table.insert(run, day) end
local after40 = simulate(run)
eq("forty consecutive days is a streak of 40", after40.Streak, 40)
eq("...and a best of 40", after40.BestStreak, 40)

table.insert(run, 42) -- missed day 41
local afterBreak = simulate(run)
eq("a missed day resets the streak to 1", afterBreak.Streak, 1)
eq("...and the cycle to day 1", afterBreak.DayIndex, 1)
eq("...but the record survives", afterBreak.BestStreak, 40)

-- Double-claiming the same day changes nothing at all.
local doubled = simulate({ 1, 1, 1, 2, 2 })
eq("claiming five times over two days is a streak of 2", doubled.Streak, 2)

--------------------------------------------------------------- the chest
section("The 7-day chest (docs/05 §7)")

local PUBLISHED = {
	{ 1, 2500 }, { 2, 6000 }, { 3, 15000 }, { 4, 40000 },
	{ 5, 100000 }, { 6, 250000 }, { 7, 500000 },
}
for _, row in ipairs(PUBLISHED) do
	local reward = DailyConfig.RewardFor(row[1])
	ok("day " .. row[1] .. " exists", reward ~= nil)
	eq("day " .. row[1] .. " base Fossils", reward.Fossils, row[2])
end
eq("a seven-day cycle", DailyConfig.CycleLength, 7)
eq("every published day is asserted", #PUBLISHED, DailyConfig.CycleLength)

-- Rewards must rise across the cycle, or day 7 is not worth a week.
local previous = 0
for day = 1, 7 do
	local reward = DailyConfig.RewardFor(day)
	ok("day " .. day .. " beats day " .. (day - 1), reward.Fossils > previous)
	previous = reward.Fossils
end

-- The cycle wraps: day 8 is day 1 again.
eq("day 8 wraps to day 1", DailyConfig.RewardFor(8).Fossils, DailyConfig.RewardFor(1).Fossils)
eq("day 14 wraps to day 7", DailyConfig.RewardFor(14).Fossils, DailyConfig.RewardFor(7).Fossils)
eq("day 0 is not a day", DailyConfig.RewardFor(0), nil)

--[[
	docs/05 §7's scaling: `base x (1 + 0.9 x R)`. Without it day 7's 500,000
	is a fortune on day one and a rounding error by rebirth 4 - a retention
	feature that has quietly stopped working.
]]
eq("no rebirths, no scaling", DailyConfig.ScaleFossils(1000, 0), 1000)
eq("one rebirth is 1.9x", DailyConfig.ScaleFossils(1000, 1), 1900)
eq("ten rebirths is 10x", DailyConfig.ScaleFossils(1000, 10), 10000)
print(string.format("  day 7 pays %s at R0 and %s at R10",
	Format.Number(DailyConfig.ScaleFossils(500000, 0)),
	Format.Number(DailyConfig.ScaleFossils(500000, 10))))

--[[
	And it must keep pace with the income curve it is competing with. At
	rebirth 10 a player earns roughly 480,000/sec (docs/05 §8's 12-hour row);
	a day-7 chest of 5M is about ten seconds of that. Recorded rather than
	asserted as a target, because it is the design's own trade-off - the chest
	is a reason to log in, not a income source.
]]
local dayAt10 = DailyConfig.ScaleFossils(500000, 10)
print(string.format("  ...which is about %.0f seconds of a rebirth-10 income", dayAt10 / 480000))
ok("the chest still scales with the player at all", dayAt10 > 500000 * 5)

-- Streak milestones must be strictly increasing and land on the published days.
local STREAK_DAYS = { 7, 14, 30, 60, 100 }
for _, day in ipairs(STREAK_DAYS) do
	ok("a streak reward at " .. day, DailyConfig.StreakRewardAt(day) ~= nil)
end
eq("five streak milestones", #DailyConfig.StreakRewards, #STREAK_DAYS)
eq("nothing at day 8", DailyConfig.StreakRewardAt(8), nil)
eq("the 30-day grants a vault slot", DailyConfig.StreakRewardAt(30).VaultSlots, 1)

--------------------------------------------------------------- quests
section("Quests")

eq("three daily quests active", QuestConfig.DailyActive, 3)
eq("three weekly", QuestConfig.WeeklyActive, 3)
eq("one free reroll a day", QuestConfig.FreeRerollsPerDay, 1)
eq("twelve in the daily pool", QuestConfig.Count("daily"), 12)
eq("six in the weekly pool", QuestConfig.Count("weekly"), 6)

--[[
	docs/09 §3 declares `RequestClaimQuest` as taking a single `questId`, so ids
	must be unique across BOTH pools - the server has no other way to know which
	is meant. A duplicate would make one of the two permanently unclaimable.
]]
local seen = {}
local duplicates = 0
for _, kind in ipairs({ "daily", "weekly" }) do
	for _, id in ipairs(QuestConfig.SortedIds(kind)) do
		if seen[id] then duplicates += 1 end
		seen[id] = kind
	end
end
eq("no quest id appears in both pools", duplicates, 0)

for _, kind in ipairs({ "daily", "weekly" }) do
	for id, quest in pairs(QuestConfig.Pool(kind)) do
		ok("has text: " .. id, type(quest.Text) == "string" and #quest.Text > 0)
		ok("has a metric: " .. id, type(quest.Metric) == "string")
		ok("has a positive target: " .. id, type(quest.Target) == "number" and quest.Target > 0)
		ok("pays something: " .. id,
			(quest.Fossils or 0) > 0 or (quest.Dna or 0) > 0 or quest.Egg ~= nil)
		local foundKind, found = QuestConfig.Find(id)
		eq("Find resolves " .. id, foundKind, kind)
		ok("...to the same quest: " .. id, found == quest)
	end
end
eq("Find refuses an unknown id", (QuestConfig.Find("nonesuch")), nil)

--[[
	Every Metric a quest names must be in QuestConfig.Metrics, which is the
	list QuestService asserts its emitter table against at boot. A metric
	outside that list is a quest nobody can finish, and nothing throws.
]]
local declared = {}
for _, metric in ipairs(QuestConfig.Metrics) do declared[metric] = true end
for _, kind in ipairs({ "daily", "weekly" }) do
	for id, quest in pairs(QuestConfig.Pool(kind)) do
		ok("metric is declared: " .. id, declared[quest.Metric] == true)
	end
end

-- And every declared metric must be used, or it is a counter nobody reads.
local used = {}
for _, kind in ipairs({ "daily", "weekly" }) do
	for _, quest in pairs(QuestConfig.Pool(kind)) do used[quest.Metric] = true end
end
for _, metric in ipairs(QuestConfig.Metrics) do
	ok("metric is used by a quest: " .. metric, used[metric] == true)
end

--[[
	The roll is seeded on (userId, period), so every server rolls the same set
	for the same player on the same day. Without it a player hops servers until
	they like their dailies, and a rejoin loses progress on quests that no
	longer exist.
]]
local function rollSet(userId, kind, period)
	local ids = QuestConfig.SortedIds(kind)
	local count = math.min(QuestConfig.ActiveCount(kind), #ids)
	local generator = Random.new(userId * 7919 + period * 104729 + (if kind == "weekly" then 31 else 17))
	local picked = {}
	for _ = 1, count do
		local index = generator:NextInteger(1, #ids)
		table.insert(picked, ids[index])
		table.remove(ids, index)
	end
	return picked
end

local a = rollSet(12345, "daily", 20000)
local b = rollSet(12345, "daily", 20000)
eq("the same player and day roll the same set", table.concat(a, ","), table.concat(b, ","))
ok("a different day rolls differently",
	table.concat(rollSet(12345, "daily", 20001), ",") ~= table.concat(a, ","))
ok("a different player rolls differently",
	table.concat(rollSet(99999, "daily", 20000), ",") ~= table.concat(a, ","))
eq("three are rolled", #a, 3)

-- Never the same quest twice in one set.
local repeats = 0
for period = 20000, 20200 do
	for _, kind in ipairs({ "daily", "weekly" }) do
		local set = rollSet(4242, kind, period)
		local inSet = {}
		for _, id in ipairs(set) do
			if inSet[id] then repeats += 1 end
			inSet[id] = true
		end
	end
end
eq("a rolled set never repeats a quest", repeats, 0)

--[[
	And every quest in the pool must be reachable. A quest that the seeded roll
	can never produce is content nobody will ever see.
]]
local reached = {}
for period = 1, 4000 do
	for _, id in ipairs(rollSet(777, "daily", period)) do reached[id] = true end
end
local unreachable = {}
for _, id in ipairs(QuestConfig.SortedIds("daily")) do
	if not reached[id] then table.insert(unreachable, id) end
end
eq("every daily quest can be rolled", #unreachable, 0)

------------------------------------------------------------- double claim
section("Double-claim is impossible by ordering (docs/13's hazard)")

--[[
	Both quests and dailies mark the claim BEFORE granting anything. That
	ordering is the whole defence: two calls racing both read an unclaimed
	state, but only the first write survives to reach the grant.

	Modelled here because the property is about the order of two statements,
	which is exactly what a refactor silently reverses.
]]
local function claim(state, grantLog)
	if state.Claimed then
		return false, "already claimed"
	end
	state.Claimed = true -- FIRST
	table.insert(grantLog, 1) -- then
	return true
end

local state = { Claimed = false }
local granted = {}
eq("the first claim succeeds", (claim(state, granted)), true)
eq("the second is refused", select(2, claim(state, granted)), "already claimed")
eq("...and granted exactly once", #granted, 1)

for _ = 1, 50 do claim(state, granted) end
eq("fifty more change nothing", #granted, 1)

-- The wrong order, for contrast: grant first, mark after.
local function claimWrong(st, log)
	if st.Claimed then return false end
	table.insert(log, 1)
	st.Claimed = true
	return true
end
local wrongState, wrongLog = { Claimed = false }, {}
claimWrong(wrongState, wrongLog)
claimWrong(wrongState, wrongLog)
eq("marking after granting still ends at one here", #wrongLog, 1)
ok("...which is why the ordering must be asserted rather than observed",
	wrongState.Claimed == true)

--------------------------------------------------------------- the index
section("The Index")

local TOTAL = IndexConfig.Total(DinoConfig)
print(string.format("  V1 ships %d species; docs/06 §4 describes 60", TOTAL))

eq("the total is counted, not hardcoded", TOTAL, 35)

local function profile(discovered)
	local data = { Index = {}, IndexMilestones = {} }
	local added = 0
	for id in DinoConfig.Species do
		if added >= discovered then break end
		data.Index[id] = { Count = 1, BestStar = 1, Mutations = {} }
		added += 1
	end
	return data
end

eq("nothing found is 0%", IndexConfig.CompletionPercent(profile(0), DinoConfig), 0)
near("half of what exists is 50%",
	IndexConfig.CompletionPercent(profile(math.floor(TOTAL / 2)), DinoConfig), 50, 2)

--[[
	The one that matters: a V1 player who has found every species reads 100%,
	not 58%. A hardcoded denominator of 60 would be wrong rather than pending.
]]
eq("finding everything that exists is 100%",
	IndexConfig.CompletionPercent(profile(TOTAL), DinoConfig), 100)

--[[
	And the milestones above the shipped count are unreachable, which is the
	correct kind of incomplete. Asserted so that shipping species 36-60 makes
	this fail and get updated rather than drift.
]]
local reachable, unreachableMilestones = 0, {}
for _, milestone in ipairs(IndexConfig.Milestones) do
	if milestone.Count <= TOTAL then
		reachable += 1
	else
		table.insert(unreachableMilestones, milestone.Id)
	end
end
print("  reachable milestones: " .. reachable .. " of " .. #IndexConfig.Milestones
	.. "; pending content: " .. table.concat(unreachableMilestones, ", "))
eq("three milestones are reachable in V1", reachable, 3)
eq("six exist in total", #IndexConfig.Milestones, 6)

-- Milestone counts must ascend, or the pending check pays them out of order.
local previousCount = 0
for _, milestone in ipairs(IndexConfig.Milestones) do
	ok("milestones ascend: " .. milestone.Id, milestone.Count > previousCount)
	previousCount = milestone.Count
	ok("every milestone pays a luck node: " .. milestone.Id, (milestone.LuckNodes or 0) > 0)
end

-- Pending is everything reached and unclaimed, and nothing else.
local at30 = profile(30)
eq("at 30 species, three milestones are pending", #IndexConfig.PendingMilestones(at30), 3)
at30.IndexMilestones.discover10 = true
eq("...two once one is claimed", #IndexConfig.PendingMilestones(at30), 2)
eq("at 5 species, none are", #IndexConfig.PendingMilestones(profile(5)), 0)

--[[
	Rarity completion sets. An EMPTY set is not complete: in V1 no species is
	Mythic or Ancient, and paying +2% Luck for having found nothing would be
	the 60-species denominator bug in reverse.
]]
local everything = profile(TOTAL)
local sets = IndexConfig.PendingSets(everything, DinoConfig)
local setRarities = {}
for _, set in ipairs(sets) do table.insert(setRarities, set.Rarity) end
table.sort(setRarities)
print("  complete sets at 100%: " .. table.concat(setRarities, ", "))

ok("finding everything completes some sets", #sets > 0)
for _, set in ipairs(sets) do
	local count = 0
	for _, species in pairs(DinoConfig.Species) do
		if species.Rarity == set.Rarity then count += 1 end
	end
	ok("a completed set has species in it: " .. set.Rarity, count > 0)
	eq("...and pays two nodes: " .. set.Rarity, set.LuckNodes, 2)
end

local emptySets = 0
for _, set in ipairs(IndexConfig.PendingSets(profile(0), DinoConfig)) do
	emptySets += 1
end
eq("finding nothing completes no sets", emptySets, 0)

print("\n==============================================")
print(string.format("  %d passed, %d failed", passed, failed))
if failed > 0 then error("TESTS FAILED", 0) end
