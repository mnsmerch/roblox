--!nonstrict
--[[
	ParkService
	ServerScriptService/SAD_Server/Services/ParkService  (ModuleScript)
	  └── PlotBuilder  (ModuleScript)

	Owns the 24 park plots: generating them, handing one to each player,
	releasing it when they leave, and answering "whose park is this position
	in?" for every system that cares.

	That last question is load-bearing. Wild guardians stop at a gate, stolen
	eggs deposit at a gate, raids start and end at gates, and shields apply
	inside them. All of it comes from GetParkAt, and all of it is computed
	SERVER-SIDE from character position - never from a client touch event,
	which a client can trivially fake.

	Plot lookup is O(1). Plots sit on a ring, so a position's angle names its
	candidate plot directly; only that one plot is then bounds-checked. Scanning
	24 plots per player per tick would work today and stop working the first
	time somebody raises PlotCount.

	API:
		ParkService.GetPlot(player) -> Model?
		ParkService.GetPlotByUserId(userId) -> Model?
		ParkService.GetOwnerOf(plot) -> number      0 when unowned
		ParkService.GetParkAt(position) -> plot?, ownerUserId?
		ParkService.IsInsideOwnPark(player) -> boolean
		ParkService.GetSpawnCFrame(plot) -> CFrame
		ParkService.GetTileCFrame(plot, tileX, tileZ, size?) -> CFrame
		ParkService.WorldToTile(plot, position) -> tileX?, tileZ?
		ParkService.SetShieldVisible(plot, visible)
		ParkService.SetVisualTier(plot, parkValue)
		ParkService.RefreshDinos(player)

		ParkService.PlotAssigned    Signal(player, plot)
		ParkService.PlotReleased    Signal(player, plot)
		ParkService.ParkEntered     Signal(player, ownerUserId, plot)
		ParkService.DinoRendered    Signal(owner, uid, model)
		ParkService.ParkExited      Signal(player, ownerUserId, plot)

	Depends on: ParkConfig, PlotBuilder, PlayerDataService, MutationSkin, Log,
	            Signal.
	Depended on by: EggService, StealService, WildAIService, DinosaurService.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local DinoConfig = require(Shared.Config.DinoConfig)
local GameConfig = require(Shared.Config.GameConfig)
local ParkConfig = require(Shared.Config.ParkConfig)
local MutationSkin = require(Shared.Modules.MutationSkin)
local RarityConfig = require(Shared.Config.RarityConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local Economy = require(Shared.Modules.Economy)
local Format = require(Shared.Modules.Format)
local Log = require(Shared.Modules.Log)
local Signal = require(Shared.Modules.Signal)

local PlotBuilder = require(script.PlotBuilder)

local ParkService = {}

ParkService.PlotAssigned = Signal.new()
ParkService.PlotReleased = Signal.new()
ParkService.ParkEntered = Signal.new()
ParkService.ParkExited = Signal.new()
--- Fired for each dinosaur model as it is rendered, so services can attach
--- behaviour to it. StealService uses it for the raid prompt.
ParkService.DinoRendered = Signal.new()

local plots: { Model } = {}
local origins: { CFrame } = {}

--[[
	The order `claimPlot` searches in: nearest the free zone first, so the walk
	docs/00 §3 beat 2 budgets fifteen seconds for is the short one by default.
	Computed once at Start, from ZoneConfig, because it never changes.
]]
local plotSearchOrder: { number } = {}
local byUserId: { [number]: Model } = {}
local plotOfPlayer: { [Player]: Model } = {}

--- [player] = the userId whose park they are currently standing in, or nil.
local occupancy: { [Player]: number? } = {}

local PlayerDataService = nil
local DinosaurService = nil
local EconomyService = nil
local worldFolder: Folder = nil
local dinoFolder: Folder = nil
local dinoAssets: Folder = nil

--- [player] = { [dinoUid] = Model }
local rendered: { [Player]: { [string]: Model } } = {}

--- [player] = the Collection Totem's prompt
local totemPrompts: { [Player]: ProximityPrompt } = {}

--[[
	Ring bounds for the cheap rejection test. A position outside this band
	cannot be in any park, which is true of most of the map most of the time.
]]
local ringInner, ringOuter = 0, 0

-- ── Geometry ────────────────────────────────────────────────────────────────

--[[
	The plot containing `position`, or nil.

	O(1): the ring gives a radius test, the angle names one candidate, and only
	that candidate is bounds-checked in its own local space.
]]
function ParkService.GetParkAt(position: Vector3): (Model?, number?)
	local flatDistance = math.sqrt(position.X * position.X + position.Z * position.Z)
	if flatDistance < ringInner or flatDistance > ringOuter then
		return nil, nil
	end

	local angle = math.atan2(position.Z, position.X)
	if angle < 0 then
		angle += math.pi * 2
	end

	local step = math.pi * 2 / ParkConfig.PlotCount
	local index = (math.floor(angle / step + 0.5) % ParkConfig.PlotCount) + 1

	local plot = plots[index]
	if not plot then
		return nil, nil
	end

	-- Confirm against the plot's own bounds. The angular guess can be one plot
	-- out near a boundary; the local-space test is exact.
	local localPosition = origins[index]:PointToObjectSpace(position)
	local half = ParkConfig.PlotSize * 0.5
	if math.abs(localPosition.X) > half or math.abs(localPosition.Z) > half then
		return nil, nil
	end

	return plot, plot:GetAttribute("OwnerUserId")
end

function ParkService.GetSpawnCFrame(plot: Model): CFrame
	local index = plot:GetAttribute("PlotIndex")
	-- Face into the park, i.e. away from the gate.
	return origins[index] * CFrame.new(ParkConfig.SpawnOffset) * CFrame.Angles(0, math.pi, 0)
end

--- World CFrame of a footprint anchored at (tileX, tileZ). `size` is a
--- DinoConfig footprint like "3x3"; omitted means a single tile.
function ParkService.GetTileCFrame(plot: Model, tileX: number, tileZ: number, size: string?): CFrame
	local index = plot:GetAttribute("PlotIndex")
	local offset = if size
		then ParkConfig.FootprintCenterOffset(tileX, tileZ, size)
		else ParkConfig.TileToOffset(tileX, tileZ)
	return origins[index] * CFrame.new(offset)
end

--- Which tile a world position falls on, or nil if it is off the grid.
function ParkService.WorldToTile(plot: Model, position: Vector3): (number?, number?)
	local index = plot:GetAttribute("PlotIndex")
	return ParkConfig.OffsetToTile(origins[index]:PointToObjectSpace(position))
end

-- ── Ownership ───────────────────────────────────────────────────────────────

function ParkService.GetPlot(player: Player): Model?
	return plotOfPlayer[player]
end

function ParkService.GetPlotByUserId(userId: number): Model?
	return byUserId[userId]
end

function ParkService.GetOwnerOf(plot: Model): number
	return plot:GetAttribute("OwnerUserId") or 0
end

function ParkService.IsInsideOwnPark(player: Player): boolean
	return occupancy[player] == player.UserId
end

--- The userId of the park `player` is standing in, or nil.
function ParkService.GetOccupiedPark(player: Player): number?
	return occupancy[player]
end

-- ── Appearance ──────────────────────────────────────────────────────────────

function ParkService.SetShieldVisible(plot: Model, visible: boolean)
	local dome = plot:FindFirstChild("SafeDome")
	if dome then
		dome.Transparency = if visible then 0.75 else 1
	end
end

--- Applies the free visual tier for a park's total value (docs/02 §3).
function ParkService.SetVisualTier(plot: Model, parkValue: number)
	local tier = ParkConfig.VisualTierFor(parkValue)
	if plot:GetAttribute("VisualTier") == tier.Id then
		return
	end
	plot:SetAttribute("VisualTier", tier.Id)

	local base = plot:FindFirstChild("Base")
	if base then
		base.Color = Color3.fromHex(tier.Base)
	end
	for _, child in plot:GetChildren() do
		if child:IsA("BasePart") and string.sub(child.Name, 1, 4) == "Wall" then
			child.Color = Color3.fromHex(tier.Wall)
		end
	end
end

local function setSignText(plot: Model, text: string)
	local gate = plot:FindFirstChild("Gate")
	local lintel = gate and gate:FindFirstChild("GateLintel")
	local sign = lintel and lintel:FindFirstChild("OwnerSign")
	local label = sign and sign:FindFirstChild("Label")
	if label then
		label.Text = text
	end
end

-- ── Rendering placed dinosaurs ──────────────────────────────────────────────

--[[
	Brings the models in the park in line with what the profile says.

	Only touches what changed - a park with thirty dinosaurs re-renders one when
	one is placed, not thirty. Called on assignment, on any placement change,
	and never on a timer.
]]
function ParkService.RefreshDinos(player: Player)
	local plot = plotOfPlayer[player]
	local data = PlayerDataService.Get(player)
	if not plot or not data then
		return
	end

	local existing = rendered[player]
	if not existing then
		existing = {}
		rendered[player] = existing
	end

	local wanted = {}

	for uid, entry in data.Dinos do
		if not entry.Placed or not entry.TileX then
			continue
		end
		wanted[uid] = true

		if existing[uid] then
			continue
		end

		local species = DinoConfig.Get(entry.SpeciesId)
		local template = species and dinoAssets:FindFirstChild(species.ModelName)
		if not template then
			continue
		end

		local model = template:Clone()
		model.Name = "ParkDino_" .. uid

		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant.CastShadow = false
			end
		end

		local cframe = ParkService.GetTileCFrame(plot, entry.TileX, entry.TileZ, species.Size)
		-- Face the gate, so a visitor walking in is looked at.
		model:PivotTo(cframe * CFrame.Angles(0, math.pi, 0))

		model:SetAttribute("DinoUid", uid)
		model:SetAttribute("OwnerUserId", player.UserId)
		model:SetAttribute("Rarity", entry.Rarity)
		if entry.Mutation then
			model:SetAttribute("Mutation", entry.Mutation)
		end
		--[[
			Both, because MaxStack is 2 and the skin paints the hide from the
			primary and the crests from the secondary. Mutation2 was rolled and
			named in the tag but never published on the model.
		]]
		if entry.Mutation2 then
			model:SetAttribute("Mutation2", entry.Mutation2)
		end

		--[[
			A mutation used to be a word in the name tag and nothing else - a
			x150 Void dinosaur rendered identically to a plain one. The recipe
			is MutationConfig.SkinFor; this is the call site.

			Server-side rather than in a controller: the model is server-built
			and the skin is part of what the dinosaur IS, not a local effect. It
			replicates once with the model instead of being recomputed by every
			client that walks past.
		]]
		MutationSkin.Apply(model, entry.Mutation, entry.Mutation2)

		-- Rare dinosaurs are meant to be visible from across the map
		-- (docs/01 §1). A light is the cheapest thing that carries at range.
		local tier = RarityConfig.Tiers[entry.Rarity]
		if tier and tier.Rank >= 4 then
			local light = Instance.new("PointLight")
			light.Color = RarityConfig.GetColor(entry.Rarity)
			light.Brightness = 3
			light.Range = 30
			--[[
				The Torso, not the PrimaryPart. The PrimaryPart is now an empty
				Root at the model's feet (it has to be, so PivotTo lands the
				dinosaur on the ground rather than in it) - and a light at the
				ankles of a 100-stud titan lights the ankles.
			]]
			light.Parent = model:FindFirstChild("Torso")
				or model.PrimaryPart
				or model:FindFirstChildWhichIsA("BasePart")
		end

		local nameTag = Instance.new("BillboardGui")
		nameTag.Name = "NameTag"
		nameTag.Size = UDim2.fromScale(12, 2.4)
		--[[
			Above the head, not at a fixed 8 studs. The adornee is the Root part
			at the model's feet, and species range from a 9-stud Compsognathus
			to a titan rex three times its own 40-stud footprint - one constant
			cannot serve both. `StandHeight` is set by AssetBuilder from the
			body plan; the fallback covers real art dropped in without it.
		]]
		local standHeight = model:GetAttribute("StandHeight")
			or model:GetExtentsSize().Y
		nameTag.StudsOffsetWorldSpace = Vector3.new(0, standHeight + 3, 0)
		nameTag.MaxDistance = 160
		nameTag.Adornee = model.PrimaryPart

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextStrokeTransparency = 0.4
		label.TextColor3 = RarityConfig.GetColor(entry.Rarity)
		label.Text = DinosaurService.DisplayNameOf(entry)
		label.Parent = nameTag
		nameTag.Parent = model.PrimaryPart

		model.Parent = dinoFolder
		existing[uid] = model
		ParkService.DinoRendered:Fire(player, uid, model)
	end

	-- Anything no longer placed goes away.
	for uid, model in existing do
		if not wanted[uid] then
			model:Destroy()
			existing[uid] = nil
		end
	end
end

local function clearDinos(player: Player)
	local existing = rendered[player]
	if existing then
		for _, model in existing do
			model:Destroy()
		end
	end
	rendered[player] = nil
end

-- ── The Collection Totem ────────────────────────────────────────────────────

--[[
	One prompt does both jobs: collect what is banked, or place a dinosaur if
	there is nothing to collect.

	Two prompts on one object is worse than one that reads the situation, and
	until Step 13 builds the Dinos menu this is the only way to place anything.
]]
local function refreshTotem(player: Player)
	local prompt = totemPrompts[player]
	if not prompt then
		return
	end

	local data = PlayerDataService.Get(player)
	if not data then
		return
	end

	local banked = EconomyService.GetBanked(player)

	if banked >= 1 then
		prompt.Enabled = true
		prompt.ActionText = "Collect"
		prompt.ObjectText = Format.Number(banked) .. " Fossils"
		return
	end

	local unplaced = 0
	for _, entry in data.Dinos do
		if not entry.Placed and not entry.Vault then
			unplaced += 1
		end
	end

	if unplaced > 0 and DinosaurService.GetPlacedCount(player) < Economy.SlotCap(data) then
		prompt.Enabled = true
		prompt.ActionText = "Place Dinosaur"
		prompt.ObjectText = unplaced .. " in storage"
	else
		prompt.Enabled = false
		prompt.ActionText = "Collect"
		prompt.ObjectText = "Nothing banked"
	end
end

ParkService.RefreshTotem = refreshTotem

local function bindTotem(player: Player, plot: Model)
	local totem = plot:FindFirstChild("CollectionTotem")
	if not totem then
		return
	end

	local existing = totem:FindFirstChildOfClass("ProximityPrompt")
	if existing then
		existing:Destroy()
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TotemPrompt"
	prompt.ActionText = "Collect"
	prompt.ObjectText = "Collection Totem"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = totem

	prompt.Triggered:Connect(function(triggerer: Player)
		-- Your own totem only. A visitor is a visitor.
		if triggerer ~= player then
			return
		end

		if EconomyService.Collect(player) <= 0 then
			DinosaurService.PlaceBest(player)
		end
		refreshTotem(player)
	end)

	totemPrompts[player] = prompt
	refreshTotem(player)
end

-- ── Assignment ──────────────────────────────────────────────────────────────

--[[
	Claims a free plot. NOT a coroutine and containing no yields, so two players
	joining in the same frame cannot both be handed plot 7 - the whole function
	runs to completion before the next resumption point.

	docs/13 flags this as the bug to watch for in this step, and a yield
	anywhere inside here is how it happens.
]]
local function claimPlot(player: Player): Model?
	--[[
		Searched nearest-the-free-zone-first rather than in index order, so a
		new player's walk out to Jurassic Plains is the short one by default.
		See ParkConfig.PlotSearchOrder. Still a preference and never a
		requirement: every plot is reachable by this loop, so it cannot starve.
	]]
	for _, index in plotSearchOrder do
		local plot = plots[index]
		if plot and plot:GetAttribute("OwnerUserId") == 0 then
			plot:SetAttribute("OwnerUserId", player.UserId)
			byUserId[player.UserId] = plot
			plotOfPlayer[player] = plot
			return plot
		end
	end
	return nil
end

local function releasePlot(player: Player)
	local plot = plotOfPlayer[player]
	if not plot then
		return
	end

	plot:SetAttribute("OwnerUserId", 0)
	plot:SetAttribute("VisualTier", nil)
	setSignText(plot, "Empty Plot")
	ParkService.SetShieldVisible(plot, false)
	ParkService.SetVisualTier(plot, 0)

	clearDinos(player)
	totemPrompts[player] = nil

	plotOfPlayer[player] = nil
	byUserId[player.UserId] = nil
	occupancy[player] = nil

	Log.info("ParkService", "Released %s from %s", player.Name, plot.Name)
	ParkService.PlotReleased:Fire(player, plot)
end

local function placeCharacter(player: Player, character: Model)
	local plot = plotOfPlayer[player]
	if not plot then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")
		or character:WaitForChild("HumanoidRootPart", 5)
	if not root then
		return
	end

	character:PivotTo(ParkService.GetSpawnCFrame(plot))
end

local function onProfileLoaded(player: Player, data)
	local plot = claimPlot(player)

	if not plot then
		--[[
			More players than plots. With MaxPlayers at PlotCount this cannot
			happen in a correctly configured place, so it is logged as an error
			rather than handled quietly - it means the place settings drifted.
		]]
		Log.error("ParkService", "No free plot for %s (%d plots, %d players)",
			player.Name, #plots, #Players:GetPlayers())
		-- With CharacterAutoLoads off they have no character to strand, so a
		-- kick is the whole story rather than leaving them in a void.
		player:Kick("This server is full. Please rejoin to get a park.")
		return
	end

	setSignText(plot, player.DisplayName .. "'s Park")
	ParkService.SetVisualTier(plot, 0)

	--[[
		Connect BEFORE spawning, then spawn manually.

		CharacterAutoLoads is off (see Init), so no character exists until this
		line - which means a player is never briefly standing at the world
		origin before being moved. docs/00 FTUE beat 1 is "spawn directly inside
		your own park", and a visible teleport in the first second of the game
		is exactly the kind of thing that reads as broken.

		A SpawnLocation with RespawnLocation would be the other route, but its
		interaction with Enabled = false is not something I want load-bearing
		on the first frame a new player sees.
	]]
	player.CharacterAdded:Connect(function(character)
		task.defer(placeCharacter, player, character)
	end)

	if player.Character then
		placeCharacter(player, player.Character)
	else
		local ok, err = pcall(function()
			player:LoadCharacter()
		end)
		if not ok then
			Log.error("ParkService", "LoadCharacter failed for %s: %s", player.Name, tostring(err))
		end
	end

	bindTotem(player, plot)
	ParkService.RefreshDinos(player)

	Log.info("ParkService", "Assigned %s to %s", player.Name, plot.Name)
	ParkService.PlotAssigned:Fire(player, plot)
end

-- ── Occupancy tracking ──────────────────────────────────────────────────────

--[[
	Samples every character's position and fires enter/exit for park boundaries.

	Server-side and position-based on purpose. A Touched event on a gate part
	would be simpler and is exactly what an exploiter fires by hand to claim
	they reached safety - see docs/03 §6.
]]
local function sampleOccupancy()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then
			continue
		end

		local plot, ownerUserId = ParkService.GetParkAt(root.Position)
		local inside = if plot and ownerUserId ~= 0 then ownerUserId else nil
		local previous = occupancy[player]

		if inside == previous then
			continue
		end

		if previous then
			local previousPlot = byUserId[previous]
			occupancy[player] = nil
			ParkService.ParkExited:Fire(player, previous, previousPlot)
		end

		if inside then
			occupancy[player] = inside
			ParkService.ParkEntered:Fire(player, inside, plot)
		end
	end
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function ParkService.Init(app)
	PlayerDataService = app.Get("PlayerDataService")
	DinosaurService = app.Get("DinosaurService")
	EconomyService = app.Get("EconomyService")

	dinoAssets = Shared:WaitForChild("SAD_Assets"):WaitForChild("Dinos")

	--[[
		Characters are spawned by hand, once a plot is assigned. Otherwise a
		player materialises at the world origin, falls, and is then teleported -
		in the first second of the game, before they know what it is.
	]]
	Players.CharacterAutoLoads = false

	worldFolder = Workspace:FindFirstChild("SAD_World")
	if not worldFolder then
		worldFolder = Instance.new("Folder")
		worldFolder.Name = "SAD_World"
		worldFolder.Parent = Workspace
	end

	-- A rebuild on a Studio re-run must not leave the previous ring behind.
	local existing = worldFolder:FindFirstChild("ParkPlots")
	if existing then
		existing:Destroy()
	end

	local container = Instance.new("Folder")
	container.Name = "ParkPlots"

	--[[
		Sorted against the FIRST zone in ZoneConfig.Order - the free one every
		new player is sent to. If the free zone ever moves, this follows it.
	]]
	local firstZoneId = ZoneConfig.Order[1]
	local firstZone = firstZoneId and ZoneConfig.Zones[firstZoneId]
	plotSearchOrder = ParkConfig.PlotSearchOrder(
		firstZone and firstZone.RingSlot, ZoneConfig.SlotCount)

	local startedAt = os.clock()
	for index = 1, ParkConfig.PlotCount do
		local plot = PlotBuilder.Build(index)
		plot.Parent = container
		plots[index] = plot
		origins[index] = PlotBuilder.OriginOf(index)
	end
	container.Parent = worldFolder

	-- Radius band for the cheap rejection test in GetParkAt. The half-diagonal
	-- covers a plot's corners, which stick out further than its half-width.
	local radius = ParkConfig.RingRadius()
	local halfDiagonal = ParkConfig.PlotSize * math.sqrt(2) * 0.5
	ringInner = math.max(0, radius - halfDiagonal)
	ringOuter = radius + halfDiagonal

	Log.info("ParkService", "Built %d plots at radius %.0f in %.0f ms",
		ParkConfig.PlotCount, radius, (os.clock() - startedAt) * 1000)

	--[[
		═══ ONE PLOT PER PLAYER, CHECKED THREE WAYS ════════════════════════════
		A player with no plot has nowhere to live: no park, no incubators, no
		income, and `claimPlot` hands them nil.

		The old check compared the players present RIGHT NOW against the plot
		count, so on an empty boot it never fired - it could only report the
		problem after it had already happened to somebody. These check the
		configuration instead, at boot, before anybody joins.

		`Players.MaxPlayers` is the one that actually governs, and it is a PLACE
		setting rather than anything in this repository - so it is a warning
		naming the fix, not an assert. The two config copies are ours, so they
		are asserts.
		═══════════════════════════════════════════════════════════════════════
	]]
	assert(GameConfig.ParkPlotCount == ParkConfig.PlotCount,
		("GameConfig.ParkPlotCount is %d and ParkConfig.PlotCount is %d - "
			.. "they are the same number and must agree")
			:format(GameConfig.ParkPlotCount, ParkConfig.PlotCount))

	assert(GameConfig.MaxPlayers <= ParkConfig.PlotCount,
		("GameConfig.MaxPlayers is %d but there are only %d plots - "
			.. "a player without a plot has nowhere to live")
			:format(GameConfig.MaxPlayers, ParkConfig.PlotCount))

	if Players.MaxPlayers > ParkConfig.PlotCount then
		Log.warn("ParkService",
			"This place allows %d players but there are only %d plots. "
				.. "Set MaxPlayers to %d in Game Settings, or players will join "
				.. "with no park", Players.MaxPlayers, ParkConfig.PlotCount,
			ParkConfig.PlotCount)
	end
end

function ParkService.Start(app)
	PlayerDataService.ProfileLoaded:Connect(onProfileLoaded)
	PlayerDataService.ProfileUnloading:Connect(function(player)
		releasePlot(player)
	end)

	-- Belt and braces: a player who leaves before their profile loads still
	-- needs their plot back.
	Players.PlayerRemoving:Connect(releasePlot)

	local interval = 1 / GameConfig.SecuritySampleHz
	task.spawn(function()
		while true do
			task.wait(interval)
			local ok, err = pcall(sampleOccupancy)
			if not ok then
				Log.error("ParkService", "Occupancy sampling failed: %s", tostring(err))
			end
		end
	end)

	local runtime = Workspace:WaitForChild("SAD_Runtime")
	dinoFolder = runtime:WaitForChild("ParkDinos")

	--[[
		Placement changes re-render one dinosaur, not thirty, and re-evaluate
		the park's free visual tier - the retexture a returning player notices
		without having bought anything (docs/02 §3).
	]]
	local function onParkChanged(player: Player)
		ParkService.RefreshDinos(player)
		refreshTotem(player)

		local plot = plotOfPlayer[player]
		local data = PlayerDataService.Get(player)
		if plot and data then
			ParkService.SetVisualTier(plot, Economy.ParkValue(data))
		end
	end

	DinosaurService.DinoPlaced:Connect(onParkChanged)
	DinosaurService.DinoStored:Connect(onParkChanged)
	DinosaurService.DinoCreated:Connect(onParkChanged)

	--[[
		One shared loop keeps every totem's readout current. 1 Hz across at
		most 24 players is nothing, and without it a totem shows a stale figure
		until the player next touches it.
	]]
	task.spawn(function()
		while true do
			task.wait(1)
			for player in totemPrompts do
				local ok, err = pcall(refreshTotem, player)
				if not ok then
					Log.error("ParkService", "Totem refresh failed for %s: %s", player.Name, tostring(err))
				end
			end
		end
	end)

	Log.info("ParkService", "Occupancy sampling at %d Hz", GameConfig.SecuritySampleHz)
end

return ParkService
