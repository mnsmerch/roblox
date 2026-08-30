--!nonstrict
--[[
	NestService
	ServerScriptService/SAD_Server/Services/NestService  (ModuleScript)
	  ├── WorldBuilder  (ModuleScript)
	  ├── NestBuilder   (ModuleScript)
	  └── ZoneService   (ModuleScript)

	Owns the world blockout, the nests in it, and the authoritative answer to
	"is that egg still there?".

	CLAIMING IS THE WHOLE JOB. Two players holding the same prompt at the same
	instant must produce exactly one egg, and a player standing across the map
	must produce none. ClaimEgg is single-threaded and yield-free for the first
	reason and re-checks distance server-side for the second - a ProximityPrompt
	does its own range check on the client, which is precisely why it cannot be
	the only one (docs/03 §6).

	Nests are discovered through CollectionService, not from WorldBuilder's
	return value. Generated anchors and hand-placed anchors are then the same
	thing, and a Studio-built zone can replace a generated one with no code
	change.

	API:
		NestService.GetNest(nestId) -> nest?
		NestService.GetNestsInZone(zoneId) -> { nest }
		NestService.ClaimEgg(player, nestId, slotIndex) -> ok, reason
		NestService.IsSlotFilled(nestId, slotIndex) -> boolean
		NestService.CountAvailableEggs(zoneId?) -> number

		NestService.EggClaimed    Signal(player, nest, slotIndex)
		NestService.NestRefilled  Signal(nest, slotIndex)

	Depends on: ZoneConfig, GameConfig, Log, Signal, WorldBuilder, NestBuilder,
	            ZoneService.
	Depended on by: EggService (Step 8), WildAIService (Step 9).
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local GameConfig = require(Shared.Config.GameConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local Log = require(Shared.Modules.Log)
local Signal = require(Shared.Modules.Signal)

local WorldBuilder = require(script.WorldBuilder)
local ZoneService = require(script.ZoneService)
local NestBuilder = require(script.NestBuilder)

local NestService = {}

NestService.EggClaimed = Signal.new()
NestService.NestRefilled = Signal.new()

--[[
	Fired when a player finishes holding a nest prompt.

	NestService does NOT claim the egg itself. Claiming without minting a carry
	token would destroy an egg and give the player nothing, so ownership of the
	whole pickup - roll, token, weld, speed - belongs to EggService, and this
	signal is the handoff. Nothing listening means nothing happens.
]]
NestService.PickupRequested = Signal.new()

--[[
	nests[nestId] = {
		Id, ZoneId, NestIndex, Model, AnchorCFrame,
		GuardianSpeciesId, Risk, RespawnSecs,
		Slots = { [i] = { Model: Model?, Prompt: ProximityPrompt?,
		                  Offset: Vector3, RefillAt: number? } },
	}
]]
local nests: { [string]: any } = {}
local nestsByZone: { [string]: { any } } = {}

local eggTemplate: Model = nil
local worldFolder: Folder = nil
local runtimeFolder: Folder = nil

-- ── Queries ─────────────────────────────────────────────────────────────────

function NestService.GetNest(nestId: string)
	return nests[nestId]
end

function NestService.GetNestsInZone(zoneId: string)
	return nestsByZone[zoneId] or {}
end

function NestService.IsSlotFilled(nestId: string, slotIndex: number): boolean
	local nest = nests[nestId]
	if not nest then
		return false
	end
	local slot = nest.Slots[slotIndex]
	return slot ~= nil and slot.Model ~= nil
end

function NestService.CountAvailableEggs(zoneId: string?): number
	local count = 0
	for _, nest in nests do
		if zoneId == nil or nest.ZoneId == zoneId then
			for _, slot in nest.Slots do
				if slot.Model then
					count += 1
				end
			end
		end
	end
	return count
end

-- ── Claiming ────────────────────────────────────────────────────────────────

--[[
	Takes an egg. Returns (ok, reason).

	CONTAINS NO YIELDS, deliberately. Between the "is it there?" check and the
	"it is mine now" write there must be no resumption point, or two players
	holding the same prompt in the same frame both pass the check and both get
	an egg. That is the duplication bug in this system, and yield-freedom is the
	whole defence.

	This is the irreversible step, so it runs LAST in EggService.TryPickup -
	everything that could refuse a pickup refuses before an egg is consumed.
]]
function NestService.ClaimEgg(player: Player, nestId: string, slotIndex: number): (boolean, string?)
	local nest = nests[nestId]
	if not nest then
		return false, "no such nest"
	end

	local slot = nest.Slots[slotIndex]
	if not slot then
		return false, "no such slot"
	end
	if not slot.Model then
		return false, "already taken"
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false, "no character"
	end

	--[[
		Server-side distance check. A ProximityPrompt enforces its own range on
		the CLIENT, which an exploiter simply removes; this is the copy that
		matters. Generous by one prompt-radius so honest players on a laggy
		connection are not punished for latency.
	]]
	local eggPosition = slot.Model:GetPivot().Position
	if (root.Position - eggPosition).Magnitude > GameConfig.InteractRangeStuds then
		return false, "too far"
	end

	-- Committed. Nothing above this line yields, so this is atomic.
	local model = slot.Model
	slot.Model = nil
	slot.Prompt = nil
	slot.RefillAt = os.clock() + nest.RespawnSecs
	model:Destroy()

	Log.debug("NestService", "%s took %s slot %d", player.Name, nestId, slotIndex)
	NestService.EggClaimed:Fire(player, nest, slotIndex)

	return true, nil
end

-- ── Respawn ─────────────────────────────────────────────────────────────────

local function refillSlot(nest, slotIndex: number)
	local slot = nest.Slots[slotIndex]
	if not slot or slot.Model then
		return
	end

	local egg, prompt = NestBuilder.RespawnEgg(nest.Model, slotIndex, slot.Offset, eggTemplate, nest.ZoneId)
	if not egg then
		Log.warn("NestService", "Could not refill %s slot %d", nest.Id, slotIndex)
		return
	end

	slot.Model = egg
	slot.Prompt = prompt
	slot.RefillAt = nil

	prompt.Triggered:Connect(function(player)
		NestService.PickupRequested:Fire(player, nest.Id, slotIndex)
	end)

	NestService.NestRefilled:Fire(nest, slotIndex)
end

local function tickRespawns()
	local now = os.clock()
	for _, nest in nests do
		for slotIndex, slot in nest.Slots do
			if slot.RefillAt and now >= slot.RefillAt then
				refillSlot(nest, slotIndex)
			end
		end
	end
end

-- ── Construction ────────────────────────────────────────────────────────────

local function buildNestAt(anchor: BasePart)
	local zoneId = anchor:GetAttribute("ZoneId")
	local nestIndex = anchor:GetAttribute("NestIndex")

	if not zoneId or not nestIndex then
		Log.warn("NestService", "Anchor %s is missing ZoneId or NestIndex", anchor:GetFullName())
		return
	end

	local zone = ZoneConfig.Zones[zoneId]
	if not zone then
		Log.warn("NestService", "Anchor %s names unknown zone '%s'", anchor.Name, tostring(zoneId))
		return
	end

	local model, slots, guardianSpeciesId = NestBuilder.Build(anchor, zoneId, nestIndex, eggTemplate)
	model.Parent = runtimeFolder

	local nest = {
		Id = model.Name,
		ZoneId = zoneId,
		NestIndex = nestIndex,
		Model = model,
		GuardianSpeciesId = guardianSpeciesId,
		Risk = model:GetAttribute("Risk"),
		RespawnSecs = zone.RespawnSecs,
		Slots = {},
	}

	for slotIndex, slot in slots do
		nest.Slots[slotIndex] = {
			Model = slot.Model,
			Prompt = slot.Prompt,
			Offset = slot.Offset,
			RefillAt = nil,
		}
		slot.Prompt.Triggered:Connect(function(player)
			NestService.PickupRequested:Fire(player, nest.Id, slotIndex)
		end)
	end

	nests[nest.Id] = nest
	nestsByZone[zoneId] = nestsByZone[zoneId] or {}
	table.insert(nestsByZone[zoneId], nest)
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function NestService.Init(app)
	worldFolder = Workspace:FindFirstChild("SAD_World")
	if not worldFolder then
		worldFolder = Instance.new("Folder")
		worldFolder.Name = "SAD_World"
		worldFolder.Parent = Workspace
	end

	local runtime = Workspace:FindFirstChild("SAD_Runtime")
	if runtime then
		runtime:Destroy()
	end
	runtime = Instance.new("Folder")
	runtime.Name = "SAD_Runtime"
	runtime.Parent = Workspace

	runtimeFolder = Instance.new("Folder")
	runtimeFolder.Name = "Nests"
	runtimeFolder.Parent = runtime

	for _, name in { "Guardians", "CarriedEggs", "ParkDinos", "Effects" } do
		local folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = runtime
	end

	local assets = Shared:WaitForChild("SAD_Assets")
	eggTemplate = assets.Eggs:FindFirstChild("Egg_Wild")
	assert(eggTemplate, "[SAD] NestService: SAD_Assets/Eggs/Egg_Wild is missing - did AssetBuilder run?")

	local startedAt = os.clock()
	WorldBuilder.BuildAll(worldFolder)
	Log.info("NestService", "Built hub and %d zone(s) in %.0f ms",
		ZoneConfig.Count(), (os.clock() - startedAt) * 1000)

	--[[
		Forwarded rather than registered in Bootstrap's roster: docs/13 §Step 14
		specifies "a small ZoneService inside NestService", and it works
		entirely on the world built directly above. Init AFTER BuildAll, so its
		Start finds the geometry it binds prompts to.
	]]
	ZoneService.Init(app)
end

function NestService.Start(app)
	--[[
		Discovered by tag, not from WorldBuilder's return value. Generated and
		hand-placed anchors are then indistinguishable, which is what lets a
		Studio-built zone replace a generated one without touching code.

		docs/13 warns that CollectionService tags are lost when a model is
		duplicated in Studio. Anchors here are generated fresh each boot, so
		that cannot bite - but a hand-built zone must have its tags applied to
		the anchors themselves, not inherited from a copied parent.
	]]
	local anchors = CollectionService:GetTagged(WorldBuilder.NEST_ANCHOR_TAG)

	local built = 0
	for _, anchor in anchors do
		if anchor:IsA("BasePart") and anchor:IsDescendantOf(Workspace) then
			buildNestAt(anchor)
			built += 1
		end
	end

	local eggs = NestService.CountAvailableEggs()
	Log.info("NestService", "Built %d nest(s) from %d anchor(s), %d egg(s) available",
		built, #anchors, eggs)

	for _, zoneId in ZoneConfig.Order do
		local zone = ZoneConfig.Zones[zoneId]
		local zoneNests = NestService.GetNestsInZone(zoneId)
		if #zoneNests ~= zone.NestCount then
			Log.warn("NestService", "%s expected %d nests, built %d",
				zoneId, zone.NestCount, #zoneNests)
		end
	end

	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(tickRespawns)
			if not ok then
				Log.error("NestService", "Respawn tick failed: %s", tostring(err))
			end
		end
	end)

	Log.info("NestService", "Respawn ticking at 1 Hz")

	ZoneService.Start(app)
end

--- Zone unlocking, shrines and teleports. See NestService/ZoneService.
NestService.Zones = ZoneService

return NestService
