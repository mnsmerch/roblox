--!nonstrict
--[[
	MinimapController
	.../SAD_Client/Controllers/MinimapController  (ModuleScript)

	The minimap. docs/08 §2's 🗺️ rail button and §4's `M` key finally have
	something listening.

	═══ IT IS ALL DERIVED GEOMETRY. THERE IS NO REMOTE ═════════════════════════
	Every mark on the map comes from `ZoneConfig` and `ParkConfig` - the same
	pure functions the server builds the world from - plus the replicated
	profile for which zones are unlocked and which plot is yours.

	So there is no `RequestMapData`, nothing polls the server, and the map is
	correct on the first frame rather than after a round trip. A minimap that
	asked the server where things are would be a remote per frame for
	information the client can compute exactly.
	═══════════════════════════════════════════════════════════════════════════

	═══ IT DOES NOT SHOW YOU OTHER PLAYERS ════════════════════════════════════
	Deliberately, and this is a design decision rather than an omission.

	docs/03 builds the whole raid loop on not knowing: a `StealAlert` tells you
	somebody is in your park, and the chase is about closing distance on
	incomplete information. A minimap with every player on it deletes that -
	you would never be surprised, and hiding would stop being a thing you can
	do.

	So it shows exactly two kinds of player: YOU, and anyone the server has
	already told you about via `StealAlert` - a thief in your own park, who you
	are entitled to find. Nothing else. The map cannot leak a position the game
	had not already given you.
	═══════════════════════════════════════════════════════════════════════════

	Two sizes, per docs/08 §4:
	  * COMPACT - a small disc on the right rail. Mobile is tap-to-expand, so
	    it starts hidden there; tablet and desktop show it persistently.
	  * EXPANDED - a large square with labels, unlock costs and the legend.

	Depends on: StateController, UIController, InputController, HUDController,
	            Theme, Create, Widgets, ZoneConfig, ParkConfig, Format.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local Format = require(Shared.Modules.Format)
local Log = require(Shared.Modules.Log)
local ParkConfig = require(Shared.Config.ParkConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)

local Client = script.Parent.Parent
local Create = require(Client.UI.Create)
local Theme = require(Client.UI.Theme)
local Widgets = require(Client.UI.Widgets)

local MinimapController = {}

local StateController, UIController, InputController

local player = Players.LocalPlayer

local compact: Frame? = nil
local expanded: Frame? = nil
local canvas: Frame? = nil
local compactCanvas: Frame? = nil
local titleLabel: TextLabel?

--- One table per mark, reused every frame. Marks are created once and moved,
--- never rebuilt: a minimap that recreates twenty frames at 30 Hz is a
--- minimap that drops frames on the phone it exists for.
local marks: { [string]: any } = {}
local thiefMarks: { [number]: any } = {}

local isOpen = false

--[[
	═══ THE ONE NUMBER THE WHOLE MAP IS BUILT ON ═══════════════════════════════
	The world's outer edge, in studs. Everything is drawn as a fraction of this,
	so the map stays correct when zones move or the ring grows.

	The zone ring's far edge, plus a margin - derived, never typed. When V1.4
	adds zones 5-7 at the same ring radius nothing changes; if the ring itself
	grows, this grows with it.
	═══════════════════════════════════════════════════════════════════════════
]]
local function worldRadius(): number
	return ZoneConfig.RingRadius + ZoneConfig.ZoneSize * 0.5 + 60
end

local COMPACT_SIZE = 132
local EXPANDED_SIZE = 460
local YOU_SIZE = 10

-- ── Projection ──────────────────────────────────────────────────────────────

--[[
	World XZ to a 0..1 fraction of the map, with (0.5, 0.5) at the world origin.

	North-up, not rotated with the camera. A rotating minimap is better for
	navigation in a corridor game and worse in a radial one: this map's whole
	job is teaching that zones sit on a ring around your park, and a ring that
	spins does not teach that.
]]
local function project(x: number, z: number): (number, number)
	local radius = worldRadius()
	return 0.5 + (x / radius) * 0.5, 0.5 + (z / radius) * 0.5
end

-- ── Marks ───────────────────────────────────────────────────────────────────

local function ensureMark(key: string, props)
	local existing = marks[key]
	if existing then
		return existing
	end

	local dot = Create("Frame", {
		Name = key,
		Size = UDim2.fromOffset(props.Size or 8, props.Size or 8),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = props.Color,
		BackgroundTransparency = props.Transparency or 0,
		BorderSizePixel = 0,
		ZIndex = props.ZIndex or 2,
		Children = {
			Create("UICorner", {
				CornerRadius = if props.Square then UDim.new(0, 2) else UDim.new(1, 0),
			}),
		},
	})

	local label
	if props.Label then
		label = Create("TextLabel", {
			Name = "Label",
			Size = UDim2.fromOffset(120, 14),
			Position = UDim2.new(0.5, 0, 0, -14),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundTransparency = 1,
			Font = Theme.Font.Bold,
			TextSize = Theme.TextSize.Tiny,
			TextColor3 = props.Color,
			Text = props.Label,
			ZIndex = (props.ZIndex or 2) + 1,
			Parent = dot,
		})
	end

	marks[key] = { Dot = dot, Label = label }
	return marks[key]
end

--- Places a mark by world position inside whichever canvas is asked for.
local function place(mark, x: number, z: number, parent: Instance)
	local fx, fz = project(x, z)
	mark.Dot.Position = UDim2.fromScale(fx, fz)
	if mark.Dot.Parent ~= parent then
		mark.Dot.Parent = parent
	end
end

-- ── Building the static marks ───────────────────────────────────────────────

--[[
	Built once, from config. Zones, the hub, the Obelisk and the park ring never
	move, so they are placed at build time and only ever recoloured.
]]
local function buildStaticMarks(parent: Instance, big: boolean)
	--[[
		The hub disc. Drawn as a circle sized to `HubRadius` in map fractions,
		so it is the plaza at the right size rather than a dot in the middle.
	]]
	local hubFraction = ZoneConfig.HubRadius / worldRadius()
	Create("Frame", {
		Name = "Hub",
		Size = UDim2.fromScale(hubFraction, hubFraction),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Theme.Color.SurfaceRaised,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		ZIndex = 1,
		Children = { Create("UICorner", { CornerRadius = UDim.new(1, 0) }) },
		Parent = parent,
	})

	--[[
		The park ring, as an outline rather than a filled disc: 24 plots is a
		ring you stand ON, and a filled circle would read as ground you can
		walk anywhere on.
	]]
	local ringFraction = (ParkConfig.RingRadius() + ParkConfig.PlotSize * 0.5) / worldRadius()
	Create("Frame", {
		Name = "ParkRing",
		Size = UDim2.fromScale(ringFraction, ringFraction),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 1,
		Children = {
			Create("UICorner", { CornerRadius = UDim.new(1, 0) }),
			Create("UIStroke", {
				Color = Theme.Color.Outline,
				Thickness = 1,
				Transparency = 0.3,
			}),
		},
		Parent = parent,
	})

	--[[
		One square per zone, at its real ring position and its real size, in its
		own colour. Sized from `ZoneSize` rather than drawn as a dot, because
		"a zone is a big square you walk into" is the thing the map is teaching.
	]]
	local zoneFraction = ZoneConfig.ZoneSize / worldRadius()
	for _, zoneId in ZoneConfig.Order do
		local zone = ZoneConfig.Zones[zoneId]
		local angle = ZoneConfig.AngleOf(zoneId)
		local x = math.cos(angle) * ZoneConfig.RingRadius
		local z = math.sin(angle) * ZoneConfig.RingRadius
		local fx, fz = project(x, z)

		local square = Create("Frame", {
			Name = "Zone_" .. zoneId,
			Size = UDim2.fromScale(zoneFraction * 0.5, zoneFraction * 0.5),
			Position = UDim2.fromScale(fx, fz),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = ZoneConfig.GetColor(zoneId),
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			ZIndex = 2,
			Children = { Create("UICorner", { CornerRadius = UDim.new(0, 3) }) },
			Parent = parent,
		})

		local label
		if big then
			label = Create("TextLabel", {
				Name = "Label",
				Size = UDim2.fromOffset(140, 30),
				Position = UDim2.new(0.5, 0, 1, 2),
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundTransparency = 1,
				Font = Theme.Font.Bold,
				TextSize = Theme.TextSize.Tiny,
				TextColor3 = Theme.Color.Text,
				TextYAlignment = Enum.TextYAlignment.Top,
				Text = zone.DisplayName,
				ZIndex = 4,
				Parent = square,
			})
		end

		marks["zone_" .. zoneId .. (if big then "_big" else "_small")] =
			{ Dot = square, Label = label, ZoneId = zoneId }
	end

	--[[
		The Teleport Obelisk, at the position `WorldBuilder` puts it. A literal
		here would drift the day it moves, so it is the one hard-coded world
		position in this file and it is called out as such.
	]]
	local obeliskX, obeliskZ = project(0, 46)
	Create("TextLabel", {
		Name = "Obelisk",
		Size = UDim2.fromOffset(14, 14),
		Position = UDim2.fromScale(obeliskX, obeliskZ),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Font = Theme.Font.Display,
		TextSize = 12,
		TextColor3 = Theme.Color.Rebirth,
		Text = "◆",
		ZIndex = 3,
		Parent = parent,
	})

end

-- ── Redrawing ───────────────────────────────────────────────────────────────

--[[
	Locked zones are dimmed and, on the big map, carry their unlock cost - the
	same information the signpost ring shows in the world, so the map and the
	signpost never disagree about what a zone costs.
]]
local function refreshZones()
	local data = StateController.Get()
	local unlocked = (data and data.ZonesUnlocked) or {}

	for _, zoneId in ZoneConfig.Order do
		local zone = ZoneConfig.Zones[zoneId]
		local isUnlocked = unlocked[zoneId] == true

		for _, suffix in { "_small", "_big" } do
			local mark = marks["zone_" .. zoneId .. suffix]
			if mark then
				mark.Dot.BackgroundTransparency = if isUnlocked then 0.15 else 0.72
				if mark.Label then
					mark.Label.Text = if isUnlocked
						then zone.DisplayName
						else string.format("%s\n🔒 %s", zone.DisplayName,
							Format.Number((zone.Unlock and zone.Unlock.Fossils) or 0))
					mark.Label.TextColor3 = if isUnlocked
						then Theme.Color.Text
						else Theme.Color.TextDim
				end
			end
		end
	end
end

--[[
	Your own park, from the plot the world actually assigned you rather than
	from an index: plot 7 is not the same park for two players, and a map that
	pointed at the wrong one would be worse than no map.
]]
local function findMyPlotAngle(): number?
	local world = workspace:FindFirstChild("SAD_World")
	local plots = world and world:FindFirstChild("ParkPlots")
	if not plots then
		return nil
	end
	for _, plot in plots:GetChildren() do
		if plot:GetAttribute("OwnerUserId") == player.UserId then
			local index = tonumber(plot.Name:match("%d+"))
			return index and ParkConfig.PlotAngle(index)
		end
	end
	return nil
end

local myPlotAngle: number? = nil

local function step()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")

	for _, target in { { canvas, isOpen }, { compactCanvas, compact and compact.Visible } } do
		local parent, visible = target[1], target[2]
		if not parent or not visible then
			continue
		end

		if root then
			local you = ensureMark("you", { Color = Theme.Color.Accent, Size = YOU_SIZE, ZIndex = 6 })
			--[[
				One `you` mark shared between both canvases: only one of them is
				ever visible, and `place` reparents. Two marks would be two
				dots to keep in sync for no benefit.
			]]
			place(you, root.Position.X, root.Position.Z, parent)
		end

		if myPlotAngle then
			local home = ensureMark("home", {
				Color = Theme.Color.Dna, Size = 9, ZIndex = 5, Square = true,
			})
			local radius = ParkConfig.RingRadius()
			place(home, math.cos(myPlotAngle) * radius, math.sin(myPlotAngle) * radius, parent)
		end

		--[[
			Thieves the server has already told us about. `HUDController` owns
			the alert; this owns where it is on the map, and it only ever knows
			about a raid already announced.
		]]
		for userId, mark in thiefMarks do
			local thief = Players:GetPlayerByUserId(userId)
			local thiefRoot = thief and thief.Character
				and thief.Character:FindFirstChild("HumanoidRootPart")
			if thiefRoot then
				place(mark, thiefRoot.Position.X, thiefRoot.Position.Z, parent)
				mark.Dot.Visible = true
			else
				mark.Dot.Visible = false
			end
		end
	end
end

-- ── Raid marks ──────────────────────────────────────────────────────────────

--[[
	Called by `HUDController` when a `StealAlert` arrives, and again when it
	clears. The map never learns about a player any other way.
]]
function MinimapController.SetThief(userId: number, active: boolean)
	if not active then
		local existing = thiefMarks[userId]
		if existing then
			existing.Dot:Destroy()
			thiefMarks[userId] = nil
		end
		return
	end

	if thiefMarks[userId] then
		return
	end

	local dot = Create("Frame", {
		Name = "Thief" .. userId,
		Size = UDim2.fromOffset(10, 10),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Theme.Color.Danger,
		BorderSizePixel = 0,
		ZIndex = 7,
		Children = { Create("UICorner", { CornerRadius = UDim.new(1, 0) }) },
	})
	thiefMarks[userId] = { Dot = dot }
end

-- ── Build ───────────────────────────────────────────────────────────────────

local function buildCompact()
	compactCanvas = Create("Frame", {
		Name = "Canvas",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
	})

	compact = Widgets.Panel({
		Name = "Minimap",
		Size = UDim2.fromOffset(COMPACT_SIZE, COMPACT_SIZE),
		--[[
			Under the right rail, which docs/08 §2 puts the 🗺️ button at the
			bottom of. Positioned from the rail rather than from the screen
			edge so it moves with it.
		]]
		Position = UDim2.new(1, -Theme.Space.M, 0.5, 150),
		AnchorPoint = Vector2.new(1, 0),
		Color = Theme.Color.Backdrop,
		Transparency = 0.15,
		Radius = Theme.Radius.Medium,
		ZIndex = Theme.Layer.Hud,
		Visible = false,
		Children = { compactCanvas },
		Parent = UIController.Layer("hud"),
	})

	buildStaticMarks(compactCanvas, false)
end

local function buildExpanded()
	titleLabel = Create("TextLabel", {
		Name = "Title",
		Size = UDim2.new(1, -Theme.Space.XL, 0, 26),
		Position = UDim2.fromOffset(Theme.Space.L, Theme.Space.M),
		BackgroundTransparency = 1,
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Heading,
		TextColor3 = Theme.Color.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "MAP",
	})

	local close = Create("TextButton", {
		Name = "Close",
		Size = UDim2.fromOffset(Theme.Size.MinTouchTarget, 40),
		Position = UDim2.new(1, -Theme.Space.L, 0, Theme.Space.M),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Theme.Color.SurfaceRaised,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Label,
		TextColor3 = Theme.Color.Text,
		Text = "✕",
		Children = { Create("UICorner", { CornerRadius = Theme.Radius.Small }) },
		Events = { MouseButton1Click = function() UIController.Close("Map") end },
	})

	canvas = Create("Frame", {
		Name = "Canvas",
		Size = UDim2.fromOffset(EXPANDED_SIZE, EXPANDED_SIZE),
		Position = UDim2.new(0.5, 0, 0, 54),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Theme.Color.Surface,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Children = { Create("UICorner", { CornerRadius = Theme.Radius.Medium }) },
	})

	--[[
		A legend, because a map of coloured dots with no key is a decoration.
		Four entries, which is all there is to say.
	]]
	local legend = Create("Frame", {
		Name = "Legend",
		Size = UDim2.new(1, -Theme.Space.XL, 0, 20),
		Position = UDim2.new(0.5, 0, 1, -Theme.Space.L),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Children = { Widgets.Layout("horizontal", Theme.Space.L, Enum.HorizontalAlignment.Center) },
	})

	for order, entry in {
		{ Text = "● YOU", Color = Theme.Color.Accent },
		{ Text = "■ YOUR PARK", Color = Theme.Color.Dna },
		{ Text = "◆ OBELISK", Color = Theme.Color.Rebirth },
		{ Text = "● RAIDER", Color = Theme.Color.Danger },
	} do
		Create("TextLabel", {
			Name = "Key" .. order,
			Size = UDim2.fromOffset(110, 20),
			BackgroundTransparency = 1,
			Font = Theme.Font.Body,
			TextSize = Theme.TextSize.Tiny,
			TextColor3 = entry.Color,
			Text = entry.Text,
			LayoutOrder = order,
			Parent = legend,
		})
	end

	expanded = Widgets.Panel({
		Name = "MapScreen",
		Size = UDim2.fromOffset(EXPANDED_SIZE + 40, EXPANDED_SIZE + 110),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Theme.Color.Backdrop,
		Transparency = 0.02,
		Radius = Theme.Radius.Large,
		ZIndex = Theme.Layer.Screen,
		Visible = false,
		Children = { titleLabel, close, canvas, legend },
		Parent = UIController.Layer("screen"),
	})

	buildStaticMarks(canvas, true)
end

--[[
	docs/08 §4: "The minimap is tap-to-expand, not always-on" on mobile;
	"a persistent minimap" on tablet. So the compact disc follows the
	breakpoint, and the expanded map is a screen on every device.
]]
local function applyBreakpoint()
	if compact then
		compact.Visible = UIController.Breakpoint ~= "compact"
	end
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function MinimapController.Init(app)
	StateController = app.Get("StateController")
	UIController = app.Get("UIController")
	InputController = app.Get("InputController")
end

function MinimapController.Start(_app)
	buildCompact()
	buildExpanded()
	refreshZones()
	applyBreakpoint()

	UIController.Register("Map", {
		Open = function()
			isOpen = true
			refreshZones()
			if expanded then
				expanded.Visible = true
			end
		end,
		Close = function()
			isOpen = false
			if expanded then
				expanded.Visible = false
			end
		end,
	})

	InputController.Action:Connect(function(action, state)
		if action == "ToggleMap" and state == "Begin" then
			UIController.Toggle("Map")
		end
	end)

	-- Tapping the compact disc expands it - docs/08 §4's "tap-to-expand".
	if compact then
		Create("TextButton", {
			Name = "Expand",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = "",
			ZIndex = 10,
			Events = { MouseButton1Click = function() UIController.Open("Map") end },
			Parent = compact,
		})
	end

	UIController.BreakpointChanged:Connect(applyBreakpoint)

	StateController.Observe({ "ZonesUnlocked" }, refreshZones)

	--[[
		Which plot is yours is answered once, when the world says so. Polled
		rather than pushed because plot assignment is a server-side attribute on
		a streamed-in model and there is no event for it - and once found, it
		does not change for the session.
	]]
	task.spawn(function()
		while myPlotAngle == nil do
			myPlotAngle = findMyPlotAngle()
			if myPlotAngle == nil then
				task.wait(2)
			end
		end
	end)

	--[[
		Marks move at 15 Hz rather than every frame. It is a map: nothing on it
		moves fast enough for 60 Hz to be visible, and this is the controller
		most likely to be running on the weakest device in the game.
	]]
	task.spawn(function()
		while true do
			task.wait(1 / 15)
			if isOpen or (compact and compact.Visible) then
				step()
			end
		end
	end)

	Log.info("MinimapController", "Ready. %d zone(s) on a %d-stud map",
		ZoneConfig.Count(), math.floor(worldRadius()))
end

return MinimapController
