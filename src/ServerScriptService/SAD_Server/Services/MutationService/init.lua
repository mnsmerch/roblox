--!nonstrict
--[[
	MutationService
	ServerScriptService/SAD_Server/Services/MutationService  (ModuleScript)

	Rolls mutations. REVEAL #3, and the one players actually chase.

	═══ WHY IT ROLLS AT HATCH, NOT AT PICKUP ═══════════════════════════════════
	Rarity is decided when an egg is taken; the mutation is decided when it
	opens. That is deliberate (docs/04 §1): the weather at the MOMENT OF
	HATCHING modifies these weights, so players hoard eggs until a Blood Moon
	and the whole server anticipates one together. Coordinated excitement for
	free, out of a single scheduling choice.
	═══════════════════════════════════════════════════════════════════════════

	Order of operations, and it matters:
	  1. Start from the shipped weights (unshipped mutations fold into `none`).
	  2. Apply WEATHER as weight multipliers, capped.
	  3. Apply MUTATION LUCK, which redistributes out of `none` into the bands.
	  4. Pick.
	  5. If it mutated, roll Prime - a 1-in-2000 second, different mutation.

	Weather before luck because weather is a property of the world and luck is a
	property of the player: a Thunderstorm should multiply Electric's presence
	in the pool, and then the player's genetics upgrade should improve their
	share of whatever pool exists.

	API:
		MutationService.Roll(player) -> mutation, mutation2?
		MutationService.RollIn(mutLuck, weatherId, rng?) -> mutation, mutation2?
		MutationService.ComputeMutLuck(player) -> number
		MutationService.MutLuckFrom(data) -> number        pure
		MutationService.SetWeather(weatherId)              Step 17 drives this
		MutationService.GetWeather() -> string

	Depends on: MutationConfig, RebirthConfig, UpgradeConfig, RNG, Log.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local MutationConfig = require(Shared.Config.MutationConfig)
local RebirthConfig = require(Shared.Config.RebirthConfig)
local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local Log = require(Shared.Modules.Log)
local RNG = require(Shared.Modules.RNG)

local MutationService = {}

local PlayerDataService

local rng = RNG.new()
local currentWeather = "clear"
local mutPowers = nil

-- ── Weather ─────────────────────────────────────────────────────────────────

--- Step 17's WeatherService owns this. Until then everything hatches in clear
--- skies, which is the correct baseline rather than a placeholder.
function MutationService.SetWeather(weatherId: string)
	currentWeather = weatherId or "clear"
end

function MutationService.GetWeather(): string
	return currentWeather
end

-- ── Luck ────────────────────────────────────────────────────────────────────

--[[
	Mutation luck as an additive fraction. Pure, so the composition is testable.

	Live today: the Incubator Genetics upgrade and rebirths. Arriving with their
	steps: the Mutation Master gamepass (21), mutation serums (18/21), the
	Zone 8 radiation field (1.6). Listed so nobody has to go looking.
]]
function MutationService.MutLuckFrom(data): number
	local luck = 0
	luck += UpgradeConfig.EffectAt("incubatorGenetics", data.Upgrades.incubatorGenetics or 0)
	luck += RebirthConfig.MutLuckBonus(data.Rebirths)

	-- docs/04 §1.2 caps MutLuck at 4.0.
	return math.clamp(luck, 0, 4.0)
end

function MutationService.ComputeMutLuck(player: Player): number
	local data = PlayerDataService.Get(player)
	if not data then
		return 0
	end
	return MutationService.MutLuckFrom(data)
end

-- ── Rolling ─────────────────────────────────────────────────────────────────

--[[
	The roll itself. Pure apart from the generator, so the published odds in
	docs/04 can be asserted directly rather than played for.

	Returns (mutationId, secondMutationId?). `none` is a real result, not a nil.
]]
function MutationService.RollIn(mutLuck: number, weatherId: string?, generator: Random?): (string, string?)
	local generatorToUse = generator or rng

	local weights = MutationConfig.RollableWeights()

	-- Weather first: it shapes the pool, luck then shapes the player's share.
	local modifiers = MutationConfig.WeatherModifiers[weatherId or "clear"]
	if modifiers and next(modifiers) then
		weights = RNG.ApplyModifiers(weights, modifiers, MutationConfig.WeatherModifierCap)
	end

	weights = RNG.ApplyLuck(weights, mutPowers or MutationConfig.MutPowers(), mutLuck)

	local primary = RNG.WeightedPick(weights, generatorToUse) or "none"
	if primary == "none" then
		return "none", nil
	end

	--[[
		PRIME. A 1-in-2000 second mutation, capped at two ever.

		Uncapped stacking reaches x720,000 and breaks the economy; two tops out
		around x9,000 at roughly 1 in 1.7 billion, which is a legend rather than
		a balance problem (docs/04 §1.1).
	]]
	if not RNG.Chance(MutationConfig.PrimeChance, generatorToUse) then
		return primary, nil
	end

	-- The second must be DIFFERENT and cannot be `none`, so both are removed
	-- from the pool before re-rolling rather than re-rolled until they differ.
	local secondaryWeights = {}
	for id, weight in weights do
		if id ~= "none" and id ~= primary then
			secondaryWeights[id] = weight
		end
	end

	local secondary = RNG.WeightedPick(secondaryWeights, generatorToUse)
	return primary, secondary
end

function MutationService.Roll(player: Player): (string, string?)
	return MutationService.RollIn(
		MutationService.ComputeMutLuck(player),
		currentWeather
	)
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function MutationService.Init(app)
	PlayerDataService = app.Get("PlayerDataService")
	mutPowers = MutationConfig.MutPowers()
end

function MutationService.Start(app)
	Log.info("MutationService", "Ready. Prime chance 1 in %d, weather '%s'",
		MutationConfig.PrimeChance, currentWeather)
end

return MutationService
