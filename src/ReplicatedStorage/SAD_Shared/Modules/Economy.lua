--!nonstrict
--[[
	Economy
	ReplicatedStorage/SAD_Shared/Modules/Economy  (ModuleScript)

	The money formulas, shared by the server that pays them out and the client
	that draws them.

	Shared for the same reason Patch is: the client generates income floaters
	locally from the replicated profile rather than being sent a packet per
	tick (docs/09 §6), so it has to arrive at exactly the number the server
	banked. Two implementations of a multiplication chain drift the first time
	one of them gains a term.

	Every function here is PURE - profile in, number out - which is what lets
	docs/05's published values be asserted rather than played for.

	Depends on: RarityConfig, DinoConfig, MutationConfig, RebirthConfig,
	            ProductConfig, Stats.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local DinoConfig = require(Shared.Config.DinoConfig)
local MutationConfig = require(Shared.Config.MutationConfig)
local RarityConfig = require(Shared.Config.RarityConfig)
local ProductConfig = require(Shared.Config.ProductConfig)
local RebirthConfig = require(Shared.Config.RebirthConfig)
local Stats = require(Shared.Modules.Stats)

local Economy = {}

--- Fossils are stored as Lua doubles, exact to 2^53. The rebirth curve is meant
--- to keep players far below this; the clamp is a safety net, not a feature.
Economy.MaxFossils = 1e30

--- Offline earns this share of the active rate (docs/05 §4). VIP raises it to
--- 1.0 in Step 21. Deliberately below 1 so an idle player progresses at well
--- under half the speed of an active one.
Economy.OfflineRate = 0.60

Economy.StarBonusPerStar = 0.35

-- ── One dinosaur ────────────────────────────────────────────────────────────

--[[
	The master income formula from docs/05 §2. Every multiplier in one place,
	in the documented order, so a number a player sees can be traced.

	`data` may be nil for a context-free valuation - a preview, a trade window -
	in which case the player-specific terms drop to 1.
]]
function Economy.IncomeOf(entry, data): number
	local tier = RarityConfig.Tiers[entry.Rarity]
	local species = DinoConfig.Get(entry.SpeciesId)
	if not tier or not species then
		return 0
	end

	local income = tier.BaseIncome * species.SpeciesFactor
	income *= MutationConfig.MultiplierFor(entry.Mutation, entry.Mutation2)
	income *= 1 + Economy.StarBonusPerStar * ((entry.Stars or 1) - 1)

	if data then
		income *= RebirthConfig.IncomeMultiplier(data.Rebirths)
		income *= Stats.ParkIncomeMult(data)
	end

	return income
end

--[[
	Fossils and DNA from selling.

	Mutations raise sell value on a SQUARE ROOT, so selling a Void dinosaur is
	lucrative but never close to as good as keeping it - measured at x12 to sell
	against x150 to keep.
]]
function Economy.SellValueOf(entry): (number, number)
	local tier = RarityConfig.Tiers[entry.Rarity]
	if not tier then
		return 0, 0
	end

	local starMult = 1 + Economy.StarBonusPerStar * ((entry.Stars or 1) - 1)
	local mutationMult = math.sqrt(MutationConfig.MultiplierFor(entry.Mutation, entry.Mutation2))

	return math.floor(tier.SellFossils * starMult * mutationMult),
		math.floor(tier.SellDna * starMult * mutationMult)
end

-- ── A whole park ────────────────────────────────────────────────────────────

--[[
	Fossils per second from everything currently PLACED.

	Stored dinosaurs earn nothing. That is what makes placement slots the core
	sink of the whole economy (docs/05 §2) - a hundred dinosaurs in a bag are
	worth exactly zero until there is somewhere to put them.

	O(dinos), so callers cache it and invalidate on change rather than calling
	it per tick. See EconomyService.
]]
function Economy.ParkIncomeRate(data): number
	if not data then
		return 0
	end

	local rate = 0
	for _, entry in data.Dinos do
		if entry.Placed or entry.Vault then
			rate += Economy.IncomeOf(entry, data)
		end
	end
	return rate
end

--- Total value of a park, for the visual tier and the leaderboard.
function Economy.ParkValue(data): number
	local value = 0
	for _, entry in data.Dinos do
		local fossils = Economy.SellValueOf(entry)
		value += fossils
	end
	return value
end

-- ── The bank ────────────────────────────────────────────────────────────────

--[[
	How many seconds of income the bank holds before it fills.

	One minute at level 0, six at max. The cap is what brings a player home
	regularly - the "come home" beat of the loop - without punishing them for
	going out (docs/05 §3).
]]
function Economy.BankSeconds(data): number
	return Stats.BankSecs(data)
end

function Economy.BankCap(data, rate: number?): number
	return (rate or Economy.ParkIncomeRate(data)) * Economy.BankSeconds(data)
end

--[[
	What is in the bank right now. Returns (banked, rate, cap).

	Computed lazily from BankedAt rather than accumulated by a tick, so the
	server does no per-player work between reads and an idle server costs
	nothing. docs/13 flags an O(dinos) income loop as the bug to watch for in
	this step, and this is the shape that avoids it.

	═══ TWO RATES, AND WHY ═════════════════════════════════════════════════════
	Accrual uses `data.BankedRate` - the rate frozen when the interval started -
	NOT the rate passed in. The bank pays for seconds that have already elapsed,
	so it must pay for them at the rate that was in force while they elapsed.
	Using the live rate would let a player idle at a low rate, place their best
	dinosaur, and have the whole idle window retroactively pay at the new one:
	a full bank, instantly, repeatable by storing and re-placing.

	`rate` is still the live rate, used for the CAP and returned for display -
	both of which describe the park as it is now.

	Whoever changes the rate is responsible for settling first
	(EconomyService.SettleBank), which is what keeps BankedRate honest.
	═══════════════════════════════════════════════════════════════════════════

	The cap bounds ACCRUAL, not the stored balance. A player who banks 500 and
	then stores a dinosaur has a smaller cap but must not lose the 500 they
	already earned, so the ceiling is `max(cap, BankedFossils)`.
]]
function Economy.BankedNow(data, now: number, rate: number?): (number, number, number)
	local liveRate = rate or Economy.ParkIncomeRate(data)
	local cap = liveRate * Economy.BankSeconds(data)

	local stored = data.BankedFossils or 0
	local elapsed = math.max(0, now - (data.BankedAt or now))
	local accrued = (data.BankedRate or 0) * elapsed

	return math.min(stored + accrued, math.max(cap, stored)), liveRate, cap
end

-- ── Offline ─────────────────────────────────────────────────────────────────

--[[
	What a park earned while its owner was away. Returns (fossils, cappedSecs).

	Separate from the bank on purpose: the bank exists to pull players home
	during a session, and applying it to offline time would mean everyone
	returns to the same sixty seconds of income regardless of how long they were
	gone, which is the opposite of a reason to come back.
]]
--[[
	The share of active income an offline park earns. 0.60 normally, 1.00 with
	VIP (docs/07 §2).

	Here rather than in PurchaseService because the offline summary is drawn
	from this same function on the client - a VIP who is shown 60% and paid
	100% would be a bug in the direction nobody reports.
]]
function Economy.OfflineRateFor(data): number
	return ProductConfig.EffectTotal(data and data.Gamepasses, "OfflineRate", Economy.OfflineRate)
end

function Economy.OfflineEarnings(data, now: number, rate: number?, offlineRate: number?): (number, number)
	local lastSeen = data.LastSeen or 0
	if lastSeen <= 0 then
		return 0, 0
	end

	local away = math.max(0, now - lastSeen)
	local capped = math.min(away, RebirthConfig.OfflineCapSecs(data.Rebirths))

	local currentRate = rate or Economy.ParkIncomeRate(data)
	return currentRate * capped * (offlineRate or Economy.OfflineRateFor(data)), capped
end

-- ── Helpers ─────────────────────────────────────────────────────────────────

function Economy.ClampFossils(amount: number): number
	if amount ~= amount then
		return 0
	end
	return math.clamp(amount, 0, Economy.MaxFossils)
end

--- Placement slots: the upgrade track plus the rebirth grant. Gamepasses add
--- to this in Step 21.
function Economy.SlotCap(data): number
	return Stats.DinoSlots(data)
end

return Economy
