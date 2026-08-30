--!strict
--[[
	RebirthConfig
	ReplicatedStorage/SAD_Shared/Config/RebirthConfig  (ModuleScript)

	Rebirth costs, what survives a reset, and what each one permanently grants.
	Mirrors docs/05-economy.md §6.

	Rebirth is the economy's primary deflation event: it removes the entire
	Fossil supply and every Fossil-bought upgrade from a player, in exchange for
	multipliers that make the next run several times faster.

	Depends on: nothing.
]]

local RebirthConfig = {}

RebirthConfig.BaseCost = 250000
RebirthConfig.Growth = 5.2

--- Also required, so a player cannot rebirth on a bare plot and lose nothing.
RebirthConfig.MinDinosaursBase = 2 -- rebirth n requires n + this many dinosaurs

-- ── Permanent grants, per rebirth ───────────────────────────────────────────

RebirthConfig.Grants = {
	IncomeMultPerRebirth = 0.15, -- additive: x(1 + 0.15n)
	LuckPerRebirth = 0.05,
	LuckCap = 0.75, -- reached at R15
	MutLuckPerRebirth = 0.03,
	MutLuckCap = 0.45, -- R15
	MoveSpeedPerRebirth = 0.02,
	MoveSpeedCap = 0.40, -- R20
	OfflineHoursPerRebirth = 1,
	OfflineHoursCap = 12,
	DinoSlotsPerTwoRebirths = 1,
	DinoSlotsCap = 10,
}

--- Vault slots unlock at these rebirth counts (docs/03 §4.3).
RebirthConfig.VaultSlotMilestones = { 3, 7, 12, 20 }
RebirthConfig.VaultSlotsBase = 1
RebirthConfig.VaultSlotsMax = 5

--- Cosmetic name-tag tiers.
RebirthConfig.NameTagTiers = {
	{ Rebirths = 0, Id = "bone", DisplayName = "Bone", Color = "E8E4D9" },
	{ Rebirths = 1, Id = "amber", DisplayName = "Amber", Color = "FFB020" },
	{ Rebirths = 5, Id = "obsidian", DisplayName = "Obsidian", Color = "2A2A35" },
	{ Rebirths = 10, Id = "prismatic", DisplayName = "Prismatic", Color = "9B5DE5" },
	{ Rebirths = 20, Id = "titan", DisplayName = "Titan", Color = "FFD24A" },
}

--[[
	What a rebirth does NOT touch. Everything absent from this list resets.

	Vaulted dinosaurs surviving is the single most important entry: a player
	who loses their favourite to a rebirth does not do a second one.
]]
RebirthConfig.Preserved = {
	"SchemaVersion",
	"DNA",
	"LuckNodes",
	"Index",
	"IndexMilestones",
	"Quests",
	"Daily",
	"Tutorial",
	"Gamepasses",
	"ProcessedReceipts",
	"RobuxSpent",
	"Settings",
	"Stats",
	"ShieldUntil",
	"ShieldBankSecs",
	"Items",
	"FirstJoinAt",
	"NewPlayerProtectionDone",
	"Rebirths",
}

--[[
	Anti-repetition: every rebirth hands out one guaranteed egg, one tier below
	the best rarity that player has ever hatched (floor: Rare). A rebirth-8
	Mythic owner restarts with an Epic in the incubator rather than from
	literally nothing, which is what stops the early grind feeling like a
	punishment for progressing. See docs/05 §6.
]]
RebirthConfig.CacheEnabled = true
RebirthConfig.CacheMinRarity = "rare"
RebirthConfig.CacheTiersBelowBest = 1

-- ── Helpers ─────────────────────────────────────────────────────────────────

--[[
	Identical to UpgradeConfig.RoundSignificant, duplicated rather than required
	because this module is declared dependency-free and every config loads it.
	Six lines of arithmetic with no state; the spec asserts the two agree.
]]
local function roundSignificant(value: number, digits: number?): number
	if value <= 0 then
		return 0
	end
	local places = digits or 3
	local magnitude = math.floor(math.log(value, 10)) - (places - 1)
	local scale = 10 ^ magnitude
	if scale < 1 then
		return math.floor(value + 0.5)
	end
	return math.floor(value / scale + 0.5) * scale
end

--[[
	Fossil cost of performing rebirth number `n` (1-indexed).

	Rounded to three significant figures for the same reason every upgrade
	price is (UpgradeConfig.RoundSignificant): a price is a thing a player
	reads and a thing a comparison is made against. Unrounded, rebirth 3 comes
	out as 6760000.000000001 - which renders with a tail of digits, and which a
	player holding exactly 6,760,000 Fossils cannot afford.
]]
function RebirthConfig.CostOf(n: number): number
	if n < 1 then
		return 0
	end
	return roundSignificant(RebirthConfig.BaseCost * RebirthConfig.Growth ^ (n - 1))
end

function RebirthConfig.DinosaursRequired(n: number): number
	return n + RebirthConfig.MinDinosaursBase
end

function RebirthConfig.IncomeMultiplier(rebirths: number): number
	return 1 + RebirthConfig.Grants.IncomeMultPerRebirth * rebirths
end

function RebirthConfig.LuckBonus(rebirths: number): number
	return math.min(rebirths * RebirthConfig.Grants.LuckPerRebirth, RebirthConfig.Grants.LuckCap)
end

function RebirthConfig.MutLuckBonus(rebirths: number): number
	return math.min(rebirths * RebirthConfig.Grants.MutLuckPerRebirth, RebirthConfig.Grants.MutLuckCap)
end

function RebirthConfig.MoveSpeedBonus(rebirths: number): number
	return math.min(rebirths * RebirthConfig.Grants.MoveSpeedPerRebirth, RebirthConfig.Grants.MoveSpeedCap)
end

function RebirthConfig.OfflineCapSecs(rebirths: number): number
	local hours = math.min(4 + rebirths * RebirthConfig.Grants.OfflineHoursPerRebirth, RebirthConfig.Grants.OfflineHoursCap)
	return hours * 3600
end

function RebirthConfig.BonusDinoSlots(rebirths: number): number
	return math.min(math.floor(rebirths / 2), RebirthConfig.Grants.DinoSlotsCap)
end

function RebirthConfig.VaultSlots(rebirths: number): number
	local slots = RebirthConfig.VaultSlotsBase
	for _, milestone in RebirthConfig.VaultSlotMilestones do
		if rebirths >= milestone then
			slots += 1
		end
	end
	return math.min(slots, RebirthConfig.VaultSlotsMax)
end

function RebirthConfig.NameTagFor(rebirths: number)
	local current = RebirthConfig.NameTagTiers[1]
	for _, tier in RebirthConfig.NameTagTiers do
		if rebirths >= tier.Rebirths then
			current = tier
		end
	end
	return current
end

return RebirthConfig
