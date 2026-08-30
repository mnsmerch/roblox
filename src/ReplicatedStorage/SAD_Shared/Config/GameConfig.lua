--!strict
--[[
	GameConfig
	ReplicatedStorage/SAD_Shared/Config/GameConfig  (ModuleScript)

	Genuinely GLOBAL constants only. Anything that belongs to one system lives
	in that system's own config module (RarityConfig, DinoConfig, ZoneConfig...).

	If you find yourself adding a dinosaur, a zone, a mutation or an upgrade
	here, it belongs somewhere else. See docs/11-content-config.md.

	Depends on: nothing. This module must stay dependency-free - Log requires it.
]]

local GameConfig = {}

-- ── Build identity ──────────────────────────────────────────────────────────
GameConfig.GameName = "Steal a Dinosaur"
GameConfig.Version = "0.1.0"

--- Bumped whenever the saved profile shape changes. See docs/10-data-schema.md.
GameConfig.SchemaVersion = 1

-- ── Diagnostics ─────────────────────────────────────────────────────────────
--- "debug" | "info" | "warn" | "error" | "none"
GameConfig.LogLevel = "debug"

--- When true, a service that fails to require/Init/Start aborts the boot loudly
--- instead of being skipped. Keep true in Studio; consider false in production
--- so one bad service cannot take the whole experience offline.
GameConfig.StrictBoot = true

--- Master switch for Studio-only debug affordances (command-bar helpers, the
--- exploit simulator in Step 24). Never ship this true.
GameConfig.DebugTools = true

-- ── World ───────────────────────────────────────────────────────────────────
GameConfig.MaxPlayers = 6
GameConfig.ParkPlotCount = 6

-- ── Server tick rates (Hz) ──────────────────────────────────────────────────
GameConfig.StateFlushHz = 5 -- coalesced StateDelta flush
GameConfig.GuardianTickHz = 6 -- chase AI steering
GameConfig.ParkDinoTickHz = 2 -- shared park wander loop
GameConfig.SecuritySampleHz = 4 -- movement plausibility sampling

-- ── Persistence ─────────────────────────────────────────────────────────────
GameConfig.DataStoreName = "SAD_Profiles_v1"
GameConfig.AutosaveIntervalSecs = 180
GameConfig.AutosaveJitterSecs = 30 -- spreads DataStore load across players
GameConfig.BindToCloseTimeoutSecs = 25

--- How long without a successful save before DataService raises SaveStalled.
--- ProfileStore retries individual writes internally, so a single failure is
--- invisible to us; a long silence is the signal that actually matters.
GameConfig.SaveStalledWarningSecs = 600

--- Studio-only escape hatch: use ProfileStore's in-memory mock store so the
--- game runs without API Services enabled. Mock data is DISCARDED on stop.
--- Must be false for anything you intend to keep.
GameConfig.UseMockDataInStudio = false

-- ── Performance caps ────────────────────────────────────────────────────────
GameConfig.MaxActiveGuardians = 20 -- beyond this, steals get a client-only Ghost Chase
GameConfig.MaxNotificationQueue = 3
GameConfig.VfxCullDistance = 120

-- ── Anti-exploit ────────────────────────────────────────────────────────────
GameConfig.InteractRangeStuds = 18 -- server-side distance check for any interaction
GameConfig.SpeedToleranceMultiplier = 1.6 -- movement plausibility slack
GameConfig.ExploitFlagsBeforeThrottle = 20
GameConfig.ExploitFlagWindowSecs = 60

--[[
	Settings a client is allowed to write, with the rules the server enforces.

	Settings are the ONLY profile field a client may change directly, which
	makes this the smallest complete example of the input contract: a known key,
	a matching type, numbers clamped rather than rejected, strings restricted to
	an allow-list. Anything else is dropped without telling the client which
	guard tripped.

	Mirrors docs/06-progression.md §8.
]]
GameConfig.SettingsSchema = {
	MusicVolume = { Type = "number", Min = 0, Max = 100 },
	SfxVolume = { Type = "number", Min = 0, Max = 100 },
	RareAnnouncements = { Type = "boolean" },
	StealNotifications = { Type = "boolean" },
	TradeRequests = { Type = "boolean" },
	CameraShake = { Type = "boolean" },
	Particles = { Type = "string", OneOf = { "High", "Medium", "Off" } },
	LowGraphics = { Type = "boolean" },
	ShowNameTags = { Type = "boolean" },
	ScreenEffects = { Type = "boolean" },
	UiScale = { Type = "number", Min = 80, Max = 130 },
	AutoCollect = { Type = "boolean" },
	--[[
		docs/07 §1 rule 7: "The first time a player opens the shop, a plain
		panel says: You never need to spend Robux to get any dinosaur in this
		game." A per-session flag would re-nag; a profile field states it once
		and remembers. It lives in Settings because there is already a
		validated remote for writing one, and because a player who wants to
		read it again can turn it back on.
	]]
	SeenStoreNotice = { Type = "boolean" },
}

-- ── Movement ────────────────────────────────────────────────────────────────

GameConfig.BaseWalkSpeed = 20

--- Carrying can never make a player slower than this fraction of base speed.
--- A Titan egg at 45% plus a second egg must still leave them able to run.
GameConfig.MaxCarryPenalty = 0.85

--- Each egg past the first contributes only this share of its own penalty, so
--- multi-carry is a real risk/reward call rather than a free upgrade.
GameConfig.MultiCarryEffectiveness = 0.40

--- Luck granted per DNA-bought Luck Node (docs/10 §1). Named here rather than
--- inline in one service, because Stats folds it and the shop previews it.
GameConfig.LuckPerNode = 0.005

-- ── Raiding (docs/03 §4.3) ──────────────────────────────────────────────────

--- Hold time to lift a dinosaur: Base + SecurityLevel x PerSecurity.
GameConfig.RaidHoldBase = 3.0
GameConfig.RaidHoldPerSecurity = 1.2

--- Raiding is heavier than egg-carrying: the dinosaur's CarryPenalty plus this.
GameConfig.RaidCarryExtra = 0.10

GameConfig.RaidSameVictimCooldown = 600 -- 10 min
GameConfig.RaidGlobalCooldown = 90
GameConfig.RaidPowerFloor = 0.25 -- cannot rob a park worth under 25% of yours
GameConfig.RaidInsuranceShare = 0.25 -- of the stolen dinosaur's sell value
GameConfig.RevengeDuration = 1800 -- 30 min
GameConfig.RevengeHoldMultiplier = 0.5

--- A tagged thief drops the dinosaur, which flies home after this long.
GameConfig.RaidTagReturnSecs = 3

--- Grace before a disconnected thief's carry resolves back to its owner.
GameConfig.RaidDisconnectGraceSecs = 30

--- Guard Tower: auto-tags a carrying thief inside this radius (docs/03 §5).
GameConfig.GuardTowerRange = 40

-- ── Shields (docs/03 §4.3) ──────────────────────────────────────────────────

GameConfig.SessionShieldSecs = 15 * 60
GameConfig.MercyShieldSecs = 10 * 60
GameConfig.MercyWindowSecs = 15 * 60
GameConfig.MercyRobberies = 3 -- robbed this many inside the window
GameConfig.ShieldStackCapSecs = 2 * 60 * 60 -- nobody buys permanent immunity
GameConfig.NewPlayerProtectionSecs = 60 * 60

--[[
	Cap on remembered raid records per profile.

	StealCooldowns and RevengeMarks are keyed by userId, so on a busy account
	they grow without a bound of their own. Expired entries are pruned on every
	write; this is the backstop for the case where they are all still live.
]]
GameConfig.StealRecordCap = 50

--[[
	Movement correction. Sustained implausible movement snaps the character
	back to its last valid position - never a kick. False positives happen on
	laggy mobile connections, and disconnecting children over network jitter is
	not an acceptable trade for catching a speed exploit.
]]
GameConfig.MovementCorrectionEnabled = true
GameConfig.MovementFlagsBeforeCorrection = 5
GameConfig.MovementFlagWindowSecs = 30

-- ── Storage ─────────────────────────────────────────────────────────────────

--[[
	Cap on undeposited eggs held in the profile.

	docs/10 bounds Dinos at 235 entries but never bounded Eggs, which would let
	a hoarder grow their profile without limit until a DataStore write starts
	failing - the worst possible failure mode, arriving late and looking like
	nothing. 50 is far more than the eight incubators can consume, so it never
	binds in normal play; it exists so the profile has a ceiling at all.

	Full storage does NOT destroy an egg. The deposit is refused, the player
	keeps carrying it, and they are told why (docs/06 §1: a visible, fixable
	blockage instead of silent loss).
]]
GameConfig.EggStorageCap = 50

-- ── Carry / theft grace ─────────────────────────────────────────────────────
GameConfig.CarryTokenGraceSecs = 30 -- disconnect-while-carrying resolution delay
GameConfig.LooseEggLifetimeSecs = 10
GameConfig.ChaseTimeoutSecs = 45

return GameConfig
