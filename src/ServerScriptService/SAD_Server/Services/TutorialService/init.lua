--!nonstrict
--[[
	TutorialService
	ServerScriptService/SAD_Server/Services/TutorialService  (ModuleScript)

	The server half of docs/00 §3's FTUE: it owns the step number, checks every
	advance against what the player has actually done, and pays out the two
	grants the tutorial promises.

	═══ THE STEP NUMBER IS SERVER STATE ════════════════════════════════════════
	`RequestTutorialStep` carries a step number and nothing else. It is not a
	command; it is the client saying "I think I finished that one". The server
	checks it against real state - is the egg actually being carried, is a chase
	actually running, is a dinosaur actually placed - and refuses otherwise.

	Without that check, a client could ask for step 12, be marked complete, and
	take the completion grant without having played. That is a small exploit
	with a large consequence: `Tutorial.Completed` is the metric docs/00 targets
	at >80%, so a fakeable one makes the number meaningless as well as the grant
	free.
	═══════════════════════════════════════════════════════════════════════════

	═══ IT DRIVES, IT DOES NOT BYPASS ══════════════════════════════════════════
	This service starts nothing. It does not spawn a special egg, run a scripted
	chase, or hatch anything itself. The player takes a real egg from a real
	nest and is chased by a real guardian; `TutorialConfig`'s four pure
	functions are consulted by `EggService`, `IncubationService` and
	`WildAIService` at the points they already compute those numbers.

	What this service does is watch, record, and pay.
	═══════════════════════════════════════════════════════════════════════════

	API:
		TutorialService.State(player) -> { Step, Completed, SkippedAt }?
		TutorialService.Advance(player, toStep) -> ok, reason?
		TutorialService.Skip(player) -> ok, reason?
		TutorialService.Facts(player) -> facts        what the server can prove
		TutorialService.IsActive(player) -> boolean
		TutorialService.ValidateFacts()               asserted at Start
		TutorialService.StepChanged  Signal(player, step, beat?)
		TutorialService.Finished     Signal(player, skipped)

	Depends on: TutorialConfig, UpgradeConfig, PlayerDataService, EggService,
	            WildAIService, ParkService, EconomyService, QuestService (for
	            RewardGrant), Net, Log, Signal.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local Log = require(Shared.Modules.Log)
local Net = require(Shared.Modules.Net)
local Signal = require(Shared.Modules.Signal)
local TutorialConfig = require(Shared.Config.TutorialConfig)
local UpgradeConfig = require(Shared.Config.UpgradeConfig)

local TutorialService = {}

TutorialService.StepChanged = Signal.new()
TutorialService.Finished = Signal.new()

local PlayerDataService, EggService, WildAIService, ParkService
local EconomyService, RewardGrant

--[[
	Set the moment a chase starts for a player mid-tutorial. Server memory, not
	profile: beat 5's requirement is "a chase happened", and a chase that ended
	two seconds ago still satisfies it - but a rejoin should not.

	Not stored in the profile for the same reason carry tokens are not: it
	describes a moment in this session, and a profile field would let a
	disconnect at the wrong instant carry a stale claim forward.
]]
local wasChased: { [Player]: boolean } = {}

--- Whether this player has collected banked income this session (beat 10).
local hasCollected: { [Player]: boolean } = {}

-- ── State ───────────────────────────────────────────────────────────────────

function TutorialService.State(player: Player)
	local data = PlayerDataService.Get(player)
	return data and data.Tutorial
end

function TutorialService.IsActive(player: Player): boolean
	return TutorialConfig.IsActive(PlayerDataService.Get(player))
end

--[[
	Everything the server can prove about this player right now.

	Every key here is a requirement some beat names, and `ValidateFacts` asserts
	the two sets match at boot - a beat requiring something nothing computes
	would deadlock the tutorial at that step with no error anywhere.

	Split into a pure half (this) and a live half (`Facts` below) so the key
	list exists in exactly one place. `ValidateFacts` enumerates it by calling
	this with an empty profile, which is the only way the two sets can agree by
	actually agreeing rather than by somebody remembering a second list.
]]
function TutorialService.FactsFrom(data, live)
	live = live or {}

	local placed = false
	local owns = false
	for _, entry in data.Dinos or {} do
		owns = true
		if entry.Placed then
			placed = true
			break
		end
	end

	local incubating = false
	for _, slot in data.Incubators or {} do
		if slot and slot.EggUid then
			incubating = true
			break
		end
	end

	local upgraded = false
	for _, level in data.Upgrades or {} do
		if (level or 0) > 0 then
			upgraded = true
			break
		end
	end

	return {
		inZone = live.inZone == true,
		carrying = live.carrying == true,
		chased = live.chased == true,
		home = live.home == true,
		incubating = incubating,
		hatched = owns,
		placed = placed,
		collected = live.collected == true,
		upgraded = upgraded,
	}
end

--- The live half: everything that comes from where the player is standing and
--- what has happened to them this session, rather than from the profile.
function TutorialService.Facts(player: Player)
	local data = PlayerDataService.Get(player)
	if not data then
		return {}
	end
	return TutorialService.FactsFrom(data, {
		inZone = ParkService.GetOccupiedPark(player) == nil,
		carrying = EggService.GetCarryCount(player) > 0,
		chased = wasChased[player] == true or WildAIService.IsChasing(player),
		home = ParkService.IsInsideOwnPark(player),
		collected = hasCollected[player] == true,
	})
end

--- Asserted at Start. See TutorialConfig.ValidateRequirements.
function TutorialService.ValidateFacts(): (boolean, string?)
	local known = {}
	for key in TutorialService.FactsFrom({}, {}) do
		known[key] = true
	end
	return TutorialConfig.ValidateRequirements(known)
end

-- ── Advancing ───────────────────────────────────────────────────────────────

local function push(player: Player)
	local state = TutorialService.State(player)
	if not state then
		return
	end
	Net.FireClient("TutorialState", player, {
		Step = state.Step,
		Completed = state.Completed,
		Skipped = state.SkippedAt ~= nil,
	})
end

--[[
	Beat 11's top-up, paid on ENTERING step 11 rather than on completing it.

	docs/00: "first upgrade costs exactly what you now have". Paid through
	`EconomyService.AddFossils` like every other grant, so it appears in the
	same balance, the same replication and the same analytics as anything else.
]]
local function payTopUp(player: Player)
	local data = PlayerDataService.Get(player)
	if not data then
		return
	end
	local cost = UpgradeConfig.CostOf(TutorialConfig.FirstUpgradeId, 1)
	local topUp = TutorialConfig.TopUpFor(data, cost)
	if topUp > 0 then
		EconomyService.AddFossils(player, topUp, "tutorial top-up")
		Log.info("TutorialService", "%s topped up %d to afford the first upgrade",
			player.Name, topUp)
	end
end

local function finish(player: Player, skipped: boolean)
	PlayerDataService.UpdateKeys(player, { "Tutorial" }, function(profile)
		profile.Tutorial.Completed = not skipped
		if skipped then
			profile.Tutorial.SkippedAt = os.time()
		end
		profile.Tutorial.Step = TutorialConfig.StepCount
	end, if skipped then "tutorial skipped" else "tutorial complete")

	PlayerDataService.Save(player, "tutorial finished")
	push(player)
	TutorialService.Finished:Fire(player, skipped)

	Log.info("TutorialService", "%s %s the tutorial",
		player.Name, if skipped then "skipped" else "finished")
end

function TutorialService.Advance(player: Player, toStep: number): (boolean, string?)
	local data = PlayerDataService.Get(player)
	if not data then
		return false, "profile not loaded"
	end

	local allowed, reason = TutorialConfig.CanAdvance(data, toStep, TutorialService.Facts(player))
	if not allowed then
		return false, reason
	end

	PlayerDataService.UpdateKeys(player, { "Tutorial" }, function(profile)
		profile.Tutorial.Step = toStep
	end, "tutorial step")

	-- Entering the upgrade beat is where the top-up lands, so the board the
	-- client is about to open already shows an affordable row.
	if toStep == 11 then
		payTopUp(player)
	end

	push(player)
	TutorialService.StepChanged:Fire(player, toStep, TutorialConfig.Get(toStep))

	--[[
		The last beat has nothing to do, so reaching it IS finishing. A twelfth
		"press to continue" would be one more thing between the player and the
		game they came for.
	]]
	if toStep >= TutorialConfig.StepCount then
		finish(player, false)
	end

	return true, nil
end

--[[
	docs/00 §3: "He is skippable at any time... If a player skips, they still
	receive the tutorial egg in their inventory."

	The egg is granted rather than the tutorial being silently abandoned,
	because a player who skips has still been promised their first egg and the
	promise is what makes skipping safe to offer.
]]
function TutorialService.Skip(player: Player): (boolean, string?)
	local data = PlayerDataService.Get(player)
	if not data then
		return false, "profile not loaded"
	end
	if not TutorialConfig.IsActive(data) then
		return false, "nothing to skip"
	end

	if TutorialConfig.SkipGrantsEgg then
		--[[
			Granted only if the tutorial has not already produced one. A player
			who skips at beat 6 is carrying the egg it gave them, one who skips
			at beat 9 has already hatched it, and a second egg for either is a
			duplication bug wearing a tutorial hat.
		]]
		local hasEgg = EggService.GetCarryCount(player) > 0 or next(data.Eggs) ~= nil
		if not hasEgg then
			for _ in data.Dinos do
				hasEgg = true
				break
			end
		end
		if not hasEgg then
			--[[
				Through `RewardGrant`, Step 19's "one place a reward is paid
				out" - so the storage cap, the notification and the analytics
				are the same ones every other granted egg goes through.
			]]
			RewardGrant.Give(player, { Egg = TutorialConfig.ForcedFirstRarity }, "tutorial skip")
		end
	end

	finish(player, true)
	return true, nil
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function TutorialService.Init(app)
	PlayerDataService = app.Get("PlayerDataService")
	EggService = app.Get("EggService")
	WildAIService = app.Get("WildAIService")
	ParkService = app.Get("ParkService")
	EconomyService = app.Get("EconomyService")
end

function TutorialService.Start(app)
	RewardGrant = app.Get("QuestService").RewardGrant

	--[[
		A beat requiring something nothing computes deadlocks the tutorial there
		with no error - the same class of hole ConfigValidator's rule 11 and
		QuestService.ValidateEmitters were added for. Asserted at boot so it
		cannot reach a live server.
	]]
	local factsOk, factsProblem = TutorialService.ValidateFacts()
	assert(factsOk, "TutorialService: " .. tostring(factsProblem))

	Net.OnEvent("RequestTutorialStep", function(player, step)
		if type(step) ~= "number" then
			return
		end
		step = math.floor(step)

		--[[
			Step 0 is the skip signal. Overloading the existing remote rather
			than adding a second one: the rate limit, the argument validation
			and the handler are already here, and a `RequestTutorialSkip` would
			be a second remote carrying no argument at all.
		]]
		if step == 0 then
			TutorialService.Skip(player)
			return
		end

		local ok, reason = TutorialService.Advance(player, step)
		if not ok then
			--[[
				Not an error and not a violation: the client asks optimistically
				and the server is the one that knows. Logged at debug so a
				genuinely stuck tutorial is diagnosable without filling Output
				during ordinary play.
			]]
			Log.debug("TutorialService", "%s asked for step %d: %s",
				player.Name, step, tostring(reason))
			-- Re-pushed so a client that got ahead of itself snaps back.
			push(player)
		end
	end)

	--[[
		The two facts that are moments rather than states. Both are session
		memory, cleared on leave.
	]]
	WildAIService.ChaseStarted:Connect(function(player)
		wasChased[player] = true
	end)

	EconomyService.Collected:Connect(function(player)
		hasCollected[player] = true
	end)

	Players.PlayerRemoving:Connect(function(player)
		wasChased[player] = nil
		hasCollected[player] = nil
	end)

	--[[
		docs/13's resume test: "Disconnect at step 6 and rejoin -> resumes at
		step 6." Nothing special is needed for that - the step is in the
		profile - but the client has to be TOLD, and a client that joins before
		this service is listening would never hear.
	]]
	PlayerDataService.ProfileLoaded:Connect(function(player)
		push(player)
	end)
	for _, player in Players:GetPlayers() do
		if PlayerDataService.Get(player) then
			push(player)
		end
	end

	Log.info("TutorialService", "Ready. %d beats, %d words, hint at %ds, auto-advance at %ds",
		TutorialConfig.StepCount, TutorialConfig.TotalWords,
		TutorialConfig.HintAfterSecs, TutorialConfig.AutoAdvanceAfterSecs)
end

return TutorialService
