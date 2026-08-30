--[[
	Bootstrap
	StarterPlayer/StarterPlayerScripts/SAD_Client/Bootstrap  (LocalScript)

	The ONLY LocalScript. Mirrors the server Bootstrap exactly: same two-phase
	contract, same injected `app`, same skip-if-not-built behaviour.

	Controller contract:
		local MyController = {}
		function MyController.Init(app) end
		function MyController.Start(app) end
		return MyController

	Controllers own presentation and input. They never decide anything the
	server cares about - they send intent through Net and render what comes
	back. See docs/09-tech-architecture.md §7.

	Depends on: Log, Net, GameConfig, and the server Bootstrap having published
	the remote tree.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local Modules = Shared:WaitForChild("Modules")
local Config = Shared:WaitForChild("Config")

local GameConfig = require(Config:WaitForChild("GameConfig"))
local Log = require(Modules:WaitForChild("Log"))
local Net = require(Modules:WaitForChild("Net"))

--- Full V1 controller roster. Entries light up as each step builds them.
local CONTROLLER_ORDER = {
	"StateController", -- Step 4
	"SoundController", -- Step 16
	"NotificationController", -- Step 16
	"UIController", -- Step 5
	"HUDController", -- Step 5
	"InputController", -- Step 5
	"CameraController", -- Step 9
	"AnimationController", -- Step 9
	"EggCarryController", -- Step 8
	"ParkController", -- Step 12
	"ShopController", -- Step 13
	"TeleportController", -- Step 14
	"WeatherController", -- Step 17
	"RebirthController", -- Step 20
	"MinimapController", -- Step 14
	"IndexController", -- Step 19
	"QuestController", -- Step 19
	"SettingsController", -- Step 24
	"TutorialController", -- Step 23
}

local controllersFolder = script.Parent:WaitForChild("Controllers")

local registry: { [string]: any } = {}
local loadedOrder: { string } = {}

local app
app = {
	IsServer = false,
	Log = Log,
	Net = Net,
	Config = Shared.Config,
	Player = Players.LocalPlayer,
	Get = function(name: string): any
		local controller = registry[name]
		if not controller then
			error(
				string.format(
					"Controller '%s' is not loaded. It may not be built yet, or it is missing from CONTROLLER_ORDER.",
					name
				),
				2
			)
		end
		return controller
	end,
}

--- A failed controller must never black-screen the player, so the client only
--- aborts under StrictBoot (Studio). In production it degrades and reports.
local function guarded(phase: string, name: string, fn: () -> ()): boolean
	local ok, err = pcall(fn)
	if ok then
		return true
	end

	Log.error("Boot", "%s failed for %s: %s", phase, name, tostring(err))
	if GameConfig.StrictBoot then
		error(string.format("[SAD] Client boot aborted: %s failed for %s\n%s", phase, name, tostring(err)), 0)
	end
	return false
end

local startedAt = os.clock()

Log.banner(string.format("%s v%s client starting", GameConfig.GameName, GameConfig.Version))

-- Blocks until the server has published SAD_Net.
Net.Init()

local skipped: { string } = {}
for _, name in CONTROLLER_ORDER do
	local moduleScript = controllersFolder:FindFirstChild(name)
	if not moduleScript then
		table.insert(skipped, name)
		continue
	end

	guarded("Require", name, function()
		local controller = require(moduleScript)
		assert(type(controller) == "table", name .. " must return a table")
		registry[name] = controller
		table.insert(loadedOrder, name)
	end)
end

if #skipped > 0 then
	Log.debug("Boot", "Not built yet (%d): %s", #skipped, table.concat(skipped, ", "))
end

for _, name in loadedOrder do
	local controller = registry[name]
	if type(controller.Init) == "function" then
		guarded("Init", name, function()
			controller.Init(app)
		end)
	end
end

for _, name in loadedOrder do
	local controller = registry[name]
	if type(controller.Start) == "function" then
		guarded("Start", name, function()
			controller.Start(app)
		end)
	end
end

Log.info("Boot", "Loaded %d controller(s): %s", #loadedOrder, table.concat(loadedOrder, ", "))
Log.banner(string.format("Client boot complete (%.0f ms)", (os.clock() - startedAt) * 1000))
