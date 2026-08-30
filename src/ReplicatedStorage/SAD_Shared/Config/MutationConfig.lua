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


-- ═══ VISUALS ════════════════════════════════════════════════════════════════

--[[
	═══ WHY THIS IS NOT `Vfx` ══════════════════════════════════════════════════
	Every mutation carries a `Vfx` name - "Mut_Golden", "Mut_Void" - naming a
	particle effect in `SAD_Assets/Effects`. That folder is empty and nothing in
	the game has ever read the field. It is the same registered-but-inert shape
	as findings 29, 30 and 56: a name that looks like wiring and is decoration.

	The names stay, because when the effects are authored they are what
	`AssetBuilder` will look up. But a mutation must be VISIBLE before then, or
	a x150 Void dinosaur looks exactly like a plain one, and the loudest moment
	in the game - a 1-in-2-million hatch - lands with nothing on screen.

	So this table is the procedural stand-in: no asset ids, no particle
	textures, nothing invented. A recolour, a material, and for the four
	mutations the game already announces, a `Highlight` outline.
	═══════════════════════════════════════════════════════════════════════════

	  Blend            how far the hide moves toward the mutation colour, 0..1
	  Material         for parts tinted Body / Belly / Limb
	  AccentMaterial   for parts tinted Accent (defaults to Material)
	  Transparency     added to every part, for the glassy ones
	  Rainbow          per-part hue wheel instead of one flat tint
	  Glow             a Highlight outline

	Materials are restricted to seven I am certain exist as PART materials
	(as opposed to terrain-only ones): SmoothPlastic, Metal, Glass, Ice, Neon,
	Marble, Foil. `MutationConfig.Materials` is that list and the spec asserts
	nothing outside it is ever named.
]]
MutationConfig.Materials = {
	SmoothPlastic = true, Metal = true, Glass = true, Ice = true,
	Neon = true, Marble = true, Foil = true,
}

--[[
	Below this brightness a mutation colour cannot carry an accent - it would be
	a dark smudge on a dark hide. The accent takes the bright complement
	instead. Same rule, same threshold and the same reasoning as
	`BodyPlanConfig.DarkRaritySwap`; kept as its own constant because the two
	tables are read by different systems and a shared constant between them
	would be a dependency neither needs.
]]
MutationConfig.DarkVisualSwap = 0.30

MutationConfig.Visuals = {
	-- x2, 12% of hatches. The common one, so it reads instantly and cheaply.
	golden = { Blend = 0.90, Material = "Metal" },

	-- x3. Glass with a little transparency; the species colour shows through,
	-- which is what separates Crystal from Diamond at a glance.
	crystal = { Blend = 0.80, Material = "Glass", Transparency = 0.25 },

	-- x3.5. Ice is the one material that says "frozen" without a particle.
	frozen = { Blend = 0.85, Material = "Ice" },

	-- x4. Body stays matte, crests and plates go Neon - the charge is on the
	-- extremities, which is also where the shape already is.
	electric = { Blend = 0.70, Material = "SmoothPlastic", AccentMaterial = "Neon" },

	-- x6, and the first the game announces. Near-white glass, Neon edges.
	diamond = { Blend = 0.88, Material = "Glass", AccentMaterial = "Neon",
		Transparency = 0.15, Glow = true },

	-- x15. Every part a different hue around the wheel, which is a rainbow
	-- with no texture and no animation loop to keep in sync.
	rainbow = { Blend = 1.00, Material = "SmoothPlastic", AccentMaterial = "Neon",
		Rainbow = true, Glow = true },

	-- x35. Marble mottles the dark purple, so it reads as depth rather than
	-- as a flat repaint.
	galaxy = { Blend = 0.92, Material = "Marble", AccentMaterial = "Neon", Glow = true },

	-- x150, 1 in 2,000,000. Almost black - the accent swap below is what stops
	-- it being an unreadable silhouette.
	void = { Blend = 0.97, Material = "SmoothPlastic", AccentMaterial = "Neon", Glow = true },
}

local function hexToHsv(hex: string): (number, number, number)
	local n = tonumber(hex, 16) or 0
	local r = bit32.rshift(n, 16) % 256 / 255
	local g = bit32.rshift(n, 8) % 256 / 255
	local b = n % 256 / 255

	local maxC = math.max(r, g, b)
	local minC = math.min(r, g, b)
	local delta = maxC - minC

	local h = 0
	if delta > 0 then
		if maxC == r then
			h = ((g - b) / delta) % 6
		elseif maxC == g then
			h = (b - r) / delta + 2
		else
			h = (r - g) / delta + 4
		end
		h /= 6
	end

	return h, (if maxC == 0 then 0 else delta / maxC), maxC
end

local function hsvToHex(h: number, s: number, v: number): string
	local c = v * s
	local x = c * (1 - math.abs((h * 6) % 2 - 1))
	local m = v - c
	local segment = math.floor(h * 6) % 6

	local r, g, b
	if segment == 0 then r, g, b = c, x, 0
	elseif segment == 1 then r, g, b = x, c, 0
	elseif segment == 2 then r, g, b = 0, c, x
	elseif segment == 3 then r, g, b = 0, x, c
	elseif segment == 4 then r, g, b = x, 0, c
	else r, g, b = c, 0, x end

	return string.format("%02X%02X%02X",
		math.round((r + m) * 255), math.round((g + m) * 255), math.round((b + m) * 255))
end

MutationConfig.HexToHsv = hexToHsv
MutationConfig.HsvToHex = hsvToHex

--[[
	The finished recipe for a dinosaur, or nil when it is unmutated.

	═══ WHY A STACK GETS TWO COLOURS ═══════════════════════════════════════════
	`MaxStack` is 2, so "Golden Rainbow" is a thing that exists, and
	`DisplayPrefix` already names both. One blended average of two mutation
	colours would render every pair as mud and lose the information the name
	promises. So the PRIMARY decides the hide, its material and whether it
	glows; the SECONDARY takes the accent - the crests, plates, frills and sails
	that BodyPlanConfig already separates out. Two mutations, two colours, on
	the parts that were already distinct.
	═══════════════════════════════════════════════════════════════════════════
]]
function MutationConfig.SkinFor(primary: string?, secondary: string?)
	if not primary or primary == "none" then
		return nil
	end

	local mutation = MutationConfig.List[primary]
	local recipe = MutationConfig.Visuals[primary]
	if not mutation or not recipe then
		return nil
	end

	local bodyHex = mutation.Color

	--[[
		The accent, in order of preference: the second mutation's colour, or -
		when the primary is too dark to carry one - its bright complement, or
		the primary colour itself.
	]]
	local accentHex = bodyHex
	local second = secondary and secondary ~= "none" and MutationConfig.List[secondary]
	if second then
		accentHex = second.Color
	else
		local h, _, v = hexToHsv(bodyHex)
		if v < MutationConfig.DarkVisualSwap then
			accentHex = hsvToHex((h + 0.5) % 1, 0.85, 1.0)
		end
	end

	return {
		Body = bodyHex,
		Accent = accentHex,
		Blend = recipe.Blend,
		Material = recipe.Material,
		AccentMaterial = recipe.AccentMaterial or recipe.Material,
		Transparency = recipe.Transparency or 0,
		Rainbow = recipe.Rainbow == true,
		--[[
			Tied to `AnnounceKind`, not to a second threshold. If the game
			stops the room to tell everyone about a hatch, the dinosaur it
			produced should be findable in a park afterwards - and if it does
			not, it should not be wearing an outline. One field, one meaning.

			It also bounds the count: Roblox stops rendering Highlights past a
			few dozen adornees, and diamond - the commonest announced mutation
			- is 1 in 250 hatches.
		]]
		Glow = mutation.AnnounceKind ~= nil,
	}
end

--[[
	Every shipped mutation must have a visual, and its Glow must agree with its
	AnnounceKind. Called by ConfigValidator rule 13.
]]
function MutationConfig.ValidateVisuals(): (boolean, { string })
	local problems = {}

	for id, mutation in MutationConfig.List :: any do
		if id == "none" or not mutation.InV1 then
			continue
		end

		local recipe = MutationConfig.Visuals[id]
		if not recipe then
			table.insert(problems, "shipped mutation '" .. id .. "' has no visual")
			continue
		end
		if not MutationConfig.Materials[recipe.Material] then
			table.insert(problems, id .. " names material '" .. tostring(recipe.Material) .. "'")
		end
		if recipe.AccentMaterial and not MutationConfig.Materials[recipe.AccentMaterial] then
			table.insert(problems, id .. " names accent material '" .. tostring(recipe.AccentMaterial) .. "'")
		end
		if recipe.Blend <= 0 or recipe.Blend > 1 then
			table.insert(problems, string.format("%s blends %.2f, which is outside 0..1", id, recipe.Blend))
		end

		local skin = MutationConfig.SkinFor(id, nil)
		if not skin then
			table.insert(problems, id .. " has a visual but SkinFor returned nothing")
		elseif skin.Glow ~= (mutation.AnnounceKind ~= nil) then
			table.insert(problems, id .. " glows but is not announced, or is announced and does not glow")
		end
	end

	for id in MutationConfig.Visuals do
		local mutation = MutationConfig.List[id]
		if not mutation then
			table.insert(problems, "visual for unknown mutation '" .. id .. "'")
		elseif not mutation.InV1 then
			table.insert(problems, "visual for unshipped mutation '" .. id .. "'")
		end
	end

	return #problems == 0, problems
end

function MutationConfig.GetColor(mutationId: string?): Color3
	local mutation = MutationConfig.Get(mutationId)
	return Color3.fromHex(if mutation then mutation.Color else "FFFFFF")
end

return MutationConfig
