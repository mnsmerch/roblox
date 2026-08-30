--!nonstrict
--[[
	EventService
	ServerScriptService/SAD_Server/Services/EventService  (ModuleScript)
	  └── Handlers  (Folder of ModuleScripts)

	The scheduler, and everything four events have in common: countdowns,
	participation, contribution scoreboards, and the rule that nobody who
	turned up leaves with nothing.

	═══ THE HANDLER PATTERN ════════════════════════════════════════════════════
	One ModuleScript per event in `Handlers`, named by EventConfig's `Handler`
	field. Each returns:

		Handler.Start(ctx)    -- build the world, bind the prompts
		Handler.Tick(ctx, dt) -- optional, ~4 Hz
		Handler.Stop(ctx)     -- tear down EVERYTHING it made

	`ctx` carries the event entry, its Params, a Trove that Stop must leave
	empty, `ctx.Get(name)` for other services, and `ctx.Score(player, points)` -
	the only way to record participation. A handler never touches profiles,
	currency or notifications; those are the same for every event and live here.

	Handlers reach other services through `ctx.Get` rather than requiring them,
	so they follow the same injection rule every service does and cannot create
	a load-order dependency of their own.

	ConfigValidator rule 8, written in Step 3 and skipped ever since, asserts
	every `Handler` name resolves to a module in that folder.
	═══════════════════════════════════════════════════════════════════════════

	═══ REWARDS ARE GRANTED ONCE, TO WHOEVER IS STILL HERE ═════════════════════
	docs/13 names "rewards granted twice on a rejoin" as this step's hazard.
	Participation is keyed by the Player OBJECT and lives only in memory for
	the length of one event, so a rejoin is a different key with no score - it
	cannot re-collect. Rewards are paid at the end, in one pass, and the table
	is cleared before anything else can run.
	═══════════════════════════════════════════════════════════════════════════

	API:
		EventService.Current() -> entry?
		EventService.EndsAt() -> os.time()
		EventService.Begin(eventId) -> ok, reason?
		EventService.Stop(reason?)
		EventService.Score(player, points)
		EventService.GetScores() -> { { Name, Score } }   sorted, descending
		EventService.Roll() -> eventId?
		EventService.Started / Ended   Signals

	Depends on: EventConfig, Trove, RNG, Net, NotificationService,
	            EconomyService, PlayerDataService, ParkService, EggService,
	            DinosaurService, NestService, WildAIService.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local Economy = require(Shared.Modules.Economy)
local EventConfig = require(Shared.Config.EventConfig)
local Format = require(Shared.Modules.Format)
local Log = require(Shared.Modules.Log)
local Net = require(Shared.Modules.Net)
local RNG = require(Shared.Modules.RNG)
local Signal = require(Shared.Modules.Signal)
local Trove = require(Shared.Modules.Trove)

local EventService = {}

EventService.Started = Signal.new()
EventService.Ended = Signal.new()

local NotificationService, EconomyService, PlayerDataService
local appRef = nil
local handlers: { [string]: any } = {}

local active = nil -- { Entry, Handler, Ctx, EndsAt, Trove }
local recent: { string } = {} -- most recent first
local scores: { [Player]: number } = {}

local rng = Random.new()
local runtimeFolder: Folder? = nil

local TICK = 0.25

-- ── Participation ───────────────────────────────────────────────────────────

--[[
	Records a contribution. The only way an event says someone took part.

	Additive, so a handler can call it per amber chunk or per dinosaur tagged
	without tracking totals itself.
]]
function EventService.Score(player: Player, points: number)
	if not active or points <= 0 then
		return
	end
	scores[player] = (scores[player] or 0) + points
end

--- Sorted descending, for the scoreboard and for reward tiers.
function EventService.GetScores()
	local list = {}
	for player, score in scores do
		table.insert(list, { Player = player, Name = player.DisplayName, Score = score })
	end
	table.sort(list, function(a, b)
		return a.Score > b.Score
	end)
	return list
end

-- ── Rewards ─────────────────────────────────────────────────────────────────

--[[
	docs/04 §3.1: "Nobody who participates receives nothing. Minimum
	participation reward is always >= 3 minutes of that player's income."

	Measured against THEIR income, not a flat number, so it is still worth
	something at hour six and still generous at minute five. A player earning
	nothing yet gets the floor instead, or the guarantee would pay zero to
	exactly the players it exists for.
]]
local MINIMUM_FLOOR_FOSSILS = 500

local function payout(entry)
	local ranked = EventService.GetScores()
	if #ranked == 0 then
		return ranked
	end

	local top = ranked[1].Score

	for place, row in ranked do
		local data = PlayerDataService.Get(row.Player)
		if not data then
			continue
		end

		local minimum = math.max(
			Economy.ParkIncomeRate(data) * EventConfig.MinRewardIncomeSecs,
			MINIMUM_FLOOR_FOSSILS)

		--[[
			Contribution decides the share above the floor, never whether there
			is one. Scaled against the top score rather than against a fixed
			target, so a quiet server does not pay everyone the minimum.
		]]
		local share = if top > 0 then row.Score / top else 0
		local reward = math.floor(minimum * (1 + share * 3))

		EconomyService.AddFossils(row.Player, reward, "event " .. entry.Id)
		row.Reward = reward
		row.Place = place
	end

	return ranked
end

--- The top-five board docs/04 §3.1 asks every event to end with.
local function scoreboard(entry, ranked)
	local lines = {}
	for place = 1, math.min(EventConfig.ScoreboardSize, #ranked) do
		local row = ranked[place]
		table.insert(lines, string.format("%d. %s", place, row.Name))
	end

	local board = if #lines > 0 then table.concat(lines, "   ") else "Nobody turned up"

	for _, player in Players:GetPlayers() do
		local mine = nil
		for _, row in ranked do
			if row.Player == player then
				mine = row
				break
			end
		end

		NotificationService.Takeover(player, {
			Title = string.upper(entry.DisplayName) .. " OVER",
			Subtitle = board,
			Headline = if mine
				then string.format("#%d  ·  +%s", mine.Place, Format.Number(mine.Reward or 0))
				else "You missed it",
			Duration = 5,
		})
	end
end

-- ── Broadcasting ────────────────────────────────────────────────────────────

local function pushState(player: Player?)
	local payload = if active
		then {
			Event = active.Entry.Id,
			DisplayName = active.Entry.DisplayName,
			Blurb = active.Entry.Blurb,
			EndsAt = active.EndsAt,
			Marker = active.Ctx.MarkerPosition,
		}
		else { Event = nil }

	if player then
		Net.FireClient("EventState", player, payload)
	else
		Net.FireAllClients("EventState", payload)
	end
end

-- ── Lifecycle of one event ──────────────────────────────────────────────────

function EventService.Current()
	return active and active.Entry or nil
end

function EventService.EndsAt(): number
	return active and active.EndsAt or 0
end

function EventService.Begin(eventId: string): (boolean, string?)
	if active then
		return false, "an event is already running"
	end

	local entry = EventConfig.Get(eventId)
	if not entry then
		return false, "no such event"
	end

	local handler = handlers[entry.Handler]
	if not handler then
		return false, "no handler named " .. tostring(entry.Handler)
	end

	local trove = Trove.new()
	local folder = Instance.new("Folder")
	folder.Name = "Event_" .. entry.Id
	folder.Parent = runtimeFolder
	trove:Add(folder)

	local ctx = {
		Entry = entry,
		Params = entry.Params or {},
		Folder = folder,
		Trove = trove,
		Rng = rng,
		Get = appRef and appRef.Get or nil,
		Score = EventService.Score,
		MarkerPosition = nil,
	}

	scores = {}
	active = {
		Entry = entry,
		Handler = handler,
		Ctx = ctx,
		Trove = trove,
		EndsAt = os.time() + entry.DurationSecs,
	}

	local ok, err = pcall(handler.Start, ctx)
	if not ok then
		Log.error("EventService", "%s failed to start: %s", entry.Id, tostring(err))
		trove:Clean()
		active = nil
		return false, "handler errored"
	end

	table.insert(recent, 1, entry.Id)
	if #recent > EventConfig.NoRepeatWithin then
		table.remove(recent)
	end

	pushState()
	NotificationService.All({
		Kind = "banner",
		Text = string.upper(entry.DisplayName) .. "  ·  " .. entry.Blurb,
		Duration = 5,
	})

	EventService.Started:Fire(entry.Id, active.EndsAt)
	Log.info("EventService", "%s started for %s", entry.DisplayName,
		Format.Time(entry.DurationSecs))
	return true
end

function EventService.Stop(reason: string?)
	if not active then
		return
	end

	local entry = active.Entry
	local handler = active.Handler
	local ctx = active.Ctx
	local trove = active.Trove

	--[[
		Stop the handler BEFORE paying out, so nothing it owns can still be
		scoring while the scores are being read.
	]]
	local ok, err = pcall(handler.Stop, ctx)
	if not ok then
		Log.error("EventService", "%s failed to stop cleanly: %s", entry.Id, tostring(err))
	end

	--[[
		The Trove runs whether or not Stop succeeded. A handler that errors
		half way through its teardown must not leave a meteor in the sky
		forever, so the container is what actually guarantees cleanup.
	]]
	trove:Clean()

	--[[
		Paid out and cleared in one step. Nothing between the read and the
		clear can score again, which is what makes double-collection
		structurally impossible rather than merely unlikely.
	]]
	local ranked = if reason ~= "empty" then payout(entry) else {}
	scores = {}
	active = nil

	pushState()
	if reason ~= "empty" and #ranked > 0 then
		scoreboard(entry, ranked)
	end

	EventService.Ended:Fire(entry.Id, reason)
	Log.info("EventService", "%s ended (%s), %d participant(s)",
		entry.DisplayName, reason or "finished", #ranked)
end

-- ── Scheduling ──────────────────────────────────────────────────────────────

--[[
	Picks the next event.

	docs/04 §3's no-repeat-within-3, clamped by EventConfig.ExclusionDepth so
	at least two events stay selectable - with four shipping, a strict
	exclusion of three leaves exactly one, which is a rotation rather than a
	weighted roll.
]]
function EventService.Roll(): string?
	local exclude = {}
	for index = 1, EventConfig.ExclusionDepth() do
		if recent[index] then
			exclude[recent[index]] = true
		end
	end

	local pool = EventConfig.RollableWeights(exclude)
	if next(pool) == nil then
		pool = EventConfig.RollableWeights()
	end

	return RNG.WeightedPick(pool, rng)
end

--[[
	The countdown from docs/04 §3.1: 60 s, 30 s, 10 s, with escalating audio.

	Announced before the event, not with it. A map marker and a minute is what
	turns an event into something players run towards rather than something
	that happens near them.
]]
local function countdown(entry)
	local previous = math.huge
	for _, beat in EventConfig.CountdownBeats do
		local wait = previous - beat
		if wait < math.huge then
			task.wait(wait)
		end
		previous = beat

		NotificationService.All({
			Kind = "banner",
			Text = string.format("%s IN %ds", string.upper(entry.DisplayName), beat),
			Duration = math.min(4, beat),
		})
	end
	task.wait(previous)
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function EventService.Init(app)
	appRef = app
	NotificationService = app.Get("NotificationService")
	EconomyService = app.Get("EconomyService")
	PlayerDataService = app.Get("PlayerDataService")

	local runtime = Workspace:FindFirstChild("SAD_Runtime")
	if not runtime then
		runtime = Instance.new("Folder")
		runtime.Name = "SAD_Runtime"
		runtime.Parent = Workspace
	end
	runtimeFolder = Instance.new("Folder")
	runtimeFolder.Name = "Events"
	runtimeFolder.Parent = runtime
end

--[[
	`Start(app)` belongs to Bootstrap's lifecycle, so the public "start an
	event" function is `Begin` - exactly the collision IncubationService hit in
	Step 11 (deviation #31) and resolved the same way. One function cannot be
	both the lifecycle hook and the public API, and the lifecycle keeps the
	name because Bootstrap looks for it by name.
]]
function EventService.Start(app)
	--[[
		Handlers are discovered rather than listed, so adding an event is a
		config entry plus a module - never an edit here.
	]]
	local folder = script:FindFirstChild("Handlers")
	if folder then
		for _, module in folder:GetChildren() do
			if module:IsA("ModuleScript") then
				local ok, handler = pcall(require, module)
				if ok and type(handler) == "table" and handler.Start and handler.Stop then
					handlers[module.Name] = handler
				else
					Log.error("EventService", "Handler '%s' is not usable", module.Name)
				end
			end
		end
	end

	for _, entry in EventConfig.Events do
		if entry.InV1 and not handlers[entry.Handler] then
			Log.error("EventService", "Event '%s' names handler '%s', which is missing",
				entry.Id, entry.Handler)
		end
	end

	Net.OnEvent("RequestEventAction", function(player, eventId, action, payload)
		if not active or type(eventId) ~= "string" or type(action) ~= "string" then
			return
		end
		if eventId ~= active.Entry.Id then
			return
		end
		local handler = active.Handler
		if type(handler.Action) == "function" then
			local ok, err = pcall(handler.Action, active.Ctx, player, action, payload)
			if not ok then
				Log.error("EventService", "%s action failed: %s", eventId, tostring(err))
			end
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		-- docs/13: "a player joining mid-event sees correct state".
		pushState(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		scores[player] = nil
	end)

	--[[
		The tick. Drives the running handler and enforces the two rules that
		end an event: its duration, and docs/13's hazard of one continuing
		after the last participant leaves.
	]]
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(TICK)
			local now = os.clock()
			local dt = now - last
			last = now

			if not active then
				continue
			end

			if EventConfig.EndWhenEmpty and #Players:GetPlayers() == 0 then
				EventService.Stop("empty")
				continue
			end

			if os.time() >= active.EndsAt then
				EventService.Stop("finished")
				continue
			end

			if type(active.Handler.Tick) == "function" then
				local ok, err = pcall(active.Handler.Tick, active.Ctx, dt)
				if not ok then
					Log.error("EventService", "%s tick failed: %s", active.Entry.Id, tostring(err))
				end
			end
		end
	end)

	--[[
		The scheduler. Sleeps a randomised 12-18 minutes, announces, fires, and
		waits for the event to finish before starting the next gap - which is
		what makes "never overlapping" structural rather than a check.
	]]
	task.spawn(function()
		while true do
			local gap = rng:NextInteger(EventConfig.MinGapSecs, EventConfig.MaxGapSecs)
			task.wait(gap - EventConfig.CountdownSecs)

			if #Players:GetPlayers() == 0 then
				continue
			end

			local eventId = EventService.Roll()
			if not eventId then
				continue
			end

			local entry = EventConfig.Get(eventId)
			countdown(entry)
			EventService.Begin(eventId)

			while active do
				task.wait(1)
			end
		end
	end)

	Log.info("EventService", "Ready. %d event(s), every %s-%s",
		EventConfig.Count(), Format.Time(EventConfig.MinGapSecs),
		Format.Time(EventConfig.MaxGapSecs))
end

return EventService
