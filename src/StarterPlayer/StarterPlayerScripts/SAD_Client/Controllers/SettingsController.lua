--!nonstrict
--[[
	SettingsController
	.../SAD_Client/Controllers/SettingsController  (ModuleScript)

	docs/06 §8's settings menu, plus the two things Low Graphics mode actually
	has to do that no other controller owns.

	═══ THE MENU IS GENERATED FROM THE SCHEMA ══════════════════════════════════
	Every row is built from `GameConfig.SettingsSchema` - the same table the
	SERVER validates against. Not a hand-written list of rows.

	That matters because the two would drift the first time a setting is added:
	a hand-written menu shows a control for a key the server drops, or hides one
	the schema accepts. Generated, a new setting is one line in the schema and
	it appears here with the right control, the right bounds and the right
	options.

	The only thing hand-written is the LABEL, because "MusicVolume" is not a
	sentence. A schema key with no label still renders, using its own key.
	═══════════════════════════════════════════════════════════════════════════

	═══ THE CLIENT NEVER WRITES THE PROFILE ════════════════════════════════════
	A control sends `RequestSetSetting(key, value)` and then does nothing. The
	row redraws when the replicated profile changes, so a value the server
	clamps or rejects snaps back visibly rather than showing a lie.
	═══════════════════════════════════════════════════════════════════════════

	Depends on: StateController, UIController, InputController, Theme, Create,
	            Widgets, GameConfig, Net.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Log = require(Shared.Modules.Log)
local Net = require(Shared.Modules.Net)

local Client = script.Parent.Parent
local Create = require(Client.UI.Create)
local Theme = require(Client.UI.Theme)
local Widgets = require(Client.UI.Widgets)

local SettingsController = {}

local StateController, UIController, InputController

local player = Players.LocalPlayer

local root: Frame? = nil
local rows: { [string]: any } = {}
local observers = {}

local ROW_HEIGHT = 56

--[[
	Display order and wording. A key missing from here still renders - it just
	uses its own name - so adding a setting to the schema can never make it
	invisible, which is the failure a hand-written list produces.

	Ordered by how often a player touches it, not alphabetically: volume first
	because it is the first thing anybody changes.
]]
local LABELS = {
	{ Key = "MusicVolume", Label = "Music", Hint = "" },
	{ Key = "SfxVolume", Label = "Sound effects", Hint = "" },
	{ Key = "UiScale", Label = "UI scale", Hint = "Accessibility" },
	{ Key = "LowGraphics", Label = "Low graphics mode", Hint = "Fewer effects, longer battery" },
	{ Key = "Particles", Label = "Particles", Hint = "" },
	{ Key = "CameraShake", Label = "Camera shake", Hint = "Accessibility" },
	{ Key = "ScreenEffects", Label = "Screen effects", Hint = "Accessibility" },
	{ Key = "ShowNameTags", Label = "Other players' name tags", Hint = "" },
	{ Key = "RareAnnouncements", Label = "Rare-hatch announcements", Hint = "Server takeovers still show" },
	{ Key = "StealNotifications", Label = "Steal notifications", Hint = "Your own park alerts cannot be muted" },
	{ Key = "TradeRequests", Label = "Trade requests", Hint = "V1.5+" },
	{ Key = "AutoCollect", Label = "Auto-collect income", Hint = "Unlocks with the upgrade" },
	--[[
		`SeenStoreNotice` is deliberately listed LAST and phrased as an action
		rather than a state: it exists to record that docs/07 §1 rule 7's panel
		has been shown, and a player who wants to read it again should be able
		to. Nobody needs to see it phrased as "seen store notice: on".
	]]
	{ Key = "SeenStoreNotice", Label = "Show the store notice again",
		Hint = "The 'you never need to spend Robux' panel", Invert = true },
}

local function labelFor(key: string)
	for _, entry in LABELS do
		if entry.Key == key then
			return entry
		end
	end
	return { Key = key, Label = key, Hint = "" }
end

--- Schema order, but with the labelled keys first and in their listed order, so
--- the menu is stable across sessions and a new key lands at the bottom.
local function orderedKeys(): { string }
	local seen, out = {}, {}
	for _, entry in LABELS do
		if GameConfig.SettingsSchema[entry.Key] then
			table.insert(out, entry.Key)
			seen[entry.Key] = true
		end
	end
	local rest = {}
	for key in GameConfig.SettingsSchema do
		if not seen[key] then
			table.insert(rest, key)
		end
	end
	table.sort(rest)
	for _, key in rest do
		table.insert(out, key)
	end
	return out
end

-- ── Writing ─────────────────────────────────────────────────────────────────

local function set(key: string, value)
	Net.FireServer("RequestSetSetting", key, value)
end

-- ── Rows ────────────────────────────────────────────────────────────────────

local function buildRow(key: string, parent: Instance, order: number)
	local schema = GameConfig.SettingsSchema[key]
	local meta = labelFor(key)

	local name = Create("TextLabel", {
		Name = "Label",
		Size = UDim2.new(1, -240, 0, 22),
		Position = UDim2.fromOffset(Theme.Space.L, 8),
		BackgroundTransparency = 1,
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Label,
		TextColor3 = Theme.Color.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = meta.Label,
	})

	local hint = Create("TextLabel", {
		Name = "Hint",
		Size = UDim2.new(1, -240, 0, 18),
		Position = UDim2.fromOffset(Theme.Space.L, 30),
		BackgroundTransparency = 1,
		Font = Theme.Font.Body,
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = Theme.Color.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = meta.Hint or "",
	})

	local control
	local kind = schema.Type

	if kind == "boolean" then
		--[[
			A single wide button rather than a switch graphic: docs/08 §4's
			touch-target guarantee is about real pixels, and a 64px button that
			says ON is both bigger and clearer than a 30px slider knob.
		]]
		control = Create("TextButton", {
			Name = "Toggle",
			Size = UDim2.fromOffset(120, Theme.Size.MinTouchTarget),
			Position = UDim2.new(1, -Theme.Space.L, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			BackgroundColor3 = Theme.Color.SurfaceRaised,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Font = Theme.Font.Bold,
			TextSize = Theme.TextSize.Small,
			TextColor3 = Theme.Color.Text,
			Text = "…",
			Children = { Create("UICorner", { CornerRadius = Theme.Radius.Small }) },
			Events = {
				MouseButton1Click = function()
					local data = StateController.Get()
					local current = data and data.Settings and data.Settings[key]
					set(key, not (current == true))
				end,
			},
		})
	elseif kind == "string" then
		--[[
			An option cycler rather than a dropdown. Three options fit on a
			phone; a dropdown is a second surface to lay out, dismiss and get
			wrong on a small screen.
		]]
		control = Create("TextButton", {
			Name = "Cycle",
			Size = UDim2.fromOffset(150, Theme.Size.MinTouchTarget),
			Position = UDim2.new(1, -Theme.Space.L, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			BackgroundColor3 = Theme.Color.SurfaceRaised,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Font = Theme.Font.Bold,
			TextSize = Theme.TextSize.Small,
			TextColor3 = Theme.Color.Text,
			Text = "…",
			Children = { Create("UICorner", { CornerRadius = Theme.Radius.Small }) },
			Events = {
				MouseButton1Click = function()
					local options = schema.OneOf or {}
					local data = StateController.Get()
					local current = data and data.Settings and data.Settings[key]
					local index = 1
					for position, option in options do
						if option == current then
							index = position
						end
					end
					set(key, options[(index % #options) + 1])
				end,
			},
		})
	else
		--[[
			Numbers are stepped rather than dragged. A drag on a slider sends a
			write per frame and the remote is rate-limited to 5/s, so most of
			them would be dropped and the value would land somewhere the player
			did not choose. Two buttons and a readout always land exactly.
		]]
		local readout = Create("TextLabel", {
			Name = "Value",
			Size = UDim2.fromOffset(70, Theme.Size.MinTouchTarget),
			Position = UDim2.new(1, -Theme.Space.L - 64, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			BackgroundTransparency = 1,
			Font = Theme.Font.Display,
			TextSize = Theme.TextSize.Body,
			TextColor3 = Theme.Color.Accent,
			Text = "…",
		})

		local function stepper(name, delta, offset)
			return Create("TextButton", {
				Name = name,
				Size = UDim2.fromOffset(Theme.Size.MinTouchTarget, Theme.Size.MinTouchTarget),
				Position = UDim2.new(1, offset, 0.5, 0),
				AnchorPoint = Vector2.new(1, 0.5),
				BackgroundColor3 = Theme.Color.SurfaceRaised,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Font = Theme.Font.Bold,
				TextSize = Theme.TextSize.Label,
				TextColor3 = Theme.Color.Text,
				Text = if delta > 0 then "+" else "−",
				Children = { Create("UICorner", { CornerRadius = Theme.Radius.Small }) },
				Events = {
					MouseButton1Click = function()
						local data = StateController.Get()
						local current = (data and data.Settings and data.Settings[key]) or 0
						--[[
							Clamped here as well as on the server, so a button
							at the end of its range does nothing visible rather
							than sending a write that is silently rejected.
						]]
						set(key, math.clamp(current + delta,
							schema.Min or -math.huge, schema.Max or math.huge))
					end,
				},
			})
		end

		control = Create("Frame", {
			Name = "Stepper",
			Size = UDim2.fromOffset(210, Theme.Size.MinTouchTarget),
			Position = UDim2.new(1, -Theme.Space.L, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			BackgroundTransparency = 1,
			Children = {
				readout,
				stepper("Down", -10, -134),
				stepper("Up", 10, 0),
			},
		})
		rows[key] = { Readout = readout }
	end

	local panel = Widgets.Panel({
		Name = key,
		Size = UDim2.new(1, -8, 0, ROW_HEIGHT),
		Color = Theme.Color.Surface,
		LayoutOrder = order,
		Children = { name, hint, control },
		Parent = parent,
	})

	local row = rows[key] or {}
	row.Panel = panel
	row.Control = control
	row.Kind = kind
	row.Key = key
	rows[key] = row
	return row
end

local function refresh()
	local data = StateController.Get()
	local settings = data and data.Settings
	if not settings then
		return
	end

	for key, row in rows do
		local value = settings[key]
		local meta = labelFor(key)

		if row.Kind == "boolean" then
			--[[
				`Invert` is for a key whose stored meaning is the opposite of
				the sentence next to it: `SeenStoreNotice = true` means the
				panel is DONE, and the row asks whether to show it again.
			]]
			local on = if meta.Invert then value ~= true else value == true
			row.Control.Text = if on then "ON" else "OFF"
			row.Control.BackgroundColor3 = if on then Theme.Color.Accent else Theme.Color.SurfaceRaised
			row.Control.TextColor3 = if on then Theme.Color.TextOnAccent else Theme.Color.TextMuted
		elseif row.Kind == "string" then
			row.Control.Text = tostring(value or "?"):upper()
		elseif row.Readout then
			row.Readout.Text = tostring(math.floor(tonumber(value) or 0))
		end
	end
end

-- ── Low Graphics mode ───────────────────────────────────────────────────────

--[[
	═══ WHAT LOW GRAPHICS ACTUALLY DOES ════════════════════════════════════════
	docs/06 §8: "also culls distant dinosaur models". `WeatherController`
	already suppresses fog and colour shifts for this setting; this owns the
	rest, because it is the controller that owns the setting.

	Everything here is LOCAL. A server-side cull would decide for everybody, and
	the whole point is that the player on the weak phone gets the cheap version
	while the player on a desktop does not.
	═══════════════════════════════════════════════════════════════════════════
]]
local function applyGraphics()
	local data = StateController.Get()
	local settings = data and data.Settings
	if not settings then
		return
	end

	local low = settings.LowGraphics == true
	local particles = settings.Particles or "High"

	--[[
		`StreamingEnabled` is a place-level property the client cannot set, so
		the cull is done the way a client actually can: distance-culled
		rendering of the park dinosaur models, which is what
		`GameConfig.VfxCullDistance` was added for in Step 5.
	]]
	local runtime = Workspace:FindFirstChild("SAD_Runtime")
	local parkDinos = runtime and runtime:FindFirstChild("ParkDinos")
	if parkDinos then
		local cull = if low then GameConfig.VfxCullDistance else math.huge
		for _, model in parkDinos:GetChildren() do
			if model:IsA("Model") then
				model:SetAttribute("CullDistance", if cull == math.huge then nil else cull)
			end
		end
	end

	--[[
		Particle density, as the emitters' own rate rather than by destroying
		them - so turning the setting back on restores them without needing
		whatever created them to run again.
	]]
	local scale = if particles == "Off" then 0 elseif particles == "Medium" then 0.4 else 1
	local effects = runtime and runtime:FindFirstChild("Effects")
	for _, descendant in (effects and effects:GetDescendants()) or {} do
		if descendant:IsA("ParticleEmitter") then
			local base = descendant:GetAttribute("BaseRate")
			if base == nil then
				base = descendant.Rate
				descendant:SetAttribute("BaseRate", base)
			end
			descendant.Rate = base * scale
		end
	end

	--[[
		Global shadows are the single biggest frame-rate lever on a low-end
		Android and are a Lighting property the client may set locally.
	]]
	Lighting.GlobalShadows = not low
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
		Text = "SETTINGS",
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
		Events = { MouseButton1Click = function() UIController.Close("Settings") end },
	})

	local list = Create("ScrollingFrame", {
		Name = "Rows",
		Size = UDim2.new(1, -Theme.Space.XL, 1, -72),
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
		Name = "SettingsScreen",
		Size = UDim2.fromScale(0.92, 0.86),
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
	for _, key in orderedKeys() do
		order += 1
		buildRow(key, list, order)
	end
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function SettingsController.Init(app)
	StateController = app.Get("StateController")
	UIController = app.Get("UIController")
	InputController = app.Get("InputController")
end

function SettingsController.Start(_app)
	build()

	UIController.Register("Settings", {
		Open = function()
			refresh()
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
		if action == "ToggleSettings" and state == "Begin" then
			UIController.Toggle("Settings")
		end
	end)

	--[[
		Redrawn from the replicated profile, never from the click. A value the
		server clamps or refuses snaps back visibly instead of the row showing
		something the profile does not contain.
	]]
	table.insert(observers, StateController.Observe({ "Settings" }, function()
		if root and root.Visible then
			refresh()
		end
		applyGraphics()
	end))

	--[[
		docs/06 §8: "Low Graphics Mode is auto-suggested on first join if the
		device reports a low quality level or is mobile."

		Suggested, not forced - a setting the game turned on without asking is a
		setting the player cannot find to turn off. This only fires when the
		player has never changed it from the default.
	]]
	task.defer(function()
		local data = StateController.GetAsync and StateController.GetAsync() or StateController.Get()
		if not data or not data.Settings then
			return
		end
		if data.Settings.LowGraphics then
			return
		end
		if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
			Log.info("SettingsController",
				"Touch device detected. Low Graphics is available in Settings")
		end
	end)

	applyGraphics()

	Log.info("SettingsController", "Ready. %d setting(s), generated from the schema",
		#orderedKeys())
end

return SettingsController
