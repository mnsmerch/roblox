--!nonstrict
--[[
	IncubationService
	ServerScriptService/SAD_Server/Services/IncubationService  (ModuleScript)

	Incubators: the wait, and the moment it pays off.

	═══ THE TIMER IS THE RARITY TELL ═══════════════════════════════════════════
	Incubation length scales with rarity, and the player can see it. A 45-minute
	timer says "Mythic" before the species is known - which is the whole point
	(docs/01 §2). The wait is not friction, it is the anticipation the reveal
	needs to land against.
	═══════════════════════════════════════════════════════════════════════════

	Timers use os.time(), NOT tick() or os.clock(). Wall-clock time is the only
	kind that survives a player logging off, and an egg that pauses while you
	are away would make the whole system feel broken - docs/13 flags this as the
	bug to watch for in this step.

	Incubators are PHYSICAL. The pads built into every park in Step 6 carry a
	ProximityPrompt that fills, counts down, and finally says HATCH. That is
	FTUE beats 7 and 8 verbatim, and it means the reveal works before any menu
	exists.

	API:
		IncubationService.BeginIncubation(player, eggUid, slotIndex?) -> ok, reason?
		IncubationService.Claim(player, slotIndex) -> ok, reason?
		IncubationService.AutoStart(player) -> started
		IncubationService.DurationFor(data, rarity) -> seconds
		IncubationService.GetSlotCount(player) -> number
		IncubationService.Hatched  Signal(player, uid, entry, odds)

	Depends on: DinosaurService, MutationService, PlayerDataService, ParkService,
	            RarityConfig, UpgradeConfig, Net.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local MutationConfig = require(Shared.Config.MutationConfig)
local RarityConfig = require(Shared.Config.RarityConfig)
local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local Economy = require(Shared.Modules.Economy)
local Format = require(Shared.Modules.Format)
local Log = require(Shared.Modules.Log)
local Net = require(Shared.Modules.Net)
local Signal = require(Shared.Modules.Signal)
local Stats = require(Shared.Modules.Stats)

local IncubationService = {}

IncubationService.Hatched = Signal.new()

local DinosaurService, MutationService, PlayerDataService, ParkService, EggService
local NotificationService

--- [player] = { [slotIndex] = ProximityPrompt }
local prompts: { [Player]: { [number]: ProximityPrompt } } = {}

-- ── Timing ──────────────────────────────────────────────────────────────────

--[[
	How long a rarity takes to hatch for this player.

	Base from RarityConfig, scaled by the Incubator Speed track (down to -60%).
	The Fast Hatch gamepass multiplies in at Step 21.
]]
function IncubationService.DurationFor(data, rarity: string): number
	local tier = RarityConfig.Tiers[rarity]
	if not tier then
		return 60
	end

	local speedMult = Stats.IncubationMult(data)
	return math.max(5, math.floor(tier.IncubationSecs * speedMult))
end

function IncubationService.GetSlotCount(player: Player): number
	local data = PlayerDataService.Get(player)
	if not data then
		return 0
	end
	return Stats.Incubators(data)
end

local function firstFreeSlot(data, slotCount: number): number?
	for index = 1, slotCount do
		if not data.Incubators[index] then
			return index
		end
	end
	return nil
end

-- ── Starting ────────────────────────────────────────────────────────────────

--[[
	Puts a stored egg into an incubator. Returns (ok, reason).

	`slotIndex` nil takes the first free slot, which is what auto-start and the
	pad prompt both want.
]]
--- Named BeginIncubation rather than Start: every service's Start(app) belongs
--- to Bootstrap's lifecycle, and one function cannot be both.
function IncubationService.BeginIncubation(player: Player, eggUid: string, slotIndex: number?): (boolean, string?)
	local data = PlayerDataService.Get(player)
	if not data then
		return false, "profile not loaded"
	end

	local egg = data.Eggs[eggUid]
	if not egg then
		return false, "no such egg"
	end

	local slotCount = IncubationService.GetSlotCount(player)
	local slot = slotIndex or firstFreeSlot(data, slotCount)

	if not slot or slot < 1 or slot > slotCount then
		return false, "no free incubator"
	end
	if data.Incubators[slot] then
		return false, "incubator busy"
	end

	local now = os.time()
	local duration = IncubationService.DurationFor(data, egg.Rarity)

	-- One write: the egg leaves storage and enters the incubator together, so
	-- there is no window where it is in both or in neither.
	PlayerDataService.UpdateKeys(player, { "Eggs", "Incubators" }, function(profile)
		profile.Eggs[eggUid] = nil
		profile.Incubators[slot] = {
			EggUid = eggUid,
			Rarity = egg.Rarity,
			Origin = egg.Origin,
			StartedAt = now,
			HatchAt = now + duration,
		}
	end, "incubate")

	Log.info("IncubationService", "%s started a %s egg in slot %d (%s)",
		player.Name, egg.Rarity, slot, Format.Time(duration))

	return true, nil
end

--- Fills every free incubator from storage, rarest first - so a Titan egg is
--- never left in the bag while a Common occupies the last slot.
function IncubationService.AutoStart(player: Player): number
	local data = PlayerDataService.Get(player)
	if not data then
		return 0
	end

	local queued = {}
	for uid, egg in data.Eggs do
		table.insert(queued, { Uid = uid, Rarity = egg.Rarity })
	end
	table.sort(queued, function(a, b)
		return RarityConfig.RankOf(a.Rarity) > RarityConfig.RankOf(b.Rarity)
	end)

	local started = 0
	for _, entry in queued do
		local ok = IncubationService.BeginIncubation(player, entry.Uid)
		if not ok then
			break -- no free slots; the rest stay in storage
		end
		started += 1
	end
	return started
end

-- ── Hatching ────────────────────────────────────────────────────────────────

local function announce(player: Player, entry, odds: string)
	local tier = RarityConfig.Tiers[entry.Rarity]
	local name = DinosaurService.DisplayNameOf(entry)
	local isPrime = entry.Mutation2 ~= nil

	--[[
		RarityConfig decides how loud a hatch is: AnnounceKind is the severity
		and CrossServer decides whether every server hears it. Both are content
		values, so a re-tune is a config edit rather than a code change.
	]]
	if isPrime then
		NotificationService.Announce({
			Kind = "banner",
			Text = string.format("PRIME! %s hatched a %s", player.DisplayName, name),
			Color = RarityConfig.GetColor(entry.Rarity),
			Duration = 5,
		})
		Log.info("IncubationService", "PRIME HATCH: %s got a %s (%s)", player.Name, name, odds)
		return
	end

	if tier.AnnounceKind == "takeover" then
		local payload = {
			Kind = "takeover",
			Title = "NO WAY!",
			Subtitle = string.format("%s hatched a %s", player.DisplayName, name),
			Headline = odds,
			Color = RarityConfig.GetColor(entry.Rarity),
			Duration = 6,
		}
		if tier.CrossServer then
			NotificationService.Announce(payload)
		else
			NotificationService.All(payload)
		end
		Log.info("IncubationService", "%s HATCH: %s got a %s (%s)",
			string.upper(tier.DisplayName), player.Name, name, odds)
	elseif tier.AnnounceKind == "banner" or tier.AnnounceKind == "toast" then
		NotificationService.All({
			Kind = "banner",
			Text = string.format("%s hatched a %s %s!", player.DisplayName, tier.DisplayName, name),
			Color = RarityConfig.GetColor(entry.Rarity),
			Duration = 4,
		})
	end
end

--[[
	Opens a finished incubator. Returns (ok, reason).

	Rolls species and mutation HERE, at the moment of opening - reveals two and
	three, decided as late as possible so the weather at this instant counts.

	The egg is only consumed once a dinosaur actually exists. A full store
	leaves it incubating and ready, so nothing is ever destroyed by a failed
	hatch.
]]
function IncubationService.Claim(player: Player, slotIndex: number): (boolean, string?)
	local data = PlayerDataService.Get(player)
	if not data then
		return false, "profile not loaded"
	end

	local slot = data.Incubators[slotIndex]
	if not slot then
		return false, "empty incubator"
	end
	if os.time() < slot.HatchAt then
		return false, "not ready"
	end

	local speciesId = DinosaurService.RollSpecies(slot.Origin, slot.Rarity)
	if not speciesId then
		return false, "no species available"
	end

	-- The egg's origin zone, so weather that is worse in one place follows the
	-- egg rather than the player (docs/04 §2, Blizzard's "Frozen Valley x2").
	local mutation, mutation2 = MutationService.Roll(player, slot.Origin)

	local uid, entry, reason = DinosaurService.Create(player, {
		SpeciesId = speciesId,
		Rarity = slot.Rarity,
		Mutation = mutation,
		Mutation2 = mutation2,
		Origin = slot.Origin,
	})

	if not uid then
		-- Refused, not lost. The egg stays ready in its incubator.
		NotificationService.Alert(player, "Dinosaur storage full - sell or place some first",
			{ Duration = 3, Tag = "storage" })
		return false, reason
	end

	PlayerDataService.UpdateKeys(player, { "Incubators", "Dinos", "Index", "Stats" }, function(profile)
		profile.Incubators[slotIndex] = nil
	end, "hatch")

	--[[
		The odds line. This is the number players screenshot, so it is computed
		from the same weight tables the roll actually used rather than written
		out by hand somewhere.
	]]
	local zoneWeights = RarityConfig.WeightsForZone(slot.Origin)
	local odds = Format.Odds(zoneWeights and zoneWeights[slot.Rarity] or 0, RarityConfig.WeightTotal)

	local mutationOdds = nil
	if mutation and mutation ~= "none" then
		local mutationEntry = MutationConfig.Get(mutation)
		mutationOdds = Format.Odds(mutationEntry.Weight, MutationConfig.WeightTotal)
	end

	Net.FireClient("HatchResult", player, {
		DinoUid = uid,
		SpeciesId = speciesId,
		DisplayName = DinosaurService.DisplayNameOf(entry),
		Rarity = slot.Rarity,
		Mutation = mutation ~= "none" and mutation or nil,
		Mutation2 = mutation2,
		Stars = entry.Stars,
		Odds = odds,
		MutationOdds = mutationOdds,
		IncomePerSec = DinosaurService.IncomeOf(entry, data),
	})

	--[[
		Straight into the park when there is room.

		A player two minutes into the game should not have to find a menu to
		make their first dinosaur earn anything - and an empty park after a
		successful run reads as the game not having worked. Step 13's Dinos
		menu adds precise placement on top; this is the floor.
	]]
	if DinosaurService.GetPlacedCount(player) < Economy.SlotCap(data) then
		DinosaurService.PlaceBest(player)
	end

	announce(player, entry, odds)
	Log.info("IncubationService", "%s hatched %s (%s, %s)",
		player.Name, DinosaurService.DisplayNameOf(entry), slot.Rarity, odds)

	IncubationService.Hatched:Fire(player, uid, entry, odds)
	return true, nil
end

-- ── Incubator pads ──────────────────────────────────────────────────────────

--[[
	Keeps each pad's prompt in step with what its slot is doing.

	Physical rather than menu-driven on purpose: FTUE beats 7 and 8 are "walk
	onto the incubator pad" and "watch it hatch", and a player two minutes into
	the game should not have to find a menu to see their first dinosaur.
]]
local function refreshPrompts(player: Player)
	local held = prompts[player]
	if not held then
		return
	end

	local data = PlayerDataService.Get(player)
	if not data then
		return
	end

	local slotCount = IncubationService.GetSlotCount(player)
	local storedEggs = 0
	for _ in data.Eggs do
		storedEggs += 1
	end

	local now = os.time()

	for slotIndex, prompt in held do
		if slotIndex > slotCount then
			prompt.Enabled = false
			continue
		end

		local slot = data.Incubators[slotIndex]

		if not slot then
			prompt.Enabled = storedEggs > 0
			prompt.ActionText = "Incubate"
			prompt.ObjectText = string.format("Incubator %d", slotIndex)
		elseif now >= slot.HatchAt then
			prompt.Enabled = true
			prompt.ActionText = "HATCH!"
			prompt.ObjectText = RarityConfig.Tiers[slot.Rarity].DisplayName .. " egg"
		else
			-- Visible but not usable: the countdown IS the rarity tell.
			prompt.Enabled = false
			prompt.ActionText = "Incubating"
			prompt.ObjectText = Format.Time(slot.HatchAt - now)
		end
	end
end

local function bindPads(player: Player, plot: Model)
	local incubators = plot:FindFirstChild("Incubators")
	if not incubators then
		return
	end

	local held = {}
	prompts[player] = held

	for _, pad in incubators:GetChildren() do
		local slotIndex = pad:GetAttribute("SlotIndex")
		if not slotIndex then
			continue
		end

		local existing = pad:FindFirstChildOfClass("ProximityPrompt")
		if existing then
			existing:Destroy()
		end

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "IncubatorPrompt"
		prompt.ActionText = "Incubate"
		prompt.ObjectText = string.format("Incubator %d", slotIndex)
		prompt.HoldDuration = 0.2
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Enabled = false
		prompt.Parent = pad

		prompt.Triggered:Connect(function(triggerer: Player)
			-- Only the owner. A visitor standing on your pad is a visitor.
			if triggerer ~= player then
				return
			end

			local data = PlayerDataService.Get(player)
			if not data then
				return
			end

			if data.Incubators[slotIndex] then
				IncubationService.Claim(player, slotIndex)
			else
				local rarest, rarestRank = nil, -1
				for uid, egg in data.Eggs do
					local rank = RarityConfig.RankOf(egg.Rarity)
					if rank > rarestRank then
						rarest, rarestRank = uid, rank
					end
				end
				if rarest then
					IncubationService.BeginIncubation(player, rarest, slotIndex)
				end
			end

			refreshPrompts(player)
		end)

		held[slotIndex] = prompt
	end

	refreshPrompts(player)
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function IncubationService.Init(app)
	DinosaurService = app.Get("DinosaurService")
	MutationService = app.Get("MutationService")
	PlayerDataService = app.Get("PlayerDataService")
	NotificationService = app.Get("NotificationService")
	ParkService = app.Get("ParkService")
	EggService = app.Get("EggService")
end

function IncubationService.Start(app)
	Net.OnEvent("RequestStartIncubation", function(player: Player, eggUid: string, slotIndex: number)
		IncubationService.BeginIncubation(player, eggUid, slotIndex)
		refreshPrompts(player)
	end)

	Net.OnEvent("RequestClaimHatch", function(player: Player, slotIndex: number)
		IncubationService.Claim(player, slotIndex)
		refreshPrompts(player)
	end)

	ParkService.PlotAssigned:Connect(bindPads)
	ParkService.PlotReleased:Connect(function(player)
		prompts[player] = nil
	end)

	-- Banking an egg should not then require a second trip to a menu.
	EggService.EggDeposited:Connect(function(player)
		task.defer(function()
			IncubationService.AutoStart(player)
			refreshPrompts(player)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		prompts[player] = nil
	end)

	--[[
		One shared tick keeps every pad's countdown current. 1 Hz, over at most
		24 players x 8 pads - trivial, and it means a pad that becomes ready
		while its owner is standing next to it says so.
	]]
	task.spawn(function()
		while true do
			task.wait(1)
			for player in prompts do
				local ok, err = pcall(refreshPrompts, player)
				if not ok then
					Log.error("IncubationService", "Prompt refresh failed for %s: %s", player.Name, tostring(err))
				end
			end
		end
	end)

	Log.info("IncubationService", "Ready. Incubator pads are live")
end

return IncubationService
