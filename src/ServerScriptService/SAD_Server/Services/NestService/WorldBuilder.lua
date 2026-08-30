--!nonstrict
--[[
	WorldBuilder
	.../Services/NestService/WorldBuilder  (ModuleScript)

	Generates the hub plaza and the four V1 zones as a blockout: coloured
	ground, entrance gates, shrines, landmarks and roads.

	This is scaffolding, not art. Everything here is a plain coloured part with
	a stable name, so an artist can replace a zone's model wholesale later
	without a single logic change - the only thing NestService actually needs
	from the world is parts tagged SAD_NestAnchor.

	That tag is the seam. Anchors are generated here today; hand-placed anchors
	in a Studio-built zone work identically tomorrow, because NestService reads
	them through CollectionService and never asks where they came from.

	Depends on: ZoneConfig, ParkConfig.
	Owned by: NestService.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local LeaderboardConfig = require(Shared.Config.LeaderboardConfig)
local ParkConfig = require(Shared.Config.ParkConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)

local WorldBuilder = {}

WorldBuilder.NEST_ANCHOR_TAG = "SAD_NestAnchor"

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

--- Slightly darker or lighter than a base colour, for landmarks and trim.
local function shade(color: Color3, amount: number): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, math.clamp(s + amount * 0.2, 0, 1), math.clamp(v + amount, 0, 1))
end

--[[
	The central plaza. A disc reaching the park ring's inner edge, so a player
	can walk from any park to any zone without falling off the world.

	Step 7 scope is a floor to stand on. The Bone Market, Fossil Lab, Colosseum
	and Event Arena from docs/02 §1.1 arrive with the systems that need them.
]]
--[[
	The Bone Market: the two upgrade boards from docs/06 §5, standing in the
	plaza where a player walking in from any park passes them.

	Each board carries a `ShopBoard` attribute. The client's ShopController
	reads it off the prompt and opens that tab - opening a menu is not
	something the server needs to be told about, so there is no remote here.
]]
local BONE_MARKET_BOARDS = {
	{ Board = "park", Label = "BONE MARKET  ·  PARK", Angle = 200 },
	{ Board = "explorer", Label = "BONE MARKET  ·  EXPLORER", Angle = 250 },
}

--- Distance from the plaza centre. Far enough not to crowd the monument, well
--- inside HubRadius so a board is never floating over the edge. Came in from
--- 90 with the plaza, to keep its 60-stud clearance from the statue plinths.
local BONE_MARKET_RADIUS = 60

local function buildBoneMarket(hub: Model)
	local market = Instance.new("Model")
	market.Name = "BoneMarket"

	for _, board in BONE_MARKET_BOARDS do
		local angle = math.rad(board.Angle)
		local position = Vector3.new(math.cos(angle), 0, math.sin(angle)) * BONE_MARKET_RADIUS

		-- Local +Z faces the plaza centre, matching the convention PlotBuilder
		-- established: LookVector is the CFrame's local -Z, so aiming the
		-- LookVector outward puts the readable face inward.
		local facing = CFrame.lookAt(position + Vector3.new(0, 6, 0), position * 2)

		local stall = part({
			Name = board.Board,
			Size = Vector3.new(16, 12, 3),
			CFrame = facing,
			Color = Color3.fromHex("6B4E2E"),
			Material = Enum.Material.WoodPlanks,
			Parent = market,
		})
		stall:SetAttribute("ShopBoard", board.Board)

		part({
			Name = "Sign",
			Size = Vector3.new(14, 4, 0.6),
			CFrame = facing * CFrame.new(0, 4, -1.8),
			Color = Color3.fromHex("FFB020"),
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = market,
		})

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Open"
		prompt.ObjectText = board.Label
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 14
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("ShopBoard", board.Board)
		prompt.Parent = stall
	end

	market.Parent = hub
	return market
end

--[[
	The Leaderboard Colosseum, "west" per docs/02 §1.1: one pillar per SHIPPED
	board, and three golden statue plinths.

	Per shipped board, not per board docs/02 names. Eight pillars for four
	boards would be four blank slabs a player walks up to and learns nothing
	from - the same reason the Index counts what exists rather than what is
	planned. The ring geometry is derived from the count, so V1.4's four extra
	boards space themselves.

	The pillars carry no text. `LeaderboardController` attaches the SurfaceGui
	and draws the cached rows, for the reason WeatherController owns Lighting:
	a board is presentation, the numbers behind it are server truth, and a
	client that fails to draw one has broken its own screen rather than
	everyone's world.
]]
--[[
	Placement. The plaza reaches 226 and the park ring's inner edge is at 226,
	so everything here has to sit inside that; the Bone Market is at 60, so the
	Colosseum has to sit outside THAT. 160 and 130 leave a clear walk between
	the two and a clear walk out to the parks.

	Was 250 and 195, sized for the 520-radius plaza a 24-plot ring produced.
	Six plots brought the plaza to 226 and the Colosseum came in with it -
	caught by step22_spec, which asserts the clearance rather than trusting it.
]]
local COLOSSEUM_ANGLE = 0 -- degrees offset; +180 below puts it opposite the market
local COLOSSEUM_RADIUS = 160
local COLOSSEUM_ARC = 70 -- degrees the pillars are spread across
local STATUE_RADIUS = 130

local function buildColosseum(hub: Model)
	local colosseum = Instance.new("Model")
	colosseum.Name = "Colosseum"

	local boardCount = LeaderboardConfig.Count()

	--[[
		A single board would sit at the arc's start rather than facing the
		plaza, so the spread is computed from the gaps between pillars, not
		from the pillars themselves.
	]]
	local gaps = math.max(boardCount - 1, 1)

	for index, boardId in LeaderboardConfig.Order do
		local entry = LeaderboardConfig.Get(boardId)
		local spread = if boardCount == 1 then 0 else (index - 1) / gaps - 0.5
		local angle = math.rad(COLOSSEUM_ANGLE + spread * COLOSSEUM_ARC + 180)
		local position = Vector3.new(math.cos(angle), 0, math.sin(angle)) * COLOSSEUM_RADIUS

		-- Same inward-facing convention PlotBuilder and the Bone Market use.
		local facing = CFrame.lookAt(position + Vector3.new(0, 14, 0), position * 2)

		local pillar = part({
			Name = "Board_" .. boardId,
			Size = Vector3.new(20, 28, 3),
			CFrame = facing,
			Color = Color3.fromHex("4A3B22"),
			Material = Enum.Material.Slate,
			Parent = colosseum,
		})
		--[[
			Attribute, not name. The controller finds boards by attribute, so a
			hand-built Colosseum in a future art pass only has to carry it -
			the same seam the nest anchors use.
		]]
		pillar:SetAttribute("LeaderboardBoard", boardId)
		pillar:SetAttribute("LeaderboardTitle", entry.DisplayName)

		part({
			Name = "Crest",
			Size = Vector3.new(22, 3, 4),
			CFrame = facing * CFrame.new(0, 15, 0),
			Color = Color3.fromHex("FFB020"),
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = colosseum,
		})
	end

	--[[
		The three plinths. Empty gold blocks: the statue itself is the top
		player's avatar, which only exists at runtime and only the client can
		usefully fetch, so the world provides the pedestal and the controller
		provides the person.
	]]
	for rank = 1, LeaderboardConfig.StatueCount do
		local spread = (rank - 2) * 0.5 -- -0.5, 0, 0.5 around the centre
		local angle = math.rad(COLOSSEUM_ANGLE + spread * COLOSSEUM_ARC * 0.55 + 180)
		local position = Vector3.new(math.cos(angle), 0, math.sin(angle)) * STATUE_RADIUS

		-- First place stands tallest. The podium reads at a glance from the
		-- plaza, before any text has loaded.
		local height = if rank == 1 then 16 else 11

		local plinth = part({
			Name = "Statue_" .. rank,
			Size = Vector3.new(10, height, 10),
			CFrame = CFrame.lookAt(position + Vector3.new(0, height * 0.5, 0), position * 2),
			Color = Color3.fromHex("D9A521"),
			Material = Enum.Material.Metal,
			Parent = colosseum,
		})
		plinth:SetAttribute("LeaderboardStatue", rank)
	end

	colosseum.Parent = hub
	return colosseum
end

function WorldBuilder.BuildHub(parent: Instance): Model
	local hub = Instance.new("Model")
	hub.Name = "Hub"

	part({
		Name = "Plaza",
		Class = "Part",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(ZoneConfig.GroundThickness, ZoneConfig.HubRadius * 2, ZoneConfig.HubRadius * 2),
		-- A Cylinder part's flat faces are on X, so it has to be laid down.
		CFrame = CFrame.new(0, -ZoneConfig.GroundThickness * 0.5, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromHex("8A7A5C"),
		Material = Enum.Material.Ground,
		Parent = hub,
	})

	-- The amber-encased fossil at the centre of the plaza (docs/02 §1.1).
	part({
		Name = "SpawnMonument",
		Size = Vector3.new(18, 30, 18),
		CFrame = CFrame.new(0, 15, 0),
		Color = Color3.fromHex("FFB020"),
		Material = Enum.Material.Neon,
		Transparency = 0.25,
		Parent = hub,
	})

	buildBoneMarket(hub)
	buildColosseum(hub)

	--[[
		The Teleport Obelisk, "beside spawn" per docs/02 §1.1. Opens the same
		zone wheel the GO button does; the destination list is replicated and
		every choice is re-validated server-side, so the prompt is pure UI.
	]]
	local obelisk = part({
		Name = "TeleportObelisk",
		Size = Vector3.new(8, 34, 8),
		CFrame = CFrame.new(0, 17, 46),
		Color = Color3.fromHex("9B5DE5"),
		Material = Enum.Material.Neon,
		Transparency = 0.15,
		Parent = hub,
	})
	obelisk:SetAttribute("TeleportObelisk", true)

	local obeliskPrompt = Instance.new("ProximityPrompt")
	obeliskPrompt.ActionText = "Travel"
	obeliskPrompt.ObjectText = "TELEPORT OBELISK"
	obeliskPrompt.HoldDuration = 0
	obeliskPrompt.MaxActivationDistance = 16
	obeliskPrompt.RequiresLineOfSight = false
	obeliskPrompt:SetAttribute("OpensTeleport", true)
	obeliskPrompt.Parent = obelisk

	hub.Parent = parent
	return hub
end

--[[
	One zone: ground, walls, gate, sign, shrine, landmarks, road, nest anchors.

	Every offset is zone-LOCAL and multiplied through `origin`, so the ring
	rotation is handled once instead of by every fixture.
]]
function WorldBuilder.BuildZone(zoneId: string, parent: Instance): Model
	local zone = ZoneConfig.Zones[zoneId]
	local origin = ZoneConfig.OriginOf(zoneId)
	local size = ZoneConfig.ZoneSize
	local half = size * 0.5
	local color = Color3.fromHex(zone.Color)

	local model = Instance.new("Model")
	model.Name = zone.WorldModel

	local ground = part({
		Name = "Ground",
		Size = Vector3.new(size, ZoneConfig.GroundThickness, size),
		CFrame = origin * CFrame.new(0, -ZoneConfig.GroundThickness * 0.5, 0),
		Color = color,
		Material = Enum.Material.Ground,
		Parent = model,
	})
	model.PrimaryPart = ground

	--[[
		The entrance gate, on the hub-facing edge. 150 studs tall on purpose:
		docs/02 §1.2 wants zone entrances readable from across the map, and a
		distant silhouette is what makes a locked zone feel like a destination.
	]]
	local gate = Instance.new("Model")
	gate.Name = "Gate"
	local gateWidth = 70
	for _, side in { -1, 1 } do
		part({
			Name = "GatePost",
			Size = Vector3.new(10, ZoneConfig.GateHeight, 10),
			CFrame = origin * CFrame.new(side * gateWidth * 0.5, ZoneConfig.GateHeight * 0.5, half),
			Color = shade(color, 0.25),
			Material = Enum.Material.Neon,
			Transparency = 0.15,
			Parent = gate,
		})
	end
	local lintel = part({
		Name = "GateLintel",
		Size = Vector3.new(gateWidth + 14, 10, 10),
		CFrame = origin * CFrame.new(0, ZoneConfig.GateHeight, half),
		Color = shade(color, 0.25),
		Material = Enum.Material.Neon,
		Transparency = 0.15,
		Parent = gate,
	})
	gate.PrimaryPart = lintel
	--[[
		ZoneService binds the unlock prompt to this. Tagged by attribute rather
		than by name so a hand-built zone only has to carry the attribute.
	]]
	lintel:SetAttribute("ZoneGate", zone.Id)

	--[[
		The locked barrier. COSMETIC ONLY - a part cannot be solid for one
		player and passable for another, so this says "locked" from a distance
		and ZoneService's positional check is what actually enforces it. The
		client hides it for zones it has unlocked.
	]]
	local barrier = part({
		Name = "ZoneBarrier",
		Size = Vector3.new(gateWidth, ZoneConfig.GateHeight, 2),
		CFrame = origin * CFrame.new(0, ZoneConfig.GateHeight * 0.5, half),
		Color = shade(color, 0.4),
		Material = Enum.Material.ForceField,
		Transparency = 0.55,
		CanCollide = false,
		Parent = gate,
	})
	barrier:SetAttribute("ZoneBarrier", zone.Id)

	gate.Parent = model

	-- Zone name and unlock cost, readable on approach.
	local signGui = Instance.new("BillboardGui")
	signGui.Name = "ZoneSign"
	signGui.Size = UDim2.fromScale(70, 18)
	signGui.StudsOffsetWorldSpace = Vector3.new(0, 24, 0)
	signGui.MaxDistance = 1500
	signGui.Adornee = lintel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromScale(1, 0.6)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = Color3.fromHex("F5F0E4")
	title.TextStrokeTransparency = 0.3
	title.Text = string.upper(zone.DisplayName)
	title.Parent = signGui

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Size = UDim2.fromScale(1, 0.4)
	subtitle.Position = UDim2.fromScale(0, 0.6)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = Enum.Font.GothamMedium
	subtitle.TextScaled = true
	subtitle.TextColor3 = Color3.fromHex("A89C86")
	subtitle.TextStrokeTransparency = 0.5
	subtitle.Text = zone.Tagline
	subtitle.Parent = signGui
	signGui.Parent = lintel

	-- Zone Shrine: interact once to register the zone on the Teleport Obelisk
	-- and collect a one-time bonus (docs/02 §2.2). ZoneService binds the prompt.
	local shrine = part({
		Name = "Shrine",
		Size = Vector3.new(12, 22, 12),
		CFrame = origin * CFrame.new(-half + 44, 11, half - 44),
		Color = shade(color, -0.3),
		Material = Enum.Material.Slate,
		Parent = model,
	})
	shrine:SetAttribute("ShrineZone", zone.Id)

	-- Landmarks, for navigation. Deterministic placement so players learn them.
	local landmarks = Instance.new("Folder")
	landmarks.Name = "Landmarks"
	for index = 1, 3 do
		local angle = (index / 3) * math.pi * 2 + zone.RingSlot
		local distance = half * 0.62
		local height = 30 + index * 14
		part({
			Name = "Landmark" .. index,
			Size = Vector3.new(16 + index * 5, height, 16 + index * 5),
			CFrame = origin
				* CFrame.new(math.cos(angle) * distance, height * 0.5, math.sin(angle) * distance)
				* CFrame.Angles(0, angle, 0),
			Color = shade(color, -0.22),
			Material = Enum.Material.Rock,
			Parent = landmarks,
		})
	end
	landmarks.Parent = model

	-- A road from the zone gate back toward the park ring, so the route from a
	-- park to a zone is legible rather than open ground.
	local parkOuterEdge = ParkConfig.RingRadius() + ParkConfig.PlotSize * 0.5
	local roadLength = ZoneConfig.RingRadius - half - parkOuterEdge
	if roadLength > 0 then
		part({
			Name = "Road",
			Size = Vector3.new(ZoneConfig.RoadWidth, 1, roadLength),
			CFrame = origin * CFrame.new(0, 0.2, half + roadLength * 0.5),
			Color = Color3.fromHex("6E5F44"),
			Material = Enum.Material.Ground,
			CanCollide = false,
			Parent = model,
		})
	end

	--[[
		Nest anchors. Tagged rather than referenced by name or index, because
		the tag is what lets a hand-built zone drop in later with no code
		change - NestService asks CollectionService, not this builder.
	]]
	local anchors = Instance.new("Folder")
	anchors.Name = "NestAnchors"
	for index, offset in ZoneConfig.NestOffsets(zoneId) do
		local anchor = part({
			Name = string.format("NestAnchor_%s_%02d", zoneId, index),
			Size = Vector3.new(4, 1, 4),
			CFrame = origin * CFrame.new(offset),
			Transparency = 1,
			CanCollide = false,
			Parent = anchors,
		})
		anchor:SetAttribute("ZoneId", zoneId)
		anchor:SetAttribute("NestIndex", index)
		CollectionService:AddTag(anchor, WorldBuilder.NEST_ANCHOR_TAG)
	end
	anchors.Parent = model

	model:SetAttribute("ZoneId", zoneId)
	model.Parent = parent
	return model
end

--- Builds the hub and every V1 zone. Returns the container.
function WorldBuilder.BuildAll(parent: Instance): Folder
	local existing = parent:FindFirstChild("Zones")
	if existing then
		existing:Destroy()
	end
	local existingHub = parent:FindFirstChild("Hub")
	if existingHub then
		existingHub:Destroy()
	end

	WorldBuilder.BuildHub(parent)

	local zones = Instance.new("Folder")
	zones.Name = "Zones"
	for _, zoneId in ZoneConfig.Order do
		WorldBuilder.BuildZone(zoneId, zones)
	end
	zones.Parent = parent

	return zones
end

return WorldBuilder
