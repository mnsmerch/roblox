--!nonstrict
--[[
	CameraController
	StarterPlayerScripts/SAD_Client/Controllers/CameraController  (ModuleScript)

	Camera shake, and later the event cuts and takeover flourishes.

	Shake is applied as an OFFSET to whatever the camera already is, bound after
	Roblox's own camera step. It never takes control of the camera, so player
	look input, first person and the mobile drag-to-look all keep working while
	the ground is shaking.

	It decays rather than switching off, because a shake that stops abruptly
	reads as a bug. And it obeys the CameraShake accessibility setting from
	docs/06 §8 - some players get motion sick, and a game about being chased
	should not be the reason they stop playing.

	API:
		CameraController.Shake(intensity, duration)
		CameraController.SetEnabled(enabled)

	Depends on: StateController, Theme.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local Log = require(Shared.Modules.Log)

local CameraController = {}

local StateController

local shakeAmount = 0
local shakeDecay = 0
local enabled = true
local bound = false

--- Studs and radians at full intensity. Deliberately small: a chase should
--- feel unsteady, not unplayable.
local MAX_OFFSET = 1.2
local MAX_TILT = 0.025

local function step()
	if shakeAmount <= 0.001 then
		return
	end

	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local magnitude = shakeAmount
	local offset = Vector3.new(
		(math.random() - 0.5) * MAX_OFFSET * magnitude,
		(math.random() - 0.5) * MAX_OFFSET * magnitude,
		0
	)
	local tilt = (math.random() - 0.5) * MAX_TILT * magnitude

	-- Applied in the camera's own space, so it shakes relative to where the
	-- player is looking rather than relative to the world.
	camera.CFrame = camera.CFrame * CFrame.new(offset) * CFrame.Angles(0, 0, tilt)
end

local function decay(deltaTime: number)
	if shakeAmount > 0 then
		shakeAmount = math.max(0, shakeAmount - shakeDecay * deltaTime)
	end
end

--- Adds shake. Intensity 0-1; repeated calls take the strongest rather than
--- stacking, so a burst of events cannot black out the screen.
function CameraController.Shake(intensity: number, duration: number)
	if not enabled then
		return
	end

	intensity = math.clamp(intensity, 0, 1)
	if intensity <= shakeAmount then
		return
	end

	shakeAmount = intensity
	shakeDecay = intensity / math.max(duration, 0.05)
end

function CameraController.SetEnabled(value: boolean)
	enabled = value
	if not value then
		shakeAmount = 0
	end
end

function CameraController.Init(app)
	StateController = app.Get("StateController")
end

function CameraController.Start(app)
	-- After Roblox's camera step, so this offsets the final camera rather than
	-- fighting whatever the default camera script just decided.
	RunService:BindToRenderStep("SAD_CameraShake", Enum.RenderPriority.Camera.Value + 1, step)
	RunService.Heartbeat:Connect(decay)
	bound = true

	StateController.Observe({ "Settings", "CameraShake" }, function(value)
		CameraController.SetEnabled(value ~= false)
	end)

	Log.info("CameraController", "Camera shake ready")
end

return CameraController
