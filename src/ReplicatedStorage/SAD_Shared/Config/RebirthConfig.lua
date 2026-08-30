--!strict
--[[
	RebirthConfig
	ReplicatedStorage/SAD_Shared/Config/RebirthConfig  (ModuleScript)

	Rebirth costs, what survives a reset, and what each one permanently grants.
	Mirrors docs/05-economy.md §6.

	Rebirth is the economy's primary deflation event: it removes the entire
	Fossil supply and every Fossil-bought upgrade from a player, in exchange for
	multipliers that make the next run several times faster.

	Depends on: nothing.
]]

local RebirthConfig = {}

RebirthConfig.BaseCost = 250000
RebirthConfig.Growth = 5.2

--- Also required, so a player cannot rebirth on a bare plot and lose nothing.
RebirthConfig.MinDinosaursBase = 2 -- rebirth n requires n + this many dinosaurs

-- ── Permanent grants, per rebirth ───────────────────────────────────────────

RebirthConfig.Grants = {
	IncomeMultPerRebirth = 0.15, -- additive: x(1 + 0.15n)
	LuckPerRebirth = 0.05,
	LuckCap = 0.75, -- reached at R15
	MutLuckPerRebirth = 0.03,
	MutLuckCap = 0.45, -- R15
	MoveSpeedPerRebirth = 0.02,
	MoveSpeedCap = 0.40, -- R20
	OfflineHoursPerRebirth = 1,
	OfflineHoursCap = 12,
	DinoSlotsPerTwoRebirths = 1,
	DinoSlotsCap = 10,
}

--- Vault slots unlock at these rebirth counts (docs/03 §4.3).
RebirthConfig.VaultSlotMilestones = { 3, 7, 12, 20 }
RebirthConfig.VaultSlotsBase = 1
RebirthConfig.VaultSlotsMax = 5

--- Cosmetic name-tag tiers.
RebirthConfig.NameTagTiers = {
	{ Rebirths = 0, Id = "bone", DisplayName = "Bone", Color = "E8E4D9" },
	{ Rebirths = 1, Id = "amber", DisplayName = "Amber", Color = "FFB020" },
	{ Rebirths = 5, Id = "obsidian", DisplayName = "Obsidian", Color = "2A2A35" },
	{ Rebirths = 10, Id = "prismatic", DisplayName = "Prismatic", Color = "9B5DE5" },
	{ Rebirths = 20, Id = "titan", DisplayName = "Titan", Color = "FFD24A" },
}

--[[
	═══ EVERY PROFILE KEY IS CLASSIFIED, IN EXACTLY ONE PLACE ══════════════════
	docs/13 §Step 20: "the reset must be one atomic profile write. A
	half-applied rebirth is the worst bug in the game."

	The half-applied rebirth this guards against is not a torn write - it is a
	field nobody classified. `Preserved` was written at Step 3 and the schema
	has grown eleven fields since; every one of them defaulted to RESET simply
	by not being mentioned, and four of those would have made rebirth an
	anti-abuse bypass.

	So the three lists below must cover the whole template, each key exactly
	once, and `RebirthConfig.Validate` asserts it at boot. Same discipline the
	replication allowlist uses (docs/09 §4): a new field forces a decision
	rather than inheriting one.
	═══════════════════════════════════════════════════════════════════════════

	Vaulted dinosaurs surviving is the single most important entry in any of
	them: a player who loses their favourite to a rebirth does not do a second.
	`Dinos` is in `Partial` for exactly that reason.
]]
RebirthConfig.Preserved = {
	-- Identity and bookkeeping
	SchemaVersion = "schema, not progress",
	FirstJoinAt = "account age; a rebirth is not a new account",
	LastSeen = "offline income reads it; wiping it loses the window, not the money",
	Rebirths = "incremented BY the rebirth, obviously not reset by it",

	-- docs/05 §6's "what never resets" list
	DNA = "the depth currency; the whole point is that it survives",
	LuckNodes = "permanent luck, bought with DNA or granted by milestones",
	Index = "discovery is knowledge, and knowledge is not spent",
	IndexMilestones = "or the same milestone pays out every rebirth",
	Quests = "docs/05 §6 lists quests and dailies explicitly",
	Daily = "the streak is a real-world commitment; a rebirth must not break it",
	Stats = "lifetime statistics, leaderboards and badges read these",
	Settings = "a player's preferences are not progress",
	Gamepasses = "paid for with money",
	ProcessedReceipts = "the receipt ledger; clearing it would allow a re-grant",
	RobuxSpent = "spend history",
	Items = "consumables already earned",
	Tutorial = "nobody should be taught the game twice",
	NewPlayerProtectionDone = "protection is spent once, not once per rebirth",

	--[[
		Added after Step 3 and NOT in the original list - each would have been
		silently wiped:
	]]
	Titles = "cosmetic, from streaks and milestones that themselves never reset",
	BonusDinoSlots = "granted permanently by Index milestones; 'permanent' has to mean it",
	BonusVaultSlots = "same, plus the 30-day streak reward",
	Shrines = "map knowledge, the same category as Index - you walked there once",
	Boosts = "a Luck Potion mid-use; losing it to a rebirth is a refund nobody gets",
	ShieldUntil = "a shield already granted, often minutes old",
	ShieldBankSecs = "banked shield time, likewise",

	--[[
		The four anti-abuse fields. These are the ones that mattered most:
		resetting them would make a rebirth a way to clear a same-victim
		cooldown, the 90-second global cooldown, and the Mercy Shield history
		that protects a player being farmed.
	]]
	StealCooldowns = "a cooldown a rebirth can clear is not a cooldown",
	RevengeMarks = "earned by being robbed; a rebirth must not cancel the revenge",
	RobbedAt = "the Mercy Shield's history; clearing it removes the anti-griefing floor",
	GlobalStealAt = "the 90-second raid cooldown",
}

--[[
	Reset to the ProfileTemplate default. Everything a rebirth is FOR.
]]
RebirthConfig.Reset = {
	Fossils = "the currency being spent",
	Upgrades = "docs/05 §6: all Fossil-purchased upgrade levels",
	Defences = "Fossil-purchased too, and on the same board",
	Eggs = "un-hatched stock; the Rebirth Cache replaces it with something better",
	Incubators = "whatever was cooking goes with the eggs",
	BankedFossils = "uncollected Fossils are still Fossils",
	BankedAt = "the banking interval restarts with the bank",
	BankedRate = "likewise; a zero rate accrues nothing, which is correct at zero dinosaurs",
}

--[[
	Neither wholly kept nor wholly cleared. RebirthService handles each one
	explicitly, and listing them here is what stops "it is complicated" from
	meaning "nobody decided".
]]
RebirthConfig.Partial = {
	Dinos = "vaulted dinosaurs survive (up to VaultSlots); everything else goes",
	ZonesUnlocked = "kept up to the highest rebirth-gated zone you still qualify for",
}

--[[
	Asserts the three lists cover the template exactly once each. Called by
	DataService at boot, so a field added without a decision fails to start
	rather than being silently destroyed the first time someone rebirths.

	Returns an error string, or nil.
]]
function RebirthConfig.Validate(template): string?
	local seen = {}

	for _, list in { RebirthConfig.Preserved, RebirthConfig.Reset, RebirthConfig.Partial } do
		for key in list do
			if seen[key] then
				return string.format("'%s' is classified twice", key)
			end
			seen[key] = true
			if template[key] == nil then
				return string.format("'%s' is classified but is not in the profile template", key)
			end
		end
	end

	for key in template do
		if not seen[key] then
			return string.format(
				"profile field '%s' is in none of Preserved, Reset or Partial - "
					.. "a rebirth would silently destroy it", key)
		end
	end

	return nil
end

RebirthConfig.CacheEnabled = true
RebirthConfig.CacheMinRarity = "rare"
RebirthConfig.CacheTiersBelowBest = 1

-- ── Helpers ─────────────────────────────────────────────────────────────────

--[[
	Identical to UpgradeConfig.RoundSignificant, duplicated rather than required
	because this module is declared dependency-free and every config loads it.
	Six lines of arithmetic with no state; the spec asserts the two agree.
]]
local function roundSignificant(value: number, digits: number?): number
	if value <= 0 then
		return 0
	end
	local places = digits or 3
	local magnitude = math.floor(math.log(value, 10)) - (places - 1)
	local scale = 10 ^ magnitude
	if scale < 1 then
		return math.floor(value + 0.5)
	end
	return math.floor(value / scale + 0.5) * scale
end

--[[
	Fossil cost of performing rebirth number `n` (1-indexed).

	Rounded to three significant figures for the same reason every upgrade
	price is (UpgradeConfig.RoundSignificant): a price is a thing a player
	reads and a thing a comparison is made against. Unrounded, rebirth 3 comes
	out as 6760000.000000001 - which renders with a tail of digits, and which a
	player holding exactly 6,760,000 Fossils cannot afford.
]]
function RebirthConfig.CostOf(n: number): number
	if n < 1 then
		return 0
	end
	return roundSignificant(RebirthConfig.BaseCost * RebirthConfig.Growth ^ (n - 1))
end

function RebirthConfig.DinosaursRequired(n: number): number
	return n + RebirthConfig.MinDinosaursBase
end

function RebirthConfig.IncomeMultiplier(rebirths: number): number
	return 1 + RebirthConfig.Grants.IncomeMultPerRebirth * rebirths
end

function RebirthConfig.LuckBonus(rebirths: number): number
	return math.min(rebirths * RebirthConfig.Grants.LuckPerRebirth, RebirthConfig.Grants.LuckCap)
end

function RebirthConfig.MutLuckBonus(rebirths: number): number
	return math.min(rebirths * RebirthConfig.Grants.MutLuckPerRebirth, RebirthConfig.Grants.MutLuckCap)
end

function RebirthConfig.MoveSpeedBonus(rebirths: number): number
	return math.min(rebirths * RebirthConfig.Grants.MoveSpeedPerRebirth, RebirthConfig.Grants.MoveSpeedCap)
end

function RebirthConfig.OfflineCapSecs(rebirths: number): number
	local hours = math.min(4 + rebirths * RebirthConfig.Grants.OfflineHoursPerRebirth, RebirthConfig.Grants.OfflineHoursCap)
	return hours * 3600
end

function RebirthConfig.BonusDinoSlots(rebirths: number): number
	return math.min(math.floor(rebirths / 2), RebirthConfig.Grants.DinoSlotsCap)
end

function RebirthConfig.VaultSlots(rebirths: number): number
	local slots = RebirthConfig.VaultSlotsBase
	for _, milestone in RebirthConfig.VaultSlotMilestones do
		if rebirths >= milestone then
			slots += 1
		end
	end
	return math.min(slots, RebirthConfig.VaultSlotsMax)
end

function RebirthConfig.NameTagFor(rebirths: number)
	local current = RebirthConfig.NameTagTiers[1]
	for _, tier in RebirthConfig.NameTagTiers do
		if rebirths >= tier.Rebirths then
			current = tier
		end
	end
	return current
end

--[[
	═══ THE PREVIEW IS PURE, AND SHARED ════════════════════════════════════════
	docs/13 §Step 20 asks for a keep/lose/gain preview. The confirm screen has
	to show the same numbers the transaction will produce, or it is a contract
	the game does not honour - "you keep 4 vaulted dinosaurs" is the one line a
	player reads before deleting their park.

	So the whole calculation is here, pure, and both sides call it: the client
	to draw the screen and the server to perform the reset. Same reasoning as
	Economy and Stats, and the same dependency-free-by-argument shape
	ZoneConfig.UnlockCheck uses.
	═══════════════════════════════════════════════════════════════════════════
]]

--[[
	Which zones survive a rebirth to `rebirths`. Returns (kept, lost) as sets.

	docs/05 §6: unlocks reset "above the highest rebirth-gated zone you qualify
	for". A zone with no rebirth requirement cannot be that floor - clearing it
	says nothing about progression - and a free zone is always kept, because
	"losing" something that costs nothing is a reset nobody can notice paying.
]]
function RebirthConfig.ZonesAfter(unlocked, rebirths: number, zoneConfig)
	local floorOrder = 0
	for _, zoneId in zoneConfig.Order do
		local zone = zoneConfig.Get(zoneId)
		if zone and zone.Unlock.Rebirths > 0 and rebirths >= zone.Unlock.Rebirths then
			floorOrder = math.max(floorOrder, zone.Order)
		end
	end

	local kept, lost = {}, {}
	for zoneId in unlocked do
		local zone = zoneConfig.Get(zoneId)
		if not zone or zone.Unlock.Fossils <= 0 or zone.Order <= floorOrder then
			kept[zoneId] = true
		else
			lost[zoneId] = true
		end
	end
	return kept, lost
end

--[[
	Which dinosaurs survive. Vaulted only, up to the vault slots this player
	has - and ordered by pedestal index so which ones survive a slot reduction
	is deterministic rather than whatever `pairs` returned.
]]
function RebirthConfig.DinosAfter(data)
	local slots = RebirthConfig.VaultSlots(data.Rebirths or 0) + (data.BonusVaultSlots or 0)

	local vaulted = {}
	for uid, entry in data.Dinos do
		if entry.Vault then
			table.insert(vaulted, { Uid = uid, Entry = entry, Slot = entry.Vault })
		end
	end
	table.sort(vaulted, function(a, b)
		return a.Slot < b.Slot
	end)

	local kept = {}
	for index, row in vaulted do
		if index <= slots then
			kept[row.Uid] = row.Entry
		end
	end
	return kept
end

--[[
	docs/05 §6's anti-repetition rule: one guaranteed egg of the highest rarity
	ever hatched, minus `CacheTiersBelowBest`, floored at CacheMinRarity.

	Read from Stats.RarestRarity, which is Preserved - so the cache scales with
	a career rather than with the run that was just deleted.
]]
function RebirthConfig.CacheRarity(data, rarityConfig): string?
	if not RebirthConfig.CacheEnabled then
		return nil
	end

	local best = (data.Stats and data.Stats.RarestRarity) or "common"
	local target = rarityConfig.TierBelow(best, RebirthConfig.CacheTiersBelowBest)

	if rarityConfig.RankOf(target) < rarityConfig.RankOf(RebirthConfig.CacheMinRarity) then
		target = RebirthConfig.CacheMinRarity
	end
	return target
end

--- The full keep/lose/gain block for the confirm screen.
function RebirthConfig.Preview(data, zoneConfig, rarityConfig)
	local nextCount = (data.Rebirths or 0) + 1

	local vaulted, loose = 0, 0
	for _, entry in data.Dinos do
		if entry.Vault then
			vaulted += 1
		else
			loose += 1
		end
	end

	local keptZones, lostZones = RebirthConfig.ZonesAfter(data.ZonesUnlocked, nextCount, zoneConfig)
	local function count(set)
		local n = 0
		for _ in set do
			n += 1
		end
		return n
	end

	--- Kept vaulted is not the same as vaulted: slots can bind.
	local survivors = count(RebirthConfig.DinosAfter(data))

	return {
		Rebirth = nextCount,
		Cost = RebirthConfig.CostOf(nextCount),
		DinosRequired = RebirthConfig.DinosaursRequired(nextCount),
		Keeps = {
			Vaulted = survivors,
			Zones = count(keptZones),
			Dna = data.DNA or 0,
			IndexEntries = count(data.Index),
			LuckNodes = data.LuckNodes or 0,
		},
		Loses = {
			Fossils = data.Fossils or 0,
			Dinos = loose + (vaulted - survivors),
			Zones = count(lostZones),
			Eggs = count(data.Eggs),
			ZoneCost = (function()
				local total = 0
				for zoneId in lostZones do
					total += zoneConfig.Get(zoneId).Unlock.Fossils
				end
				return total
			end)(),
		},
		Gains = {
			IncomeMultiplier = RebirthConfig.IncomeMultiplier(nextCount),
			Luck = RebirthConfig.LuckBonus(nextCount),
			MutLuck = RebirthConfig.MutLuckBonus(nextCount),
			MoveSpeed = RebirthConfig.MoveSpeedBonus(nextCount),
			OfflineCapHours = RebirthConfig.OfflineCapSecs(nextCount) / 3600,
			DinoSlots = RebirthConfig.BonusDinoSlots(nextCount),
			VaultSlots = RebirthConfig.VaultSlots(nextCount),
			NameTag = RebirthConfig.NameTagFor(nextCount).DisplayName,
			CacheRarity = RebirthConfig.CacheRarity(data, rarityConfig),
		},
	}
end

return RebirthConfig
