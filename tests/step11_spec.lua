--[[
	Step 11 specification.

	The three reveals. Rarity was decided at pickup; species and mutation land
	here, and the odds line printed on screen has to be the same number the roll
	actually used - a game that misquotes the thing players screenshot is lying
	to them.

	Run with:  ./tests/run.sh
]]

local RandomMT = {}
RandomMT.__index = RandomMT
function RandomMT:NextNumber(a, b)
	self.s = (self.s * 16807) % 2147483647
	local x = self.s / 2147483647
	if a then return a + x * (b - a) end
	return x
end
function RandomMT:NextInteger(a, b) return a + math.floor(self:NextNumber() * (b - a + 1)) end
Random = { new = function(seed) return setmetatable({ s = seed or 1 }, RandomMT) end }

local Vector3MT = {}
Vector3MT.__index = Vector3MT
local function v3(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, Vector3MT) end
Vector3MT.__add = function(a, b) return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
Vector3MT.__sub = function(a, b) return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
Vector3MT.__mul = function(a, b)
	if type(b) == "number" then return v3(a.X * b, a.Y * b, a.Z * b) end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
Vector3 = { new = v3, zero = v3(0, 0, 0) }
Color3 = { fromHex = function(h) return { Hex = h } end }
typeof = type

local _shared = { Config = {}, Modules = {} }
game = { GetService = function(_, _n) return { WaitForChild = function() return _shared end } end }
local _realRequire = require
require = function(t) if type(t) == "table" then return t end return _realRequire(t) end

--@INJECT GameConfig=src/ReplicatedStorage/SAD_Shared/Config/GameConfig.lua RarityConfig=src/ReplicatedStorage/SAD_Shared/Config/RarityConfig.lua MutationConfig=src/ReplicatedStorage/SAD_Shared/Config/MutationConfig.lua DinoConfig=src/ReplicatedStorage/SAD_Shared/Config/DinoConfig.lua ZoneConfig=src/ReplicatedStorage/SAD_Shared/Config/ZoneConfig.lua UpgradeConfig=src/ReplicatedStorage/SAD_Shared/Config/UpgradeConfig.lua RebirthConfig=src/ReplicatedStorage/SAD_Shared/Config/RebirthConfig.lua RNG=src/ReplicatedStorage/SAD_Shared/Modules/RNG.lua Signal=src/ReplicatedStorage/SAD_Shared/Modules/Signal.lua Format=src/ReplicatedStorage/SAD_Shared/Modules/Format.lua@

_shared.Config.GameConfig = GameConfig
_shared.Config.RarityConfig = RarityConfig
_shared.Config.MutationConfig = MutationConfig
_shared.Config.DinoConfig = DinoConfig
_shared.Config.ZoneConfig = ZoneConfig
_shared.Config.UpgradeConfig = UpgradeConfig
_shared.Config.RebirthConfig = RebirthConfig
_shared.Modules.RNG = RNG
_shared.Modules.Signal = Signal
_shared.Modules.Format = Format
_shared.Modules.Log = { debug = function() end, info = function() end, warn = function() end, error = function() end }
_shared.Modules.Net = { OnEvent = function() end, FireClient = function() end, FireAllClients = function() end }

-- DinosaurService reads placement geometry and delegates its money maths to
-- the shared Economy module, so both have to be in the shim before it loads.
--@INJECT ParkConfig=src/ReplicatedStorage/SAD_Shared/Config/ParkConfig.lua@

_shared.Config.ParkConfig = ParkConfig

--@INJECT Economy=src/ReplicatedStorage/SAD_Shared/Modules/Economy.lua@

_shared.Modules.Economy = Economy

--@INJECT MutationService=src/ServerScriptService/SAD_Server/Services/MutationService/init.lua DinosaurService=src/ServerScriptService/SAD_Server/Services/DinosaurService/init.lua@

local passed, failed = 0, 0
local function eq(label, got, want)
	if got == want then passed = passed + 1
	else failed = failed + 1; print(string.format("  FAIL %-50s got %s want %s", label, tostring(got), tostring(want))) end
end
local function near(label, got, want, tol)
	if math.abs(got - want) <= tol then passed = passed + 1
	else failed = failed + 1; print(string.format("  FAIL %-50s got %.4f want ~%.4f", label, got, want)) end
end
local function ok(label, cond)
	if cond then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. label) end
end
local function section(name) print("\n== " .. name) end

local function profile(overrides)
	local data = { Upgrades = {}, Rebirths = 0, LuckNodes = 0 }
	for k, v in pairs(overrides or {}) do data[k] = v end
	return data
end

------------------------------------------------------------------ mutluck
section("Mutation luck")

eq("a fresh player has none", MutationService.MutLuckFrom(profile()), 0)
near("Incubator Genetics maxed is +80%",
	MutationService.MutLuckFrom(profile({ Upgrades = { incubatorGenetics = 15 } })), 0.80, 0.001)
near("fifteen rebirths are +45%",
	MutationService.MutLuckFrom(profile({ Rebirths = 15 })), 0.45, 0.001)
near("sources compose",
	MutationService.MutLuckFrom(profile({ Upgrades = { incubatorGenetics = 15 }, Rebirths = 15 })),
	1.25, 0.001)
ok("capped at 4.0", MutationService.MutLuckFrom(profile({ Rebirths = 99999 })) <= 4.0)

------------------------------------------------------------------ rolls
section("Mutation distribution")

local function rollMany(n, mutLuck, weather)
	local generator = Random.new(20260830)
	local counts, primes = {}, 0
	for _ = 1, n do
		local primary, secondary = MutationService.RollIn(mutLuck, weather, generator)
		counts[primary] = (counts[primary] or 0) + 1
		if secondary then
			primes = primes + 1
			-- The second must be different and never `none`.
			if secondary == primary or secondary == "none" then
				failed = failed + 1
				print("  FAIL invalid prime pairing: " .. primary .. " + " .. tostring(secondary))
			end
		end
	end
	return counts, primes
end

local N = 400000
local base = rollMany(N, 0, "clear")

print(string.format("  %-10s %10s %10s %10s", "mutation", "expected", "observed", "odds"))
for _, id in ipairs({ "none", "golden", "crystal", "frozen", "electric", "diamond" }) do
	local entry = MutationConfig.List[id]
	local expected = entry.Weight / MutationConfig.WeightTotal * 100
	local observed = (base[id] or 0) / N * 100
	print(string.format("  %-10s %9.4f%% %9.4f%% %10s", id, expected, observed,
		Format.Odds(entry.Weight, MutationConfig.WeightTotal)))
	near("matches its weight: " .. id, observed, expected, math.max(0.35, expected * 0.06))
end

-- Only shipped mutations may ever appear.
for id in pairs(base) do
	ok("rolled mutation is shipped: " .. id, MutationConfig.List[id].InV1 == true)
end

local mutated = N - (base.none or 0)
near("V1 mutation rate is ~19.93%", mutated / N * 100, 19.93, 0.3)

section("Prime")

-- 1 in 2000 of the ~20% that mutate at all.
local expectedPrimes = mutated / MutationConfig.PrimeChance
local _, primes = rollMany(N, 0, "clear")
print(string.format("  %d primes in %s rolls (expected ~%.0f)", primes, Format.Comma(N), expectedPrimes))
ok("primes occur", primes > 0)
ok("primes are rare", primes < expectedPrimes * 2.5)
eq("stacking is capped at two", MutationConfig.MaxStack, 2)

-- The ceiling has to stay bounded, which is the whole reason for the cap.
local worst = 0
for _, a in pairs(MutationConfig.List) do
	for _, b in pairs(MutationConfig.List) do
		if a.InV1 and b.InV1 and a.Id ~= b.Id and a.Id ~= "none" and b.Id ~= "none" then
			worst = math.max(worst, a.Multiplier * b.Multiplier)
		end
	end
end
print(string.format("  best possible prime pairing: x%d", worst))
ok("the prime ceiling stays bounded", worst <= 10000)

section("Mutation luck shifts the odds")

local lucky = rollMany(N, 2.0, "clear")
ok("luck reduces plain hatches", (lucky.none or 0) < (base.none or 0))
ok("luck raises the upper bands", (lucky.diamond or 0) > (base.diamond or 0))

-- Golden sits at MutPower 0: luck must not simply inflate the cheapest tier.
local goldenShare = (lucky.golden or 0) / (N - (lucky.none or 0))
local baseGoldenShare = (base.golden or 0) / (N - (base.none or 0))
ok("luck does not just make more Goldens", goldenShare < baseGoldenShare)

section("Weather")

local storm = rollMany(N, 0, "thunderstorm")
print(string.format("  electric: clear %.4f%% -> thunderstorm %.4f%%",
	(base.electric or 0) / N * 100, (storm.electric or 0) / N * 100))
ok("a thunderstorm floods electric", (storm.electric or 0) > (base.electric or 0) * 10)

local blizzard = rollMany(N, 0, "blizzard")
ok("a blizzard floods frozen", (blizzard.frozen or 0) > (base.frozen or 0) * 10)
ok("a blizzard does not touch electric",
	math.abs((blizzard.electric or 0) - (base.electric or 0)) < base.electric * 0.5)

-- Weather must never exceed the documented cap.
for weatherId, modifiers in pairs(MutationConfig.WeatherModifiers) do
	for mutationId, multiplier in pairs(modifiers) do
		ok(string.format("%s/%s is within the cap", weatherId, mutationId),
			multiplier <= MutationConfig.WeatherModifierCap)
		ok(string.format("%s/%s names a shipped mutation", weatherId, mutationId),
			MutationConfig.List[mutationId] ~= nil)
	end
end

------------------------------------------------------------------ species
section("Species rolls")

-- Every zone x rarity combination must produce something hatchable, always.
local generator = Random.new(99)
for _, zoneId in ipairs(ZoneConfig.Order) do
	local weights = RarityConfig.ZoneWeights[zoneId]
	for _, rarityId in ipairs(RarityConfig.Order) do
		if (weights[rarityId] or 0) > 0 then
			local seen = {}
			for _ = 1, 200 do
				local speciesId = DinosaurService.RollSpecies(zoneId, rarityId, generator)
				if speciesId then seen[speciesId] = true end
			end

			local count = 0
			for _ in pairs(seen) do count = count + 1 end
			ok(string.format("%s/%s always hatches something", zoneId, rarityId), count > 0)

			-- And only species that actually live there, at that tier.
			for speciesId in pairs(seen) do
				local species = DinoConfig.Get(speciesId)
				eq(string.format("%s/%s -> right rarity", zoneId, rarityId), species.Rarity, rarityId)
				local livesHere = false
				for _, zid in ipairs(species.Zones) do
					if zid == zoneId then livesHere = true end
				end
				ok(string.format("%s/%s -> %s lives there", zoneId, rarityId, speciesId), livesHere)
			end
		end
	end
end

eq("an impossible combination returns nil", DinosaurService.RollSpecies("plains", "mythic", generator), nil)

------------------------------------------------------------------ income
section("The master income formula")

--[[
	The worked example from docs/05 §2: a rebirth-6 player with a Star-3 Golden
	Mythic (SF 1.20), Feeding Trough L8, Steel enclosure.

	This assertion caught the document. The example originally labelled its
	Feeding Trough multiplier "L8 (x2.1)", but the track in the same document is
	+8% per level, so L8 is x1.64 and x2.1 would be L13 - the example could not
	be reproduced from its own table, and its stated total was 20 off its own
	arithmetic besides. Both corrected; the number below is what the code
	actually produces.

	The species is Mythic and ships in V1.1, so the arithmetic is checked
	against its published inputs rather than against a species that exists yet.
]]
local docExample = RarityConfig.Tiers.mythic.BaseIncome * 1.20 * 2
	* (1 + 0.35 * 2) * (1 + 0.15 * 6) * UpgradeConfig.EffectAt("feedingTrough", 8) * 1.25
near("docs/05 worked example", docExample, 34962, 2)

-- And the multiplier the example depends on, so a change to the track fails
-- here rather than silently invalidating the document.
near("Feeding Trough L8 is x1.64", UpgradeConfig.EffectAt("feedingTrough", 8), 1.64, 0.001)

-- And the formula as implemented, against a V1 species.
local trex = { SpeciesId = "trex", Rarity = "legendary", Stars = 1 }
near("a plain T-Rex earns base x factor",
	DinosaurService.IncomeOf(trex, nil),
	RarityConfig.Tiers.legendary.BaseIncome * DinoConfig.Get("trex").SpeciesFactor, 0.001)

local goldenTrex = { SpeciesId = "trex", Rarity = "legendary", Mutation = "golden", Stars = 1 }
near("Golden doubles it", DinosaurService.IncomeOf(goldenTrex, nil),
	DinosaurService.IncomeOf(trex, nil) * 2, 0.001)

local primeTrex = { SpeciesId = "trex", Rarity = "legendary", Mutation = "void", Mutation2 = "golden", Stars = 1 }
near("a Prime multiplies both", DinosaurService.IncomeOf(primeTrex, nil),
	DinosaurService.IncomeOf(trex, nil) * 300, 0.01)

local star5 = { SpeciesId = "trex", Rarity = "legendary", Stars = 5 }
near("Star 5 is x2.4", DinosaurService.IncomeOf(star5, nil),
	DinosaurService.IncomeOf(trex, nil) * 2.4, 0.001)

local withPlayer = DinosaurService.IncomeOf(trex, profile({ Rebirths = 6, Upgrades = { feedingTrough = 8 } }))
near("rebirths and upgrades multiply in", withPlayer,
	DinosaurService.IncomeOf(trex, nil) * 1.90 * UpgradeConfig.EffectAt("feedingTrough", 8), 0.01)

-- Income must rise with rarity for every species pairing at the same tier.
local previous = 0
for _, rarityId in ipairs(RarityConfig.Order) do
	local income = DinosaurService.IncomeOf({ SpeciesId = "trex", Rarity = rarityId, Stars = 1 }, nil)
	ok("income rises with rarity: " .. rarityId, income > previous)
	previous = income
end

section("Sell values")

-- Mutations raise sell value on a SQUARE ROOT, so selling a Void dinosaur is
-- lucrative but never better than keeping it.
local plainF = DinosaurService.SellValueOf(trex)
local voidEntry = { SpeciesId = "trex", Rarity = "legendary", Mutation = "void", Stars = 1 }
local voidF = DinosaurService.SellValueOf(voidEntry)

local sellRatio = voidF / plainF
local incomeRatio = DinosaurService.IncomeOf(voidEntry, nil) / DinosaurService.IncomeOf(trex, nil)
print(string.format("  Void T-Rex: sell x%.1f, income x%.0f", sellRatio, incomeRatio))
ok("selling a mutated dinosaur is worth more", sellRatio > 1)
ok("but keeping it is worth far more", incomeRatio > sellRatio * 5)

for _, rarityId in ipairs(RarityConfig.Order) do
	local fossils, dna = DinosaurService.SellValueOf({ SpeciesId = "trex", Rarity = rarityId, Stars = 1 })
	ok("sell value is positive: " .. rarityId, fossils > 0 and dna > 0)
end

section("Display names")

eq("plain", DinosaurService.DisplayNameOf({ SpeciesId = "trex", Rarity = "legendary" }),
	"Tyrannosaurus Rex")
eq("mutated", DinosaurService.DisplayNameOf({ SpeciesId = "trex", Mutation = "golden" }),
	"Golden Tyrannosaurus Rex")
eq("prime puts the rarer first",
	DinosaurService.DisplayNameOf({ SpeciesId = "trex", Mutation = "golden", Mutation2 = "void" }),
	"Void Golden Tyrannosaurus Rex")

------------------------------------------------------------------ timing
section("Incubation as the rarity tell")

--[[
	The timer telegraphs the tier before the species is known, so it has to be
	strictly increasing - if two tiers shared a duration the tell would be
	ambiguous exactly where it matters most.
]]
local function duration(data, rarity)
	local tier = RarityConfig.Tiers[rarity]
	return math.max(5, math.floor(tier.IncubationSecs
		* UpgradeConfig.EffectAt("incubatorSpeed", data.Upgrades.incubatorSpeed or 0)))
end

local fresh = profile()
local maxed = profile({ Upgrades = { incubatorSpeed = 15 } })

print(string.format("  %-11s %12s %12s", "rarity", "base", "maxed"))
local previousBase, previousMaxed = 0, 0
for _, rarityId in ipairs(RarityConfig.Order) do
	local a, b = duration(fresh, rarityId), duration(maxed, rarityId)
	print(string.format("  %-11s %12s %12s", rarityId, Format.Time(a), Format.Time(b)))
	ok("base duration is distinct: " .. rarityId, a > previousBase)
	ok("upgraded duration is distinct: " .. rarityId, b > previousMaxed)
	ok("upgrades never slow it: " .. rarityId, b <= a)
	previousBase, previousMaxed = a, b
end

eq("a Common hatches in 30s", duration(fresh, "common"), 30)
eq("a Mythic takes 45m", duration(fresh, "mythic"), 2700)
eq("a Titan takes 6h", duration(fresh, "titan"), 21600)
near("maxed incubators are 60% faster", duration(maxed, "titan") / duration(fresh, "titan"), 0.40, 0.01)

print(string.format("\n%s\n  %d passed, %d failed\n", string.rep("=", 46), passed, failed))
if failed > 0 then error("TESTS FAILED") end
