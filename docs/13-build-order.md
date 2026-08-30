# 13 — Roblox Studio Build Order

24 steps to a playable V1. Each step is independently testable and leaves the
game in a working state. **Do not skip ahead** — later steps assume earlier ones
exist by the exact names in [09-tech-architecture.md](09-tech-architecture.md).

Each step below states: **Build** (what), **Location** (where in Studio),
**Objects** (what to create), **Talks to** (dependencies), **Test** (how to
verify), **Watch for** (the bugs that actually happen).

---

### Step 1 — Project skeleton & shared modules
- **Build:** the entire folder tree, empty configs, and the utility modules.
- **Location:** `ReplicatedStorage/SAD_Shared`, `ReplicatedStorage/SAD_Net`,
  `ServerScriptService/SAD_Server`, `StarterPlayerScripts/SAD_Client`.
- **Objects:** all folders; ModuleScripts `Types`, `Signal`, `Net`, `RNG`,
  `Format`, `TableUtil`, `Trove`; `Bootstrap` (Script) and `Bootstrap`
  (LocalScript); `GameConfig`.
- **Talks to:** nothing yet.
- **Test:** Play. Output shows `[SAD] Server boot complete` and
  `[SAD] Client boot complete` with no errors.
- **Watch for:** circular requires; `Bootstrap` running before
  `ReplicatedStorage` children replicate on the client (use `WaitForChild`).

### Step 2 — DataService & PlayerDataService
- **Build:** persistence with session locking, schema v1, migration chain,
  autosave, `BindToClose`.
- **Location:** `SAD_Server/Services/DataService`, `PlayerDataService`.
- **Objects:** those two ModuleScripts + `ProfileStore` module in
  `ServerScriptService/SAD_Server` (third-party, added manually).
- **Talks to:** `Bootstrap`; later, *everything*.
- **Test:** join, set `Fossils = 500` via the command bar, leave, rejoin →
  500 persists. Force a save failure (rename the store) → banner appears, no
  crash.
- **Watch for:** Studio API access to DataStores must be enabled in Game
  Settings; session locks not releasing on a Studio stop; `BindToClose` firing
  before saves complete.

### Step 3 — Config modules & ConfigValidator
- **Build:** `RarityConfig`, `DinoConfig` (34 species), `MutationConfig` (8),
  `ZoneConfig` (4 zones), `UpgradeConfig`, `RebirthConfig`, plus
  `ConfigValidator`.
- **Location:** `SAD_Shared/Config`.
- **Test:** boot passes validation. Deliberately break a weight sum → boot fails
  with a precise message.
- **Watch for:** validator rule #6 (a rarity reachable in a zone with no species
  in that zone's pool) — this *will* fire, and it's the point.

### Step 4 — State replication
- **Build:** `StateFull` / `StateDelta`, client `StateController`.
- **Location:** remotes in `SAD_Net/Events`; `SAD_Client/Controllers/StateController`.
- **Test:** change `Fossils` server-side → the client mirror updates within
  200 ms. Confirm another player's client does **not** receive it.
- **Watch for:** sending the whole profile every change (bandwidth); leaking
  server-only fields into the replicated slice.

### Step 5 — HUD skeleton
- **Build:** top bar, bottom bar, empty action zone.
- **Location:** `StarterGui/SAD_UI`; `HUDController`, `UIController`,
  `InputController`, `Format`.
- **Test:** currency displays and formats (1.23K / 4.5M). Resize to a phone
  viewport → nothing overlaps, everything is thumb-reachable.
- **Watch for:** `ResetOnSpawn` must be false or the HUD dies on respawn.

### Step 6 — Park plots
- **Build:** 6 plots, assignment on join, release on leave, gate trigger,
  placement grid, spawn-in-your-own-park.
- **Location:** `Workspace/SAD_World/ParkPlots`; `ParkService`.
- **Objects:** `Plot01…Plot24` Models each containing `Gate`, `SafeDome`,
  `Grid` (64 tile parts), `IncubatorRow`, `VaultPedestal1`, `CollectionTotem`.
- **Test:** two Studio clients get different plots; leaving frees a plot; a
  25th joiner is handled gracefully (queue + message, never an error).
- **Watch for:** plot assignment race on simultaneous joins — assign inside a
  single-threaded function.

### Step 7 — Nests & the world
- **Build:** Zone 1–4 geometry (blockout is fine), `SAD_NestAnchor` tags,
  nest spawning, egg models, respawn timers, nest signs.
- **Location:** `Workspace/SAD_World/Zones`; `NestService`.
- **Test:** eggs appear at every anchor; emptying a nest refills after the
  zone's respawn time; the sign shows correct odds.
- **Watch for:** `CollectionService` tags lost on model duplication in Studio.

### Step 8 — Egg pickup & carrying
- **Build:** `ProximityPrompt` hold, server-side rarity roll, carry token, egg
  attached overhead, carry speed penalty, rarity aura, drop.
- **Location:** `EggService`, `SecurityService`; client `EggCarryController`.
- **Remotes:** `RequestPickupEgg`, `RequestDropEgg`.
- **Test:** pick up → rarity chip appears, speed drops measurably. Two clients
  grab the same egg simultaneously → exactly one succeeds.
- **Watch for:** the egg model must be welded, not parented to the character's
  physics; network ownership must stay with the server.

### Step 9 — Guardian AI & the chase
- **Build:** dormant guardians, aggro on pickup, the 6 Hz chase tick, path
  recalc throttling, 8 archetypes, catch → trip → egg drops, de-aggro rules,
  the 20-guardian cap with Ghost Chase fallback.
- **Location:** `WildAIService`; client `ChaseState` handling in
  `EggCarryController` + `CameraController` shake.
- **Test:** steal → chased → escape to your gate → chase ends. Get caught →
  trip, egg bounces, egg returns to the nest after 10 s. Spawn 20 guardians →
  frame time stays under budget.
- **Watch for:** guardians pathing into parks (they must stop at the gate);
  `Humanoid:MoveTo` re-issuing every tick (it must not); guardians network-owned
  by a client.

### Step 10 — Safe zone & deposit
- **Build:** server-side gate crossing detection, auto-deposit into a free
  incubator or egg storage, `SAFE!` feedback.
- **Location:** `ParkService`, `EggService`.
- **Test:** carry an egg through your gate → deposits, chase ends. Carry through
  *someone else's* gate → does **not** deposit, guardian still stops.
- **Watch for:** detecting the crossing on the client (never do this); double
  deposits from a single crossing.

### Step 11 — Incubation & hatching
- **Build:** incubator timers, rarity-scaled duration, offline continuation,
  species + mutation roll at hatch, hatch VFX, `HatchResult`.
- **Location:** `IncubationService`, `DinosaurService`, `MutationService`.
- **Remotes:** `RequestStartIncubation`, `RequestClaimHatch`, `HatchResult`.
- **Test:** hatch a Common in 30 s. Set a hatch time in the past and rejoin →
  it's ready. Force-roll each rarity and mutation via the command bar and
  confirm every VFX and announcement path.
- **Watch for:** timers driven by `tick()` (use `os.time()` so they survive
  offline); claiming an unfinished hatch; hatching into full storage.

### Step 12 — Placement & income
- **Build:** drag-to-place on the grid, size footprints, income formula, the
  lazy bank, the Collection Totem, income floaters, offline income screen.
- **Location:** `DinosaurService`, `EconomyService`; client `ParkController`.
- **Remotes:** `RequestPlaceDino`, `RequestStoreDino`, `RequestCollectIncome`.
- **Test:** place a dinosaur → income ticks. Formula matches
  [05-economy.md](05-economy.md) §2 by hand. Leave 10 minutes → offline screen
  shows the right number. Bank caps correctly.
- **Watch for:** O(dinos) income loops — it must be lazy; 4×4 footprints
  overlapping; collecting twice in one frame.

### Step 13 — Upgrades & shop
- **Build:** 11 upgrade tracks + 3 defence tracks, `PlayerStats` aggregation,
  Buy / Buy Max, the three shop boards.
- **Location:** `UpgradeService`; client `ShopController`.
- **Remotes:** `RequestBuyUpgrade`, `RequestBuyDefence`.
- **Test:** buy each track to max; confirm each effect actually applies. Buy Max
  with insufficient funds → buys the affordable amount, never goes negative.
- **Watch for:** float drift on geometric costs (round consistently, server-side
  only); client-computed costs disagreeing with the server.

### Step 14 — Zones & teleports
- **Build:** zone gates, unlock validation, Zone Shrines, the Teleport Obelisk
  and zone wheel.
- **Location:** `ParkService` / a small `ZoneService` inside `NestService`;
  client `TeleportController`.
- **Remotes:** `RequestUnlockZone`, `RequestTeleport`.
- **Test:** unlock Zone 2, teleport, confirm a locked zone rejects both the walk
  and the teleport.
- **Watch for:** teleports tripping the movement-plausibility detector (set
  `ExemptUntil`).

### Step 15 — Player raiding
- **Build:** the full state machine from [03-stealing.md](03-stealing.md) §4:
  hold-to-steal, carry, tagging, gate transfer, disconnect resolution, shields,
  Vault, cooldowns, power floor, insurance, Revenge Mark.
- **Location:** `StealService`.
- **Remotes:** `RequestStealBegin`, `RequestStealCancel`, `RequestTagThief`,
  `RequestVaultDino`, `StealAlert`.
- **Test:** **two clients, always.** Full steal succeeds. Owner tags → returns.
  Thief disconnects mid-carry → returns after 30 s. Vaulted dino cannot be
  targeted. Shielded park cannot be entered for theft. Offline player cannot be
  raided.
- **Watch for:** this is the #1 dupe surface. Test: steal → disconnect →
  immediately rejoin. Steal → owner leaves. Two thieves target the same dino.

### Step 16 — Notifications & announcements
- **Build:** toast/banner/takeover/alert, the queue, `BroadcastService` over
  `MessagingService`, the odds display.
- **Location:** `NotificationService`, `BroadcastService`; client
  `NotificationController`, `SoundController`.
- **Test:** trigger each severity. Force 5 takeovers at once → they queue, max 3,
  then drop. Two Studio servers → cross-server messages arrive.
- **Watch for:** `MessagingService` rate limits; unvalidated inbound payloads.

### Step 17 — Weather
- **Build:** 4 weathers, the 8-minute roll, Lighting transitions, mutation
  weight modifiers, the countdown banner.
- **Location:** `WeatherService`.
- **Test:** force each weather; confirm the mutation weight shift is measurable
  over 10,000 simulated rolls; confirm Lighting restores on Clear.
- **Watch for:** Lighting changes not reverting; weather applied client-side
  (the *effects* are server truth, only the visuals are local).

### Step 18 — Server events
- **Build:** the scheduler, the handler module pattern, 4 events, countdowns,
  participation tracking, contribution scoreboards.
- **Location:** `EventService` + `Handlers/`.
- **Test:** each event start→finish; rewards distributed by contribution; a
  player joining mid-event sees correct state; no two events overlap.
- **Watch for:** events continuing after the last participant leaves; rewards
  granted twice on a rejoin.

### Step 19 — Quests, dailies, index
- **Build:** daily/weekly quest rolls and progress, the 7-day chest, streaks,
  the Index book and milestones.
- **Location:** `QuestService`, `DailyService`, `IndexService`.
- **Test:** complete a quest; cross a UTC day boundary (fake `os.time()`);
  break and rebuild a streak; discover a species and confirm the Index and a
  milestone fire.
- **Watch for:** timezone handling (use UTC days consistently); double-claim.

### Step 20 — Rebirth
- **Build:** cost curve, the keep/lose/gain preview, the reset transaction,
  grants, Vault preservation, the Rebirth Cache.
- **Location:** `RebirthService`.
- **Test:** rebirth at exactly the threshold; confirm vaulted dinos and Index
  survive; confirm the multiplier applies; confirm a mid-carry rebirth is
  rejected.
- **Watch for:** the reset must be one atomic profile write. A half-applied
  rebirth is the worst bug in the game.

### Step 21 — Purchases
- **Build:** `ProcessReceipt` with idempotency, gamepass ownership cache, all 6
  passes and 8 products, server-wide boost purchases + the Thanks button.
- **Location:** `PurchaseService`.
- **Test:** buy each product in a Studio test place; kill the server mid-grant →
  the receipt reprocesses exactly once on rejoin. Buy a gamepass mid-session →
  effect applies without a rejoin.
- **Watch for:** returning `PurchaseGranted` before the profile is marked dirty
  (this loses purchases and it is the most expensive bug possible).

### Step 22 — Leaderboards
- **Build:** 4 `OrderedDataStore` boards, throttled writes, the 60 s read cache,
  the Colosseum statues.
- **Location:** `LeaderboardService`.
- **Test:** values appear within 5 minutes; your own rank pins correctly; budget
  usage stays inside limits with 30 players.
- **Watch for:** writing every change (budget exhaustion); values above the
  `OrderedDataStore` 64-bit integer range — store `math.min(value, 9e18)`.

### Step 23 — Tutorial
- **Build:** Professor Rok, the 12 beats, world-space arrows, the forced-Common
  first egg, the unlosable first chase, step timeouts, skip, resume.
- **Location:** `TutorialController` + a small server validator in
  `PlayerDataService`.
- **Test:** a fresh profile completes it in under 3 minutes. Skip works.
  Disconnect at step 6 and rejoin → resumes at step 6. Idle at every step → the
  auto-advance fires.
- **Watch for:** the tutorial fighting the real systems (it must *drive* them,
  never bypass them).

### Step 24 — Polish, analytics, hardening
- **Build:** all `AnalyticsService` events, settings menu, Low Graphics mode,
  sound pass, animation pass, the `DebugExploitClient` sweep, and the launch
  readiness gates in [12-mvp-and-roadmap.md](12-mvp-and-roadmap.md) §4.
- **Test:** the full gate checklist. Run `DebugExploitClient` against every
  remote and confirm zero state changes.
- **Watch for:** `DebugExploitClient` must be deleted or `RunService:IsStudio()`
  guarded before publishing.

---

## Working agreement for the build

1. One step per session. Complete code, exact locations, exact object names.
2. Every step ends with its test list run and the result stated plainly.
3. A running `PROGRESS.md` records what exists, so nothing gets renamed or
   rebuilt by accident.
4. Names from [09-tech-architecture.md](09-tech-architecture.md) and
   [10-data-schema.md](10-data-schema.md) do not change. If one must, the doc
   changes first, with the reason written down.
5. If a Roblox API behaves differently than expected, I say so rather than
   inventing a workaround that looks plausible.
