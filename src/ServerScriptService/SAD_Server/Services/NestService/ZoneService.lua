--!nonstrict
--[[
	ZoneService
	.../Services/NestService/ZoneService  (ModuleScript)

	Zone unlocking, Zone Shrines, and the Teleport Obelisk.

	A submodule of NestService rather than a service of its own, as docs/13
	§Step 14 specifies: it works entirely on the world NestService already
	built and owns no loop of its own. NestService forwards Init and Start.

	═══ WHY TELEPORTING MID-CHASE IS REFUSED ═══════════════════════════════════
	docs/08 §2.2 says the PARK button "teleports you home", and docs/00 §3 makes
	teleports load-bearing for the loop's tempo - measured at 86 seconds on foot
	against a 45-second target.

	But a teleport that works DURING a chase deletes the chase. Steal, tap PARK,
	bank: the only risk in the game, skipped by a button. So a teleport is
	refused while a guardian is actively chasing, and allowed the moment the
	chase ends.

	That is precisely the split deviation #30 already made: the chase resolves
	by ESCAPE, and the walk home afterwards is unopposed. Teleports remove the
	unopposed walk, which is tax, and leave the chase, which is the game.

	Carrying an egg is NOT itself a reason to refuse - once you have escaped,
	you have earned the trip home.
	═══════════════════════════════════════════════════════════════════════════

	API:
		ZoneService.CanUnlock(data, zoneId) -> ok, reason, requirements
		ZoneService.Unlock(player, zoneId) -> ok, reason?
		ZoneService.RegisterShrine(player, zoneId) -> ok, reason?
		ZoneService.Teleport(player, destination) -> ok, reason?
		ZoneService.DestinationCFrame(player, destination) -> CFrame?
		ZoneService.RegisterBlocker(name, fn)   -- fn(player) -> reason?
		ZoneService.ZoneAt(position) -> zoneId?
		ZoneService.ZoneUnlocked / ShrineFound / Teleported   Signals

	Depends on: ZoneConfig, DinoConfig, RarityConfig, PlayerDataService,
	            EconomyService, ParkService, SecurityService, WildAIService.
	Owned by: NestService.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local DinoConfig = require(Shared.Config.DinoConfig)
local Format = require(Shared.Modules.Format)
local Log = require(Shared.Modules.Log)
local Net = require(Shared.Modules.Net)
local RarityConfig = require(Shared.Config.RarityConfig)
local Signal = require(Shared.Modules.Signal)
local ZoneConfig = require(Shared.Config.ZoneConfig)

local ZoneService = {}

ZoneService.ZoneUnlocked = Signal.new()
ZoneService.ShrineFound = Signal.new()
ZoneService.Teleported = Signal.new()

local PlayerDataService, EconomyService, ParkService, SecurityService, WildAIService
local NotificationService

--- One-time Fossil bonus for touching a shrine (docs/02 §2.2).
local SHRINE_BONUS = 500

--[[
	Seconds of movement-check amnesty after a teleport.

	docs/09 §7 requires it: a teleport is, by definition, exactly the
	displacement the plausibility detector exists to catch. Three seconds
	covers the pivot plus the character settling on the ground.
]]
local TELEPORT_EXEMPT_SECS = 3

--- How often locked-zone trespass is checked. 2 Hz over 24 players x 4 zones
--- is 192 point-in-square tests a second - far below anything measurable.
local TRESPASS_INTERVAL = 0.5

--[[
	Reasons a teleport can be refused, contributed by other systems.

	A registry rather than a hardcoded list because the systems that need to
	block one arrive over several steps: the chase in Step 9 (registered
	below), player raiding in Step 15. Each is one line at its own call site
	instead of an edit here.
]]
local blockers: { [string]: (Player) -> string? } = {}

function ZoneService.RegisterBlocker(name: string, fn: (Player) -> string?)
	blockers[name] = fn
end

-- ── Unlocking ───────────────────────────────────────────────────────────────

function ZoneService.CanUnlock(data, zoneId: string)
	return ZoneConfig.UnlockCheck(zoneId, data, DinoConfig, RarityConfig)
end

--[[
	Charges the gate and unlocks the zone. Returns (ok, reason).

	The check and the charge are one transaction: the requirements are
	re-evaluated here, on the server, from the profile - never from anything
	the client sent, which is only ever a zone id.
]]
function ZoneService.Unlock(player: Player, zoneId: string): (boolean, string?)
	local zone = ZoneConfig.Get(zoneId)
	if not zone then
		return false, "no such zone"
	end

	local data = PlayerDataService.Get(player)
	if not data then
		return false, "profile not loaded"
	end

	local ok, reason = ZoneService.CanUnlock(data, zoneId)
	if not ok then
		return false, reason
	end

	local cost = zone.Unlock.Fossils
	if cost > 0 and not EconomyService.TrySpendFossils(player, cost, "unlock " .. zoneId) then
		-- Only reachable if the balance moved between the check and here.
		return false, "not enough Fossils"
	end

	PlayerDataService.UpdateKeys(player, { "ZonesUnlocked" }, function(profile)
		profile.ZonesUnlocked[zoneId] = true
	end, "unlock " .. zoneId)

	ZoneService.ZoneUnlocked:Fire(player, zoneId)

	NotificationService.Takeover(player, {
		Title = "ZONE UNLOCKED",
		Subtitle = zone.Tagline,
		Headline = string.upper(zone.DisplayName),
		Duration = 4,
	})

	Log.info("ZoneService", "%s unlocked %s for %s", player.Name, zoneId, Format.Number(cost))
	return true
end

-- ── Shrines ─────────────────────────────────────────────────────────────────

--[[
	Registers a zone on the player's Obelisk. Idempotent: touching a shrine a
	second time is a no-op, not a second bonus.
]]
function ZoneService.RegisterShrine(player: Player, zoneId: string): (boolean, string?)
	local zone = ZoneConfig.Get(zoneId)
	if not zone then
		return false, "no such zone"
	end

	local data = PlayerDataService.Get(player)
	if not data then
		return false, "profile not loaded"
	end
	if data.Shrines[zoneId] then
		return false, "already registered"
	end

	--[[
		You cannot register a shrine in a zone you have not unlocked. Without
		this, walking past a locked zone's shrine on a bad collision would hand
		out both the bonus and a teleport destination into a zone the player
		has not paid for.
	]]
	if not data.ZonesUnlocked[zoneId] then
		return false, "zone is locked"
	end

	PlayerDataService.UpdateKeys(player, { "Shrines" }, function(profile)
		profile.Shrines[zoneId] = true
	end, "shrine " .. zoneId)

	EconomyService.AddFossils(player, SHRINE_BONUS, "shrine " .. zoneId)
	ZoneService.ShrineFound:Fire(player, zoneId)

	NotificationService.Toast(player, string.upper(zone.DisplayName) .. " SHRINE",
		string.format("On your Obelisk  ·  +%s", Format.Number(SHRINE_BONUS)))

	Log.info("ZoneService", "%s registered the %s shrine", player.Name, zoneId)
	return true
end

-- ── Teleporting ─────────────────────────────────────────────────────────────

--[[
	Where a destination actually puts you.

	Zones land OUTSIDE their gate, not inside. Arriving at the entrance keeps
	the gate the thing you walk through - which is what the 150-stud silhouette
	in docs/02 §1.2 is for - and means a teleport never drops a player past a
	check that walking would have applied.
]]
function ZoneService.DestinationCFrame(player: Player, destination: string): CFrame?
	if destination == "hub" then
		return CFrame.new(0, 8, ZoneConfig.HubRadius * 0.35)
	end

	if destination == "park" then
		local plot = ParkService.GetPlot(player)
		return if plot then ParkService.GetSpawnCFrame(plot) else nil
	end

	local origin = ZoneConfig.OriginOf(destination)
	if not origin then
		return nil
	end

	-- Local +Z faces the hub (the convention PlotBuilder set in Step 6), so
	-- the approach apron is a short step out along +Z from the gate edge.
	local half = ZoneConfig.ZoneSize * 0.5
	return origin * CFrame.new(0, 8, half + 30) * CFrame.Angles(0, math.pi, 0)
end

--- Every reason a teleport is refused right now, or nil.
function ZoneService.TeleportBlocked(player: Player): string?
	for _, fn in blockers do
		local reason = fn(player)
		if reason then
			return reason
		end
	end
	return nil
end

function ZoneService.Teleport(player: Player, destination: string): (boolean, string?)
	local data = PlayerDataService.Get(player)
	if not data then
		return false, "profile not loaded"
	end

	if destination ~= "hub" and destination ~= "park" then
		local zone = ZoneConfig.Get(destination)
		if not zone then
			return false, "no such destination"
		end
		if not data.ZonesUnlocked[destination] then
			return false, "zone is locked"
		end
		--[[
			Unlocked is not enough. docs/02 §2.2 makes the shrine the thing
			that puts a zone on the Obelisk, so the first trip to a zone is
			always walked - which is what teaches the map before the player is
			allowed to skip it.
		]]
		if not data.Shrines[destination] then
			return false, "find its shrine first"
		end
	end

	local blocked = ZoneService.TeleportBlocked(player)
	if blocked then
		return false, blocked
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false, "no character"
	end

	local target = ZoneService.DestinationCFrame(player, destination)
	if not target then
		return false, "destination unavailable"
	end

	-- Before the pivot, never after: the detector samples on its own clock and
	-- a race here is a false positive on a legitimate teleport.
	SecurityService.Exempt(player, TELEPORT_EXEMPT_SECS)
	character:PivotTo(target)

	ZoneService.Teleported:Fire(player, destination)
	Log.debug("ZoneService", "%s teleported to %s", player.Name, destination)
	return true
end

-- ── Trespass ────────────────────────────────────────────────────────────────

--[[
	Which zone contains a world position, if any.

	Delegates to `ZoneConfig.ZoneAt`, which is where the square test moved when
	the minimap and the analytics snapshot turned out to need the same answer.
	Kept as a function here because it is a published part of this service's
	API and three callers already use it.
]]
function ZoneService.ZoneAt(position: Vector3): string?
	return ZoneConfig.ZoneAt(position)
end

--[[
	Walks a trespasser back out of a locked zone.

	The barrier across each gate is COSMETIC - a part cannot be solid for one
	player and not another, so the client hides the ones it has unlocked and
	this is what actually enforces the gate. Positional, on the server, from
	server state: exactly the same shape as every other check in the project.
]]
local function checkTrespass(player: Player)
	local data = PlayerDataService.Get(player)
	if not data then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	local zoneId = ZoneService.ZoneAt(root.Position)
	if not zoneId or data.ZonesUnlocked[zoneId] then
		return
	end

	local zone = ZoneConfig.Get(zoneId)
	local target = ZoneService.DestinationCFrame(player, zoneId)
	if not target then
		return
	end

	SecurityService.Exempt(player, TELEPORT_EXEMPT_SECS)
	character:PivotTo(target)

	NotificationService.Toast(player, string.upper(zone.DisplayName) .. " IS LOCKED",
		string.format("%s Fossils to open", Format.Number(zone.Unlock.Fossils)))
end

-- ── Prompts ─────────────────────────────────────────────────────────────────

--[[
	Binds the world objects WorldBuilder tagged.

	Prompts are created here rather than in the builder for the same reason the
	incubator pads are: the builder describes geometry, and a prompt is
	behaviour. A zone with hand-built geometry only has to carry the
	attributes.
]]
local function bindWorld()
	local world = Workspace:FindFirstChild("SAD_World")
	if not world then
		return 0, 0
	end

	local shrines, obelisks = 0, 0

	for _, descendant in world:GetDescendants() do
		local shrineZone = descendant:GetAttribute("ShrineZone")
		if shrineZone and descendant:IsA("BasePart") then
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Register"
			prompt.ObjectText = "ZONE SHRINE"
			prompt.HoldDuration = 0.5
			prompt.MaxActivationDistance = 12
			prompt.RequiresLineOfSight = false
			prompt.Parent = descendant
			prompt.Triggered:Connect(function(player)
				ZoneService.RegisterShrine(player, shrineZone)
			end)
			shrines += 1

		elseif descendant:GetAttribute("ZoneGate") and descendant:IsA("BasePart") then
			--[[
				The unlock prompt lives on the gate, so a player who has walked
				to a locked zone can buy it from where they are standing rather
				than being told to find a menu.
			]]
			local zoneId = descendant:GetAttribute("ZoneGate")
			local zone = ZoneConfig.Get(zoneId)
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Unlock"
			prompt.ObjectText = string.format("%s  ·  %s Fossils",
				string.upper(zone.DisplayName), Format.Number(zone.Unlock.Fossils))
			prompt.HoldDuration = 1
			prompt.MaxActivationDistance = 30
			prompt.RequiresLineOfSight = false
			prompt.Parent = descendant
			prompt.Triggered:Connect(function(player)
				local ok, reason = ZoneService.Unlock(player, zoneId)
				if not ok and reason then
					NotificationService.Toast(player, string.upper(zone.DisplayName), reason)
				end
			end)

		elseif descendant:GetAttribute("TeleportObelisk") and descendant:IsA("BasePart") then
			--[[
				The Obelisk opens the same wheel the GO button does. Purely
				client-side: the destination list is already replicated, and
				every destination is re-validated on the server when one is
				chosen.
			]]
			obelisks += 1
		end
	end

	return shrines, obelisks
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function ZoneService.Init(app)
	PlayerDataService = app.Get("PlayerDataService")
	NotificationService = app.Get("NotificationService")
	EconomyService = app.Get("EconomyService")
	ParkService = app.Get("ParkService")
	SecurityService = app.Get("SecurityService")
end

function ZoneService.Start(app)
	WildAIService = app.Get("WildAIService")

	--[[
		The one blocker V1 ships with. See the header for why: a teleport
		during a chase is the chase deleted.
	]]
	ZoneService.RegisterBlocker("chase", function(player)
		return if WildAIService.IsChasing(player) then "not while you are being chased" else nil
	end)

	Net.OnEvent("RequestUnlockZone", function(player, zoneId)
		if type(zoneId) ~= "string" then
			return
		end
		local ok, reason = ZoneService.Unlock(player, zoneId)
		if not ok and reason then
			NotificationService.Toast(player, "CANNOT UNLOCK", reason)
		end
	end)

	Net.OnEvent("RequestTeleport", function(player, destination)
		if type(destination) ~= "string" then
			return
		end
		local ok, reason = ZoneService.Teleport(player, destination)
		if not ok and reason then
			NotificationService.Toast(player, "CANNOT TRAVEL", reason)
		end
	end)

	local shrines, obelisks = bindWorld()

	task.spawn(function()
		while true do
			task.wait(TRESPASS_INTERVAL)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(checkTrespass, player)
				if not ok then
					Log.error("ZoneService", "Trespass check failed for %s: %s", player.Name, tostring(err))
				end
			end
		end
	end)

	Log.info("ZoneService", "Ready. %d shrine(s), %d obelisk(s), %d zone(s)",
		shrines, obelisks, ZoneConfig.Count())
end

return ZoneService
