--!nonstrict
--[[
	QuestService
	ServerScriptService/SAD_Server/Services/QuestService  (ModuleScript)
	  └── RewardGrant  (ModuleScript)

	Three daily quests, three weekly, and the counters behind them.

	═══ ONE EMITTER TABLE, NOT FIFTEEN LISTENERS ═══════════════════════════════
	Every quest is a Metric and a Target. `EMITTERS` maps each Metric to the
	signal that increments it, in one place, and boot asserts that the set of
	Metrics in QuestConfig and the set of keys here are identical.

	A metric with no emitter is a quest nobody can finish. An emitter with no
	metric is a counter nobody reads. Neither throws, and either can sit in a
	shipped game for months - which is why boot refuses both.
	═══════════════════════════════════════════════════════════════════════════

	═══ UTC DAYS, EVERYWHERE ═══════════════════════════════════════════════════
	docs/13 §Step 19 names timezone handling as this step's hazard. Rolls are
	keyed on `Time.DayIndex` and `Time.WeekIndex`, both pure integer division on
	`os.time()`, and stored in the profile as those integers. "Is it a new day"
	is `index > stored` - never a date, never a locale, never a duration.
	═══════════════════════════════════════════════════════════════════════════

	API:
		QuestService.Refresh(player)              -- rolls if the day/week turned
		QuestService.Bump(player, metric, amount) -- progress
		QuestService.Claim(player, questId) -> ok, reason?
		QuestService.Reroll(player, questId) -> ok, reason?
		QuestService.GetActive(data, kind) -> { questId }
		QuestService.QuestCompleted  Signal(player, kind, questId)

	Depends on: QuestConfig, Time, RNG, PlayerDataService, EconomyService,
	            NotificationService, RewardGrant.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local Format = require(Shared.Modules.Format)
local Log = require(Shared.Modules.Log)
local Net = require(Shared.Modules.Net)
local QuestConfig = require(Shared.Config.QuestConfig)
local Signal = require(Shared.Modules.Signal)
local Time = require(Shared.Modules.Time)

local QuestService = {}

QuestService.QuestCompleted = Signal.new()

local PlayerDataService, NotificationService, RewardGrant

--[[
	Metric -> the signal that increments it, and by how much.

	`From` is resolved at Start so this table can name services that load after
	this one. `Amount` is a function of the signal's own arguments, so a metric
	counting Fossils and one counting events use the same mechanism.
]]
local EMITTERS = {
	eggsStolen = { Service = "EggService", Signal = "EggDeposited" },
	dinosHatched = { Service = "IncubationService", Signal = "Hatched" },
	fossilsEarned = { Service = "EconomyService", Signal = "Collected",
		Amount = function(_, amount) return amount end },
	dinosStolen = { Service = "StealService", Signal = "StealCompleted" },
	speciesDiscovered = { Service = "IndexService", Signal = "SpeciesDiscovered" },
	eventsJoined = { Service = "EventService", Signal = "Started", Broadcast = true },
	parksVisited = { Service = "ParkService", Signal = "ParkEntered",
		Filter = function(player, ownerUserId) return player.UserId ~= ownerUserId end },
	chasesEscaped = { Service = "WildAIService", Signal = "ChaseEnded",
		Filter = function(_, reason) return reason == "escaped" end },
	dinosPlaced = { Service = "DinosaurService", Signal = "DinoPlaced" },
	incomeCollected = { Service = "EconomyService", Signal = "Collected" },
	raidsSurvived = { Service = "StealService", Signal = "StealFailed" },
	weatherHatches = { Service = "IncubationService", Signal = "Hatched", Weather = true },
	epicHatches = { Service = "IncubationService", Signal = "Hatched", MinRarity = "epic" },
	--[[
		These two are bumped by other systems calling Bump directly rather than
		by a signal of their own: one counts this service's own completions, and
		the other is a state change ZoneService already announces.
	]]
	dailyQuestsDone = { Direct = true },
	zonesUnlocked = { Service = "NestService", Zones = true, Signal = "ZoneUnlocked" },
}

-- ── Rolling ─────────────────────────────────────────────────────────────────

--[[
	Picks `count` distinct quests from a pool, seeded so every server rolls the
	same set for the same player on the same day.

	Seeded on (userId, day) rather than randomly: otherwise a player who
	hops servers re-rolls their dailies until they like them, and a player who
	rejoins loses the progress they had on quests that no longer exist.
]]
local function rollSet(userId: number, kind: string, period: number)
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

local function emptyProgress(questIds)
	local set = {}
	for _, id in questIds do
		set[id] = { Progress = 0, Claimed = false }
	end
	return set
end

--[[
	Rolls new quests if the day or the week has turned. Idempotent: called on
	join, on every claim, and once a minute, and does nothing when nothing has
	turned over.
]]
function QuestService.Refresh(player: Player, now: number?)
	local data = PlayerDataService.Get(player)
	if not data then
		return
	end

	local at = now or os.time()
	local day = Time.DayIndex(at)
	local week = Time.WeekIndex(at)

	local rolledDaily = day > (data.Quests.DailyResetDay or 0)
	local rolledWeekly = week > (data.Quests.WeeklyResetWeek or 0)
	if not rolledDaily and not rolledWeekly then
		return
	end

	PlayerDataService.UpdateKeys(player, { "Quests" }, function(profile)
		if rolledDaily then
			profile.Quests.Daily = emptyProgress(rollSet(player.UserId, "daily", day))
			profile.Quests.DailyResetDay = day
			profile.Quests.RerollsUsed = 0
		end
		if rolledWeekly then
			profile.Quests.Weekly = emptyProgress(rollSet(player.UserId, "weekly", week))
			profile.Quests.WeeklyResetWeek = week
		end
	end, "quest roll")

	Log.debug("QuestService", "%s rolled %s%s", player.Name,
		if rolledDaily then "dailies " else "", if rolledWeekly then "weeklies" else "")
end

function QuestService.GetActive(data, kind: string): { string }
	local set = if kind == "weekly" then data.Quests.Weekly else data.Quests.Daily
	local ids = {}
	for id in set do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

-- ── Progress ────────────────────────────────────────────────────────────────

--[[
	Adds progress to every active quest tracking `metric`, in both pools.

	Progress is capped at the Target on write, so a quest cannot store a number
	larger than it needs and a later Target change cannot retroactively
	complete something.
]]
function QuestService.Bump(player: Player, metric: string, amount: number?)
	local data = PlayerDataService.Get(player)
	if not data then
		return
	end

	local step = amount or 1
	if step <= 0 then
		return
	end

	local completed = {}

	PlayerDataService.UpdateKeys(player, { "Quests" }, function(profile)
		for _, kind in { "daily", "weekly" } do
			local set = if kind == "weekly" then profile.Quests.Weekly else profile.Quests.Daily
			for questId, state in set do
				local quest = QuestConfig.Get(kind, questId)
				if not quest or quest.Metric ~= metric or state.Claimed then
					continue
				end
				if state.Progress >= quest.Target then
					continue
				end

				state.Progress = math.min(state.Progress + step, quest.Target)
				if state.Progress >= quest.Target then
					table.insert(completed, { Kind = kind, Quest = quest })
				end
			end
		end
	end, "quest progress")

	for _, entry in completed do
		NotificationService.Toast(player, "QUEST COMPLETE", entry.Quest.Text,
			{ Sound = "Upgrade" })
		QuestService.QuestCompleted:Fire(player, entry.Kind, entry.Quest.Id)
	end
end

-- ── Claiming ────────────────────────────────────────────────────────────────

--[[
	Claims one quest by id. The pool is derived, not passed: docs/09 §3 gives
	`RequestClaimQuest` a single `questId` argument, and QuestConfig asserts ids
	are unique across both pools so that is unambiguous.
]]
function QuestService.Claim(player: Player, questId: string): (boolean, string?)
	local data = PlayerDataService.Get(player)
	if not data then
		return false, "profile not loaded"
	end

	local kind, quest = QuestConfig.Find(questId)
	if not quest then
		return false, "no such quest"
	end

	local set = if kind == "weekly" then data.Quests.Weekly else data.Quests.Daily
	local state = set[questId]
	if not state then
		return false, "not one of yours"
	end
	if state.Claimed then
		return false, "already claimed"
	end
	if state.Progress < quest.Target then
		return false, "not finished"
	end

	--[[
		Marked claimed BEFORE anything is granted. docs/13 names double-claim as
		this step's other hazard, and the order is the whole defence: two calls
		racing both read Claimed = false, but only the first write survives to
		reach the grant.
	]]
	PlayerDataService.UpdateKeys(player, { "Quests" }, function(profile)
		local target = if kind == "weekly" then profile.Quests.Weekly else profile.Quests.Daily
		target[questId].Claimed = true
	end, "quest claim")

	RewardGrant.Give(player, quest, "quest " .. questId)

	--[[
		A completed daily feeds the weekly that counts them. Bumped after the
		grant so a weekly completing at the same moment cannot re-enter this
		function before the daily is marked.
	]]
	if kind == "daily" then
		QuestService.Bump(player, "dailyQuestsDone", 1)
	end

	Log.info("QuestService", "%s claimed %s quest '%s'", player.Name, kind, questId)
	return true
end

--[[
	docs/05 §7: "reroll 1 per day free". Rerolls a single daily for one that is
	not already active, and costs a use whether or not the player likes the
	result - otherwise it is not one reroll, it is unlimited.
]]
function QuestService.Reroll(player: Player, questId: string): (boolean, string?)
	local data = PlayerDataService.Get(player)
	if not data then
		return false, "profile not loaded"
	end
	if (data.Quests.RerollsUsed or 0) >= QuestConfig.FreeRerollsPerDay then
		return false, "no rerolls left today"
	end

	local state = data.Quests.Daily[questId]
	if not state then
		return false, "not one of yours"
	end
	if state.Claimed then
		return false, "already claimed"
	end

	local candidates = {}
	for _, id in QuestConfig.SortedIds("daily") do
		if not data.Quests.Daily[id] then
			table.insert(candidates, id)
		end
	end
	if #candidates == 0 then
		return false, "nothing else to roll"
	end

	local replacement = candidates[Random.new(os.clock() * 1000):NextInteger(1, #candidates)]

	PlayerDataService.UpdateKeys(player, { "Quests" }, function(profile)
		profile.Quests.Daily[questId] = nil
		profile.Quests.Daily[replacement] = { Progress = 0, Claimed = false }
		profile.Quests.RerollsUsed = (profile.Quests.RerollsUsed or 0) + 1
	end, "quest reroll")

	return true
end

-- ── Wiring ──────────────────────────────────────────────────────────────────

--[[
	Boot check: the Metrics QuestConfig names and the keys of EMITTERS must be
	the same set. Returns an error string, or nil.
]]
function QuestService.ValidateEmitters(): string?
	local declared = {}
	for _, metric in QuestConfig.Metrics do
		declared[metric] = true
		if not EMITTERS[metric] then
			return string.format("metric '%s' is used by a quest but nothing emits it", metric)
		end
	end

	for metric in EMITTERS do
		if not declared[metric] then
			return string.format("emitter '%s' feeds no quest", metric)
		end
	end

	--[[
		And every quest's Metric must be in the declared list. A quest naming a
		metric that is neither declared nor emitted would slip past both loops
		above.
	]]
	for _, kind in { "daily", "weekly" } do
		for id, quest in QuestConfig.Pool(kind) do
			if not declared[quest.Metric] then
				return string.format("quest '%s' names metric '%s', which is not in QuestConfig.Metrics",
					id, quest.Metric)
			end
		end
	end

	return nil
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function QuestService.Init(app)
	PlayerDataService = app.Get("PlayerDataService")
	NotificationService = app.Get("NotificationService")
	--[[
		Owned here because quests are its largest consumer, and exposed as
		`QuestService.RewardGrant` for DailyService and IndexService - the same
		shape `NestService.Zones` uses for ZoneService.
	]]
	RewardGrant = require(script.RewardGrant)
	RewardGrant.Init(app)
	QuestService.RewardGrant = RewardGrant
end

function QuestService.Start(app)
	local problem = QuestService.ValidateEmitters()
	assert(not problem, "[SAD] QuestService: " .. tostring(problem))

	local WeatherService = app.Get("WeatherService")
	local RarityConfig = require(Shared.Config.RarityConfig)

	for metric, emitter in EMITTERS do
		if emitter.Direct then
			continue
		end

		local service = app.Get(emitter.Service)
		local source = if emitter.Zones then service.Zones else service
		local signal = source and source[emitter.Signal]
		if not signal then
			Log.error("QuestService", "Emitter '%s' cannot find %s.%s",
				metric, emitter.Service, emitter.Signal)
			continue
		end

		signal:Connect(function(...)
			local args = { ... }

			--[[
				Server-wide signals fire once with no player, so every player
				present is credited. An event nobody could opt out of is one
				everybody took part in.
			]]
			if emitter.Broadcast then
				for _, player in game:GetService("Players"):GetPlayers() do
					QuestService.Bump(player, metric, 1)
				end
				return
			end

			local player = args[1]
			if typeof(player) ~= "Instance" or not player:IsA("Player") then
				return
			end

			if emitter.Filter and not emitter.Filter(table.unpack(args)) then
				return
			end

			-- "Hatch an egg during special weather" only counts when it is.
			if emitter.Weather and WeatherService.Current() == "clear" then
				return
			end

			-- "Hatch 5 Epic or better" reads the entry the signal carried.
			if emitter.MinRarity then
				local entry = args[3]
				local rarity = entry and entry.Rarity
				if not rarity
					or RarityConfig.RankOf(rarity) < RarityConfig.RankOf(emitter.MinRarity) then
					return
				end
			end

			QuestService.Bump(player, metric, if emitter.Amount then emitter.Amount(...) else 1)
		end)
	end

	PlayerDataService.ProfileLoaded:Connect(function(player)
		QuestService.Refresh(player)
	end)

	Net.OnEvent("RequestClaimQuest", function(player, questId)
		if type(questId) ~= "string" then
			return
		end
		local ok, reason = QuestService.Claim(player, questId)
		if not ok and reason then
			NotificationService.Toast(player, "QUEST", reason)
		end
	end)

	Net.OnEvent("RequestRerollQuest", function(player, questId)
		if type(questId) ~= "string" then
			return
		end
		local ok, reason = QuestService.Reroll(player, questId)
		if not ok and reason then
			NotificationService.Toast(player, "QUEST", reason)
		end
	end)

	--[[
		The day can turn while someone is playing. Checked once a minute rather
		than scheduled to the exact second, because a quest board that refreshes
		up to sixty seconds late is invisible and a mis-scheduled timer is not.
	]]
	task.spawn(function()
		while true do
			task.wait(60)
			for player in PlayerDataService.GetAll() do
				local ok, err = pcall(QuestService.Refresh, player)
				if not ok then
					Log.error("QuestService", "Refresh failed for %s: %s", player.Name, tostring(err))
				end
			end
		end
	end)

	Log.info("QuestService", "Ready. %d daily, %d weekly, %d metrics",
		QuestConfig.Count("daily"), QuestConfig.Count("weekly"), #QuestConfig.Metrics)
end

return QuestService
