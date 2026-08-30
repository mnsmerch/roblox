--!nonstrict
--[[
	EggCarryController
	StarterPlayerScripts/SAD_Client/Controllers/EggCarryController  (ModuleScript)

	Draws what you are carrying and how far you are from safety.

	It reads carry state off the WORLD, not from a remote. The server welds each
	carried egg to the character with EggUid, Rarity and Origin attributes, and
	that model is already replicated to everyone - so observers get the same
	information for free, and there is no extra packet or extra remote to keep
	in sync with the truth.

	It also finds the player's own park by scanning plot attributes rather than
	asking the server. `OwnerUserId` is already on every plot for other reasons;
	reading it costs nothing and one fewer round trip is one fewer thing to be
	waiting on mid-chase.

	Nothing here is authoritative. Deleting the model, editing an attribute or
	stopping this script changes nothing the server believes - the carry token
	lives on the server and only there.

	It also owns the client half of the chase: the ChaseState remote drives the
	HUD readout and the camera shake, and the vignette pulses with how close the
	guardian actually is.

	Depends on: HUDController, CameraController, InputController, Net,
	            RarityConfig, ChaseConfig.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local ChaseConfig = require(Shared.Config.ChaseConfig)
local RarityConfig = require(Shared.Config.RarityConfig)
local Log = require(Shared.Modules.Log)
local Net = require(Shared.Modules.Net)
local Trove = require(Shared.Modules.Trove)

local EggCarryController = {}

local player = Players.LocalPlayer

local HUDController, CameraController, InputController

local characterTrove = Trove.new()
local carried: { [string]: any } = {}
local ownPlot: Model? = nil
local chase: any = nil

--- Refresh rate for the distance readout. Every frame would be wasted work for
--- a number that changes by a stud.
local UPDATE_INTERVAL = 0.2

-- ── Own park ────────────────────────────────────────────────────────────────

--[[
	Finds this player's plot by attribute.

	Plots already carry OwnerUserId for the server's own bookkeeping, and
	attributes replicate, so the client can answer "where is home" without a
	round trip. Re-checked lazily because the plot is assigned a moment after
	the character spawns.
]]
local function findOwnPlot(): Model?
	if ownPlot and ownPlot.Parent and ownPlot:GetAttribute("OwnerUserId") == player.UserId then
		return ownPlot
	end

	local world = Workspace:FindFirstChild("SAD_World")
	local plots = world and world:FindFirstChild("ParkPlots")
	if not plots then
		return nil
	end

	for _, plot in plots:GetChildren() do
		if plot:GetAttribute("OwnerUserId") == player.UserId then
			ownPlot = plot
			return plot
		end
	end

	ownPlot = nil
	return nil
end

--- Distance from the character to their own park gate, or nil.
local function distanceToPark(): number?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end

	local plot = findOwnPlot()
	if not plot then
		return nil
	end

	local gate = plot:FindFirstChild("GateThreshold") or plot.PrimaryPart
	if not gate then
		return nil
	end

	local delta = root.Position - gate.Position
	return math.sqrt(delta.X * delta.X + delta.Z * delta.Z)
end

-- ── Carry tracking ──────────────────────────────────────────────────────────

--- The heaviest thing being carried leads the readout - that is what the
--- player is actually anxious about.
local function headlineToken()
	local best, bestRank = nil, -1
	for _, token in carried do
		local rank = RarityConfig.RankOf(token.Rarity)
		if rank > bestRank then
			best, bestRank = token, rank
		end
	end
	return best
end

local function refreshHud()
	local count = 0
	for _ in carried do
		count += 1
	end

	if count == 0 then
		HUDController.SetCarry(nil)
		return
	end

	local headline = headlineToken()
	HUDController.SetCarry({
		Rarity = RarityConfig.Tiers[headline.Rarity].DisplayName,
		RarityColor = RarityConfig.GetColor(headline.Rarity),
		Count = count,
		Distance = distanceToPark(),
	})
end

local function onEggAdded(model: Instance)
	if not model:IsA("Model") then
		return
	end

	-- Identified by attributes rather than by name: the name is a convenience,
	-- the attributes are the contract EggService writes.
	local uid = model:GetAttribute("EggUid")
	local rarity = model:GetAttribute("Rarity")
	if not uid or not rarity or not RarityConfig.Tiers[rarity] then
		return
	end

	carried[uid] = { Uid = uid, Rarity = rarity, Model = model }
	refreshHud()

	Log.debug("EggCarryController", "Carrying a %s egg (%s)", rarity, uid)
end

local function onEggRemoved(model: Instance)
	local uid = model:GetAttribute("EggUid")
	if uid and carried[uid] then
		carried[uid] = nil
		refreshHud()
	end
end

--[[
	Rebinds to a new character.

	A carried egg does not survive a respawn - the model was welded to a
	character that no longer exists - so the local view is cleared rather than
	left showing an egg the server has already returned to its nest.
]]
local function bindCharacter(character: Model)
	characterTrove:Clean()
	carried = {}
	refreshHud()

	characterTrove:Connect(character.ChildAdded, onEggAdded)
	characterTrove:Connect(character.ChildRemoved, onEggRemoved)

	for _, child in character:GetChildren() do
		onEggAdded(child)
	end
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

-- ── The chase ───────────────────────────────────────────────────────────────

--[[
	Distance from the nearest guardian, for the vignette pulse.

	Read off the world rather than streamed from the server: guardian models are
	already replicated, so their positions are free, and a per-frame distance
	packet for a visual effect would be indefensible.
]]
local function nearestGuardianDistance(): number?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end

	local runtime = Workspace:FindFirstChild("SAD_Runtime")
	local guardians = runtime and runtime:FindFirstChild("Guardians")
	if not guardians then
		return nil
	end

	local nearest = nil
	for _, model in guardians:GetChildren() do
		if model:IsA("Model") and model.PrimaryPart then
			local delta = model.PrimaryPart.Position - root.Position
			local distance = math.sqrt(delta.X * delta.X + delta.Z * delta.Z)
			if not nearest or distance < nearest then
				nearest = distance
			end
		end
	end
	return nearest
end

local function onChaseState(state)
	if not state or state.Active == false then
		chase = nil
		HUDController.SetChase(nil)
		return
	end

	if state.Caught then
		HUDController.SetChase({ Caught = true })
		CameraController.Shake(0.9, 0.7)
		return
	end

	if state.Ability then
		-- The ability tell: a jolt on the wind-up, so a Charger's charge is
		-- something the player can react to rather than only observe.
		CameraController.Shake(0.45, 0.35)
		return
	end

	chase = state
	HUDController.SetChase(state)
	CameraController.Shake(0.55, 0.5)
end

function EggCarryController.Init(app)
	HUDController = app.Get("HUDController")
	CameraController = app.Get("CameraController")
	InputController = app.Get("InputController")
end

function EggCarryController.Start(app)
	if player.Character then
		bindCharacter(player.Character)
	end
	player.CharacterAdded:Connect(bindCharacter)

	-- Q, or gamepad X. The server decides whether the drop happens.
	InputController.Action:Connect(function(action, state)
		if action ~= "DropEgg" or state ~= "Begin" then
			return
		end

		local headline = headlineToken()
		if headline then
			Net.FireServer("RequestDropEgg", headline.Uid)
		end
	end)

	Net.On("ChaseState", onChaseState)

	-- Only the distance readouts need refreshing; carry contents and chase
	-- starts are event-driven.
	task.spawn(function()
		while true do
			task.wait(UPDATE_INTERVAL)

			if next(carried) then
				refreshHud()
			end

			if chase then
				local distance = nearestGuardianDistance()
				if distance then
					-- Full pulse when it is within reach, nothing at 100 studs.
					local fraction = 1 - math.clamp((distance - 8) / 92, 0, 1)
					HUDController.SetChaseProximity(fraction)
				end
			end
		end
	end)

	Log.info("EggCarryController", "Watching for carried eggs")
end

return EggCarryController
