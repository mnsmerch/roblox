--!nonstrict
--[[
	QuestConfig
	ReplicatedStorage/SAD_Shared/Config/QuestConfig  (ModuleScript)

	The daily and weekly quest pools from docs/05 §7.

	═══ EVERY QUEST IS A COUNTER AND A SIGNAL ══════════════════════════════════
	`Metric` names what is counted; `Target` is how many. QuestService owns one
	table mapping each Metric to the signal that increments it, so adding a
	quest is a row here - never a new listener, never a new counter, never a
	new place progress can be lost.

	That also makes the whole pool testable: a quest whose Metric nothing emits
	is a quest nobody can finish, and boot says so.
	═══════════════════════════════════════════════════════════════════════════

	Depends on: nothing.
]]

local QuestConfig = {}

--- docs/05 §7: "3 active, reroll 1 per day free" / "3 active, Monday reset".
QuestConfig.DailyActive = 3
QuestConfig.WeeklyActive = 3
QuestConfig.FreeRerollsPerDay = 1

--- docs/05 §7: "All Fossil values are multiplied by (1 + 0.9 x rebirths)."
QuestConfig.RebirthScale = 0.9

local daily = {}
local weekly = {}

local function quest(list, entry)
	assert(list[entry.Id] == nil, "duplicate quest: " .. entry.Id)
	list[entry.Id] = entry
	return entry
end

-- ── Daily pool (docs/05 §7) ─────────────────────────────────────────────────

quest(daily, { Id = "stealEggs", Text = "Steal 5 wild eggs",
	Metric = "eggsStolen", Target = 5, Fossils = 8000 })
quest(daily, { Id = "hatch10", Text = "Hatch 10 dinosaurs",
	Metric = "dinosHatched", Target = 10, Fossils = 12000 })
quest(daily, { Id = "earn100k", Text = "Earn 100,000 Fossils",
	Metric = "fossilsEarned", Target = 100000, Fossils = 15000 })
quest(daily, { Id = "raidOne", Text = "Steal a dinosaur from another player",
	Metric = "dinosStolen", Target = 1, Fossils = 20000, Shield = 600 })
quest(daily, { Id = "discover", Text = "Discover a new species",
	Metric = "speciesDiscovered", Target = 1, Fossils = 25000, Dna = 10 })
quest(daily, { Id = "joinEvent", Text = "Participate in a server event",
	Metric = "eventsJoined", Target = 1, Fossils = 18000,
	Boost = { Id = "luckPotion", Secs = 900 } })
quest(daily, { Id = "visitPark", Text = "Visit another player's park",
	Metric = "parksVisited", Target = 1, Fossils = 5000 })
quest(daily, { Id = "escape3", Text = "Escape 3 chases without being caught",
	Metric = "chasesEscaped", Target = 3, Fossils = 14000 })
quest(daily, { Id = "place3", Text = "Place 3 dinosaurs",
	Metric = "dinosPlaced", Target = 3, Fossils = 10000 })
quest(daily, { Id = "collect5", Text = "Collect income 5 times",
	Metric = "incomeCollected", Target = 5, Fossils = 6000 })
quest(daily, { Id = "surviveRaid", Text = "Survive a raid attempt",
	Metric = "raidsSurvived", Target = 1, Fossils = 22000 })
quest(daily, { Id = "weatherHatch", Text = "Hatch an egg during special weather",
	Metric = "weatherHatches", Target = 1, Fossils = 20000, Dna = 15 })

-- ── Weekly pool (docs/05 §7) ────────────────────────────────────────────────

quest(weekly, { Id = "steal100", Text = "Steal 100 wild eggs",
	Metric = "eggsStolen", Target = 100, Fossils = 400000, Dna = 200 })
quest(weekly, { Id = "hatch5Epic", Text = "Hatch 5 Epic or better",
	Metric = "epicHatches", Target = 5, Fossils = 600000, Egg = "legendary" })
quest(weekly, { Id = "daily20", Text = "Complete 20 daily quests",
	Metric = "dailyQuestsDone", Target = 20, Fossils = 750000, LuckNodes = 1 })
quest(weekly, { Id = "raid10", Text = "Steal 10 dinosaurs from players",
	Metric = "dinosStolen", Target = 10, Fossils = 500000, Shield = 1200 })
quest(weekly, { Id = "events15", Text = "Participate in 15 server events",
	Metric = "eventsJoined", Target = 15, Fossils = 450000, Dna = 300 })
quest(weekly, { Id = "newZone", Text = "Reach a new zone",
	Metric = "zonesUnlocked", Target = 1, Fossils = 1000000 })

QuestConfig.Daily = daily
QuestConfig.Weekly = weekly

--- Ids must be unique across both pools; see QuestConfig.Find.
for id in daily do
	assert(weekly[id] == nil,
		"[SAD] QuestConfig: '" .. id .. "' is in both the daily and weekly pools. "
			.. "RequestClaimQuest takes only an id, so one of them would be unclaimable")
end

--[[
	Every Metric a quest can name. QuestService asserts its own emitter table
	covers exactly this set - a metric here with no emitter is an unfinishable
	quest, and an emitter with no metric is a counter nobody reads.
]]
QuestConfig.Metrics = {
	"eggsStolen", "dinosHatched", "fossilsEarned", "dinosStolen",
	"speciesDiscovered", "eventsJoined", "parksVisited", "chasesEscaped",
	"dinosPlaced", "incomeCollected", "raidsSurvived", "weatherHatches",
	"epicHatches", "dailyQuestsDone", "zonesUnlocked",
}

-- ── Helpers ─────────────────────────────────────────────────────────────────

function QuestConfig.Get(kind: string, questId: string)
	local pool = if kind == "weekly" then weekly else daily
	return pool[questId]
end

--[[
	Finds a quest by id alone, returning (kind, quest).

	docs/09 §3 declares `RequestClaimQuest` as taking a single `questId`, so ids
	must be unique ACROSS both pools - the server has no other way to know which
	one is meant. Asserted at load below rather than trusted, because a
	duplicate id would silently make one of the two unclaimable.
]]
function QuestConfig.Find(questId: string)
	local quest = daily[questId]
	if quest then
		return "daily", quest
	end
	quest = weekly[questId]
	if quest then
		return "weekly", quest
	end
	return nil, nil
end

function QuestConfig.Pool(kind: string)
	return if kind == "weekly" then weekly else daily
end

function QuestConfig.ActiveCount(kind: string): number
	return if kind == "weekly" then QuestConfig.WeeklyActive else QuestConfig.DailyActive
end

--- Sorted ids, so a seeded roll is reproducible. `pairs` order is not.
function QuestConfig.SortedIds(kind: string): { string }
	local ids = {}
	for id in QuestConfig.Pool(kind) do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

function QuestConfig.Count(kind: string): number
	return #QuestConfig.SortedIds(kind)
end

--- docs/05 §7's scaling, applied to Fossils only. DNA is the depth currency
--- and deliberately does not inflate (docs/05 §1).
function QuestConfig.ScaleFossils(base: number, rebirths: number): number
	return math.floor(base * (1 + QuestConfig.RebirthScale * (rebirths or 0)))
end

return QuestConfig
