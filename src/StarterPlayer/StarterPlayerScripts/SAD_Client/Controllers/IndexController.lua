--!nonstrict
--[[
	IndexController
	.../SAD_Client/Controllers/IndexController  (ModuleScript)

	The Dinosaur Index book: one page per zone, every species on it, and what
	you know about each (docs/06 §4).

	An undiscovered species shows its silhouette - name hidden, rarity shown -
	because the rarity is the reason to keep looking and the name is the
	reward. A discovered one shows everything the profile records: best
	mutation, star record, times hatched, and its odds.

	The completion percentage is computed with the same shared `IndexConfig`
	the server pays milestones from, so the HUD and the reward agree about what
	100 % means - which matters more than usual here, because V1 ships 35 of
	the 60 species docs/06 describes.

	Depends on: StateController, UIController, InputController, HUDController,
	            Theme, Create, Widgets, IndexConfig, DinoConfig, ZoneConfig,
	            RarityConfig, MutationConfig, Format.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local DinoConfig = require(Shared.Config.DinoConfig)
local Format = require(Shared.Modules.Format)
local IndexConfig = require(Shared.Config.IndexConfig)
local Log = require(Shared.Modules.Log)
local MutationConfig = require(Shared.Config.MutationConfig)
local RarityConfig = require(Shared.Config.RarityConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)

local Client = script.Parent.Parent
local Create = require(Client.UI.Create)
local Theme = require(Client.UI.Theme)
local Widgets = require(Client.UI.Widgets)

local IndexController = {}

local StateController, UIController, InputController

local screen, list, header = nil, nil, nil
local rows = {}
local tabs = {}
local activeZone = "plains"
local observers = {}

local ROW_HEIGHT = 68

--[[
	Species grouped by zone, sorted by rarity then name, computed once.

	DinoConfig.Zones is authoritative for which species appear where
	(deviation #5), and a species can appear in more than one zone - so a page
	lists everything findable there rather than everything exclusive to it.
]]
local pages = nil

local function buildPages()
	pages = {}
	for _, zoneId in ZoneConfig.Order do
		local entries = {}
		for id, species in DinoConfig.Species do
			for _, zone in species.Zones do
				if zone == zoneId then
					table.insert(entries, species)
					break
				end
			end
		end
		table.sort(entries, function(a, b)
			local rankA, rankB = RarityConfig.RankOf(a.Rarity), RarityConfig.RankOf(b.Rarity)
			if rankA ~= rankB then
				return rankA < rankB
			end
			return a.DisplayName < b.DisplayName
		end)
		pages[zoneId] = entries
	end
end

-- ── Rows ────────────────────────────────────────────────────────────────────

local function buildRow(parent, order)
	local name = Create("TextLabel", {
		Name = "Name",
		Size = UDim2.new(1, -Theme.Space.XXL, 0, 22),
		Position = UDim2.fromOffset(Theme.Space.XL, Theme.Space.S),
		BackgroundTransparency = 1,
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Label,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	})

	local detail = Create("TextLabel", {
		Name = "Detail",
		Size = UDim2.new(1, -Theme.Space.XXL, 0, 18),
		Position = UDim2.fromOffset(Theme.Space.XL, 34),
		BackgroundTransparency = 1,
		Font = Theme.Font.Body,
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = Theme.Color.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	})

	-- The rarity stripe. docs/08 §7: rarity is never colour alone, so the
	-- detail line always names it too.
	local stripe = Create("Frame", {
		Name = "Stripe",
		Size = UDim2.new(0, 6, 1, -Theme.Space.M),
		Position = UDim2.fromOffset(Theme.Space.S, Theme.Space.S),
		BorderSizePixel = 0,
		Children = { Create("UICorner", { CornerRadius = Theme.Radius.Small }) },
	})

	local panel = Widgets.Panel({
		Name = "Entry",
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		LayoutOrder = order,
		Color = Theme.Color.Surface,
		Children = { stripe, name, detail },
		Parent = parent,
	})

	return { Panel = panel, Name = name, Detail = detail, Stripe = stripe }
end

local function refresh()
	local data = StateController.Get()
	if not data or not list then
		return
	end

	local entries = pages[activeZone] or {}
	local wanted = {}

	for order, species in entries do
		wanted[species.Id] = true
		local row = rows[species.Id]
		if not row then
			row = buildRow(list, order)
			rows[species.Id] = row
		end
		row.Panel.LayoutOrder = order

		local tier = RarityConfig.Tiers[species.Rarity]
		local found = data.Index[species.Id]

		row.Stripe.BackgroundColor3 = RarityConfig.GetColor(species.Rarity)

		if not found then
			--[[
				Undiscovered: the rarity is shown and the name is not. The
				rarity is why you keep looking; the name is the reward for
				having looked.
			]]
			row.Name.Text = "???"
			row.Name.TextColor3 = Theme.Color.TextDim
			row.Detail.Text = string.format("%s  ·  %s",
				string.upper(tier.DisplayName),
				--[[
					`Format.Odds(weight, total)` takes two arguments. This
					passed one, so `total` was nil and opening the Index threw
					on the `weight >= total` compare - the panel never opened.
				]]
				Format.Odds(
					RarityConfig.ZoneWeights[activeZone]
						and RarityConfig.ZoneWeights[activeZone][species.Rarity]
						or 0,
					RarityConfig.WeightTotal))
			row.Panel.BackgroundTransparency = 0.5
		else
			local mutations = {}
			for mutationId in found.Mutations or {} do
				local mutation = MutationConfig.Get(mutationId)
				if mutation and mutation.Id ~= "none" then
					table.insert(mutations, mutation.DisplayName)
				end
			end
			table.sort(mutations)

			row.Name.Text = species.DisplayName
			row.Name.TextColor3 = Theme.Color.Text
			row.Detail.Text = string.format("%s  ·  x%d  ·  %d★%s",
				string.upper(tier.DisplayName),
				found.Count or 1,
				found.BestStar or 1,
				if #mutations > 0 then "  ·  " .. table.concat(mutations, ", ") else "")
			row.Panel.BackgroundTransparency = 0.08
		end
	end

	for id, row in rows do
		if not wanted[id] then
			row.Panel:Destroy()
			rows[id] = nil
		end
	end

	if header then
		header.Text = string.format("INDEX  ·  %d / %d  (%.0f%%)",
			IndexConfig.Discovered(data), IndexConfig.Total(DinoConfig),
			IndexConfig.CompletionPercent(data, DinoConfig))
	end

	for zoneId, button in tabs do
		local on = zoneId == activeZone
		button.BackgroundColor3 = if on then Theme.Color.Accent else Theme.Color.SurfaceRaised
		button.TextColor3 = if on then Theme.Color.TextOnAccent else Theme.Color.TextMuted
	end
end

-- ── Build ───────────────────────────────────────────────────────────────────

local function build()
	buildPages()
	local layer = UIController.Layer("screen")

	header = Create("TextLabel", {
		Name = "Title",
		Size = UDim2.new(1, -Theme.Space.XXL, 0, 30),
		Position = UDim2.fromOffset(Theme.Space.L, Theme.Space.L),
		BackgroundTransparency = 1,
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Heading,
		TextColor3 = Theme.Color.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "INDEX",
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
		Events = { MouseButton1Click = function() UIController.Close("Index") end },
	})

	local tabRow = Create("Frame", {
		Name = "Pages",
		Size = UDim2.new(1, -Theme.Space.XL, 0, 40),
		Position = UDim2.fromOffset(Theme.Space.L, 56),
		BackgroundTransparency = 1,
		Children = { Widgets.Layout("horizontal", Theme.Space.S, Enum.HorizontalAlignment.Left) },
	})

	for _, zoneId in ZoneConfig.Order do
		local zone = ZoneConfig.Get(zoneId)
		tabs[zoneId] = Create("TextButton", {
			Name = zoneId,
			Size = UDim2.fromOffset(150, 40),
			BackgroundColor3 = Theme.Color.SurfaceRaised,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Font = Theme.Font.Bold,
			TextSize = Theme.TextSize.Small,
			TextColor3 = Theme.Color.TextMuted,
			Text = string.upper(zone.DisplayName),
			Children = { Create("UICorner", { CornerRadius = Theme.Radius.Small }) },
			Events = {
				MouseButton1Click = function()
					activeZone = zoneId
					refresh()
				end,
			},
			Parent = tabRow,
		})
	end

	list = Create("ScrollingFrame", {
		Name = "Entries",
		Size = UDim2.new(1, -Theme.Space.XL, 1, -110),
		Position = UDim2.fromOffset(Theme.Space.L, 102),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.Color.Outline,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Children = { Widgets.Layout("vertical", Theme.Space.S, Enum.HorizontalAlignment.Left) },
	})

	screen = Widgets.Panel({
		Name = "IndexScreen",
		Size = UDim2.fromScale(0.9, 0.88),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Theme.Color.Backdrop,
		Transparency = 0.02,
		Radius = Theme.Radius.Large,
		ZIndex = Theme.Layer.Screen,
		Visible = false,
		Children = { header, close, tabRow, list },
		Parent = layer,
	})
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function IndexController.Init(app)
	StateController = app.Get("StateController")
	UIController = app.Get("UIController")
	InputController = app.Get("InputController")
end

function IndexController.Start(_app)
	build()

	UIController.Register("Index", {
		Open = function()
			refresh()
			screen.Visible = true
		end,
		Close = function()
			screen.Visible = false
		end,
	})

	InputController.Action:Connect(function(action, state)
		if action == "ToggleIndex" and state == "Begin" then
			UIController.Toggle("Index")
		end
	end)

	table.insert(observers, StateController.Observe({ "Index" }, function()
		if screen and screen.Visible then
			refresh()
		end
	end))

	Log.info("IndexController", "Ready. %d species across %d pages",
		IndexConfig.Total(DinoConfig), #ZoneConfig.Order)
end

return IndexController
