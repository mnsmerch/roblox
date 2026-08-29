--!nonstrict
--[[
	UIController
	StarterPlayerScripts/SAD_Client/Controllers/UIController  (ModuleScript)

	Owns the single ScreenGui, the layer stack, responsive scaling, and which
	screen is open.

	The ScreenGui is CREATED HERE, in PlayerGui, rather than living in
	StarterGui. Building it in code keeps the whole interface in version control
	and diffable, and a PlayerGui-parented ScreenGui survives respawn
	inherently - there is no ResetOnSpawn property left to get wrong.

	Layers exist up front, empty, so later steps parent into a named layer
	instead of inventing ZIndex values:

		Hud (10) < Screen (20) < Prompt (30) < Notification (40) < Takeover (50)

	One screen is open at a time. That is a deliberate constraint from
	docs/08 §1: a player being chased must never be behind two stacked menus.

	API:
		UIController.Layer(name)              -> Frame
		UIController.Register(name, screen)   -- screen: { Open(), Close() }
		UIController.Open(name) / Close(name) / Toggle(name) / CloseAll()
		UIController.GetOpen()                -> name?
		UIController.Breakpoint               -> "phone" | "tablet" | "desktop"
		UIController.BreakpointChanged        Signal(breakpoint, logicalWidth)
		UIController.ScreenChanged            Signal(openName?)

	Depends on: Theme, Create, StateController, Log, Signal.
	Depended on by: HUDController and every screen from Step 13 onward.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local Log = require(Shared.Modules.Log)
local Signal = require(Shared.Modules.Signal)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Create = require(UI.Create)

local UIController = {}

UIController.BreakpointChanged = Signal.new()
UIController.ScreenChanged = Signal.new()
UIController.Breakpoint = "wide"
UIController.LogicalWidth = 1280

local player = Players.LocalPlayer

local screenGui: ScreenGui = nil
local root: Frame = nil
local uiScale: UIScale = nil
local layers: { [string]: Frame } = {}

local screens: { [string]: any } = {}
local openScreen: string? = nil

local userScalePercent = 100

-- ── Scaling ─────────────────────────────────────────────────────────────────

-- Scale and breakpoint maths live in Theme as pure functions, so the
-- mobile-first guarantee is covered by tests/step5_spec.lua rather than by
-- someone remembering to resize a Studio window.

local function applyLayout()
	if not screenGui then
		return
	end

	local viewport = screenGui.AbsoluteSize
	if viewport.X <= 0 or viewport.Y <= 0 then
		return
	end

	local scale = Theme.ScaleFor(viewport.X, viewport.Y, userScalePercent, GuiService:IsTenFootInterface())
	uiScale.Scale = scale

	-- Breakpoints compare LOGICAL pixels, so two viewports with the same room
	-- for UI get the same layout regardless of what device they are.
	local logicalWidth = viewport.X / scale
	local breakpoint = Theme.BreakpointFor(logicalWidth)

	local changed = breakpoint ~= UIController.Breakpoint
	UIController.Breakpoint = breakpoint
	UIController.LogicalWidth = logicalWidth

	-- Console overscan inset. Harmless elsewhere, essential on a TV.
	local inset = if GuiService:IsTenFootInterface() then Theme.ConsoleInsetScale else 0
	root.Position = UDim2.fromScale(inset, inset)
	root.Size = UDim2.fromScale(1 - inset * 2, 1 - inset * 2)

	if changed then
		Log.debug("UIController", "Breakpoint %s (%.0f logical px, scale %.2f)", breakpoint, logicalWidth, scale)
		UIController.BreakpointChanged:Fire(breakpoint, logicalWidth)
	end
end

-- ── Layers ──────────────────────────────────────────────────────────────────

function UIController.Layer(name: string): Frame
	local layer = layers[name]
	assert(layer, "UIController: unknown layer '" .. tostring(name) .. "'")
	return layer
end

function UIController.Root(): Frame
	return root
end

-- ── Screens ─────────────────────────────────────────────────────────────────

--- A screen is any table with Open() and Close(). Step 13 onward register here.
function UIController.Register(name: string, screen)
	assert(type(screen) == "table" and screen.Open and screen.Close,
		"UIController.Register: screen '" .. name .. "' needs Open and Close")
	screens[name] = screen
end

function UIController.Close(name: string?)
	local target = name or openScreen
	if not target or openScreen ~= target then
		return
	end

	local screen = screens[target]
	if screen then
		local ok, err = pcall(screen.Close, screen)
		if not ok then
			Log.error("UIController", "Close failed for %s: %s", target, tostring(err))
		end
	end

	openScreen = nil
	UIController.ScreenChanged:Fire(nil)
end

function UIController.Open(name: string)
	local screen = screens[name]
	if not screen then
		Log.warn("UIController", "No screen registered as '%s' - not built yet?", name)
		return false
	end

	-- One at a time: never let a player be chased behind two stacked menus.
	if openScreen and openScreen ~= name then
		UIController.Close(openScreen)
	end
	if openScreen == name then
		return true
	end

	local ok, err = pcall(screen.Open, screen)
	if not ok then
		Log.error("UIController", "Open failed for %s: %s", name, tostring(err))
		return false
	end

	openScreen = name
	UIController.ScreenChanged:Fire(name)
	return true
end

function UIController.Toggle(name: string)
	if openScreen == name then
		UIController.Close(name)
	else
		UIController.Open(name)
	end
end

--- Called whenever gameplay needs the screen clear - a chase starting, a
--- takeover announcement, a raid alert.
function UIController.CloseAll()
	if openScreen then
		UIController.Close(openScreen)
	end
end

function UIController.GetOpen(): string?
	return openScreen
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function UIController.Init(app)
	local playerGui = player:WaitForChild("PlayerGui")

	screenGui = Create("ScreenGui", {
		Name = "SAD_UI",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 10,
	})

	--[[
		ScreenInsets keeps the UI clear of notches and rounded corners, but it
		is a newer property than IgnoreGuiInset. Set it defensively so an older
		client falls back to the inset behaviour above rather than failing to
		build a HUD at all.
	]]
	pcall(function()
		screenGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	end)

	uiScale = Create("UIScale", { Scale = 1 })

	root = Create("Frame", {
		Name = "Root",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Children = { uiScale },
		Parent = screenGui,
	})

	for name, zIndex in Theme.Layer do
		layers[name:lower()] = Create("Frame", {
			Name = name .. "Layer",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = zIndex,
			Parent = root,
		})
	end

	screenGui.Parent = playerGui

	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout)
	applyLayout()

	Log.info("UIController", "SAD_UI mounted with %d layers", #root:GetChildren() - 1)
end

function UIController.Start(app)
	-- The accessibility scale from docs/06 §8, applied live.
	local StateController = app.Get("StateController")
	StateController.Observe({ "Settings", "UiScale" }, function(value)
		userScalePercent = tonumber(value) or 100
		applyLayout()
	end)
end

return UIController
