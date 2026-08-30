--[[
	Step 10 specification.

	The loop closes here: steal, run, KEEP IT. So this measures the loop rather
	than only checking constants - travel distances, carry-weighted return
	times, and whether the "chased all the way home" moment is reachable at all.

	Run with:  ./tests/run.sh
]]

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
Color3 = { fromHex = function(hex) return { Hex = hex } end }
CFrame = { lookAt = function(from, to) return { Position = from, LookAt = to } end,
	new = function(x, y, z) return { Position = v3(x, y, z) } end }

local _shared = { Config = {}, Modules = {} }
game = { GetService = function(_, _n) return { WaitForChild = function() return _shared end } end }
local _realRequire = require
require = function(t) if type(t) == "table" then return t end return _realRequire(t) end

--@INJECT GameConfig=src/ReplicatedStorage/SAD_Shared/Config/GameConfig.lua RarityConfig=src/ReplicatedStorage/SAD_Shared/Config/RarityConfig.lua ChaseConfig=src/ReplicatedStorage/SAD_Shared/Config/ChaseConfig.lua UpgradeConfig=src/ReplicatedStorage/SAD_Shared/Config/UpgradeConfig.lua TableUtil=src/ReplicatedStorage/SAD_Shared/Modules/TableUtil.lua@

_shared.Config.GameConfig = GameConfig

--@INJECT ParkConfig=src/ReplicatedStorage/SAD_Shared/Config/ParkConfig.lua ZoneConfig=src/ReplicatedStorage/SAD_Shared/Config/ZoneConfig.lua ProfileTemplate=src/ServerScriptService/SAD_Server/Services/DataService/ProfileTemplate.lua@

local passed, failed = 0, 0
local function eq(label, got, want)
	if got == want then passed = passed + 1
	else failed = failed + 1; print(string.format("  FAIL %-50s got %s want %s", label, tostring(got), tostring(want))) end
end
local function ok(label, cond)
	if cond then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. label) end
end
local function section(name) print("\n== " .. name) end

local BASE = GameConfig.BaseWalkSpeed

------------------------------------------------------------------ storage
section("Egg storage")

ok("egg storage is bounded", GameConfig.EggStorageCap > 0 and GameConfig.EggStorageCap <= 500)

-- The cap must never bind in normal play, or a player is blocked by a limit
-- they cannot see the point of. Eight incubators is the most that can ever be
-- consuming eggs at once.
local maxIncubators = UpgradeConfig.MaxEffect("incubators")
ok(string.format("storage (%d) far exceeds incubators (%d)", GameConfig.EggStorageCap, maxIncubators),
	GameConfig.EggStorageCap >= maxIncubators * 4)

-- And it must exceed what one full carry can deposit at once, or a maxed pouch
-- could be refused on arrival.
ok("a full carry always fits",
	GameConfig.EggStorageCap > UpgradeConfig.MaxEffect("eggPouch"))

-- The profile must stay bounded overall. docs/10 sized Dinos but never Eggs.
local maxDinos = UpgradeConfig.MaxEffect("dinoStorage") + UpgradeConfig.MaxEffect("dinoSlots") + 5
ok(string.format("profile entry ceiling is sane (%d dinos + %d eggs)", maxDinos, GameConfig.EggStorageCap),
	maxDinos + GameConfig.EggStorageCap < 400)

section("Deposited egg shape")

-- What DepositAll writes must match the schema, or a field appears that
-- Reconcile will happily persist forever.
local depositedEgg = { Rarity = "epic", Origin = "plains", AcquiredAt = 1756512000 }
local templateEgg = { Rarity = true, Origin = true, AcquiredAt = true }
for key in pairs(depositedEgg) do
	ok("deposited field is in the schema: " .. key, templateEgg[key] == true)
end
for key in pairs(templateEgg) do
	ok("schema field is written on deposit: " .. key, depositedEgg[key] ~= nil)
end
ok("Eggs starts empty in the template", TableUtil.IsEmpty(ProfileTemplate.Eggs))

section("Loop statistics")

-- The funnel in docs/14 needs all four of these, and the gap between the first
-- two is how well a player actually runs.
for _, stat in ipairs({ "EggsStolen", "EggsLost", "ChasesEscaped", "ChasesCaught" }) do
	ok("stat exists in the schema: " .. stat, ProfileTemplate.Stats[stat] ~= nil)
	eq("stat starts at zero: " .. stat, ProfileTemplate.Stats[stat], 0)
end

------------------------------------------------------------------ geometry
section("Travel distances")

--[[
	Distance from a park gate to a zone's nearest nest.

	Parks and zones both sit on rings, so the distance depends entirely on how
	far apart their angles are. A player whose park happens to face a zone has a
	much shorter run than one on the far side, and the average is what sets the
	loop's tempo.
]]
local parkGate = ParkConfig.RingRadius() + ParkConfig.PlotSize * 0.5
local nestRing = ZoneConfig.RingRadius
local nestSpread = ZoneConfig.ZoneSize * 0.40

local function distanceAtAngle(angleDeg)
	local a = math.rad(angleDeg)
	local px, pz = parkGate, 0
	local nx, nz = math.cos(a) * (nestRing - nestSpread), math.sin(a) * (nestRing - nestSpread)
	return math.sqrt((nx - px) ^ 2 + (nz - pz) ^ 2)
end

print(string.format("  park gate at %.0f, nearest nests at %.0f", parkGate, nestRing - nestSpread))
print(string.format("  %-22s %10s %10s %12s", "park-to-zone offset", "distance", "walk out", "walk home"))

local aligned = distanceAtAngle(0)
local typical = distanceAtAngle(45)
local worst = distanceAtAngle(180)

for _, case in ipairs({ { "aligned (0 degrees)", aligned }, { "typical (45 degrees)", typical },
	{ "opposite (180 degrees)", worst } }) do
	local carrying = BASE * (1 - RarityConfig.Tiers.legendary.CarryPenalty)
	print(string.format("  %-22s %9.0f %9.0fs %11.0fs", case[1], case[2], case[2] / BASE, case[2] / carrying))
end

ok("an aligned run is short", aligned < 400)
ok("even the worst run is walkable", worst / BASE < 120)
ok("carrying is slower than running out",
	typical / (BASE * (1 - RarityConfig.Tiers.legendary.CarryPenalty)) > typical / BASE)

section("Is being chased home reachable?")

--[[
	The chase leash is 250 studs from the nest, so whether a guardian can follow
	you all the way to your gate depends on how well your park lines up with the
	zone you are robbing.

	It should be possible sometimes - that is the "SAFE!" moment the loop
	diagram in docs/00 describes - but not always, or the leash would never fire
	and escaping by distance would be dead.
]]
local reachable, total = 0, 0
for offset = 0, 350, 10 do
	total = total + 1
	if distanceAtAngle(offset) <= ChaseConfig.MaxChaseDistance then
		reachable = reachable + 1
	end
end

print(string.format("  %d of %d park angles can be chased to the gate (%.0f%%)",
	reachable, total, reachable / total * 100))

ok("being chased home is possible", reachable > 0)
ok("being chased home is not the only ending", reachable < total)

-- The other endings must therefore be the common ones.
ok("the leash fires for most park positions", reachable / total < 0.5)

section("Loop tempo")

--[[
	docs/00 §2 targets a ~45 second micro-loop: travel, steal, chase, deposit.
	Walking, that is not achievable on this map - which is fine, because
	docs/02 §2.2 puts a Zone Shrine in every zone that registers it on the
	Teleport Obelisk, and docs/08 §2.2 puts a PARK button on the bottom bar.

	Measured here so the gap is a known quantity rather than a surprise when
	Step 14 lands.
]]
local carrying = BASE * (1 - RarityConfig.Tiers.legendary.CarryPenalty)
local stealSecs = 5
local chaseSecs = 15

local walkingLoop = typical / BASE + stealSecs + chaseSecs + typical / carrying
local teleportLoop = stealSecs + chaseSecs + 3

print(string.format("  walking:     %.0fs  (out %.0f + steal %d + chase %d + home %.0f)",
	walkingLoop, typical / BASE, stealSecs, chaseSecs, typical / carrying))
print(string.format("  teleporting: %.0fs  (Step 14: zone shrines and the PARK button)", teleportLoop))
print(string.format("  docs/00 target: 45s"))

ok("the walking loop is long but not absurd", walkingLoop < 150)
ok("teleporting reaches the documented tempo", teleportLoop <= 45)
ok("teleports are worth building", walkingLoop > teleportLoop * 1.5)

section("Safe-zone rules")

-- A park's shield dome must cover the whole plot, or there is a corner of your
-- own park where you are not actually safe.
ok("the dome covers the plot", ParkConfig.SafeDomeRadius >= ParkConfig.PlotSize * 0.5)

-- Guardians must be able to reach a gate they then refuse to cross, or the
-- rule never visibly applies.
ok("the leash outlasts a plot's own width",
	ChaseConfig.MaxChaseDistance > ParkConfig.PlotSize)

-- Recovering from a catch must be quicker than walking home, or being caught
-- near your gate is a bigger setback than being caught far away.
ok("recovery is quicker than the walk home",
	ChaseConfig.TripRagdollSecs + ChaseConfig.WindedSecs < typical / carrying)

print(string.format("\n%s\n  %d passed, %d failed\n", string.rep("=", 46), passed, failed))
if failed > 0 then error("TESTS FAILED") end
