--[[
	Step 17 specification.

	Weather. It is server-wide, identical for everyone, and the only thing in
	the game that changes the odds without the player doing anything - so the
	failure modes are all about a number quietly not being what the document
	says:

	  * a Clear share that does not match "roughly 45% of the time nothing
	    special is happening";
	  * a mutation multiplier that is applied but not measurable;
	  * a cap that never trims anything, so nobody notices it stopped working;
	  * two tables naming different sets of weathers.

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

Color3 = { fromHex = function(h) return { Hex = h } end, fromRGB = function(r, g, b) return { r, g, b } end }
typeof = type

local _shared = { Config = {}, Modules = {} }
game = { GetService = function(_, _n) return { WaitForChild = function() return _shared end } end }
local _realRequire = require
require = function(t) if type(t) == "table" then return t end return _realRequire(t) end

--@INJECT WeatherConfig=src/ReplicatedStorage/SAD_Shared/Config/WeatherConfig.lua MutationConfig=src/ReplicatedStorage/SAD_Shared/Config/MutationConfig.lua RarityConfig=src/ReplicatedStorage/SAD_Shared/Config/RarityConfig.lua ZoneConfig=src/ReplicatedStorage/SAD_Shared/Config/ZoneConfig.lua RebirthConfig=src/ReplicatedStorage/SAD_Shared/Config/RebirthConfig.lua DailyConfig=src/ReplicatedStorage/SAD_Shared/Config/DailyConfig.lua UpgradeConfig=src/ReplicatedStorage/SAD_Shared/Config/UpgradeConfig.lua GameConfig=src/ReplicatedStorage/SAD_Shared/Config/GameConfig.lua RNG=src/ReplicatedStorage/SAD_Shared/Modules/RNG.lua Format=src/ReplicatedStorage/SAD_Shared/Modules/Format.lua@

for name, mod in pairs({ WeatherConfig = WeatherConfig, MutationConfig = MutationConfig,
	RarityConfig = RarityConfig, ZoneConfig = ZoneConfig, RebirthConfig = RebirthConfig,
	UpgradeConfig = UpgradeConfig, GameConfig = GameConfig ,
	DailyConfig = DailyConfig }) do
	_shared.Config[name] = mod
end
_shared.Modules.RNG = RNG
_shared.Modules.Log = { debug = function() end, info = function() end, warn = function() end, error = function() end }

--@INJECT Stats=src/ReplicatedStorage/SAD_Shared/Modules/Stats.lua@
_shared.Modules.Stats = Stats

--@INJECT MutationService=src/ServerScriptService/SAD_Server/Services/MutationService/init.lua@

local passed, failed = 0, 0
local function eq(label, got, want)
	if got == want then passed = passed + 1
	else failed = failed + 1; print(string.format("  FAIL %-52s got %s want %s", label, tostring(got), tostring(want))) end
end
local function near(label, got, want, tol)
	if math.abs(got - want) <= tol then passed = passed + 1
	else failed = failed + 1; print(string.format("  FAIL %-52s got %.4f want ~%.4f", label, got, want)) end
end
local function ok(label, cond)
	if cond then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. label) end
end
local function section(name) print("\n== " .. name) end

------------------------------------------------------------------ the table
section("The weather table (docs/04 §2)")

--[[
	The published rows for what V1 ships. These are weights players never see
	directly, but they decide how often the game feels eventful - the most
	load-bearing invisible numbers in the project.
]]
local PUBLISHED = {
	{ "clear", 4500, 0 },
	{ "rainstorm", 1400, 6 * 60 },
	{ "thunderstorm", 900, 5 * 60 },
	{ "blizzard", 650, 5 * 60 },
}
for _, row in ipairs(PUBLISHED) do
	local entry = WeatherConfig.Get(row[1])
	ok("weather exists: " .. row[1], entry ~= nil)
	eq(row[1] .. " weight", entry.Weight, row[2])
	eq(row[1] .. " duration", entry.DurationSecs, row[3])
	ok(row[1] .. " ships in V1", entry.InV1 == true)
end

eq("V1 ships four weathers", WeatherConfig.Count(), 4)
eq("every published weather is asserted", #PUBLISHED, WeatherConfig.Count())
eq("the roll interval is 8 minutes", WeatherConfig.RollInterval, 480)
eq("the countdown is 20 seconds", WeatherConfig.CountdownSecs, 20)
eq("the forced Clear gap is 3 minutes", WeatherConfig.MinClearGapSecs, 180)

-- Clear is the resting state: it has no duration of its own and runs to the
-- next roll, which is what makes "one weather is always active" true.
eq("clear runs until the next roll",
	WeatherConfig.DurationOf("clear"), WeatherConfig.RollInterval)
eq("an unknown weather falls back to a roll interval",
	WeatherConfig.DurationOf("hurricane"), WeatherConfig.RollInterval)
eq("nil resolves to clear", WeatherConfig.Get(nil).Id, "clear")

--------------------------------------------------------------- clear share
section("How often is nothing happening?")

--[[
	docs/04 §2: "Clear is weighted so that roughly 45% of the time nothing
	special is happening (special needs to feel special)."

	That 45% is exact - but only across all ELEVEN weathers, where the exotic
	weights sum to 5,500 against Clear's 4,500 out of 10,000. V1 ships three
	exotics summing to 2,950, so Clear is 60%.
]]
local v1Share = WeatherConfig.ClearShare()
print(string.format("  V1 (4 weathers):  Clear %.1f%% of rolls", v1Share * 100))

local FULL_EXOTIC_WEIGHTS = { 1400, 900, 700, 650, 550, 500, 350, 250, 130, 70 }
local fullExotic = 0
for _, weight in ipairs(FULL_EXOTIC_WEIGHTS) do
	fullExotic += weight
end
local fullShare = 4500 / (4500 + fullExotic)
print(string.format("  V1.1+ (11):       Clear %.1f%% of rolls  (docs/04: 'roughly 45%%')", fullShare * 100))

eq("the full table's exotic weights sum to 5,500", fullExotic, 5500)
near("...making Clear exactly 45%", fullShare, 0.45, 0.0001)

--[[
	V1's 60% is not a bug and is not a compromise: with only three exotics,
	MORE clear is what keeps them special. At 45% each of three would appear
	every other roll. Recorded as a measured fact rather than corrected
	towards a number that describes different content.
]]
near("V1's clear share is 60%", v1Share, 0.604, 0.005)
ok("V1 sees exotic weather less often than the full table would",
	v1Share > fullShare)
ok("...but still often enough to matter", v1Share < 0.75)

-- Weights must be positive and ordered as published: rarer weather is rarer.
local previous = math.huge
for _, row in ipairs(PUBLISHED) do
	local entry = WeatherConfig.Get(row[1])
	ok("weights descend: " .. row[1], entry.Weight <= previous)
	previous = entry.Weight
end

--------------------------------------------------------------- the roll
section("The roll distribution")

--[[
	Weights are only real if the picker honours them. Ten thousand rolls
	against the table, which is docs/13's own test for this step applied to
	the selection as well as to the mutation shift.
]]
local rng = Random.new(20260830)
local counts = {}
local ROLLS = 20000
local pool = WeatherConfig.RollableWeights()
for _ = 1, ROLLS do
	local picked = RNG.WeightedPick(pool, rng)
	counts[picked] = (counts[picked] or 0) + 1
end

local total = 0
for _, weight in pairs(pool) do
	total += weight
end

print("  weather        expected   observed")
for _, row in ipairs(PUBLISHED) do
	local expected = pool[row[1]] / total
	local observed = (counts[row[1]] or 0) / ROLLS
	print(string.format("  %-12s   %6.2f%%    %6.2f%%", row[1], expected * 100, observed * 100))
	near("rolls match the weight: " .. row[1], observed, expected, 0.02)
end

--[[
	The forced Clear gap converts an exotic roll into Clear rather than
	re-rolling it. That distinction matters: re-rolling would quietly reshape
	the table, because a rare weather that survives a filter is likelier than
	its weight says.
]]
local function rollWithGap(picked, sinceLastExotic)
	if picked ~= "clear" and sinceLastExotic < WeatherConfig.MinClearGapSecs then
		return "clear"
	end
	return picked
end
eq("an exotic inside the gap becomes clear", rollWithGap("blizzard", 60), "clear")
eq("...and outside it does not", rollWithGap("blizzard", 300), "blizzard")
eq("clear inside the gap is still clear", rollWithGap("clear", 60), "clear")

--------------------------------------------------------- mutation shift
section("The mutation shift is measurable (docs/13's test)")

--[[
	docs/13 §Step 17: "force each weather; confirm the mutation weight shift is
	measurable over 10,000 simulated rolls."

	Measured against the odds docs/04 publishes rather than against whatever
	the code happens to produce.
]]
local function distribution(weatherId, zoneId, rolls)
	local generator = Random.new(4242)
	local seen = {}
	for _ = 1, rolls do
		local mutation = MutationService.RollIn(0, weatherId, generator, zoneId)
		seen[mutation] = (seen[mutation] or 0) + 1
	end
	return seen
end

local ROLLS_M = 20000
local clearDist = distribution("clear", nil, ROLLS_M)
local stormDist = distribution("thunderstorm", nil, ROLLS_M)
local blizzardDist = distribution("blizzard", nil, ROLLS_M)

local function share(dist, id)
	return (dist[id] or 0) / ROLLS_M
end

print(string.format("  electric:  clear %.2f%%  ->  thunderstorm %.2f%%",
	share(clearDist, "electric") * 100, share(stormDist, "electric") * 100))
print(string.format("  frozen:    clear %.2f%%  ->  blizzard     %.2f%%",
	share(clearDist, "frozen") * 100, share(blizzardDist, "frozen") * 100))

ok("thunderstorm moves electric a long way",
	share(stormDist, "electric") > share(clearDist, "electric") * 10)
ok("blizzard moves frozen a long way",
	share(blizzardDist, "frozen") > share(clearDist, "frozen") * 10)

-- And it must move only the mutation it names.
ok("thunderstorm does not move frozen",
	math.abs(share(stormDist, "frozen") - share(clearDist, "frozen")) < 0.01)
ok("blizzard does not move electric",
	math.abs(share(blizzardDist, "electric") - share(clearDist, "electric")) < 0.01)

-- Clear must be genuinely the baseline, not a weather with an empty-looking
-- table that still does something.
eq("clear has no modifiers", next(MutationConfig.WeatherModifiers.clear), nil)
eq("rainstorm has none either", next(MutationConfig.WeatherModifiers.rainstorm), nil)

--[[
	docs/04 §2's interaction rule: "Prime chance is never modified by weather."

	Read carefully, that is about the CHANCE, not the count - and the two move
	differently. Prime is only rolled once a mutation has already landed, so a
	weather that mutates more often produces more Primes in absolute terms
	while leaving the 1-in-2,000 untouched. Measuring the raw count and
	expecting it to be flat is measuring the wrong thing; the count SHOULD
	rise, and it is the conditional rate that must not.
]]
local function primeRate(weatherId, rolls)
	local generator = Random.new(99)
	local mutated, primes = 0, 0
	for _ = 1, rolls do
		local primary, second = MutationService.RollIn(0, weatherId, generator)
		if primary ~= "none" then
			mutated += 1
			if second then
				primes += 1
			end
		end
	end
	return mutated, primes
end

local PRIME_ROLLS = 300000
local clearMutated, clearPrimes = primeRate("clear", PRIME_ROLLS)
local stormMutated, stormPrimes = primeRate("thunderstorm", PRIME_ROLLS)

print(string.format("  in %d rolls: clear mutated %d -> %d primes (1 in %.0f)",
	PRIME_ROLLS, clearMutated, clearPrimes,
	if clearPrimes > 0 then clearMutated / clearPrimes else 0))
print(string.format("               storm mutated %d -> %d primes (1 in %.0f)",
	stormMutated, stormPrimes,
	if stormPrimes > 0 then stormMutated / stormPrimes else 0))

-- The count rises, and that is correct: more rolls reach the Prime check.
ok("a stormy server does produce more Primes", stormPrimes > clearPrimes)
ok("...because more of its rolls mutated at all", stormMutated > clearMutated)

--[[
	And the rate does not. Asserted with a wide band because a 1-in-2,000 event
	is still only ~30 and ~90 samples here - tight enough to catch a weather
	that multiplied the chance, loose enough not to fail on variance.
]]
local target = 1 / MutationConfig.PrimeChance
local clearRate = clearPrimes / math.max(1, clearMutated)
local stormRate = stormPrimes / math.max(1, stormMutated)
near("clear's prime rate is 1 in 2,000", clearRate, target, target * 0.5)
near("thunderstorm's is the same", stormRate, target, target * 0.5)

------------------------------------------------------------------- the cap
section("The x40 cap earns its keep")

--[[
	docs/04 §2: "Weather cannot exceed a x40 cap on any single mutation."

	In V1 nothing reaches it - Frozen is x25 - EXCEPT in the one place the
	document also says is worse: "Blizzard ... Frozen Valley x2". 25 x 2 = 50,
	which the cap trims to 40. That is the only V1 interaction where the cap
	does anything, so it is the only place it can be shown to work.
]]
eq("the cap is x40", MutationConfig.WeatherModifierCap, 40)
eq("blizzard boosts the frozen zone x2", WeatherConfig.ZoneBoost("blizzard", "frozen"), 2)
eq("...and nowhere else", WeatherConfig.ZoneBoost("blizzard", "plains"), 1)
eq("thunderstorm boosts no zone", WeatherConfig.ZoneBoost("thunderstorm", "frozen"), 1)
eq("a nil zone never boosts", WeatherConfig.ZoneBoost("blizzard", nil), 1)

local base = MutationConfig.WeatherModifiers.blizzard.frozen
eq("blizzard's own frozen modifier is x25", base, 25)
local boosted = base * WeatherConfig.ZoneBoost("blizzard", "frozen")
eq("in the Valley that would be x50", boosted, 50)
eq("...which the cap trims to x40",
	math.min(boosted, MutationConfig.WeatherModifierCap), 40)

--[[
	And it is measurable through the real roll, not only in arithmetic: a
	blizzard hatch from a Frozen Valley egg must produce more Frozen than the
	same blizzard elsewhere.
]]
local valleyDist = distribution("blizzard", "frozen", ROLLS_M)
print(string.format("  frozen in a blizzard: elsewhere %.2f%%, Frozen Valley %.2f%%",
	share(blizzardDist, "frozen") * 100, share(valleyDist, "frozen") * 100))
ok("the Valley boost is visible in real rolls",
	share(valleyDist, "frozen") > share(blizzardDist, "frozen"))

--[[
	But NOT by the full x2, because the cap trims it. The observed ratio has
	to land between 1 and 2 - if it reached 2 the cap is not applied, and if it
	were 1 the boost is not.
]]
local ratio = share(valleyDist, "frozen") / share(blizzardDist, "frozen")
print(string.format("  ratio %.3f (uncapped would be near 2.00)", ratio))
ok("the boost is real", ratio > 1.05)
ok("...and the cap trims it", ratio < 1.9)

--------------------------------------------------------------- the effects
section("Effects are named, and each is read by one system")

--[[
	Every non-mutation effect a weather has. Listed here so a weather that
	quietly stops doing something fails a test rather than becoming decorative.
]]
local EXPECTED_EFFECTS = {
	clear = {},
	rainstorm = { GroundSpeedMult = 0.90, NestRespawnMult = 0.75 },
	thunderstorm = { LightningChance = 0.10, LightningInterval = 12 },
	blizzard = { FogEnd = 260 }, -- ZoneBoost is a table, checked above
}
for weatherId, effects in pairs(EXPECTED_EFFECTS) do
	for key, value in pairs(effects) do
		eq(string.format("%s.%s", weatherId, key),
			WeatherConfig.EffectOf(weatherId, key, nil), value)
	end
end

eq("rainstorm slows the ground 10%", WeatherConfig.EffectOf("rainstorm", "GroundSpeedMult", 1), 0.90)
eq("nests refill 25% faster", WeatherConfig.EffectOf("rainstorm", "NestRespawnMult", 1), 0.75)
eq("clear does neither", WeatherConfig.EffectOf("clear", "GroundSpeedMult", 1), 1)
eq("an unknown effect returns the default", WeatherConfig.EffectOf("blizzard", "Nonsense", 7), 7)
eq("an unknown weather returns the default", WeatherConfig.EffectOf("hurricane", "FogEnd", 5), 5)

-- The rain slow must be survivable alongside a carried egg. Rain at 10% plus
-- a Titan at 45% is 50.5% - inside the 85% floor, so it is never immobilising.
local rainMult = WeatherConfig.EffectOf("rainstorm", "GroundSpeedMult", 1)
local worstCombined = 1 - (1 - rainMult) * (1 - RarityConfig.Tiers.titan.CarryPenalty)
print(string.format("  rain + a Titan egg: %.0f%% of base speed (floor is %.0f%%)",
	worstCombined * 100, (1 - GameConfig.MaxCarryPenalty) * 100))
ok("rain plus the heaviest egg still moves",
	worstCombined > 1 - GameConfig.MaxCarryPenalty)

------------------------------------------------------------------ agreement
section("The two weather tables agree")

--[[
	WeatherConfig holds weights and durations; MutationConfig.WeatherModifiers
	holds the mutation multipliers. Two tables describing one thing is exactly
	what deviation #5 removed elsewhere, so this pair only survives because
	something checks them - ConfigValidator rule 11 at boot, and here.
]]
local shipped = 0
for id, entry in pairs(WeatherConfig.Weathers) do
	if entry.InV1 then
		shipped += 1
		ok("has a modifier table: " .. id, MutationConfig.WeatherModifiers[id] ~= nil)
	end
end
for id in pairs(MutationConfig.WeatherModifiers) do
	local entry = WeatherConfig.Weathers[id]
	ok("modifiers name a real weather: " .. id, entry ~= nil and entry.InV1 == true)
end
eq("both tables list the same four", shipped, 4)

--[[
	Every mutation a weather names must be a real, shipped mutation. A modifier
	on an unshipped one is a weather that does nothing and says nothing.
]]
for weatherId, modifiers in pairs(MutationConfig.WeatherModifiers) do
	for mutationId in pairs(modifiers) do
		local mutation = MutationConfig.Get(mutationId)
		ok(string.format("%s boosts a real mutation: %s", weatherId, mutationId), mutation ~= nil)
		ok(string.format("...that ships in V1: %s", mutationId), mutation ~= nil and mutation.InV1 == true)
	end
end

print("\n==============================================")
print(string.format("  %d passed, %d failed", passed, failed))
if failed > 0 then error("TESTS FAILED", 0) end
