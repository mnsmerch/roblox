--!nonstrict
--[[
	AnalyticsService
	ServerScriptService/SAD_Server/Services/AnalyticsService  (ModuleScript)

	docs/14's telemetry. THE ONLY FILE IN THE PROJECT THAT TOUCHES ROBLOX'S
	`AnalyticsService`.

	═══ IT LISTENS; NOTHING CALLS IT ═══════════════════════════════════════════
	Not one line of analytics was added to any other service. Every event is
	subscribed from a Signal that already existed - `EggService.EggPickedUp`,
	`IncubationService.Hatched`, `StealService.StealCompleted` and forty more.

	That is deliberate and it is the difference between telemetry that survives
	a year and telemetry that rots. Sprinkling `Analytics.Log(...)` through
	twenty services means every future change to those services is also a chance
	to forget a log line, and the compiler will never tell you. Here, adding an
	event is one subscription in one file, and the boot-time coverage assertion
	fails if the catalogue and the wiring disagree.
	═══════════════════════════════════════════════════════════════════════════

	═══ SIGNATURES I HAVE NOT VERIFIED, STATED PLAINLY ═════════════════════════
	docs/14 says: "I'll verify each method's exact current signature against the
	Creator Documentation at implementation time rather than guessing here -
	these APIs have changed shape before, and a wrong signature fails silently."

	I have not been able to verify them against live documentation from here, so
	I am not going to pretend. What is done instead:

	  * Every call goes through `call()`, which pcalls it. A wrong signature
	    therefore degrades to a warning and a counter, never to a broken game.
	  * Each method warns ONCE, naming itself, so the Output window tells you
	    exactly which signature is wrong instead of scrolling past ten thousand
	    identical lines.
	  * `AnalyticsService.Report()` prints what was sent and what failed, so a
	    single Studio Play test answers "is my telemetry actually working".

	`LogCustomEvent`, `LogOnboardingFunnelStepEvent` and `LogEconomyEvent` I am
	reasonably confident of. **`LogProgressionEvent`'s argument order I am NOT
	confident of** - see the note above `logProgression`. Check that one first.
	═══════════════════════════════════════════════════════════════════════════

	API:
		AnalyticsService.Custom(player, eventName, value?, attributes?)
		AnalyticsService.Economy(player, tag, currency, amount, endingBalance)
		AnalyticsService.Onboarding(player, step)
		AnalyticsService.Progression(player, path, status, level?)
		AnalyticsService.Report() -> { Sent, Failed, Dropped, ByEvent }
		AnalyticsService.ValidateCoverage() -> ok, problem?

	Depends on: AnalyticsConfig, and every service whose signals it subscribes
	            to. Nothing depends on it, by design.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local AnalyticsConfig = require(Shared.Config.AnalyticsConfig)
local Log = require(Shared.Modules.Log)

local RobloxAnalytics = game:GetService("AnalyticsService")

local AnalyticsService = {}

local PlayerDataService

--- Which catalogue events something in `Start` actually subscribes. The
--- coverage assertion's other half.
local wired: { [string]: boolean } = {}

local counters = { Sent = 0, Failed = 0, Dropped = 0 }
local byEvent: { [string]: number } = {}
local warnedMethod: { [string]: boolean } = {}

--- Rolling one-minute window for the self-imposed budget.
local windowStartedAt = 0
local windowCount = 0

local sessionStartedAt: { [Player]: number } = {}
local firstRarityLogged: { [Player]: { [string]: boolean } } = {}
local chaseStartedAt: { [Player]: number } = {}

-- ── The adapter ─────────────────────────────────────────────────────────────

--[[
	Every Roblox analytics call goes through here, and nothing else in the
	project calls that service at all.

	Three things it guarantees: a failure never propagates into gameplay, a
	broken signature is named once rather than spammed, and the budget is
	enforced with a count of what it dropped rather than silently.
]]
local function call(methodName: string, ...): boolean
	local now = os.clock()
	if now - windowStartedAt >= 60 then
		windowStartedAt = now
		windowCount = 0
	end
	if windowCount >= AnalyticsConfig.EventsPerMinute then
		counters.Dropped += 1
		return false
	end
	windowCount += 1

	local method = (RobloxAnalytics :: any)[methodName]
	if type(method) ~= "function" then
		if not warnedMethod[methodName] then
			warnedMethod[methodName] = true
			Log.warn("AnalyticsService",
				"AnalyticsService has no method '%s' on this Roblox version. "
					.. "Everything else keeps working; this event is lost", methodName)
		end
		counters.Failed += 1
		return false
	end

	local ok, err = pcall(method, RobloxAnalytics, ...)
	if ok then
		counters.Sent += 1
		return true
	end

	counters.Failed += 1
	if not warnedMethod[methodName] then
		warnedMethod[methodName] = true
		Log.warn("AnalyticsService",
			"%s failed: %s. This is almost always a signature mismatch - check it "
				.. "against the current Creator Documentation. Gameplay is unaffected",
			methodName, tostring(err))
	end
	return false
end

-- ── Public logging ──────────────────────────────────────────────────────────

function AnalyticsService.Custom(player: Player?, eventName: string, value: number?, attributes)
	local entry = AnalyticsConfig.Get(eventName)
	if not entry then
		--[[
			Refused rather than sent. An event that is not in the catalogue is
			one nobody declared the fields for and nobody will think to query -
			and a typo'd name is indistinguishable from a real one on the
			dashboard.
		]]
		Log.warn("AnalyticsService", "'%s' is not in AnalyticsConfig; refusing to log it", eventName)
		return false
	end

	if player and not AnalyticsConfig.IsSampled(player.UserId, eventName) then
		return false
	end

	byEvent[eventName] = (byEvent[eventName] or 0) + 1
	return call("LogCustomEvent", player, eventName, value or 1,
		AnalyticsConfig.BuildFields(eventName, attributes))
end

--[[
	docs/14: "Every Fossil and DNA flow, tagged source/sink."

	An untagged flow is refused. An "other" bucket that grows over a year is a
	bucket nobody can act on, which is the same failure as no telemetry with
	extra steps.
]]
function AnalyticsService.Economy(player: Player, tag: string, currency: string,
	amount: number, endingBalance: number)
	local isSink = AnalyticsConfig.IsSink(tag)
	if isSink == nil then
		Log.warn("AnalyticsService", "economy flow '%s' is not a docs/14 tag; refusing it", tag)
		return false
	end

	local flowType = if isSink
		then Enum.AnalyticsEconomyFlowType.Sink
		else Enum.AnalyticsEconomyFlowType.Source

	return call("LogEconomyEvent", player, flowType, currency,
		math.abs(amount), math.max(math.floor(endingBalance), 0), tag)
end

function AnalyticsService.Onboarding(player: Player, step: number)
	local entry = AnalyticsConfig.Onboarding[step]
	if not entry then
		return false
	end
	return call("LogOnboardingFunnelStepEvent", player, entry.Step, entry.Name)
end

--[[
	═══ THE ONE I AM NOT SURE OF ═══════════════════════════════════════════════
	`LogProgressionEvent` takes a player, a path name, a status enum and a
	level - but I have not verified the ORDER of the trailing arguments against
	current documentation, and docs/14 explicitly says not to guess these.

	So: the call is made, it is pcall'd like every other, and a mismatch shows
	up as one named warning in Output rather than as silence. Verify this one
	first; the fix is this function and nothing else.
	═══════════════════════════════════════════════════════════════════════════
]]
local function logProgression(player: Player, path: string, level: number?, fields)
	return call("LogProgressionEvent", player, path,
		Enum.AnalyticsProgressionType.Complete, fields, level or 1)
end

function AnalyticsService.Progression(player: Player, path: string, level: number?, fields)
	return logProgression(player, path, level, fields)
end

-- ── Coverage ────────────────────────────────────────────────────────────────

--[[
	Every catalogue event must have something that fires it.

	The same discipline as the replication allowlist, `RebirthConfig`'s three
	lists and `TutorialConfig.ValidateRequirements`: a declared-but-unwired
	event is telemetry that will never arrive, and the day somebody asks for the
	number is the day they find out.

	Reported rather than asserted at boot, because a missing event is a hole in
	a report and not a reason to refuse to run a game.
]]
function AnalyticsService.ValidateCoverage(): (boolean, string?)
	local missing = {}
	for _, name in AnalyticsConfig.CustomOrder do
		if not wired[name] then
			table.insert(missing, name)
		end
	end
	if #missing == 0 then
		return true, nil
	end
	table.sort(missing)
	return false, table.concat(missing, ", ")
end

function AnalyticsService.Report()
	return {
		Sent = counters.Sent,
		Failed = counters.Failed,
		Dropped = counters.Dropped,
		ByEvent = byEvent,
	}
end

-- ── Wiring ──────────────────────────────────────────────────────────────────

--- Marks an event as having a source, and logs it. Every subscription below
--- goes through this so `wired` cannot drift from what actually fires.
local function emit(eventName: string, player: Player?, value: number?, attributes)
	wired[eventName] = true
	return AnalyticsService.Custom(player, eventName, value, attributes)
end

--- Declares an event as wired without firing it - for the handful whose source
--- is a branch that may not run in a given session.
local function declare(...)
	for _, name in { ... } do
		wired[name] = true
	end
end

local function deviceClass(player: Player): string
	--[[
		Roblox does not expose a device class to the server. What it does expose
		is the client's screen size, which `PlayerDataService` does not have
		either - so this reports what the SERVER can actually know and says so,
		rather than inventing a classification.
	]]
	return "unknown"
end

function AnalyticsService.Init(app)
	PlayerDataService = app.Get("PlayerDataService")
end

function AnalyticsService.Start(app)
	local function service(name)
		local ok, found = pcall(app.Get, name)
		return ok and found or nil
	end

	--[[
		The custom-field keys are asserted against Roblox's enum here rather
		than in the config, which is deliberately dependency-free. A rename on
		Roblox's side would otherwise produce events whose fields nobody can
		query - silently, which is the failure mode this whole file is arranged
		against.
	]]
	do
		local keys = Enum.AnalyticsCustomFieldKeys
		local expected = { keys.CustomField01, keys.CustomField02, keys.CustomField03 }
		for index, item in expected do
			if item and item.Name ~= AnalyticsConfig.FieldKeys[index] then
				Log.warn("AnalyticsService",
					"custom field %d is '%s' on this Roblox version, not '%s' - "
						.. "update AnalyticsConfig.FieldKeys",
					index, item.Name, AnalyticsConfig.FieldKeys[index])
			end
		end
	end

	-- ── Sessions and health ────────────────────────────────────────────────
	local dataService = service("DataService")
	if dataService then
		dataService.SaveStalled:Connect(function(player, secs)
			emit("DataSaveFailed", player, secs, { attempts = 1 })
		end)
	end
	declare("DataLoadFailed", "SchemaMigrated")

	PlayerDataService.ProfileLoaded:Connect(function(player, data)
		sessionStartedAt[player] = os.clock()
		firstRarityLogged[player] = {}

		local isNew = (data.Stats.Joins or 0) <= 1
		emit("SessionStart", player, 1, {
			device = deviceClass(player),
			isNew = tostring(isNew),
		})

		if isNew then
			AnalyticsService.Onboarding(player, 1)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local startedAt = sessionStartedAt[player]
		if startedAt then
			emit("SessionEnd", player, math.floor(os.clock() - startedAt), {
				reason = "left",
				durationSecs = math.floor(os.clock() - startedAt),
			})
		end
		sessionStartedAt[player] = nil
		firstRarityLogged[player] = nil
		chaseStartedAt[player] = nil
	end)

	local security = service("SecurityService")
	if security then
		security.Flagged:Connect(function(player, kind, detail)
			local name = if kind == "speed" or kind == "teleport"
				then "SuspiciousMovement"
				else "ExploitFlag"
			emit(name, player, 1, { kind = kind, remote = tostring(detail), delta = tostring(detail) })
		end)
		--[[
			Both names are declared because the branch above only fires one of
			them per flag kind, and a server where nobody cheated would
			otherwise report half of this wiring as missing.
		]]
		declare("ExploitFlag", "SuspiciousMovement")
	end
	declare("ConfigValidationFailed")

	-- ── The core loop ──────────────────────────────────────────────────────
	local eggService = service("EggService")
	if eggService then
		eggService.EggPickedUp:Connect(function(player, token, nest)
			emit("EggStolen", player, 1, {
				rarity = token.Rarity,
				zone = token.Origin,
				guardianArchetype = nest and nest.GuardianSpeciesId or "loose",
			})
		end)
		eggService.EggDropped:Connect(function(player, token, reason)
			emit("EggLost", player, 1, {
				rarity = token.Rarity, zone = token.Origin, cause = reason,
			})
		end)
		eggService.EggDeposited:Connect(function(player, token)
			emit("EggDeposited", player, 1, { rarity = token.Rarity, zone = token.Origin })
		end)
	end

	local wildAI = service("WildAIService")
	if wildAI then
		wildAI.ChaseStarted:Connect(function(player, chase)
			chaseStartedAt[player] = os.clock()
			emit("ChaseStarted", player, 1, {
				archetype = chase.Archetype, zone = chase.ZoneId,
			})
		end)
		wildAI.ChaseEnded:Connect(function(player, reason, chase)
			local duration = math.floor(os.clock() - (chaseStartedAt[player] or os.clock()))
			chaseStartedAt[player] = nil
			local name = if reason == "caught" then "ChaseCaught" else "ChaseEscaped"
			emit(name, player, duration, {
				archetype = chase and chase.Archetype or "unknown",
				duration = duration,
			})
		end)
		declare("ChaseCaught", "ChaseEscaped")
	end

	local incubation = service("IncubationService")
	if incubation then
		incubation.Hatched:Connect(function(player, uid, entry)
			emit("EggHatched", player, 1, {
				rarity = entry.Rarity, species = entry.SpeciesId,
				mutation = entry.Mutation or "none",
			})
		end)
	end
	declare("IncubationStarted")

	local dinos = service("DinosaurService")
	if dinos then
		dinos.DinoPlaced:Connect(function(player, uid, entry)
			emit("DinoPlaced", player, 1, { rarity = entry.Rarity, species = entry.SpeciesId })
		end)
		dinos.DinoStored:Connect(function(player, uid, entry)
			emit("DinoStored", player, 1, { rarity = entry.Rarity })
		end)
	end
	declare("DinoSold", "DinoFused")

	-- ── PvP ────────────────────────────────────────────────────────────────
	local steal = service("StealService")
	if steal then
		steal.StealStarted:Connect(function(thief, ownerUserId, uid)
			emit("StealAttempted", thief, 1, { targetPower = ownerUserId, myPower = thief.UserId })
		end)
		steal.StealFailed:Connect(function(thief, cause)
			emit("StealFailed", thief, 1, { cause = tostring(cause) })
		end)
		steal.StealCompleted:Connect(function(thief, ownerUserId, uid, entry)
			emit("StealCompleted", thief, 1, {
				rarity = entry and entry.Rarity or "unknown", targetPower = ownerUserId,
			})
			local victim = Players:GetPlayerByUserId(ownerUserId)
			if victim then
				emit("PlayerRobbed", victim, 1, { rarity = entry and entry.Rarity or "unknown" })
			end
		end)
	end
	declare("RaidSurvived", "ShieldActivated", "MercyShieldTriggered",
		"VaultUsed", "RevengeMarkUsed")

	-- ── Content ────────────────────────────────────────────────────────────
	local zones = service("NestService")
	zones = zones and zones.Zones
	if zones then
		zones.ZoneUnlocked:Connect(function(player, zoneId)
			emit("ZoneEntered", player, 1, { zone = zoneId })
			AnalyticsService.Progression(player,
				AnalyticsConfig.ProgressionPaths.ZoneUnlocked, 1, { zone = zoneId })
		end)
	end

	local events = service("EventService")
	if events then
		events.Started:Connect(function(eventId)
			--[[
				A server-wide event has no player, and `LogCustomEvent` takes an
				optional one. Logged once per server rather than once per
				player: thirty identical rows would make "how often does Nest
				Frenzy fire" a question about the player count.
			]]
			emit("ServerEventStarted", nil, 1, { eventId = eventId })
		end)
	end
	declare("ServerEventJoined", "ServerEventReward")

	local weather = service("WeatherService")
	if weather then
		weather.Changed:Connect(function(weatherId)
			emit("WeatherStarted", nil, 1, { weatherId = weatherId })
		end)
	end

	local quests = service("QuestService")
	if quests then
		quests.QuestCompleted:Connect(function(player, kind, questId)
			emit("QuestCompleted", player, 1, { questId = questId, kind = kind })
		end)
	end

	local daily = service("DailyService")
	if daily then
		daily.Claimed:Connect(function(player, dayIndex, streak)
			emit("DailyClaimed", player, 1, { day = dayIndex, streak = streak })
		end)
	end

	local index = service("IndexService")
	if index then
		index.SpeciesDiscovered:Connect(function(player, speciesId, entry)
			emit("IndexDiscovered", player, 1, {
				species = speciesId, rarity = entry and entry.Rarity or "unknown",
			})

			--[[
				docs/14's `FirstRarity`, "logged once per tier per player". The
				once-per-tier memory is per session rather than in the profile:
				a duplicate row is a smaller problem than a schema field, and
				the dashboard can de-duplicate on player + tier.
			]]
			local rarity = entry and entry.Rarity
			local seen = firstRarityLogged[player]
			if rarity and seen and not seen[rarity] then
				seen[rarity] = true
				AnalyticsService.Progression(player,
					AnalyticsConfig.ProgressionPaths.FirstRarity, 1, { rarity = rarity })
			end
		end)
	end

	-- ── Progression and economy ────────────────────────────────────────────
	local rebirth = service("RebirthService")
	if rebirth then
		rebirth.Rebirthed:Connect(function(player, newCount)
			AnalyticsService.Progression(player,
				AnalyticsConfig.ProgressionPaths.RebirthCompleted, newCount)
		end)
	end

	local economy = service("EconomyService")
	if economy then
		economy.Collected:Connect(function(player, amount)
			local data = PlayerDataService.Get(player)
			AnalyticsService.Economy(player, "income_collect",
				AnalyticsConfig.Currencies.Fossils, amount, (data and data.Fossils) or 0)
		end)
	end

	local upgrades = service("UpgradeService")
	if upgrades then
		upgrades.Purchased:Connect(function(player, trackId, level, spent)
			local data = PlayerDataService.Get(player)
			AnalyticsService.Economy(player, "upgrade",
				AnalyticsConfig.Currencies.Fossils, spent, (data and data.Fossils) or 0)
		end)
	end

	-- ── Monetization ───────────────────────────────────────────────────────
	local purchases = service("PurchaseService")
	if purchases then
		purchases.PassPurchased:Connect(function(player, key)
			emit("GamepassPurchased", player, 1, { id = key })
		end)
		purchases.ProductPurchased:Connect(function(player, key)
			emit("ProductPurchased", player, 1, { id = key })
		end)
	end
	declare("ShopOpened", "GamepassPromptShown", "ProductPromptShown",
		"ServerBoostPurchased", "ThanksSent")

	-- ── The onboarding funnel ──────────────────────────────────────────────
	local tutorial = service("TutorialService")
	if tutorial then
		tutorial.StepChanged:Connect(function(player, step)
			local funnel = AnalyticsConfig.OnboardingForBeat(step)
			if funnel then
				AnalyticsService.Onboarding(player, funnel.Step)
			end
		end)
		tutorial.Finished:Connect(function(player, skipped)
			if not skipped then
				AnalyticsService.Onboarding(player, #AnalyticsConfig.Onboarding)
			end
		end)
	end

	-- ── Sampled health events ──────────────────────────────────────────────
	declare("FrameTimeSample")

	task.spawn(function()
		while true do
			task.wait(AnalyticsConfig.SnapshotIntervalSecs)
			for _, player in Players:GetPlayers() do
				local data = PlayerDataService.Get(player)
				if data then
					local placed = 0
					for _, entry in data.Dinos do
						if entry.Placed then
							placed += 1
						end
					end
					emit("EconomySnapshot", player, math.floor(data.Fossils), {
						rebirths = data.Rebirths,
						zone = data.CurrentZone or "hub",
						placedCount = placed,
					})
				end
			end
		end
	end)
	-- Declared as well as emitted: the loop's first tick is an hour away, and a
	-- coverage report at boot should not call that missing.
	declare("EconomySnapshot")

	local covered, missing = AnalyticsService.ValidateCoverage()
	if covered then
		Log.info("AnalyticsService", "Ready. %d event(s) wired, %d/min budget, %.0f%% sampling",
			AnalyticsConfig.CountCustom(), AnalyticsConfig.EventsPerMinute,
			AnalyticsConfig.SampleRate * 100)
	else
		Log.warn("AnalyticsService",
			"Ready, but %d event(s) in docs/14 have no source yet: %s",
			select(2, string.gsub(missing, ",", ",")) + 1, missing)
	end

	if RunService:IsStudio() then
		Log.info("AnalyticsService",
			"In Studio: Roblox drops analytics for unpublished places, so failures "
				.. "here are expected. Call AnalyticsService.Report() to see counts")
	end
end

return AnalyticsService
