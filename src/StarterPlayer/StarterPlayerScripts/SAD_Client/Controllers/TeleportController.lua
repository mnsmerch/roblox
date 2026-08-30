--!nonstrict
--[[
	TeleportController
	.../SAD_Client/Controllers/TeleportController  (ModuleScript)

	The zone wheel: your park, the hub, and every zone whose shrine you have
	found. Locked zones stay on the wheel showing what they cost, because a
	destination you cannot reach yet is the thing that makes you want to.

	═══ WHY THE WHEEL EXISTS ═══════════════════════════════════════════════════
	Step 10 measured the walking loop at 86 seconds against docs/00's 45-second
	target: 177 studs when a park happens to face a zone, 576 typical, 1,443
	opposite. This controller and the PARK button are what bring it to 23. The
	map is deliberately too large to walk repeatedly; that is a decision, and
	this is the other half of it.
	═══════════════════════════════════════════════════════════════════════════

	It sends a destination id and nothing else. Whether that destination is
	unlocked, whether its shrine is registered, and whether a chase is in
	progress are all decided on the server - this only draws the answer it
	already has so the wheel does not offer a button that will be refused.

	Also hides the cosmetic gate barrier for zones the player has unlocked. A
	part cannot be solid for one player and passable for another, so the
	barrier is scenery and ZoneService's positional check is the real gate;
	changing Transparency here affects this client only.

	Depends on: StateController, UIController, InputController, Theme, Create,
	            Widgets, ZoneConfig, Format, Net.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local Format = require(Shared.Modules.Format)
local Log = require(Shared.Modules.Log)
local Net = require(Shared.Modules.Net)
local ZoneConfig = require(Shared.Config.ZoneConfig)

local Client = script.Parent.Parent
local Create = require(Client.UI.Create)
local Theme = require(Client.UI.Theme)
local Widgets = require(Client.UI.Widgets)

local TeleportController = {}

local StateController, UIController, InputController

local root: Frame? = nil
local cards: { [string]: any } = {}
local observers = {}

local CARD_HEIGHT = 78

--[[
	The two fixed destinations. Always available, never gated: getting home and
	getting to the hub are traversal, not progression.
]]
local FIXED = {
	{ Id = "park", Label = "YOUR PARK", Blurb = "Bank what you are carrying", Color = Theme.Color.Accent },
	{ Id = "hub", Label = "THE HUB", Blurb = "Bone Market and Obelisk", Color = Theme.Color.Shield },
}

-- ── Cards ───────────────────────────────────────────────────────────────────

local function buildCard(id: string, label: string, blurb: string, accent: Color3, order: number, parent: Instance)
	local name = Create("TextLabel", {
		Name = "Label",
		Size = UDim2.new(1, -Theme.Space.XXL, 0, 22),
		Position = UDim2.fromOffset(Theme.Space.XL, Theme.Space.M),
		BackgroundTransparency = 1,
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Label,
		TextColor3 = Theme.Color.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = label,
	})

	local status = Create("TextLabel", {
		Name = "Status",
		Size = UDim2.new(1, -Theme.Space.XXL, 0, 20),
		Position = UDim2.fromOffset(Theme.Space.XL, 38),
		BackgroundTransparency = 1,
		Font = Theme.Font.Body,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Color.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = blurb,
	})

	-- A colour stripe down the left edge, so a zone is identifiable at a glance
	-- by the same colour its gate and ground use.
	local stripe = Create("Frame", {
		Name = "Stripe",
		Size = UDim2.new(0, 6, 1, -Theme.Space.M),
		Position = UDim2.fromOffset(Theme.Space.S, Theme.Space.S),
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		Children = { Create("UICorner", { CornerRadius = Theme.Radius.Small }) },
	})

	local button = Create("TextButton", {
		Name = id,
		Size = UDim2.new(1, 0, 0, CARD_HEIGHT),
		LayoutOrder = order,
		BackgroundColor3 = Theme.Color.Surface,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Children = {
			Create("UICorner", { CornerRadius = Theme.Radius.Medium }),
			Create("UIStroke", {
				Color = Theme.Color.Outline,
				Thickness = Theme.Size.StrokeThickness,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
			stripe, name, status,
		},
		Events = {
			MouseButton1Click = function()
				--[[
					Fired even when the card is drawn as unavailable. The
					server's refusal carries the real reason, and a button that
					explains why is better than one that does nothing - but the
					wheel closes only on a destination it believes will work.
				]]
				Net.FireServer("RequestTeleport", id)
				if cards[id] and cards[id].Available then
					UIController.Close("Teleport")
				end
			end,
		},
		Parent = parent,
	})

	return { Button = button, Status = status, Label = name, Available = true }
end

--[[
	Redraws one zone card from the profile.

	Three states, and the difference between the last two is the point of the
	shrine: LOCKED (not paid for), UNVISITED (paid for, but you have never
	walked there, so it is not on the Obelisk), and READY.
]]
local function refreshZone(zoneId: string, data)
	local card = cards[zoneId]
	if not card then
		return
	end

	local zone = ZoneConfig.Get(zoneId)
	local unlocked = data.ZonesUnlocked and data.ZonesUnlocked[zoneId]
	local visited = data.Shrines and data.Shrines[zoneId]

	if not unlocked then
		card.Available = false
		card.Status.Text = string.format("LOCKED  ·  %s Fossils", Format.Number(zone.Unlock.Fossils))
		card.Status.TextColor3 = Theme.Color.TextDim
	elseif not visited then
		card.Available = false
		card.Status.Text = "Walk there once to put it on your Obelisk"
		card.Status.TextColor3 = Theme.Color.Warning
	else
		card.Available = true
		card.Status.Text = zone.Tagline
		card.Status.TextColor3 = Theme.Color.TextMuted
	end

	card.Label.TextColor3 = if card.Available then Theme.Color.Text else Theme.Color.TextMuted
	card.Button.BackgroundTransparency = if card.Available then 0.08 else 0.5
end

local function refreshAll()
	local data = StateController.Get()
	if not data then
		return
	end
	for _, zoneId in ZoneConfig.Order do
		refreshZone(zoneId, data)
	end
end

-- ── Gate barriers ───────────────────────────────────────────────────────────

--[[
	Hides the barrier on zones this player has unlocked.

	Local-only by construction: a Transparency written on the client is not
	replicated, so every player sees the barriers matching their own progress.
	Purely cosmetic - ZoneService walks a trespasser back out regardless.
]]
local function refreshBarriers()
	local data = StateController.Get()
	local world = Workspace:FindFirstChild("SAD_World")
	if not data or not world then
		return
	end

	for _, descendant in world:GetDescendants() do
		local zoneId = descendant:GetAttribute("ZoneBarrier")
		if zoneId and descendant:IsA("BasePart") then
			local unlocked = data.ZonesUnlocked and data.ZonesUnlocked[zoneId]
			descendant.Transparency = if unlocked then 1 else 0.55
		end
	end
end

-- ── Build ───────────────────────────────────────────────────────────────────

local function build()
	local layer = UIController.Layer("screen")

	local title = Create("TextLabel", {
		Name = "Title",
		Size = UDim2.new(1, -Theme.Space.XL, 0, 30),
		Position = UDim2.fromOffset(Theme.Space.L, Theme.Space.L),
		BackgroundTransparency = 1,
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Heading,
		TextColor3 = Theme.Color.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "TRAVEL",
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
		Events = { MouseButton1Click = function() UIController.Close("Teleport") end },
	})

	local list = Create("ScrollingFrame", {
		Name = "Destinations",
		Size = UDim2.new(1, -Theme.Space.XL, 1, -70),
		Position = UDim2.fromOffset(Theme.Space.L, 60),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.Color.Outline,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Children = { Widgets.Layout("vertical", Theme.Space.S, Enum.HorizontalAlignment.Left) },
	})

	root = Widgets.Panel({
		Name = "TeleportScreen",
		Size = UDim2.fromScale(0.62, 0.78),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Theme.Color.Backdrop,
		Transparency = 0.02,
		Radius = Theme.Radius.Large,
		ZIndex = Theme.Layer.Screen,
		Visible = false,
		Children = { title, close, list },
		Parent = layer,
	})

	local order = 0
	for _, fixed in FIXED do
		order += 1
		cards[fixed.Id] = buildCard(fixed.Id, fixed.Label, fixed.Blurb, fixed.Color, order, list)
	end

	-- Zone order, not alphabetical: the wheel reads as the progression it is.
	for _, zoneId in ZoneConfig.Order do
		local zone = ZoneConfig.Get(zoneId)
		order += 1
		cards[zoneId] = buildCard(zoneId, string.upper(zone.DisplayName), zone.Tagline,
			ZoneConfig.GetColor(zoneId), order, list)
	end
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function TeleportController.Init(app)
	StateController = app.Get("StateController")
	UIController = app.Get("UIController")
	InputController = app.Get("InputController")
end

function TeleportController.Start(_app)
	build()

	UIController.Register("Teleport", {
		Open = function()
			refreshAll()
			if root then
				root.Visible = true
			end
		end,
		Close = function()
			if root then
				root.Visible = false
			end
		end,
	})

	InputController.Action:Connect(function(action, state)
		if state ~= "Begin" then
			return
		end
		if action == "ToggleTeleport" then
			UIController.Toggle("Teleport")
		elseif action == "ToggleParkMenu" then
			--[[
				docs/08 §2.2: "PARK - teleports you home." The one-tap version
				of the wheel, and half of what closes the 86-second loop.
			]]
			Net.FireServer("RequestTeleport", "park")
		end
	end)

	for _, path in { { "ZonesUnlocked" }, { "Shrines" } } do
		table.insert(observers, StateController.Observe(path, function()
			refreshBarriers()
			if root and root.Visible then
				refreshAll()
			end
		end))
	end

	-- The Obelisk opens the wheel. No remote: the destination list is already
	-- replicated, and every choice is re-validated when it is made.
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		if player == Players.LocalPlayer and prompt:GetAttribute("OpensTeleport") then
			UIController.Open("Teleport")
		end
	end)

	Log.info("TeleportController", "Ready. %d destination(s)", ZoneConfig.Count() + #FIXED)
end

return TeleportController
