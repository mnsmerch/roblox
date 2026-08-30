--!nonstrict
--[[
	HUDController
	StarterPlayerScripts/SAD_Client/Controllers/HUDController  (ModuleScript)

	The persistent interface: top bar, side rails, bottom bar, action prompt.
	Mirrors the screen map in docs/08 §2.

	Everything binds through StateController.Observe, so nothing here polls and
	nothing here holds a copy of game state. A counter updates because the
	server said so, or it does not update.

	Progressive disclosure (docs/08 §2.1): DNA, the rebirth badge and the shield
	timer stay hidden until they mean something. A brand-new player sees one
	currency and five buttons, which is the whole interface they need in their
	first two minutes.

	Icons are emoji placeholders. Step 24 swaps in real assets; the layout does
	not change when it does.

	API:
		HUDController.SetAction(text?, progress?)   -- the contextual prompt
		HUDController.SetChaseMode(active)          -- Step 9 strips the HUD
		HUDController.SetCompass(text?)             -- Step 6
		HUDController.SetEventBanner(text?)         -- Step 18
		HUDController.OnStealAlert(info)            -- Step 15 raid alerts

	Depends on: UIController, StateController, InputController, Theme, Create,
	            Widgets, Format.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local RarityConfig = require(Shared.Config.RarityConfig)
local Format = require(Shared.Modules.Format)
local Log = require(Shared.Modules.Log)
local Net = require(Shared.Modules.Net)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Widgets = require(UI.Widgets)

local HUDController = {}

local UIController, StateController, InputController

local hud
local topBar, leftRail, rightRail, bottomBar
local chips = {}
local buttons = {}
local actionPrompt
local carryPanel
local chaseBanner, chaseVignette
local flashPanel
local flashToken = 0
local hatchPanel
local hatchToken = 0
local compass, eventBanner
local railToggle

--- Bottom bar, left to right (docs/08 §2.2).
local BOTTOM_BUTTONS = {
	{ Id = "Park", Icon = "🏠", Label = "PARK", Action = "ToggleParkMenu" },
	{ Id = "Eggs", Icon = "🥚", Label = "EGGS", Action = "ToggleEggs" },
	{ Id = "Dinos", Icon = "🦖", Label = "DINOS", Action = "ToggleDinos" },
	{ Id = "Shop", Icon = "🛒", Label = "SHOP", Action = "ToggleShop" },
	{ Id = "Teleport", Icon = "🚀", Label = "GO", Action = "ToggleTeleport" },
}

local LEFT_RAIL = {
	{ Id = "Daily", Icon = "🎁", Action = "ToggleDaily" },
	{ Id = "Quests", Icon = "✅", Action = "ToggleQuests" },
	{ Id = "Index", Icon = "📖", Action = "ToggleIndex" },
	{ Id = "Settings", Icon = "⚙️", Action = "ToggleSettings" },
}

local RIGHT_RAIL = {
	{ Id = "Weather", Icon = "⛅", Action = "ToggleWeather" },
	{ Id = "Leaders", Icon = "🏆", Action = "ToggleLeaderboards" },
	{ Id = "Friends", Icon = "👥", Action = "ToggleFriends" },
	{ Id = "Map", Icon = "🗺️", Action = "ToggleMap" },
}

-- ── Construction ────────────────────────────────────────────────────────────

local function buildTopBar()
	topBar = Create("Frame", {
		Name = "TopBar",
		Size = UDim2.new(1, 0, 0, Theme.Size.TopBarHeight),
		Position = UDim2.fromOffset(0, Theme.Space.S),
		BackgroundTransparency = 1,
		ZIndex = Theme.Layer.Hud,
		Children = { Widgets.Layout("horizontal", Theme.Space.S) },
		Parent = hud,
	})

	chips.Fossils = Widgets.Chip({
		Name = "FossilsChip", Icon = "🦴", IconColor = Theme.Color.Accent,
		Width = 128, Text = "0", LayoutOrder = 1, Parent = topBar,
	})

	-- Hidden until the player has any. A new player should see one currency.
	chips.DNA = Widgets.Chip({
		Name = "DnaChip", Icon = "🧬", IconColor = Theme.Color.Dna,
		Width = 104, Text = "0", LayoutOrder = 2, Visible = false, Parent = topBar,
	})

	chips.Rebirth = Widgets.Chip({
		Name = "RebirthChip", Icon = "⭐", IconColor = Theme.Color.Rebirth,
		Width = 74, Text = "0", LayoutOrder = 3, Visible = false, Parent = topBar,
	})

	chips.Shield = Widgets.Chip({
		Name = "ShieldChip", Icon = "🛡️", IconColor = Theme.Color.Shield,
		Width = 104, Text = "", LayoutOrder = 4, Visible = false, Parent = topBar,
	})
end

local function buildCompass()
	-- Populated in Step 6, once a park exists to point at.
	compass = Create("TextLabel", {
		Name = "Compass",
		Size = UDim2.new(0, 260, 0, 22),
		Position = UDim2.new(0.5, 0, 0, Theme.Size.TopBarHeight + Theme.Space.M),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Color.TextMuted,
		Text = "",
		Visible = false,
		ZIndex = Theme.Layer.Hud,
		Parent = hud,
	})
end

local function buildEventBanner()
	-- Populated in Step 18.
	eventBanner = Widgets.Panel({
		Name = "EventBanner",
		Size = UDim2.new(0, 420, 0, 40),
		Position = UDim2.new(0.5, 0, 0, Theme.Size.TopBarHeight + 40),
		AnchorPoint = Vector2.new(0.5, 0),
		Color = Theme.Color.SurfaceRaised,
		StrokeColor = Theme.Color.Warning,
		Visible = false,
		ZIndex = Theme.Layer.Hud,
		Children = {
			Create("TextLabel", {
				Name = "Label",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Font = Theme.Font.Display,
				TextSize = Theme.TextSize.Label,
				TextColor3 = Theme.Color.Warning,
				Text = "",
				ZIndex = Theme.Layer.Hud + 1,
			}),
		},
		Parent = hud,
	})
end

local function buildRail(name: string, entries, side: string)
	local rail = Create("Frame", {
		Name = name,
		Size = UDim2.fromOffset(Theme.Size.RailButton, #entries * (Theme.Size.RailButton + Theme.Space.S)),
		Position = if side == "left"
			then UDim2.new(0, Theme.Space.M, 0.5, 0)
			else UDim2.new(1, -Theme.Space.M, 0.5, 0),
		AnchorPoint = if side == "left" then Vector2.new(0, 0.5) else Vector2.new(1, 0.5),
		BackgroundTransparency = 1,
		ZIndex = Theme.Layer.Hud,
		Children = { Widgets.Layout("vertical", Theme.Space.S) },
		Parent = hud,
	})

	for order, entry in entries do
		Widgets.RailButton({
			Name = entry.Id,
			Icon = entry.Icon,
			LayoutOrder = order,
			Parent = rail,
			OnActivated = function()
				InputController.Fire(entry.Action)
			end,
		})
	end

	return rail
end

local function buildBottomBar()
	--[[
		Capped width and centred. Stretching five buttons across a 4K monitor
		puts them further apart than a mouse wants and further apart than a
		thumb can reach on the tablets that share this layout.
	]]
	bottomBar = Create("Frame", {
		Name = "BottomBar",
		Size = UDim2.new(1, -Theme.Space.XL, 0, Theme.Size.BottomButtonHeight),
		Position = UDim2.new(0.5, 0, 1, -Theme.Space.M),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		ZIndex = Theme.Layer.Hud,
		Children = {
			Create("UISizeConstraint", { MaxSize = Vector2.new(760, math.huge) }),
			Widgets.Layout("horizontal", Theme.Space.S),
		},
		Parent = hud,
	})

	for order, entry in BOTTOM_BUTTONS do
		buttons[entry.Id] = Widgets.BottomButton({
			Name = entry.Id,
			Icon = entry.Icon,
			Label = entry.Label,
			LayoutOrder = order,
			Size = UDim2.new(0.2, -Theme.Space.S, 1, 0),
			Parent = bottomBar,
			OnActivated = function()
				InputController.Fire(entry.Action)
			end,
		})
	end
end

local function buildActionPrompt()
	actionPrompt = Widgets.ActionPrompt({
		Position = UDim2.new(0.5, 0, 1, -(Theme.Size.BottomBarHeight + Theme.Space.L)),
		AnchorPoint = Vector2.new(0.5, 1),
		ZIndex = Theme.Layer.Prompt,
		Parent = UIController.Layer("prompt"),
	})
end

--[[
	The carry readout: what you are holding and how far you are from safety.

	Sits above the action prompt because during a run it is the only thing that
	matters (docs/08 §2.3). Rarity is coloured, so a Mythic carry is legible at
	a glance without reading the word.
]]
local function buildCarryPanel()
	local rarityLabel = Create("TextLabel", {
		Name = "Rarity",
		Size = UDim2.new(1, -Theme.Space.L, 0, 26),
		Position = UDim2.fromOffset(Theme.Space.M, 6),
		BackgroundTransparency = 1,
		Font = Theme.Font.Display,
		TextSize = Theme.TextSize.Label,
		TextColor3 = Theme.Color.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		ZIndex = Theme.Layer.Prompt + 1,
	})

	local distanceLabel = Create("TextLabel", {
		Name = "Distance",
		Size = UDim2.new(1, -Theme.Space.L, 0, 20),
		Position = UDim2.fromOffset(Theme.Space.M, 30),
		BackgroundTransparency = 1,
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Color.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		ZIndex = Theme.Layer.Prompt + 1,
	})

	carryPanel = Widgets.Panel({
		Name = "CarryPanel",
		Size = UDim2.new(0, 300, 0, 58),
		Position = UDim2.new(0.5, 0, 1, -(Theme.Size.BottomBarHeight + Theme.Size.ActionPromptHeight + Theme.Space.XL)),
		AnchorPoint = Vector2.new(0.5, 1),
		Color = Theme.Color.SurfaceRaised,
		Transparency = 0.05,
		StrokeColor = Theme.Color.Accent,
		Visible = false,
		ZIndex = Theme.Layer.Prompt,
		Children = { rarityLabel, distanceLabel },
		Parent = UIController.Layer("prompt"),
	})

	carryPanel.Rarity = rarityLabel
	carryPanel.Distance = distanceLabel
end

--[[
	The chase readout: a red tint and one loud line.

	During a chase the HUD strips down to what a running player can actually
	use (docs/00 §6). The vignette pulses with proximity rather than sitting
	still, because a static red overlay stops being information after a second.
]]
local function buildChase()
	chaseVignette = Create("Frame", {
		Name = "ChaseVignette",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Color.Danger,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = Theme.Layer.Hud - 1,
		Parent = hud,
	})

	local label = Create("TextLabel", {
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Theme.Font.Display,
		TextSize = Theme.TextSize.Display,
		TextColor3 = Theme.Color.Text,
		Text = "",
		ZIndex = Theme.Layer.Prompt + 2,
	})

	chaseBanner = Widgets.Panel({
		Name = "ChaseBanner",
		Size = UDim2.new(0, 460, 0, 54),
		Position = UDim2.new(0.5, 0, 0, Theme.Size.TopBarHeight + Theme.Space.XXL),
		AnchorPoint = Vector2.new(0.5, 0),
		Color = Theme.Color.Danger,
		Transparency = 0.2,
		StrokeColor = Theme.Color.Danger,
		Visible = false,
		ZIndex = Theme.Layer.Prompt + 1,
		Children = { label },
		Parent = UIController.Layer("prompt"),
	})

	chaseBanner.Label = label
end

--[[
	A transient centre banner: SAFE!, storage full, and anything else that needs
	to be read in one glance mid-run.

	Deliberately minimal. Step 16's NotificationController replaces this with
	the proper queue, severities and cross-server takeovers - but without
	something here, banking an egg produces no feedback at all and the run has
	no ending.
]]
local function buildFlash()
	local label = Create("TextLabel", {
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Theme.Font.Display,
		TextSize = Theme.TextSize.Display,
		TextColor3 = Theme.Color.Text,
		Text = "",
		ZIndex = Theme.Layer.Notification + 1,
	})

	flashPanel = Widgets.Panel({
		Name = "Flash",
		Size = UDim2.new(0, 420, 0, 62),
		Position = UDim2.fromScale(0.5, 0.34),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Theme.Color.SurfaceRaised,
		Transparency = 0.05,
		StrokeColor = Theme.Color.Accent,
		Visible = false,
		ZIndex = Theme.Layer.Notification,
		Children = { label },
		Parent = UIController.Layer("notification"),
	})

	flashPanel.Label = label
end

--[[
	The hatch reveal.

	Three lines because there are three reveals, and they are what the entire
	loop exists to deliver: what it is, what mutated it, and how unlikely that
	was. The odds line is the part players screenshot, so it is rendered large
	and read from the same weight tables the roll actually used.

	Step 16 replaces this with the full takeover treatment - camera cut, sound
	sting, cross-server broadcast. This is the honest version of it.
]]
local function buildHatch()
	local title = Create("TextLabel", {
		Name = "Title",
		Size = UDim2.new(1, -Theme.Space.XL, 0, 40),
		Position = UDim2.fromOffset(Theme.Space.L, 14),
		BackgroundTransparency = 1,
		Font = Theme.Font.Display,
		TextSize = Theme.TextSize.Display,
		TextColor3 = Theme.Color.Text,
		TextScaled = true,
		Text = "",
		ZIndex = Theme.Layer.Takeover + 1,
	})

	local subtitle = Create("TextLabel", {
		Name = "Subtitle",
		Size = UDim2.new(1, -Theme.Space.XL, 0, 24),
		Position = UDim2.fromOffset(Theme.Space.L, 58),
		BackgroundTransparency = 1,
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Label,
		TextColor3 = Theme.Color.TextMuted,
		Text = "",
		ZIndex = Theme.Layer.Takeover + 1,
	})

	local odds = Create("TextLabel", {
		Name = "Odds",
		Size = UDim2.new(1, -Theme.Space.XL, 0, 30),
		Position = UDim2.fromOffset(Theme.Space.L, 86),
		BackgroundTransparency = 1,
		Font = Theme.Font.Display,
		TextSize = Theme.TextSize.Heading,
		TextColor3 = Theme.Color.Accent,
		Text = "",
		ZIndex = Theme.Layer.Takeover + 1,
	})

	hatchPanel = Widgets.Panel({
		Name = "HatchReveal",
		Size = UDim2.new(0, 480, 0, 130),
		Position = UDim2.fromScale(0.5, 0.4),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Theme.Color.Backdrop,
		Transparency = 0.02,
		StrokeColor = Theme.Color.Accent,
		Visible = false,
		ZIndex = Theme.Layer.Takeover,
		Children = { title, subtitle, odds },
		Parent = UIController.Layer("takeover"),
	})

	hatchPanel.Title = title
	hatchPanel.Subtitle = subtitle
	hatchPanel.Odds = odds
end

local function buildRailToggle()
	-- Below RailCollapseWidth the left rail folds behind one button
	-- (docs/08 §4). Four extra icons is exactly what a 5.5" screen cannot
	-- afford next to a thumb.
	railToggle = Widgets.RailButton({
		Name = "RailToggle",
		Icon = "☰",
		Parent = hud,
		OnActivated = function()
			leftRail.Visible = not leftRail.Visible
		end,
	})
	railToggle.Position = UDim2.new(0, Theme.Space.M, 0, Theme.Size.TopBarHeight + Theme.Space.XL)
	railToggle.Visible = false
end

-- ── State binding ───────────────────────────────────────────────────────────

local shieldTicker = nil

local function bindState()
	local firstFossils = true
	StateController.Observe({ "Fossils" }, function(value)
		local amount = tonumber(value) or 0
		Widgets.SetNumber(chips.Fossils.Value, amount, Format.Number, firstFossils)
		firstFossils = false
	end)

	StateController.Observe({ "DNA" }, function(value)
		local amount = tonumber(value) or 0
		chips.DNA.Instance.Visible = amount > 0
		Widgets.SetNumber(chips.DNA.Value, amount, Format.Number)
	end)

	StateController.Observe({ "Rebirths" }, function(value)
		local count = tonumber(value) or 0
		chips.Rebirth.Instance.Visible = count > 0
		chips.Rebirth.Value.Text = "R" .. count
	end)

	StateController.Observe({ "Eggs" }, function(eggs)
		local count = 0
		if type(eggs) == "table" then
			for _ in eggs do
				count += 1
			end
		end
		buttons.Eggs.SetBadge(count)
	end)

	--[[
		The shield chip counts down in real time, so it needs a ticker - but
		only while a shield is actually running. An idle HUD should not hold a
		second-by-second loop for something that is off.
	]]
	StateController.Observe({ "ShieldUntil" }, function(value)
		local expiry = tonumber(value) or 0

		if shieldTicker then
			task.cancel(shieldTicker)
			shieldTicker = nil
		end

		if expiry <= os.time() then
			chips.Shield.Instance.Visible = false
			return
		end

		chips.Shield.Instance.Visible = true
		shieldTicker = task.spawn(function()
			while os.time() < expiry do
				chips.Shield.Value.Text = Format.Clock(expiry - os.time())
				task.wait(1)
			end
			chips.Shield.Instance.Visible = false
			shieldTicker = nil
		end)
	end)
end

-- ── Responsive ──────────────────────────────────────────────────────────────

local function applyBreakpoint(breakpoint: string, logicalWidth: number)
	local collapse = Theme.ShouldCollapseRail(logicalWidth)

	railToggle.Visible = collapse
	leftRail.Visible = not collapse

	-- The right rail is informational. In compact layouts the minimap is
	-- tap-to-expand and the rest belongs behind the menu (docs/08 §4).
	rightRail.Visible = breakpoint ~= "compact"

	-- Nothing crowds the action prompt on a short screen.
	compass.Visible = compass.Text ~= "" and breakpoint ~= "compact"
end

-- ── Public API ──────────────────────────────────────────────────────────────

--- The contextual prompt. nil text hides it. Step 8 and Step 15 drive this.
function HUDController.SetAction(text: string?, progress: number?)
	actionPrompt.Set(text, progress)
end

--[[
	Chase mode. docs/00 §6: nothing may block the chase, so menus close and the
	HUD strips down to what a running player needs. Step 9 calls this.
]]
function HUDController.SetChaseMode(active: boolean)
	UIController.CloseAll()
	leftRail.Visible = not active and leftRail.Visible
	rightRail.Visible = not active and rightRail.Visible
	bottomBar.Visible = not active

	if not active then
		applyBreakpoint(UIController.Breakpoint, UIController.LogicalWidth)
	end
end

--[[
	Shows or hides the carry readout.

	`info` nil hides it. Otherwise: { Rarity, RarityColor, Count, Distance }.
	EggCarryController drives this; nothing here knows what an egg is.
]]
function HUDController.SetCarry(info)
	if not info then
		carryPanel.Visible = false
		return
	end

	carryPanel.Visible = true

	local suffix = if info.Count and info.Count > 1 then string.format("  x%d", info.Count) else ""
	carryPanel.Rarity.Text = string.format("🥚 %s EGG%s", string.upper(info.Rarity or "?"), suffix)
	carryPanel.Rarity.TextColor3 = info.RarityColor or Theme.Color.Text

	if info.Distance then
		carryPanel.Distance.Text = string.format("↑ %d studs to your park", math.floor(info.Distance))
	else
		carryPanel.Distance.Text = "Get to your park!"
	end
end

--[[
	Shows or hides the chase readout.

	`info` nil ends it. Otherwise: { DisplayName, Caught }. Also strips the HUD,
	because nothing may block a chase.
]]
function HUDController.SetChase(info)
	if not info then
		chaseBanner.Visible = false
		chaseVignette.Visible = false
		HUDController.SetChaseMode(false)
		return
	end

	HUDController.SetChaseMode(true)
	chaseBanner.Visible = true
	chaseVignette.Visible = true

	if info.Caught then
		chaseBanner.Label.Text = "CAUGHT!"
	else
		chaseBanner.Label.Text = string.format("RUN! %s", string.upper(info.DisplayName or "SOMETHING"))
	end
end

--- Pulse strength for the chase vignette, 0 (far) to 1 (about to be caught).
function HUDController.SetChaseProximity(fraction: number)
	if not chaseVignette.Visible then
		return
	end
	-- Never fully opaque: the player still has to see where they are running.
	chaseVignette.BackgroundTransparency = 0.95 - math.clamp(fraction, 0, 1) * 0.25
end

--- Shows `text` for `duration` seconds. A later call replaces an earlier one
--- rather than queueing, so the most recent thing is always what is readable.
function HUDController.Flash(text: string, color: Color3?, duration: number?)
	flashToken += 1
	local token = flashToken

	flashPanel.Visible = true
	flashPanel.Label.Text = text
	flashPanel.Label.TextColor3 = color or Theme.Color.Text

	local stroke = flashPanel:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color or Theme.Color.Accent
	end

	task.delay(duration or 2.5, function()
		-- Only the most recent flash may hide the panel.
		if flashToken == token then
			flashPanel.Visible = false
		end
	end)
end

--[[
	The three-line reveal panel: what it is, what it means, and the big number.

	Used by hatches and by the offline-earnings summary, because both are the
	same shape of moment - something happened, here is how much it was worth.
]]
function HUDController.ShowReveal(info)
	if type(info) ~= "table" then
		return
	end

	hatchToken += 1
	local token = hatchToken

	local color = info.Color or Theme.Color.Accent

	hatchPanel.Visible = true
	hatchPanel.Title.Text = info.Title or ""
	hatchPanel.Title.TextColor3 = color
	hatchPanel.Subtitle.Text = info.Subtitle or ""
	hatchPanel.Odds.Text = info.Headline or ""
	hatchPanel.Odds.TextColor3 = color

	local stroke = hatchPanel:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color
	end

	task.delay(info.Duration or 3, function()
		if hatchToken == token then
			hatchPanel.Visible = false
		end
	end)
end

--[[
	Shows a hatch result. `result` is the HatchResult payload.

	Rarer hatches linger longer - a Common should not hold the screen as long as
	a Void Titan Rex, and the duration is part of how the tier reads.
]]
function HUDController.ShowHatch(result)
	if type(result) ~= "table" then
		return
	end

	local tier = RarityConfig.Tiers[result.Rarity]
	local rank = tier and tier.Rank or 1

	local parts = { tier and string.upper(tier.DisplayName) or "?" }
	if result.Mutation2 then
		table.insert(parts, "PRIME")
	end
	if result.IncomePerSec then
		table.insert(parts, Format.Number(result.IncomePerSec) .. " Fossils/sec")
	end

	HUDController.ShowReveal({
		Title = string.upper(result.DisplayName or "?"),
		Subtitle = table.concat(parts, "  ·  "),
		-- The mutation's odds beat the rarity's when there is one: a Galaxy
		-- Compsognathus is a rarer event than the Compsognathus was.
		Headline = result.MutationOdds or result.Odds or "",
		Color = RarityConfig.GetColor(result.Rarity),
		Duration = 2.5 + math.min(rank, 9) * 0.4,
	})
end

--[[
	Raid alerts (docs/03 §4). Every one of these is a moment where the player
	needs to know something RIGHT NOW - someone is in your park, someone has
	your Mythic, you have been tagged - so they all land on the flash banner or
	the reveal panel rather than in a menu.

	Purely a renderer: every decision behind these has already been made and
	enforced on the server, and nothing here is sent back.
]]
local STEAL_ALERTS = {
	intruder = function(info)
		HUDController.Flash(string.upper(info.ThiefName or "SOMEONE") .. " IS IN YOUR PARK!",
			Theme.Color.Warning, 3)
	end,
	raidStarted = function(info)
		HUDController.Flash(string.format("%s IS TAKING YOUR %s!",
			string.upper(info.ThiefName or "SOMEONE"), string.upper(info.DinoName or "DINOSAUR")),
			Theme.Color.Danger, math.max(3, info.Seconds or 3))
	end,
	lifted = function(info)
		HUDController.Flash(string.format("TAG %s TO GET IT BACK",
			string.upper(info.ThiefName or "THEM")), Theme.Color.Danger, 4)
	end,
	carrying = function(info)
		HUDController.SetChaseMode(true)
		HUDController.Flash("GET TO YOUR GATE", Theme.Color.Accent, 3)
	end,
	tagged = function(info)
		HUDController.SetChaseMode(false)
		HUDController.Flash(if info.Source == "tower" then "GUARD TOWER GOT YOU" else "TAGGED!",
			Theme.Color.Danger, 3)
	end,
	towerFired = function(info)
		HUDController.Flash("YOUR GUARD TOWER TAGGED " .. string.upper(info.ThiefName or "THEM"),
			Theme.Color.Success, 3)
	end,
	returned = function(info)
		HUDController.Flash(string.upper(info.DinoName or "IT") .. " CAME HOME",
			Theme.Color.Success, 3)
	end,
	stolen = function(info)
		HUDController.SetChaseMode(false)
		HUDController.ShowReveal({
			Title = "STOLEN",
			Subtitle = string.upper(info.DinoName or ""),
			Headline = "IT IS YOURS",
			Color = RarityConfig.GetColor(info.Rarity or "common"),
			Duration = 3,
		})
	end,
	robbed = function(info)
		HUDController.ShowReveal({
			Title = "ROBBED",
			Subtitle = string.format("%s took your %s",
				info.ThiefName or "Someone", info.DinoName or "dinosaur"),
			Headline = "+" .. Format.Number(info.Insurance or 0) .. " INSURANCE",
			Color = Theme.Color.Danger,
			Duration = 4,
		})
	end,
	mercy = function(info)
		HUDController.Flash(string.format("MERCY SHIELD  ·  %s", Format.Time(info.Seconds or 0)),
			Theme.Color.Shield, 4)
	end,
	failed = function(info)
		HUDController.SetChaseMode(false)
		HUDController.Flash(string.upper(info.Reason or "IT GOT AWAY"), Theme.Color.Danger, 3)
	end,
	refused = function(info)
		HUDController.Flash(string.upper(info.Reason or "NOT NOW"), Theme.Color.TextMuted, 2)
	end,
	holdStarted = function() end,
	holdEnded = function() end,
}

function HUDController.OnStealAlert(info)
	if type(info) ~= "table" then
		return
	end
	local handler = STEAL_ALERTS[info.Kind]
	if handler then
		handler(info)
	end
end

function HUDController.SetCompass(text: string?)
	compass.Text = text or ""
	compass.Visible = text ~= nil and UIController.Breakpoint ~= "compact"
end

function HUDController.SetEventBanner(text: string?)
	eventBanner.Visible = text ~= nil
	if text then
		eventBanner.Label.Text = text
	end
end

function HUDController.GetButton(id: string)
	return buttons[id]
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function HUDController.Init(app)
	UIController = app.Get("UIController")
	StateController = app.Get("StateController")
	InputController = app.Get("InputController")

	hud = UIController.Layer("hud")

	buildTopBar()
	buildCompass()
	buildEventBanner()
	leftRail = buildRail("LeftRail", LEFT_RAIL, "left")
	rightRail = buildRail("RightRail", RIGHT_RAIL, "right")
	buildBottomBar()
	buildRailToggle()
	buildActionPrompt()
	buildCarryPanel()
	buildChase()
	buildFlash()
	buildHatch()

	Log.info("HUDController", "HUD built")
end

function HUDController.Start(app)
	bindState()

	Net.On("StealAlert", HUDController.OnStealAlert)

	UIController.BreakpointChanged:Connect(applyBreakpoint)
	applyBreakpoint(UIController.Breakpoint, UIController.LogicalWidth)

	-- Keyboard and gamepad reach the same buttons the touch UI does.
	InputController.Action:Connect(function(action, state)
		if state ~= "Begin" then
			return
		end
		if action == "Close" then
			UIController.CloseAll()
		end
	end)

	Log.info("HUDController", "HUD live")
end

return HUDController
