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
    │   ├── RebirthConfig            (ModuleScript)  costs, the three classification
    │   │                                            lists, grants, the shared preview
    │   ├── WeatherConfig            (ModuleScript)  11 weathers (4 in V1); mutation
    │   │                                            weights stay in MutationConfig
    │   ├── EventConfig              (ModuleScript)  12 server events
    │   ├── QuestConfig              (ModuleScript)  daily + weekly pools
    │   ├── DailyConfig              (ModuleScript)  7-day + streak table
    │   ├── ProductConfig            (ModuleScript)  gamepass + dev product ids
    │   ├── IndexConfig              (ModuleScript)  milestone rewards
    │   ├── ParkConfig               (ModuleScript)  plot geometry + grid maths
    │   ├── ChaseConfig              (ModuleScript)  guardian archetype behaviour
    │   ├── NotificationConfig       (ModuleScript)  severities, queueing, publish budget
    │   └── ConfigValidator          (ModuleScript)  boot-time content checks
    ├── Modules                      (Folder)
    │   ├── Types                    (ModuleScript)  Luau type exports
    │   ├── Log                      (ModuleScript)  scoped, level-filtered logging
    │   ├── Net                      (ModuleScript)  remote wrapper + rate limits
    │   ├── Patch                    (ModuleScript)  structural diff + apply (shared)
    │   ├── Economy                  (ModuleScript)  income/sell/bank maths (shared)
    │   ├── Time                     (ModuleScript)  UTC day/week indices (shared)
    │   ├── Stats                    (ModuleScript)  derived player stats (shared)
    │   ├── AssetBuilder             (ModuleScript)  placeholder model generation
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
        ├── EggService               pickup, rarity roll, carry tokens, loose eggs
        ├── EconomyService           Fossils/DNA, lazy banking, offline earnings
        ├── ParkService              plot assign/release, placement grid, defences
        │   └── PlotBuilder          procedural plot geometry
        ├── NestService              world blockout, nest spawn/respawn/claim
        │   ├── WorldBuilder         procedural hub + zone geometry
        │   ├── NestBuilder          nest bowl, eggs, sign
        │   └── ZoneService          unlocking, shrines, teleports, trespass
        ├── WildAIService            guardian spawn, chase ticking, de-aggro
        ├── IncubationService        timers, hatch resolution
        ├── DinosaurService          hatch rolls, ownership, place/store/sell/fuse
        ├── MutationService          mutation rolls, weather modifiers, reroll
        ├── StealService             raid state machine, tagging, shields, insurance
        ├── WeatherService           selection, effects; visuals are the client's
        ├── EventService             scheduler, participation, rewards
        │   └── Handlers             one ModuleScript per event
        ├── QuestService             daily/weekly rolls, progress, claims
        │   └── RewardGrant          the one place a reward is paid out
        ├── DailyService             the 7-day chest and the streak
        ├── RebirthService           validation, the one-write reset, grants
        ├── IndexService             discovery, completion %, milestones
        ├── UpgradeService           upgrade/defence pricing, Buy and Buy Max
        ├── PurchaseService          ProcessReceipt, ownership cache, server boosts
        ├── LeaderboardService       the ONLY file that touches OrderedDataStore
        ├── TutorialService          owns the step number; checks every advance
        ├── AnalyticsService         the ONLY file that touches Roblox's AnalyticsService.
        │                            Subscribes to 40+ existing Signals; nothing calls it
        ├── NotificationService      the one place a notification is created
        └── BroadcastService         MessagingService: the only file that knows it exists

StarterPlayer
└── StarterPlayerScripts
    └── SAD_Client                   (Folder)
        ├── Bootstrap                (LocalScript)   the ONLY LocalScript
        ├── UI                       (Folder)
        │   ├── Theme                (ModuleScript)  design tokens + layout rules
        │   ├── Create               (ModuleScript)  declarative Instance builder
        │   └── Widgets              (ModuleScript)  reusable UI pieces
        └── Controllers              (Folder of ModuleScripts)
            ├── StateController      mirrors the replicated profile
            ├── UIController         mounts/unmounts screens
            ├── HUDController        top bar, bottom bar, action zone
            ├── InputController      keyboard/touch/gamepad mapping
            ├── CameraController     shake, event cuts, takeovers
            ├── NotificationController  the queue and the four severities
            ├── SoundController      slots by name; no asset ids invented
            ├── AnimationController
            ├── EggCarryController   carry visuals, chase HUD
            ├── ParkController       income floaters, park-side visuals
            ├── ShopController       the three upgrade boards
            ├── IndexController      the book, one page per zone
            ├── QuestController      the quest board and the daily chest
            ├── TeleportController   the zone wheel and PARK teleport
            ├── MinimapController
            ├── WeatherController    Lighting, locally, so it always reverts
            ├── RebirthController    the keep/lose/gain confirm screen
            ├── PurchaseController   the store, the honesty panel, Thanks
            ├── LeaderboardController  the boards screen and the Colosseum
            ├── TutorialController   Rok, one arrow, one objective line, skip
            └── SettingsController   generated from GameConfig.SettingsSchema

(StarterGui is empty. SAD_UI is CREATED AT RUNTIME by UIController into
 PlayerGui - the interface is built in code so it stays in version control and
 diffable, and a PlayerGui-parented ScreenGui survives respawn inherently, with
 no ResetOnSpawn property left to get wrong.)

PlayerGui                            (at runtime)
└── SAD_UI                           (ScreenGui)
    └── Root                         (Frame, holds the single UIScale)
        ├── HudLayer                 (ZIndex 10)
        ├── ScreenLayer              (ZIndex 20)
        ├── PromptLayer              (ZIndex 30)
        ├── NotificationLayer        (ZIndex 40)
        └── TakeoverLayer            (ZIndex 50)

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
order, calls `Service.Init(app)` on all of them, then `Service.Start(app)` on
all of them. Two phases means services can reference each other in `Start`
without caring about require order.

**The service contract:**

```lua
local MyService = {}
function MyService.Init(app) end   -- own state only; do not call other services
function MyService.Start(app) end  -- everything is loaded; cross-calls are safe
return MyService
```

`app` is **injected**, not required. `StealService` needs `ParkService` and
`ParkService` needs `StealService`; a direct `require` in both directions
deadlocks. `app` exposes `Get(name)`, `Log`, `Net`, `Config`, `IsServer` (and
`Player` on the client). Controllers follow the identical contract.

Services listed in `SERVICE_ORDER` that do not yet exist on disk are **skipped**,
not errors — that is what lets each build step add one service without editing
Bootstrap.

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
| `RequestTutorialStep` | 3 / 5 | `step: number` — an *ask*, not a command; the server checks it against real state. **Step 0 is the skip signal**, overloaded onto this remote rather than adding a second one that carries no argument |
| `RequestEventAction` | 3 / 6 | `eventId: string, action: string, arg: any?` |
| `RequestThanks` | 2 / 3 | `buyerUserId: number` — docs/07 §4's Thanks button |

### 3.2 RemoteEvents — server → client

| Name | Payload |
|---|---|
| `StateDelta` | **an array** of `{Path: {key}, Value: any}` / `{Path: {key}, Remove: true}` patches. Batched — one packet per flush, not one per field. Path keys keep their native type |
| `StateFull` | full replicated profile snapshot (on join and on rebirth) |
| `Notify` | `{kind: "toast"\|"banner"\|"takeover"\|"alert", text, color, sfx, duration}` |
| `HatchResult` | `{dinoUid, speciesId, rarity, mutation, mutation2?, stars, odds}` |
| `WeatherChanged` | `{weatherId, endsAt}` |
| `EventState` | `{eventId, phase, endsAt, data}` |
| `StealAlert` | `{thiefUserId, thiefName, dinoUid, stage}` |
| `ServerBoost` | `{buyerUserId, buyerName, product, windowSecs}` — a server-wide purchase, and the window in which Thanks may be sent |
| `ChaseState` | `{active, guardianModelName, distance}` |
| `IncomePopup` | `{amount, worldPos}` |
| `TutorialState` | `{Step, Completed, Skipped}` — pushed on every change and on profile load, which is how docs/13's resume test works |

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
immediately (they need to feel instant), with a 50 ms floor so a burst of income
collection cannot become a remote call per frame.

**The slice is an allowlist.** Fields are withheld by default and must be named
in `Replication.REPLICATED` to be sent. A denylist leaks every field somebody
adds later and forgets about, silently. `Replication.Init` asserts that every
key in `ProfileTemplate` appears in exactly one of `REPLICATED` or `WITHHELD`,
so adding a profile field **fails the boot** until someone decides about it.
Currently withheld: `ProcessedReceipts`, `RobuxSpent`, `LastSeen`,
`FirstJoinAt`, `SchemaVersion`.

**Diffing is shared code.** `SAD_Shared/Modules/Patch` holds both `Diff` and
`Apply`, required by the server that produces deltas and the client that
consumes them. Writing them separately would let the two sides disagree about
what a patch means — a numeric key stringified on one side, a removal
mishandled on the other — and desync a player's inventory in a way that reads
as a gameplay bug. One implementation, one set of tests, and the round-trip
property (`apply(diff(a,b), a) == b`) asserted directly.

Diff depth is **3**, which gives per-field granularity for every shape in the
schema (`Dinos → uid → field`, `Quests → Daily → questId → field`) and ships
anything deeper wholesale. Past 60 patches in one flush a full snapshot is sent
instead — cheaper to build, cheaper to send, and far easier to reason about.

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
- **On save failure:** ProfileStore performs its own internal write retries, so
  a single failed write is not observable to us and a manual retry loop on top
  would fight it. What *is* observable — and what actually matters — is a long
  silence. `DataService` tracks the time since the last successful save and
  raises a `SaveStalled` signal after `GameConfig.SaveStalledWarningSecs`
  (600 s). Step 16 turns that signal into a player-facing banner and Step 21
  gates Robux purchases on it.
  *(Adapted from the original "retry 5× with backoff" plan once ProfileStore
  was chosen — see PROGRESS.md deviation #4.)*
- `game:BindToClose` waits for all outstanding saves (max 25 s).

**Schema safety, enforced at boot.** `DataService.Init` asserts two invariants
before the store is opened, because both failures are silent and server-wide:
1. `Migrations.Validate()` — the migration chain is contiguous from 1 with no
   gaps and no non-function entries. A migration stranded past a gap never
   runs, so profiles would load claiming an old version while the code assumed
   the new shape.
2. `ProfileTemplate.SchemaVersion == Migrations.CurrentVersion()` — bumping the
   schema without adding the matching migration means *nobody can log in*.

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
| Guardian AI | Dormant until aggro — an idle nest has no loop, no connection and no physics cost. **Decisions at 6 Hz, movement integrated every frame** from the last decision: steering six times a second looks like stop-motion, deciding sixty times a second costs sixty times as much for an answer that changes about as often as the player turns. Guardians are anchored and moved by CFrame rather than driven by Humanoids — the placeholder models have no rig, a Humanoid each would cost far more than the steering, and CFrame movement is unambiguously server-authoritative. Hard cap 20 active; at the cap a new steal **recycles the longest-running chase** |
| Particles | Global `ParticleBudget`; rarity VFX auto-downgrade beyond 120 studs and are disabled entirely in Low Graphics Mode |
| Remotes | 5 Hz coalesced state deltas; no per-frame remotes anywhere. Income floaters are generated client-side from a replicated rate, not sent per tick |
| Income ticking | The server does **not** tick per dinosaur. It stores `bankedAt` + `ratePerSecond` and computes lazily on read. O(1) per player, not O(dinos) |
| Nest queries | `CollectionService:GetTagged("SAD_Nest")` once at boot into a spatial bucket grid; proximity checks are bucket lookups, not distance loops over all nests |
| Physics | Guardians are network-owned by the **server** (`BasePart:SetNetworkOwner(nil)`) — required for anti-cheat and it keeps physics off client CPUs. **Carried eggs are not**: a part welded to a character joins that character's assembly and is simulated on its owner's client, unavoidably. That is safe because the carried model is purely cosmetic — the CarryToken on the server is the only authority, and deleting, duplicating or editing the model changes nothing the server believes |
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
| Offline specs | `./tests/run.sh` syntax-checks every source file with `luau-compile` and runs assertions against the pure modules outside Roblox. Fast enough to run on every change |
| Pure logic | `RNG`, `Format`, economy formulas and migrations are pure functions with a `TestEZ`-style spec run in Studio via a `RunTests` script |
| Integration | Studio `Play Solo` checklists per build step (each step in [13-build-order.md](13-build-order.md) ships with its own test list) |
| Multiplayer | Studio "Start Server + 2 Players" for every steal/raid change — never test stealing in solo |
| Exploit sim | A `DebugExploitClient` LocalScript (Studio-only, stripped from production) that fires every remote with malformed payloads, out-of-range positions, and spam bursts. Every build step must survive it |
| Load | 30-bot soak via `Players:CreateLocalPlayer` stand-ins is not possible; instead a `SimulatedLoad` server module spawns 20 guardians + 700 park dinos and reports frame time |
