--!nonstrict
--[[
	StealService
	ServerScriptService/SAD_Server/Services/StealService  (ModuleScript)

	Player raiding: the whole state machine from docs/03 §4.

	═══ THE DINOSAUR NEVER LEAVES ITS OWNER UNTIL THE GATE ═════════════════════
	docs/03 §4.6 says ownership does not transfer until the thief reaches their
	own Park Gate, and §4.9 says a disconnect mid-carry loses nothing. Both are
	satisfied by the same choice: while carried, the dinosaur stays in the
	OWNER's profile, and the carry itself is a server-only token holding a
	reference to it.

	The alternative - remove it at lift, re-add it at the gate - has a window
	where the dinosaur exists only in server memory. A crash there deletes it.
	This way the worst case is that the owner keeps their dinosaur, which is
	the direction an error should fall.

	The cost is that the owner must be ONLINE for the transfer to complete.
	docs/03 §4.3 already makes offline parks fully raid-immune, so a raid
	against someone who leaves mid-carry is voided rather than resolved. See
	the note in PROGRESS.md: this does mean disconnecting saves your dinosaur.
	═══════════════════════════════════════════════════════════════════════════

	═══ THE OWNER'S ENTRY IS LOCKED WHILE IT IS CARRIED ════════════════════════
	Because the dinosaur is still theirs, an owner could otherwise sell, vault
	or store it out from under a raid in progress - which is a dupe if the
	transfer then completes. `locked` is that guard, held server-side only.
	═══════════════════════════════════════════════════════════════════════════

	API:
		StealService.IsCarrying(player) -> token?
		StealService.CanRaid(thief, ownerUserId) -> ok, reason?
		StealService.HoldSecondsFor(thief, ownerData) -> seconds
		StealService.Begin(thief, ownerUserId, dinoUid) -> ok, reason?
		StealService.Cancel(thief, reason?)
		StealService.Tag(tagger, thiefUserId) -> ok, reason?
		StealService.IsLocked(ownerUserId, uid) -> boolean
		StealService.Vault(player, uid, slot) -> ok, reason?
		StealService.GrantShield(player, seconds, reason) -> until
		StealService.IsShielded(data, now?) -> boolean
		StealService.StealStarted / StealCompleted / StealFailed   Signals

	Depends on: GameConfig, Stats, Economy, PlayerDataService, EconomyService,
	            ParkService, DinosaurService, EggService, Net,
	            NestService (for the teleport blocker).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local DinoConfig = require(Shared.Config.DinoConfig)
local Economy = require(Shared.Modules.Economy)
local Format = require(Shared.Modules.Format)
local GameConfig = require(Shared.Config.GameConfig)
local Log = require(Shared.Modules.Log)
local Net = require(Shared.Modules.Net)
local RarityConfig = require(Shared.Config.RarityConfig)
local RebirthConfig = require(Shared.Config.RebirthConfig)
local Signal = require(Shared.Modules.Signal)
local Stats = require(Shared.Modules.Stats)
local UpgradeConfig = require(Shared.Config.UpgradeConfig)

local StealService = {}

StealService.StealStarted = Signal.new()
StealService.StealCompleted = Signal.new()
StealService.StealFailed = Signal.new()

local PlayerDataService, EconomyService, ParkService, DinosaurService
local EggService, NestService

--[[
	The carry tokens. Server memory only, never written to a profile - the same
	rule EggService follows, and for the same reason: a carry that exists in a
	profile can be banked by disconnecting.

	[thief] = {
		OwnerUserId, Uid, StartedAt, Model,
		Snapshot,     -- what was lifted, for the notification after transfer
	}
]]
local carrying: { [Player]: any } = {}

--- [ownerUserId] = { [uid] = thiefPlayer }. Guards owner-side mutation.
local locked: { [number]: { [string]: Player } } = {}

--- [thief] = { OwnerUserId, Uid, Progress, ... } while the hold ring is filling.
local holding: { [Player]: any } = {}

--- [ownerUserId] = os.clock() of that park's last Guard Tower tag.
local towerFiredAt: { [number]: number } = {}

local HOLD_TICK = 0.1
local CARRY_TICK = 0.25
local TOWER_TICK = 1

-- ── Shields ─────────────────────────────────────────────────────────────────

function StealService.IsShielded(data, now: number?): boolean
	return (data.ShieldUntil or 0) > (now or os.time())
end

--[[
	Adds shield time, capped at the two-hour stack docs/03 §4.3 publishes.

	The cap is on the RESULTING duration, not on what is added, so no sequence
	of grants - free, quest, purchased, or all three - reaches permanence.
]]
function StealService.GrantShield(player: Player, seconds: number, reason: string): number
	local data = PlayerDataService.Get(player)
	if not data then
		return 0
	end

	local now = os.time()
	local base = math.max(data.ShieldUntil or 0, now)
	local capped = math.min(base + seconds, now + GameConfig.ShieldStackCapSecs)

	PlayerDataService.UpdateKeys(player, { "ShieldUntil" }, function(profile)
		profile.ShieldUntil = capped
	end, "shield: " .. reason)

	local plot = ParkService.GetPlot(player)
	if plot then
		ParkService.SetShieldVisible(plot, true)
	end

	Log.info("StealService", "%s shielded for %s (%s)",
		player.Name, Format.Time(capped - now), reason)
	return capped
end

--[[
	New Player Protection: 60 minutes of playtime OR until the first Rare
	hatch, "whichever is later" (docs/03 §4.3). Both conditions must be past,
	which is what makes it a floor rather than a race.
]]
local function protectionActive(data): boolean
	if data.NewPlayerProtectionDone then
		return false
	end

	local playedEnough = (data.Stats.PlaytimeSecs or 0) >= GameConfig.NewPlayerProtectionSecs
	local rare = RarityConfig.Tiers.rare
	local best = RarityConfig.Tiers[data.Stats.RarestRarity or "common"]
	local hatchedRare = best ~= nil and rare ~= nil and best.Rank >= rare.Rank

	return not (playedEnough and hatchedRare)
end

-- ── Pruning ─────────────────────────────────────────────────────────────────

--[[
	Drops expired cooldowns and marks. Called on every write to either table so
	they cannot grow without bound on a busy account, and on load so a profile
	that sat for a month comes back clean.
]]
local function pruneRecords(profile, now: number)
	for _, key in { "StealCooldowns", "RevengeMarks" } do
		local records = profile[key]
		local live = {}
		local count = 0
		for id, expiry in records do
			if expiry > now then
				live[id] = expiry
				count += 1
			end
		end

		-- Backstop for the case where they are all still live: drop the ones
		-- expiring soonest, since those cost the player least.
		if count > GameConfig.StealRecordCap then
			local ordered = {}
			for id, expiry in live do
				table.insert(ordered, { Id = id, Expiry = expiry })
			end
			table.sort(ordered, function(a, b) return a.Expiry > b.Expiry end)
			live = {}
			for index = 1, GameConfig.StealRecordCap do
				live[ordered[index].Id] = ordered[index].Expiry
			end
		end

		profile[key] = live
	end

	local cutoff = now - GameConfig.MercyWindowSecs
	local recent = {}
	for _, stamp in profile.RobbedAt do
		if stamp > cutoff then
			table.insert(recent, stamp)
		end
	end
	profile.RobbedAt = recent
end

-- ── Eligibility ─────────────────────────────────────────────────────────────

function StealService.IsCarrying(player: Player)
	return carrying[player]
end

function StealService.IsLocked(ownerUserId: number, uid: string): boolean
	local held = locked[ownerUserId]
	return held ~= nil and held[uid] ~= nil
end

--[[
	Every rule in docs/03 §4.3, in one place, evaluated from server state.

	Ordered cheapest-first, and deliberately returns the FIRST failing reason
	rather than a list: the prompt has one line to explain itself.
]]
function StealService.CanRaid(thief: Player, ownerUserId: number): (boolean, string?)
	if thief.UserId == ownerUserId then
		return false, "that is your own park"
	end
	if carrying[thief] then
		return false, "you are already carrying one"
	end

	local thiefData = PlayerDataService.Get(thief)
	if not thiefData then
		return false, "profile not loaded"
	end

	local owner = Players:GetPlayerByUserId(ownerUserId)
	if not owner then
		-- docs/03 §4.3: offline parks are fully raid-immune.
		return false, "they are offline"
	end

	local ownerData = PlayerDataService.Get(owner)
	if not ownerData then
		return false, "they are offline"
	end

	local now = os.time()

	if StealService.IsShielded(ownerData, now) then
		return false, "their park is shielded"
	end
	if protectionActive(ownerData) then
		return false, "new player protection"
	end

	local sinceGlobal = now - (thiefData.GlobalStealAt or 0)
	if sinceGlobal < GameConfig.RaidGlobalCooldown then
		return false, string.format("wait %ds", GameConfig.RaidGlobalCooldown - sinceGlobal)
	end

	--[[
		The Revenge Mark ignores the same-victim cooldown (docs/03 §4.4), so
		it is checked before it rather than after.
	]]
	local marked = (thiefData.RevengeMarks[tostring(ownerUserId)] or 0) > now
	if not marked then
		local cooldown = thiefData.StealCooldowns[tostring(ownerUserId)] or 0
		if cooldown > now then
			return false, string.format("robbed recently - %s", Format.Time(cooldown - now))
		end
	end

	--[[
		The power floor. Compares PARK value, not net worth: what is at risk is
		what is on display, so what protects you should be too.
	]]
	local ownerValue = Economy.ParkValue(ownerData)
	local thiefValue = Economy.ParkValue(thiefData)
	if thiefValue > 0 and ownerValue < thiefValue * GameConfig.RaidPowerFloor then
		return false, "their park is too small"
	end

	return true
end

--- Hold seconds for this raid: the park's security, halved by a Revenge Mark.
function StealService.HoldSecondsFor(thief: Player, ownerData, ownerUserId: number): number
	local seconds = Stats.RaidHoldSecs(ownerData)

	local thiefData = PlayerDataService.Get(thief)
	if thiefData and (thiefData.RevengeMarks[tostring(ownerUserId)] or 0) > os.time() then
		seconds *= GameConfig.RevengeHoldMultiplier
	end

	return seconds
end

--- Whether a specific dinosaur can be lifted at all (docs/03 §4.1).
local function stealableReason(ownerData, uid: string, ownerUserId: number): string?
	local entry = ownerData.Dinos[uid]
	if not entry then
		return "no such dinosaur"
	end
	if entry.Vault then
		return "it is vaulted"
	end
	if not entry.Placed then
		return "it is not on display"
	end
	if StealService.IsLocked(ownerUserId, uid) then
		return "someone else has it"
	end
	return nil
end

-- ── The hold ────────────────────────────────────────────────────────────────

local function stopHold(thief: Player)
	local state = holding[thief]
	if not state then
		return
	end
	holding[thief] = nil
	Net.FireClient("StealAlert", thief, { Kind = "holdEnded" })
end

function StealService.Begin(thief: Player, ownerUserId: number, dinoUid: string): (boolean, string?)
	local ok, reason = StealService.CanRaid(thief, ownerUserId)
	if not ok then
		return false, reason
	end

	local owner = Players:GetPlayerByUserId(ownerUserId)
	local ownerData = PlayerDataService.Get(owner)
	local blocked = stealableReason(ownerData, dinoUid, ownerUserId)
	if blocked then
		return false, blocked
	end

	-- Spatial: you must be standing in the park you are robbing. Positional,
	-- server-side, from the server's own occupancy tracking.
	if ParkService.GetOccupiedPark(thief) ~= ownerUserId then
		return false, "you are not in their park"
	end

	local holdSecs = StealService.HoldSecondsFor(thief, ownerData, ownerUserId)

	holding[thief] = {
		OwnerUserId = ownerUserId,
		Uid = dinoUid,
		StartedAt = os.clock(),
		HoldSecs = holdSecs,
	}

	--[[
		"A giant progress ring is visible to everyone" (docs/03 §4.2). The
		owner is told immediately and by name: a raid the victim cannot see
		coming is a raid they cannot answer.
	]]
	local entry = ownerData.Dinos[dinoUid]
	Net.FireClient("StealAlert", owner, {
		Kind = "raidStarted",
		ThiefName = thief.DisplayName,
		DinoName = DinosaurService.DisplayNameOf(entry),
		Seconds = holdSecs,
	})
	Net.FireClient("StealAlert", thief, { Kind = "holdStarted", Seconds = holdSecs })

	StealService.StealStarted:Fire(thief, ownerUserId, dinoUid)
	return true
end

function StealService.Cancel(thief: Player, reason: string?)
	if holding[thief] then
		stopHold(thief)
		StealService.StealFailed:Fire(thief, reason or "cancelled")
	end
end

-- ── Carrying ────────────────────────────────────────────────────────────────

local function attachDino(thief: Player, entry, uid: string)
	local character = thief.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end

	local model = Instance.new("Part")
	model.Name = "StolenDino_" .. uid
	model.Size = Vector3.new(4, 4, 5)
	model.Color = RarityConfig.GetColor(entry.Rarity)
	model.Material = Enum.Material.SmoothPlastic
	model.CanCollide = false
	model.Massless = true
	model:SetAttribute("DinoUid", uid)
	model:SetAttribute("Rarity", entry.Rarity)

	-- Cosmetic only. The server reads its own token and never this model -
	-- the same rule the carried-egg model follows.
	local weld = Instance.new("WeldConstraint")
	model.CFrame = root.CFrame * CFrame.new(0, 3.2, 0)
	model.Parent = character
	weld.Part0 = root
	weld.Part1 = model
	weld.Parent = model

	--[[
		"Visible from anywhere, with a name tag" (docs/03 §4.4). The whole
		server should be able to see who is carrying what - that visibility is
		the counterplay.
	]]
	local gui = Instance.new("BillboardGui")
	gui.Name = "StealTag"
	gui.Size = UDim2.fromScale(16, 3)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	gui.MaxDistance = 500
	gui.AlwaysOnTop = true

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = RarityConfig.GetColor(entry.Rarity)
	label.TextStrokeTransparency = 0.2
	label.Text = string.format("%s IS STEALING A %s", string.upper(thief.DisplayName),
		string.upper(DinosaurService.DisplayNameOf(entry)))
	label.Parent = gui
	gui.Parent = model

	return model
end

local function lock(ownerUserId: number, uid: string, thief: Player)
	local held = locked[ownerUserId]
	if not held then
		held = {}
		locked[ownerUserId] = held
	end
	held[uid] = thief
end

local function unlock(ownerUserId: number, uid: string)
	local held = locked[ownerUserId]
	if held then
		held[uid] = nil
		if next(held) == nil then
			locked[ownerUserId] = nil
		end
	end
end

--- Lifts the dinosaur once the hold completes.
local function completeHold(thief: Player)
	local state = holding[thief]
	if not state then
		return
	end
	holding[thief] = nil

	-- Re-checked, not trusted: the hold took seconds, and everything that
	-- could have changed in them is checked again here.
	local ok, reason = StealService.CanRaid(thief, state.OwnerUserId)
	if not ok then
		StealService.StealFailed:Fire(thief, reason or "no longer possible")
		return
	end

	local owner = Players:GetPlayerByUserId(state.OwnerUserId)
	local ownerData = PlayerDataService.Get(owner)
	local blocked = stealableReason(ownerData, state.Uid, state.OwnerUserId)
	if blocked then
		StealService.StealFailed:Fire(thief, blocked)
		return
	end

	local entry = ownerData.Dinos[state.Uid]

	--[[
		The dinosaur comes off the grid so the owner's park stops rendering and
		stops paying for it, but it stays IN their profile. Placed = false is
		the reversible half; the lock is what stops them selling it meanwhile.
	]]
	PlayerDataService.UpdateKeys(owner, { "Dinos" }, function(profile)
		local held = profile.Dinos[state.Uid]
		if held then
			held.Placed = false
			held.TileX, held.TileZ = nil, nil
		end
	end, "raid lifted")

	lock(state.OwnerUserId, state.Uid, thief)
	EconomyService.InvalidateRate(owner)
	ParkService.RefreshDinos(owner)

	carrying[thief] = {
		OwnerUserId = state.OwnerUserId,
		Uid = state.Uid,
		StartedAt = os.clock(),
		Model = attachDino(thief, entry, state.Uid),
		Snapshot = {
			SpeciesId = entry.SpeciesId,
			Rarity = entry.Rarity,
			Name = DinosaurService.DisplayNameOf(entry),
		},
	}

	--[[
		"Slowed by that dinosaur's CarryPenalty + 10%, and you cannot sprint"
		(docs/03 §4.5). Routed through EggService's modifier stack so a raider
		who is also carrying eggs is slowed by both rather than by whichever
		system wrote last.
	]]
	local tier = RarityConfig.Tiers[entry.Rarity]
	local penalty = math.min((tier and tier.CarryPenalty or 0.2) + GameConfig.RaidCarryExtra,
		GameConfig.MaxCarryPenalty)
	EggService.SetSpeedModifier(thief, "raid", 1 - penalty)

	Net.FireClient("StealAlert", thief, {
		Kind = "carrying",
		DinoName = carrying[thief].Snapshot.Name,
		Rarity = entry.Rarity,
	})
	Net.FireClient("StealAlert", owner, {
		Kind = "lifted",
		ThiefName = thief.DisplayName,
		DinoName = carrying[thief].Snapshot.Name,
	})

	Log.info("StealService", "%s lifted %s from %s",
		thief.Name, carrying[thief].Snapshot.Name, owner.Name)
end

-- ── Resolution ──────────────────────────────────────────────────────────────

--[[
	Puts a carried dinosaur back where it came from. The single un-happy path:
	tagging, disconnecting, dying and the owner leaving all end here, so there
	is one place where "the raid did not work" is expressed.
]]
local function returnCarry(thief: Player, reason: string)
	local token = carrying[thief]
	if not token then
		return
	end
	carrying[thief] = nil

	if token.Model then
		token.Model:Destroy()
	end
	EggService.ClearSpeedModifier(thief, "raid")
	unlock(token.OwnerUserId, token.Uid)

	local owner = Players:GetPlayerByUserId(token.OwnerUserId)
	local ownerData = owner and PlayerDataService.Get(owner)
	if ownerData then
		--[[
			It never left their profile, so "returning" it is putting it back
			on the grid. If the grid filled up while it was away it simply
			stays in storage - refusing to return it would be the only way to
			actually lose one.
		]]
		local species = DinoConfig.Get(token.Snapshot.SpeciesId)
		local tileX, tileZ = DinosaurService.FindFreeFootprint(ownerData,
			species and species.Size or "1x1")
		if tileX then
			DinosaurService.Place(owner, token.Uid, tileX, tileZ)
		end

		EconomyService.InvalidateRate(owner)
		ParkService.RefreshDinos(owner)

		Net.FireClient("StealAlert", owner, {
			Kind = "returned",
			DinoName = token.Snapshot.Name,
			Reason = reason,
		})
	end

	StealService.StealFailed:Fire(thief, reason)
	Log.info("StealService", "%s's carry returned (%s)", thief.Name, reason)
end

--- Reaching your own gate: ownership transfers (docs/03 §4.8).
local function completeSteal(thief: Player)
	local token = carrying[thief]
	if not token then
		return
	end

	local owner = Players:GetPlayerByUserId(token.OwnerUserId)
	local ownerData = owner and PlayerDataService.Get(owner)
	if not ownerData then
		-- The owner left mid-carry. docs/03 §4.3 makes offline parks immune,
		-- so the raid voids rather than resolving against an absent profile.
		returnCarry(thief, "they left")
		return
	end

	local entry = ownerData.Dinos[token.Uid]
	if not entry then
		returnCarry(thief, "it is gone")
		return
	end

	local snapshot = table.clone(entry)
	carrying[thief] = nil
	if token.Model then
		token.Model:Destroy()
	end
	EggService.ClearSpeedModifier(thief, "raid")
	unlock(token.OwnerUserId, token.Uid)

	--[[
		The transfer. Two profile writes with no client step between them, and
		the removal happens FIRST: if anything failed after this point the
		dinosaur would be lost rather than duplicated, and one lost dinosaur is
		a support ticket while one duplicated dinosaur is an economy.
	]]
	PlayerDataService.UpdateKeys(owner, { "Dinos", "Stats" }, function(profile)
		profile.Dinos[token.Uid] = nil
		profile.Stats.DinosLostToOthers += 1
	end, "raided")

	local uid, newEntry = DinosaurService.Create(thief, {
		SpeciesId = snapshot.SpeciesId,
		Rarity = snapshot.Rarity,
		Mutation = snapshot.Mutation,
		Mutation2 = snapshot.Mutation2,
		Stars = snapshot.Stars,
		Origin = snapshot.Origin,
		-- Not hatched by this player, and not born today.
		Acquired = "steal",
		HatchedAt = snapshot.HatchedAt,
	})

	if not uid then
		-- Storage full. The dinosaur is already gone from its owner, so it
		-- goes back rather than evaporating.
		PlayerDataService.UpdateKeys(owner, { "Dinos", "Stats" }, function(profile)
			profile.Dinos[token.Uid] = snapshot
			profile.Stats.DinosLostToOthers -= 1
		end, "raid rolled back")
		Net.FireClient("StealAlert", thief, { Kind = "failed", Reason = "your storage is full" })
		return
	end

	local now = os.time()
	PlayerDataService.UpdateKeys(thief, { "StealCooldowns", "RevengeMarks", "GlobalStealAt", "Stats" },
		function(profile)
			profile.StealCooldowns[tostring(token.OwnerUserId)] = now + GameConfig.RaidSameVictimCooldown
			profile.RevengeMarks[tostring(token.OwnerUserId)] = nil
			profile.GlobalStealAt = now
			profile.Stats.DinosStolenFromOthers += 1
			pruneRecords(profile, now)
		end, "raid completed")

	--[[
		Insurance and the Revenge Mark (docs/03 §4.4). Being robbed becomes a
		revenge quest rather than a loss: 25% of sell value now, and half-price
		hold time against that thief for half an hour.
	]]
	local sellFossils = Economy.SellValueOf(snapshot)
	local insurance = math.floor(sellFossils * GameConfig.RaidInsuranceShare)
	EconomyService.AddFossils(owner, insurance, "insurance")

	PlayerDataService.UpdateKeys(owner, { "RevengeMarks", "RobbedAt" }, function(profile)
		profile.RevengeMarks[tostring(thief.UserId)] = now + GameConfig.RevengeDuration
		table.insert(profile.RobbedAt, now)
		pruneRecords(profile, now)
	end, "robbed")

	-- Mercy Shield: robbed three times inside fifteen minutes (docs/03 §4.3).
	local recent = PlayerDataService.Get(owner).RobbedAt
	if #recent >= GameConfig.MercyRobberies then
		StealService.GrantShield(owner, GameConfig.MercyShieldSecs, "mercy")
		Net.FireClient("StealAlert", owner, {
			Kind = "mercy",
			Seconds = GameConfig.MercyShieldSecs,
		})
	end

	EconomyService.InvalidateRate(owner)
	EconomyService.InvalidateRate(thief)
	ParkService.RefreshDinos(owner)
	DinosaurService.PlaceBest(thief)

	Net.FireClient("StealAlert", thief, {
		Kind = "stolen", DinoName = token.Snapshot.Name, Rarity = snapshot.Rarity,
	})
	Net.FireClient("StealAlert", owner, {
		Kind = "robbed", ThiefName = thief.DisplayName, DinoName = token.Snapshot.Name,
		Insurance = insurance,
	})

	StealService.StealCompleted:Fire(thief, token.OwnerUserId, uid, newEntry)
	Log.info("StealService", "%s stole %s from %s (insurance %s)",
		thief.Name, token.Snapshot.Name, owner.Name, Format.Number(insurance))
end

-- ── Tagging ─────────────────────────────────────────────────────────────────

--[[
	docs/03 §4.7: the owner, or anyone the owner has as a friend in-server, can
	tag a carrying thief by touching them.

	Distance is measured on the SERVER at the moment of the grant, not trusted
	from the client - the same rule egg pickup follows.
]]
local TAG_RANGE = 12

function StealService.Tag(tagger: Player, thiefUserId: number): (boolean, string?)
	local thief = Players:GetPlayerByUserId(thiefUserId)
	if not thief then
		return false, "no such player"
	end

	local token = carrying[thief]
	if not token then
		return false, "they are not carrying anything"
	end

	if tagger.UserId ~= token.OwnerUserId then
		local ok, isFriend = pcall(function()
			return tagger:IsFriendsWith(token.OwnerUserId)
		end)
		if not (ok and isFriend) then
			return false, "not your dinosaur"
		end
	end

	local taggerRoot = tagger.Character and tagger.Character:FindFirstChild("HumanoidRootPart")
	local thiefRoot = thief.Character and thief.Character:FindFirstChild("HumanoidRootPart")
	if not taggerRoot or not thiefRoot then
		return false, "too far"
	end
	if (taggerRoot.Position - thiefRoot.Position).Magnitude > TAG_RANGE then
		return false, "too far"
	end

	Net.FireClient("StealAlert", thief, { Kind = "tagged" })
	task.delay(GameConfig.RaidTagReturnSecs, function()
		if carrying[thief] == token then
			returnCarry(thief, "tagged")
		end
	end)

	return true
end

--[[
	Guard Tower: auto-tags a carrying thief inside 40 studs of the park it
	defends, once per its cooldown (docs/03 §5). The one defence that acts
	without the owner present - which is what it is for.
]]
local function tickTowers()
	local now = os.clock()

	for thief, token in carrying do
		local owner = Players:GetPlayerByUserId(token.OwnerUserId)
		local ownerData = owner and PlayerDataService.Get(owner)
		if not ownerData then
			continue
		end

		local towerLevel = UpgradeConfig.LevelIn(ownerData, "guardTower")
		if towerLevel < 1 then
			continue
		end

		local cooldown = Stats.TowerCooldown(ownerData)
		if now - (towerFiredAt[token.OwnerUserId] or -math.huge) < cooldown then
			continue
		end

		local plot = ParkService.GetPlotByUserId(token.OwnerUserId)
		local thiefRoot = thief.Character and thief.Character:FindFirstChild("HumanoidRootPart")
		if not plot or not plot.PrimaryPart or not thiefRoot then
			continue
		end

		if (thiefRoot.Position - plot.PrimaryPart.Position).Magnitude <= GameConfig.GuardTowerRange then
			towerFiredAt[token.OwnerUserId] = now
			Net.FireClient("StealAlert", thief, { Kind = "tagged", Source = "tower" })
			Net.FireClient("StealAlert", owner, { Kind = "towerFired", ThiefName = thief.DisplayName })
			task.delay(GameConfig.RaidTagReturnSecs, function()
				if carrying[thief] == token then
					returnCarry(thief, "guard tower")
				end
			end)
		end
	end
end

-- ── The Vault ───────────────────────────────────────────────────────────────

--[[
	docs/03 §4.1: a vaulted dinosaur is never stealable. Slots come from
	rebirths (RebirthConfig.VaultSlots), so the protection is earned rather
	than bought - and a vaulted dinosaur still earns, so vaulting is not a
	sacrifice either.
]]
function StealService.Vault(player: Player, uid: string, slot: number): (boolean, string?)
	local data = PlayerDataService.Get(player)
	if not data then
		return false, "profile not loaded"
	end

	local entry = data.Dinos[uid]
	if not entry then
		return false, "no such dinosaur"
	end
	if StealService.IsLocked(player.UserId, uid) then
		return false, "someone is carrying it"
	end

	local slots = RebirthConfig.VaultSlots(data.Rebirths)
	if slot < 1 or slot > slots then
		return false, string.format("you have %d vault slot(s)", slots)
	end

	for otherUid, other in data.Dinos do
		if other.Vault == slot and otherUid ~= uid then
			return false, "that pedestal is taken"
		end
	end

	PlayerDataService.UpdateKeys(player, { "Dinos" }, function(profile)
		local held = profile.Dinos[uid]
		held.Vault = slot
		held.Placed = false
		held.TileX, held.TileZ = nil, nil
		held.Locked = true
	end, "vault")

	EconomyService.InvalidateRate(player)
	ParkService.RefreshDinos(player)
	return true
end

-- ── Ticks ───────────────────────────────────────────────────────────────────

local function tickHolds()
	local now = os.clock()
	for thief, state in holding do
		local elapsed = now - state.StartedAt

		-- Leaving the park cancels the hold: the ring is a commitment to stand
		-- there, which is what gives the owner something to interrupt.
		if ParkService.GetOccupiedPark(thief) ~= state.OwnerUserId then
			stopHold(thief)
			StealService.StealFailed:Fire(thief, "left the park")
			continue
		end

		if elapsed >= state.HoldSecs then
			completeHold(thief)
		end
	end
end

--[[
	The gate check. Server-side and positional, never a client remote - docs/03
	§6 names "fake I reached my gate" as an attack and this is the mitigation.
]]
local function tickCarries()
	for thief in carrying do
		if ParkService.IsInsideOwnPark(thief) then
			completeSteal(thief)
		end
	end
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function StealService.Init(app)
	PlayerDataService = app.Get("PlayerDataService")
	EconomyService = app.Get("EconomyService")
	ParkService = app.Get("ParkService")
	DinosaurService = app.Get("DinosaurService")
	EggService = app.Get("EggService")
	NestService = app.Get("NestService")
end

function StealService.Start(_app)
	--[[
		Step 14 built the registry for exactly this. A raider who can teleport
		home has not raided anyone - they have pressed a button.
	]]
	NestService.Zones.RegisterBlocker("raid", function(player)
		return if carrying[player] then "not while you are carrying a dinosaur" else nil
	end)

	--[[
		The raid prompt on every placed dinosaur. Attached here rather than in
		ParkService for the same reason the incubator and shrine prompts are
		attached in their services: rendering is geometry, and a prompt that
		can take someone's dinosaur is behaviour.

		HoldDuration is set per-park from the owner's security, so the ring the
		raider sees IS the wait - there is no second timer to disagree with it.
		The 0.1s tick then confirms completion server-side; the prompt firing is
		treated as a request, never as proof.
	]]
	ParkService.DinoRendered:Connect(function(owner, uid, model)
		local anchorPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
		if not anchorPart then
			return
		end

		local ownerData = PlayerDataService.Get(owner)
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "RaidPrompt"
		prompt.ActionText = "Steal"
		prompt.ObjectText = DinosaurService.DisplayNameOf(ownerData and ownerData.Dinos[uid] or {})
		prompt.HoldDuration = if ownerData then Stats.RaidHoldSecs(ownerData) else GameConfig.RaidHoldBase
		prompt.MaxActivationDistance = 14
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("RaidOwnerUserId", owner.UserId)
		prompt.Parent = anchorPart

		--[[
			PromptButtonHoldBegan starts the server's own hold, so leaving the
			park mid-hold cancels it (tickHolds) even though the client's ring
			would happily keep filling.
		]]
		prompt.PromptButtonHoldBegan:Connect(function(player)
			local ok, reason = StealService.Begin(player, owner.UserId, uid)
			if not ok and reason then
				Net.FireClient("StealAlert", player, { Kind = "refused", Reason = reason })
			end
		end)
		prompt.PromptButtonHoldEnded:Connect(function(player)
			StealService.Cancel(player, "let go")
		end)
	end)

	Net.OnEvent("RequestStealBegin", function(player, ownerUserId, dinoUid)
		if type(ownerUserId) ~= "number" or type(dinoUid) ~= "string" then
			return
		end
		local ok, reason = StealService.Begin(player, ownerUserId, dinoUid)
		if not ok and reason then
			Net.FireClient("StealAlert", player, { Kind = "refused", Reason = reason })
		end
	end)

	Net.OnEvent("RequestStealCancel", function(player)
		StealService.Cancel(player, "cancelled")
	end)

	Net.OnEvent("RequestTagThief", function(player, thiefUserId)
		if type(thiefUserId) ~= "number" then
			return
		end
		StealService.Tag(player, thiefUserId)
	end)

	Net.OnEvent("RequestVaultDino", function(player, uid, slot)
		if type(uid) ~= "string" or type(slot) ~= "number" then
			return
		end
		local ok, reason = StealService.Vault(player, uid, math.floor(slot))
		if not ok and reason then
			Net.FireClient("StealAlert", player, { Kind = "refused", Reason = reason })
		end
	end)

	--[[
		Session shield and record pruning on load. The shield is what lets a
		player set their park up without being ambushed in the first minute
		(docs/03 §4.3).
	]]
	PlayerDataService.ProfileLoaded:Connect(function(player, _data)
		PlayerDataService.UpdateKeys(player, { "StealCooldowns", "RevengeMarks", "RobbedAt" },
			function(profile)
				pruneRecords(profile, os.time())
			end, "prune raid records")

		StealService.GrantShield(player, GameConfig.SessionShieldSecs, "session")
	end)

	--[[
		docs/03 §6: "Dupe by leaving mid-carry". The token is resolved BEFORE
		the profile releases - which for a raid means the owner gets their
		dinosaur back, because it never left their profile in the first place.

		The published 30-second grace is a timer on the returning animation,
		not on the ownership: there is no window in which the dinosaur belongs
		to nobody, so nothing has to be held open.
	]]
	Players.PlayerRemoving:Connect(function(player)
		--[[
			Raids AGAINST them first, while their profile is still loaded and
			the dinosaur can be put back on their grid. An owner leaving voids
			any raid on them for the same reason an offline park cannot be
			entered: there is no profile to transfer from.
		]]
		for thief, token in carrying do
			if token.OwnerUserId == player.UserId then
				returnCarry(thief, "they left")
			end
		end
		for thief, state in holding do
			if state.OwnerUserId == player.UserId then
				stopHold(thief)
			end
		end

		-- Then their own carry, then their bookkeeping.
		if carrying[player] then
			returnCarry(player, "they disconnected")
		end
		holding[player] = nil
		towerFiredAt[player.UserId] = nil
		locked[player.UserId] = nil
	end)

	--[[
		Dying drops the carry. Without this the weld is destroyed with the old
		character and the token survives, so the thief walks home carrying an
		invisible dinosaur.
	]]
	Players.PlayerAdded:Connect(function(player)
		player.CharacterRemoving:Connect(function()
			if carrying[player] then
				returnCarry(player, "they died")
			end
			holding[player] = nil
		end)
	end)
	for _, player in Players:GetPlayers() do
		player.CharacterRemoving:Connect(function()
			if carrying[player] then
				returnCarry(player, "they died")
			end
			holding[player] = nil
		end)
	end

	--[[
		"SOMEONE IS IN YOUR PARK!" (docs/03 §4.2), extended by the Camera
		track's alert range. The alert is free counterplay: it costs the owner
		nothing and gives them the seconds the hold ring is there to provide.
	]]
	ParkService.ParkEntered:Connect(function(player, ownerUserId)
		if player.UserId == ownerUserId then
			return
		end
		local owner = Players:GetPlayerByUserId(ownerUserId)
		local ownerData = owner and PlayerDataService.Get(owner)
		if not ownerData or not ownerData.Settings.StealNotifications then
			return
		end
		Net.FireClient("StealAlert", owner, {
			Kind = "intruder",
			ThiefName = player.DisplayName,
		})
	end)

	task.spawn(function()
		while true do
			task.wait(HOLD_TICK)
			local ok, err = pcall(tickHolds)
			if not ok then
				Log.error("StealService", "Hold tick failed: %s", tostring(err))
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(CARRY_TICK)
			local ok, err = pcall(tickCarries)
			if not ok then
				Log.error("StealService", "Carry tick failed: %s", tostring(err))
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(TOWER_TICK)
			local ok, err = pcall(tickTowers)
			if not ok then
				Log.error("StealService", "Tower tick failed: %s", tostring(err))
			end
		end
	end)

	Log.info("StealService", "Ready. Hold %.1f-%.1fs, %ds same-victim cooldown",
		GameConfig.RaidHoldBase,
		GameConfig.RaidHoldBase + 5 * GameConfig.RaidHoldPerSecurity,
		GameConfig.RaidSameVictimCooldown)
end

return StealService
