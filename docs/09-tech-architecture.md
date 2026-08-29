# 09 — Technical Architecture

**Every name in this document is frozen.** Systems will be built against these
exact strings. Changes require a documented reason and a doc edit first.

Language: **Luau**, `--!strict` on all shared config and data modules,
`--!nonstrict` on gameplay services. Modern APIs only — `task.wait`,
`task.spawn`, `task.defer`; never `wait()`, `spawn()`, `delay()`, or
`Instance.new(class, parent)`.

---

## 1. Studio object tree

```
ReplicatedStorage
└── SAD_Shared                       (Folder)
    ├── Config                       (Folder)
    │   ├── GameConfig               (ModuleScript)  global constants, tuning
    │   ├── RarityConfig             (ModuleScript)  9 tiers, zone weight vectors, luck powers
    │   ├── DinoConfig               (ModuleScript)  60 species
    │   ├── MutationConfig           (ModuleScript)  19 entries + weather modifiers
    │   ├── ZoneConfig               (ModuleScript)  10 zones, nests, unlock gates
    │   ├── UpgradeConfig            (ModuleScript)  18 tracks
    │   ├── RebirthConfig            (ModuleScript)  costs, keeps, grants
    │   ├── WeatherConfig            (ModuleScript)  11 weathers
    │   ├── EventConfig              (ModuleScript)  12 server events
    │   ├── QuestConfig              (ModuleScript)  daily + weekly pools
    │   ├── DailyConfig              (ModuleScript)  7-day + streak table
    │   ├── ProductConfig            (ModuleScript)  gamepass + dev product ids
    │   └── IndexConfig              (ModuleScript)  milestone rewards
    ├── Modules                      (Folder)
    │   ├── Types                    (ModuleScript)  Luau type exports
    │   ├── Net                      (ModuleScript)  remote wrapper + rate limits
    │   ├── Signal                   (ModuleScript)  lightweight event class
    │   ├── RNG                      (ModuleScript)  weighted pick, luck maths
    │   ├── Format                   (ModuleScript)  number/time formatting
    │   ├── TableUtil                (ModuleScript)  deep copy/merge/reconcile
    │   └── Trove                    (ModuleScript)  cleanup helper
    └── SAD_Assets                   (Folder)
        ├── Dinos                    (Folder of Models)
        ├── Eggs                     (Folder of Models)
        ├── Effects                  (Folder)
        └── UI                       (Folder of ScreenGui templates)

ReplicatedStorage
└── SAD_Net                          (Folder)
    ├── Events                       (Folder of RemoteEvents)
    └── Functions                    (Folder of RemoteFunctions)

ServerScriptService
└── SAD_Server                       (Folder)
    ├── Bootstrap                    (Script)         the ONLY Script; requires services in order
    └── Services                     (Folder of ModuleScripts)
        ├── DataService              persistence, session locking
        ├── PlayerDataService        in-memory profile access + replication
        ├── SecurityService          rate limits, distance checks, movement sanity
        ├── EconomyService           Fossils/DNA mutations, income ticking, offline
        ├── ParkService              plot assign/release, placement grid, defences
        ├── NestService              nest spawn/respawn/claim
        ├── EggService               pickup, carry tokens, deposit
        ├── WildAIService            guardian spawn, chase ticking, de-aggro
        ├── IncubationService        timers, hatch resolution
        ├── DinosaurService          hatch rolls, ownership, place/store/sell/fuse
        ├── MutationService          mutation rolls, weather modifiers, reroll
        ├── StealService             player raiding state machine, shields, insurance
        ├── WeatherService           weather selection + broadcast
        ├── EventService             server event scheduler + participation
        ├── QuestService             daily/weekly progress
        ├── DailyService             7-day rewards, streaks
        ├── RebirthService           rebirth validation + grants
        ├── IndexService             discovery tracking + milestones
        ├── UpgradeService           upgrade purchase validation
        ├── PurchaseService          ProcessReceipt, gamepass ownership cache
        ├── LeaderboardService       OrderedDataStore aggregation
        ├── NotificationService      toast/banner/takeover dispatch
        ├── BroadcastService         MessagingService cross-server announcements
        └── AnalyticsService         AnalyticsService wrappers + custom logging

StarterPlayer
└── StarterPlayerScripts
    └── SAD_Client                   (Folder)
        ├── Bootstrap                (LocalScript)   the ONLY LocalScript
        └── Controllers              (Folder of ModuleScripts)
            ├── StateController      mirrors the replicated profile
            ├── UIController         mounts/unmounts screens
            ├── HUDController        top bar, bottom bar, action zone
            ├── InputController      keyboard/touch/gamepad mapping
            ├── CameraController     shake, event cuts, takeovers
            ├── NotificationController
            ├── SoundController
            ├── AnimationController
            ├── EggCarryController   carry visuals, chase HUD
            ├── ParkController       placement drag/drop, grid preview
            ├── ShopController
            ├── IndexController
            ├── QuestController
            ├── TeleportController
            ├── MinimapController
            ├── TutorialController
            └── SettingsController

StarterGui
└── SAD_UI                           (ScreenGui, ResetOnSpawn = false, IgnoreGuiInset = false)
    └── (all screens, initially Visible = false)

Workspace
├── SAD_World                        (Folder)
│   ├── Hub                          (Model)
│   ├── ParkPlots                    (Folder: Plot01 … Plot24, each a Model)
│   ├── Zones                        (Folder: Zone01 … Zone10, each a Model with NestAnchors)
│   └── Boundaries                   (Folder of invisible zone/park trigger parts)
└── SAD_Runtime                      (Folder, cleared on start)
    ├── Guardians                    (Folder)
    ├── CarriedEggs                  (Folder)
    ├── ParkDinos                    (Folder)
    └── Effects                      (Folder)

ServerStorage
└── SAD_Private                      (Folder)
    └── DinoModels                   (server-authoritative model source)
```

**Why one `Script` and one `LocalScript`.** Load order becomes explicit and
debuggable, circular requires surface immediately, and there is exactly one
place to add a service. Every other unit is a ModuleScript.

---

## 2. Bootstrap order

`ServerScriptService/SAD_Server/Bootstrap` requires services in dependency
order, calls `Service.Init()` on all of them, then `Service.Start()` on all of
them. Two phases means services can reference each other in `Start` without
caring about require order.

```
1  SecurityService      2  DataService         3  PlayerDataService
4  EconomyService       5  AnalyticsService    6  NotificationService
7  BroadcastService     8  ParkService         9  DinosaurService
10 MutationService      11 IncubationService   12 NestService
13 WildAIService        14 EggService          15 StealService
16 UpgradeService       17 RebirthService      18 IndexService
19 QuestService         20 DailyService        21 WeatherService
22 EventService         23 PurchaseService     24 LeaderboardService
```

Client `Bootstrap` mirrors this: `Init()` all controllers, then `Start()`.

---

## 3. Remote inventory (frozen)

All remotes are created **by the server at boot** into `SAD_Net`, never by the
client. Every one is routed through `Net`, which applies the rate limit, drops
over-limit calls silently, and logs offenders to `SecurityService`.

### 3.1 RemoteEvents — client → server

| Name | Rate (per s / burst) | Payload |
|---|---:|---|
| `RequestPickupEgg` | 2 / 3 | `nestId: string, eggSlot: number` |
| `RequestDropEgg` | 2 / 3 | `eggUid: string` |
| `RequestDepositEggs` | 1 / 2 | `()` |
| `RequestStartIncubation` | 3 / 5 | `eggUid: string, incubatorIndex: number` |
| `RequestClaimHatch` | 3 / 5 | `incubatorIndex: number` |
| `RequestPlaceDino` | 4 / 6 | `dinoUid: string, tileX: number, tileZ: number` |
| `RequestStoreDino` | 4 / 6 | `dinoUid: string` |
| `RequestVaultDino` | 2 / 3 | `dinoUid: string, pedestalIndex: number` |
| `RequestSellDinos` | 1 / 2 | `dinoUids: {string}` |
| `RequestSetDinoFlags` | 4 / 6 | `dinoUid: string, locked: boolean?, favorite: boolean?` |
| `RequestFuse` | 1 / 2 | `dinoUids: {string}` (must be exactly 5) |
| `RequestRerollMutation` | 1 / 2 | `dinoUid: string` |
| `RequestBuyUpgrade` | 4 / 8 | `trackId: string, levels: number` |
| `RequestBuyDefence` | 2 / 4 | `defenceId: string, levels: number` |
| `RequestUnlockZone` | 1 / 2 | `zoneId: string` |
| `RequestTeleport` | 1 / 2 | `zoneId: string \| "park" \| "hub"` |
| `RequestRebirth` | 0.5 / 1 | `()` |
| `RequestCollectIncome` | 2 / 3 | `()` |
| `RequestStealBegin` | 1 / 2 | `targetUserId: number, dinoUid: string` |
| `RequestStealCancel` | 2 / 3 | `()` |
| `RequestTagThief` | 3 / 5 | `thiefUserId: number` |
| `RequestClaimDaily` | 1 / 2 | `()` |
| `RequestClaimQuest` | 2 / 3 | `questId: string` |
| `RequestRerollQuest` | 1 / 2 | `questId: string` |
| `RequestUseItem` | 2 / 4 | `itemId: string` |
| `RequestSetSetting` | 5 / 10 | `key: string, value: any` |
| `RequestTutorialStep` | 3 / 5 | `step: number` |
| `RequestEventAction` | 3 / 6 | `eventId: string, action: string, arg: any?` |

### 3.2 RemoteEvents — server → client

| Name | Payload |
|---|---|
| `StateDelta` | `{path: {string}, value: any}` — patches the client's profile mirror |
| `StateFull` | full replicated profile snapshot (on join and on rebirth) |
| `Notify` | `{kind: "toast"\|"banner"\|"takeover"\|"alert", text, color, sfx, duration}` |
| `HatchResult` | `{dinoUid, speciesId, rarity, mutation, mutation2?, stars, odds}` |
| `WeatherChanged` | `{weatherId, endsAt}` |
| `EventState` | `{eventId, phase, endsAt, data}` |
| `StealAlert` | `{thiefUserId, thiefName, dinoUid, stage}` |
| `ChaseState` | `{active, guardianModelName, distance}` |
| `IncomePopup` | `{amount, worldPos}` |
| `TutorialState` | `{step, hintText}` |

### 3.3 RemoteFunctions (kept minimal — 4 total)

| Name | Returns |
|---|---|
| `GetProfileSnapshot` | Replicated slice of the caller's profile |
| `GetLeaderboards` | `{boardId -> {entries}}`, cached 60 s server-side |
| `GetParkSnapshot` | `(targetUserId) -> park layout + stealable dino list` |
| `GetIndexData` | Caller's index table |

RemoteFunctions yield and can be exploited to hang a thread, so they are used
only for read-only, idempotent queries. **Every mutating call is a RemoteEvent.**

---

## 4. Data replication strategy

The server holds the authoritative profile. A **subset** is replicated to the
owning client only:

```
Replicated:      Fossils, DNA, Rebirths, Upgrades, Zones, Dinos, Eggs,
                 Incubators, Index, Quests, Daily, Boosts, Settings, Stats
Server-only:     RNG seeds, receipt ids, session lock, anti-cheat counters,
                 shield internals, steal cooldown tables
Public (other
players):        park layout, placed dinosaurs, park value, name tag tier
```

On join: `StateFull`. Thereafter: `StateDelta` patches, coalesced and flushed on
a **5 Hz** timer so a burst of changes costs one packet. Currency changes flush
immediately (they need to feel instant).

Public park data is exposed via `GetParkSnapshot` and via `Attributes` on the
plot model, not by replicating other players' full profiles.

---

## 5. Persistence

`DataService` wraps **ProfileStore** (the open-source successor to
ProfileService by loleris). To be explicit: **ProfileStore is a community
module, not a Roblox API** — it must be added to the place manually, and I'll
flag its exact version when we build Step 2. It is used because it solves
session locking, which is the single largest cause of duplication exploits and
data loss in games of this genre.

If we choose not to take a third-party dependency, the fallback is a custom
wrapper over `DataStoreService:GetDataStore()` with:
- `UpdateAsync` for every write (never `SetAsync`),
- a session lock field (`{jobId, timestamp}`) refreshed every 60 s and stolen
  only after a 180 s stale timeout,
- exponential-backoff retries with a `DataStoreSetOptions` metadata stamp.

I'll build against ProfileStore by default and note the swap point.

**Save policy**
- Autosave every **180 s** (jittered per player to spread DataStore budget).
- Save on `PlayerRemoving` and on `game:BindToClose` (with a `task.wait` fence).
- Save immediately after: rebirth, a Robux purchase, any Legendary+ hatch, a
  completed steal.
- On save failure: retry 5× with backoff; on total failure, keep the session
  lock, warn the player with a banner, and block further Robux purchases.
- `game:BindToClose` waits for all outstanding saves (max 25 s).

**Schema versioning**: every profile carries `SchemaVersion`. `DataService`
runs an ordered migration chain `v1→v2→v3…`. Migrations are pure functions,
never destructive, and are unit-tested against fixtures. See
[10-data-schema.md](10-data-schema.md).

---

## 6. Performance architecture

**Budget: 60 fps on a 2019 mid-range Android with 30 players and 20 active
guardians.**

| Concern | Approach |
|---|---|
| Dinosaur count | Up to 30 placed dinos × 24 parks = 720. Park dinos are **not** Humanoids — they are Models with an animated `AnimationController` and a simple 3-state wander driven by a **single shared 2 Hz loop** that batches all parks |
| Distant parks | `StreamingEnabled` + per-park `Model.LevelOfDetail`; beyond 250 studs a park renders a single impostor billboard of its skyline |
| Guardian AI | Dormant until aggro. 6 Hz tick. Path recalc ≤ every 1.5 s. Hard cap 20 active; overflow becomes a client-only Ghost Chase |
| Particles | Global `ParticleBudget`; rarity VFX auto-downgrade beyond 120 studs and are disabled entirely in Low Graphics Mode |
| Remotes | 5 Hz coalesced state deltas; no per-frame remotes anywhere. Income floaters are generated client-side from a replicated rate, not sent per tick |
| Income ticking | The server does **not** tick per dinosaur. It stores `bankedAt` + `ratePerSecond` and computes lazily on read. O(1) per player, not O(dinos) |
| Nest queries | `CollectionService:GetTagged("SAD_Nest")` once at boot into a spatial bucket grid; proximity checks are bucket lookups, not distance loops over all nests |
| Physics | Guardians and carried eggs are network-owned by the **server** (`BasePart:SetNetworkOwner(nil)`) — required for anti-cheat and it keeps physics off client CPUs |
| Parallel Luau | Guardian steering runs inside `Actor` instances with `task.desynchronize()` for the vector maths, re-synchronising only to apply `MoveTo` |
| Memory | Object pooling for eggs, income floaters, VFX and guardian models via a shared `Pool` in `Trove` |

**Explicitly avoided:** per-frame `Heartbeat` loops over all players; `while
true do wait() end`; `workspace:GetChildren()` scans in hot paths; `FindFirstChild`
in loops (cached at spawn); creating a `Tween` per income popup (pooled).

---

## 7. Security architecture

**Principle: the client is a renderer and an input device. Nothing else.**

### 7.1 What the client may send

Only **intent**: "I want to pick up egg 2 at nest `plains_04`." Never a value,
never a result, never a currency amount, never a rarity, never a position.

### 7.2 Validation layers (every mutating remote passes all five)

1. **Rate limit** — token bucket per player per remote (§3.1). Over-limit calls
   are dropped and counted; 20 violations in 60 s → `SecurityService` flags the
   player, logs `ExploitFlag`, and throttles them to 0.2×.
2. **Type/shape check** — every payload is validated against an explicit
   schema. Wrong type = drop + flag. No `pcall`-and-hope.
3. **Ownership check** — does this player own this `dinoUid` / `eggUid` /
   plot / incubator? Uids are server-generated GUIDs, never client-chosen.
4. **State-machine check** — is this transition legal *right now*? (You cannot
   deposit an egg you aren't carrying; you cannot steal while already carrying;
   you cannot rebirth mid-carry.)
5. **Spatial check** — `(character.HumanoidRootPart.Position - target.Position)
   .Magnitude <= allowedRange` computed **server-side** at the instant of the
   grant, plus a movement-plausibility check (below).

### 7.3 Movement plausibility

`SecurityService` samples every character's position at **4 Hz**. If a sample
implies a speed greater than `maxAllowedSpeed × 1.6` and the player is not in a
known teleport/launcher/event state, it:
- invalidates any active carry token,
- logs `SuspiciousMovement` with the delta,
- and after 5 flags in 30 s, teleports the character back to the last valid
  position (a soft correction, not a kick — false positives happen on laggy
  mobile connections and kicking children over network jitter is unacceptable).

Teleports, launch pads and event portals set an `ExemptUntil` timestamp so they
never trip the detector.

### 7.4 Duplication prevention

Every transferable object exists in exactly one place at a time, tracked by a
server-side **token**:

```
CarryToken = { kind = "egg"|"dino", uid, ownerUserId, originKind, originRef,
               grantedAt, expiresAt }
```
- Creating a token **removes** the object from its origin in the same
  synchronous block.
- A player may hold at most `eggCapacity` egg tokens and exactly **1** dino
  token.
- On `PlayerRemoving`, every token is resolved **before** the profile releases:
  wild egg → back to nest; stolen dino → back to its owner's park (after a 30 s
  grace so a rejoining player isn't punished for a crash).
- Deposits are single atomic server functions: `removeToken()` → `appendToProfile()`
  → `markDirty()`. There is no client round-trip in the middle to exploit.

### 7.5 Randomness

All rolls use a **server-side** `Random.new()` instance created per-service at
boot from `os.clock()` entropy. Rarity rolls at pickup, species and mutation
rolls at hatch. The client is only ever *told* results. Roll inputs (luck,
weather, zone) are read from server state, never from the payload.

### 7.6 Purchases

`MarketplaceService.ProcessReceipt` is implemented once, in `PurchaseService`,
and is **idempotent**: each `PurchaseId` is recorded in the profile's
`ProcessedReceipts` ring buffer (last 100) *before* granting, and the grant only
returns `Enum.ProductPurchaseDecision.PurchaseGranted` after the profile has
been marked dirty. If the profile isn't loaded, it returns `NotProcessedYet` so
Roblox retries. Gamepass ownership is checked with
`MarketplaceService:UserOwnsGamePassAsync` on join (cached, with a
`PromptGamePassPurchaseFinished` listener to update mid-session).

### 7.7 Cross-server messaging

`BroadcastService` uses `MessagingService` with:
- a per-server send budget (max 6 messages/min; excess is dropped, not queued
  forever),
- payloads capped at 800 bytes,
- an allow-list of message kinds, and strict shape validation **on receive** —
  an inbound message is treated as untrusted input exactly like a client packet.

### 7.8 Text safety

All player-visible player-authored text (only park names in V1.4+) goes through
`TextService:FilterStringAsync` with the correct context, per Roblox policy.
Announcement templates use `Players:GetNameFromUserIdAsync`-sourced usernames,
which are already moderated, so no raw user strings enter announcements in V1.

---

## 8. Testing approach

| Layer | Method |
|---|---|
| Config integrity | A `ConfigValidator` module run at boot in Studio: asserts weight tables sum to their totals, every `DinoConfig.Zones` id exists, every asset name resolves |
| Pure logic | `RNG`, `Format`, economy formulas and migrations are pure functions with a `TestEZ`-style spec run in Studio via a `RunTests` script |
| Integration | Studio `Play Solo` checklists per build step (each step in [13-build-order.md](13-build-order.md) ships with its own test list) |
| Multiplayer | Studio "Start Server + 2 Players" for every steal/raid change — never test stealing in solo |
| Exploit sim | A `DebugExploitClient` LocalScript (Studio-only, stripped from production) that fires every remote with malformed payloads, out-of-range positions, and spam bursts. Every build step must survive it |
| Load | 30-bot soak via `Players:CreateLocalPlayer` stand-ins is not possible; instead a `SimulatedLoad` server module spawns 20 guardians + 700 park dinos and reports frame time |
