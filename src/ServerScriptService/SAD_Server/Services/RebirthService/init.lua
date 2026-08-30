--!nonstrict
--[[
	RebirthService
	ServerScriptService/SAD_Server/Services/RebirthService  (ModuleScript)

	The economy's deflation event: it removes a player's entire Fossil supply
	and every Fossil-bought upgrade, in exchange for multipliers that make the
	next run several times faster (docs/05 §6).

	═══ ONE WRITE ══════════════════════════════════════════════════════════════
	docs/13 §Step 20: "the reset must be one atomic profile write. A
	half-applied rebirth is the worst bug in the game."

	So `Perform` builds the ENTIRE new profile shape first - what survives,
	what returns to its default, what is partially kept - and applies it in a
	single `UpdateKeys` callback. Nothing yields inside that callback, so there
	is no point at which a player's Fossils are gone and their multiplier has
	not arrived.

	The Rebirth Cache is granted AFTER the write, deliberately: an egg that
	fails to fit is a missing egg, and a reset that fails halfway is a
	destroyed account.
	═══════════════════════════════════════════════════════════════════════════

	═══ THE FIELD NOBODY CLASSIFIED ════════════════════════════════════════════
	The other half of "half-applied" is a profile field that nobody decided
	about. RebirthConfig now classifies every key as Preserved, Reset or
	Partial, and asserts the three lists cover the template exactly once at
	boot - so a field added in a later step cannot default to being destroyed.
	═══════════════════════════════════════════════════════════════════════════

	API:
		RebirthService.CanRebirth(player) -> ok, reason?, requirements
		RebirthService.Preview(player) -> { Cost, Keeps, Loses, Gains }
		RebirthService.Perform(player) -> ok, reason?
		RebirthService.Rebirthed  Signal(player, newCount)

	Depends on: RebirthConfig, RarityConfig, ZoneConfig, Economy, Stats,
	            PlayerDataService, DataService, EconomyService, ParkService,
	            EggService, StealService, DinosaurService, NotificationService.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local Economy = require(Shared.Modules.Economy)
local Format = require(Shared.Modules.Format)
local Log = require(Shared.Modules.Log)
local Net = require(Shared.Modules.Net)
local RarityConfig = require(Shared.Config.RarityConfig)
local RebirthConfig = require(Shared.Config.RebirthConfig)
local Signal = require(Shared.Modules.Signal)
local ZoneConfig = require(Shared.Config.ZoneConfig)

local RebirthService = {}

RebirthService.Rebirthed = Signal.new()

local PlayerDataService, EconomyService, ParkService, EggService
local StealService, NotificationService, DinosaurService, ProfileTemplate

-- ── Eligibility ─────────────────────────────────────────────────────────────

--[[
	docs/05 §6: `rebirthCost(n) = 250,000 * 5.2^(n-1)`, "must also own n+2
	dinosaurs".

	The dinosaur requirement is what stops a player rebirthing on a bare plot
	and losing nothing - a rebirth is meant to cost something.
]]
function RebirthService.CanRebirth(player: Player): (boolean, string?, any)
	local data = PlayerDataService.Get(player)
	if not data then
		return false, "profile not loaded", {}
	end

	local next = (data.Rebirths or 0) + 1
	local cost = RebirthConfig.CostOf(next)
	local needed = RebirthConfig.DinosaursRequired(next)

	local owned = 0
	for _ in data.Dinos do
		owned += 1
	end

	local requirements = {
		{ Label = Format.Number(cost) .. " Fossils", Met = (data.Fossils or 0) >= cost },
		{ Label = needed .. " dinosaurs", Met = owned >= needed },
	}

	--[[
		docs/13 §Step 20: "confirm a mid-carry rebirth is rejected."

		Both carries matter and for different reasons. A carried egg would be
		destroyed by the reset with no record of it anywhere; a carried STOLEN
		dinosaur belongs to someone else, and rebirthing mid-raid would resolve
		it into a profile that no longer has the slot for it.
	]]
	local carrying = EggService.GetCarryCount(player) > 0
	local raiding = StealService and StealService.IsCarrying(player) ~= nil
	table.insert(requirements, { Label = "not carrying anything", Met = not (carrying or raiding) })

	for _, requirement in requirements do
		if not requirement.Met then
			return false, requirement.Label, requirements
		end
	end

	return true, nil, requirements
end

--[[
	What a rebirth would do, for the confirm screen.

	Delegated to RebirthConfig, which the CLIENT also calls to draw that
	screen. The preview a player reads before deleting their park and the
	transaction that deletes it are then the same calculation rather than two
	that agree today.
]]
function RebirthService.Preview(player: Player)
	local data = PlayerDataService.Get(player)
	if not data then
		return nil
	end

	local preview = RebirthConfig.Preview(data, ZoneConfig, RarityConfig)
	-- The one term that is not pure config: what the park is currently making.
	preview.Loses.ParkRate = Economy.ParkIncomeRate(data)
	return preview
end

--- Shorthands, so the reset below reads as what it does.
function RebirthService.ZonesAfter(data, rebirths: number)
	return RebirthConfig.ZonesAfter(data.ZonesUnlocked, rebirths, ZoneConfig)
end

function RebirthService.DinosAfter(data)
	return RebirthConfig.DinosAfter(data)
end

function RebirthService.CacheRarity(data): string?
	return RebirthConfig.CacheRarity(data, RarityConfig)
end

-- ── The reset ───────────────────────────────────────────────────────────────

function RebirthService.Perform(player: Player): (boolean, string?)
	local data = PlayerDataService.Get(player)
	if not data then
		return false, "profile not loaded"
	end

	local ok, reason = RebirthService.CanRebirth(player)
	if not ok then
		return false, reason
	end

	local newCount = (data.Rebirths or 0) + 1

	--[[
		Everything is decided BEFORE the write. The callback below does no
		arithmetic, calls nothing, and yields nowhere - it copies prepared
		values in. That is what makes it atomic in the only sense that matters
		here: there is no state the profile can be left in halfway.
	]]
	local keptDinos = RebirthService.DinosAfter(data)
	local keptZones = RebirthService.ZonesAfter(data, newCount)
	local cacheRarity = RebirthService.CacheRarity(data)
	local cacheUid = string.sub(HttpService:GenerateGUID(false):gsub("-", ""), 1, 8)

	--[[
		Every key classified as Reset returns to its template default, taken
		from the template itself rather than written out here - so a default
		that changes changes in one place.
	]]
	local defaults = {}
	for key in RebirthConfig.Reset do
		local default = ProfileTemplate[key]
		defaults[key] = if type(default) == "table" then {} else default
	end

	local touched = { "Rebirths", "Dinos", "ZonesUnlocked" }
	for key in RebirthConfig.Reset do
		table.insert(touched, key)
	end

	PlayerDataService.UpdateKeys(player, touched, function(profile)
		profile.Rebirths = newCount

		for key, value in defaults do
			profile[key] = value
		end

		profile.Dinos = keptDinos
		profile.ZonesUnlocked = keptZones

		-- The cache egg goes in inside the same write, so a player is never
		-- momentarily left with nothing at all.
		if cacheRarity then
			profile.Eggs[cacheUid] = {
				Rarity = cacheRarity,
				Origin = "rebirth",
				AcquiredAt = os.time(),
			}
		end
	end, "rebirth " .. newCount)

	--[[
		Everything after this point is consequence, not transaction. Each is
		safe to fail on its own: the rebirth has already happened and is
		already consistent.
	]]
	EconomyService.InvalidateRate(player)
	ParkService.RefreshDinos(player)
	if ParkService.RefreshTotem then
		ParkService.RefreshTotem(player)
	end

	--[[
		Saved immediately rather than at the next autosave. A rebirth is the
		single most expensive thing a player does, and losing one to a crash in
		the following thirty seconds is not a bug anybody forgives.
	]]
	PlayerDataService.Save(player, "rebirth")

	local grants = RebirthConfig.NameTagFor(newCount)
	NotificationService.Takeover(player, {
		Title = "REBIRTH " .. newCount,
		Subtitle = string.format("x%.2f income  ·  +%d%% luck  ·  %s",
			RebirthConfig.IncomeMultiplier(newCount),
			math.floor(RebirthConfig.LuckBonus(newCount) * 100 + 0.5),
			grants.DisplayName),
		Headline = if cacheRarity
			then "1 " .. RarityConfig.Tiers[cacheRarity].DisplayName .. " EGG"
			else "",
		Duration = 6,
	})

	NotificationService.Announce({
		Kind = "banner",
		Text = string.format("%s reached Rebirth %d", player.DisplayName, newCount),
		Duration = 4,
	})

	RebirthService.Rebirthed:Fire(player, newCount)
	Log.info("RebirthService", "%s rebirthed to %d, kept %d vaulted and %d zone(s)",
		player.Name, newCount, (function()
			local n = 0
			for _ in keptDinos do
				n += 1
			end
			return n
		end)(), (function()
			local n = 0
			for _ in keptZones do
				n += 1
			end
			return n
		end)())

	return true
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function RebirthService.Init(app)
	PlayerDataService = app.Get("PlayerDataService")
	EconomyService = app.Get("EconomyService")
	ParkService = app.Get("ParkService")
	EggService = app.Get("EggService")
	DinosaurService = app.Get("DinosaurService")
	NotificationService = app.Get("NotificationService")

	-- DataService exposes it; see its footer. Nothing else reads the template.
	ProfileTemplate = app.Get("DataService").Template
end

function RebirthService.Start(app)
	local ok, service = pcall(app.Get, "StealService")
	StealService = if ok then service else nil

	--[[
		The coverage assertion. A profile field added in a later step that
		nobody classified would otherwise be destroyed by the first rebirth
		after it shipped, silently, on a live account.
	]]
	local problem = RebirthConfig.Validate(ProfileTemplate)
	assert(not problem, "[SAD] RebirthService: " .. tostring(problem))

	Net.OnEvent("RequestRebirth", function(player)
		local performed, reason = RebirthService.Perform(player)
		if not performed and reason then
			NotificationService.Toast(player, "CANNOT REBIRTH", reason)
		end
	end)

	Log.info("RebirthService", "Ready. Rebirth 1 costs %s and %d dinosaur(s)",
		Format.Number(RebirthConfig.CostOf(1)), RebirthConfig.DinosaursRequired(1))
end

return RebirthService
