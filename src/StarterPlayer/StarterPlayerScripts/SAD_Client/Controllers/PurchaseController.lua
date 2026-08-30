--!nonstrict
--[[
	PurchaseController
	.../SAD_Client/Controllers/PurchaseController  (ModuleScript)

	Three things, all of them docs/07's:

	  1. The Robux store - 6 gamepasses and 8 products, priced and described
	     from the same `ProductConfig` the server grants from.
	  2. The first-open honesty panel (§1 rule 7).
	  3. The server-purchase banner and the Thanks button (§4).

	═══ IT PROMPTS, IT DOES NOT GRANT ══════════════════════════════════════════
	Every button here calls `MarketplaceService:PromptGamePassPurchase` or
	`PromptProductPurchase` and then does nothing else. Robux moves through
	Roblox and lands on the server's `ProcessReceipt`; the effect appears here
	because the profile changed, exactly like a Fossil purchase in the Bone
	Market. There is no "purchase succeeded" message from client to server,
	because a client that could send one could send it without paying.
	═══════════════════════════════════════════════════════════════════════════

	═══ AN UNCONFIGURED ITEM SAYS SO ═══════════════════════════════════════════
	Every `AssetId` in `ProductConfig` is 0 until the live place exists. Rather
	than prompting with an id Roblox will reject, those rows render greyed and
	read COMING SOON. The store is therefore browsable and honest today, and
	becomes purchasable the moment ids are pasted in - with no code change.
	═══════════════════════════════════════════════════════════════════════════

	Depends on: StateController, UIController, InputController, HUDController,
	            Theme, Create, Widgets, ProductConfig, Net.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local Log = require(Shared.Modules.Log)
local Net = require(Shared.Modules.Net)
local ProductConfig = require(Shared.Config.ProductConfig)

local Client = script.Parent.Parent
local Create = require(Client.UI.Create)
local Theme = require(Client.UI.Theme)
local Widgets = require(Client.UI.Widgets)

local PurchaseController = {}

local StateController, UIController, InputController, HUDController

local player = Players.LocalPlayer

local root: Frame? = nil
local noticePanel: Frame? = nil
local banner: Frame? = nil
local thanksButton: TextButton? = nil
local rows: { any } = {}
local tabButtons: { [string]: TextButton } = {}
local activeTab = "passes"
local observers = {}

--- Who the Thanks button currently credits, and until when. Cleared by the
--- window expiring or by pressing it, so it can never be pressed twice.
local pendingThanks: { UserId: number, Until: number }? = nil
local bannerToken = 0

local ROW_HEIGHT = 96

local TABS = {
	{ Id = "passes", Label = "GAMEPASSES" },
	{ Id = "products", Label = "ITEMS" },
}

--[[
	The order the store lists things in lives in `ProductConfig`, not here: a
	hash table has no order, and an order the client owns cannot be checked
	against the catalogue, so a pass added without a listing would simply never
	appear for sale. ProductConfig asserts both lists cover it exactly once.
]]

-- ── Prompting ───────────────────────────────────────────────────────────────

--[[
	`Prompt*` yields on a network round trip and can throw if Roblox rejects
	the id, so it goes in a pcall on its own thread. A store button that
	freezes the UI thread is worse than one that quietly does nothing.
]]
local function prompt(kind: string, entry)
	if not ProductConfig.IsConfigured(entry) then
		HUDController.Flash("NOT AVAILABLE YET", Theme.Color.TextMuted, 2)
		return
	end

	task.spawn(function()
		local ok, err = pcall(function()
			if kind == "gamepass" then
				MarketplaceService:PromptGamePassPurchase(player, entry.AssetId)
			else
				MarketplaceService:PromptProductPurchase(player, entry.AssetId)
			end
		end)
		if not ok then
			Log.warn("PurchaseController", "Prompt failed for %s: %s", entry.Key, tostring(err))
			HUDController.Flash("STORE UNAVAILABLE", Theme.Color.Danger, 2)
		end
	end)
end

-- ── Rows ────────────────────────────────────────────────────────────────────

local function buildRow(kind: string, entry, parent: Instance, order: number)
	local name = Create("TextLabel", {
		Name = "Name",
		Size = UDim2.new(1, -190, 0, 22),
		Position = UDim2.fromOffset(Theme.Space.L, Theme.Space.M),
		BackgroundTransparency = 1,
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Label,
		TextColor3 = Theme.Color.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = entry.DisplayName,
	})

	local blurb = Create("TextLabel", {
		Name = "Blurb",
		Size = UDim2.new(1, -190, 0, 40),
		Position = UDim2.fromOffset(Theme.Space.L, 36),
		BackgroundTransparency = 1,
		Font = Theme.Font.Body,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Color.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Text = entry.Blurb or "",
	})

	local buy = Create("TextButton", {
		Name = "Buy",
		Size = UDim2.fromOffset(150, Theme.Size.MinTouchTarget),
		Position = UDim2.new(1, -Theme.Space.L, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = Theme.Color.Accent,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Label,
		TextColor3 = Theme.Color.TextOnAccent,
		Text = string.format("R$ %d", entry.Robux),
		Children = { Create("UICorner", { CornerRadius = Theme.Radius.Small }) },
		Events = { MouseButton1Click = function() prompt(kind, entry) end },
	})

	local panel = Widgets.Panel({
		Name = entry.Key,
		Size = UDim2.new(1, -8, 0, ROW_HEIGHT),
		Color = Theme.Color.Surface,
		LayoutOrder = order,
		--[[
			docs/07 §4: a server purchase is the one thing here that is
			supposed to make you popular. Marking it in the store is how a
			player finds out that is what it does before they buy it.
		]]
		StrokeColor = if entry.ServerWide then Theme.Color.Accent else Theme.Color.Outline,
		Children = { name, blurb, buy },
		Parent = parent,
	})

	local row = { Kind = kind, Entry = entry, Panel = panel, Buy = buy, Name = name }
	table.insert(rows, row)
	return row
end

local function refreshRow(row, data)
	local entry = row.Entry
	local owned = row.Kind == "gamepass" and (data.Gamepasses or {})[entry.Key] == true

	if owned then
		row.Buy.Text = "OWNED"
		row.Buy.BackgroundColor3 = Theme.Color.SurfaceRaised
		row.Buy.TextColor3 = Theme.Color.Success
		row.Buy.Active = false
	elseif not ProductConfig.IsConfigured(entry) then
		row.Buy.Text = "COMING SOON"
		row.Buy.BackgroundColor3 = Theme.Color.SurfaceRaised
		row.Buy.TextColor3 = Theme.Color.TextDim
		row.Buy.Active = false
	else
		row.Buy.Text = string.format("R$ %d", entry.Robux)
		row.Buy.BackgroundColor3 = Theme.Color.Accent
		row.Buy.TextColor3 = Theme.Color.TextOnAccent
		row.Buy.Active = true
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

-- ── Tabs ────────────────────────────────────────────────────────────────────

local function showTab(tabId: string)
	activeTab = tabId
	for id, button in tabButtons do
		local on = id == tabId
		button.BackgroundColor3 = if on then Theme.Color.Accent else Theme.Color.SurfaceRaised
		button.TextColor3 = if on then Theme.Color.TextOnAccent else Theme.Color.TextMuted
	end
	local wanted = if tabId == "passes" then "gamepass" else "product"
	for _, row in rows do
		row.Panel.Visible = row.Kind == wanted
	end
end

-- ── The honesty panel (docs/07 §1 rule 7) ───────────────────────────────────

local function dismissNotice()
	if noticePanel then
		noticePanel.Visible = false
	end
	--[[
		Written through the ordinary settings remote, which is validated
		against `GameConfig.SettingsSchema` like every other setting. The panel
		hides immediately rather than waiting for the round trip: it is a
		dismissal, and if the write is dropped the worst case is seeing an
		honest message once more.
	]]
	Net.FireServer("RequestSetSetting", "SeenStoreNotice", true)
end

local function buildNotice(parent: Instance)
	local body = Create("TextLabel", {
		Name = "Body",
		Size = UDim2.new(1, -Theme.Space.XL, 1, -110),
		Position = UDim2.fromOffset(Theme.Space.L, Theme.Space.XL),
		BackgroundTransparency = 1,
		Font = Theme.Font.Body,
		TextSize = Theme.TextSize.Body,
		TextColor3 = Theme.Color.Text,
		TextWrapped = true,
		Text = "You never need to spend Robux to get any dinosaur in this game."
			.. "\n\nEvery gamepass here makes something faster or roomier. None of them "
			.. "unlocks a species, a rarity or a zone you cannot reach by playing.",
	})

	local dismiss = Create("TextButton", {
		Name = "Dismiss",
		Size = UDim2.new(1, -Theme.Space.XL, 0, Theme.Size.MinTouchTarget),
		Position = UDim2.new(0.5, 0, 1, -Theme.Space.L),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = Theme.Color.Accent,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Label,
		TextColor3 = Theme.Color.TextOnAccent,
		Text = "GOT IT",
		Children = { Create("UICorner", { CornerRadius = Theme.Radius.Small }) },
		Events = { MouseButton1Click = dismissNotice },
	})

	noticePanel = Widgets.Panel({
		Name = "StoreNotice",
		Size = UDim2.fromOffset(420, 260),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Theme.Color.Backdrop,
		Transparency = 0,
		Radius = Theme.Radius.Large,
		ZIndex = Theme.Layer.Prompt,
		Visible = false,
		Children = {
			Create("TextLabel", {
				Name = "Title",
				Size = UDim2.new(1, -Theme.Space.XL, 0, 26),
				Position = UDim2.fromOffset(Theme.Space.L, Theme.Space.M),
				BackgroundTransparency = 1,
				Font = Theme.Font.Bold,
				TextSize = Theme.TextSize.Heading,
				TextColor3 = Theme.Color.Accent,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = "BEFORE YOU BROWSE",
			}),
			body,
			dismiss,
		},
		Parent = parent,
	})
end

-- ── The server-purchase banner (docs/07 §4) ─────────────────────────────────

local function hideBanner()
	pendingThanks = nil
	if banner then
		banner.Visible = false
	end
end

--[[
	A gold banner naming the buyer, with the one-tap Thanks beside it.

	The countdown is local because the window is: the server checks it again
	when the Thanks arrives, so a client that keeps the button on screen
	forever gets "too late" rather than a payment.
]]
local function showBanner(info)
	if not banner or not thanksButton then
		return
	end

	local isSelf = info.BuyerUserId == player.UserId
	local label = banner:FindFirstChild("Text") :: TextLabel?
	if label then
		label.Text = string.format("%s BOUGHT %s FOR EVERYONE",
			string.upper(info.BuyerName or "SOMEONE"),
			string.upper((ProductConfig.GetProduct(info.Product) or {}).DisplayName or "A BOOST"))
	end

	-- You cannot thank yourself, so the buyer gets the banner without a button.
	thanksButton.Visible = not isSelf
	thanksButton.Text = "THANKS!"
	thanksButton.BackgroundColor3 = Theme.Color.Accent
	thanksButton.TextColor3 = Theme.Color.TextOnAccent
	thanksButton.Active = not isSelf

	local window = tonumber(info.WindowSecs) or ProductConfig.ThanksWindowSecs
	pendingThanks = if isSelf then nil else { UserId = info.BuyerUserId, Until = os.clock() + window }
	banner.Visible = true

	bannerToken += 1
	local token = bannerToken
	task.delay(window, function()
		if bannerToken == token then
			hideBanner()
		end
	end)
end

local function sendThanks()
	local pending = pendingThanks
	if not pending or os.clock() > pending.Until then
		return
	end

	-- Cleared before the send, not after: the button cannot be double-tapped
	-- into two requests, which is what the server's rate limit would otherwise
	-- be absorbing.
	pendingThanks = nil
	if thanksButton then
		thanksButton.Text = "THANKED"
		thanksButton.BackgroundColor3 = Theme.Color.SurfaceRaised
		thanksButton.TextColor3 = Theme.Color.Success
		thanksButton.Active = false
	end

	Net.FireServer("RequestThanks", pending.UserId)
end

local function buildBanner(parent: Instance)
	thanksButton = Create("TextButton", {
		Name = "Thanks",
		Size = UDim2.fromOffset(140, 40),
		Position = UDim2.new(1, -Theme.Space.M, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = Theme.Color.Accent,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Color.TextOnAccent,
		Text = "THANKS!",
		ZIndex = Theme.Layer.Notification + 1,
		Children = { Create("UICorner", { CornerRadius = Theme.Radius.Small }) },
		Events = { MouseButton1Click = sendThanks },
	})

	banner = Widgets.Panel({
		Name = "ServerBoostBanner",
		Size = UDim2.new(0.7, 0, 0, 56),
		Position = UDim2.new(0.5, 0, 0, 96),
		AnchorPoint = Vector2.new(0.5, 0),
		Color = Theme.Color.AccentDark,
		Transparency = 0.05,
		Radius = Theme.Radius.Medium,
		StrokeColor = Theme.Color.Accent,
		ZIndex = Theme.Layer.Notification,
		Visible = false,
		Children = {
			Create("TextLabel", {
				Name = "Text",
				Size = UDim2.new(1, -170, 1, 0),
				Position = UDim2.fromOffset(Theme.Space.L, 0),
				BackgroundTransparency = 1,
				Font = Theme.Font.Bold,
				TextSize = Theme.TextSize.Label,
				TextColor3 = Theme.Color.Text,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextScaled = false,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Text = "",
				ZIndex = Theme.Layer.Notification + 1,
			}),
			thanksButton,
		},
		Parent = parent,
	})
end

-- ── Build ───────────────────────────────────────────────────────────────────

local function build()
	local screenLayer = UIController.Layer("screen")

	local title = Create("TextLabel", {
		Name = "Title",
		Size = UDim2.new(1, -Theme.Space.XL, 0, 30),
		Position = UDim2.fromOffset(Theme.Space.L, Theme.Space.L),
		BackgroundTransparency = 1,
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Heading,
		TextColor3 = Theme.Color.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "STORE",
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
		Events = { MouseButton1Click = function() UIController.Close("Store") end },
	})

	local tabs = Create("Frame", {
		Name = "Tabs",
		Size = UDim2.new(1, -Theme.Space.XL, 0, 40),
		Position = UDim2.fromOffset(Theme.Space.L, 56),
		BackgroundTransparency = 1,
		Children = { Widgets.Layout("horizontal", Theme.Space.S, Enum.HorizontalAlignment.Left) },
	})

	for _, tab in TABS do
		tabButtons[tab.Id] = Create("TextButton", {
			Name = tab.Id,
			Size = UDim2.fromOffset(160, 40),
			BackgroundColor3 = Theme.Color.SurfaceRaised,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Font = Theme.Font.Bold,
			TextSize = Theme.TextSize.Small,
			TextColor3 = Theme.Color.TextMuted,
			Text = tab.Label,
			Children = { Create("UICorner", { CornerRadius = Theme.Radius.Small }) },
			Events = { MouseButton1Click = function() showTab(tab.Id) end },
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
		Name = "StoreScreen",
		Size = UDim2.fromScale(0.92, 0.86),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Theme.Color.Backdrop,
		Transparency = 0.02,
		Radius = Theme.Radius.Large,
		ZIndex = Theme.Layer.Screen,
		Visible = false,
		Children = { title, close, tabs, list },
		Parent = screenLayer,
	})

	local order = 0
	for _, key in ProductConfig.PassOrder do
		local entry = ProductConfig.GetPass(key)
		if entry then
			order += 1
			buildRow("gamepass", entry, list, order)
		end
	end
	for _, key in ProductConfig.ProductOrder do
		local entry = ProductConfig.GetProduct(key)
		if entry then
			order += 1
			buildRow("product", entry, list, order)
		end
	end

	--[[
		Both of these live on the notification layer rather than inside the
		store: a server purchase must be visible to a player who is nowhere
		near the store, and the honesty panel has to sit above it.
	]]
	buildNotice(UIController.Layer("prompt"))
	buildBanner(UIController.Layer("notification"))

	showTab("passes")
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function PurchaseController.Init(app)
	StateController = app.Get("StateController")
	UIController = app.Get("UIController")
	InputController = app.Get("InputController")
	HUDController = app.Get("HUDController")
end

function PurchaseController.Start(_app)
	build()

	UIController.Register("Store", {
		Open = function()
			refreshAll()
			if root then
				root.Visible = true
			end

			-- docs/07 §1 rule 7: once, on the first open, before anything is
			-- for sale to them.
			local data = StateController.Get()
			if noticePanel and data and data.Settings and not data.Settings.SeenStoreNotice then
				noticePanel.Visible = true
			end
		end,
		Close = function()
			if root then
				root.Visible = false
			end
			if noticePanel then
				noticePanel.Visible = false
			end
		end,
	})

	InputController.Action:Connect(function(action, state)
		if action == "ToggleStore" and state == "Begin" then
			UIController.Toggle("Store")
		end
	end)

	-- A gamepass bought mid-session lands as a profile change, so the rows
	-- redraw from the same signal a Fossil purchase would use.
	table.insert(observers, StateController.Observe({ "Gamepasses" }, function()
		if root and root.Visible then
			refreshAll()
		end
	end))

	Net.On("ServerBoost", function(info)
		if type(info) ~= "table" then
			return
		end

		-- The buyer's own confirmation that someone pressed Thanks.
		if info.Kind == "thanked" then
			HUDController.Flash(
				string.format("%s SAYS THANKS", string.upper(tostring(info.FromName or "SOMEONE"))),
				Theme.Color.Accent, 2.5)
			return
		end

		showBanner(info)
	end)

	Log.info("PurchaseController", "Ready. %d gamepass(es), %d product(s), %d awaiting an id",
		ProductConfig.CountPasses(), ProductConfig.CountProducts(),
		(select(1, ProductConfig.Unconfigured()) + select(2, ProductConfig.Unconfigured())))
end

return PurchaseController
