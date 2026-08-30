--!nonstrict
--[[
	ConfigValidator
	ReplicatedStorage/SAD_Shared/Config/ConfigValidator  (ModuleScript)

	Runs at boot, before any service loads. Implements the content rules in
	docs/11-content-config.md §8.

	The point: content bugs in a game like this are SILENT. A zone that can roll
	a rarity it has no species for does not throw - it rolls, finds an empty
	bucket, and hands the player nothing, three weeks after launch, on one
	server, once. Weights that sum to 99,999,999 do not throw either; they just
	make the published odds a lie. Every rule here converts one of those into a
	loud failure at start-up.

	In Studio it prints a full report and (under StrictBoot) aborts.
	In production it aborts too - a server that cannot hatch what it rolls is
	worse than a server that does not start.

	Configs are INJECTED rather than required directly, so the whole thing runs
	against fixtures in tests/step3_spec.lua - including deliberately broken
	configs, because a validator nobody has watched fail is not a validator.

		ConfigValidator.Run(configs) -> { errors, warnings, checks }
		ConfigValidator.RunDefault() -> same, resolving from script.Parent

	Depends on: nothing (configs arrive as arguments).
]]

local ConfigValidator = {}

--[[
	Configs that do not exist yet are SKIPPED with a note rather than failing.
	Same principle as Bootstrap's service roster: rules light up as the content
	they check gets built, so this file is written once and never revisited.
]]
local OPTIONAL_CONFIGS = {
	Event = "EventConfig (Step 18)",
	Product = "ProductConfig (Step 21)",
	--[[
		QuestConfig and DailyConfig were listed here as forward declarations
		and no rule ever read them. Removed at Step 19 rather than left as
		labels for a skip that never happens - findings #29 and #30 in
		PROGRESS.md are both about exactly that kind of decoration.

		Their invariants are asserted where they can fail loudly instead:
		QuestConfig asserts id uniqueness at load, and
		QuestService.ValidateEmitters asserts the metric/emitter sets match at
		Start.
	]]
	Weather = "WeatherConfig (Step 17)",
	Assets = "SAD_Assets (Step 7)",
	BodyPlan = "BodyPlanConfig + ChaseConfig",
	MutationVisuals = "MutationConfig.Visuals (a fixture without functions)",
}

local function newReport()
	return {
		errors = {},
		warnings = {},
		checks = {},
		skipped = {},
	}
end

local function fail(report, rule: string, message: string, ...)
	local body = if select("#", ...) > 0 then string.format(message, ...) else message
	table.insert(report.errors, string.format("[%s] %s", rule, body))
end

local function warn(report, rule: string, message: string, ...)
	local body = if select("#", ...) > 0 then string.format(message, ...) else message
	table.insert(report.warnings, string.format("[%s] %s", rule, body))
end

local function pass(report, rule: string, message: string, ...)
	local body = if select("#", ...) > 0 then string.format(message, ...) else message
	table.insert(report.checks, string.format("[%s] %s", rule, body))
end

-- ═══ Rules ═════════════════════════════════════════════════════════════════

--- Rule 1: every zone's rarity weight vector sums exactly to WeightTotal.
local function ruleRarityWeightSums(report, c)
	local total = c.Rarity.WeightTotal
	local zoneCount = 0

	for zoneId, weights in c.Rarity.ZoneWeights do
		zoneCount += 1
		local sum = 0
		for _, weight in weights do
			sum += weight
		end
		if sum ~= total then
			fail(report, "R1", "zone '%s' weights sum to %d, expected %d (off by %d)",
				zoneId, sum, total, sum - total)
		end

		-- A tier missing from a vector reads as "impossible", which is usually
		-- a typo rather than intent. Explicit 0 says it was deliberate.
		for _, rarityId in c.Rarity.Order do
			if weights[rarityId] == nil then
				fail(report, "R1", "zone '%s' has no entry for rarity '%s' - write 0 if that is intended",
					zoneId, rarityId)
			end
		end
	end

	if zoneCount == 0 then
		fail(report, "R1", "no zone weight vectors defined at all")
	else
		pass(report, "R1", "%d zone weight vector(s) sum to %d", zoneCount, total)
	end
end

--- Rule 2: mutation weights sum exactly to WeightTotal.
local function ruleMutationWeightSum(report, c)
	local total = c.Mutation.WeightTotal
	local sum = 0
	local shipped = 0

	for _, mutation in c.Mutation.List do
		if mutation.InV1 then
			sum += mutation.Weight
			shipped += 1
		end
	end

	if sum ~= total then
		fail(report, "R2", "shipped mutation weights sum to %d, expected %d (off by %d)",
			sum, total, sum - total)
	else
		pass(report, "R2", "%d shipped mutation(s) sum to %d", shipped, total)
	end

	if not c.Mutation.List.none then
		fail(report, "R2", "no 'none' entry - every hatch must be able to roll no mutation")
	end
end

--- Rule 3: every species names a rarity that exists.
local function ruleSpeciesRarities(report, c)
	local count = 0
	for id, entry in c.Dino.Species do
		count += 1
		if not c.Rarity.Tiers[entry.Rarity] then
			fail(report, "R3", "species '%s' has unknown rarity '%s'", id, tostring(entry.Rarity))
		end
	end
	pass(report, "R3", "%d species reference known rarities", count)
end

--- Rule 4: every species names zones that exist.
local function ruleSpeciesZones(report, c)
	for id, entry in c.Dino.Species do
		if type(entry.Zones) ~= "table" or #entry.Zones == 0 then
			fail(report, "R4", "species '%s' is in no zone - it can never be obtained", id)
			continue
		end
		for _, zoneId in entry.Zones do
			if not c.Zone.Zones[zoneId] then
				fail(report, "R4", "species '%s' references unknown zone '%s'", id, tostring(zoneId))
			end
		end
	end
	pass(report, "R4", "all species zone references resolve")
end

--- Rule 5: every zone in ZoneConfig has at least one species, and every zone
--- with a weight vector is a real zone.
local function ruleZoneCoverage(report, c)
	local index = c.Dino.BuildZoneIndex()

	for zoneId in c.Zone.Zones do
		if not index[zoneId] then
			fail(report, "R5", "zone '%s' has no species at all", zoneId)
		end
		if not c.Rarity.ZoneWeights[zoneId] then
			fail(report, "R5", "zone '%s' has no rarity weight vector", zoneId)
		end
	end

	for zoneId in c.Rarity.ZoneWeights do
		if not c.Zone.Zones[zoneId] then
			fail(report, "R5", "weight vector for '%s', which is not a zone", zoneId)
		end
	end

	pass(report, "R5", "zones, pools and weight vectors line up")
end

--[[
	Rule 6: THE IMPORTANT ONE.

	Every zone x rarity combination with a non-zero weight must have at least
	one species available in that zone. Otherwise the game rolls a rarity it
	cannot hatch - the player watches a three-hour Secret incubation finish and
	receives nothing.

	The error names the tier's V1 status, because "Zone 1 can roll Mythic and no
	Mythic ships until V1.1" is a scope decision, not a typo, and the two want
	different fixes.
]]
local function ruleRarityCoverage(report, c)
	local index = c.Dino.BuildZoneIndex()
	local combos, covered = 0, 0

	for zoneId, weights in c.Rarity.ZoneWeights do
		local zoneIndex = index[zoneId] or {}

		for _, rarityId in c.Rarity.Order do
			local weight = weights[rarityId] or 0
			if weight <= 0 then
				continue
			end

			combos += 1
			local bucket = zoneIndex[rarityId]

			if not bucket or #bucket == 0 then
				local tier = c.Rarity.Tiers[rarityId]
				local scope = if tier and tier.InV1 == false
					then " (that tier ships after V1 - set its weight to 0 until then)"
					else ""
				fail(report, "R6",
					"zone '%s' rolls %s at weight %d but has NO %s species%s",
					zoneId, rarityId, weight, rarityId, scope)
			else
				covered += 1
			end
		end
	end

	if combos > 0 and covered == combos then
		pass(report, "R6", "all %d rollable zone x rarity combinations have species", combos)
	end
end

--- Rule 7: every model name referenced by a species exists in SAD_Assets.
--- Skipped until the asset folders are populated in Step 7.
local function ruleAssetsExist(report, c)
	if not c.Assets then
		table.insert(report.skipped, OPTIONAL_CONFIGS.Assets)
		return
	end

	local dinos = c.Assets.Dinos or {}
	local eggs = c.Assets.Eggs or {}

	local checked = 0
	for id, entry in c.Dino.Species do
		checked += 1
		if not dinos[entry.ModelName] then
			fail(report, "R7", "species '%s' needs model '%s' in SAD_Assets/Dinos", id, entry.ModelName)
		end
		if not eggs[entry.EggModelName] then
			fail(report, "R7", "species '%s' needs egg model '%s' in SAD_Assets/Eggs", id, entry.EggModelName)
		end
	end

	-- The generic nest egg. No species names it - rarity is not rolled until
	-- pickup - so nothing above would catch it going missing.
	if not eggs.Egg_Wild then
		fail(report, "R7", "SAD_Assets/Eggs/Egg_Wild is missing - nests have nothing to show")
	end

	pass(report, "R7", "%d species models and the wild egg resolve", checked)
end

--- Rule 8: every event names a handler module that exists.
local function ruleEventHandlers(report, c)
	if not c.Event then
		table.insert(report.skipped, OPTIONAL_CONFIGS.Event)
		return
	end
	for id, event in c.Event.Events do
		if not event.Handler or event.Handler == "" then
			fail(report, "R8", "event '%s' names no handler", id)
		elseif c.EventHandlers and not c.EventHandlers[event.Handler] then
			fail(report, "R8", "event '%s' names handler '%s', which does not exist", id, event.Handler)
		end
	end
	pass(report, "R8", "all event handlers resolve")
end

--[[
	Rule 9: every upgrade Effect.Kind has a handler, costs grow, and the maximum
	effect stays sane. The last part catches the mistake that actually happens:
	a PerLevel that takes a multiplier through zero and into negative income.
]]
local function ruleUpgradeEffects(report, c)
	local boards = {}
	for _, board in c.Upgrade.Boards do
		boards[board] = true
	end

	local count = 0
	for id, entry in c.Upgrade.Tracks do
		count += 1

		if not entry.Effect or not entry.Effect.Kind then
			fail(report, "R9", "track '%s' has no Effect.Kind", id)
			continue
		end
		if c.UpgradeHandlers and not c.UpgradeHandlers[entry.Effect.Kind] then
			fail(report, "R9", "track '%s' uses Effect.Kind '%s', which has no handler", id, entry.Effect.Kind)
		end
		if not boards[entry.Board] then
			fail(report, "R9", "track '%s' is on unknown board '%s'", id, tostring(entry.Board))
		end
		if entry.MaxLevel < 1 then
			fail(report, "R9", "track '%s' has MaxLevel %d", id, entry.MaxLevel)
		end
		if entry.Growth <= 1 then
			fail(report, "R9", "track '%s' has Growth %.2f - costs must rise or the sink never closes",
				id, entry.Growth)
		end

		local first = c.Upgrade.CostOf(id, 1)
		local last = c.Upgrade.CostOf(id, entry.MaxLevel)
		if entry.MaxLevel > 1 and last <= first then
			fail(report, "R9", "track '%s' costs do not increase (%d -> %d)", id, first, last)
		end

		-- Multiplicative effects must never reach zero or flip sign.
		local kind = entry.Effect.Kind
		if kind == "incubationMult" or kind == "carryPenaltyMult"
			or kind == "moveSpeedMult" or kind == "parkIncomeMult" then
			local maxEffect = c.Upgrade.MaxEffect(id)
			if maxEffect <= 0 then
				fail(report, "R9", "track '%s' reaches a multiplier of %.3f at max level", id, maxEffect)
			end
		end
	end

	pass(report, "R9", "%d upgrade track(s) validated", count)
end

--- Rule 10: every configured product id is a unique positive integer.
local function ruleProductIds(report, c)
	if not c.Product then
		table.insert(report.skipped, OPTIONAL_CONFIGS.Product)
		return
	end

	--[[
		An AssetId of 0 means NOT CONFIGURED YET, and it warns rather than
		failing. The Roblox experience does not exist yet, and a game with no
		store must still boot and be entirely playable - docs/07 §1 rule 1
		guarantees every paid effect exists free at lower magnitude, so a
		store-less build is a complete game rather than a broken one.

		Anything OTHER than 0 is held to the full rule: a positive integer,
		unique across both catalogues. A wrong id is far worse than a missing
		one, because it charges for somebody else's product.
	]]
	local seen = {}
	local configured, unconfigured = 0, 0

	for _, group in { c.Product.Gamepasses or {}, c.Product.Products or {} } do
		for id, entry in group do
			local assetId = entry.AssetId

			if assetId == 0 then
				unconfigured += 1
			elseif type(assetId) ~= "number" or assetId < 0 or assetId % 1 ~= 0 then
				fail(report, "R10", "'%s' has AssetId %s - must be a positive integer or 0",
					id, tostring(assetId))
			elseif seen[assetId] then
				fail(report, "R10", "AssetId %d is used by both '%s' and '%s'", assetId, seen[assetId], id)
			else
				seen[assetId] = id
				configured += 1
			end
		end
	end

	if unconfigured > 0 then
		warn(report, "R10", "%d product(s) have no AssetId yet - they cannot be sold", unconfigured)
	end
	pass(report, "R10", "%d configured product id(s), all unique; %d awaiting an id",
		configured, unconfigured)
end

-- ═══ Extra structural checks ═══════════════════════════════════════════════

--- Not one of the ten, but cheap and catches real mistakes.
local function ruleStructural(report, c)
	-- Rarity ranks must be unique and match Order.
	local seenRank = {}
	for id, tier in c.Rarity.Tiers do
		if seenRank[tier.Rank] then
			fail(report, "S1", "rarities '%s' and '%s' share Rank %d", seenRank[tier.Rank], id, tier.Rank)
		end
		seenRank[tier.Rank] = id
	end
	for position, rarityId in c.Rarity.Order do
		local tier = c.Rarity.Tiers[rarityId]
		if not tier then
			fail(report, "S1", "Order lists '%s', which has no tier", rarityId)
		elseif tier.Rank ~= position then
			fail(report, "S1", "'%s' is at Order position %d but has Rank %d", rarityId, position, tier.Rank)
		end
	end

	-- Income and incubation must both rise with rank, or the ladder is broken.
	local previousIncome, previousIncubation = -1, -1
	for _, rarityId in c.Rarity.Order do
		local tier = c.Rarity.Tiers[rarityId]
		if tier then
			if tier.BaseIncome <= previousIncome then
				fail(report, "S2", "'%s' income %d does not exceed the tier below (%d)",
					rarityId, tier.BaseIncome, previousIncome)
			end
			if tier.IncubationSecs <= previousIncubation then
				fail(report, "S2", "'%s' incubation %ds does not exceed the tier below (%ds)",
					rarityId, tier.IncubationSecs, previousIncubation)
			end
			previousIncome = tier.BaseIncome
			previousIncubation = tier.IncubationSecs
		end
	end

	-- Mutation multipliers must rise with rank.
	local ordered = {}
	for _, mutation in c.Mutation.List do
		table.insert(ordered, mutation)
	end
	table.sort(ordered, function(a, b)
		return a.Rank < b.Rank
	end)
	local previousMultiplier = 0
	for _, mutation in ordered do
		if mutation.Multiplier <= previousMultiplier then
			fail(report, "S3", "mutation '%s' (rank %d) multiplier %.1f does not exceed the one below (%.1f)",
				mutation.Id, mutation.Rank, mutation.Multiplier, previousMultiplier)
		end
		previousMultiplier = mutation.Multiplier
	end

	-- Species factors inside the documented band.
	for id, entry in c.Dino.Species do
		if entry.SpeciesFactor < 0.5 or entry.SpeciesFactor > 2.0 then
			fail(report, "S4", "species '%s' has SpeciesFactor %.2f, outside the sane band",
				id, entry.SpeciesFactor)
		end
	end

	pass(report, "S", "structural checks complete")
end

-- ═══ Entry points ══════════════════════════════════════════════════════════

--[[
	Rule 11: WeatherConfig and MutationConfig.WeatherModifiers name the same
	weathers.

	Two tables describe one thing here on purpose - weights and durations in
	one, mutation multipliers in the other, because a weather's mutation
	weights belong with the mutations. That is only safe while something checks
	they agree. A weather in one and not the other is either a weather that
	rolls and does nothing, or a modifier table nothing can reach.
]]
local function ruleWeatherTables(report, c)
	if not c.Weather then
		table.insert(report.skipped, OPTIONAL_CONFIGS.Weather)
		return
	end

	local checked = 0
	for id, entry in c.Weather.Weathers do
		if not entry.InV1 then
			continue
		end
		checked += 1

		if c.Mutation.WeatherModifiers[id] == nil then
			fail(report, "R11", "weather '%s' has no entry in MutationConfig.WeatherModifiers", id)
		end
		if entry.Weight <= 0 then
			fail(report, "R11", "weather '%s' has weight %d and can never roll", id, entry.Weight)
		end
		if id ~= "clear" and entry.DurationSecs <= 0 then
			fail(report, "R11", "weather '%s' has no duration", id)
		end
	end

	for id in c.Mutation.WeatherModifiers do
		local entry = c.Weather.Weathers[id]
		if not entry then
			fail(report, "R11", "MutationConfig.WeatherModifiers has '%s', which is not a weather", id)
		elseif not entry.InV1 then
			fail(report, "R11", "weather '%s' has modifiers but is not in V1", id)
		end
	end

	--[[
		A cap at or below 1 would mean no weather could shift anything, which
		is a whole system quietly switched off.
	]]
	if c.Mutation.WeatherModifierCap <= 1 then
		fail(report, "R11", "WeatherModifierCap is %.2f, so no weather can shift anything",
			c.Mutation.WeatherModifierCap)
	end

	pass(report, "R11", "%d weather(s) validated against their mutation modifiers", checked)
end

--[[
	R12: every species resolves to a body plan, and every plan stands on the
	ground inside its tile.

	`BodyPlanConfig.Validate` does the measuring - it is the same function
	tests/bodyplan_spec.lua calls, so the boot check and the offline check
	cannot disagree about what "valid" means. This rule exists so a placeholder
	that hovers, clips its neighbour, or silently falls back to the generic
	theropod fails the boot rather than being noticed in a Play session.
]]
local function ruleBodyPlans(report, c)
	--[[
		Skips rather than fails when either is absent, the same as rules 7, 8,
		10 and 11 - a caller assembling `configs` by hand to exercise one rule
		should not have to supply every other rule's inputs.

		The protection against this becoming another registered-but-inert rule
		is not here: it is that `RunDefault` supplies both unconditionally, and
		that `Run` fails any rule reporting neither a pass, a skip nor an error.
		A skip shows up in the boot log as a line, not as silence.
	]]
	if not c.BodyPlan or not c.Chase then
		table.insert(report.skipped, OPTIONAL_CONFIGS.BodyPlan)
		return
	end

	local ok, problems = c.BodyPlan.Validate(c.Chase, c.Dino)
	if not ok then
		for _, problem in problems do
			fail(report, "R12", "%s", problem)
		end
		return
	end

	local plans = 0
	for _ in c.BodyPlan.Plans do
		plans += 1
	end

	--[[
		Counting the species per plan is what catches the opposite failure: not
		a broken plan, but a plan nothing points at any more, which means a
		species quietly lost its silhouette to the fallback.
	]]
	local used = {}
	local species = 0
	for _, entry in c.Dino.Species do
		species += 1
		used[c.BodyPlan.PlanIdFor(entry)] = true
	end
	local usedCount = 0
	for _ in used do
		usedCount += 1
	end

	if usedCount < plans then
		warn(report, "R12", "%d of %d body plan(s) are used by no species", plans - usedCount, plans)
	end

	pass(report, "R12", "%d species across %d body plan(s)", species, plans)
end

--[[
	R13: every shipped mutation has a visual, and the ones that glow are exactly
	the ones the game announces.

	`MutationConfig.ValidateVisuals` does the measuring, so the boot check and
	tests/mutation_visual_spec.lua cannot disagree. The failure this catches is
	silent by nature: a mutation with no visual is a dinosaur that renders as if
	it had no mutation, which is only noticeable if you already know what you
	were supposed to be looking at.
]]
local function ruleMutationVisuals(report, c)
	--[[
		A hand-assembled Mutation fixture (step3_spec has several) carries
		weights and multipliers but no functions. Skipping is right: those
		fixtures exist to exercise the weight rules, not this one.

		Written as a type check rather than `c.Mutation.ValidateVisuals and
		c.Mutation.ValidateVisuals()`, which is how I first wrote it - an
		`and` expression truncates a call to a single value, so `problems`
		would have been nil on every failure and the loop below would have
		errored instead of reporting.
	]]
	if type(c.Mutation.ValidateVisuals) ~= "function" then
		table.insert(report.skipped, OPTIONAL_CONFIGS.MutationVisuals)
		return
	end

	local ok, problems = c.Mutation.ValidateVisuals()
	if not ok then
		for _, problem in problems do
			fail(report, "R13", "%s", problem)
		end
		return
	end

	local shipped, glowing = 0, 0
	for id, mutation in c.Mutation.List do
		if id ~= "none" and mutation.InV1 then
			shipped += 1
			if mutation.AnnounceKind ~= nil then
				glowing += 1
			end
		end
	end
	pass(report, "R13", "%d shipped mutation(s) have a visual, %d of them glow", shipped, glowing)
end

--[[
	The rule list.

	`RULES` is asserted contiguous and all-functions immediately below. That is
	not paranoia: a rule registered here whose function was never defined is a
	`nil` in the middle of the array, and a nil in an array is not an error -
	it is a hole that generalized iteration steps straight over. Rule 11 spent
	a whole step in exactly that state, registered and never once running.

	Same failure the Migrations chain was hardened against in Step 2, arriving
	from the other direction.
]]
local RULES = {
	ruleRarityWeightSums,
	ruleMutationWeightSum,
	ruleSpeciesRarities,
	ruleSpeciesZones,
	ruleZoneCoverage,
	ruleRarityCoverage,
	ruleAssetsExist,
	ruleEventHandlers,
	ruleUpgradeEffects,
	ruleProductIds,
	ruleWeatherTables,
	ruleBodyPlans,
	ruleMutationVisuals,
	ruleStructural,
}

--- Asserted at load, so a mis-registered rule cannot reach a running game.
for index = 1, 14 do
	assert(type(RULES[index]) == "function",
		string.format("[SAD] ConfigValidator: rule #%d is %s, not a function - it is "
			.. "registered in RULES but never defined", index, typeof(RULES[index])))
end
assert(RULES[15] == nil, "[SAD] ConfigValidator: RULES has more entries than the count asserted above")

--[[
	`configs` needs at minimum: Rarity, Mutation, Dino, Zone, Upgrade.
	Optional: Event, EventHandlers, Product, Assets, UpgradeHandlers, Weather.
]]
function ConfigValidator.Run(configs)
	local report = newReport()

	for _, required in { "Rarity", "Mutation", "Dino", "Zone", "Upgrade" } do
		if not configs[required] then
			fail(report, "R0", "%sConfig was not supplied to the validator", required)
		end
	end
	if #report.errors > 0 then
		return report
	end

	--[[
		Every rule must SAY something - a pass, a skip, or a failure. A rule
		that reports nothing has silently done nothing, which is how rule 11
		spent a whole step registered but never given the config it reads.

		Counted rather than inspected, because the rules append to shared lists
		and the count is the only thing that cannot be faked by a rule that
		merely looks busy.
	]]
	for index, rule in RULES do
		local before = #report.checks + #report.skipped + #report.errors + #report.warnings

		local ok, err = pcall(rule, report, configs)
		if not ok then
			fail(report, "R0", "a validation rule itself errored: %s", tostring(err))
			continue
		end

		local after = #report.checks + #report.skipped + #report.errors + #report.warnings
		if after == before then
			fail(report, "R0",
				"rule #%d ran but reported nothing - it is probably missing the config it reads",
				index)
		end
	end

	return report
end

--- Resolves the configs from this module's own parent folder.
function ConfigValidator.RunDefault()
	local parent = script.Parent

	local function optional(name)
		local child = parent:FindFirstChild(name)
		return if child then require(child) else nil
	end

	--[[
		The event handler modules, by name. Looked up in ServerScriptService and
		only on the server: the client validates content too, and it has no
		handlers folder - so there it returns nil and rule 8 skips rather than
		failing on something that is not its business.
	]]
	local function eventHandlers()
		local ok, found = pcall(function()
			local services = game:GetService("ServerScriptService")
				:FindFirstChild("SAD_Server")
			local eventService = services and services:FindFirstChild("Services")
				and services.Services:FindFirstChild("EventService")
			return eventService and eventService:FindFirstChild("Handlers")
		end)
		if not ok or not found then
			return nil
		end

		local names = {}
		for _, module in found:GetChildren() do
			if module:IsA("ModuleScript") then
				names[module.Name] = true
			end
		end
		return names
	end

	-- Assets are read through AssetBuilder's manifest, which is populated by
	-- Bootstrap before this runs. If SAD_Assets does not exist yet, rule 7
	-- reports itself skipped rather than failing the boot.
	local assets = nil
	local modules = parent.Parent:FindFirstChild("Modules")
	local assetBuilder = modules and modules:FindFirstChild("AssetBuilder")
	if assetBuilder then
		assets = require(assetBuilder).Manifest()
	end

	return ConfigValidator.Run({
		Rarity = require(parent.RarityConfig),
		Mutation = require(parent.MutationConfig),
		Dino = require(parent.DinoConfig),
		Zone = require(parent.ZoneConfig),
		Upgrade = require(parent.UpgradeConfig),
		--[[
			Rule 9's handler hook, reserved since Step 3 and filled in at Step
			13. Stats.KindToField IS the handler table: a track whose
			Effect.Kind is not in it computes nothing, so the player buys an
			upgrade that does exactly nothing and nothing throws.
		]]
		UpgradeHandlers = require(parent.Parent.Modules.Stats).KindToField,
		--[[
			Rule 11's input (Step 17). A rule registered without the config it
			reads skips forever and reports nothing - which is exactly what
			happened to this line between Steps 17 and 18. `Run` now refuses a
			rule that reports neither a pass nor a skip, so the same omission
			cannot be silent twice.
		]]
		Weather = require(parent.WeatherConfig),
		--[[
			Rule 8's two inputs, reserved since Step 3 and filled in at Step 18.
			EventHandlers is the folder of handler modules by name, so an event
			naming a handler that does not exist fails at boot rather than
			firing into nothing.
		]]
		Event = optional("EventConfig"),
		EventHandlers = eventHandlers(),
		Assets = assets,
		--[[
			Rule 10's input, reserved since Step 3 and filled in at Step 21.
			`optional` still, because a build with no store is a build the
			validator should pass rather than refuse.
		]]
		Product = optional("ProductConfig"),
		--[[
			Rule 12's two inputs. Both are required rather than optional: a
			build with no body plans is a build where all 35 species look
			identical, which is not something to pass quietly.
		]]
		BodyPlan = require(parent.BodyPlanConfig),
		Chase = require(parent.ChaseConfig),
	})
end

--- Formats a report for the Output window.
function ConfigValidator.Format(report): string
	local lines = {}

	for _, check in report.checks do
		table.insert(lines, "  ok      " .. check)
	end
	for _, skip in report.skipped do
		table.insert(lines, "  skipped " .. skip .. " - not built yet")
	end
	for _, warning in report.warnings do
		table.insert(lines, "  WARN    " .. warning)
	end
	for _, err in report.errors do
		table.insert(lines, "  ERROR   " .. err)
	end

	table.insert(lines, string.format(
		"  %d passed, %d warning(s), %d error(s), %d skipped",
		#report.checks, #report.warnings, #report.errors, #report.skipped
	))

	return table.concat(lines, "\n")
end

return ConfigValidator
