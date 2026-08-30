--!nonstrict
--[[
	NotificationController
	.../SAD_Client/Controllers/NotificationController  (ModuleScript)

	The queue behind docs/08 §5's four severities, and the thing that stops a
	busy minute from becoming an unreadable one.

	═══ WHAT THE CLIENT OWNS, AND WHAT IT DOES NOT ═════════════════════════════
	It owns the QUEUE: how many of each severity fit on screen, what happens
	when a fifth takeover arrives, and which severities this player has muted.

	It does NOT own severity. Every entry originates from a server event and
	arrives already labelled; nothing here promotes a toast into a takeover.
	A client that could decide what was worth dimming the screen for is a
	client that can dim everyone's screen for nothing.
	═══════════════════════════════════════════════════════════════════════════

	docs/08 §5's rules, each implemented once:
	  * max 1 takeover at a time, others queue, max queue 3, then drop;
	  * banners never cover the action zone;
	  * a player's own park alerts cannot be muted.

	Depends on: StateController, UIController, HUDController, SoundController,
	            NotificationConfig, Theme, Create, Widgets, Net.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local Log = require(Shared.Modules.Log)
local Net = require(Shared.Modules.Net)
local NotificationConfig = require(Shared.Config.NotificationConfig)

local Client = script.Parent.Parent
local Create = require(Client.UI.Create)
local Theme = require(Client.UI.Theme)
local Widgets = require(Client.UI.Widgets)

local NotificationController = {}

local StateController, UIController, HUDController, SoundController

local toastHolder: Frame? = nil
local activeToasts = {}
local alertBar: Frame? = nil

--- Takeovers waiting their turn. Bounded by the severity's QueueLimit.
local takeoverQueue = {}
local takeoverBusy = false

--- [tag] = true while an alert with that tag is up, so Clear can find it.
local alerts = {}

--[[
	Which Settings key mutes which severity.

	Only the mutable ones appear: docs/08 §5 says a player's own park alerts
	cannot be muted, and a takeover is a once-a-week event that the game is
	built around. Missing from this table means "always shown".
]]
local MUTE_SETTING = {
	toast = nil, -- toasts are never noisy enough to be worth muting
	banner = "RareAnnouncements",
}

-- ── Muting ──────────────────────────────────────────────────────────────────

local function isMuted(payload): boolean
	local severity = NotificationConfig.Get(payload.Kind)
	if not severity or not severity.Mutable then
		return false
	end

	local key = MUTE_SETTING[payload.Kind]
	if not key then
		return false
	end

	--[[
		`Local = true` marks a notification about THIS player - their own
		hatch, their own park. Those are never muted by a setting about other
		people's announcements, which is what RareAnnouncements is.
	]]
	if payload.Local then
		return false
	end

	local data = StateController.Get()
	local settings = data and data.Settings
	return settings ~= nil and settings[key] == false
end

-- ── Toasts ──────────────────────────────────────────────────────────────────

local TOAST_HEIGHT = 52
local TOAST_WIDTH = 280

local function buildToastHolder()
	toastHolder = Create("Frame", {
		Name = "Toasts",
		-- Top-right, below the top bar, and narrow enough never to reach the
		-- action zone in the centre.
		Size = UDim2.fromOffset(TOAST_WIDTH, TOAST_HEIGHT * 4),
		Position = UDim2.new(1, -Theme.Space.L, 0, Theme.Size.TopBarHeight + Theme.Space.L),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Children = {
			Widgets.Layout("vertical", Theme.Space.S, Enum.HorizontalAlignment.Right),
		},
		Parent = UIController.Layer("notification"),
	})
end

local function showToast(payload)
	local severity = NotificationConfig.Get("toast")

	-- Oldest first: a toast that has been read is the one to lose.
	while #activeToasts >= severity.Concurrent do
		local oldest = table.remove(activeToasts, 1)
		if oldest then
			oldest:Destroy()
		end
	end

	local title = Create("TextLabel", {
		Name = "Title",
		Size = UDim2.new(1, -Theme.Space.XL, 0, 20),
		Position = UDim2.fromOffset(Theme.Space.M, Theme.Space.S),
		BackgroundTransparency = 1,
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Small,
		TextColor3 = payload.Color or Theme.Color.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = payload.Title or payload.Text or "",
	})

	local subtitle = Create("TextLabel", {
		Name = "Subtitle",
		Size = UDim2.new(1, -Theme.Space.XL, 0, 18),
		Position = UDim2.fromOffset(Theme.Space.M, 28),
		BackgroundTransparency = 1,
		Font = Theme.Font.Body,
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = Theme.Color.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = payload.Subtitle or "",
		Visible = payload.Subtitle ~= nil,
	})

	local panel = Widgets.Panel({
		Name = "Toast",
		Size = UDim2.fromOffset(TOAST_WIDTH, TOAST_HEIGHT),
		Color = Theme.Color.SurfaceRaised,
		Children = { title, subtitle },
		Parent = toastHolder,
	})

	table.insert(activeToasts, panel)

	-- Slides in from the right edge it lives on.
	panel.Position = UDim2.fromOffset(TOAST_WIDTH, 0)
	TweenService:Create(panel, TweenInfo.new(Theme.Duration.Fast, Theme.Easing.Bounce), {
		Position = UDim2.fromOffset(0, 0),
	}):Play()

	task.delay(payload.Duration or NotificationConfig.Get("toast").Duration, function()
		local index = table.find(activeToasts, panel)
		if index then
			table.remove(activeToasts, index)
		end
		panel:Destroy()
	end)
end

-- ── Takeovers ───────────────────────────────────────────────────────────────

--[[
	One at a time. docs/08 §5: "max 1 takeover at a time (others queue, max
	queue 3, then drop)".

	Dropping rather than growing is the point. A player who has just had five
	Titans announced at them does not want to watch a queue for twenty seconds;
	they want to keep playing, and the game will tell them about the next one.
]]
local function pumpTakeovers()
	if takeoverBusy then
		return
	end

	local payload = table.remove(takeoverQueue, 1)
	if not payload then
		return
	end

	takeoverBusy = true
	local duration = payload.Duration or NotificationConfig.Get("takeover").Duration

	HUDController.ShowReveal({
		Title = payload.Title or payload.Text or "",
		Subtitle = payload.Subtitle,
		Headline = payload.Headline,
		Color = payload.Color,
		Duration = duration,
	})

	task.delay(duration, function()
		takeoverBusy = false
		pumpTakeovers()
	end)
end

local function showTakeover(payload)
	local limit = NotificationConfig.Get("takeover").QueueLimit
	if #takeoverQueue >= limit then
		Log.debug("NotificationController", "Takeover queue full (%d) - dropping", limit)
		return
	end

	table.insert(takeoverQueue, payload)
	pumpTakeovers()
end

-- ── Alerts ──────────────────────────────────────────────────────────────────

local function buildAlertBar()
	local label = Create("TextLabel", {
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Label,
		TextColor3 = Theme.Color.Text,
		Text = "",
	})

	alertBar = Widgets.Panel({
		Name = "Alert",
		--[[
			Full width at the very top, above the top bar. Deliberately not
			centred: docs/08 §5 says banners never cover the action zone, and
			an alert that stays up until resolved must not cover it either.
		]]
		Size = UDim2.new(1, -Theme.Space.XL, 0, 40),
		Position = UDim2.new(0.5, 0, 0, Theme.Space.S),
		AnchorPoint = Vector2.new(0.5, 0),
		Color = Theme.Color.Danger,
		Transparency = 0.1,
		Visible = false,
		Children = { label },
		Parent = UIController.Layer("notification"),
	})
end

local function pulseAlert()
	if not alertBar then
		return
	end
	local tween = TweenService:Create(alertBar,
		TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ BackgroundTransparency = 0.45 })
	tween:Play()
	return tween
end

local alertTween = nil

local function showAlert(payload)
	if not alertBar then
		return
	end

	alerts[payload.Tag or "alert"] = true
	alertBar.Label.Text = payload.Text or ""
	alertBar.Visible = true

	if not alertTween then
		alertTween = pulseAlert()
	end

	--[[
		Duration 0 means "until resolved" (NotificationConfig.UntilResolved).
		A caller that sends a duration gets a self-clearing alert, which is
		what a raid uses: the raid ends whether or not anyone clears it.
	]]
	local duration = payload.Duration or 0
	if duration > 0 then
		task.delay(duration, function()
			NotificationController.Clear(payload.Tag or "alert")
		end)
	end
end

function NotificationController.Clear(tag: string)
	alerts[tag] = nil

	if next(alerts) == nil and alertBar then
		alertBar.Visible = false
		if alertTween then
			alertTween:Cancel()
			alertTween = nil
		end
		alertBar.BackgroundTransparency = 0.1
	end
end

-- ── Dispatch ────────────────────────────────────────────────────────────────

local HANDLERS = {
	toast = showToast,
	banner = function(payload)
		HUDController.Flash(payload.Text or payload.Title or "", payload.Color,
			payload.Duration or NotificationConfig.Get("banner").Duration)
	end,
	takeover = showTakeover,
	alert = showAlert,
}

function NotificationController.Handle(payload)
	if type(payload) ~= "table" then
		return
	end

	if payload.Kind == "clear" then
		NotificationController.Clear(payload.Tag or "alert")
		return
	end

	--[[
		Sanitised again on arrival. The server sanitises on the way out, but
		this is the boundary that actually protects the queue - and it costs a
		table walk on a message that arrives a few times a minute.
	]]
	local clean = NotificationConfig.Sanitise(payload)
	if not clean then
		return
	end
	-- Colour survives sanitising as a Color3, which is not a scalar.
	clean.Color = payload.Color

	if isMuted(clean) then
		return
	end

	local handler = HANDLERS[clean.Kind]
	if handler then
		handler(clean)
		SoundController.PlayNotification(clean.Kind)
	end
end

--- How many takeovers are waiting. Read by the Studio test in SETUP.md.
function NotificationController.GetQueueDepth(): number
	return #takeoverQueue
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function NotificationController.Init(app)
	StateController = app.Get("StateController")
	UIController = app.Get("UIController")
	HUDController = app.Get("HUDController")
	SoundController = app.Get("SoundController")
end

function NotificationController.Start(_app)
	buildToastHolder()
	buildAlertBar()

	Net.On("Notify", NotificationController.Handle)

	Log.info("NotificationController", "Ready. %d severities", #NotificationConfig.Order)
end

return NotificationController
