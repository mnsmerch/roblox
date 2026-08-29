--!strict
--[[
	MutationConfig
	ReplicatedStorage/SAD_Shared/Config/MutationConfig  (ModuleScript)

	Mutations, their weights and their income multipliers. Mirrors
	docs/04-mutations-weather-events.md §1.

	Rolled at HATCH, not at pickup. That is deliberate: weather at the moment of
	hatching modifies these weights, so players hoard eggs until a Blood Moon.
	Coordinated server-wide anticipation for free.

	═══ V1 SCOPE NOTE ══════════════════════════════════════════════════════════
	V1 ships 8 mutations (docs/12 §2), chosen to spread the multiplier ladder
	from x2 to x150 so its shape is legible immediately. The other 10 keep their
	design weights in comments and land in V1.1 and V1.3.

	The 8 shipped keep their exact design weights and the remainder goes to
	`none`, so a V1 hatch mutates 19.93% of the time against a design target of
	22%. Rescaling the survivors to hit 22% would mean re-tuning every rate
	again when the rest ship - the drift is deliberate and temporary.
	═══════════════════════════════════════════════════════════════════════════

	Depends on: nothing.
]]

local MutationConfig = {}

MutationConfig.WeightTotal = 100000000

--- After a non-`none` roll, a 1-in-N chance of a SECOND, different mutation.
--- Capped at two, ever. Uncapped stacking reaches x720,000 and breaks the
--- economy; two tops out around x9,000 at roughly 1 in 1.7 billion, which is a
--- legend rather than a balance problem. See docs/04 §1.1.
MutationConfig.PrimeChance = 2000
MutationConfig.MaxStack = 2

--- Weather can never push a single mutation's weight beyond this multiple.
MutationConfig.WeatherModifierCap = 40

export type Mutation = {
	Id: string,
	DisplayName: string,
	Weight: number,
	Multiplier: number,
	Color: string,
	Vfx: string?,
	MutPower: number,
	AnnounceKind: string?,
	CrossServer: boolean,
	Rank: number,
	InV1: boolean,
}

--[[
	MutPower drives the MutLuck redistribution, the same mechanism as rarity
	luck but scoped to this table. The low tiers sit at 0 so mutation luck moves
	mass out of `none` and into the middle and upper bands rather than doubling
	the number of Goldens.
]]
MutationConfig.List = {
	none = {
		Id = "none", DisplayName = "", Weight = 80068950, Multiplier = 1,
		Color = "FFFFFF", Vfx = nil, MutPower = -0.60,
		AnnounceKind = nil, CrossServer = false, Rank = 0, InV1 = true,
	},
	golden = {
		Id = "golden", DisplayName = "Golden", Weight = 12000000, Multiplier = 2,
		Color = "FFC94A", Vfx = "Mut_Golden", MutPower = 0.00,
		AnnounceKind = nil, CrossServer = false, Rank = 1, InV1 = true,
	},
	crystal = {
		Id = "crystal", DisplayName = "Crystal", Weight = 4000000, Multiplier = 3,
		Color = "BFE9F5", Vfx = "Mut_Crystal", MutPower = 0.00,
		AnnounceKind = nil, CrossServer = false, Rank = 2, InV1 = true,
	},
	frozen = {
		Id = "frozen", DisplayName = "Frozen", Weight = 2000000, Multiplier = 3.5,
		Color = "8FD9F5", Vfx = "Mut_Frozen", MutPower = 0.00,
		AnnounceKind = nil, CrossServer = false, Rank = 3, InV1 = true,
	},
	electric = {
		Id = "electric", DisplayName = "Electric", Weight = 1500000, Multiplier = 4,
		Color = "5AC8FF", Vfx = "Mut_Electric", MutPower = 0.45,
		AnnounceKind = nil, CrossServer = false, Rank = 4, InV1 = true,
	},
	diamond = {
		Id = "diamond", DisplayName = "Diamond", Weight = 400000, Multiplier = 6,
		Color = "E8F7FF", Vfx = "Mut_Diamond", MutPower = 0.45,
		AnnounceKind = "local", CrossServer = false, Rank = 8, InV1 = true,
	},
	rainbow = {
		Id = "rainbow", DisplayName = "Rainbow", Weight = 30000, Multiplier = 15,
		Color = "FF6BD6", Vfx = "Mut_Rainbow", MutPower = 0.75,
		AnnounceKind = "toast", CrossServer = false, Rank = 12, InV1 = true,
	},
	galaxy = {
		Id = "galaxy", DisplayName = "Galaxy", Weight = 1000, Multiplier = 35,
		Color = "6B4FD6", Vfx = "Mut_Galaxy", MutPower = 0.50,
		AnnounceKind = "banner", CrossServer = true, Rank = 16, InV1 = true,
	},
	void = {
		Id = "void", DisplayName = "Void", Weight = 50, Multiplier = 150,
		Color = "140A20", Vfx = "Mut_Void", MutPower = 0.50,
		AnnounceKind = "banner", CrossServer = true, Rank = 19, InV1 = true,
	},

	--[[
		V1.1 / V1.3, with their design weights preserved. Adding one means
		flipping InV1, moving its weight out of `none`, and shipping the VFX:

		toxic       Weight  1000000  Multiplier 4.5   Rank 5   V1.1
		volcanic    Weight   700000  Multiplier 5     Rank 6   V1.1
		radioactive Weight   200000  Multiplier 8     Rank 9   V1.6
		ghost       Weight   100000  Multiplier 10    Rank 10  V1.3
		shadow      Weight    50000  Multiplier 12    Rank 11  V1.3
		solar       Weight    10000  Multiplier 20    Rank 13  V1.3
		lunar       Weight     6000  Multiplier 22    Rank 14  V1.3
		bloodmoon   Weight     2500  Multiplier 28    Rank 15  V1.3
		celestial   Weight      350  Multiplier 60    Rank 17  V1.3
		ancient     Weight      100  Multiplier 80    Rank 18  V1.3

		Their combined weight (2,069,000) currently sits in `none`.
	]]
}

--[[
	[weatherId] = { [mutationId] = weightMultiplier }

	Applied to the weight table BEFORE luck, then everything renormalises. Only
	V1 weathers appear here; WeatherService arrives in Step 17.
]]
MutationConfig.WeatherModifiers = {
	clear = {},
	rainstorm = {},
	thunderstorm = { electric = 25 },
	blizzard = { frozen = 25 },
}

-- ── Helpers ─────────────────────────────────────────────────────────────────

function MutationConfig.Get(mutationId: string?): Mutation?
	if not mutationId then
		return (MutationConfig.List :: any).none
	end
	return (MutationConfig.List :: any)[mutationId]
end

--[[
	Combined income multiplier for a dinosaur's mutations. nil, "none", or an
	unknown id all yield 1, so callers never have to special-case an un-mutated
	dinosaur.
]]
function MutationConfig.MultiplierFor(primary: string?, secondary: string?): number
	local total = 1
	for _, id in { primary, secondary } do
		local mutation = MutationConfig.Get(id)
		if mutation and mutation.Id ~= "none" then
			total *= mutation.Multiplier
		end
	end
	return total
end

--- Rarer mutation first: "Void Golden Tyrannosaurus Rex".
function MutationConfig.DisplayPrefix(primary: string?, secondary: string?): string
	local first = MutationConfig.Get(primary)
	local second = MutationConfig.Get(secondary)

	local parts = {}
	if first and first.Id ~= "none" then
		table.insert(parts, first)
	end
	if second and second.Id ~= "none" then
		table.insert(parts, second)
	end
	if #parts == 0 then
		return ""
	end

	table.sort(parts, function(a, b)
		return a.Rank > b.Rank
	end)

	local names = {}
	for _, mutation in parts do
		table.insert(names, mutation.DisplayName)
	end
	return table.concat(names, " ") .. " "
end

function MutationConfig.MutPowers(): { [string]: number }
	local powers = {}
	for id, mutation in MutationConfig.List :: any do
		powers[id] = mutation.MutPower
	end
	return powers
end

--- Weights with only the shipped mutations, for rolling. Anything with
--- InV1 = false is folded into `none` so the table always sums to WeightTotal.
function MutationConfig.RollableWeights(): { [string]: number }
	local weights = {}
	for id, mutation in MutationConfig.List :: any do
		if mutation.InV1 then
			weights[id] = mutation.Weight
		end
	end
	return weights
end

function MutationConfig.GetColor(mutationId: string?): Color3
	local mutation = MutationConfig.Get(mutationId)
	return Color3.fromHex(if mutation then mutation.Color else "FFFFFF")
end

return MutationConfig
