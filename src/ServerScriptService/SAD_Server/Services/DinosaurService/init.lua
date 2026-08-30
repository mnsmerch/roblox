--!nonstrict
--[[
	DinosaurService
	ServerScriptService/SAD_Server/Services/DinosaurService  (ModuleScript)

	Owns dinosaurs: rolling which species an egg becomes, minting the profile
	entry, and computing what one is worth.

	REVEAL #2 lives here. The species is chosen at hatch from the pool for the
	egg's ORIGIN ZONE and its already-decided rarity - so a Legendary egg taken
	in Frozen Valley can only ever be something Frozen Valley has, and a player
	who wants a specific dinosaur has a zone to go and rob for it.

	Step 12 adds placing, storing and selling. This is creation and valuation.

	API:
		DinosaurService.RollSpecies(zoneId, rarity, rng?) -> speciesId?
		DinosaurService.Create(player, params) -> uid?, entry?, reason?
		DinosaurService.IncomeOf(entry, data) -> number
		DinosaurService.SellValueOf(entry) -> fossils, dna
		DinosaurService.GetStorageUsed(player) -> number
		DinosaurService.GetStorageCap(player) -> number
		DinosaurService.DisplayNameOf(entry) -> string
		DinosaurService.Place(player, uid, tileX, tileZ) -> ok, reason?
		DinosaurService.PlaceBest(player) -> uid?, reason?
		DinosaurService.Store(player, uid) -> ok, reason?
		DinosaurService.FindFreeFootprint(data, size) -> tileX?, tileZ?
		DinosaurService.GetPlacedCount(player) -> number
		DinosaurService.DinoCreated  Signal(player, uid, entry)
		DinosaurService.DinoPlaced   Signal(player, uid, entry)
		DinosaurService.DinoStored   Signal(player, uid, entry)

	Depends on: DinoConfig, RarityConfig, MutationConfig, RebirthConfig,
	            UpgradeConfig, PlayerDataService, RNG.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local DinoConfig = require(Shared.Config.DinoConfig)
local ParkConfig = require(Shared.Config.ParkConfig)
local MutationConfig = require(Shared.Config.MutationConfig)
local RarityConfig = require(Shared.Config.RarityConfig)
local RebirthConfig = require(Shared.Config.RebirthConfig)
local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local Economy = require(Shared.Modules.Economy)
local Log = require(Shared.Modules.Log)
local Net = require(Shared.Modules.Net)
local RNG = require(Shared.Modules.RNG)
local Signal = require(Shared.Modules.Signal)
local Stats = require(Shared.Modules.Stats)

local DinosaurService = {}

DinosaurService.DinoCreated = Signal.new()
DinosaurService.DinoPlaced = Signal.new()
DinosaurService.DinoStored = Signal.new()

local PlayerDataService
local rng = RNG.new()

-- ── Species ─────────────────────────────────────────────────────────────────

--[[
	Picks a species for `rarity` from `zoneId`'s pool.

	Uniform within the bucket. Weighting individual species would be a second
	rarity system layered on the first, and the SpeciesFactor spread (0.60-1.30)
	already makes some outcomes better than others without needing one.

	Returns nil only if the combination has no coverage - which ConfigValidator
	rule 6 refuses to let the server boot with, so it should be unreachable.
]]
function DinosaurService.RollSpecies(zoneId: string, rarity: string, generator: Random?): string?
	local pool = DinoConfig.SpeciesFor(zoneId, rarity)
	if #pool == 0 then
		Log.error("DinosaurService", "No %s species in zone '%s' - ConfigValidator should have caught this",
			rarity, tostring(zoneId))
		return nil
	end
	return pool[(generator or rng):NextInteger(1, #pool)]
end

-- ── Valuation ───────────────────────────────────────────────────────────────

--[[
	Income and sell value live in SAD_Shared/Modules/Economy, because the client
	computes income locally to draw floaters and the two sides must agree
	exactly. Re-exported here so callers do not need to know which module owns
	which half of the maths.
]]
DinosaurService.IncomeOf = Economy.IncomeOf
DinosaurService.SellValueOf = Economy.SellValueOf

--- "Void Golden Tyrannosaurus Rex". Rarer mutation first.
function DinosaurService.DisplayNameOf(entry): string
	local species = DinoConfig.Get(entry.SpeciesId)
	local prefix = MutationConfig.DisplayPrefix(entry.Mutation, entry.Mutation2)
	return prefix .. (species and species.DisplayName or entry.SpeciesId)
end

-- ── Storage ─────────────────────────────────────────────────────────────────

function DinosaurService.GetStorageUsed(player: Player): number
	local data = PlayerDataService.Get(player)
	if not data then
		return 0
	end

	--[[
		Only UNPLACED dinosaurs count against storage. Placed ones live in the
		park and are limited by dinoSlots instead, and vaulted ones are outside
		both - otherwise filling your park would lock you out of hatching.
	]]
	local used = 0
	for _, entry in data.Dinos do
		if not entry.Placed and not entry.Vault then
			used += 1
		end
	end
	return used
end

function DinosaurService.GetStorageCap(player: Player): number
	local data = PlayerDataService.Get(player)
	if not data then
		return 0
	end
	return Stats.DinoStorage(data)
end

-- ── Placement ───────────────────────────────────────────────────────────────

function DinosaurService.GetPlacedCount(player: Player): number
	local data = PlayerDataService.Get(player)
	if not data then
		return 0
	end
	local count = 0
	for _, entry in data.Dinos do
		if entry.Placed then
			count += 1
		end
	end
	return count
end

--- Which grid tiles are currently occupied, and by whom.
local function occupancyOf(data, exceptUid: string?)
	local occupied = {}
	for uid, entry in data.Dinos do
		if entry.Placed and entry.TileX and uid ~= exceptUid then
			local species = DinoConfig.Get(entry.SpeciesId)
			local tiles = species and ParkConfig.FootprintTiles(entry.TileX, entry.TileZ, species.Size)
			for _, tile in tiles or {} do
				occupied[tile[1] .. "," .. tile[2]] = uid
			end
		end
	end
	return occupied
end

--[[
	First anchor where `size` fits without overlapping anything.

	Scans back-to-front so the park fills from the far wall toward the gate,
	which keeps the view from the entrance clear and puts the newest arrival
	where a visitor sees it.
]]
function DinosaurService.FindFreeFootprint(data, size: string, exceptUid: string?): (number?, number?)
	local occupied = occupancyOf(data, exceptUid)

	for tileZ = 1, ParkConfig.GridTiles do
		for tileX = 1, ParkConfig.GridTiles do
			local tiles = ParkConfig.FootprintTiles(tileX, tileZ, size)
			if tiles then
				local clear = true
				for _, tile in tiles do
					if occupied[tile[1] .. "," .. tile[2]] then
						clear = false
						break
					end
				end
				if clear then
					return tileX, tileZ
				end
			end
		end
	end

	return nil, nil
end

--[[
	Places a dinosaur on the grid. Returns (ok, reason).

	Three things can refuse it, and all three are the player's to fix: no free
	slot, the footprint runs off the grid, or something is already there. None
	of them changes any state.
]]
function DinosaurService.Place(player: Player, uid: string, tileX: number, tileZ: number): (boolean, string?)
	local data = PlayerDataService.Get(player)
	if not data then
		return false, "profile not loaded"
	end

	local entry = data.Dinos[uid]
	if not entry then
		return false, "no such dinosaur"
	end
	if entry.Placed then
		return false, "already placed"
	end
	if entry.Vault then
		return false, "vaulted"
	end

	if DinosaurService.GetPlacedCount(player) >= Economy.SlotCap(data) then
		return false, "no free slots"
	end

	local species = DinoConfig.Get(entry.SpeciesId)
	if not species then
		return false, "unknown species"
	end

	local tiles = ParkConfig.FootprintTiles(tileX, tileZ, species.Size)
	if not tiles then
		return false, "does not fit on the grid"
	end

	local occupied = occupancyOf(data, uid)
	for _, tile in tiles do
		if occupied[tile[1] .. "," .. tile[2]] then
			return false, "something is already there"
		end
	end

	PlayerDataService.UpdateKeys(player, { "Dinos", "Stats" }, function(profile)
		local target = profile.Dinos[uid]
		target.Placed = true
		target.TileX = tileX
		target.TileZ = tileZ
		profile.Stats.DinosPlaced += 1
	end, "place")

	DinosaurService.DinoPlaced:Fire(player, uid, entry)
	return true, nil
end

--[[
	Places the most valuable unplaced dinosaur wherever it fits.

	This is what the Collection Totem's prompt calls, and what a hatch calls
	when a slot is free. Best-first because a player who can only place one more
	thing should be placing their Mythic, not whichever Compsognathus the
	iteration happened to reach.
]]
function DinosaurService.PlaceBest(player: Player): (string?, string?)
	local data = PlayerDataService.Get(player)
	if not data then
		return nil, "profile not loaded"
	end

	if DinosaurService.GetPlacedCount(player) >= Economy.SlotCap(data) then
		return nil, "no free slots"
	end

	local bestUid, bestIncome = nil, -1
	for uid, entry in data.Dinos do
		if not entry.Placed and not entry.Vault then
			local income = Economy.IncomeOf(entry, data)
			if income > bestIncome then
				bestUid, bestIncome = uid, income
			end
		end
	end

	if not bestUid then
		return nil, "nothing to place"
	end

	local species = DinoConfig.Get(data.Dinos[bestUid].SpeciesId)
	local tileX, tileZ = DinosaurService.FindFreeFootprint(data, species.Size)
	if not tileX then
		return nil, "no room on the grid"
	end

	local ok, reason = DinosaurService.Place(player, bestUid, tileX, tileZ)
	if not ok then
		return nil, reason
	end
	return bestUid, nil
end

--- Returns a dinosaur to storage, freeing its slot and its tiles.
function DinosaurService.Store(player: Player, uid: string): (boolean, string?)
	local data = PlayerDataService.Get(player)
	if not data then
		return false, "profile not loaded"
	end

	local entry = data.Dinos[uid]
	if not entry then
		return false, "no such dinosaur"
	end
	if not entry.Placed then
		return false, "not placed"
	end

	if DinosaurService.GetStorageUsed(player) >= DinosaurService.GetStorageCap(player) then
		return false, "storage full"
	end

	PlayerDataService.UpdateKeys(player, { "Dinos" }, function(profile)
		local target = profile.Dinos[uid]
		target.Placed = false
		target.TileX = nil
		target.TileZ = nil
	end, "store")

	DinosaurService.DinoStored:Fire(player, uid, entry)
	return true, nil
end

-- ── Creation ────────────────────────────────────────────────────────────────

local function newUid(data): string
	-- Server-generated and collision-checked. The client never supplies one.
	for _ = 1, 8 do
		local uid = string.sub(string.gsub(HttpService:GenerateGUID(false), "-", ""), 1, 8)
		if not data.Dinos[uid] then
			return uid
		end
	end
	return string.sub(string.gsub(HttpService:GenerateGUID(false), "-", ""), 1, 12)
end

--[[
	Mints a dinosaur into the profile. Returns (uid, entry, reason).

	Refuses when storage is full rather than overwriting or discarding, so the
	blockage is visible and fixable (docs/06 §1). The caller decides what to do
	about it - IncubationService leaves the egg in its incubator.
]]
function DinosaurService.Create(player: Player, params): (string?, any?, string?)
	local data = PlayerDataService.Get(player)
	if not data then
		return nil, nil, "profile not loaded"
	end

	if DinosaurService.GetStorageUsed(player) >= DinosaurService.GetStorageCap(player) then
		return nil, nil, "storage full"
	end

	local tier = RarityConfig.Tiers[params.Rarity]
	if not tier or not DinoConfig.Get(params.SpeciesId) then
		return nil, nil, "unknown species or rarity"
	end

	local uid = newUid(data)
	local entry = {
		SpeciesId = params.SpeciesId,
		Rarity = params.Rarity,
		Mutation = if params.Mutation ~= "none" then params.Mutation else nil,
		Mutation2 = params.Mutation2,
		Stars = params.Stars or 1,
		Placed = false,
		Locked = tier.AutoLock == true,
		Favorite = false,
		HatchedAt = os.time(),
		Rerolls = 0,
		Origin = params.Origin or "plains",
	}

	data.Dinos[uid] = entry

	-- Index bookkeeping. IndexService (Step 19) adds milestones and rewards on
	-- top; recording what happened belongs with the thing that happened.
	local indexEntry = data.Index[params.SpeciesId]
	if not indexEntry then
		indexEntry = { Count = 0, BestStar = 0, Mutations = {}, FirstAt = os.time() }
		data.Index[params.SpeciesId] = indexEntry
	end
	indexEntry.Count += 1
	indexEntry.BestStar = math.max(indexEntry.BestStar, entry.Stars)
	if entry.Mutation then
		indexEntry.Mutations[entry.Mutation] = true
	end
	if entry.Mutation2 then
		indexEntry.Mutations[entry.Mutation2] = true
	end

	-- Personal bests, for the rebirth cache and the leaderboards.
	data.Stats.DinosHatched += 1
	if RarityConfig.RankOf(params.Rarity) > RarityConfig.RankOf(data.Stats.RarestRarity) then
		data.Stats.RarestRarity = params.Rarity
	end
	local bestMutation = MutationConfig.Get(data.Stats.BestMutation)
	local rolled = MutationConfig.Get(entry.Mutation)
	if rolled and bestMutation and rolled.Rank > bestMutation.Rank then
		data.Stats.BestMutation = rolled.Id
	end

	DinosaurService.DinoCreated:Fire(player, uid, entry)
	return uid, entry, nil
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function DinosaurService.Init(app)
	PlayerDataService = app.Get("PlayerDataService")
end

function DinosaurService.Start(app)
	Net.OnEvent("RequestPlaceDino", function(player: Player, uid: string, tileX: number, tileZ: number)
		DinosaurService.Place(player, uid, tileX, tileZ)
	end)

	Net.OnEvent("RequestStoreDino", function(player: Player, uid: string)
		DinosaurService.Store(player, uid)
	end)

	Log.info("DinosaurService", "Ready. %d species available", DinoConfig.Count())
end

return DinosaurService
