--[[
	Step 3 specification.

	Two jobs:
	  1. Verify the content data matches the design documents. Every number in
	     docs/01, /02, /04 and /05 that a system will read is asserted here.
	  2. Verify ConfigValidator actually catches broken content. A validator
	     nobody has watched fail is not a validator.

	All six config modules are dependency-free by design, so this spec needs no
	Roblox shims at all - colours are hex strings and Color3 is only built
	lazily inside GetColor().

	Run with:  ./tests/run.sh
]]

--@INJECT TableUtil=src/ReplicatedStorage/SAD_Shared/Modules/TableUtil.lua RarityConfig=src/ReplicatedStorage/SAD_Shared/Config/RarityConfig.lua MutationConfig=src/ReplicatedStorage/SAD_Shared/Config/MutationConfig.lua DinoConfig=src/ReplicatedStorage/SAD_Shared/Config/DinoConfig.lua ZoneConfig=src/ReplicatedStorage/SAD_Shared/Config/ZoneConfig.lua UpgradeConfig=src/ReplicatedStorage/SAD_Shared/Config/UpgradeConfig.lua RebirthConfig=src/ReplicatedStorage/SAD_Shared/Config/RebirthConfig.lua ConfigValidator=src/ReplicatedStorage/SAD_Shared/Config/ConfigValidator.lua@

local passed, failed = 0, 0
local function eq(label, got, want)
	if got == want then passed = passed + 1
	else failed = failed + 1; print(string.format("  FAIL %-46s got %s want %s", label, tostring(got), tostring(want))) end
end
local function near(label, got, want, tol)
	if math.abs(got - want) <= tol then passed = passed + 1
	else failed = failed + 1; print(string.format("  FAIL %-46s got %s want ~%s", label, tostring(got), tostring(want))) end
end
local function ok(label, cond)
	if cond then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. label) end
end
local function section(name) print("\n== " .. name) end

local REAL = {
	Rarity = RarityConfig, Mutation = MutationConfig, Dino = DinoConfig,
	Zone = ZoneConfig, Upgrade = UpgradeConfig,
}

------------------------------------------------------------------ rarity
section("RarityConfig")

eq("nine tiers in Order", #RarityConfig.Order, 9)
eq("weight total", RarityConfig.WeightTotal, 100000000)
eq("first tier", RarityConfig.Order[1], "common")
eq("last tier", RarityConfig.Order[9], "titan")

for position, rarityId in ipairs(RarityConfig.Order) do
	local tier = RarityConfig.Tiers[rarityId]
	ok("tier exists: " .. rarityId, tier ~= nil)
	eq("rank matches order: " .. rarityId, tier.Rank, position)
end

-- Income ladder from docs/01 §2.
eq("common income", RarityConfig.Tiers.common.BaseIncome, 2)
eq("legendary income", RarityConfig.Tiers.legendary.BaseIncome, 500)
eq("titan income", RarityConfig.Tiers.titan.BaseIncome, 200000)
eq("mythic incubation 45m", RarityConfig.Tiers.mythic.IncubationSecs, 2700)
eq("titan incubation 6h", RarityConfig.Tiers.titan.IncubationSecs, 21600)
eq("titan carry penalty", RarityConfig.Tiers.titan.CarryPenalty, 0.45)

-- Luck tail guard: Secret and Titan must gain LESS from luck than Mythic and
-- Ancient, or luck buys the lottery. Verified empirically in step1_spec.
ok("secret luck power below mythic",
	RarityConfig.Tiers.secret.LuckPower < RarityConfig.Tiers.mythic.LuckPower)
ok("titan luck power below secret",
	RarityConfig.Tiers.titan.LuckPower < RarityConfig.Tiers.secret.LuckPower)
ok("common luck power negative", RarityConfig.Tiers.common.LuckPower < 0)

-- Legendary and above auto-lock on hatch, which is what stops the
-- "I misclicked and sold my Titan" support ticket.
for _, rarityId in ipairs({ "legendary", "mythic", "ancient", "secret", "titan" }) do
	ok("auto-locks: " .. rarityId, RarityConfig.Tiers[rarityId].AutoLock == true)
end
ok("common does not auto-lock", RarityConfig.Tiers.common.AutoLock == false)
ok("secret is cross-server", RarityConfig.Tiers.secret.CrossServer == true)
ok("titan is cross-server", RarityConfig.Tiers.titan.CrossServer == true)

section("Zone weight vectors")

local zoneSums = {}
for zoneId, weights in pairs(RarityConfig.ZoneWeights) do
	local sum = 0
	for _, w in pairs(weights) do sum = sum + w end
	zoneSums[zoneId] = sum
	eq("sums to 1e8: " .. zoneId, sum, RarityConfig.WeightTotal)
end
eq("four V1 zones have vectors", TableUtil.Count(RarityConfig.ZoneWeights), 4)

-- V1 ships no Mythic or Ancient species, so those tiers MUST be zero.
for zoneId, weights in pairs(RarityConfig.ZoneWeights) do
	eq("mythic zeroed in V1: " .. zoneId, weights.mythic, 0)
	eq("ancient zeroed in V1: " .. zoneId, weights.ancient, 0)
end

-- The published odds. These exact strings appear in announcements.
eq("Zone 1 secret weight", RarityConfig.ZoneWeights.plains.secret, 19)
eq("Zone 1 titan weight", RarityConfig.ZoneWeights.plains.titan, 1)
near("Zone 1 secret is ~1 in 5.26M", 100000000 / 19, 5263158, 1)
eq("Zone 4 titan is 1 in 2M", 100000000 / RarityConfig.ZoneWeights.frozen.titan, 2000000)
eq("Zone 4 secret is 1 in 80k", 100000000 / RarityConfig.ZoneWeights.frozen.secret, 80000)

-- Difficulty must rise monotonically across the zone order.
local previousCommon, previousLegendary = math.huge, 0
for _, zoneId in ipairs(ZoneConfig.Order) do
	local w = RarityConfig.ZoneWeights[zoneId]
	ok("common falls through zones: " .. zoneId, w.common < previousCommon)
	ok("legendary rises through zones: " .. zoneId, w.legendary > previousLegendary)
	previousCommon, previousLegendary = w.common, w.legendary
end

eq("TierBelow legendary", RarityConfig.TierBelow("legendary"), "epic")
eq("TierBelow clamps at common", RarityConfig.TierBelow("common"), "common")
eq("TierBelow one step from secret", RarityConfig.TierBelow("secret"), "ancient")
eq("TierBelow two steps from secret", RarityConfig.TierBelow("secret", 2), "mythic")

------------------------------------------------------------------ mutations
section("MutationConfig")

local mutationSum, shippedCount, mutatingWeight = 0, 0, 0
for _, mutation in pairs(MutationConfig.List) do
	if mutation.InV1 then
		mutationSum = mutationSum + mutation.Weight
		shippedCount = shippedCount + 1
		if mutation.Id ~= "none" then mutatingWeight = mutatingWeight + mutation.Weight end
	end
end
eq("shipped weights sum to 1e8", mutationSum, MutationConfig.WeightTotal)
eq("V1 ships 8 mutations plus none", shippedCount, 9)
near("V1 mutation rate ~19.93%", mutatingWeight / 1e6, 19.93, 0.01)

eq("golden is 1 in 8.3", math.floor(1e8 / MutationConfig.List.golden.Weight + 0.5), 8)
eq("rainbow is 1 in 3,333", math.floor(1e8 / MutationConfig.List.rainbow.Weight + 0.5), 3333)
eq("galaxy is 1 in 100,000", 1e8 / MutationConfig.List.galaxy.Weight, 100000)
eq("void is 1 in 2,000,000", 1e8 / MutationConfig.List.void.Weight, 2000000)
eq("void multiplier", MutationConfig.List.void.Multiplier, 150)
eq("prime chance", MutationConfig.PrimeChance, 2000)
eq("stack capped at 2", MutationConfig.MaxStack, 2)

eq("no mutation is x1", MutationConfig.MultiplierFor(nil, nil), 1)
eq("explicit none is x1", MutationConfig.MultiplierFor("none", nil), 1)
eq("single golden", MutationConfig.MultiplierFor("golden", nil), 2)
eq("prime void+golden", MutationConfig.MultiplierFor("void", "golden"), 300)
eq("unknown id is ignored", MutationConfig.MultiplierFor("notamutation", nil), 1)

-- The theoretical ceiling has to stay bounded. Two mutations, best case.
eq("prime ceiling is void x celestial-equivalent",
	MutationConfig.MultiplierFor("void", "galaxy"), 150 * 35)

-- Display order puts the rarer mutation first.
eq("prime name order", MutationConfig.DisplayPrefix("golden", "void"), "Void Golden ")
eq("single name", MutationConfig.DisplayPrefix("golden", nil), "Golden ")
eq("no name when unmutated", MutationConfig.DisplayPrefix(nil, nil), "")

eq("thunderstorm boosts electric", MutationConfig.WeatherModifiers.thunderstorm.electric, 25)
eq("blizzard boosts frozen", MutationConfig.WeatherModifiers.blizzard.frozen, 25)
ok("weather cap exists", MutationConfig.WeatherModifierCap == 40)

------------------------------------------------------------------ species
section("DinoConfig")

eq("V1 roster is 34 species", DinoConfig.Count(), 34)

local byRarity = {}
for _, entry in pairs(DinoConfig.Species) do
	byRarity[entry.Rarity] = (byRarity[entry.Rarity] or 0) + 1
end
eq("10 common", byRarity.common, 10)
eq("9 uncommon", byRarity.uncommon, 9)
eq("8 rare", byRarity.rare, 8)
eq("3 epic", byRarity.epic, 3)
eq("2 legendary", byRarity.legendary, 2)
eq("1 secret", byRarity.secret, 1)
eq("1 titan", byRarity.titan, 1)
eq("no mythic in V1", byRarity.mythic, nil)
eq("no ancient in V1", byRarity.ancient, nil)

for id, entry in pairs(DinoConfig.Species) do
	eq("id matches key: " .. id, entry.Id, id)
	ok("has a display name: " .. id, type(entry.DisplayName) == "string" and #entry.DisplayName > 0)
	ok("model name derived: " .. id, entry.ModelName == "Dino_" .. id)
	ok("egg model from rarity: " .. id, entry.EggModelName == "Egg_" .. entry.Rarity)
	ok("in at least one zone: " .. id, #entry.Zones > 0)
	ok("species factor in band: " .. id, entry.SpeciesFactor >= 0.80 and entry.SpeciesFactor <= 1.30)
end

eq("titan renders at 3x", DinoConfig.Species.titanrex.VisualScale, 3)
eq("trex is the top legendary", DinoConfig.Species.trex.SpeciesFactor, 1.30)
eq("index order is declaration order", DinoConfig.Species.compsognathus.IndexOrder, 1)
eq("titan is last in the index", DinoConfig.Species.titanrex.IndexOrder, 34)

local ordered = DinoConfig.Ordered()
eq("Ordered returns everything", #ordered, 34)
ok("Ordered runs common to titan",
	ordered[1].Rarity == "common" and ordered[34].Rarity == "titan")

------------------------------------------------------------------ coverage
section("Zone x rarity coverage (validator rule 6)")

-- The failure this prevents: rolling a rarity the zone has no species for, so
-- the player's incubation finishes and produces nothing.
local combos, missing = 0, 0
print(string.format("  %-8s %-10s %8s  %s", "zone", "rarity", "weight", "species"))
for _, zoneId in ipairs(ZoneConfig.Order) do
	local weights = RarityConfig.ZoneWeights[zoneId]
	for _, rarityId in ipairs(RarityConfig.Order) do
		local weight = weights[rarityId] or 0
		if weight > 0 then
			combos = combos + 1
			local pool = DinoConfig.SpeciesFor(zoneId, rarityId)
			if #pool == 0 then missing = missing + 1 end
			print(string.format("  %-8s %-10s %8d  %d", zoneId, rarityId, weight, #pool))
			ok(string.format("%s/%s has species", zoneId, rarityId), #pool > 0)
		end
	end
end
eq("no uncovered combinations", missing, 0)
eq("28 rollable combinations", combos, 28)

-- A species must never appear twice in one bucket.
for _, zoneId in ipairs(ZoneConfig.Order) do
	for _, rarityId in ipairs(RarityConfig.Order) do
		local pool = DinoConfig.SpeciesFor(zoneId, rarityId)
		local seen = {}
		for _, speciesId in ipairs(pool) do
			ok("no duplicate in " .. zoneId .. "/" .. rarityId, not seen[speciesId])
			seen[speciesId] = true
		end
	end
end

------------------------------------------------------------------ zones
section("ZoneConfig")

eq("four V1 zones", ZoneConfig.Count(), 4)
eq("plains is free", ZoneConfig.Zones.plains.Unlock.Fossils, 0)
eq("canyon costs 5k", ZoneConfig.Zones.canyon.Unlock.Fossils, 5000)
eq("swamp costs 45k", ZoneConfig.Zones.swamp.Unlock.Fossils, 45000)
eq("frozen costs 400k", ZoneConfig.Zones.frozen.Unlock.Fossils, 400000)
ok("no V1 zone needs a rebirth", ZoneConfig.Zones.frozen.Unlock.Rebirths == 0)
ok("no SpeciesPool duplication", ZoneConfig.Zones.plains.SpeciesPool == nil)

local previousCost, previousRespawn = -1, 0
for _, zoneId in ipairs(ZoneConfig.Order) do
	local zone = ZoneConfig.Zones[zoneId]
	ok("unlock cost rises: " .. zoneId, zone.Unlock.Fossils > previousCost)
	ok("respawn slows: " .. zoneId, zone.RespawnSecs > previousRespawn)
	previousCost, previousRespawn = zone.Unlock.Fossils, zone.RespawnSecs
end

eq("next locked after plains", ZoneConfig.NextLocked({ plains = true }).Id, "canyon")
eq("nothing locked when all open",
	ZoneConfig.NextLocked({ plains = true, canyon = true, swamp = true, frozen = true }), nil)

------------------------------------------------------------------ upgrades
section("UpgradeConfig")

eq("14 tracks in V1", UpgradeConfig.Count(), 14)
eq("7 on the park board", #UpgradeConfig.ForBoard("park"), 7)
eq("4 on the explorer board", #UpgradeConfig.ForBoard("explorer"), 4)
eq("3 on the defence board", #UpgradeConfig.ForBoard("defence"), 3)

-- Level 1 costs, straight from docs/05 §5.
eq("dinoSlots L1", UpgradeConfig.CostOf("dinoSlots", 1), 800)
eq("incubators L1", UpgradeConfig.CostOf("incubators", 1), 3500)
eq("feedingTrough L1", UpgradeConfig.CostOf("feedingTrough", 1), 2000)
eq("eggSense L1", UpgradeConfig.CostOf("eggSense", 1), 4000)
eq("fence L1", UpgradeConfig.CostOf("fence", 1), 15000)

-- Max effects, straight from docs/05 §5.
eq("30 dinosaur slots at max", UpgradeConfig.MaxEffect("dinoSlots"), 30)
eq("8 incubators at max", UpgradeConfig.MaxEffect("incubators"), 8)
near("incubation -60% at max", UpgradeConfig.MaxEffect("incubatorSpeed"), 0.40, 0.001)
near("mutation luck +80% at max", UpgradeConfig.MaxEffect("incubatorGenetics"), 0.80, 0.001)
near("luck +75% at max", UpgradeConfig.MaxEffect("eggSense"), 0.75, 0.001)
near("park income x2.6 at max", UpgradeConfig.MaxEffect("feedingTrough"), 2.60, 0.001)
near("move speed +24% at max", UpgradeConfig.MaxEffect("runnersLegs"), 1.24, 0.001)
near("carry penalty -60% at max", UpgradeConfig.MaxEffect("strongBack"), 0.40, 0.001)
eq("carry 5 eggs at max", UpgradeConfig.MaxEffect("eggPouch"), 5)
eq("bank 6 minutes at max", UpgradeConfig.MaxEffect("bankSize"), 360)
eq("storage 205 at max", UpgradeConfig.MaxEffect("dinoStorage"), 205)
eq("fence adds 5s at max", UpgradeConfig.MaxEffect("fence"), 5)
eq("tower cooldown 5s at max", UpgradeConfig.MaxEffect("guardTower"), 5)

-- Costs must rise, and no multiplicative effect may reach zero.
for id, entry in pairs(UpgradeConfig.Tracks) do
	local previous = 0
	for level = 1, entry.MaxLevel do
		local cost = UpgradeConfig.CostOf(id, level)
		ok("cost rises: " .. id .. " L" .. level, cost > previous)
		previous = cost
	end
	eq("out of range is 0: " .. id, UpgradeConfig.CostOf(id, entry.MaxLevel + 1), 0)
	eq("level 0 is 0: " .. id, UpgradeConfig.CostOf(id, 0), 0)

	local kind = entry.Effect.Kind
	if kind == "incubationMult" or kind == "carryPenaltyMult"
		or kind == "moveSpeedMult" or kind == "parkIncomeMult" then
		ok("multiplier stays positive: " .. id, UpgradeConfig.MaxEffect(id) > 0)
	end
end

eq("CostRange sums levels",
	UpgradeConfig.CostRange("dinoSlots", 0, 3),
	UpgradeConfig.CostOf("dinoSlots", 1) + UpgradeConfig.CostOf("dinoSlots", 2) + UpgradeConfig.CostOf("dinoSlots", 3))
eq("CostRange of nothing is 0", UpgradeConfig.CostRange("dinoSlots", 3, 3), 0)
eq("EffectAt clamps above max",
	UpgradeConfig.EffectAt("dinoSlots", 999), UpgradeConfig.MaxEffect("dinoSlots"))

eq("significant rounding 1376 -> 1380", UpgradeConfig.RoundSignificant(1376), 1380)
eq("significant rounding 27834 -> 27800", UpgradeConfig.RoundSignificant(27834), 27800)
eq("small values unrounded", UpgradeConfig.RoundSignificant(42), 42)

------------------------------------------------------------------ rebirth
section("RebirthConfig")

eq("rebirth 1 costs 250k", RebirthConfig.CostOf(1), 250000)
eq("rebirth 2 costs 1.3M", RebirthConfig.CostOf(2), 1300000)
near("rebirth 3 costs 6.76M", RebirthConfig.CostOf(3), 6760000, 1)
near("rebirth 5 costs ~183M", RebirthConfig.CostOf(5), 182790400, 100)
near("rebirth 8 costs ~25.7B", RebirthConfig.CostOf(8), 25.70e9, 0.02e9)
near("rebirth 12 costs ~18.8T", RebirthConfig.CostOf(12), 18.79e12, 0.05e12)

eq("rebirth 1 needs 3 dinosaurs", RebirthConfig.DinosaursRequired(1), 3)
near("R6 income is x1.9", RebirthConfig.IncomeMultiplier(6), 1.90, 0.001)
near("R10 luck +50%", RebirthConfig.LuckBonus(10), 0.50, 0.001)
near("luck caps at +75%", RebirthConfig.LuckBonus(99), 0.75, 0.001)
near("move speed caps at +40%", RebirthConfig.MoveSpeedBonus(99), 0.40, 0.001)
eq("offline caps at 12h", RebirthConfig.OfflineCapSecs(99), 12 * 3600)
eq("offline base is 4h", RebirthConfig.OfflineCapSecs(0), 4 * 3600)
eq("bonus slots cap at 10", RebirthConfig.BonusDinoSlots(99), 10)
eq("one bonus slot every 2 rebirths", RebirthConfig.BonusDinoSlots(5), 2)

eq("1 vault slot at R0", RebirthConfig.VaultSlots(0), 1)
eq("2 vault slots at R3", RebirthConfig.VaultSlots(3), 2)
eq("3 vault slots at R7", RebirthConfig.VaultSlots(7), 3)
eq("5 vault slots at R20", RebirthConfig.VaultSlots(20), 5)
eq("vault slots cap at 5", RebirthConfig.VaultSlots(99), 5)

eq("name tag at R0", RebirthConfig.NameTagFor(0).Id, "bone")
eq("name tag at R7", RebirthConfig.NameTagFor(7).Id, "obsidian")
eq("name tag at R50", RebirthConfig.NameTagFor(50).Id, "titan")

-- Vaulted dinosaurs and the Index surviving a rebirth is what makes players
-- willing to do a second one.
local preserved = {}
for _, key in ipairs(RebirthConfig.Preserved) do preserved[key] = true end
for _, key in ipairs({ "Index", "DNA", "Settings", "Stats", "Gamepasses", "Tutorial", "Rebirths" }) do
	ok("survives rebirth: " .. key, preserved[key] == true)
end
for _, key in ipairs({ "Fossils", "Upgrades", "ZonesUnlocked", "Dinos" }) do
	ok("resets on rebirth: " .. key, preserved[key] == nil)
end

------------------------------------------------------------------ validator
section("ConfigValidator against the real configs")

local report = ConfigValidator.Run(REAL)
if #report.errors > 0 then
	for _, e in ipairs(report.errors) do print("    " .. e) end
end
eq("no errors on real configs", #report.errors, 0)
ok("ran several checks", #report.checks >= 8)
ok("skipped configs not yet built", #report.skipped >= 2)

section("ConfigValidator catches broken configs")

-- Minimal fixture set, so each negative test breaks exactly one thing.
local function fakeDino(list)
	local species = {}
	for _, entry in ipairs(list) do species[entry.Id] = entry end
	local module = { Species = species }
	function module.BuildZoneIndex()
		local index = {}
		for _, entry in pairs(species) do
			for _, zoneId in ipairs(entry.Zones) do
				index[zoneId] = index[zoneId] or {}
				index[zoneId][entry.Rarity] = index[zoneId][entry.Rarity] or {}
				table.insert(index[zoneId][entry.Rarity], entry.Id)
			end
		end
		return index
	end
	return module
end

local function baseline()
	return {
		Rarity = TableUtil.DeepCopy({
			Order = { "common", "rare" },
			WeightTotal = 100,
			Tiers = {
				common = { Id = "common", Rank = 1, BaseIncome = 2, IncubationSecs = 30, LuckPower = -0.5, InV1 = true },
				rare = { Id = "rare", Rank = 2, BaseIncome = 30, IncubationSecs = 180, LuckPower = 0.15, InV1 = true },
			},
			ZoneWeights = { plains = { common = 90, rare = 10 } },
		}),
		Mutation = TableUtil.DeepCopy({
			WeightTotal = 100,
			List = {
				none = { Id = "none", Weight = 90, Multiplier = 1, Rank = 0, InV1 = true },
				golden = { Id = "golden", Weight = 10, Multiplier = 2, Rank = 1, InV1 = true },
			},
		}),
		Dino = fakeDino({
			{ Id = "a", Rarity = "common", Zones = { "plains" }, SpeciesFactor = 1.0,
			  ModelName = "Dino_a", EggModelName = "Egg_common" },
			{ Id = "b", Rarity = "rare", Zones = { "plains" }, SpeciesFactor = 1.0,
			  ModelName = "Dino_b", EggModelName = "Egg_rare" },
		}),
		Zone = { Zones = { plains = { Id = "plains" } }, Order = { "plains" } },
		Upgrade = UpgradeConfig,
	}
end

local function errorsFor(mutate)
	local configs = baseline()
	mutate(configs)
	local r = ConfigValidator.Run(configs)
	return r.errors
end

ok("baseline fixture is clean", #ConfigValidator.Run(baseline()).errors == 0)

ok("R1 catches a weight sum that is off", #errorsFor(function(c)
	c.Rarity.ZoneWeights.plains.common = 89
end) > 0)

ok("R1 catches a missing rarity entry", #errorsFor(function(c)
	c.Rarity.ZoneWeights.plains.rare = nil
	c.Rarity.ZoneWeights.plains.common = 100
end) > 0)

ok("R2 catches a mutation sum that is off", #errorsFor(function(c)
	c.Mutation.List.golden.Weight = 11
end) > 0)

ok("R2 catches a missing 'none' mutation", #errorsFor(function(c)
	c.Mutation.List.none = nil
	c.Mutation.List.golden.Weight = 100
end) > 0)

ok("R3 catches an unknown rarity", #errorsFor(function(c)
	c.Dino.Species.a.Rarity = "legendary"
end) > 0)

ok("R4 catches an unknown zone", #errorsFor(function(c)
	c.Dino.Species.a.Zones = { "atlantis" }
end) > 0)

ok("R4 catches a species in no zone", #errorsFor(function(c)
	c.Dino.Species.a.Zones = {}
end) > 0)

ok("R5 catches a zone with no weight vector", #errorsFor(function(c)
	c.Zone.Zones.swamp = { Id = "swamp" }
end) > 0)

-- The one that matters most: a rollable rarity with nothing to hatch.
local coverageErrors = errorsFor(function(c)
	c.Dino.Species.b = nil -- remove the only Rare while rare weight stays 10
end)
ok("R6 catches a rollable rarity with no species", #coverageErrors > 0)
ok("R6 error names the zone and rarity", (function()
	for _, e in ipairs(coverageErrors) do
		if string.find(e, "R6") and string.find(e, "plains") and string.find(e, "rare") then
			return true
		end
	end
	return false
end)())

-- A post-V1 tier should say so, rather than reading as a typo.
local scopedErrors = errorsFor(function(c)
	c.Rarity.Order = { "common", "rare", "mythic" }
	c.Rarity.Tiers.mythic = { Id = "mythic", Rank = 3, BaseIncome = 2200, IncubationSecs = 2700,
		LuckPower = 0.7, InV1 = false }
	c.Rarity.ZoneWeights.plains = { common = 80, rare = 10, mythic = 10 }
end)
ok("R6 explains a post-V1 tier as scope", (function()
	for _, e in ipairs(scopedErrors) do
		if string.find(e, "ships after V1") then return true end
	end
	return false
end)())

ok("R9 catches growth that does not grow", #errorsFor(function(c)
	c.Upgrade = {
		Boards = { "park" },
		Tracks = { bad = { Id = "bad", Board = "park", MaxLevel = 5, BaseCost = 100,
			Growth = 1.0, Effect = { Kind = "luck", Base = 0, PerLevel = 1 } } },
		CostOf = function() return 100 end,
		MaxEffect = function() return 5 end,
	}
end) > 0)

ok("R9 catches a multiplier that reaches zero", #errorsFor(function(c)
	c.Upgrade = {
		Boards = { "park" },
		Tracks = { bad = { Id = "bad", Board = "park", MaxLevel = 25, BaseCost = 100,
			Growth = 1.5, Effect = { Kind = "parkIncomeMult", Base = 1.0, PerLevel = -0.04 } } },
		CostOf = function(_, level) return 100 * level end,
		MaxEffect = function() return 1.0 - 0.04 * 25 end,
	}
end) > 0)

ok("S1 catches duplicate rarity ranks", #errorsFor(function(c)
	c.Rarity.Tiers.rare.Rank = 1
end) > 0)

ok("S2 catches a broken income ladder", #errorsFor(function(c)
	c.Rarity.Tiers.rare.BaseIncome = 1
end) > 0)

ok("S3 catches a broken mutation ladder", #errorsFor(function(c)
	c.Mutation.List.golden.Multiplier = 0.5
end) > 0)

ok("S4 catches an out-of-band species factor", #errorsFor(function(c)
	c.Dino.Species.a.SpeciesFactor = 12
end) > 0)

ok("R0 catches a missing config entirely", (function()
	local r = ConfigValidator.Run({ Rarity = RarityConfig })
	return #r.errors > 0
end)())

print(string.format("\n%s\n  %d passed, %d failed\n", string.rep("=", 46), passed, failed))
if failed > 0 then error("TESTS FAILED") end
