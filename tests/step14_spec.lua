--[[
	Step 14 specification.

	Zones, unlocking and teleports. The failure modes that nothing throws for:

	  * a teleport destination that lands INSIDE the zone it travels to, past
	    the gate check walking would have applied;
	  * a zone square that overlaps the park ring, so standing in your own park
	    counts as trespassing in a locked zone;
	  * an unlock gate that does not match the one docs/02 publishes on the sign
	    a player is reading.

	It also re-measures docs/00's loop tempo claim - 86 seconds on foot, 23 with
	teleports - now that the teleports exist.

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
function Vector3MT.__index.Magnitude(self) return math.sqrt(self.X^2 + self.Y^2 + self.Z^2) end
Vector3MT.__index.Unit = nil
Vector3 = { new = v3, zero = v3(0, 0, 0), yAxis = v3(0, 1, 0) }
Color3 = { fromHex = function(h) return { Hex = h } end }

--[[
	A CFrame stand-in with only what this spec exercises: a position, a yaw
	basis built from lookAt, composition with an offset, and the inverse
	transform ZoneService.ZoneAt uses. Rotation is 2D because every zone origin
	is level - which the real OriginOf guarantees by passing Vector3.yAxis.
]]
local CFrameMT = {}
CFrameMT.__index = CFrameMT

local function makeCF(pos, look)
	-- `look` is the LookVector: the frame's local -Z.
	local right = v3(-look.Z, 0, look.X) -- +X = look rotated -90 degrees about Y
	return setmetatable({ P = pos, Look = look, Right = right }, CFrameMT)
end

local function cfNew(x, y, z) return makeCF(v3(x, y, z), v3(0, 0, -1)) end

CFrameMT.__mul = function(a, b)
	-- b is a pure translation CFrame: apply its offset in a's basis.
	local o = b.P
	local up = v3(0, 1, 0)
	local forward = a.Look * -1 -- local +Z
	local pos = a.P + a.Right * o.X + up * o.Y + forward * o.Z
	return makeCF(pos, a.Look)
end

function CFrameMT.__index.PointToObjectSpace(self, point)
	local d = point - self.P
	local forward = self.Look * -1
	return v3(d.X * self.Right.X + d.Z * self.Right.Z, d.Y,
		d.X * forward.X + d.Z * forward.Z)
end

CFrame = {
	new = cfNew,
	lookAt = function(from, to, _up)
		local d = to - from
		local len = math.sqrt(d.X^2 + d.Y^2 + d.Z^2)
		return makeCF(from, if len > 0 then v3(d.X / len, d.Y / len, d.Z / len) else v3(0, 0, -1))
	end,
	Angles = function(_x, y, _z)
		-- Only ever used to spin a destination 180 degrees; the spec checks
		-- positions, not facings, so this is an identity translation.
		return cfNew(0, 0, 0)
	end,
}

local _shared = { Config = {}, Modules = {} }
game = { GetService = function(_, _n) return { WaitForChild = function() return _shared end } end }
local _realRequire = require
require = function(t) if type(t) == "table" then return t end return _realRequire(t) end

--@INJECT GameConfig=src/ReplicatedStorage/SAD_Shared/Config/GameConfig.lua RarityConfig=src/ReplicatedStorage/SAD_Shared/Config/RarityConfig.lua DinoConfig=src/ReplicatedStorage/SAD_Shared/Config/DinoConfig.lua ParkConfig=src/ReplicatedStorage/SAD_Shared/Config/ParkConfig.lua ZoneConfig=src/ReplicatedStorage/SAD_Shared/Config/ZoneConfig.lua Format=src/ReplicatedStorage/SAD_Shared/Modules/Format.lua@

local passed, failed = 0, 0
local function eq(label, got, want)
	if got == want then passed = passed + 1
	else failed = failed + 1; print(string.format("  FAIL %-52s got %s want %s", label, tostring(got), tostring(want))) end
end
local function near(label, got, want, tol)
	if math.abs(got - want) <= tol then passed = passed + 1
	else failed = failed + 1; print(string.format("  FAIL %-52s got %.3f want ~%.3f", label, got, want)) end
end
local function ok(label, cond)
	if cond then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. label) end
end
local function section(name) print("\n== " .. name) end

local function profile(overrides)
	local data = { ZonesUnlocked = { plains = true }, Shrines = {}, Upgrades = {}, Defences = {},
		Dinos = {}, Index = {}, Rebirths = 0, Fossils = 0 }
	for k, v in pairs(overrides or {}) do data[k] = v end
	return data
end

------------------------------------------------------------------ gates
section("Unlock gates (docs/02 §2.1)")

--[[
	The table on the sign a player reads at the gate. If these drift, the game
	charges a price the design never published.
]]
local PUBLISHED = {
	{ "plains", 0, 0 }, { "canyon", 5000, 0 }, { "swamp", 45000, 0 }, { "frozen", 400000, 0 },
}
for _, row in ipairs(PUBLISHED) do
	local zone = ZoneConfig.Get(row[1])
	ok("zone exists: " .. row[1], zone ~= nil)
	eq(row[1] .. " costs " .. row[2], zone.Unlock.Fossils, row[2])
	eq(row[1] .. " rebirth gate", zone.Unlock.Rebirths, row[3])
end
eq("V1 ships 4 zones", ZoneConfig.Count(), 4)
eq("every published zone is asserted", #PUBLISHED, ZoneConfig.Count())

-- Zones 1-4 are "pure money" (docs/02 §2.1): no rebirth, index or rarity gate
-- may appear before Zone 5, or a Day-1 player cannot reach Zone 4.
for _, zoneId in ZoneConfig.Order do
	local gate = ZoneConfig.Get(zoneId).Unlock
	eq(zoneId .. " has no rebirth gate", gate.Rebirths, 0)
	eq(zoneId .. " has no index gate", gate.IndexPercent, 0)
	eq(zoneId .. " has no rarity gate", gate.OwnRarity, nil)
end

-- Costs must rise with zone order, or the progression reads backwards.
local previousCost = -1
for _, zoneId in ZoneConfig.Order do
	local cost = ZoneConfig.Get(zoneId).Unlock.Fossils
	ok("cost rises: " .. zoneId, cost > previousCost)
	previousCost = cost
end

------------------------------------------------------------------ check
section("UnlockCheck")

local broke = profile()
local okCanyon, reason = ZoneConfig.UnlockCheck("canyon", broke, DinoConfig, RarityConfig)
ok("a broke player cannot unlock Zone 2", not okCanyon)
eq("...and is told why", reason, "not enough Fossils")

local exact = profile({ Fossils = 5000 })
ok("exactly the price is enough", (ZoneConfig.UnlockCheck("canyon", exact, DinoConfig, RarityConfig)))

local short = profile({ Fossils = 4999 })
ok("one Fossil short is not", not (ZoneConfig.UnlockCheck("canyon", short, DinoConfig, RarityConfig)))

local owned = profile({ Fossils = 1e9, ZonesUnlocked = { plains = true, canyon = true } })
local reOk, reReason = ZoneConfig.UnlockCheck("canyon", owned, DinoConfig, RarityConfig)
ok("an owned zone cannot be bought twice", not reOk)
eq("...and says so", reReason, "already unlocked")

ok("an unknown zone is refused",
	not (ZoneConfig.UnlockCheck("atlantis", profile({ Fossils = 1e9 }), DinoConfig, RarityConfig)))
ok("no profile is refused", not (ZoneConfig.UnlockCheck("canyon", nil, DinoConfig, RarityConfig)))

--[[
	The other three gate kinds ship with zones 5-10, so there is nothing live to
	measure them on. Injected here for the same reason step13_spec injects a
	bogus upgrade track: machinery nobody has watched work is not machinery.
]]
ZoneConfig.Zones.testzone = {
	Id = "testzone", RingSlot = 5, DisplayName = "Test", Order = 5, Color = "FFFFFF",
	Unlock = { Fossils = 100, Rebirths = 3, IndexPercent = 50, OwnRarity = "legendary" },
	NestCount = 1, EggsPerNest = 1, RespawnSecs = 1, GuardiansPerNest = { min = 1, max = 1 },
	LuckBonus = 0, GuardianSpeedBonus = 0, Hazards = {}, WorldModel = "X", Tagline = "-",
}

local speciesCount = 0
for _ in DinoConfig.Species do speciesCount += 1 end

local function withIndex(count, overrides)
	local data = profile(overrides)
	local seen = 0
	for id in DinoConfig.Species do
		if seen >= count then break end
		data.Index[id] = true
		seen += 1
	end
	return data
end

local rich = profile({ Fossils = 1e9 })
local _, r1 = ZoneConfig.UnlockCheck("testzone", rich, DinoConfig, RarityConfig)
eq("rebirth gate fires first", r1, "rebirth too low")

local rebirthed = profile({ Fossils = 1e9, Rebirths = 3 })
local _, r2 = ZoneConfig.UnlockCheck("testzone", rebirthed, DinoConfig, RarityConfig)
eq("then the index gate", r2, "index too low")

local indexed = withIndex(math.ceil(speciesCount * 0.5), { Fossils = 1e9, Rebirths = 3 })
local _, r3 = ZoneConfig.UnlockCheck("testzone", indexed, DinoConfig, RarityConfig)
eq("then the rarity gate", r3, "missing a legendary")

-- A rarity gate is satisfied by that tier OR BETTER, not by that tier exactly.
local withEpic = withIndex(math.ceil(speciesCount * 0.5), { Fossils = 1e9, Rebirths = 3,
	Dinos = { a = { SpeciesId = "trex", Rarity = "epic" } } })
ok("an Epic does not satisfy a Legendary gate",
	not (ZoneConfig.UnlockCheck("testzone", withEpic, DinoConfig, RarityConfig)))

local withTitan = withIndex(math.ceil(speciesCount * 0.5), { Fossils = 1e9, Rebirths = 3,
	Dinos = { a = { SpeciesId = "trex", Rarity = "titan" } } })
ok("a Titan does satisfy a Legendary gate",
	(ZoneConfig.UnlockCheck("testzone", withTitan, DinoConfig, RarityConfig)))

-- The requirements breakdown is what the client renders, so it must list every
-- gate, met or not - a locked zone says WHICH gate is short.
local _, _, requirements = ZoneConfig.UnlockCheck("testzone", rich, DinoConfig, RarityConfig)
eq("all four gates are listed", #requirements, 4)
local metCount = 0
for _, req in ipairs(requirements) do
	if req.Met then metCount += 1 end
end
eq("a rich player has met exactly one of them", metCount, 1)

local _, _, canyonReqs = ZoneConfig.UnlockCheck("canyon", broke, DinoConfig, RarityConfig)
eq("a money-only zone lists one gate", #canyonReqs, 1)

ZoneConfig.Zones.testzone = nil

--------------------------------------------------------------- geometry
section("Teleport destinations")

--[[
	Reimplements ZoneService.DestinationCFrame and ZoneAt. The service itself
	needs Players, Workspace and four other services, so it cannot be injected;
	the geometry is the part that can be wrong silently, and it is pure.
]]
local HALF = ZoneConfig.ZoneSize * 0.5

local function destinationOf(zoneId)
	local origin = ZoneConfig.OriginOf(zoneId)
	return (origin * CFrame.new(0, 8, HALF + 30)).P
end

local function zoneAt(point)
	for zoneId in ZoneConfig.Zones do
		local origin = ZoneConfig.OriginOf(zoneId)
		local localPoint = origin:PointToObjectSpace(point)
		if math.abs(localPoint.X) <= HALF and math.abs(localPoint.Z) <= HALF then
			return zoneId
		end
	end
	return nil
end

-- The basis must be the one the whole project uses: local +Z faces the hub.
for _, zoneId in ZoneConfig.Order do
	local origin = ZoneConfig.OriginOf(zoneId)
	local centre = origin.P
	local hubward = (origin * CFrame.new(0, 0, 100)).P
	ok("local +Z faces the hub: " .. zoneId,
		hubward:Magnitude() < centre:Magnitude() - 99)
end

--[[
	The one that matters. A teleport must land you OUTSIDE the zone, at its
	gate - otherwise it drops a player past the check that walking applies, and
	the trespass sweep would immediately shove them back out again.
]]
for _, zoneId in ZoneConfig.Order do
	local landing = destinationOf(zoneId)
	eq("teleport lands outside " .. zoneId, zoneAt(landing), nil)
	local origin = ZoneConfig.OriginOf(zoneId)
	local localLanding = origin:PointToObjectSpace(landing)
	near("...30 studs beyond its gate: " .. zoneId, localLanding.Z, HALF + 30, 0.5)
end

-- And a point at each centre must resolve to that zone and no other.
for _, zoneId in ZoneConfig.Order do
	eq("centre resolves to itself: " .. zoneId, zoneAt(ZoneConfig.OriginOf(zoneId).P), zoneId)
end

eq("the hub centre is in no zone", zoneAt(Vector3.new(0, 0, 0)), nil)

--[[
	Zone squares must not reach the park ring, or standing in your own park
	registers as trespassing in a locked zone and the sweep teleports you out
	of your own home. Step 7 checked zone-against-zone; this is the pair it
	could not check, because parks were the other module.
]]
local parkRing = ParkConfig.RingRadius()
local parkOuter = parkRing + ParkConfig.PlotSize * 0.5
local nearestZoneEdge = ZoneConfig.RingRadius - HALF * math.sqrt(2)

print(string.format("  park ring outer edge %.0f, nearest zone corner %.0f, clearance %.0f studs",
	parkOuter, nearestZoneEdge, nearestZoneEdge - parkOuter))

ok("zone squares clear the park ring entirely", nearestZoneEdge > parkOuter)

-- Sampled rather than argued: walk the park ring and check every plot centre.
local trespassing = 0
for index = 0, ParkConfig.PlotCount - 1 do
	local angle = index / ParkConfig.PlotCount * math.pi * 2
	local point = Vector3.new(math.cos(angle) * parkRing, 0, math.sin(angle) * parkRing)
	if zoneAt(point) then trespassing += 1 end
end
eq("no park centre sits inside a zone", trespassing, 0)

--------------------------------------------------------------- loop tempo
section("Loop tempo, with teleports (docs/00 §3)")

--[[
	Step 10 measured the walking loop at 86 seconds against a 45-second target,
	and recorded that Step 14 would bring it to 23. Now that Step 14 exists,
	the same measurement is re-run against the real destinations rather than
	against a plan.

	The legs that remain on foot are the ones inside a zone - gate to nest and
	back - plus the walk from the park spawn pad to its own gate. Everything
	between rings is a teleport.
]]
local walkSpeed = GameConfig.BaseWalkSpeed

local distances = {}
for _, zoneId in ZoneConfig.Order do
	for _, offset in ZoneConfig.NestOffsets(zoneId) do
		-- Distance from the gate (local 0, half) to the nest, inside the zone.
		local dx, dz = offset.X, offset.Z - HALF
		table.insert(distances, math.sqrt(dx * dx + dz * dz))
	end
end
table.sort(distances)

local nearestNest = distances[1]
local typicalNest = distances[math.ceil(#distances / 2)]
local worstNest = distances[#distances]

local parkWalk = ParkConfig.PlotSize * 0.5 -- spawn pad to gate, worst case

--- Into the zone, out again, plus the walk across your own plot.
local function loopFor(nestDistance)
	return (parkWalk + nestDistance * 2) / walkSpeed
end

print(string.format("  gate-to-nest: nearest %.0f, typical %.0f, furthest %.0f studs",
	nearestNest, typicalNest, worstNest))
print(string.format("  loop with teleports: %.0f s nearest nest, %.0f s typical, %.0f s furthest",
	loopFor(nearestNest), loopFor(typicalNest), loopFor(worstNest)))
print("  (on foot it was 86 s; docs/00's target is 45 s)")

--[[
	Step 10 projected 23 seconds for this. The real number, measured against
	the destinations that now exist rather than against a plan, is 33 seconds
	to the furthest nest and 27 to a typical one - because the projection
	priced a typical nest rather than the walk across a 350-stud zone to the
	far side of it. Still less than half the 86 seconds on foot, and inside the
	45-second target at every nest in the game. docs/00 now carries the
	measured figures.
]]
ok("every nest is inside the 45-second target", loopFor(worstNest) < 45)
ok("a typical nest is comfortably inside it", loopFor(typicalNest) < 35)
ok("...and it is not instant, so the zone still has to be crossed", loopFor(nearestNest) > 8)
ok("teleports more than halve the walking loop", loopFor(worstNest) < 86 * 0.5)

--[[
	The claim being checked is specifically that the RING traversal is what the
	teleports remove. Worth stating in numbers: the walk a teleport replaces.
]]
local parkToZone = ZoneConfig.RingRadius - ParkConfig.RingRadius()
local acrossMap = ZoneConfig.RingRadius * 2
print(string.format("  a teleport replaces %.0f studs at best and %.0f at worst (%.0f-%.0f s)",
	parkToZone, acrossMap, parkToZone / walkSpeed, acrossMap / walkSpeed))
ok("the walk being skipped is the dominant one", acrossMap / walkSpeed > loopFor(worstNest))

------------------------------------------------------------ progression
section("Can a Day-1 player reach Zone 4?")

--[[
	docs/02 §2.1: "Zones 1-4 are pure money, so a Day-1 player reaches Zone 4."
	Measured against docs/05 §8's cumulative income - which is the same curve
	step13_spec uses for the upgrade constraint, so the two agree by
	construction rather than by luck.

	Zone costs are SPENT, and so is the upgrade tree, so this checks the zone
	gates alone are reachable - a floor, not a schedule.
]]
local CURVE = { { 300, 6 }, { 1200, 45 }, { 3600, 380 }, { 7200, 2100 }, { 10800, 5400 },
	{ 21600, 34000 }, { 43200, 480000 }, { 86400, 6.2e6 } }

local function rateAt(t)
	if t <= CURVE[1][1] then return CURVE[1][2] end
	for i = 1, #CURVE - 1 do
		local a, b = CURVE[i], CURVE[i + 1]
		if t <= b[1] then
			local f = (t - a[1]) / (b[1] - a[1])
			return math.exp(math.log(a[2]) + f * (math.log(b[2]) - math.log(a[2])))
		end
	end
	return CURVE[#CURVE][2]
end

--- Wall-clock seconds until cumulative published income reaches `target`.
local function timeToEarn(target)
	local total, t, dt = 0, 0, 10
	while total < target and t < 86400 do
		total += rateAt(t) * dt
		t += dt
	end
	return t
end

local DAY_ONE = 3 * 3600
for _, zoneId in ZoneConfig.Order do
	local cost = ZoneConfig.Get(zoneId).Unlock.Fossils
	local when = timeToEarn(cost)
	print(string.format("  %-8s %12s Fossils  reachable at %s", zoneId, Format.Number(cost),
		if cost == 0 then "start" else Format.Time(when)))
	ok("reachable on day one: " .. zoneId, cost == 0 or when <= DAY_ONE)
end

--[[
	And the gate that teaches rebirth. docs/02 §2.1 puts Zone 5's rebirth
	requirement "at roughly the 3-hour mark, which is exactly when players are
	ready to be taught what rebirth is", and docs/05 §8 puts Rebirth 1 at the
	same 3 hours. V1.1 ships Zone 5, so the two have to agree.

	Everything above is a FLOOR, not a schedule: timeToEarn measures GROSS
	cumulative income, and a real player is spending all the way along - 400 K
	on Zone 4 alone, and 1.67 B to max the upgrade tree. So a gross floor
	earlier than the published mark is consistent with arriving at it on time,
	and a floor LATER than the mark would falsify the claim outright.
]]
local zone5Cost = 3500000
local zone5Floor = timeToEarn(zone5Cost)
print(string.format("  zone 5 (V1.1) %s Fossils: gross-earnings floor %s, published mark 3h",
	Format.Number(zone5Cost), Format.Time(zone5Floor)))

ok("Zone 5 is not reachable in the first hour", zone5Floor > 3600)
ok("...and its floor is inside the published 3-hour mark", zone5Floor < DAY_ONE)

print("\n==============================================")
print(string.format("  %d passed, %d failed", passed, failed))
if failed > 0 then error("TESTS FAILED", 0) end
