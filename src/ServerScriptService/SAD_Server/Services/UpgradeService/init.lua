--!nonstrict
--[[
	UpgradeService
	ServerScriptService/SAD_Server/Services/UpgradeService  (ModuleScript)

	The 11 upgrade tracks and 3 defence tracks: validation, pricing, and the
	one transaction that moves a player's level and their Fossils together.

	═══ ONE TRANSACTION ════════════════════════════════════════════════════════
	Buy Max for eight levels is a SINGLE profile write, not eight. Charging per
	level would mean eight chances to be interrupted between the charge and the
	grant, and eight replication flushes for one button press. The affordable
	count is worked out first, from a snapshot, and then applied in one go.
	═══════════════════════════════════════════════════════════════════════════

	═══ THE CLIENT NEVER PRICES ANYTHING ═══════════════════════════════════════
	It sends a track id and how many levels it wants. It never sends a cost.
	docs/13 flags "client-computed costs disagreeing with the server" for this
	step; the shape that cannot disagree is the one where the client's number is
	never read. The client DOES render prices - from the same shared
	UpgradeConfig, so they match - but that is a display, not an input.
	═══════════════════════════════════════════════════════════════════════════

	API:
		UpgradeService.LevelOf(data, trackId) -> level
		UpgradeService.Affordable(data, trackId, wanted) -> levels, cost
		UpgradeService.Buy(player, trackId, wanted) -> bought, spent, reason?
		UpgradeService.Purchased  Signal(player, trackId, newLevel, spent)

	Depends on: UpgradeConfig, Stats, EconomyService, PlayerDataService, Net.
	Depended on by: nothing yet; Step 20 rebirth resets levels through it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local Format = require(Shared.Modules.Format)
local Log = require(Shared.Modules.Log)
local Net = require(Shared.Modules.Net)
local Signal = require(Shared.Modules.Signal)
local UpgradeConfig = require(Shared.Config.UpgradeConfig)

local UpgradeService = {}

UpgradeService.Purchased = Signal.new()

local PlayerDataService, EconomyService, EggService, IncubationService

--[[
	Tracks whose effect is visible immediately rather than at the next natural
	recomputation. Everything else is read fresh through Stats when it is next
	needed, so it needs no hook at all - which is the point of Stats.
]]
local LIVE_EFFECTS = {
	-- Changes the park's Fossils/sec, so the banking interval must be closed
	-- at the old rate before the new one applies. See EconomyService.SettleBank.
	dinoSlots = "rate",
	feedingTrough = "rate",
	-- Only affects the cap, but settling keeps BankedRate and BankedAt in step.
	bankSize = "rate",
	-- Both feed the walk speed already applied to the character.
	runnersLegs = "speed",
	strongBack = "speed",
	-- A newly unlocked slot should take an egg now, not at the next hatch.
	-- The pads themselves need no hook: IncubationService already refreshes
	-- every prompt at 1 Hz, so the new pad lights up on its own.
	incubators = "incubators",
}

-- ── Pricing ─────────────────────────────────────────────────────────────────

function UpgradeService.LevelOf(data, trackId: string): number
	return UpgradeConfig.LevelIn(data, trackId)
end

--[[
	How many of the next `wanted` levels the player can actually pay for, and
	what that costs. Pure: takes a profile, returns numbers.

	Walks level by level rather than solving the geometric series, because the
	series is not what the player is charged - each level is rounded to three
	significant figures first, and the sum of rounded prices is not the rounded
	sum. Walking is what makes the total match the prices the shop showed.
]]
function UpgradeService.Affordable(data, trackId: string, wanted: number): (number, number)
	local entry = UpgradeConfig.Get(trackId)
	if not entry or not data or wanted < 1 then
		return 0, 0
	end

	local level = UpgradeService.LevelOf(data, trackId)
	local budget = data.Fossils or 0
	local bought, spent = 0, 0

	local limit = math.min(wanted, entry.MaxLevel - level)
	for step = 1, limit do
		local cost = UpgradeConfig.CostOf(trackId, level + step)
		if cost <= 0 or spent + cost > budget then
			break
		end
		spent += cost
		bought += 1
	end

	return bought, spent
end

-- ── Buying ──────────────────────────────────────────────────────────────────

--[[
	Buys up to `wanted` levels. Returns (bought, spent, reason).

	`bought` can be less than `wanted` and that is a SUCCESS: docs/13 requires
	Buy Max with insufficient funds to buy the affordable amount rather than
	failing, and never to go negative. A reason is returned only when nothing
	at all could be bought, so the client can say why.
]]
function UpgradeService.Buy(player: Player, trackId: string, wanted: number): (number, number, string?)
	local entry = UpgradeConfig.Get(trackId)
	if not entry then
		return 0, 0, "no such upgrade"
	end

	local data = PlayerDataService.Get(player)
	if not data then
		return 0, 0, "profile not loaded"
	end

	local level = UpgradeService.LevelOf(data, trackId)
	if level >= entry.MaxLevel then
		return 0, 0, "already at max"
	end

	local bought, spent = UpgradeService.Affordable(data, trackId, wanted)
	if bought < 1 then
		return 0, 0, "not enough Fossils"
	end

	--[[
		Settle BEFORE the level changes. bankSize moves the cap and the income
		tracks move the rate; either way the seconds already elapsed must be
		paid at the old rate, or buying an income upgrade retroactively re-pays
		the whole idle window at the new one.
	]]
	if LIVE_EFFECTS[trackId] == "rate" then
		EconomyService.SettleBank(player)
	end

	local store = UpgradeConfig.StoreFor(trackId)
	local newLevel = level + bought

	PlayerDataService.UpdateKeys(player, { store, "Fossils", "Stats" }, function(profile)
		profile[store][trackId] = newLevel
		profile.Fossils -= spent
		profile.Stats.FossilsSpent += spent
	end, "upgrade " .. trackId)

	UpgradeService.ApplyLiveEffect(player, trackId)
	UpgradeService.Purchased:Fire(player, trackId, newLevel, spent)

	Log.info("UpgradeService", "%s bought %s x%d -> L%d for %s",
		player.Name, trackId, bought, newLevel, Format.Number(spent))

	return bought, spent
end

--[[
	Pushes a freshly bought level into whatever is already running.

	Only three kinds of state need this. Everything else reads Stats when it
	next needs the number, which is why there is no list of eleven hooks here.
]]
function UpgradeService.ApplyLiveEffect(player: Player, trackId: string)
	local kind = LIVE_EFFECTS[trackId]
	if not kind then
		return
	end

	if kind == "rate" then
		EconomyService.InvalidateRate(player)
	elseif kind == "speed" then
		EggService.ApplySpeed(player)
	elseif kind == "incubators" then
		IncubationService.AutoStart(player)
	end
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function UpgradeService.Init(app)
	PlayerDataService = app.Get("PlayerDataService")
	EconomyService = app.Get("EconomyService")
	EggService = app.Get("EggService")
	IncubationService = app.Get("IncubationService")
end

function UpgradeService.Start(_app)
	--[[
		Two remotes for what is nearly one operation, because docs/09 §3 gives
		them different rate limits and because it lets each one refuse tracks
		from the other's board. Without that check a client could push defence
		purchases through the four-per-second upgrade remote instead of the
		two-per-second defence one.
	]]
	local function handler(expectedBoard: string)
		return function(player: Player, trackId: any, wanted: any)
			if type(trackId) ~= "string" or type(wanted) ~= "number" then
				return
			end

			local entry = UpgradeConfig.Get(trackId)
			if not entry then
				return
			end

			local isDefence = entry.Board == "defence"
			if (expectedBoard == "defence") ~= isDefence then
				Log.warn("UpgradeService", "%s sent '%s' to the %s remote",
					player.Name, trackId, expectedBoard)
				return
			end

			-- Clamped, not rejected: a Buy Max button legitimately asks for
			-- more levels than exist, and the floor stops a 0 or negative
			-- count from being a free no-op that still costs a rate slot.
			wanted = math.clamp(math.floor(wanted), 1, entry.MaxLevel)

			local bought, spent, reason = UpgradeService.Buy(player, trackId, wanted)
			if bought > 0 then
				Net.FireClient("Notify", player, {
					Kind = "toast",
					Title = entry.DisplayName,
					Subtitle = string.format("Level %d  ·  −%s",
						UpgradeService.LevelOf(PlayerDataService.Get(player), trackId),
						Format.Number(spent)),
					Duration = 2.5,
				})
			elseif reason then
				Net.FireClient("Notify", player, {
					Kind = "toast",
					Title = entry.DisplayName,
					Subtitle = reason,
					Duration = 2,
				})
			end
		end
	end

	Net.OnEvent("RequestBuyUpgrade", handler("upgrade"))
	Net.OnEvent("RequestBuyDefence", handler("defence"))

	Log.info("UpgradeService", "Ready. %d tracks across %d boards",
		UpgradeConfig.Count(), #UpgradeConfig.Boards)
end

return UpgradeService
