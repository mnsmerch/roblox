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
GameConfig.MaxPlayers = 24
GameConfig.ParkPlotCount = 24

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

-- ── Carry / theft grace ─────────────────────────────────────────────────────
GameConfig.CarryTokenGraceSecs = 30 -- disconnect-while-carrying resolution delay
GameConfig.LooseEggLifetimeSecs = 10
GameConfig.ChaseTimeoutSecs = 45

return GameConfig
