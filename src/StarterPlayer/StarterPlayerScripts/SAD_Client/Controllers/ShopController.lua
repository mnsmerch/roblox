--!nonstrict
--[[
	ShopController
	.../SAD_Client/Controllers/ShopController  (ModuleScript)

	The Bone Market: three boards of upgrade rows, each showing what the level
	does now, what the next level does, and what it costs.

	═══ IT PRICES, IT DOES NOT PAY ═════════════════════════════════════════════
	Every number rendered here comes from the SAME shared UpgradeConfig and
	Stats the server charges and applies from, so what the player reads is what
	they get. But the purchase itself sends only a track id and a level count -
	never a cost. docs/13 warns about "client-computed costs disagreeing with
	the server"; a cost the server never reads cannot disagree with it.
	═══════════════════════════════════════════════════════════════════════════

	Rows re-render from the replicated profile rather than from a purchase
	response, so a level bought on another device, granted by a rebirth, or
	refunded by support all land the same way: the profile changed, the row
	redraws.

	Depends on: StateController, UIController, InputController, Theme, Create,
	            Widgets, UpgradeConfig, Stats, Format, Net.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local Format = require(Shared.Modules.Format)
local Log = require(Shared.Modules.Log)
local Net = require(Shared.Modules.Net)
local Stats = require(Shared.Modules.Stats)
local UpgradeConfig = require(Shared.Config.UpgradeConfig)

local Client = script.Parent.Parent
local Create = require(Client.UI.Create)
local Theme = require(Client.UI.Theme)
local Widgets = require(Client.UI.Widgets)

local ShopController = {}

local StateController, UIController, InputController

local root: Frame? = nil
local rows: { [string]: any } = {}
local boardButtons: { [string]: TextButton } = {}
local activeBoard = "park"
local observers = {}

--[[
	Board display names. docs/06 §5 calls the first two "Bone Market" and the
	third "Park Gate"; the tab label is the half that differs.
]]
local BOARDS = {
	{ Id = "park", Label = "PARK", Title = "BONE MARKET" },
	{ Id = "explorer", Label = "EXPLORER", Title = "BONE MARKET" },
	{ Id = "defence", Label = "DEFENCE", Title = "PARK GATE" },
}

local ROW_HEIGHT = 92

--[[
	How to phrase each track's effect. The generic fallback would be honest but
	useless ("1.24 -> 1.32"); a player deciding what to buy next needs units.

	Formatter takes the effect value at a level and returns a display string.
]]
local EFFECT_FORMAT = {
	dinoSlots = function(v) return string.format("%d slots", v) end,
	dinoStorage = function(v) return string.format("%d stored", v) end,
	incubators = function(v) return string.format("%d incubators", v) end,
	incubatorSpeed = function(v) return string.format("%d%% hatch time", math.round(v * 100)) end,
	incubatorGenetics = function(v) return string.format("+%d%% mutation luck", math.round(v * 100)) end,
	feedingTrough = function(v) return string.format("x%.2f income", v) end,
	bankSize = function(v) return Format.Time(v) .. " of bank" end,
	eggSense = function(v) return string.format("+%d%% luck", math.round(v * 100)) end,
	runnersLegs = function(v) return string.format("x%.2f speed", v) end,
	strongBack = function(v) return string.format("%d%% carry penalty", math.round(v * 100)) end,
	eggPouch = function(v) return string.format("%d eggs at once", v) end,
	fence = function(v) return string.format("+%.1fs raid time", v) end,
	guardTower = function(v) return string.format("%ds tag cooldown", math.round(v)) end,
	camera = function(v) return string.format("%d studs alert", math.round(v)) end,
}

local function describe(trackId: string, level: number): string
	local formatter = EFFECT_FORMAT[trackId]
	local value = UpgradeConfig.EffectAt(trackId, level)
	if formatter then
		return formatter(value)
	end
	return string.format("%.2f", value)
end

-- ── Row ─────────────────────────────────────────────────────────────────────

local function buildRow(entry, parent: Instance, order: number)
	local isDefence = entry.Board == "defence"
	local remote = if isDefence then "RequestBuyDefence" else "RequestBuyUpgrade"

	local name = Create("TextLabel", {
		Name = "TrackName",
		Size = UDim2.new(1, -180, 0, 22),
		Position = UDim2.fromOffset(Theme.Space.L, Theme.Space.M),
		BackgroundTransparency = 1,
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Label,
		TextColor3 = Theme.Color.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = entry.DisplayName,
	})

	local effect = Create("TextLabel", {
		Name = "Effect",
		Size = UDim2.new(1, -180, 0, 20),
		Position = UDim2.fromOffset(Theme.Space.L, 36),
		BackgroundTransparency = 1,
		Font = Theme.Font.Body,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Color.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	})

	local blurb = Create("TextLabel", {
		Name = "Blurb",
		Size = UDim2.new(1, -180, 0, 18),
		Position = UDim2.fromOffset(Theme.Space.L, 58),
		BackgroundTransparency = 1,
		Font = Theme.Font.Body,
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = Theme.Color.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = entry.Blurb,
	})

	local function actionButton(label: string, wanted: number, offsetY: number, primary: boolean)
		return Create("TextButton", {
			Name = label,
			Size = UDim2.fromOffset(148, 34),
			Position = UDim2.new(1, -Theme.Space.M, 0, offsetY),
			AnchorPoint = Vector2.new(1, 0),
			BackgroundColor3 = if primary then Theme.Color.Accent else Theme.Color.SurfaceRaised,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Font = Theme.Font.Bold,
			TextSize = Theme.TextSize.Small,
			TextColor3 = if primary then Theme.Color.TextOnAccent else Theme.Color.Text,
			Text = label,
			Children = { Create("UICorner", { CornerRadius = Theme.Radius.Small }) },
			Events = {
				MouseButton1Click = function()
					--[[
						Buy Max asks for the whole track. The server clamps it
						to what is left and to what the player can pay for, so
						asking for more than exists is not a special case here.
					]]
					Net.FireServer(remote, entry.Id, wanted)
				end,
			},
		})
	end

	local buy = actionButton("BUY", 1, Theme.Space.M, true)
	local buyMax = actionButton("BUY MAX", entry.MaxLevel, Theme.Space.M + 40, false)

	local panel = Widgets.Panel({
		Name = entry.Id,
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		LayoutOrder = order,
		Color = Theme.Color.Surface,
		Children = { name, effect, blurb, buy, buyMax },
		Parent = parent,
	})

	return {
		Entry = entry,
		Panel = panel,
		Effect = effect,
		Buy = buy,
		BuyMax = buyMax,
	}
end

--[[
	Redraws one row from the profile.

	Everything shown is derived here rather than remembered, so there is no
	state to get out of step with the profile.
]]
local function refreshRow(row, data)
	local entry = row.Entry
	local level = UpgradeConfig.LevelIn(data, entry.Id)
	local fossils = (data and data.Fossils) or 0

	if level >= entry.MaxLevel then
		row.Effect.Text = string.format("MAX  ·  %s", describe(entry.Id, level))
		row.Effect.TextColor3 = Theme.Color.Success
		row.Buy.Text = "MAXED"
		row.Buy.BackgroundColor3 = Theme.Color.SurfaceRaised
		row.Buy.TextColor3 = Theme.Color.TextDim
		row.BuyMax.Visible = false
		return
	end

	local cost = UpgradeConfig.CostOf(entry.Id, level + 1)
	local affordable = fossils >= cost

	row.Effect.Text = string.format("L%d  %s  →  %s",
		level, describe(entry.Id, level), describe(entry.Id, level + 1))
	row.Effect.TextColor3 = Theme.Color.TextMuted

	row.Buy.Text = Format.Number(cost)
	row.Buy.BackgroundColor3 = if affordable then Theme.Color.Accent else Theme.Color.SurfaceRaised
	row.Buy.TextColor3 = if affordable then Theme.Color.TextOnAccent else Theme.Color.TextDim

	-- How many levels this balance actually covers, priced level by level for
	-- the same reason the server does: the sum of rounded prices is not the
	-- rounded sum, and the two numbers have to agree.
	local budget, levels = fossils, 0
	for step = 1, entry.MaxLevel - level do
		local price = UpgradeConfig.CostOf(entry.Id, level + step)
		if price > budget then
			break
		end
		budget -= price
		levels += 1
	end

	row.BuyMax.Visible = levels > 1
	row.BuyMax.Text = string.format("BUY %d  ·  %s", levels, Format.Number(fossils - budget))
end

-- ── Board ───────────────────────────────────────────────────────────────────

local function showBoard(boardId: string)
	activeBoard = boardId

	for id, button in boardButtons do
		local on = id == boardId
		button.BackgroundColor3 = if on then Theme.Color.Accent else Theme.Color.SurfaceRaised
		button.TextColor3 = if on then Theme.Color.TextOnAccent else Theme.Color.TextMuted
	end

	for _, row in rows do
		row.Panel.Visible = row.Entry.Board == boardId
	end

	local title = root and root:FindFirstChild("Title")
	if title then
		for _, board in BOARDS do
			if board.Id == boardId then
				title.Text = board.Title
			end
		end
	end
end

local function refreshAll()
	local data = StateController.Get()
	if not data then
		return
	end
	for _, row in rows do
		refreshRow(row, data)
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
		Text = "BONE MARKET",
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
		Events = { MouseButton1Click = function() UIController.Close("Shop") end },
	})

	local tabs = Create("Frame", {
		Name = "Tabs",
		Size = UDim2.new(1, -Theme.Space.XL, 0, 40),
		Position = UDim2.fromOffset(Theme.Space.L, 56),
		BackgroundTransparency = 1,
		Children = { Widgets.Layout("horizontal", Theme.Space.S, Enum.HorizontalAlignment.Left) },
	})

	for _, board in BOARDS do
		boardButtons[board.Id] = Create("TextButton", {
			Name = board.Id,
			Size = UDim2.fromOffset(140, 40),
			BackgroundColor3 = Theme.Color.SurfaceRaised,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Font = Theme.Font.Bold,
			TextSize = Theme.TextSize.Small,
			TextColor3 = Theme.Color.TextMuted,
			Text = board.Label,
			Children = { Create("UICorner", { CornerRadius = Theme.Radius.Small }) },
			Events = { MouseButton1Click = function() showBoard(board.Id) end },
			Parent = tabs,
		})
	end

	local list = Create("ScrollingFrame", {
		Name = "Rows",
		Size = UDim2.new(1, -Theme.Space.XL, 1, -112),
		Position = UDim2.fromOffset(Theme.Space.L, 104),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.Color.Outline,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Children = { Widgets.Layout("vertical", Theme.Space.S, Enum.HorizontalAlignment.Left) },
	})

	root = Widgets.Panel({
		Name = "ShopScreen",
		Size = UDim2.fromScale(0.92, 0.86),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Theme.Color.Backdrop,
		Transparency = 0.02,
		Radius = Theme.Radius.Large,
		ZIndex = Theme.Layer.Screen,
		Visible = false,
		Children = { title, close, tabs, list },
		Parent = layer,
	})

	-- Board order, then alphabetical inside a board: the order UpgradeConfig
	-- already returns, so the shop and any future admin listing agree.
	local order = 0
	for _, board in BOARDS do
		for _, entry in UpgradeConfig.ForBoard(board.Id) do
			order += 1
			rows[entry.Id] = buildRow(entry, list, order)
		end
	end

	showBoard("park")
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function ShopController.Init(app)
	StateController = app.Get("StateController")
	UIController = app.Get("UIController")
	InputController = app.Get("InputController")
end

function ShopController.Start(_app)
	build()

	UIController.Register("Shop", {
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
		if action == "ToggleShop" and state == "Begin" then
			UIController.Toggle("Shop")
		end
	end)

	--[[
		Redraw on anything that changes a price or a level. Fossils are in the
		list because affordability is what most of a row's colour expresses,
		and the balance moves constantly while the park earns.
	]]
	for _, path in { { "Upgrades" }, { "Defences" }, { "Fossils" }, { "Rebirths" } } do
		table.insert(observers, StateController.Observe(path, function()
			if root and root.Visible then
				refreshAll()
			end
		end))
	end

	--[[
		The physical boards. A prompt tagged with a board id opens the shop on
		that board - no remote, because opening a menu is not a server concern.
	]]
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		if player ~= Players.LocalPlayer then
			return
		end
		local board = prompt:GetAttribute("ShopBoard")
		if not board then
			return
		end
		showBoard(board)
		UIController.Open("Shop")
	end)

	Log.info("ShopController", "Ready. %d tracks across %d boards",
		UpgradeConfig.Count(), #BOARDS)
end

return ShopController
