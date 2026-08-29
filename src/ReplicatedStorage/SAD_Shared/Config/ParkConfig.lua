--!strict
--[[
	ParkConfig
	ReplicatedStorage/SAD_Shared/Config/ParkConfig  (ModuleScript)

	Park plot geometry and layout. Mirrors docs/02-zones-and-map.md §3.

	Shared rather than server-only because the client needs the same numbers to
	draw a placement preview (Step 12) that lands where the server will actually
	put the dinosaur. Two copies of a grid origin is two grids.

	═══ THE GRID IS MATHEMATICAL ════════════════════════════════════════════
	docs/13 called for 64 tile PARTS per plot. That is 1,536 anchored parts
	across 24 plots to express what is a coordinate transform, and it is the
	kind of thing that quietly costs a mobile player ten frames a second.

	One textured GridSurface part shows the grid; TileToOffset/OffsetToTile do
	the maths. Placement preview spawns a single highlight part on demand.
	═════════════════════════════════════════════════════════════════════════

	Depends on: nothing.
]]

local ParkConfig = {}

ParkConfig.PlotCount = 24

-- ── Plot footprint ──────────────────────────────────────────────────────────

ParkConfig.PlotSize = 120 -- studs, square
ParkConfig.PlotGap = 30 -- clearance between neighbouring plots
ParkConfig.BaseThickness = 2

--[[
	Ring radius is DERIVED, not chosen. 24 plots each 120 wide with 20 studs of
	clearance need 3,360 studs of circumference, so the ring has to sit at
	3360 / 2pi. Picking a radius by hand is how plots end up overlapping the
	moment somebody changes PlotCount.
]]
function ParkConfig.RingRadius(): number
	local circumference = ParkConfig.PlotCount * (ParkConfig.PlotSize + ParkConfig.PlotGap)
	return circumference / (2 * math.pi)
end

--- Plots face INWARD so that standing in the plaza you can see every park's
--- skyline at once. That is the status engine from docs/02 §1.1.
ParkConfig.FaceInward = true

-- ── Enclosure grid ──────────────────────────────────────────────────────────

ParkConfig.GridTiles = 8 -- 8x8
ParkConfig.TileSize = 10 -- studs, so the grid spans 80 of the plot's 120

--[[
	The plot's 120 studs of depth, front (gate, +Z) to back (-Z):

		+60 .. +50   gate, spawn pad, collection totem
		+50 .. +42   incubator row - the first thing a visitor sees
		+42 .. +38   clearance
		+38 .. -42   the 8x8 enclosure grid
		-42 .. -49   clearance
		-49 .. -60   vault pedestals, against the back wall

	tests/step6_spec.lua asserts every one of those fits and that none of them
	overlap. An earlier pass had a 96-stud grid poking two studs through the
	back wall and the vault row sitting on top of it, which renders as
	dinosaurs clipping into pedestals rather than as an error.
]]
ParkConfig.GridCenterOffset = Vector3.new(0, 0, -2)

-- ── Fixtures ────────────────────────────────────────────────────────────────

ParkConfig.IncubatorCount = 8 -- maximum; upgrades unlock them
ParkConfig.IncubatorSize = 8
ParkConfig.IncubatorSpacing = 11
ParkConfig.IncubatorRowZ = 46

ParkConfig.VaultPedestalCount = 5
ParkConfig.VaultSize = 9
ParkConfig.VaultSpacing = 14
ParkConfig.VaultRowZ = -54 -- against the back wall, raised, obviously precious

ParkConfig.TotemSize = 6
ParkConfig.TotemPosition = Vector3.new(-48, 0, 52)
ParkConfig.SpawnOffset = Vector3.new(0, 4, 54) -- inside the gate, facing in

ParkConfig.WallHeight = 10
ParkConfig.WallThickness = 2
ParkConfig.GateWidth = 34
ParkConfig.SafeDomeRadius = 88

-- ── Colours ─────────────────────────────────────────────────────────────────

ParkConfig.Color = {
	Base = Color3.fromHex("6B5B3E"),
	Grid = Color3.fromHex("7C6B48"),
	Wall = Color3.fromHex("4A3F2A"),
	GateArch = Color3.fromHex("FFB020"),
	Totem = Color3.fromHex("C48010"),
	Incubator = Color3.fromHex("3FA9F5"),
	Vault = Color3.fromHex("FFD24A"),
	Dome = Color3.fromHex("3FA9F5"),
}

--[[
	Park visual tiers, applied automatically by total park value (docs/02 §3).

	Free, visible progression: a returning player's park looks different without
	buying anything, which is a strong D7 hook. Only Tier 1 renders in V1; the
	retextures land with the decoration pass in V1.4.
]]
ParkConfig.VisualTiers = {
	{ Id = "dirt", DisplayName = "Dirt Lot", MinValue = 0, Base = "6B5B3E", Wall = "4A3F2A" },
	{ Id = "wooden", DisplayName = "Wooden Ranch", MinValue = 50000, Base = "7A6340", Wall = "5C4A30" },
	{ Id = "stone", DisplayName = "Stone Preserve", MinValue = 2000000, Base = "6E6E68", Wall = "55554F" },
	{ Id = "steel", DisplayName = "Steel Facility", MinValue = 100000000, Base = "8A8F96", Wall = "5F666E" },
	{ Id = "amber", DisplayName = "Amber Kingdom", MinValue = 10000000000, Base = "C89A3C", Wall = "8A6720" },
	{ Id = "titan", DisplayName = "Titan Sanctuary", MinValue = 1000000000000, Base = "3A2E4A", Wall = "241C2E" },
}

-- ── Grid maths ──────────────────────────────────────────────────────────────

--[[
	Tile (1,1) is the back-left corner looking in from the gate; (8,8) is
	front-right. Returns an offset in PLOT-LOCAL space - callers combine it with
	the plot's CFrame, so a rotated plot needs no special handling.
]]
function ParkConfig.TileToOffset(tileX: number, tileZ: number): Vector3
	local span = (ParkConfig.GridTiles - 1) * ParkConfig.TileSize * 0.5
	return ParkConfig.GridCenterOffset
		+ Vector3.new((tileX - 1) * ParkConfig.TileSize - span, 0, (tileZ - 1) * ParkConfig.TileSize - span)
end

--- Inverse of TileToOffset. Returns nil when the offset is off the grid.
function ParkConfig.OffsetToTile(offset: Vector3): (number?, number?)
	local span = (ParkConfig.GridTiles - 1) * ParkConfig.TileSize * 0.5
	local local_ = offset - ParkConfig.GridCenterOffset

	local tileX = math.floor((local_.X + span) / ParkConfig.TileSize + 0.5) + 1
	local tileZ = math.floor((local_.Z + span) / ParkConfig.TileSize + 0.5) + 1

	if tileX < 1 or tileX > ParkConfig.GridTiles or tileZ < 1 or tileZ > ParkConfig.GridTiles then
		return nil, nil
	end
	return tileX, tileZ
end

--- Tiles a footprint occupies, anchored at its lower-left tile.
--- Returns nil if any part of it would fall off the grid.
function ParkConfig.FootprintTiles(tileX: number, tileZ: number, size: string): { { number } }?
	local span = tonumber(string.sub(size, 1, 1)) or 1

	if tileX < 1 or tileZ < 1
		or tileX + span - 1 > ParkConfig.GridTiles
		or tileZ + span - 1 > ParkConfig.GridTiles then
		return nil
	end

	local tiles = {}
	for x = tileX, tileX + span - 1 do
		for z = tileZ, tileZ + span - 1 do
			table.insert(tiles, { x, z })
		end
	end
	return tiles
end

--- Centre of a footprint, so a 4x4 dinosaur sits in the middle of its block
--- rather than on its corner tile.
function ParkConfig.FootprintCenterOffset(tileX: number, tileZ: number, size: string): Vector3
	local span = tonumber(string.sub(size, 1, 1)) or 1
	local corner = ParkConfig.TileToOffset(tileX, tileZ)
	local shift = (span - 1) * ParkConfig.TileSize * 0.5
	return corner + Vector3.new(shift, 0, shift)
end

--- Half-depth a fixture row occupies, for the layout assertions in the spec.
function ParkConfig.GridHalfSpan(): number
	return ParkConfig.GridTiles * ParkConfig.TileSize * 0.5
end

--[[
	Centre-to-centre distance between neighbouring plots on the ring.

	Plots are squares rotated relative to each other by one ring step, so
	non-overlap needs this chord to exceed the projection of both footprints
	onto the tangent: half + half * (cos(step) + sin(step)).
]]
function ParkConfig.NeighbourChord(): number
	return 2 * ParkConfig.RingRadius() * math.sin(math.pi / ParkConfig.PlotCount)
end

function ParkConfig.MinimumSeparation(): number
	local step = math.pi * 2 / ParkConfig.PlotCount
	local half = ParkConfig.PlotSize * 0.5
	return half + half * (math.cos(step) + math.sin(step))
end

function ParkConfig.VisualTierFor(parkValue: number)
	local current = ParkConfig.VisualTiers[1]
	for _, tier in ParkConfig.VisualTiers do
		if parkValue >= tier.MinValue then
			current = tier
		end
	end
	return current
end

return ParkConfig
