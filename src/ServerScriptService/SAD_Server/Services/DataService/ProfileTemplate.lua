--!strict
--[[
	ProfileTemplate
	ServerScriptService/SAD_Server/Services/DataService/ProfileTemplate  (ModuleScript)

	The default profile for a brand-new player, and the reconcile source for
	every existing one. Mirrors docs/10-data-schema.md exactly - when that
	document changes, this file changes in the same commit.

	Two rules:

	1. Every key a service reads MUST exist here with a sensible default. A key
	   that only appears once a player has done something will be nil on their
	   first session, and that nil is how you get "attempt to index nil" three
	   weeks after launch on one player in one server.

	2. Player-owned dictionaries (Dinos, Eggs, Index, Items, Boosts...) are
	   EMPTY tables here. Reconcile adds an empty table when missing and then
	   leaves it alone, so a player's contents are never touched.

	3. NOTHING but profile fields goes in this table. Every key here is copied
	   into every player's save by Reconcile, so a helper list or a function
	   parked here would be persisted to 24 DataStore keys per server, forever.
	   The drift test that checks this file for missing keys lives in
	   tests/step2_spec.lua, deliberately holding its own independent key list.

	Depends on: nothing. Depended on by: DataService, Migrations, tests.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("SAD_Shared")
local GameConfig = require(Shared.Config.GameConfig)

local ProfileTemplate = {
	SchemaVersion = GameConfig.SchemaVersion,

	-- ── Currency ────────────────────────────────────────────────────────────
	Fossils = 0,
	DNA = 0,

	-- ── Progression ─────────────────────────────────────────────────────────
	Rebirths = 0,
	ZonesUnlocked = { plains = true }, -- Zone 1 is free; see docs/02 §2.1
	--[[
		[zoneId] = true for every Zone Shrine touched. Deliberately separate
		from ZonesUnlocked: buying a zone gets you in, WALKING to its shrine is
		what puts it on the Teleport Obelisk (docs/02 §2.2). That is the beat
		that teaches the map before it lets you skip it.
	]]
	Shrines = {},
	Upgrades = {}, -- [trackId] = level; absent means 0
	Defences = {}, -- [defenceId] = level
	LuckNodes = 0,

	-- ── Collection ──────────────────────────────────────────────────────────
	Dinos = {}, -- [dinoUid] = DinoEntry
	Eggs = {}, -- [eggUid] = EggEntry
	Incubators = {}, -- [slotIndex] = IncubatorSlot

	Index = {}, -- [speciesId] = IndexEntry
	IndexMilestones = {}, -- [milestoneId] = true

	-- ── Boosts & items ──────────────────────────────────────────────────────
	Boosts = {}, -- [boostId] = expiry os.time()
	Items = {}, -- [itemId] = count
	ShieldUntil = 0,
	ShieldBankSecs = 0,

	-- ── Loop content ────────────────────────────────────────────────────────
	Daily = {
		LastClaimDay = 0,
		DayIndex = 0,
		Streak = 0,
		BestStreak = 0,
	},
	Quests = {
		Daily = {},
		Weekly = {},
		DailyResetDay = 0,
		WeeklyResetWeek = 0,
		RerollsUsed = 0,
	},
	Tutorial = {
		Step = 0,
		Completed = false,
		SkippedAt = nil,
	},

	-- ── Monetization ────────────────────────────────────────────────────────
	Gamepasses = {}, -- [passId] = true (cache, refreshed on join)
	ProcessedReceipts = {}, -- ring buffer of the last 100 PurchaseIds
	RobuxSpent = 0,

	-- ── Settings (docs/06 §8) ───────────────────────────────────────────────
	Settings = {
		MusicVolume = 60,
		SfxVolume = 80,
		RareAnnouncements = true,
		StealNotifications = true,
		TradeRequests = true,
		CameraShake = true,
		Particles = "High",
		LowGraphics = false,
		ShowNameTags = true,
		ScreenEffects = true,
		UiScale = 100,
		AutoCollect = false,
	},

	-- ── Statistics (leaderboards, quests and analytics all read these) ──────
	Stats = {
		PlaytimeSecs = 0,
		Joins = 0,
		EggsStolen = 0,
		EggsLost = 0,
		EggsHatched = 0,
		DinosHatched = 0,
		DinosPlaced = 0,
		DinosSold = 0,
		DinosFused = 0,
		DinosStolenFromOthers = 0,
		DinosLostToOthers = 0,
		RaidsSurvived = 0,
		ChasesEscaped = 0,
		ChasesCaught = 0,
		FossilsEarned = 0,
		FossilsSpent = 0,
		DnaEarned = 0,
		EventsJoined = 0,
		RarestRarity = "common",
		BestMutation = "none",
		PeakIncomePerSec = 0,
	},

	-- ── Bookkeeping ─────────────────────────────────────────────────────────
	LastSeen = 0, -- os.time() at last save; EconomyService reads for offline income
	BankedFossils = 0, -- uncollected park bank
	BankedAt = 0, -- os.time() the bank was last computed
	--[[
		The Fossils/sec the CURRENT banking interval accrues at, frozen when
		the interval started. Not a cache of the live rate: the bank pays for
		time already elapsed, so it has to be paid at the rate that was in
		force during it. See EconomyService.SettleBank.
	]]
	BankedRate = 0,
	FirstJoinAt = 0, -- 0 means "never joined" - how a new player is detected
	NewPlayerProtectionDone = false,
}

return ProfileTemplate
