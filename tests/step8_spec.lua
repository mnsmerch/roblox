--[[
	Step 8 specification.

	The carry-weight table in docs/03 §1.2 is published to players: a Titan egg
	costs 45% of your speed. This asserts the code actually produces those
	numbers, because a published number the game does not honour is worse than
	no number at all.

	Also covers the luck composition and the rarity roll, including the tail
	guard - maxed luck must not be able to buy a Titan.

	Run with:  ./tests/run.sh
]]

-- ── Roblox shims ────────────────────────────────────────────────────────────
local RandomMT = {}
RandomMT.__index = RandomMT
function RandomMT:NextNumber(a, b)
	self.s = (self.s * 16807) % 2147483647
	local x = self.s / 2147483647
	if a then return a + x * (b - a) end
	return x
end
function RandomMT:NextInteger(a, b) return a + math.floor(self:NextNumber() * (b - a + 1)) end
Random = { new = function(seed) return setmetatable({ s = seed or 12345 }, RandomMT) end }

local Vector3MT = {}
Vector3MT.__index = Vector3MT
local function v3(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, Vector3MT) end
Vector3MT.__add = function(a, b) return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
Vector3MT.__sub = function(a, b) return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
Vector3MT.__mul = function(a, b)
	if type(b) == "number" then return v3(a.X * b, a.Y * b, a.Z * b) end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
Vector3 = { new = v3, zero = v3(0, 0, 0), yAxis = v3(0, 1, 0) }
Color3 = { fromHex = function(hex) return { Hex = hex } end, fromHSV = function() return {} end }
CFrame = {
	lookAt = function(from, to) return { Position = from, LookAt = to } end,
	new = function(x, y, z) return { Position = v3(x, y, z) } end,
}
typeof = type

local _shared = { Config = {}, Modules = {} }
local _services = {}
game = { GetService = function(_, name) return _services[name] end }
_services.RunService = { IsServer = function() return true end, IsStudio = function() return false end }
_services.Players = { PlayerRemoving = { Connect = function() end }, PlayerAdded = { Connect = function() end },
	GetPlayers = function() return {} end }
_services.HttpService = { GenerateGUID = function() return "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" end }
_services.ReplicatedStorage = { WaitForChild = function() return _shared end }
_services.Workspace = { WaitForChild = function() return { WaitForChild = function() return {} end } end }

local _realRequire = require
require = function(target)
	if type(target) == "table" then return target end
	return _realRequire(target)
end

--@INJECT GameConfig=src/ReplicatedStorage/SAD_Shared/Config/GameConfig.lua RarityConfig=src/ReplicatedStorage/SAD_Shared/Config/RarityConfig.lua RebirthConfig=src/ReplicatedStorage/SAD_Shared/Config/RebirthConfig.lua DailyConfig=src/ReplicatedStorage/SAD_Shared/Config/DailyConfig.lua ProductConfig=src/ReplicatedStorage/SAD_Shared/Config/ProductConfig.lua TutorialConfig=src/ReplicatedStorage/SAD_Shared/Config/TutorialConfig.lua UpgradeConfig=src/ReplicatedStorage/SAD_Shared/Config/UpgradeConfig.lua ZoneConfig=src/ReplicatedStorage/SAD_Shared/Config/ZoneConfig.lua RNG=src/ReplicatedStorage/SAD_Shared/Modules/RNG.lua Signal=src/ReplicatedStorage/SAD_Shared/Modules/Signal.lua@

_shared.Config.GameConfig = GameConfig
_shared.Config.RarityConfig = RarityConfig
_shared.Config.RebirthConfig = RebirthConfig
_shared.Config.UpgradeConfig = UpgradeConfig
_shared.Config.ZoneConfig = ZoneConfig
_shared.Config.DailyConfig = DailyConfig
_shared.Config.ProductConfig = ProductConfig
_shared.Config.TutorialConfig = TutorialConfig
_shared.Modules.RNG = RNG
_shared.Modules.Signal = Signal
_shared.Modules.Log = { debug = function() end, info = function() end, warn = function() end, error = function() end }
_shared.Modules.Net = { OnEvent = function() end }
_shared.SAD_Assets = { WaitForChild = function() return {} end }

--@INJECT Stats=src/ReplicatedStorage/SAD_Shared/Modules/Stats.lua@
_shared.Modules.Stats = Stats

--@INJECT EggService=src/ServerScriptService/SAD_Server/Services/EggService/init.lua@

local passed, failed = 0, 0
local function eq(label, got, want)
	if got == want then passed = passed + 1
	else failed = failed + 1; print(string.format("  FAIL %-48s got %s want %s", label, tostring(got), tostring(want))) end
end
local function near(label, got, want, tol)
	if math.abs(got - want) <= tol then passed = passed + 1
	else failed = failed + 1; print(string.format("  FAIL %-48s got %.4f want ~%.4f", label, got, want)) end
end
local function ok(label, cond)
	if cond then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. label) end
end
local function section(name) print("\n== " .. name) end

------------------------------------------------------------------ carry table
section("The published carry table (docs/03 §1.2)")

--[[
	Every one of these appears in the design document as a promise to the
	player. If the code stops producing them, this fails.
]]
local EXPECTED_SPEED = {
	common = 20.0, uncommon = 19.2, rare = 18.2, epic = 17.0,
	legendary = 15.6, mythic = 14.2, ancient = 13.0, secret = 12.0, titan = 11.0,
}

print(string.format("  %-11s %9s %9s", "rarity", "penalty", "speed"))
for _, rarityId in ipairs(RarityConfig.Order) do
	local penalty = RarityConfig.Tiers[rarityId].CarryPenalty
	local computed = EggService.CarryPenaltyOf({ penalty }, 1)
	local speed = GameConfig.BaseWalkSpeed * (1 - computed)

	print(string.format("  %-11s %8.0f%% %9.1f", rarityId, penalty * 100, speed))
	near("speed matches the published table: " .. rarityId, speed, EXPECTED_SPEED[rarityId], 0.01)
end

-- Penalties must rise with rarity, or carrying a Titan is easier than a Rare.
local previous = -1
for _, rarityId in ipairs(RarityConfig.Order) do
	local penalty = RarityConfig.Tiers[rarityId].CarryPenalty
	ok("penalty rises with rarity: " .. rarityId, penalty >= previous)
	previous = penalty
end

section("Multi-carry stacking")

eq("carrying nothing costs nothing", EggService.CarryPenaltyOf({}, 1), 0)
near("one titan egg", EggService.CarryPenaltyOf({ 0.45 }, 1), 0.45, 0.0001)

-- The second egg contributes 40% of its own weight.
near("two titan eggs", EggService.CarryPenaltyOf({ 0.45, 0.45 }, 1), 0.45 + 0.45 * 0.4, 0.0001)
near("titan plus common", EggService.CarryPenaltyOf({ 0.45, 0.0 }, 1), 0.45, 0.0001)
near("titan plus rare", EggService.CarryPenaltyOf({ 0.45, 0.09 }, 1), 0.45 + 0.09 * 0.4, 0.0001)

-- The heaviest counts in full regardless of the order it arrives in.
near("order does not matter",
	EggService.CarryPenaltyOf({ 0.09, 0.45 }, 1),
	EggService.CarryPenaltyOf({ 0.45, 0.09 }, 1), 0.0001)

-- Five titan eggs, the theoretical worst case, must still leave you moving.
local worst = EggService.CarryPenaltyOf({ 0.45, 0.45, 0.45, 0.45, 0.45 }, 1)
near("five titan eggs clamp at the cap", worst, GameConfig.MaxCarryPenalty, 0.0001)
ok("even the worst carry can still move", GameConfig.BaseWalkSpeed * (1 - worst) > 2)

section("Strong Back")

local maxStrongBack = UpgradeConfig.MaxEffect("strongBack")
near("Strong Back maxes at -60%", maxStrongBack, 0.40, 0.001)

-- The worked example from docs/03 §1.2.
near("maxed Strong Back carries a Titan egg at 16.4",
	GameConfig.BaseWalkSpeed * (1 - EggService.CarryPenaltyOf({ 0.45 }, maxStrongBack)), 16.4, 0.01)

for level = 0, 10 do
	local mult = UpgradeConfig.EffectAt("strongBack", level)
	local penalty = EggService.CarryPenaltyOf({ 0.45 }, mult)
	ok("Strong Back never makes carrying worse: L" .. level, penalty <= 0.45 + 1e-9)
end
ok("Strong Back level 10 beats level 0",
	EggService.CarryPenaltyOf({ 0.45 }, UpgradeConfig.EffectAt("strongBack", 10))
	< EggService.CarryPenaltyOf({ 0.45 }, UpgradeConfig.EffectAt("strongBack", 0)))

------------------------------------------------------------------ luck
section("Luck composition")

local function profile(overrides)
	local data = { Upgrades = {}, Rebirths = 0, LuckNodes = 0 }
	for key, value in pairs(overrides or {}) do data[key] = value end
	return data
end

eq("a fresh player in Zone 1 has no luck",
	EggService.LuckFrom(profile(), ZoneConfig.Zones.plains), 0)

near("Egg Sense level 1 is +5%",
	EggService.LuckFrom(profile({ Upgrades = { eggSense = 1 } }), nil), 0.05, 0.0001)
near("Egg Sense maxed is +75%",
	EggService.LuckFrom(profile({ Upgrades = { eggSense = 15 } }), nil), 0.75, 0.0001)
near("ten rebirths are +50%",
	EggService.LuckFrom(profile({ Rebirths = 10 }), nil), 0.50, 0.0001)
near("Zone 4 adds its own bonus",
	EggService.LuckFrom(profile(), ZoneConfig.Zones.frozen), ZoneConfig.Zones.frozen.LuckBonus, 0.0001)
near("twenty luck nodes are +10%",
	EggService.LuckFrom(profile({ LuckNodes = 20 }), nil), 0.10, 0.0001)

-- Sources add.
near("sources compose",
	EggService.LuckFrom(profile({ Upgrades = { eggSense = 15 }, Rebirths = 15, LuckNodes = 20 }),
		ZoneConfig.Zones.frozen),
	0.75 + 0.75 + 0.10 + ZoneConfig.Zones.frozen.LuckBonus, 0.0001)

-- The documented hard cap.
ok("luck is capped at +500%",
	EggService.LuckFrom(profile({ Rebirths = 9999, LuckNodes = 999999 }), ZoneConfig.Zones.frozen) <= 5.0)

------------------------------------------------------------------ rolls
section("Rarity rolls")

local function distribution(zoneId, luck, samples)
	local generator = Random.new(4242)
	local counts = {}
	for _, rarityId in ipairs(RarityConfig.Order) do counts[rarityId] = 0 end
	for _ = 1, samples do
		local rolled = EggService.RollRarityIn(zoneId, luck, generator)
		counts[rolled] = counts[rolled] + 1
	end
	return counts
end

local N = 300000
local base = distribution("plains", 0, N)
local weights = RarityConfig.ZoneWeights.plains

near("zero luck reproduces the Zone 1 common weight",
	base.common / N * 100, weights.common / 1e6, 0.5)
near("zero luck reproduces the Zone 1 uncommon weight",
	base.uncommon / N * 100, weights.uncommon / 1e6, 0.5)
near("zero luck reproduces the Zone 1 rare weight",
	base.rare / N * 100, weights.rare / 1e6, 0.4)

-- A tier V1 ships no species for must never be rolled.
eq("Zone 1 never rolls mythic in V1", base.mythic, 0)
eq("Zone 1 never rolls ancient in V1", base.ancient, 0)

local lucky = distribution("plains", 1.0, N)
ok("luck reduces commons", lucky.common < base.common)
ok("luck increases epics", lucky.epic > base.epic)

print(string.format("  luck 0:    common %.2f%%  epic %.3f%%", base.common / N * 100, base.epic / N * 100))
print(string.format("  luck +100%%: common %.2f%%  epic %.3f%%", lucky.common / N * 100, lucky.epic / N * 100))

--[[
	The tail guard from docs/01 §1.2: luck must help the tiers a player can
	realistically grind MORE than it helps the lottery tiers.

	The comparison is Secret and Titan against MYTHIC and ANCIENT - not against
	Epic. Titan's luck power (0.40) is deliberately above Epic's (0.35); the
	guard is about the top of the ladder, not the middle.

	V1 zeroes Mythic and Ancient, so this cannot be measured on a live zone
	vector - there is no probability to compare against. It is measured on the
	design-target Zone 1 weights from docs/01 §1.1 instead, which is what the
	live vectors return to once those species ship in V1.1 and V1.3.
]]
local powers = RarityConfig.LuckPowers()

local DESIGN_TARGET_ZONE1 = {
	common = 62000000, uncommon = 27000000, rare = 9000000, epic = 1800000,
	legendary = 190000, mythic = 9500, ancient = 480, secret = 19, titan = 1,
}
local designSum = 0
for _, weight in pairs(DESIGN_TARGET_ZONE1) do designSum = designSum + weight end
eq("the design-target vector still sums to 1e8", designSum, RarityConfig.WeightTotal)

local designScaled = RNG.ApplyLuck(DESIGN_TARGET_ZONE1, powers, 1.0)
local function gain(rarityId)
	return RNG.ProbabilityOf(designScaled, rarityId) / RNG.ProbabilityOf(DESIGN_TARGET_ZONE1, rarityId)
end

print(string.format("  tail guard at +100%% luck: mythic x%.2f  ancient x%.2f  secret x%.2f  titan x%.2f",
	gain("mythic"), gain("ancient"), gain("secret"), gain("titan")))

ok("luck helps mythic more than secret", gain("mythic") > gain("secret"))
ok("luck helps mythic more than titan", gain("mythic") > gain("titan"))
ok("luck helps ancient more than secret", gain("ancient") > gain("secret"))
ok("luck helps ancient more than titan", gain("ancient") > gain("titan"))
ok("luck still drains commons", gain("common") < 1)

-- And the config-level ordering the guard rests on.
ok("secret luck power is below mythic",
	RarityConfig.Tiers.secret.LuckPower < RarityConfig.Tiers.mythic.LuckPower)
ok("titan luck power is below ancient",
	RarityConfig.Tiers.titan.LuckPower < RarityConfig.Tiers.ancient.LuckPower)

--[[
	A V1-specific consequence worth stating rather than discovering later:
	with Mythic and Ancient zeroed, the highest luck powers in play are
	Legendary and Secret, both 0.55. So in V1 a maxed-luck player improves
	their Secret odds as much as their Legendary odds. At 1 in 5,263,158 in
	Zone 1 that is a rounding error in absolute terms, and it corrects itself
	when the missing tiers ship.
]]
eq("V1's top live luck powers are legendary and secret",
	RarityConfig.Tiers.legendary.LuckPower, RarityConfig.Tiers.secret.LuckPower)

-- Every zone must roll something hatchable, at any luck.
for _, zoneId in ipairs(ZoneConfig.Order) do
	for _, luck in ipairs({ 0, 1, 5 }) do
		local rolled = EggService.RollRarityIn(zoneId, luck, Random.new(7))
		ok(string.format("%s at luck %g rolls a real tier", zoneId, luck),
			RarityConfig.Tiers[rolled] ~= nil)
		ok(string.format("%s at luck %g rolls a tier with weight", zoneId, luck),
			(RarityConfig.ZoneWeights[zoneId][rolled] or 0) > 0)
	end
end

eq("an unknown zone falls back to common", EggService.RollRarityIn("atlantis", 0, Random.new(1)), "common")

------------------------------------------------------------------ capacity
section("Egg capacity")

eq("a new player carries one egg", UpgradeConfig.EffectAt("eggPouch", 0), 1)
eq("Egg Pouch maxes at five", UpgradeConfig.MaxEffect("eggPouch"), 5)
for level = 0, 4 do
	eq("capacity is level plus one: L" .. level, UpgradeConfig.EffectAt("eggPouch", level), level + 1)
end

print(string.format("\n%s\n  %d passed, %d failed\n", string.rep("=", 46), passed, failed))
if failed > 0 then error("TESTS FAILED") end
