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
		DinosaurService.DinoCreated  Signal(player, uid, entry)

	Depends on: DinoConfig, RarityConfig, MutationConfig, RebirthConfig,
	            UpgradeConfig, PlayerDataService, RNG.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local DinoConfig = require(Shared.Config.DinoConfig)
local MutationConfig = require(Shared.Config.MutationConfig)
local RarityConfig = require(Shared.Config.RarityConfig)
local RebirthConfig = require(Shared.Config.RebirthConfig)
local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local Log = require(Shared.Modules.Log)
local RNG = require(Shared.Modules.RNG)
local Signal = require(Shared.Modules.Signal)

local DinosaurService = {}

DinosaurService.DinoCreated = Signal.new()

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
	The master income formula from docs/05 §2.

	Every multiplier in one place, in the documented order, so a number a player
	sees can always be traced. `data` may be nil for a context-free valuation
	(a preview, a trade window) - the player-specific terms then drop to 1.
]]
function DinosaurService.IncomeOf(entry, data): number
	local tier = RarityConfig.Tiers[entry.Rarity]
	local species = DinoConfig.Get(entry.SpeciesId)
	if not tier or not species then
		return 0
	end

	local income = tier.BaseIncome * species.SpeciesFactor
	income *= MutationConfig.MultiplierFor(entry.Mutation, entry.Mutation2)

	-- Stars 1-5, +35% each. Fusion raises them in V1.2.
	income *= 1 + 0.35 * ((entry.Stars or 1) - 1)

	if data then
		income *= RebirthConfig.IncomeMultiplier(data.Rebirths)
		income *= UpgradeConfig.EffectAt("feedingTrough", data.Upgrades.feedingTrough or 0)
	end

	return income
end

--- Fossils and DNA from selling. Mutations raise sell value on a SQUARE ROOT,
--- so selling a Void dinosaur is lucrative but never better than keeping it.
function DinosaurService.SellValueOf(entry): (number, number)
	local tier = RarityConfig.Tiers[entry.Rarity]
	if not tier then
		return 0, 0
	end

	local starMult = 1 + 0.35 * ((entry.Stars or 1) - 1)
	local mutationMult = math.sqrt(MutationConfig.MultiplierFor(entry.Mutation, entry.Mutation2))

	return math.floor(tier.SellFossils * starMult * mutationMult),
		math.floor(tier.SellDna * starMult * mutationMult)
end

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
	return UpgradeConfig.EffectAt("dinoStorage", data.Upgrades.dinoStorage or 0)
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
	Log.info("DinosaurService", "Ready. %d species available", DinoConfig.Count())
end

return DinosaurService
