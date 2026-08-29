--!strict
--[[
	RarityConfig
	ReplicatedStorage/SAD_Shared/Config/RarityConfig  (ModuleScript)

	The nine rarity tiers, their economics, and the per-zone weight vectors that
	decide what an egg becomes. Mirrors docs/01-dinosaurs.md.

	Weights are INTEGERS out of WeightTotal (100,000,000). Integers rather than
	percentages because the tail matters: Titan in Zone 1 is a weight of 1, and
	expressing that as 0.000001% invites float drift into the one number players
	screenshot. Every vector must sum exactly to WeightTotal, which
	ConfigValidator asserts at boot.

	Colours are hex STRINGS, not Color3 values. Constructing nine Color3s at
	require time is wasted work on the server, which never draws anything, and
	it makes this module testable outside Roblox. Call GetColor() where you
	actually need one.

	Depends on: nothing.
]]

local RarityConfig = {}

--- Ascending. Anywhere order matters (UI sorting, "one tier below", weighted
--- picks) reads this rather than assuming dictionary order.
RarityConfig.Order = {
	"common",
	"uncommon",
	"rare",
	"epic",
	"legendary",
	"mythic",
	"ancient",
	"secret",
	"titan",
}

RarityConfig.WeightTotal = 100000000

export type Tier = {
	Id: string,
	DisplayName: string,
	Color: string,
	Rank: number,
	BaseIncome: number,
	SellFossils: number,
	SellDna: number,
	IncubationSecs: number,
	CarryPenalty: number,
	AnnounceKind: string?,
	CrossServer: boolean,
	AutoLock: boolean,
	LuckPower: number,
	EggAura: string?,
	InV1: boolean,
}

--[[
	LuckPower drives RNG.ApplyLuck: scaled = base * (1 + luck * power).

	Negative on Common/Uncommon so luck drains the bottom into the middle.
	Secret and Titan carry LOWER powers than Mythic and Ancient on purpose - a
	maxed-luck player should improve the tiers they can realistically grind far
	more than the lottery tiers. Verified empirically in tests/step1_spec.lua.

	InV1 marks which tiers have species shipping in Version 1. ConfigValidator
	uses it to explain coverage failures in terms of scope rather than as a
	mysterious missing-species error.
]]
RarityConfig.Tiers = {
	common = {
		Id = "common", DisplayName = "Common", Color = "E8E4D9", Rank = 1,
		BaseIncome = 2, SellFossils = 60, SellDna = 1,
		IncubationSecs = 30, CarryPenalty = 0.00,
		AnnounceKind = nil, CrossServer = false, AutoLock = false,
		LuckPower = -0.50, EggAura = nil, InV1 = true,
	},
	uncommon = {
		Id = "uncommon", DisplayName = "Uncommon", Color = "5FD35F", Rank = 2,
		BaseIncome = 8, SellFossils = 260, SellDna = 3,
		IncubationSecs = 60, CarryPenalty = 0.04,
		AnnounceKind = nil, CrossServer = false, AutoLock = false,
		LuckPower = -0.25, EggAura = nil, InV1 = true,
	},
	rare = {
		Id = "rare", DisplayName = "Rare", Color = "3FA9F5", Rank = 3,
		BaseIncome = 30, SellFossils = 1100, SellDna = 10,
		IncubationSecs = 180, CarryPenalty = 0.09,
		AnnounceKind = nil, CrossServer = false, AutoLock = false,
		LuckPower = 0.15, EggAura = "Aura_Rare", InV1 = true,
	},
	epic = {
		Id = "epic", DisplayName = "Epic", Color = "A050F0", Rank = 4,
		BaseIncome = 120, SellFossils = 4800, SellDna = 35,
		IncubationSecs = 480, CarryPenalty = 0.15,
		AnnounceKind = "local", CrossServer = false, AutoLock = false,
		LuckPower = 0.35, EggAura = "Aura_Epic", InV1 = true,
	},
	legendary = {
		Id = "legendary", DisplayName = "Legendary", Color = "FFB020", Rank = 5,
		BaseIncome = 500, SellFossils = 22000, SellDna = 120,
		IncubationSecs = 1200, CarryPenalty = 0.22,
		AnnounceKind = "toast", CrossServer = false, AutoLock = true,
		LuckPower = 0.55, EggAura = "Aura_Legendary", InV1 = true,
	},
	mythic = {
		Id = "mythic", DisplayName = "Mythic", Color = "FF4B3E", Rank = 6,
		BaseIncome = 2200, SellFossils = 110000, SellDna = 450,
		IncubationSecs = 2700, CarryPenalty = 0.29,
		AnnounceKind = "banner", CrossServer = false, AutoLock = true,
		LuckPower = 0.70, EggAura = "Aura_Mythic", InV1 = false,
	},
	ancient = {
		Id = "ancient", DisplayName = "Ancient", Color = "17C6A3", Rank = 7,
		BaseIncome = 10000, SellFossils = 600000, SellDna = 1800,
		IncubationSecs = 5400, CarryPenalty = 0.35,
		AnnounceKind = "banner", CrossServer = false, AutoLock = true,
		LuckPower = 0.80, EggAura = "Aura_Ancient", InV1 = false,
	},
	secret = {
		Id = "secret", DisplayName = "Secret", Color = "1A1A24", Rank = 8,
		BaseIncome = 45000, SellFossils = 3000000, SellDna = 7500,
		IncubationSecs = 10800, CarryPenalty = 0.40,
		AnnounceKind = "takeover", CrossServer = true, AutoLock = true,
		LuckPower = 0.55, EggAura = "Aura_Secret", InV1 = true,
	},
	titan = {
		Id = "titan", DisplayName = "Titan", Color = "FFD24A", Rank = 9,
		BaseIncome = 200000, SellFossils = 15000000, SellDna = 30000,
		IncubationSecs = 21600, CarryPenalty = 0.45,
		AnnounceKind = "takeover", CrossServer = true, AutoLock = true,
		LuckPower = 0.40, EggAura = "Aura_Titan", InV1 = true,
	},
}

--[[
	Per-zone rarity weights. Each vector sums to WeightTotal.

	═══ V1 SCOPE NOTE ═══════════════════════════════════════════════════════
	Version 1 ships no Mythic and no Ancient species (docs/12 §2), so those
	tiers are ZERO here and their mass is folded into Legendary. A non-zero
	weight for a tier with no species in that zone's pool is exactly the bug
	ConfigValidator rule 6 exists to catch - it would roll a rarity the game
	then cannot hatch.

	When V1.1 and V1.3 add those species, these vectors move back toward the
	design targets published in docs/01 §1.1. Zones 5-10 arrive with them.
	═════════════════════════════════════════════════════════════════════════
]]
RarityConfig.ZoneWeights = {
	-- Zone 1: a beginner zone with a real lottery tail. Titan at 1 in 100
	-- million will essentially never happen, and the nest sign says it can.
	plains = {
		common = 62000000,
		uncommon = 27000000,
		rare = 9000000,
		epic = 1800000,
		legendary = 199980,
		mythic = 0,
		ancient = 0,
		secret = 19,
		titan = 1,
	},
	canyon = {
		common = 52000000,
		uncommon = 32000000,
		rare = 13000000,
		epic = 2600000,
		legendary = 399953,
		mythic = 0,
		ancient = 0,
		secret = 45,
		titan = 2,
	},
	swamp = {
		common = 40000000,
		uncommon = 34000000,
		rare = 19000000,
		epic = 5600000,
		legendary = 1399690,
		mythic = 0,
		ancient = 0,
		secret = 300,
		titan = 10,
	},
	-- Zone 4 is the V1 end game: Legendary at 1 in 29, Secret at 1 in 80,000,
	-- Titan at 1 in 2,000,000. Rare enough to be a story, common enough that a
	-- server sees one occasionally.
	frozen = {
		common = 30000000,
		uncommon = 33000000,
		rare = 24000000,
		epic = 9500000,
		legendary = 3498700,
		mythic = 0,
		ancient = 0,
		secret = 1250,
		titan = 50,
	},
}

-- ── Helpers ─────────────────────────────────────────────────────────────────

function RarityConfig.Get(rarityId: string): Tier?
	return (RarityConfig.Tiers :: any)[rarityId]
end

--- Rank, or 0 for an unknown id. Used for "is this rarer than that" checks.
function RarityConfig.RankOf(rarityId: string): number
	local tier = (RarityConfig.Tiers :: any)[rarityId]
	return if tier then tier.Rank else 0
end

--- The tier `steps` below `rarityId`, clamped to Common. The Rebirth Cache
--- (docs/05 §6) hands out "your best ever, minus one tier".
function RarityConfig.TierBelow(rarityId: string, steps: number?): string
	local rank = RarityConfig.RankOf(rarityId)
	local target = math.clamp(rank - (steps or 1), 1, #RarityConfig.Order)
	return RarityConfig.Order[target]
end

--- Lazily built Color3. Server code never needs one, so none are made at load.
function RarityConfig.GetColor(rarityId: string): Color3
	local tier = (RarityConfig.Tiers :: any)[rarityId]
	return Color3.fromHex(if tier then tier.Color else "FFFFFF")
end

--- LuckPower table in the shape RNG.ApplyLuck expects.
function RarityConfig.LuckPowers(): { [string]: number }
	local powers = {}
	for id, tier in RarityConfig.Tiers :: any do
		powers[id] = tier.LuckPower
	end
	return powers
end

function RarityConfig.WeightsForZone(zoneId: string): { [string]: number }?
	return (RarityConfig.ZoneWeights :: any)[zoneId]
end

return RarityConfig
