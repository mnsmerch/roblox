--!nonstrict
--[[
	InputController
	StarterPlayerScripts/SAD_Client/Controllers/InputController  (ModuleScript)

	Turns raw input into named actions, so nothing downstream knows or cares
	whether a player pressed E, tapped a button, or held gamepad A.

		InputController.Action:Connect(function(action, state)
			if action == "Interact" and state == "Begin" then ... end
		end)

	Every binding from docs/08 §4 in one place. Adding console support later
	means editing this file, not hunting for KeyCode checks across ten
	controllers.

	Uses ContextActionService rather than UserInputService.InputBegan so
	bindings cooperate with Roblox's core UI - a player typing in chat does not
	drop their egg because they pressed Q.

	API:
		InputController.Action        Signal(actionName, state, inputObject?)
		InputController.Fire(action, state)   -- HUD buttons route through here
		InputController.DeviceKind    -> "Touch" | "Keyboard" | "Gamepad" | "Console"
		InputController.DeviceChanged Signal(kind)

	Depends on: Log, Signal.
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local Log = require(Shared.Modules.Log)
local Signal = require(Shared.Modules.Signal)

local InputController = {}

InputController.Action = Signal.new()
InputController.DeviceChanged = Signal.new()
InputController.DeviceKind = "Keyboard"

--[[
	The complete binding table (docs/08 §4).

	Priority matters: menu toggles sit below gameplay actions so that Escape
	closing a screen never competes with something the player is mid-way
	through doing.
]]
local BINDINGS = {
	{ Action = "Interact", Priority = 300,
	  Keys = { Enum.KeyCode.E }, Gamepad = { Enum.KeyCode.ButtonA } },
	{ Action = "Sprint", Priority = 300,
	  Keys = { Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift }, Gamepad = { Enum.KeyCode.ButtonL3 } },
	{ Action = "DropEgg", Priority = 300,
	  Keys = { Enum.KeyCode.Q }, Gamepad = { Enum.KeyCode.ButtonX } },

	{ Action = "ToggleParkMenu", Priority = 200, Keys = { Enum.KeyCode.One } },
	{ Action = "ToggleEggs", Priority = 200, Keys = { Enum.KeyCode.Two } },
	{ Action = "ToggleDinos", Priority = 200, Keys = { Enum.KeyCode.Three } },
	{ Action = "ToggleShop", Priority = 200, Keys = { Enum.KeyCode.Four } },
	{ Action = "ToggleTeleport", Priority = 200,
	  Keys = { Enum.KeyCode.Five }, Gamepad = { Enum.KeyCode.ButtonY } },

	{ Action = "ToggleInventory", Priority = 200, Keys = { Enum.KeyCode.Tab } },
	{ Action = "ToggleMap", Priority = 200,
	  Keys = { Enum.KeyCode.M }, Gamepad = { Enum.KeyCode.ButtonSelect } },
	{ Action = "Close", Priority = 100,
	  Keys = { Enum.KeyCode.Escape }, Gamepad = { Enum.KeyCode.ButtonB } },
}

--- Emits an action. HUD buttons call this directly so a tap and a keypress are
--- literally the same event downstream.
function InputController.Fire(action: string, state: string?, inputObject: InputObject?)
	InputController.Action:Fire(action, state or "Begin", inputObject)
end

local function detectDevice(): string
	if GuiService:IsTenFootInterface() then
		return "Console"
	end

	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		return "Touch"
	elseif last == Enum.UserInputType.Gamepad1
		or last == Enum.UserInputType.Gamepad2
		or last == Enum.UserInputType.Gamepad3
		or last == Enum.UserInputType.Gamepad4 then
		return "Gamepad"
	elseif last == Enum.UserInputType.Keyboard
		or last == Enum.UserInputType.MouseButton1
		or last == Enum.UserInputType.MouseMovement then
		return "Keyboard"
	end

	-- No meaningful input yet: fall back to what the device actually has.
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Touch"
	end
	return InputController.DeviceKind
end

local function updateDevice()
	local kind = detectDevice()
	if kind ~= InputController.DeviceKind then
		InputController.DeviceKind = kind
		Log.debug("InputController", "Device is now %s", kind)
		InputController.DeviceChanged:Fire(kind)
	end
end

function InputController.Init(app)
	for _, binding in BINDINGS do
		local keys = {}
		for _, key in binding.Keys or {} do
			table.insert(keys, key)
		end
		for _, key in binding.Gamepad or {} do
			table.insert(keys, key)
		end
		if #keys == 0 then
			continue
		end

		ContextActionService:BindActionAtPriority(
			"SAD_" .. binding.Action,
			function(_, inputState, inputObject)
				if inputState == Enum.UserInputState.Begin then
					InputController.Fire(binding.Action, "Begin", inputObject)
				elseif inputState == Enum.UserInputState.End then
					InputController.Fire(binding.Action, "End", inputObject)
				end
				-- Pass through: these never consume input from the character
				-- controller or the core UI.
				return Enum.ContextActionResult.Pass
			end,
			false, -- touch buttons come from our own HUD, not the CAS overlay
			binding.Priority,
			table.unpack(keys)
		)
	end

	Log.info("InputController", "%d action(s) bound", #BINDINGS)
end

function InputController.Start(app)
	UserInputService.LastInputTypeChanged:Connect(updateDevice)
	updateDevice()
	Log.info("InputController", "Starting device: %s", InputController.DeviceKind)
end

return InputController
