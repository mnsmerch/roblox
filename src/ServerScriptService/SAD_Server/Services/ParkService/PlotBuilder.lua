--!nonstrict
--[[
	PlotBuilder
	.../Services/ParkService/PlotBuilder  (ModuleScript)

	Constructs one park plot out of parts. Called 24 times at boot.

	Generated rather than placed by hand because 24 identical plots is exactly
	what you do not want in a .rbxl: it cannot be diffed, a fix has to be
	applied 24 times, and changing the ring radius means moving everything.
	Here, PlotCount is a number in ParkConfig.

	Roughly 27 parts per plot, so ~650 for the whole ring - cheap enough that
	StreamingEnabled has easy work to do. The 8x8 enclosure grid is a texture
	on one part plus maths in ParkConfig, not 64 parts.

	Depends on: ParkConfig.
	Owned by: ParkService.
]]

local ParkConfig = require(game:GetService("ReplicatedStorage")
	:WaitForChild("SAD_Shared").Config.ParkConfig)

local PlotBuilder = {}

local function part(props): BasePart
	local instance = Instance.new(props.Class or "Part")
	instance.Anchored = true
	instance.CanCollide = props.CanCollide ~= false
	instance.CastShadow = props.CastShadow == true
	instance.Material = props.Material or Enum.Material.SmoothPlastic
	instance.TopSurface = Enum.SurfaceType.Smooth
	instance.BottomSurface = Enum.SurfaceType.Smooth

	instance.Name = props.Name
	instance.Size = props.Size
	instance.CFrame = props.CFrame
	instance.Color = props.Color or Color3.fromHex("FFFFFF")

	if props.Transparency then
		instance.Transparency = props.Transparency
	end
	if props.Shape then
		instance.Shape = props.Shape
	end
	if props.Parent then
		instance.Parent = props.Parent
	end
	return instance
end

--[[
	Plot-local origin CFrame for `index`, without building anything.
	Build() and ParkService's position tests both go through here, so the
	geometry and the maths are the same transform by construction.

	Orientation is the easy thing to get backwards. CFrame.LookVector is the
	CFrame's local -Z, so lookAt(position, hubCentre) would make local +Z point
	AWAY from the hub - and every gate, incubator row and spawn pad in
	ParkConfig sits on +Z. Aiming the LookVector OUTWARD instead puts local +Z
	toward the hub, which is where a park's entrance belongs: visible from the
	plaza, with the incubator row the first thing a visitor sees.
]]
function PlotBuilder.OriginOf(index: number): CFrame
	local angle = (index - 1) / ParkConfig.PlotCount * math.pi * 2
	local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local position = outward * ParkConfig.RingRadius()

	return CFrame.lookAt(position, position + outward, Vector3.yAxis)
end

--[[
	Builds plot `index` (1-based) and returns the Model, unparented.

	Plots sit on a ring and face INWARD, so every park's skyline is visible from
	the plaza (docs/02 §1.1). Everything below is expressed in plot-LOCAL space
	and multiplied through `origin`, which means the rotation is handled once
	rather than by every fixture.
]]
function PlotBuilder.Build(index: number): Model
	local plotCount = ParkConfig.PlotCount
	local radius = ParkConfig.RingRadius()
	local size = ParkConfig.PlotSize
	local half = size * 0.5

	local angle = (index - 1) / plotCount * math.pi * 2

	-- Shared with OriginOf, so the geometry and the position maths cannot drift.
	local origin = PlotBuilder.OriginOf(index)

	local model = Instance.new("Model")
	model.Name = string.format("Plot%02d", index)

	local base = part({
		Name = "Base",
		Size = Vector3.new(size, ParkConfig.BaseThickness, size),
		CFrame = origin * CFrame.new(0, -ParkConfig.BaseThickness * 0.5, 0),
		Color = Color3.fromHex(ParkConfig.VisualTiers[1].Base),
		Material = Enum.Material.Ground,
		Parent = model,
	})
	model.PrimaryPart = base

	-- One part for the whole enclosure grid. A Texture on the top face draws
	-- the tile lines; ParkConfig does the coordinate maths.
	local gridSpan = ParkConfig.GridTiles * ParkConfig.TileSize
	local grid = part({
		Name = "GridSurface",
		Size = Vector3.new(gridSpan, 0.2, gridSpan),
		CFrame = origin * CFrame.new(ParkConfig.GridCenterOffset + Vector3.new(0, 0.1, 0)),
		Color = ParkConfig.Color.Grid,
		CanCollide = false,
		Parent = model,
	})

	local texture = Instance.new("Texture")
	texture.Name = "GridLines"
	texture.Face = Enum.NormalId.Top
	texture.StudsPerTileU = ParkConfig.TileSize
	texture.StudsPerTileV = ParkConfig.TileSize
	texture.Transparency = 0.65
	-- Placeholder studs texture; the art pass swaps in a proper grid decal.
	texture.Texture = "rbxasset://textures/studs.png"
	texture.Parent = grid

	-- Perimeter walls, with a gap at the gate.
	local wallY = ParkConfig.WallHeight * 0.5
	local sideLength = size
	local gateGap = ParkConfig.GateWidth
	local frontRun = (size - gateGap) * 0.5

	local walls = {
		{ Name = "WallBack", Size = Vector3.new(size, ParkConfig.WallHeight, ParkConfig.WallThickness),
		  Offset = Vector3.new(0, wallY, -half) },
		{ Name = "WallLeft", Size = Vector3.new(ParkConfig.WallThickness, ParkConfig.WallHeight, sideLength),
		  Offset = Vector3.new(-half, wallY, 0) },
		{ Name = "WallRight", Size = Vector3.new(ParkConfig.WallThickness, ParkConfig.WallHeight, sideLength),
		  Offset = Vector3.new(half, wallY, 0) },
		{ Name = "WallFrontLeft", Size = Vector3.new(frontRun, ParkConfig.WallHeight, ParkConfig.WallThickness),
		  Offset = Vector3.new(-(gateGap + frontRun) * 0.5, wallY, half) },
		{ Name = "WallFrontRight", Size = Vector3.new(frontRun, ParkConfig.WallHeight, ParkConfig.WallThickness),
		  Offset = Vector3.new((gateGap + frontRun) * 0.5, wallY, half) },
	}
	for _, wall in walls do
		part({
			Name = wall.Name,
			Size = wall.Size,
			CFrame = origin * CFrame.new(wall.Offset),
			Color = Color3.fromHex(ParkConfig.VisualTiers[1].Wall),
			Parent = model,
		})
	end

	-- Gate: two posts and a lintel, in the owner's accent colour.
	local gate = Instance.new("Model")
	gate.Name = "Gate"
	local postHeight = ParkConfig.WallHeight + 6
	for _, side in { -1, 1 } do
		part({
			Name = "GatePost",
			Size = Vector3.new(3, postHeight, 3),
			CFrame = origin * CFrame.new(side * gateGap * 0.5, postHeight * 0.5, half),
			Color = ParkConfig.Color.GateArch,
			Parent = gate,
		})
	end
	local lintel = part({
		Name = "GateLintel",
		Size = Vector3.new(gateGap + 6, 3, 3),
		CFrame = origin * CFrame.new(0, postHeight + 1.5, half),
		Color = ParkConfig.Color.GateArch,
		Parent = gate,
	})
	--[[
		The defence board, docs/06 §5's "Park Gate" third board. Beside the
		gate rather than in the hub, because what it sells is about THIS park:
		a player deciding whether to buy a Fence is standing at the thing a
		thief walks through.

		Same contract as the Bone Market stalls - a `ShopBoard` attribute the
		client reads off the prompt. No remote: opening a menu is not a server
		concern, and the purchase remote validates the board anyway.
	]]
	local defenceBoard = part({
		Name = "DefenceBoard",
		Size = Vector3.new(8, 7, 1.5),
		-- Mounted on the OUTER face of the front-right wall, so it faces a
		-- player walking up from the hub and cannot intrude on the enclosure
		-- grid inside. The wall spans z = half +/- WallThickness/2, so
		-- half + 1 + depth/2 sits flush against it.
		CFrame = origin * CFrame.new(gateGap * 0.5 + 7, 4,
			half + ParkConfig.WallThickness * 0.5 + 0.75),
		Color = ParkConfig.Color.GateArch,
		Material = Enum.Material.Metal,
		Parent = gate,
	})
	defenceBoard:SetAttribute("ShopBoard", "defence")

	local defencePrompt = Instance.new("ProximityPrompt")
	defencePrompt.ActionText = "Open"
	defencePrompt.ObjectText = "PARK GATE  ·  DEFENCE"
	defencePrompt.HoldDuration = 0
	defencePrompt.MaxActivationDistance = 12
	defencePrompt.RequiresLineOfSight = false
	defencePrompt:SetAttribute("ShopBoard", "defence")
	defencePrompt.Parent = defenceBoard

	gate.PrimaryPart = lintel
	gate.Parent = model

	-- The safe-zone threshold. Invisible and non-colliding: crossing is
	-- detected server-side from position, never from a client touch event.
	part({
		Name = "GateThreshold",
		Size = Vector3.new(gateGap, ParkConfig.WallHeight, 4),
		CFrame = origin * CFrame.new(0, ParkConfig.WallHeight * 0.5, half),
		Transparency = 1,
		CanCollide = false,
		Parent = model,
	})

	-- Shield dome. Hidden until a shield is actually up.
	part({
		Name = "SafeDome",
		Class = "Part",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(ParkConfig.SafeDomeRadius * 2, ParkConfig.SafeDomeRadius * 2, ParkConfig.SafeDomeRadius * 2),
		CFrame = origin * CFrame.new(0, 0, 0),
		Color = ParkConfig.Color.Dome,
		Transparency = 1,
		CanCollide = false,
		Material = Enum.Material.ForceField,
		Parent = model,
	})

	-- Incubator row, along the gate wall.
	local incubators = Instance.new("Folder")
	incubators.Name = "Incubators"
	local rowSpan = (ParkConfig.IncubatorCount - 1) * ParkConfig.IncubatorSpacing * 0.5
	for slot = 1, ParkConfig.IncubatorCount do
		local pad = part({
			Name = "Incubator" .. slot,
			Size = Vector3.new(ParkConfig.IncubatorSize, 1.5, ParkConfig.IncubatorSize),
			CFrame = origin * CFrame.new(
				(slot - 1) * ParkConfig.IncubatorSpacing - rowSpan,
				0.75,
				ParkConfig.IncubatorRowZ
			),
			Color = ParkConfig.Color.Incubator,
			Material = Enum.Material.Neon,
			Transparency = 0.35,
			Parent = incubators,
		})
		pad:SetAttribute("SlotIndex", slot)
	end
	incubators.Parent = model

	-- Vault pedestals: raised, caged, and unmistakably precious.
	local vaults = Instance.new("Folder")
	vaults.Name = "VaultPedestals"
	local vaultSpan = (ParkConfig.VaultPedestalCount - 1) * ParkConfig.VaultSpacing * 0.5
	for slot = 1, ParkConfig.VaultPedestalCount do
		local pedestal = part({
			Name = "Vault" .. slot,
			Size = Vector3.new(ParkConfig.VaultSize, 4, ParkConfig.VaultSize),
			CFrame = origin * CFrame.new(
				(slot - 1) * ParkConfig.VaultSpacing - vaultSpan,
				2,
				ParkConfig.VaultRowZ
			),
			Color = ParkConfig.Color.Vault,
			Material = Enum.Material.Metal,
			Parent = vaults,
		})
		pedestal:SetAttribute("SlotIndex", slot)
		-- Only the first is unlocked at rebirth 0 (docs/03 §4.3).
		pedestal.Transparency = if slot == 1 then 0 else 0.7
	end
	vaults.Parent = model

	-- Collection totem.
	local totem = part({
		Name = "CollectionTotem",
		Size = Vector3.new(ParkConfig.TotemSize, 12, ParkConfig.TotemSize),
		CFrame = origin * CFrame.new(ParkConfig.TotemPosition + Vector3.new(0, 6, 0)),
		Color = ParkConfig.Color.Totem,
		Material = Enum.Material.WoodPlanks,
		Parent = model,
	})

	-- Owner sign above the gate.
	local sign = Instance.new("BillboardGui")
	sign.Name = "OwnerSign"
	sign.Size = UDim2.fromScale(14, 3)
	sign.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)
	sign.AlwaysOnTop = false
	sign.MaxDistance = 400
	sign.Adornee = lintel

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromHex("F5F0E4")
	label.TextStrokeTransparency = 0.4
	label.Text = "Empty Plot"
	label.Parent = sign
	sign.Parent = lintel

	-- Spawn point, just inside the gate facing in, so a player materialises
	-- looking at their own park (docs/00 FTUE beat 1).
	local spawnPad = part({
		Name = "SpawnPad",
		Size = Vector3.new(8, 0.4, 8),
		CFrame = origin * CFrame.new(ParkConfig.SpawnOffset - Vector3.new(0, 3.8, 0)),
		Color = Color3.fromHex("5FD35F"),
		Transparency = 0.5,
		CanCollide = false,
		Parent = model,
	})

	model:SetAttribute("PlotIndex", index)
	model:SetAttribute("OwnerUserId", 0)
	model:SetAttribute("Angle", angle)

	return model
end

return PlotBuilder
