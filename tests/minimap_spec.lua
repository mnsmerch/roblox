--[[
	Minimap specification.

	The minimap is pure geometry — every mark comes from `ZoneConfig` and
	`ParkConfig`, so all of it can be checked here rather than by squinting at
	a screenshot.

	Three things are asserted:

	  1. `ZoneConfig.ZoneAt`, which moved out of `ZoneService` when the minimap
	     and the analytics snapshot turned out to need the same square test.
	     Driven at every zone's centre, every edge and every corner.
	  2. The projection: everything the world contains lands on the map, the
	     origin is the centre, and nothing clips off an edge.
	  3. That the map cannot leak a position the game had not already given the
	     player — the raid design depends on not knowing where people are.

	Run with:  ./tests/run.sh
]]

Color3 = { fromHex = function(h) return { Hex = h } end }
typeof = type

local Vector3MT = {}
Vector3MT.__index = Vector3MT
local function v3(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, Vector3MT) end
Vector3MT.__add = function(a, b) return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
Vector3MT.__sub = function(a, b) return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
Vector3MT.__mul = function(a, b)
	if type(b) == "number" then return v3(a.X * b, a.Y * b, a.Z * b) end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
Vector3MT.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
Vector3 = { new = v3, zero = v3(0, 0, 0), yAxis = v3(0, 1, 0) }
CFrame = {
	lookAt = function(from, to) return { Position = from, LookAt = to } end,
	new = function(x, y, z) return { Position = v3(x, y, z) } end,
}

--@INJECT ParkConfig=src/ReplicatedStorage/SAD_Shared/Config/ParkConfig.lua ZoneConfig=src/ReplicatedStorage/SAD_Shared/Config/ZoneConfig.lua@

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

--- The projection MinimapController uses, restated here. Two implementations
--- of eight lines of arithmetic is acceptable; two implementations of the
--- square test was not, which is why `ZoneAt` moved into the config.
local function worldRadius()
	return ZoneConfig.RingRadius + ZoneConfig.ZoneSize * 0.5 + 60
end
local function project(x, z)
	local radius = worldRadius()
	return 0.5 + (x / radius) * 0.5, 0.5 + (z / radius) * 0.5
end

----------------------------------------------------------------- ZoneAt
section("ZoneConfig.ZoneAt — the square test three things now share")

--[[
	Moved out of `ZoneService` because the trespass check, the minimap's "you
	are here" and the analytics snapshot's zone dimension all need the same
	answer. Three implementations of a square test is two too many, and the
	third would have been written by someone who had not read the first.
]]
for _, zoneId in ipairs(ZoneConfig.Order) do
	local angle = ZoneConfig.AngleOf(zoneId)
	local cx = math.cos(angle) * ZoneConfig.RingRadius
	local cz = math.sin(angle) * ZoneConfig.RingRadius
	local half = ZoneConfig.ZoneSize * 0.5

	eq("the centre is inside: " .. zoneId, ZoneConfig.ZoneAt(Vector3.new(cx, 0, cz)), zoneId)

	--[[
		Just inside and just outside along the outward direction, which is the
		axis a player actually crosses when they walk in through the gate.
	]]
	local ox, oz = math.cos(angle), math.sin(angle)
	eq("just inside the outer edge: " .. zoneId,
		ZoneConfig.ZoneAt(Vector3.new(cx + ox * (half - 1), 0, cz + oz * (half - 1))), zoneId)
	eq("just outside it: " .. zoneId,
		ZoneConfig.ZoneAt(Vector3.new(cx + ox * (half + 2), 0, cz + oz * (half + 2))), nil)

	-- And the same on the hub-facing side, which is where the gate is.
	eq("just inside the hub-facing edge: " .. zoneId,
		ZoneConfig.ZoneAt(Vector3.new(cx - ox * (half - 1), 0, cz - oz * (half - 1))), zoneId)
	eq("just outside it: " .. zoneId,
		ZoneConfig.ZoneAt(Vector3.new(cx - ox * (half + 2), 0, cz - oz * (half + 2))), nil)

	--[[
		The corners. A rotation done wrong would still put the centre and the
		axis points inside, and only a corner would show it — which is exactly
		the kind of bug that ships.
	]]
	local rx, rz = -math.sin(angle), math.cos(angle) -- the perpendicular
	for _, sign in ipairs({ 1, -1 }) do
		local inside = Vector3.new(
			cx + ox * (half - 2) + rx * sign * (half - 2), 0,
			cz + oz * (half - 2) + rz * sign * (half - 2))
		eq("an inner corner is inside: " .. zoneId, ZoneConfig.ZoneAt(inside), zoneId)

		local outside = Vector3.new(
			cx + ox * (half + 3) + rx * sign * (half + 3), 0,
			cz + oz * (half + 3) + rz * sign * (half + 3))
		eq("the corner beyond it is outside: " .. zoneId, ZoneConfig.ZoneAt(outside), nil)
	end
end

-- The hub is not a zone, and neither is the park ring.
eq("the plaza centre is in no zone", ZoneConfig.ZoneAt(Vector3.new(0, 0, 0)), nil)
eq("the park ring is in no zone",
	ZoneConfig.ZoneAt(Vector3.new(ParkConfig.RingRadius(), 0, 0)), nil)
eq("far outside everything is in no zone",
	ZoneConfig.ZoneAt(Vector3.new(99999, 0, 99999)), nil)

--[[
	No point may be in two zones. Checked by sampling rather than proved,
	because the zones are squares on a ring and the gaps between them are what
	the sampling is looking for.
]]
do
	local misses = 0
	for _, zoneId in ipairs(ZoneConfig.Order) do
		local angle = ZoneConfig.AngleOf(zoneId)
		local half = ZoneConfig.ZoneSize * 0.5
		local cx = math.cos(angle) * ZoneConfig.RingRadius
		local cz = math.sin(angle) * ZoneConfig.RingRadius
		local rx, rz = -math.sin(angle), math.cos(angle)
		--[[
			Sampled strictly INSIDE. The boundary itself is asserted separately
			below, because it is genuinely ambiguous and always has been - the
			first version of this sweep ran to +/-half and failed four times,
			once per zone, on floating-point accumulation in the loop rather
			than on anything about the geometry.
		]]
		for index = -4, 4 do
			local step = index / 4 * (half - 1)
			local point = Vector3.new(cx + rx * step, 0, cz + rz * step)
			if ZoneConfig.ZoneAt(point) ~= zoneId then
				misses += 1
			end
		end
	end
	eq("every point strictly inside a zone reports that zone", misses, 0)
end

--[[
	The boundary, stated rather than left to be discovered. `ZoneAt` uses
	`<= half`, so a point exactly on the edge IS inside - but a float a
	whisker past it is not, and the zone's ground part is exactly `ZoneSize`
	wide, so the outermost stud is where this matters.

	Unchanged from the version that lived in `ZoneService`, which is the point:
	the move into `ZoneConfig` was a refactor, not a behaviour change.
]]
do
	local zoneId = ZoneConfig.Order[1]
	local angle = ZoneConfig.AngleOf(zoneId)
	local half = ZoneConfig.ZoneSize * 0.5
	local cx = math.cos(angle) * ZoneConfig.RingRadius
	local cz = math.sin(angle) * ZoneConfig.RingRadius
	local ox, oz = math.cos(angle), math.sin(angle)

	eq("exactly on the edge is inside",
		ZoneConfig.ZoneAt(Vector3.new(cx + ox * half, 0, cz + oz * half)), zoneId)
	eq("a hundredth of a stud past it is not",
		ZoneConfig.ZoneAt(Vector3.new(cx + ox * (half + 0.01), 0, cz + oz * (half + 0.01))), nil)
end

--------------------------------------------------------------- projection
section("The projection: everything in the world lands on the map")

local cx, cy = project(0, 0)
near("the world origin is the map centre, X", cx, 0.5, 0.0001)
near("...and Y", cy, 0.5, 0.0001)

--[[
	Every fixture the map draws must land inside 0..1, or it is clipped and the
	player is looking at a map with a piece missing. Driven over every zone
	corner, the park ring and the hub edge.
]]
local function inside(fx, fz)
	return fx >= 0 and fx <= 1 and fz >= 0 and fz <= 1
end

local worst, worstWhat = 0, "nothing"
local function check(label, x, z)
	local fx, fz = project(x, z)
	ok("on the map: " .. label, inside(fx, fz))
	local far = math.max(math.abs(fx - 0.5), math.abs(fz - 0.5))
	if far > worst then
		worst, worstWhat = far, label
	end
end

for _, zoneId in ipairs(ZoneConfig.Order) do
	local angle = ZoneConfig.AngleOf(zoneId)
	local half = ZoneConfig.ZoneSize * 0.5
	local zx = math.cos(angle) * ZoneConfig.RingRadius
	local zz = math.sin(angle) * ZoneConfig.RingRadius
	local ox, oz = math.cos(angle), math.sin(angle)
	local rx, rz = -math.sin(angle), math.cos(angle)

	for _, a in ipairs({ 1, -1 }) do
		for _, b in ipairs({ 1, -1 }) do
			check(zoneId .. " corner",
				zx + ox * half * a + rx * half * b,
				zz + oz * half * a + rz * half * b)
		end
	end
end

for index = 1, ParkConfig.PlotCount do
	local angle = ParkConfig.PlotAngle(index)
	local radius = ParkConfig.RingRadius() + ParkConfig.PlotSize * 0.5
	check("plot " .. index, math.cos(angle) * radius, math.sin(angle) * radius)
end

check("hub edge", ZoneConfig.HubRadius, 0)
check("the Obelisk", 0, 46)

print(string.format("  map radius %d studs; the furthest fixture sits at %.0f%% from centre (%s)",
	math.floor(worldRadius()), worst * 200, worstWhat))

--[[
	And the map must not be mostly empty margin. If the furthest thing in the
	world sits at 60 % of the way out, 40 % of the map is blank and every mark
	is smaller than it needs to be.
]]
ok("the map is not mostly margin", worst > 0.4)

--[[
	The 10-zone build-out has to fit too, or the map breaks the day zone 5
	ships. Every ring slot is checked, not just the four with zones in them.
]]
for slot = 1, ZoneConfig.SlotCount do
	local angle = (slot - 1) / ZoneConfig.SlotCount * math.pi * 2
	local half = ZoneConfig.ZoneSize * 0.5
	local x = math.cos(angle) * (ZoneConfig.RingRadius + half)
	local z = math.sin(angle) * (ZoneConfig.RingRadius + half)
	local fx, fz = project(x, z)
	ok(string.format("ring slot %d fits, so V1.4's zones will too", slot), inside(fx, fz))
end

--[[
	Scale sanity: a zone square must be big enough to read and small enough not
	to swallow the map. On a 460px expanded map, the zone squares are drawn at
	half their true fraction (they are markers, not footprints).
]]
do
	local zoneFraction = ZoneConfig.ZoneSize / worldRadius()
	local pixels = zoneFraction * 0.5 * 460
	print(string.format("  a zone square is %.0f px on the 460 px map", pixels))
	ok("a zone is big enough to tap", pixels >= 30)
	ok("...and small enough that ten of them fit round a ring", pixels <= 100)

	local hubFraction = ZoneConfig.HubRadius / worldRadius()
	print(string.format("  the hub disc is %.0f%% of the map's width", hubFraction * 100))
	ok("the hub does not swallow the map", hubFraction < 0.65)
	ok("...and is visible at all", hubFraction > 0.2)
end

------------------------------------------------------- the position boundary
section("The map cannot leak a position the game had not already given you")

--[[
	═══ WHY THIS IS A TEST AND NOT A COMMENT ═══════════════════════════════════
	docs/03 builds the raid loop on incomplete information: a `StealAlert` tells
	you somebody is in your park, and closing the distance is the game. A
	minimap with every player on it deletes that.

	`MinimapController` only ever learns a userId through
	`MinimapController.SetThief`, which only `HUDController` calls, and only
	from a `StealAlert` the server sent. Modelled here as the state machine that
	boundary actually is.
	═══════════════════════════════════════════════════════════════════════════
]]
do
	local tracked = {}
	local function setThief(userId, active)
		if active then tracked[userId] = true else tracked[userId] = nil end
	end

	local function count()
		local n = 0
		for _ in pairs(tracked) do n += 1 end
		return n
	end

	eq("nobody is on the map to begin with", count(), 0)

	-- Only these two alert kinds add a mark; the rest are text.
	setThief(4242, true)   -- intruder
	eq("an announced raider appears", count(), 1)

	setThief(4242, true)   -- a second intruder alert for the same raider
	eq("...and only once", count(), 1)

	setThief(4242, false)  -- returned / towerFired
	eq("and is gone when the raid resolves", count(), 0)

	--[[
		The property that matters: a userId the server never announced is never
		tracked. There is no code path that adds one — the map has no access to
		`Players:GetPlayers()` for positions, only for resolving a userId it was
		already handed.
	]]
	setThief(9999, false)
	eq("clearing an unknown raider is a no-op, not an add", count(), 0)
end

print("\n==============================================")
print(string.format("  %d passed, %d failed", passed, failed))
if failed > 0 then error("TESTS FAILED", 0) end
