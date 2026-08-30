--!nonstrict
--[[
	ParkController
	StarterPlayerScripts/SAD_Client/Controllers/ParkController  (ModuleScript)

	Makes a park look like it is earning.

	Income floaters are generated ENTIRELY on the client, from the replicated
	profile, using the same Economy module the server banks with (docs/09 §6).
	The server sends nothing per tick. A park with thirty dinosaurs producing a
	floater every couple of seconds would otherwise be thirty remote calls a
	minute, per player, for something purely decorative.

	The numbers are honest even though they are local: they come from the same
	pure function that decides what actually lands in the bank, so a floater
	never says a figure the server disagrees with.

	Depends on: StateController, HUDController, Economy, Format, Theme.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local DinoConfig = require(Shared.Config.DinoConfig)
local RarityConfig = require(Shared.Config.RarityConfig)
local Economy = require(Shared.Modules.Economy)
local Format = require(Shared.Modules.Format)
local Log = require(Shared.Modules.Log)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Create = require(UI.Create)

local ParkController = {}

local player = Players.LocalPlayer
local StateController, HUDController

--- Floaters only spawn for dinosaurs this close, so a distant park costs
--- nothing to look at.
local FLOATER_RANGE = 140
local FLOATER_INTERVAL = 2.2
local FLOATER_LIFETIME = 1.6

--- Never more than this many in the air at once, however large the park.
local MAX_FLOATERS = 12

local activeFloaters = 0

--[[
	A "+N" that drifts up and fades.

	Pooled by count rather than by instance: they live under two seconds, and a
	real pool would be more bookkeeping than the allocation it saves.
]]
local function spawnFloater(worldPosition: Vector3, amount: number, color: Color3)
	if activeFloaters >= MAX_FLOATERS then
		return
	end
	activeFloaters += 1

	local anchor = Create("Part", {
		Name = "IncomeFloater",
		Size = Vector3.new(0.2, 0.2, 0.2),
		CFrame = CFrame.new(worldPosition),
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Transparency = 1,
		Parent = Workspace,
	})

	local gui = Create("BillboardGui", {
		Size = UDim2.fromScale(8, 2),
		AlwaysOnTop = false,
		MaxDistance = FLOATER_RANGE,
		Parent = anchor,
		Children = {
			Create("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Font = Theme.Font.Display,
				TextScaled = true,
				TextColor3 = color,
				TextStrokeTransparency = 0.4,
				Text = "+" .. Format.Number(amount),
			}),
		},
	})

	TweenService:Create(anchor, TweenInfo.new(FLOATER_LIFETIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = CFrame.new(worldPosition + Vector3.new(0, 7, 0)),
	}):Play()

	local label = gui:FindFirstChildOfClass("TextLabel")
	TweenService:Create(label, TweenInfo.new(FLOATER_LIFETIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()

	task.delay(FLOATER_LIFETIME, function()
		anchor:Destroy()
		activeFloaters -= 1
	end)
end

--- The park models this player owns, near enough to be worth decorating.
local function nearbyOwnDinos()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return {}
	end

	local runtime = Workspace:FindFirstChild("SAD_Runtime")
	local folder = runtime and runtime:FindFirstChild("ParkDinos")
	if not folder then
		return {}
	end

	local nearby = {}
	for _, model in folder:GetChildren() do
		if model:GetAttribute("OwnerUserId") ~= player.UserId then
			continue
		end
		local primary = model.PrimaryPart
		if primary and (primary.Position - root.Position).Magnitude <= FLOATER_RANGE then
			table.insert(nearby, model)
		end
	end
	return nearby
end

local function tickFloaters()
	local state = StateController.Get()
	if not state or not state.Dinos then
		return
	end

	local nearby = nearbyOwnDinos()
	if #nearby == 0 then
		return
	end

	-- One dinosaur per tick, chosen at random. Every dinosaur floating at once
	-- is noise; one at a time reads as a park quietly working.
	local model = nearby[math.random(1, #nearby)]
	local uid = model:GetAttribute("DinoUid")
	local entry = uid and state.Dinos[uid]
	if not entry then
		return
	end

	--[[
		The same pure function the server banks with. A floater showing a number
		the server disagrees with would be worse than no floater at all.
	]]
	local perSecond = Economy.IncomeOf(entry, state)
	if perSecond <= 0 then
		return
	end

	spawnFloater(
		model:GetPivot().Position + Vector3.new(0, 6, 0),
		perSecond * FLOATER_INTERVAL,
		RarityConfig.GetColor(entry.Rarity)
	)
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function ParkController.Init(app)
	StateController = app.Get("StateController")
	HUDController = app.Get("HUDController")
end

function ParkController.Start(app)
	task.spawn(function()
		while true do
			task.wait(FLOATER_INTERVAL)
			local ok, err = pcall(tickFloaters)
			if not ok then
				Log.error("ParkController", "Floater tick failed: %s", tostring(err))
			end
		end
	end)

	Log.info("ParkController", "Income floaters ready")
end

return ParkController
