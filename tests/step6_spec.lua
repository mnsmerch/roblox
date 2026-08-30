--[[
	Step 6 specification.

	Park geometry. Two classes of bug live here and neither throws:

	  * Tile indexing off by one, so a dinosaur renders half a tile from where
	    the server thinks it is.
	  * Fixtures overlapping or poking through a wall, which renders as
	    dinosaurs clipping into pedestals rather than as an error.

	Both are asserted arithmetically, so they cannot reach a Studio session.

	Run with:  ./tests/run.sh
]]

-- ── Roblox shims ────────────────────────────────────────────────────────────
-- ParkConfig builds Vector3 and Color3 values at load and does vector maths in
-- its grid functions, so Vector3 needs real arithmetic.

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
Vector3 = { new = v3, zero = v3(0, 0, 0) }
Color3 = { fromHex = function(hex) return { Hex = hex } end }

--@INJECT ParkConfig=src/ReplicatedStorage/SAD_Shared/Config/ParkConfig.lua GameConfig=src/ReplicatedStorage/SAD_Shared/Config/GameConfig.lua@

local passed, failed = 0, 0
local function eq(label, got, want)
	if got == want then passed = passed + 1
	else failed = failed + 1; print(string.format("  FAIL %-48s got %s want %s", label, tostring(got), tostring(want))) end
end
local function near(label, got, want, tol)
	if math.abs(got - want) <= tol then passed = passed + 1
	else failed = failed + 1; print(string.format("  FAIL %-48s got %.3f want ~%.3f", label, got, want)) end
end
local function ok(label, cond)
	if cond then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. label) end
end
local function section(name) print("\n== " .. name) end

local HALF = ParkConfig.PlotSize * 0.5

------------------------------------------------------------------ ring
section("Plot ring")

local radius = ParkConfig.RingRadius()
local chord = ParkConfig.NeighbourChord()
local required = ParkConfig.MinimumSeparation()

print(string.format("  %d plots, radius %.1f, neighbour chord %.1f, minimum separation %.1f (margin %.1f)",
	ParkConfig.PlotCount, radius, chord, required, chord - required))

ok("radius is derived, not tiny", radius > ParkConfig.PlotSize)
ok("neighbouring plots do not overlap", chord > required)
ok("there is real clearance between plots", chord - required > 5)

-- The radius must follow PlotCount, or raising it silently overlaps plots.
local baseCount = ParkConfig.PlotCount
ParkConfig.PlotCount = 48
local biggerRadius = ParkConfig.RingRadius()
ok("radius grows with plot count", biggerRadius > radius)
ok("48 plots still do not overlap", ParkConfig.NeighbourChord() > ParkConfig.MinimumSeparation())
ParkConfig.PlotCount = baseCount
--[[
	═══ ONE PLOT PER PLAYER ════════════════════════════════════════════════════
	The ring dropped from 24 plots to 6 after the first Studio session showed a
	horizon of tiny parks across an empty plain. Three numbers have to move
	together for that, and two of them are ours.
	═══════════════════════════════════════════════════════════════════════════
]]
eq("six plots, per the reference games", ParkConfig.PlotCount, 6)
eq("GameConfig agrees about the count", GameConfig.ParkPlotCount, ParkConfig.PlotCount)
ok("no player can join without a plot", GameConfig.MaxPlayers <= ParkConfig.PlotCount)
print(string.format("  %d plots, %d max players, ring radius %.0f",
	ParkConfig.PlotCount, GameConfig.MaxPlayers, ParkConfig.RingRadius()))

-- Against what it saved, not against a literal: the literal was 24 and went
-- stale the moment the ring dropped to six.
eq("plot count restored", ParkConfig.PlotCount, baseCount)

------------------------------------------------------------------ grid
section("Tile round trip")

local gridHalf = ParkConfig.GridHalfSpan()
local roundTripped = 0
for tileX = 1, ParkConfig.GridTiles do
	for tileZ = 1, ParkConfig.GridTiles do
		local offset = ParkConfig.TileToOffset(tileX, tileZ)
		local backX, backZ = ParkConfig.OffsetToTile(offset)
		if backX == tileX and backZ == tileZ then
			roundTripped = roundTripped + 1
		else
			failed = failed + 1
			print(string.format("  FAIL tile (%d,%d) round tripped to (%s,%s)",
				tileX, tileZ, tostring(backX), tostring(backZ)))
		end
	end
end
eq("all 64 tiles round trip", roundTripped, ParkConfig.GridTiles ^ 2)
passed = passed + roundTripped

-- Corner identities pin the orientation down, so a sign flip is caught.
local first = ParkConfig.TileToOffset(1, 1)
local last = ParkConfig.TileToOffset(ParkConfig.GridTiles, ParkConfig.GridTiles)
near("tile (1,1) sits at -X", first.X, ParkConfig.GridCenterOffset.X - gridHalf + ParkConfig.TileSize * 0.5, 0.001)
near("tile (8,8) sits at +X", last.X, ParkConfig.GridCenterOffset.X + gridHalf - ParkConfig.TileSize * 0.5, 0.001)
near("grid centre is the configured offset",
	(first.X + last.X) * 0.5, ParkConfig.GridCenterOffset.X, 0.001)
near("grid centre Z is the configured offset",
	(first.Z + last.Z) * 0.5, ParkConfig.GridCenterOffset.Z, 0.001)

-- Neighbouring tiles are exactly one tile apart.
near("adjacent tiles are TileSize apart",
	ParkConfig.TileToOffset(2, 1).X - ParkConfig.TileToOffset(1, 1).X, ParkConfig.TileSize, 0.001)

-- A point anywhere inside a tile resolves to that tile.
local edge = ParkConfig.TileSize * 0.49
for _, nudge in ipairs({ -edge, 0, edge }) do
	local probe = ParkConfig.TileToOffset(4, 4) + Vector3.new(nudge, 0, nudge)
	local x, z = ParkConfig.OffsetToTile(probe)
	eq(string.format("a point %+.1f inside tile (4,4) resolves there", nudge), x .. "," .. z, "4,4")
end

section("Off-grid rejection")

local outside = {
	{ Vector3.new(gridHalf * 3, 0, 0), "far +X" },
	{ Vector3.new(-gridHalf * 3, 0, 0), "far -X" },
	{ Vector3.new(0, 0, gridHalf * 3), "far +Z" },
	{ Vector3.new(0, 0, -gridHalf * 3), "far -Z" },
}
for _, case in ipairs(outside) do
	local x, z = ParkConfig.OffsetToTile(case[1])
	ok("off-grid returns nil: " .. case[2], x == nil and z == nil)
end

------------------------------------------------------------------ footprints
section("Footprints")

eq("1x1 covers one tile", #ParkConfig.FootprintTiles(1, 1, "1x1"), 1)
eq("2x2 covers four tiles", #ParkConfig.FootprintTiles(1, 1, "2x2"), 4)
eq("3x3 covers nine tiles", #ParkConfig.FootprintTiles(1, 1, "3x3"), 9)
eq("4x4 covers sixteen tiles", #ParkConfig.FootprintTiles(1, 1, "4x4"), 16)

ok("1x1 fits in the far corner", ParkConfig.FootprintTiles(8, 8, "1x1") ~= nil)
ok("2x2 does not fit in the far corner", ParkConfig.FootprintTiles(8, 8, "2x2") == nil)
ok("4x4 fits at (5,5)", ParkConfig.FootprintTiles(5, 5, "4x4") ~= nil)
ok("4x4 does not fit at (6,6)", ParkConfig.FootprintTiles(6, 6, "4x4") == nil)
ok("4x4 fits at (1,1)", ParkConfig.FootprintTiles(1, 1, "4x4") ~= nil)
ok("negative anchors are rejected", ParkConfig.FootprintTiles(0, 1, "1x1") == nil)

-- Every tile a footprint claims must itself be on the grid.
for _, size in ipairs({ "1x1", "2x2", "3x3", "4x4" }) do
	local span = tonumber(string.sub(size, 1, 1))
	local placements, tilesOnGrid = 0, 0
	for x = 1, ParkConfig.GridTiles do
		for z = 1, ParkConfig.GridTiles do
			local tiles = ParkConfig.FootprintTiles(x, z, size)
			if tiles then
				placements = placements + 1
				for _, tile in ipairs(tiles) do
					if tile[1] >= 1 and tile[1] <= ParkConfig.GridTiles
						and tile[2] >= 1 and tile[2] <= ParkConfig.GridTiles then
						tilesOnGrid = tilesOnGrid + 1
					end
				end
			end
		end
	end
	local expectedPlacements = (ParkConfig.GridTiles - span + 1) ^ 2
	eq("valid placements for " .. size, placements, expectedPlacements)
	eq("every claimed tile is on the grid for " .. size, tilesOnGrid, placements * span * span)
end

-- A 1x1 sits on its tile; larger footprints sit in the middle of their block.
local single = ParkConfig.FootprintCenterOffset(3, 3, "1x1")
local tile = ParkConfig.TileToOffset(3, 3)
ok("1x1 centre is its tile centre", single.X == tile.X and single.Z == tile.Z)

local quad = ParkConfig.FootprintCenterOffset(1, 1, "2x2")
near("2x2 centre sits between its tiles",
	quad.X, (ParkConfig.TileToOffset(1, 1).X + ParkConfig.TileToOffset(2, 2).X) * 0.5, 0.001)

local big = ParkConfig.FootprintCenterOffset(1, 1, "4x4")
near("4x4 centre sits between its tiles",
	big.X, (ParkConfig.TileToOffset(1, 1).X + ParkConfig.TileToOffset(4, 4).X) * 0.5, 0.001)

------------------------------------------------------------------ layout
section("Plot layout: everything fits, nothing overlaps")

--[[
	Depth budget along local Z, gate (+60) to back wall (-60). Each row is
	{ label, nearEdge, farEdge } with nearEdge closer to the gate.
]]
local rows = {
	{ "spawn pad", ParkConfig.SpawnOffset.Z + 4, ParkConfig.SpawnOffset.Z - 4 },
	{ "incubator row", ParkConfig.IncubatorRowZ + ParkConfig.IncubatorSize * 0.5,
	   ParkConfig.IncubatorRowZ - ParkConfig.IncubatorSize * 0.5 },
	{ "enclosure grid", ParkConfig.GridCenterOffset.Z + gridHalf,
	   ParkConfig.GridCenterOffset.Z - gridHalf },
	{ "vault pedestals", ParkConfig.VaultRowZ + ParkConfig.VaultSize * 0.5,
	   ParkConfig.VaultRowZ - ParkConfig.VaultSize * 0.5 },
}

print(string.format("  %-18s %8s %8s", "row", "front", "back"))
for _, row in ipairs(rows) do
	print(string.format("  %-18s %+8.1f %+8.1f", row[1], row[2], row[3]))
	ok(row[1] .. " is inside the front wall", row[2] <= HALF)
	ok(row[1] .. " is inside the back wall", row[3] >= -HALF)
end

for index = 1, #rows - 1 do
	local nearer, further = rows[index], rows[index + 1]
	ok(string.format("%s does not overlap %s", nearer[1], further[1]), nearer[3] >= further[2])
end

section("Plot layout: widths")

local incubatorHalfWidth = (ParkConfig.IncubatorCount - 1) * ParkConfig.IncubatorSpacing * 0.5
	+ ParkConfig.IncubatorSize * 0.5
ok("incubator row fits between the side walls", incubatorHalfWidth <= HALF)

local vaultHalfWidth = (ParkConfig.VaultPedestalCount - 1) * ParkConfig.VaultSpacing * 0.5
	+ ParkConfig.VaultSize * 0.5
ok("vault row fits between the side walls", vaultHalfWidth <= HALF)

ok("incubator pads do not overlap each other", ParkConfig.IncubatorSpacing > ParkConfig.IncubatorSize)
ok("vault pedestals do not overlap each other", ParkConfig.VaultSpacing > ParkConfig.VaultSize)

ok("grid fits between the side walls", math.abs(ParkConfig.GridCenterOffset.X) + gridHalf <= HALF)

local totemHalf = ParkConfig.TotemSize * 0.5
ok("totem is inside the plot",
	math.abs(ParkConfig.TotemPosition.X) + totemHalf <= HALF
	and math.abs(ParkConfig.TotemPosition.Z) + totemHalf <= HALF)
ok("totem clears the incubator row",
	math.abs(ParkConfig.TotemPosition.X) - totemHalf > incubatorHalfWidth)

ok("the gate is narrower than the wall it sits in", ParkConfig.GateWidth < ParkConfig.PlotSize)
ok("the shield dome covers the plot", ParkConfig.SafeDomeRadius >= HALF)

------------------------------------------------------------------ tiers
section("Visual tiers")

eq("a new park is a dirt lot", ParkConfig.VisualTierFor(0).Id, "dirt")
eq("50k reaches wooden", ParkConfig.VisualTierFor(50000).Id, "wooden")
eq("just under 50k is still dirt", ParkConfig.VisualTierFor(49999).Id, "dirt")
eq("2M reaches stone", ParkConfig.VisualTierFor(2000000).Id, "stone")
eq("a trillion reaches titan", ParkConfig.VisualTierFor(1e12).Id, "titan")
eq("beyond the top tier stays titan", ParkConfig.VisualTierFor(1e30).Id, "titan")

local previousValue = -1
for _, tier in ipairs(ParkConfig.VisualTiers) do
	ok("tier thresholds ascend: " .. tier.Id, tier.MinValue > previousValue)
	previousValue = tier.MinValue
	ok("tier has colours: " .. tier.Id, tier.Base ~= nil and tier.Wall ~= nil)
end

print(string.format("\n%s\n  %d passed, %d failed\n", string.rep("=", 46), passed, failed))
if failed > 0 then error("TESTS FAILED") end
