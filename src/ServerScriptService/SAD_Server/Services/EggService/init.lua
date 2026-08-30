--!nonstrict
--[[
	EggService
	ServerScriptService/SAD_Server/Services/EggService  (ModuleScript)

	The pickup, the roll, and the carry. The first half of the game's signature
	verb; Steps 9 and 10 add the chase and the deposit.

	═══ THE CARRY TOKEN IS THE ONLY AUTHORITY ══════════════════════════════════
	A carried egg is NOT in the player's profile. It exists as a server-side
	token and nothing else, which is what makes leaving mid-carry cost the
	player exactly what it should: the egg goes back to its nest and the profile
	is untouched. Putting it in the profile would make disconnecting a way to
	bank a Titan egg without ever surviving the chase.

	The model welded to the character is COSMETIC. It is client-owned physics,
	because a part welded to a character belongs to that character's assembly
	and there is no way around that - but it carries no authority. Deleting it,
	duplicating it or editing its attributes changes nothing the server
	believes.
	═══════════════════════════════════════════════════════════════════════════

	Rarity is rolled HERE, at pickup, server-side (docs/03 §1.1). Species and
	mutation wait for the hatch, so one egg pays out three separate reveals.

	API:
		EggService.TryPickup(player, nestId, slotIndex) -> ok, reason?
		EggService.Drop(player, eggUid, reason?) -> ok
		EggService.DropAll(player, reason?)
		EggService.GetCarried(player) -> { [uid]: token }
		EggService.GetCarryCount(player) -> number
		EggService.GetCapacity(player) -> number
		EggService.GetCarryPenalty(player) -> number     0..MaxCarryPenalty
		EggService.ComputeLuck(player, zoneId) -> number
		EggService.TakeToken(player, uid) -> token?
		EggService.DepositAll(player) -> deposited, refused

		EggService.EggPickedUp   Signal(player, token, nest)
		EggService.EggDropped    Signal(player, token, reason)
		EggService.EggDeposited  Signal(player, token, eggUid)
		EggService.RareGrab      Signal(player, token)   Legendary+, for Step 16

	Depends on: NestService, SecurityService, PlayerDataService, ParkService,
	            RarityConfig, ZoneConfig, UpgradeConfig, RebirthConfig, RNG.
	Depended on by: WildAIService (Step 9), IncubationService (Step 10).
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local GameConfig = require(Shared.Config.GameConfig)
local RarityConfig = require(Shared.Config.RarityConfig)
local RebirthConfig = require(Shared.Config.RebirthConfig)
local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local Log = require(Shared.Modules.Log)
local Net = require(Shared.Modules.Net)
local RNG = require(Shared.Modules.RNG)
local Signal = require(Shared.Modules.Signal)
local Stats = require(Shared.Modules.Stats)

local EggService = {}

EggService.EggPickedUp = Signal.new()
EggService.EggDropped = Signal.new()
EggService.RareGrab = Signal.new()
EggService.EggDeposited = Signal.new()

local NestService, SecurityService, PlayerDataService, ParkService, NotificationService

--- [player] = { [eggUid] = token }. Server-only, never replicated, never saved.
local carried: { [Player]: { [string]: any } } = {}

--- Eggs lying in the world after a drop, grabbable by anyone for a few seconds.
local loose: { [string]: any } = {}

--[[
	Temporary speed effects, keyed so each source owns exactly one.

	modifiers[player][key] = { Multiplier, ExpiresAt }

	Lives here because EggService already owns the one function that decides a
	player's speed. A guardian's honk, a spitter's goo, being winded after a
	trip, and Step 17's weather all multiply into the same place rather than
	each writing WalkSpeed and clobbering the others.
]]
local modifiers: { [Player]: { [string]: any } } = {}

local rng = RNG.new()
local eggTemplates: Folder = nil
local looseFolder: Folder = nil
local carryFolder: Folder = nil
local luckPowers = nil

-- ── Luck ────────────────────────────────────────────────────────────────────

--[[
	The player's current Luck for a roll in `zoneId`, as an additive fraction.

	Sources that exist today are read for real; the rest land with their steps
	and are listed so nobody has to go hunting for what is missing:
	  * Egg Sense upgrade          live
	  * rebirths                   live
	  * zone base bonus            live
	  * DNA luck nodes             live
	  * index milestones           Step 19
	  * potions and server boosts  Step 18 / 21
	  * Lucky Player gamepass      Step 21
]]
function EggService.ComputeLuck(player: Player, zoneId: string): number
	local data = PlayerDataService.Get(player)
	if not data then
		return 0
	end
	return EggService.LuckFrom(data, ZoneConfig.Zones[zoneId])
end

--- The luck composition itself, as a pure function of profile and zone.
--- Split out so the formula is covered by tests rather than only by playing.
function EggService.LuckFrom(data, zone): number
	-- Stats owns the upgrade + rebirth + node composition and the 4.0 cap.
	local luck = Stats.Luck(data)

	if zone then
		luck += zone.LuckBonus
	end

	-- Hard cap from docs/01 §1.2: luck must not be able to buy the tail.
	return math.clamp(luck, 0, 5.0)
end

--[[
	Rolls a rarity for an egg taken from `zoneId`.

	Server-side, from server state, with a server RNG. The client is told the
	result and never participates in producing it.
]]
function EggService.RollRarity(player: Player, zoneId: string): string
	return EggService.RollRarityIn(zoneId, EggService.ComputeLuck(player, zoneId))
end

--- The roll itself, given a zone and a luck value. Pure apart from the RNG,
--- which is why the odds in docs/01 can be asserted directly.
function EggService.RollRarityIn(zoneId: string, luck: number, generator: Random?): string
	local weights = RarityConfig.WeightsForZone(zoneId)
	if not weights then
		Log.error("EggService", "No weight vector for zone '%s'", tostring(zoneId))
		return "common"
	end

	local scaled = RNG.ApplyLuck(weights, luckPowers or RarityConfig.LuckPowers(), luck)
	return RNG.WeightedPick(scaled, generator or rng, RarityConfig.Order) or "common"
end

-- ── Carry weight ────────────────────────────────────────────────────────────

function EggService.GetCarried(player: Player)
	return carried[player] or {}
end

function EggService.GetCarryCount(player: Player): number
	local count = 0
	for _ in EggService.GetCarried(player) do
		count += 1
	end
	return count
end

function EggService.GetCapacity(player: Player): number
	local data = PlayerDataService.Get(player)
	if not data then
		return 1
	end
	return Stats.EggCapacity(data)
end

--[[
	Total speed penalty, 0 to MaxCarryPenalty.

	The heaviest egg counts in full and each additional one contributes only
	MultiCarryEffectiveness of its own weight (docs/03 §1.2), so a second egg is
	a real decision rather than a free upgrade. Strong Back then scales the
	whole thing down.
]]
function EggService.GetCarryPenalty(player: Player): number
	local penalties = {}
	for _, token in EggService.GetCarried(player) do
		table.insert(penalties, token.Penalty)
	end

	local data = PlayerDataService.Get(player)
	local strongBack = data and Stats.CarryPenaltyMult(data) or 1

	return EggService.CarryPenaltyOf(penalties, strongBack)
end

--[[
	The stacking rule itself, as a pure function.

	Heaviest egg in full, each additional one at MultiCarryEffectiveness of its
	own weight, then scaled by Strong Back and clamped. Split out because these
	are the numbers docs/03 §1.2 publishes, and a published number that the code
	does not actually produce is worse than no number at all.
]]
function EggService.CarryPenaltyOf(penalties: { number }, strongBackMult: number?): number
	if #penalties == 0 then
		return 0
	end

	local sorted = table.clone(penalties)
	table.sort(sorted, function(a, b)
		return a > b
	end)

	local total = sorted[1]
	for index = 2, #sorted do
		total += sorted[index] * GameConfig.MultiCarryEffectiveness
	end

	total *= (strongBackMult or 1)
	return math.clamp(total, 0, GameConfig.MaxCarryPenalty)
end

--[[
	Applies a temporary speed effect. `key` identifies the source, so a second
	honk refreshes the first rather than stacking into immobility.
	`multiplier` below 1 slows; nil duration means it lasts until cleared.
]]
function EggService.SetSpeedModifier(player: Player, key: string, multiplier: number, duration: number?)
	local held = modifiers[player]
	if not held then
		held = {}
		modifiers[player] = held
	end

	held[key] = {
		Multiplier = multiplier,
		ExpiresAt = if duration then os.clock() + duration else math.huge,
	}
	EggService.ApplySpeed(player)
end

function EggService.ClearSpeedModifier(player: Player, key: string)
	local held = modifiers[player]
	if held and held[key] then
		held[key] = nil
		EggService.ApplySpeed(player)
	end
end

--- Product of every live modifier, dropping any that have expired.
local function modifierProduct(player: Player): number
	local held = modifiers[player]
	if not held then
		return 1
	end

	local now = os.clock()
	local product = 1
	for key, entry in held do
		if now >= entry.ExpiresAt then
			held[key] = nil
		else
			product *= entry.Multiplier
		end
	end
	return product
end

--- Re-applies WalkSpeed and tells SecurityService what to measure against.
local function applySpeed(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	local data = PlayerDataService.Get(player)
	-- Stats folds Runner's Legs and the rebirth grant into one multiplier.
	local speedMult = data and Stats.MoveSpeedMult(data) or 1

	local speed = GameConfig.BaseWalkSpeed * speedMult
	speed *= (1 - EggService.GetCarryPenalty(player))
	speed *= modifierProduct(player)

	if humanoid then
		humanoid.WalkSpeed = speed
	end

	-- The budget movement plausibility is measured against. A client that
	-- edits its own WalkSpeed is then measured against what the SERVER
	-- intended, not against whatever it claims.
	SecurityService.SetMaxSpeed(player, speed)
end

EggService.ApplySpeed = applySpeed

-- ── Visuals ─────────────────────────────────────────────────────────────────

--[[
	Builds the carried egg and welds it above the player's head.

	Massless and non-colliding so it cannot affect how the character moves.
	Welded, which means it joins the character's assembly and is simulated on
	that player's client - unavoidable, and harmless, because this model carries
	no authority. The token does.
]]
local function attachEgg(player: Player, token)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end

	local template = eggTemplates:FindFirstChild("Egg_" .. token.Rarity)
		or eggTemplates:FindFirstChild("Egg_Wild")
	if not template then
		return nil
	end

	local model = template:Clone()
	model.Name = "CarriedEgg_" .. token.Uid

	local tier = RarityConfig.Tiers[token.Rarity]

	-- Stack multiple eggs so a two-egg carry reads at a glance.
	local index = EggService.GetCarryCount(player)
	local height = 3.6 + index * 2.2

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.Massless = true
			descendant.CastShadow = false
		end
	end

	local shell = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	model:PivotTo(root.CFrame * CFrame.new(0, height, 0))

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = shell
	weld.Part1 = root
	weld.Parent = shell

	--[[
		Epic and above emit a visible beam (docs/03 §1.1). This is the
		mechanic that turns a solo pickup into a server-wide event: everyone
		can see what you are carrying, and decide to come and take it.
	]]
	if tier.Rank >= 4 then
		local light = Instance.new("PointLight")
		light.Color = RarityConfig.GetColor(token.Rarity)
		light.Brightness = 4
		light.Range = 26
		light.Parent = shell

		local beacon = Instance.new("Part")
		beacon.Name = "Beacon"
		beacon.Size = Vector3.new(1.6, 260, 1.6)
		beacon.Color = RarityConfig.GetColor(token.Rarity)
		beacon.Material = Enum.Material.Neon
		beacon.Transparency = 0.72
		beacon.CanCollide = false
		beacon.Massless = true
		beacon.CastShadow = false
		beacon.CFrame = shell.CFrame * CFrame.new(0, 130, 0)
		beacon.Parent = model

		local beaconWeld = Instance.new("WeldConstraint")
		beaconWeld.Part0 = beacon
		beaconWeld.Part1 = shell
		beaconWeld.Parent = beacon
	end

	-- The client reads carry state off these attributes rather than through a
	-- dedicated remote: the model is already replicated to everyone, so
	-- observers get the same information for free.
	model:SetAttribute("EggUid", token.Uid)
	model:SetAttribute("Rarity", token.Rarity)
	model:SetAttribute("Origin", token.Origin)
	model:SetAttribute("CarrierUserId", player.UserId)

	model.Parent = character
	return model
end

local function detachEgg(token)
	if token.Model then
		token.Model:Destroy()
		token.Model = nil
	end
end

-- ── Loose eggs ──────────────────────────────────────────────────────────────

local function returnLooseToNest(entry)
	loose[entry.Uid] = nil
	if entry.Model then
		entry.Model:Destroy()
	end

	-- Hand the slot back so the nest refills on its normal timer rather than
	-- staying permanently one egg short.
	local nest = NestService.GetNest(entry.NestId)
	if nest then
		local slot = nest.Slots[entry.SlotIndex]
		if slot and not slot.Model and not slot.RefillAt then
			slot.RefillAt = os.clock()
		end
	end
end

--[[
	Drops an egg into the world, grabbable by ANYONE for a few seconds.

	This is the mechanic behind the best free moment in the design: a loose
	Mythic egg on the ground with three players sprinting at it (docs/15).
	Step 9 uses the same path when a guardian catches someone.
]]
local function spawnLoose(token, position: Vector3)
	local template = eggTemplates:FindFirstChild("Egg_" .. token.Rarity)
		or eggTemplates:FindFirstChild("Egg_Wild")
	if not template then
		return
	end

	local model = template:Clone()
	model.Name = "LooseEgg_" .. token.Uid
	model:PivotTo(CFrame.new(position + Vector3.new(0, 2, 0)))

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CastShadow = false
		end
	end

	local shell = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "GrabPrompt"
	prompt.ActionText = "Grab Egg"
	prompt.ObjectText = RarityConfig.Tiers[token.Rarity].DisplayName
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = shell

	local entry = {
		Uid = token.Uid,
		Rarity = token.Rarity,
		Origin = token.Origin,
		NestId = token.NestId,
		SlotIndex = token.SlotIndex,
		Penalty = token.Penalty,
		-- Event eggs are guaranteed to hatch mutated; the flag rides the whole
		-- way from the crater to the incubator rather than being re-derived.
		Mutated = token.Mutated,
		Model = model,
		ExpiresAt = os.clock() + GameConfig.LooseEggLifetimeSecs,
	}

	model:SetAttribute("EggUid", token.Uid)
	model:SetAttribute("Rarity", token.Rarity)

	prompt.Triggered:Connect(function(grabber: Player)
		EggService.GrabLoose(grabber, entry.Uid)
	end)

	loose[entry.Uid] = entry
	model.Parent = looseFolder
end

--[[
	Puts an egg on the ground that came from no nest.

	Step 18's events need this: a meteor crater and a parachute drop are eggs
	that exist without anyone having stolen them. Everything downstream - the
	grab prompt, the carry token, the deposit - is the same path a dropped egg
	takes, so an event egg is never a second kind of egg.

	`params` takes Rarity, Origin and an optional Mutated flag. Returns the uid.
]]
function EggService.SpawnEventEgg(params, position: Vector3): string
	local tier = RarityConfig.Tiers[params.Rarity]
	local token = {
		Uid = string.sub(HttpService:GenerateGUID(false):gsub("-", ""), 1, 8),
		Rarity = params.Rarity,
		Origin = params.Origin or "plains",
		Penalty = tier and tier.CarryPenalty or 0.2,
		Mutated = params.Mutated == true,
	}
	spawnLoose(token, position)
	return token.Uid
end

--- Picks up an egg someone dropped. Anyone may, which is the point.
function EggService.GrabLoose(player: Player, uid: string): (boolean, string?)
	local entry = loose[uid]
	if not entry then
		return false, "gone"
	end

	if EggService.GetCarryCount(player) >= EggService.GetCapacity(player) then
		return false, "hands full"
	end

	local ok, reason = SecurityService.CheckDistance(player, entry.Model:GetPivot().Position)
	if not ok then
		return false, reason
	end

	-- Committed, and nothing above yields.
	loose[uid] = nil
	entry.Model:Destroy()

	local token = {
		Uid = entry.Uid,
		Rarity = entry.Rarity,
		Origin = entry.Origin,
		NestId = entry.NestId,
		SlotIndex = entry.SlotIndex,
		Penalty = entry.Penalty,
		Mutated = entry.Mutated,
		GrantedAt = os.time(),
	}

	carried[player] = carried[player] or {}
	carried[player][token.Uid] = token
	token.Model = attachEgg(player, token)
	applySpeed(player)

	Log.debug("EggService", "%s grabbed a loose %s egg", player.Name, token.Rarity)
	EggService.EggPickedUp:Fire(player, token, nil)
	return true, nil
end

-- ── Pickup ──────────────────────────────────────────────────────────────────

--[[
	Takes an egg from a nest. Returns (ok, reason).

	Order matters: everything that can refuse runs BEFORE NestService.ClaimEgg,
	because claiming is the irreversible step. Refusing after the claim would
	destroy an egg nobody gets.
]]
function EggService.TryPickup(player: Player, nestId: string, slotIndex: number): (boolean, string?)
	local data = PlayerDataService.Get(player)
	if not data then
		return false, "profile not loaded"
	end

	if EggService.GetCarryCount(player) >= EggService.GetCapacity(player) then
		return false, "hands full"
	end

	local nest = NestService.GetNest(nestId)
	if not nest then
		return false, "no such nest"
	end

	if not data.ZonesUnlocked[nest.ZoneId] then
		return false, "zone locked"
	end

	-- NestService re-checks distance itself; this reports it before the claim
	-- so a rejected pickup never consumes an egg.
	local slot = nest.Slots[slotIndex]
	if not slot or not slot.Model then
		return false, "already taken"
	end

	local inRange, rangeReason = SecurityService.CheckDistance(player, slot.Model:GetPivot().Position)
	if not inRange then
		return false, rangeReason
	end

	local claimed, claimReason = NestService.ClaimEgg(player, nestId, slotIndex)
	if not claimed then
		return false, claimReason
	end

	-- REVEAL #1. Rolled here, from server state, with a server RNG.
	local rarity = EggService.RollRarity(player, nest.ZoneId)
	local tier = RarityConfig.Tiers[rarity]

	local token = {
		Uid = string.sub(HttpService:GenerateGUID(false):gsub("-", ""), 1, 8),
		Rarity = rarity,
		Origin = nest.ZoneId,
		NestId = nestId,
		SlotIndex = slotIndex,
		Penalty = tier.CarryPenalty,
		GrantedAt = os.time(),
	}

	carried[player] = carried[player] or {}
	carried[player][token.Uid] = token
	token.Model = attachEgg(player, token)
	applySpeed(player)

	Log.info("EggService", "%s took a %s egg from %s (luck %.2f)",
		player.Name, rarity, nestId, EggService.ComputeLuck(player, nest.ZoneId))

	EggService.EggPickedUp:Fire(player, token, nest)

	-- Legendary and above tells the whole server, which is what turns a
	-- pickup into a chase with more than one participant (docs/03 §1.1).
	if tier.Rank >= 5 then
		EggService.RareGrab:Fire(player, token)
		Log.info("EggService", "RARE GRAB: %s is carrying a %s egg", player.Name, tier.DisplayName)
	end

	return true, nil
end

-- ── Drop ────────────────────────────────────────────────────────────────────

function EggService.Drop(player: Player, uid: string, reason: string?): boolean
	local held = carried[player]
	local token = held and held[uid]
	if not token then
		return false
	end

	held[uid] = nil

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local position = root and root.Position or Vector3.zero

	detachEgg(token)
	spawnLoose(token, position)
	applySpeed(player)

	-- Losing a carried egg is tracked separately from banking one: the gap
	-- between EggsStolen and EggsLost is how well a player actually runs.
	local data = PlayerDataService.Get(player)
	if data then
		data.Stats.EggsLost += 1
	end

	Log.debug("EggService", "%s dropped a %s egg (%s)", player.Name, token.Rarity, reason or "manual")
	EggService.EggDropped:Fire(player, token, reason or "manual")
	return true
end

function EggService.DropAll(player: Player, reason: string?)
	for uid in EggService.GetCarried(player) do
		EggService.Drop(player, uid, reason)
	end
end

--[[
	Removes a token from a player and hands it over. Step 10 calls this when an
	egg crosses a park gate: the token stops existing here and becomes a profile
	entry there, with no window in between where it exists in both places.
]]
function EggService.TakeToken(player: Player, uid: string)
	local held = carried[player]
	local token = held and held[uid]
	if not token then
		return nil
	end

	held[uid] = nil
	detachEgg(token)
	applySpeed(player)
	return token
end

--[[
	Resolves everything a leaving player was carrying.

	Wild eggs go straight back to their nests. Nothing is banked, because a
	carried egg was never in the profile - which is exactly what stops
	disconnecting from being a way to keep a Titan egg without surviving the run.
]]
function EggService.ResolveTokens(player: Player)
	local held = carried[player]
	carried[player] = nil
	if not held then
		return
	end

	for _, token in held do
		detachEgg(token)

		local nest = NestService.GetNest(token.NestId)
		if nest then
			local slot = nest.Slots[token.SlotIndex]
			if slot and not slot.Model and not slot.RefillAt then
				slot.RefillAt = os.clock()
			end
		end
	end

	Log.info("EggService", "Returned %s's carried egg(s) to their nests", player.Name)
end

-- ── Deposit ─────────────────────────────────────────────────────────────────

--- Fires the Notify remote directly. Step 16's NotificationService takes over
--- the dispatch; until then this is the only feedback path that exists.
local function notify(player: Player, kind: string, text: string, color: Color3?)
	NotificationService.Send(player, {
		Kind = kind,
		Text = text,
		Color = color,
		Duration = 2.5,
	})
end

--[[
	Banks everything the player is carrying. Returns (deposited, refused).

	This is the moment the run pays off, and the moment a carried egg stops
	being a token and becomes profile data. Each egg moves in ONE step -
	TakeToken removes it from the carry table and the same block writes it into
	the profile, with no resumption point between where it could exist in both
	places or in neither.

	A full store refuses rather than destroys. The player keeps carrying the
	egg and is told why.
]]
function EggService.DepositAll(player: Player): (number, number)
	local data = PlayerDataService.Get(player)
	if not data then
		return 0, 0
	end

	local held = carried[player]
	if not held or not next(held) then
		return 0, 0
	end

	-- Snapshot the uids: TakeToken mutates the table being iterated.
	local uids = {}
	for uid in held do
		table.insert(uids, uid)
	end

	local stored = 0
	for _ in data.Eggs do
		stored += 1
	end

	local deposited, refused = 0, 0

	for _, uid in uids do
		if stored >= GameConfig.EggStorageCap then
			refused += 1
			continue
		end

		local token = EggService.TakeToken(player, uid)
		if token then
			data.Eggs[token.Uid] = {
				Rarity = token.Rarity,
				Origin = token.Origin,
				AcquiredAt = os.time(),
				-- Only written when true, so an ordinary egg's entry keeps the
				-- exact three-field shape docs/10 §1 publishes.
				Mutated = if token.Mutated then true else nil,
			}
			stored += 1
			deposited += 1
			data.Stats.EggsStolen += 1
			EggService.EggDeposited:Fire(player, token, token.Uid)
		end
	end

	if deposited > 0 then
		-- One replication flush for the whole deposit rather than one per egg.
		PlayerDataService.UpdateKeys(player, { "Eggs", "Stats" }, function() end, "deposit")

		local suffix = if deposited > 1 then string.format(" (%d eggs)", deposited) else ""
		notify(player, "banner", "SAFE!" .. suffix, Color3.fromHex("5FD35F"))

		Log.info("EggService", "%s banked %d egg(s)", player.Name, deposited)
	end

	if refused > 0 then
		notify(player, "alert",
			string.format("Egg storage full - hatch some first (%d)", refused),
			Color3.fromHex("FF4B3E"))
	end

	return deposited, refused
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function EggService.Init(app)
	NestService = app.Get("NestService")
	SecurityService = app.Get("SecurityService")
	PlayerDataService = app.Get("PlayerDataService")
	NotificationService = app.Get("NotificationService")
	ParkService = app.Get("ParkService")

	luckPowers = RarityConfig.LuckPowers()

	eggTemplates = Shared:WaitForChild("SAD_Assets"):WaitForChild("Eggs")

	local runtime = Workspace:WaitForChild("SAD_Runtime")
	carryFolder = runtime:WaitForChild("CarriedEggs")

	looseFolder = Instance.new("Folder")
	looseFolder.Name = "LooseEggs"
	looseFolder.Parent = runtime
end

function EggService.Start(app)
	Net.OnEvent("RequestPickupEgg", function(player: Player, nestId: string, slotIndex: number)
		EggService.TryPickup(player, nestId, slotIndex)
	end)

	Net.OnEvent("RequestDropEgg", function(player: Player, eggUid: string)
		EggService.Drop(player, eggUid, "manual")
	end)

	--[[
		Manual deposit, for a player standing in their park with a refused egg
		after freeing up space. The server re-checks that they are actually
		home - the remote is a request, not an assertion.
	]]
	Net.OnEvent("RequestDepositEggs", function(player: Player)
		if ParkService.IsInsideOwnPark(player) then
			EggService.DepositAll(player)
		end
	end)

	--[[
		THE SAFE ZONE.

		Crossing your own gate banks everything you are carrying. Detected from
		ParkService's server-side position sampling, never from a client claim
		or a Touched event - "I reached my park" is exactly the assertion an
		exploiter would like to make from anywhere on the map (docs/03 §6).

		ParkEntered fires once per transition, so loitering in the gateway
		cannot produce a second deposit.
	]]
	ParkService.ParkEntered:Connect(function(player: Player, ownerUserId: number)
		if ownerUserId == player.UserId then
			EggService.DepositAll(player)
		end
	end)

	-- An implausible move voids the carry outright. This is the defence against
	-- teleport-to-nest, grab, teleport-home (docs/03 §6).
	SecurityService.CarryVoided:Connect(function(player, reason)
		if EggService.GetCarryCount(player) > 0 then
			EggService.DropAll(player, reason)
		end
	end)

	PlayerDataService.ProfileUnloading:Connect(function(player)
		EggService.ResolveTokens(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		EggService.ResolveTokens(player)
		modifiers[player] = nil
	end)

	--[[
		Modifiers expire on their own clock, but WalkSpeed only changes when
		something recomputes it. Without this sweep a honk would keep a player
		slowed until the next time they happened to pick up or drop an egg.
	]]
	task.spawn(function()
		while true do
			task.wait(0.25)

			local now = os.clock()
			for player, held in modifiers do
				local expired = false
				for key, entry in held do
					if now >= entry.ExpiresAt then
						held[key] = nil
						expired = true
					end
				end
				if expired and player.Parent then
					applySpeed(player)
				end
			end
		end
	end)

	-- A carried egg does not survive a respawn: the model was welded to a
	-- character that no longer exists.
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			task.defer(function()
				EggService.DropAll(player, "respawned")
				applySpeed(player)
			end)
		end)
	end)

	-- Loose eggs return to their nests when nobody claims them.
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			for _, entry in loose do
				if now >= entry.ExpiresAt then
					returnLooseToNest(entry)
				end
			end
		end
	end)

	Log.info("EggService", "Ready. Loose eggs last %ds", GameConfig.LooseEggLifetimeSecs)
end

return EggService
