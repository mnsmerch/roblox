# 10 — Player Data Schema

`SchemaVersion = 1`. Every key below is frozen. New keys may be **added** with a
migration; existing keys are never renamed or repurposed.

## 1. Profile shape

```lua
{
    SchemaVersion = 1,

    -- ── Currency ────────────────────────────────────────────────
    Fossils        = 0,        -- number (double), clamped [0, 1e30]
    DNA            = 0,

    -- ── Progression ────────────────────────────────────────────
    Rebirths       = 0,
    ZonesUnlocked  = { plains = true },        -- [zoneId] = true
    Upgrades       = {},                        -- [trackId] = level (absent = 0)
    Defences       = {},                        -- [defenceId] = level
    LuckNodes      = 0,                         -- DNA-bought permanent luck

    -- ── Collection ─────────────────────────────────────────────
    Dinos = {                                   -- [dinoUid] = entry
        ["a1b2c3d4"] = {
            SpeciesId  = "trex",
            Rarity     = "legendary",
            Mutation   = "golden",              -- or nil
            Mutation2  = nil,                   -- Prime only
            Stars      = 1,                     -- 1-5
            Placed     = true,
            TileX      = 3, TileZ = 5,          -- nil when stored
            Vault      = nil,                   -- pedestal index when vaulted
            Locked     = true,
            Favorite   = false,
            HatchedAt  = 1756512000,            -- os.time()
            Rerolls    = 0,
            Origin     = "plains",              -- zone it came from
        },
    },
    Eggs = {                                    -- [eggUid] = entry
        ["e5f6a7b8"] = {
            Rarity      = "epic",
            Origin      = "canyon",
            AcquiredAt  = 1756512000,
        },
    },
    Incubators = {                              -- array, 1..IncubatorCount
        [1] = { EggUid = "e5f6a7b8", StartedAt = 1756512000, HatchAt = 1756512480 },
        [2] = nil,
    },

    -- ── Index ──────────────────────────────────────────────────
    Index = {                                   -- [speciesId] = entry
        ["trex"] = {
            Count         = 4,
            BestStar      = 2,
            Mutations     = { golden = true, crystal = true },
            FirstAt       = 1756500000,
        },
    },
    IndexMilestones = {},                       -- [milestoneId] = true

    -- ── Boosts & items ─────────────────────────────────────────
    Boosts = {                                  -- [boostId] = expiry os.time()
        luck2x = 1756512900,
    },
    Items = {},                                 -- [itemId] = count
    ShieldUntil    = 0,                         -- os.time()
    ShieldBankSecs = 0,                         -- unspent free shield seconds

    -- ── Loop content ───────────────────────────────────────────
    Daily = {
        LastClaimDay  = 0,                      -- days since epoch
        DayIndex      = 0,                      -- 0-6
        Streak        = 0,
        BestStreak    = 0,
    },
    Quests = {
        Daily  = { [questId] = { Progress = 0, Claimed = false } },
        Weekly = { [questId] = { Progress = 0, Claimed = false } },
        DailyResetDay  = 0,
        WeeklyResetWeek = 0,
        RerollsUsed    = 0,
    },
    Tutorial = { Step = 0, Completed = false, SkippedAt = nil },

    -- ── Monetization ───────────────────────────────────────────
    Gamepasses        = {},                     -- [passId] = true (cache)
    ProcessedReceipts = {},                     -- ring buffer of last 100 PurchaseIds
    RobuxSpent        = 0,                      -- analytics only

    -- ── Settings ───────────────────────────────────────────────
    Settings = {
        MusicVolume = 60, SfxVolume = 80,
        RareAnnouncements = true, StealNotifications = true,
        TradeRequests = true, CameraShake = true,
        Particles = "High", LowGraphics = false,
        ShowNameTags = true, ScreenEffects = true, UiScale = 100,
        AutoCollect = false,
    },

    -- ── Statistics (leaderboards + analytics) ──────────────────
    Stats = {
        PlaytimeSecs = 0, Joins = 0,
        EggsStolen = 0, EggsLost = 0, EggsHatched = 0,
        DinosHatched = 0, DinosPlaced = 0, DinosSold = 0, DinosFused = 0,
        DinosStolenFromOthers = 0, DinosLostToOthers = 0,
        RaidsSurvived = 0, ChasesEscaped = 0, ChasesCaught = 0,
        FossilsEarned = 0, FossilsSpent = 0, DnaEarned = 0,
        EventsJoined = 0, RarestRarity = "common",
        BestMutation = "none", PeakIncomePerSec = 0,
    },

    -- ── Bookkeeping ────────────────────────────────────────────
    LastSeen        = 0,                        -- os.time() at last save/leave
    BankedFossils   = 0,                        -- uncollected park bank
    BankedAt        = 0,                        -- os.time() the bank was last computed
    FirstJoinAt     = 0,
    NewPlayerProtectionDone = false,
}
```

## 2. Rules

**Uids.** `dinoUid` and `eggUid` are 8-character server-generated hex strings
from `HttpService:GenerateGUID(false)` truncated and collision-checked against
the player's own tables. The client never supplies or invents one.

**Income is never stored.** `BankedFossils` + `BankedAt` + a derived
`ratePerSecond` are enough to compute the bank lazily. Storing per-second income
in the profile would make it a cheat target and would desync after every
upgrade.

**Numbers, not strings.** All currency is a Lua double. Doubles are exact to
2⁵³ ≈ 9.007 × 10¹⁵. Because late-game income exceeds this, `EconomyService`
clamps at `1e30` and displays saturated values as `MAX`; the design intent is
that the rebirth curve keeps players below 10²⁰ in practice, and the clamp is a
safety net, not a feature.

**Table growth.** `Dinos` is capped by `Dino Storage` (max 200) + placed slots
(max 30) + vault (5) = **235 entries max**. `Index` is capped at 60.
`ProcessedReceipts` is a 100-entry ring. This bounds a profile at roughly
40–60 KB, comfortably inside the 4 MB DataStore value limit with room for
several future versions.

## 3. Migrations

`DataService.Migrations` is an ordered array of pure functions.

```lua
Migrations[1] = function(profile)  -- v1 -> v2, example shape
    profile.LuckNodes = profile.LuckNodes or 0
    profile.SchemaVersion = 2
    return profile
end
```

Rules:
- Migrations run in order from the profile's version to `CURRENT_VERSION`.
- They **only add or transform**; they never delete a player's dinosaurs.
- Every migration ships with fixture tests: an old-shape profile in, an
  asserted new shape out.
- If a profile's version is *higher* than the server's (a rollback), the server
  refuses to load it into gameplay, loads it read-only, and shows the player a
  maintenance banner rather than overwriting newer data with older code.

## 4. DataStore layout

| Store | Type | Key | Contents |
|---|---|---|---|
| `SAD_Profiles_v1` | DataStore (via ProfileStore) | `Player_<userId>` | the profile above |
| `SAD_LB_Fossils` | OrderedDataStore | `<userId>` | current Fossils |
| `SAD_LB_Income` | OrderedDataStore | `<userId>` | peak income/sec |
| `SAD_LB_Rebirths` | OrderedDataStore | `<userId>` | rebirth count |
| `SAD_LB_Index` | OrderedDataStore | `<userId>` | species discovered |
| `SAD_LB_DinosStolen` | OrderedDataStore | `<userId>` | steal count |
| `SAD_LB_EggsStolen` | OrderedDataStore | `<userId>` | egg count |
| `SAD_LB_ParkValue` | OrderedDataStore | `<userId>` | total park value |
| `SAD_LB_Rarest` | OrderedDataStore | `<userId>` | rarity tier index × 1e6 + income |
| `SAD_Global` | MemoryStore SortedMap | various | cross-server event coordination, steal cooldowns |

Leaderboards are written at most once every 5 minutes per player and only when
the value actually changed, to stay well inside `OrderedDataStore` budgets.
`LeaderboardService` reads the top 100 of each board every 60 s and caches.

**Measured (Step 22).** A player earning every second for an hour costs **15**
requests, against 14,400 for a naive write-every-change — 960× fewer. The first
throttled tick writes all four boards; the eleven after it write only the one
value that moved, which is the changed check rather than the throttle doing the
work. An idle player costs four requests in their first tick and nothing ever
again.

**60 s is a floor, not a fixed period.** Reads are per-*server* while the read
budget (`GetSortedAsync`: 5 + 2 × players per minute) scales with players, so
the tightest case is a nearly empty server, not a full one. V1's four boards
cost 4/min against a budget of 7 at one player and fit. The eight boards
docs/02 §1.1 describes would cost 8/min and would **not** — so
`LeaderboardConfig.ReadIntervalFor` derives the period from the board count and
stretches to ~92 s once all eight ship. V1 is unaffected; the build-out slows
itself instead of silently failing.

**The value ceiling is 2^53, not the 9e18 the build order names.** 9e18 is under
the int64 limit but far above the point where a Lua double stops representing
consecutive integers, so a value near it would already have been rounded before
the store saw it. `Economy.MaxFossils` uses the same ceiling — see docs/05 §6 on
what that means for deep rebirths.

**There is no rank query.** `OrderedDataStore` returns pages and has no API for
"what rank is this key"; counting everyone above a player means paging the whole
store. A player in the cached top 100 is shown their real rank. A player outside
it is shown their **value** and the words *outside the top 100*, never an
estimated number.
