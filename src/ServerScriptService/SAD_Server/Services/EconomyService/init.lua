--!nonstrict
--[[
	EconomyService
	ServerScriptService/SAD_Server/Services/EconomyService  (ModuleScript)

	Fossils and DNA: the bank, collection, offline earnings, and the single
	place any service goes to move currency.

	═══ THE BANK IS LAZY ═══════════════════════════════════════════════════════
	Nothing ticks. The profile stores BankedFossils and BankedAt, and what is in
	the bank right now is computed from the clock when someone asks. An idle
	server does no per-player work at all, and a server with 24 full parks costs
	exactly the same as an empty one.

	docs/13 names an O(dinos) income loop as the bug to watch for in this step.
	The rate is O(dinos), so it is computed once and CACHED, invalidated only
	when something that could change it changes - placing, storing, hatching,
	selling, rebirthing, or buying an income upgrade.
	═══════════════════════════════════════════════════════════════════════════

	API:
		EconomyService.GetRate(player) -> fossilsPerSecond
		EconomyService.GetBanked(player) -> banked, rate, cap
		EconomyService.Collect(player) -> collected
		EconomyService.InvalidateRate(player)
		EconomyService.AddFossils(player, amount, reason) -> newTotal
		EconomyService.TrySpendFossils(player, amount, reason) -> ok
		EconomyService.AddDna(player, amount, reason)
		EconomyService.Collected  Signal(player, amount)

	Depends on: Economy, PlayerDataService, ParkService, Net.
	Depended on by: UpgradeService (13), RebirthService (20), everything paying.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local Economy = require(Shared.Modules.Economy)
local Format = require(Shared.Modules.Format)
local Log = require(Shared.Modules.Log)
local Net = require(Shared.Modules.Net)
local RebirthConfig = require(Shared.Config.RebirthConfig)
local Signal = require(Shared.Modules.Signal)

local EconomyService = {}

EconomyService.Collected = Signal.new()

local PlayerDataService, ParkService, NotificationService

--- [player] = cached fossils/second, or nil when it needs recomputing.
local rateCache: { [Player]: number } = {}

--- Auto-collect is a free upgrade, not a purchase, unlocked at this rebirth.
local AUTO_COLLECT_REBIRTH = 2
local AUTO_COLLECT_INTERVAL = 30

-- ── Rate ────────────────────────────────────────────────────────────────────

--[[
	Closes the current banking interval and opens a new one at today's rate.

	MUST be called whenever the park's output changes. The bank accrues at
	`BankedRate`, frozen at the start of the interval, precisely so that a rate
	change cannot pay retroactively for time that elapsed at the old rate -
	otherwise placing a strong dinosaur after idling hands the player a full
	bank instantly, and store/re-place becomes a money printer.

	The old rate comes out of the PROFILE, not the cache, so this is correct no
	matter whether the caller settles before or after writing the change.
]]
function EconomyService.SettleBank(player: Player)
	local data = PlayerDataService.Get(player)
	if not data then
		return
	end

	-- The live rate is what the NEXT interval accrues at. Computed directly
	-- rather than through GetRate, because the cache may still hold the value
	-- this settle exists to replace.
	local nextRate = Economy.ParkIncomeRate(data)
	local banked = Economy.BankedNow(data, os.time(), nextRate)

	--[[
		The peak is recorded HERE because this is the one function every rate
		change goes through. Until Step 22 nothing wrote `PeakIncomePerSec` at
		all, so the Highest Income leaderboard would have ranked every player
		at zero - the registered-but-inert failure this project keeps removing.

		Peak rather than current, deliberately: a player who sells their park
		to fund a rebirth should not drop off the board for the ten minutes it
		takes to rebuild. It never decreases, so it survives the reset that
		`RebirthConfig` classifies `Stats` as Preserved for.
	]]
	PlayerDataService.UpdateKeys(player,
		{ "BankedFossils", "BankedAt", "BankedRate", "Stats" }, function(profile)
			profile.BankedFossils = banked
			profile.BankedAt = os.time()
			profile.BankedRate = nextRate
			if nextRate > profile.Stats.PeakIncomePerSec then
				profile.Stats.PeakIncomePerSec = nextRate
			end
		end, "settle bank")

	rateCache[player] = nextRate
end

--[[
	Anything that could change a park's output calls this.

	Deliberately blunt: it is far better to recompute a rate that did not change
	than to miss one that did, because a stale rate silently under- or over-pays
	a player for as long as they stay logged in.
]]
function EconomyService.InvalidateRate(player: Player)
	rateCache[player] = nil
	EconomyService.SettleBank(player)
end

function EconomyService.GetRate(player: Player): number
	local cached = rateCache[player]
	if cached then
		return cached
	end

	local data = PlayerDataService.Get(player)
	if not data then
		return 0
	end

	local rate = Economy.ParkIncomeRate(data)
	rateCache[player] = rate
	return rate
end

-- ── Bank ────────────────────────────────────────────────────────────────────

--- What is in the bank right now. Returns (banked, rate, cap).
function EconomyService.GetBanked(player: Player): (number, number, number)
	local data = PlayerDataService.Get(player)
	if not data then
		return 0, 0, 0
	end
	return Economy.BankedNow(data, os.time(), EconomyService.GetRate(player))
end

--[[
	Empties the bank into the wallet. Returns what was collected.

	Resets BankedAt in the same write, so collecting twice in one frame - which
	docs/13 flags for this step - banks the same seconds only once: the second
	call finds zero elapsed and zero stored.
]]
function EconomyService.Collect(player: Player): number
	local data = PlayerDataService.Get(player)
	if not data then
		return 0
	end

	local banked = Economy.BankedNow(data, os.time(), EconomyService.GetRate(player))
	if banked <= 0 then
		return 0
	end

	local rate = EconomyService.GetRate(player)
	PlayerDataService.UpdateKeys(player,
		{ "Fossils", "BankedFossils", "BankedAt", "BankedRate", "Stats" }, function(profile)
			profile.Fossils = Economy.ClampFossils(profile.Fossils + banked)
			profile.BankedFossils = 0
			profile.BankedAt = os.time()
			profile.BankedRate = rate
			profile.Stats.FossilsEarned += banked
		end, "collect")

	EconomyService.Collected:Fire(player, banked)
	return banked
end

-- ── Currency ────────────────────────────────────────────────────────────────

--[[
	The only way currency moves. Every grant and every charge goes through here
	so there is one place to log from, one place to clamp, and one place for
	Step 24's analytics to hook.
]]
function EconomyService.AddFossils(player: Player, amount: number, reason: string?): number
	if amount == 0 then
		return 0
	end

	local total = 0
	PlayerDataService.UpdateKeys(player, { "Fossils", "Stats" }, function(profile)
		profile.Fossils = Economy.ClampFossils(profile.Fossils + amount)
		if amount > 0 then
			profile.Stats.FossilsEarned += amount
		end
		total = profile.Fossils
	end, reason or "grant")

	return total
end

--- Charges the player if they can afford it. Returns whether they could.
function EconomyService.TrySpendFossils(player: Player, amount: number, reason: string?): boolean
	local data = PlayerDataService.Get(player)
	if not data or amount < 0 or data.Fossils < amount then
		return false
	end

	PlayerDataService.UpdateKeys(player, { "Fossils", "Stats" }, function(profile)
		profile.Fossils = Economy.ClampFossils(profile.Fossils - amount)
		profile.Stats.FossilsSpent += amount
	end, reason or "spend")

	return true
end

function EconomyService.AddDna(player: Player, amount: number, reason: string?)
	if amount == 0 then
		return
	end
	PlayerDataService.UpdateKeys(player, { "DNA", "Stats" }, function(profile)
		profile.DNA = Economy.ClampFossils(profile.DNA + amount)
		if amount > 0 then
			profile.Stats.DnaEarned += amount
		end
	end, reason or "grant")
end

-- ── Offline ─────────────────────────────────────────────────────────────────

--[[
	Pays out what the park earned while its owner was away, on load.

	Not routed through the bank: the bank exists to pull players home during a
	session, and capping offline time with it would mean everyone returns to the
	same sixty seconds regardless of how long they were gone - the opposite of a
	reason to come back.
]]
local function grantOffline(player: Player, data)
	local rate = Economy.ParkIncomeRate(data)
	if rate <= 0 then
		return
	end

	local earned, seconds = Economy.OfflineEarnings(data, os.time(), rate)
	if earned <= 0 or seconds < 60 then
		return -- not worth a popup for under a minute
	end

	EconomyService.AddFossils(player, earned, "offline")

	NotificationService.Takeover(player, {
		Title = "WHILE YOU WERE AWAY",
		Subtitle = string.format("%s of income at %s Fossils/sec",
			Format.Time(seconds), Format.Number(rate)),
		Headline = "+" .. Format.Number(earned),
		Duration = 5,
	})

	Log.info("EconomyService", "%s earned %s offline over %s",
		player.Name, Format.Number(earned), Format.Time(seconds))
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function EconomyService.Init(app)
	PlayerDataService = app.Get("PlayerDataService")
	NotificationService = app.Get("NotificationService")
	ParkService = app.Get("ParkService")
end

function EconomyService.Start(app)
	local DinosaurService = app.Get("DinosaurService")
	local IncubationService = app.Get("IncubationService")

	Net.OnEvent("RequestCollectIncome", function(player: Player)
		EconomyService.Collect(player)
	end)

	--[[
		Every event that can change a park's output invalidates the cache.
		Missing one silently under- or over-pays for the rest of the session, so
		the list is deliberately generous.
	]]
	for _, signal in {
		DinosaurService.DinoPlaced,
		DinosaurService.DinoStored,
		DinosaurService.DinoCreated,
		IncubationService.Hatched,
	} do
		signal:Connect(function(player)
			EconomyService.InvalidateRate(player)
		end)
	end

	PlayerDataService.ProfileLoaded:Connect(function(player, data)
		EconomyService.InvalidateRate(player)

		-- Before anything else touches LastSeen: BeforeSave stamps it on every
		-- write, so the offline window has to be read while it still describes
		-- the previous session.
		task.defer(grantOffline, player, data)

		-- Opens a fresh interval stamped with this session's real rate. Offline
		-- time is paid separately above and must not also accrue in the bank.
		local rate = Economy.ParkIncomeRate(data)
		PlayerDataService.UpdateKeys(player, { "BankedAt", "BankedRate" }, function(profile)
			profile.BankedAt = os.time()
			profile.BankedRate = rate
		end, "session start")
	end)

	Players.PlayerRemoving:Connect(function(player)
		rateCache[player] = nil
	end)

	--[[
		Banking on save, so a crash cannot lose accrued income. The lazy bank is
		only correct while BankedAt is accurate, and a save writes the profile
		as it stands - so the pending amount is folded in first.
	]]
	local DataService = app.Get("DataService")
	DataService.BeforeSave:Connect(function(player, data)
		-- Folds at BankedRate, which is what the elapsed seconds earned. The
		-- interval is not closed - BankedRate carries on unchanged - so a save
		-- mid-interval is invisible to the player.
		data.BankedFossils = Economy.BankedNow(data, os.time(), EconomyService.GetRate(player))
		data.BankedAt = os.time()
	end)

	-- Auto-collect: free at rebirth 2 (docs/05 §3), and a setting the player
	-- can turn off if they prefer tapping the totem.
	task.spawn(function()
		while true do
			task.wait(AUTO_COLLECT_INTERVAL)
			for player, data in PlayerDataService.GetAll() do
				if data.Settings.AutoCollect and data.Rebirths >= AUTO_COLLECT_REBIRTH then
					EconomyService.Collect(player)
				end
			end
		end
	end)

	Log.info("EconomyService", "Ready. Bank is lazy; auto-collect unlocks at rebirth %d",
		AUTO_COLLECT_REBIRTH)
end

return EconomyService
