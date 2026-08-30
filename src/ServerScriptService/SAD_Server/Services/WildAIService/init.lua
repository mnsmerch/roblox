--!nonstrict
--[[
	WildAIService
	ServerScriptService/SAD_Server/Services/WildAIService  (ModuleScript)

	The chase. RUN is the game's signature verb (docs/00 §1) and this is where
	it happens.

	═══ WHY IT IS BUILT THIS WAY ═══════════════════════════════════════════════

	Guardians are DORMANT until their egg is taken. An idle nest has no loop, no
	connection and no physics cost, which is what lets 48 nests exist at once.

	DECISIONS run at 6 Hz; MOVEMENT integrates every frame from the last
	decision. Steering six times a second would look like stop-motion, and
	deciding sixty times a second would cost sixty times as much for an answer
	that changes about as often as the player turns.

	Guardians are ANCHORED and moved by CFrame rather than driven by Humanoids.
	The placeholder models have no rig, a Humanoid each would cost far more than
	the steering does, and CFrame movement is unambiguously server-authoritative
	- there is no assembly whose ownership could drift to a client.

	They pass THROUGH scenery. In a chase that reads as unstoppable rather than
	as broken, and docs/03 already wants Bulldozers smashing through rocks. What
	they cannot pass through is a park boundary, and that is a rule rather than
	a collision.

	═══ WHY IT IS FAIR ═════════════════════════════════════════════════════════

	Guardian speed is a RATIO of the thief's speed sampled at aggro, so upgrades
	never make chases trivial and a new player is never outrun instantly. They
	accelerate over two seconds, giving a guaranteed head start. They rubber-band
	when far behind so they stay on screen. And they cannot hurt you: there is no
	health, no damage and no death anywhere in this file. Being caught trips you
	over and drops your egg, which anyone can then pick up.

	API:
		WildAIService.StartChase(player, nest, token)
		WildAIService.EndChase(player, reason)
		WildAIService.IsChasing(player) -> boolean
		WildAIService.GetActiveCount() -> number
		WildAIService.ChaseStarted / ChaseEnded / ThiefCaught   Signals

	Depends on: ChaseConfig, DinoConfig, GameConfig, ParkService, EggService,
	            NestService, Net, Log, Signal, Trove.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local ChaseConfig = require(Shared.Config.ChaseConfig)
local DinoConfig = require(Shared.Config.DinoConfig)
local GameConfig = require(Shared.Config.GameConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local Log = require(Shared.Modules.Log)
local Net = require(Shared.Modules.Net)
local Signal = require(Shared.Modules.Signal)

local WildAIService = {}

WildAIService.ChaseStarted = Signal.new()
WildAIService.ChaseEnded = Signal.new()
WildAIService.ThiefCaught = Signal.new()

local ParkService, EggService, NestService, PlayerDataService

--- [player] = chase. One guardian per thief; a second steal joins the same one.
local chases: { [Player]: any } = {}
local activeCount = 0

local guardianFolder: Folder = nil
local dinoAssets: Folder = nil

local decisionInterval = 1 / ChaseConfig.DecisionHz
local decisionAccumulator = 0

local groundParams = RaycastParams.new()

-- ── Helpers ─────────────────────────────────────────────────────────────────

--[[
	Set by EventService's Nest Frenzy handler (guardians 20% slower) and reset
	when it ends. A plain field rather than a service lookup: WildAIService
	loads before EventService and the dependency only ever runs one way.
]]
WildAIService.EventSpeedMultiplier = 1

local function flatDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

--- Drops the guardian onto whatever is beneath it. Cheap terrain following
--- without physics, which is all a blockout needs.
local function groundY(position: Vector3, fallback: number): number
	local result = Workspace:Raycast(position + Vector3.new(0, 40, 0), Vector3.new(0, -160, 0), groundParams)
	return if result then result.Position.Y else fallback
end

local function thiefRoot(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

-- ── Spawning ────────────────────────────────────────────────────────────────

local function buildGuardian(speciesId: string, cframe: CFrame): Model?
	local species = DinoConfig.Get(speciesId)
	if not species then
		return nil
	end

	local template = dinoAssets:FindFirstChild(species.ModelName)
	if not template then
		Log.warn("WildAIService", "No model '%s' for guardian '%s'", species.ModelName, speciesId)
		return nil
	end

	local model = template:Clone()
	model.Name = "Guardian_" .. speciesId

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CastShadow = false
		end
	end

	model:PivotTo(cframe)
	model:SetAttribute("SpeciesId", speciesId)
	model.Parent = guardianFolder
	return model
end

-- ── Chase lifecycle ─────────────────────────────────────────────────────────

--[[
	Ends the chase and sends the guardian home.

	The guardian is simply destroyed rather than walked back: at the distances
	involved nobody is watching it return, and a second AI mode for the walk
	home would cost real frames for scenery.
]]
function WildAIService.EndChase(player: Player, reason: string)
	local chase = chases[player]
	if not chase then
		return
	end

	chases[player] = nil
	activeCount -= 1

	if chase.Model then
		chase.Model:Destroy()
	end

	--[[
		Escapes are counted, catches are counted where they happen. The ratio
		between them is the single most diagnostic number about whether the
		chase is tuned - docs/14 targets a 62-75% escape rate, and this is
		where that measurement comes from.
	]]
	if not chase.CaughtAt then
		local data = PlayerDataService.Get(player)
		if data then
			data.Stats.ChasesEscaped += 1
		end
	end

	Net.FireClient("ChaseState", player, { Active = false, Reason = reason })
	Log.debug("WildAIService", "Chase on %s ended: %s", player.Name, reason)
	WildAIService.ChaseEnded:Fire(player, reason, chase)
end

--[[
	Catches the thief. A comedy beat, never a punishment (docs/03 §1.3).

	They trip, they are winded for a few seconds, and every egg they were
	carrying lands on the ground where ANYONE can pick it up. Nothing is
	destroyed and nothing is deducted - the egg goes back to its nest only if
	nobody claims it within ten seconds.
]]
local function catchThief(player: Player, chase)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if humanoid then
		-- PlatformStand is the cheapest thing that reads as "tripped over".
		humanoid.PlatformStand = true
		task.delay(ChaseConfig.TripRagdollSecs, function()
			if humanoid.Parent then
				humanoid.PlatformStand = false
			end
		end)
	end

	EggService.SetSpeedModifier(player, "winded", ChaseConfig.WindedSpeedMult, ChaseConfig.WindedSecs)
	EggService.DropAll(player, "caught")

	chase.CaughtAt = os.clock()

	local data = PlayerDataService.Get(player)
	if data then
		data.Stats.ChasesCaught += 1
	end

	Net.FireClient("ChaseState", player, { Active = true, Caught = true })
	Log.info("WildAIService", "%s was caught by a %s", player.Name, chase.SpeciesId)
	WildAIService.ThiefCaught:Fire(player, chase)
end

--[[
	Starts a chase, or refreshes the one already running.

	Taking a second egg from the same nest does not spawn a second guardian -
	it re-aims the one already after you, which is both cheaper and what a
	player expects.
]]
function WildAIService.StartChase(player: Player, nest, token)
	local existing = chases[player]
	if existing then
		existing.StartedAt = os.clock()
		existing.CaughtAt = nil
		return
	end

	if not nest or not nest.GuardianSpeciesId then
		return
	end

	local species = DinoConfig.Get(nest.GuardianSpeciesId)
	local archetype = ChaseConfig.Get(species and species.ChaseArchetype)

	--[[
		At the cap, recycle the longest-running chase rather than refusing this
		one. Whoever has been running longest gets away - a gift, not a
		punishment - and every steal still gets a real guardian.
	]]
	if activeCount >= ChaseConfig.MaxActiveGuardians then
		local oldest, oldestAt = nil, math.huge
		for otherPlayer, otherChase in chases do
			if otherChase.StartedAt < oldestAt then
				oldest, oldestAt = otherPlayer, otherChase.StartedAt
			end
		end
		if oldest then
			WildAIService.EndChase(oldest, "recycled at guardian cap")
		end
	end

	local root = thiefRoot(player)
	if not root then
		return
	end

	local spawnCFrame = nest.Model:GetPivot() * CFrame.new(0, 3, 0)
	local model = buildGuardian(nest.GuardianSpeciesId, spawnCFrame)
	if not model then
		return
	end

	-- Sampled ONCE, at aggro. A thief who drops their eggs mid-run gets faster;
	-- the guardian does not, which is the reward for dropping them.
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local thiefSpeed = humanoid and humanoid.WalkSpeed or GameConfig.BaseWalkSpeed

	-- Zone bonus: a Frozen Valley guardian is a tougher individual of the same
	-- species than a Jurassic Plains one. Without it the risk skulls on a nest
	-- sign would be decoration.
	local zone = ZoneConfig.Zones[nest.ZoneId]
	local zoneBonus = zone and zone.GuardianSpeedBonus or 0

	local chase = {
		Player = player,
		Nest = nest,
		NestPosition = nest.Model:GetPivot().Position,
		ZoneId = nest.ZoneId,
		SpeciesId = nest.GuardianSpeciesId,
		Archetype = archetype,
		Model = model,
		Position = spawnCFrame.Position,
		Facing = spawnCFrame.LookVector,
		--[[
			The event multiplier is folded in at aggro, alongside the zone
			bonus, so a Nest Frenzy guardian that spawns during the event stays
			slow for the whole chase rather than speeding up when it ends.
		]]
		BaseSpeed = ChaseConfig.SpeedFor(species and species.ChaseArchetype, thiefSpeed, zoneBonus)
			* WildAIService.EventSpeedMultiplier,
		StartedAt = os.clock(),
		--[[
			Seeded to NOW, not to zero, so the first ability fires one full
			cooldown into the chase rather than at the instant of aggro.

			A Charger that charges on frame one closes an eighteen-stud head
			start in three seconds - before the player has run anywhere, and
			before the wind-up can function as a tell. Guardians run first, then
			use their trick.
		]]
		LastAbilityAt = os.clock(),
		WindupUntil = 0,
		AbilityUntil = 0,
		RubberBandUntil = 0,
		OutOfZoneSince = nil,
		CaughtAt = nil,
		CachedDirection = Vector3.zero,
		CachedSpeed = 0,
	}

	chases[player] = chase
	activeCount += 1

	Net.FireClient("ChaseState", player, {
		Active = true,
		SpeciesId = chase.SpeciesId,
		DisplayName = species and species.DisplayName or "Something",
		Archetype = archetype.Id,
	})

	Log.info("WildAIService", "%s is being chased by a %s in %s (%.1f studs/s vs their %.1f)",
		player.Name, chase.SpeciesId, nest.ZoneId, chase.BaseSpeed, thiefSpeed)

	WildAIService.ChaseStarted:Fire(player, chase)
end

function WildAIService.IsChasing(player: Player): boolean
	return chases[player] ~= nil
end

function WildAIService.GetActiveCount(): number
	return activeCount
end

-- ── Decisions ───────────────────────────────────────────────────────────────

--[[
	Speed multiplier from whichever ability phase is running.

	Wind-up first, at reduced speed. That is both the tell the player reacts to
	and the cost that makes the charge fair - a charge that begins instantly is
	not dodgeable, it is a tax.
]]
local function abilityMultiplier(chase, now: number): number
	local archetype = chase.Archetype

	if now < chase.WindupUntil then
		return ChaseConfig.WindupSpeedMultiplier
	end
	if archetype.AbilityMultiplier and archetype.AbilityMultiplier > 1 and now < chase.AbilityUntil then
		return archetype.AbilityMultiplier
	end
	return 1
end

--- Fires an ability if its cooldown has elapsed.
local function tryAbility(chase, now: number, thiefPlayer: Player, distance: number)
	local archetype = chase.Archetype
	if not archetype.Ability or not archetype.AbilityCooldown then
		return
	end
	if now - chase.LastAbilityAt < archetype.AbilityCooldown then
		return
	end

	-- Only within a distance where it would read as aimed at the player.
	if distance > 90 then
		return
	end

	local windup = archetype.AbilityWindupSecs or 0
	chase.LastAbilityAt = now
	chase.WindupUntil = now + windup
	chase.AbilityUntil = chase.WindupUntil + (archetype.AbilityDuration or 0)

	local ability = archetype.Ability

	if ability == "slow" then
		-- Honks and goo: they cannot catch you, they make you catchable.
		-- Applied after the wind-up, so the sound is the warning.
		task.delay(windup, function()
			if chases[thiefPlayer] == chase then
				EggService.SetSpeedModifier(thiefPlayer, "guardian_" .. chase.SpeciesId,
					archetype.AbilityMultiplier or 0.85, archetype.AbilityDuration or 2)
			end
		end)
	elseif ability == "blink" then
		local root = thiefRoot(thiefPlayer)
		if root then
			chase.Position = root.Position - root.CFrame.LookVector * 10
		end
	elseif ability == "glitch" then
		chase.Position += Vector3.new(math.random(-8, 8), 0, math.random(-8, 8))
	end
	-- charge, burst and swoop need no side effect: AbilityMultiplier alone
	-- makes them a burst of speed, which is the whole behaviour.

	-- Sent at the START of the wind-up: this is the tell the player reacts to,
	-- and it is worth nothing if it arrives with the charge.
	Net.FireClient("ChaseState", thiefPlayer, {
		Active = true,
		Ability = ability,
		WindupSecs = windup,
		SpeciesId = chase.SpeciesId,
	})
end

--[[
	One decision tick for one chase. Returns false when the chase should end.

	Everything that ends a chase lives here, in one place, so "why did it stop"
	is always answerable.
]]
local function decide(player: Player, chase, now: number): (boolean, string?)
	local root = thiefRoot(player)
	if not root then
		return false, "thief left"
	end

	local thiefPosition = root.Position

	-- Reaching your own park ends it. Guardians never enter a park (docs/03 §1.4).
	local plot, ownerUserId = ParkService.GetParkAt(thiefPosition)
	if plot and ownerUserId ~= 0 then
		return false, if ownerUserId == player.UserId then "reached safety" else "entered a park"
	end

	-- Lingering after a catch, then giving up.
	if chase.CaughtAt and now - chase.CaughtAt >= ChaseConfig.PostCatchLingerSecs then
		return false, "caught them"
	end

	local elapsed = now - chase.StartedAt
	if elapsed >= chase.Archetype.GiveUpSecs then
		return false, "gave up"
	end
	if elapsed >= GameConfig.ChaseTimeoutSecs then
		return false, "timed out"
	end

	if flatDistance(chase.NestPosition, thiefPosition) > ChaseConfig.MaxChaseDistance then
		return false, "too far from the nest"
	end

	-- Leaving the zone for a sustained period, rather than clipping a corner.
	local zoneOrigin = ZoneConfig.OriginOf(chase.ZoneId)
	if zoneOrigin then
		local localPosition = zoneOrigin:PointToObjectSpace(thiefPosition)
		local half = ZoneConfig.ZoneSize * 0.5
		local outside = math.abs(localPosition.X) > half or math.abs(localPosition.Z) > half
		if outside then
			chase.OutOfZoneSince = chase.OutOfZoneSince or now
			if now - chase.OutOfZoneSince >= ChaseConfig.OutOfZoneGraceSecs then
				return false, "lost them outside the zone"
			end
		else
			chase.OutOfZoneSince = nil
		end
	end

	local distance = flatDistance(chase.Position, thiefPosition)

	if not chase.CaughtAt then
		tryAbility(chase, now, player, distance)
		if distance <= chase.Archetype.Reach then
			catchThief(player, chase)
		end
	end

	-- Rubber band, so a guardian that fell behind stays on screen.
	if distance > ChaseConfig.RubberBandDistance then
		chase.RubberBandUntil = now + ChaseConfig.RubberBandSecs
	end

	--[[
		Steering. Ambushers aim where the player is GOING; everyone else aims
		where they are. TurnRate then limits how fast the guardian can change
		heading, which is what makes a Sprinter beatable by cornering and a
		Skitterer not.
	]]
	local target = thiefPosition
	if chase.Archetype.Ability == "predict" then
		target += root.AssemblyLinearVelocity * 0.6
	end

	local desired = Vector3.new(target.X - chase.Position.X, 0, target.Z - chase.Position.Z)
	if desired.Magnitude > 0.01 then
		desired = desired.Unit

		local maxTurn = chase.Archetype.TurnRate * decisionInterval
		local currentAngle = math.atan2(chase.Facing.Z, chase.Facing.X)
		local desiredAngle = math.atan2(desired.Z, desired.X)

		local delta = (desiredAngle - currentAngle + math.pi) % (math.pi * 2) - math.pi
		local turned = currentAngle + math.clamp(delta, -maxTurn, maxTurn)
		chase.Facing = Vector3.new(math.cos(turned), 0, math.sin(turned))
	end

	local speed = chase.BaseSpeed

	-- Acceleration: they lumber into a run rather than launching.
	speed *= math.min(elapsed / ChaseConfig.AccelerationSecs, 1)
	speed *= abilityMultiplier(chase, now)
	if now < chase.RubberBandUntil then
		speed *= ChaseConfig.RubberBandMultiplier
	end
	if chase.CaughtAt then
		speed = 0 -- stand over them and gloat
	end

	chase.CachedDirection = chase.Facing
	chase.CachedSpeed = speed

	return true, nil
end

-- ── Movement ────────────────────────────────────────────────────────────────

--- Integrates every frame from the last decision, so the AI is cheap without
--- looking like it updates six times a second.
local function integrate(dt: number)
	for _, chase in chases do
		if chase.CachedSpeed <= 0 then
			continue
		end

		local next_ = chase.Position + chase.CachedDirection * chase.CachedSpeed * dt

		local y = if chase.Archetype.Flies
			then groundY(next_, chase.Position.Y) + 14
			else groundY(next_, chase.Position.Y) + 2
		chase.Position = Vector3.new(next_.X, y, next_.Z)

		if chase.Model and chase.Model.PrimaryPart then
			chase.Model:PivotTo(CFrame.lookAt(
				chase.Position,
				chase.Position + chase.CachedDirection,
				Vector3.yAxis
			))
		end
	end
end

local function onHeartbeat(dt: number)
	integrate(dt)

	decisionAccumulator += dt
	if decisionAccumulator < decisionInterval then
		return
	end
	decisionAccumulator = 0

	local now = os.clock()
	local ending = {}

	for player, chase in chases do
		local ok, keepGoing, reason = pcall(decide, player, chase, now)
		if not ok then
			Log.error("WildAIService", "Decision failed for %s: %s", player.Name, tostring(keepGoing))
			table.insert(ending, { player, "error" })
		elseif not keepGoing then
			table.insert(ending, { player, reason or "ended" })
		end
	end

	-- Ended outside the loop: EndChase mutates `chases`.
	for _, entry in ending do
		WildAIService.EndChase(entry[1], entry[2])
	end
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function WildAIService.Init(app)
	ParkService = app.Get("ParkService")
	EggService = app.Get("EggService")
	NestService = app.Get("NestService")
	PlayerDataService = app.Get("PlayerDataService")

	dinoAssets = Shared:WaitForChild("SAD_Assets"):WaitForChild("Dinos")

	local runtime = Workspace:WaitForChild("SAD_Runtime")
	guardianFolder = runtime:WaitForChild("Guardians")

	-- Ground rays must ignore the guardians themselves and anything a player is
	-- standing in, or a guardian rides up its own back.
	groundParams.FilterType = Enum.RaycastFilterType.Exclude
	groundParams.FilterDescendantsInstances = { guardianFolder, runtime }
	groundParams.IgnoreWater = true
end

function WildAIService.Start(app)
	--[[
		Aggro. The pickup is what wakes a guardian - before this fires, that
		nest has no loop, no connection and no cost at all.
	]]
	EggService.EggPickedUp:Connect(function(player, token, nest)
		if nest then
			WildAIService.StartChase(player, nest, token)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		WildAIService.EndChase(player, "left")
	end)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			WildAIService.EndChase(player, "respawned")
		end)
	end)

	RunService.Heartbeat:Connect(onHeartbeat)

	Log.info("WildAIService", "Chase AI ready: decisions at %d Hz, cap %d guardians",
		ChaseConfig.DecisionHz, ChaseConfig.MaxActiveGuardians)
end

return WildAIService
