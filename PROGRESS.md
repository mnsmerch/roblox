# Build Progress

Running record of everything that exists, so nothing gets renamed or rebuilt by
accident. Updated at the end of every build step.

## Status: **Step 14 of 24 complete.** The map closes up. Awaiting the Studio Play test before Step 15.

## Completed

| Date | Item | Notes |
|---|---|---|
| 2026-08-29 | Game Design Blueprint (docs 00–15) | Full design, economy, architecture, MVP, build order |
| 2026-08-29 | **Step 1** — project skeleton & shared modules | 11 files, 83 offline assertions |
| 2026-08-29 | **Step 2** — DataService & PlayerDataService | ProfileStore-backed persistence, 150 more assertions |
| 2026-08-29 | **Step 3** — config modules & ConfigValidator | All V1 content data, 800 more assertions |
| 2026-08-29 | Glitch Compsognathus added (species #35) | The any-zone Secret; approved as V1 scope |
| 2026-08-29 | **Step 4** — state replication | Shared `Patch` module, allowlist boundary, 183 more assertions |
| 2026-08-29 | **Step 5** — HUD skeleton | UI built in code, 96 more assertions |
| 2026-08-29 | **Step 6** — park plots | 24 plots generated procedurally, 142 more assertions |
| 2026-08-29 | **Step 7** — world, zones & nests | Hub + 4 zones + 48 nests generated, 356 more assertions |
| 2026-08-30 | **Step 8** — egg pickup & carrying | Rarity roll, carry tokens, loose eggs, 96 more assertions |
| 2026-08-30 | **Step 9** — guardian AI & the chase | 20 archetypes, zone difficulty curve, 274 more assertions |
| 2026-08-30 | **Step 10** — safe zone & deposit | The loop closes: steal → chase → keep it. 31 more assertions |
| 2026-08-30 | **Step 11** — incubation & hatching | Species + mutation rolls, incubator pads, 298 more assertions |
| 2026-08-30 | **Step 12** — placement & income | Lazy bank, offline earnings, auto-placement, 57 more assertions |
| 2026-08-30 | **Step 13** — upgrades & the shop | 14 tracks, shared `Stats`, three boards, 106 more assertions |
| 2026-08-30 | **Step 14** — zones & teleports | Unlock gates, shrines, the Obelisk, 82 more assertions |

## Build steps (see docs/13-build-order.md)

| Step | Name | Status |
|---:|---|---|
| 1 | Project skeleton & shared modules | ✅ **done** |
| 2 | DataService & PlayerDataService | ✅ **done** |
| 3 | Config modules & ConfigValidator | ✅ **done** |
| 4 | State replication | ✅ **done** |
| 5 | HUD skeleton | ✅ **done** |
| 6 | Park plots | ✅ **done** |
| 7 | Nests & the world | ✅ **done** |
| 8 | Egg pickup & carrying | ✅ **done** |
| 9 | Guardian AI & the chase | ✅ **done** |
| 10 | Safe zone & deposit | ✅ **done** |
| 11 | Incubation & hatching | ✅ **done** |
| 12 | Placement & income | ✅ **done** |
| 13 | Upgrades & shop | ✅ **done** |
| 14 | Zones & teleports | ✅ **done** |
| 15 | Player raiding | ⬜ |
| 16 | Notifications & announcements | ⬜ |
| 17 | Weather | ⬜ |
| 18 | Server events | ⬜ |
| 19 | Quests, dailies, index | ⬜ |
| 20 | Rebirth | ⬜ |
| 21 | Purchases | ⬜ |
| 22 | Leaderboards | ⬜ |
| 23 | Tutorial | ⬜ |
| 24 | Polish, analytics, hardening | ⬜ |

## What exists in Studio

Names below are frozen. Nothing here gets renamed without a doc change first.

### ReplicatedStorage/SAD_Shared

| Object | Type | Purpose |
|---|---|---|
| `Config/GameConfig` | ModuleScript | Global constants only. Dependency-free |
| `Config/RarityConfig` | ModuleScript | 9 tiers, 4 zone weight vectors, luck powers |
| `Config/MutationConfig` | ModuleScript | 8 V1 mutations + none, Prime rule, weather modifiers |
| `Config/DinoConfig` | ModuleScript | 34 V1 species. **Authoritative for species↔zone** |
| `Config/ZoneConfig` | ModuleScript | Zones 1–4, unlock gates, nest parameters |
| `Config/UpgradeConfig` | ModuleScript | 11 upgrade + 3 defence tracks, cost/effect curves |
| `Config/RebirthConfig` | ModuleScript | Cost curve, preserved keys, permanent grants |
| `Config/ConfigValidator` | ModuleScript | 10 content rules + 4 structural; aborts boot on error |
| `Config/ParkConfig` | ModuleScript | Plot geometry, grid maths, visual tiers |
| `Config/ChaseConfig` | ModuleScript | 20 guardian archetypes, chase tuning, the guardian cap |
| `Modules/Types` | ModuleScript | Luau types incl. the full `Profile` shape |
| `Modules/Log` | ModuleScript | `Log.debug/info/warn/error/banner(scope, msg, ...)` |
| `Modules/Signal` | ModuleScript | `new/Connect/Once/Fire/Wait/DisconnectAll` |
| `Modules/Trove` | ModuleScript | `new/Add/Connect/Extend/Remove/Clean` |
| `Modules/TableUtil` | ModuleScript | `DeepCopy/Reconcile/Merge/Count/SortedKeys/DeepFreeze/DeepEquals` |
| `Modules/Format` | ModuleScript | `Number/Comma/Time/Clock/Odds/Percent/Multiplier` |
| `Modules/RNG` | ModuleScript | `new/WeightedPick/ApplyLuck/ApplyModifiers/Chance/Shuffle/Pick/ProbabilityOf` |
| `Modules/Net` | ModuleScript | Remote inventory, rate limits, arg validation |
| `Modules/Patch` | ModuleScript | Structural diff + apply, shared by both sides of replication |
| `Modules/Economy` | ModuleScript | Income, sell value, banking and offline maths. Pure; shared by both sides |
| `Modules/Stats` | ModuleScript | Every derived player number: upgrades + rebirth grants + caps. Pure |
| `Modules/AssetBuilder` | ModuleScript | Placeholder egg + dinosaur models; only fills what is missing |
| `SAD_Assets/{Dinos,Eggs,Effects,UI}` | Folders | Empty until Step 7 |

### Created at runtime (do NOT build by hand)

`ReplicatedStorage/SAD_Net` with `Events` (28 client→server + 10 server→client
RemoteEvents) and `Functions` (4 RemoteFunctions). `Net.Init()` destroys and
rebuilds this on every server start.

### ServerScriptService/SAD_Server

| Object | Type | Purpose |
|---|---|---|
| `Bootstrap` | **Script** | The only Script in the project |
| `ProfileStore` | ModuleScript | **Third-party** (MadStudioRoblox). Installed by hand — see SETUP.md |
| `Services` | Folder | One service per build step |
| `Services/DataService` | ModuleScript | Persistence + session locking. **The only file that knows ProfileStore exists** |
| `Services/DataService/ProfileTemplate` | ModuleScript | Schema v1 defaults; mirrors docs/10 |
| `Services/DataService/Migrations` | ModuleScript | Ordered pure migrations + `Validate`/`Apply`/`WriteInPlace` |
| `Services/PlayerDataService` | ModuleScript | Profile access layer for every other service |
| `Services/PlayerDataService/Replication` | ModuleScript | The client mirror: allowlist slice, 5 Hz coalesced deltas |
| `Services/ParkService` | ModuleScript | Plot ownership, park occupancy, grid ↔ world |
| `Services/ParkService/PlotBuilder` | ModuleScript | Procedural plot geometry |
| `Services/NestService` | ModuleScript | World blockout, nest state, egg claiming, respawn |
| `Services/NestService/WorldBuilder` | ModuleScript | Hub plaza + 4 zone blockouts + tagged anchors |
| `Services/NestService/NestBuilder` | ModuleScript | Nest bowl, generic eggs, risk/odds sign |
| `Services/NestService/ZoneService` | ModuleScript | Zone unlocking, shrines, teleports, locked-zone trespass |
| `Services/SecurityService` | ModuleScript | Rate-limit records, movement plausibility, distance checks |
| `Services/EggService` | ModuleScript | Pickup, rarity roll, carry tokens, carry weight, loose eggs, speed modifiers |
| `Services/WildAIService` | ModuleScript | Guardian spawn, chase decisions, abilities, catching, de-aggro |
| `Services/MutationService` | ModuleScript | Mutation rolls, weather modifiers, MutLuck, the Prime rule |
| `Services/DinosaurService` | ModuleScript | Species rolls, profile entries, income and sell value |
| `Services/IncubationService` | ModuleScript | Incubator timers, physical pads, hatch resolution |
| `Services/EconomyService` | ModuleScript | The lazy bank, collection, offline earnings, all currency movement |
| `Services/UpgradeService` | ModuleScript | Pricing, Buy and Buy Max in one transaction, live effect application |

```
MutationService.Roll(player) -> mutation, mutation2?
MutationService.RollIn(mutLuck, weatherId, rng?) -> mutation, mutation2?   -- pure
MutationService.MutLuckFrom(data) -> number                                -- pure
MutationService.SetWeather(weatherId)          -- Step 17 drives this

DinosaurService.RollSpecies(zoneId, rarity, rng?) -> speciesId?
DinosaurService.Create(player, params) -> uid?, entry?, reason?
DinosaurService.IncomeOf(entry, data) -> number      -- the master formula
DinosaurService.SellValueOf(entry) -> fossils, dna
DinosaurService.DisplayNameOf(entry) -> string
DinosaurService.GetStorageUsed / GetStorageCap

IncubationService.BeginIncubation(player, eggUid, slotIndex?) -> ok, reason?
IncubationService.Claim(player, slotIndex) -> ok, reason?
IncubationService.AutoStart(player) -> started
IncubationService.DurationFor(data, rarity) -> seconds
IncubationService.Hatched  Signal(player, uid, entry, odds)
```

**Incubators are physical.** The pads built in Step 6 carry prompts that fill,
count down, and say HATCH — FTUE beats 7 and 8 verbatim, and the reveal works
before any menu exists.

```
Economy.IncomeOf(entry, data?) -> fossilsPerSecond    -- the master formula
Economy.SellValueOf(entry) -> fossils, dna
Economy.ParkIncomeRate(data) -> fossilsPerSecond      -- placed + vaulted only
Economy.BankedNow(data, now, rate?) -> banked, rate, cap
Economy.OfflineEarnings(data, now, rate?, offlineRate?) -> fossils, cappedSecs
Economy.BankSeconds(data) -> seconds       -- 4h + 1h/rebirth, capped at 12h
Economy.BankCap(data, rate?) -> fossils
Economy.ClampFossils(amount) -> number
Economy.ParkValue(data) -> fossils
Economy.SlotCap(data) -> number
Economy.MaxFossils / Economy.OfflineRate / Economy.StarBonusPerStar

EconomyService.GetRate(player) -> fossilsPerSecond       -- cached
EconomyService.GetBanked(player) -> banked, rate, cap
EconomyService.Collect(player) -> collected
EconomyService.InvalidateRate(player)
EconomyService.AddFossils(player, amount, reason) -> newTotal
EconomyService.TrySpendFossils(player, amount, reason) -> ok
EconomyService.AddDna(player, amount, reason)
EconomyService.Collected  Signal(player, amount)

DinosaurService.Place(player, uid, tileX, tileZ) -> ok, reason?
DinosaurService.PlaceBest(player) -> uid?, reason?
DinosaurService.Store(player, uid) -> ok, reason?
DinosaurService.FindFreeFootprint(data, size, exceptUid?) -> tileX?, tileZ?
DinosaurService.DinoPlaced / DinoStored   Signals
```

**Nothing ticks.** The bank is `BankedFossils + BankedRate × (now − BankedAt)`,
capped, computed on read. The rate is the only O(dinos) part and it is cached,
dropped whenever a park changes. `DataService.BeforeSave` folds the pending bank
into `BankedFossils`, so a crash cannot lose accrued income.

**`BankedRate` is not a cache.** It is the rate the *current interval* accrues
at, frozen when the interval opened, and it lives in the profile. Anything that
changes a park's output must call `EconomyService.SettleBank` first — see
finding 13 below for what happens otherwise.

```
Stats.Of(data) -> { DinoSlots, DinoStorage, Incubators, IncubationMult,
                    ParkIncomeMult, BankSecs, Luck, MutLuck, MoveSpeedMult,
                    CarryPenaltyMult, EggCapacity, StealHoldBonus,
                    TowerCooldown, AlertRange }
Stats.<Field>(data) -> number       -- one field, no allocation; same expression
Stats.KindToField                   -- Effect.Kind -> field; ConfigValidator R9
Stats.AssertComplete() -> ok, reason?

UpgradeConfig.StoreFor(trackId) -> "Upgrades" | "Defences"
UpgradeConfig.LevelIn(data, trackId) -> level
UpgradeConfig.CostOf(trackId, level) -> fossils      -- 0 means not purchasable
UpgradeConfig.CostRange(trackId, from, to) -> fossils

UpgradeService.LevelOf(data, trackId) -> level
UpgradeService.Affordable(data, trackId, wanted) -> levels, cost
UpgradeService.Buy(player, trackId, wanted) -> bought, spent, reason?
UpgradeService.ApplyLiveEffect(player, trackId)
UpgradeService.Purchased  Signal(player, trackId, newLevel, spent)

EconomyService.SettleBank(player)   -- closes the interval at the OLD rate
```

**Eleven call sites became one module.** Before Step 13, six files each wrote
their own `UpgradeConfig.EffectAt(track, data.Upgrades[track] or 0)`, and the
ones that also had a rebirth grant or a cap folded it in locally. `Stats` owns
all of it; the old public functions (`EggService.LuckFrom`,
`MutationService.MutLuckFrom`, `DinosaurService.GetStorageCap`,
`Economy.SlotCap`, `Economy.BankSeconds`) kept their names and delegate.

```
ZoneConfig.UnlockCheck(zoneId, data, dinoConfig, rarityConfig)
    -> ok, reason?, requirements     -- requirements = { {Label, Met}, ... }

ZoneService.CanUnlock(data, zoneId) -> ok, reason?, requirements
ZoneService.Unlock(player, zoneId) -> ok, reason?
ZoneService.RegisterShrine(player, zoneId) -> ok, reason?
ZoneService.Teleport(player, destination) -> ok, reason?
ZoneService.DestinationCFrame(player, destination) -> CFrame?
ZoneService.TeleportBlocked(player) -> reason?
ZoneService.RegisterBlocker(name, fn)      -- fn(player) -> reason?
ZoneService.ZoneAt(position) -> zoneId?
ZoneService.ZoneUnlocked / ShrineFound / Teleported   Signals

NestService.Zones                          -- the ZoneService above
```

**Unlocked and discovered are different fields.** `ZonesUnlocked` is what you
paid for; `Shrines` is what you have walked to. A zone is only a teleport
destination once both are true, so the first trip to any zone is always walked.

**Teleports are refused mid-chase**, and that is the whole design of them —
see deviation #43. `RegisterBlocker` is how Step 15 adds the raiding case in
one line at its own call site.

```
WildAIService.StartChase(player, nest, token) / EndChase(player, reason)
WildAIService.IsChasing(player) -> boolean
WildAIService.GetActiveCount() -> number
WildAIService.ChaseStarted / ChaseEnded / ThiefCaught   Signals

EggService.SetSpeedModifier(player, key, multiplier, duration?)
EggService.ClearSpeedModifier(player, key)
```

```
SecurityService.CheckDistance(player, position, range?) -> ok, reason?
SecurityService.SetMaxSpeed(player, speed) / GetMaxSpeed(player)
SecurityService.Exempt(player, seconds) / IsExempt(player)
SecurityService.Flag(player, kind, detail) / GetFlagCount(player)
SecurityService.Flagged / CarryVoided   Signals

EggService.TryPickup(player, nestId, slotIndex) -> ok, reason?
EggService.Drop(player, uid, reason?) / DropAll(player, reason?)
EggService.GrabLoose(player, uid) -> ok, reason?
EggService.TakeToken(player, uid) -> token?      -- Step 10 deposits with this
EggService.GetCarried / GetCarryCount / GetCapacity / GetCarryPenalty
EggService.CarryPenaltyOf(penalties, strongBackMult) -> number   -- pure
EggService.LuckFrom(data, zone) -> number                        -- pure
EggService.RollRarityIn(zoneId, luck, rng?) -> rarityId          -- pure given rng
EggService.EggPickedUp / EggDropped / RareGrab   Signals
```

**A carried egg is never in the profile.** It exists as a server-side token and
nothing else, so leaving mid-run returns it to its nest rather than banking it.
The model welded to the character is cosmetic — deleting or editing it changes
nothing the server believes.

```
NestService.GetNest(nestId) -> nest?
NestService.GetNestsInZone(zoneId) -> { nest }
NestService.ClaimEgg(player, nestId, slotIndex) -> ok, reason   -- yield-free
NestService.IsSlotFilled(nestId, slotIndex) -> boolean
NestService.CountAvailableEggs(zoneId?) -> number
NestService.EggClaimed / NestRefilled   Signals
```

Generated at runtime into `Workspace/SAD_World` (hub, zones) and
`Workspace/SAD_Runtime/Nests`. 48 nests, 122 eggs. Anchors are discovered
through the `SAD_NestAnchor` **CollectionService tag**, not from the builder's
return value — so a hand-built zone can replace a generated one with no code
change.

```
ParkService.GetPlot(player) -> Model?
ParkService.GetPlotByUserId(userId) -> Model?
ParkService.GetOwnerOf(plot) -> number
ParkService.GetParkAt(position) -> plot?, ownerUserId?     -- O(1)
ParkService.IsInsideOwnPark(player) -> boolean
ParkService.GetOccupiedPark(player) -> userId?
ParkService.GetSpawnCFrame(plot) -> CFrame
ParkService.GetTileCFrame(plot, tileX, tileZ, size?) -> CFrame
ParkService.WorldToTile(plot, position) -> tileX?, tileZ?
ParkService.SetShieldVisible(plot, visible)
ParkService.SetVisualTier(plot, parkValue)
ParkService.PlotAssigned / PlotReleased / ParkEntered / ParkExited   Signals
```

Generated at runtime into `Workspace/SAD_World/ParkPlots`; the previous ring is
destroyed on each boot. `Players.CharacterAutoLoads` is **off** — characters are
spawned by hand once a plot is assigned.

**Public API in use (frozen):**

```
DataService.StartSessionAsync(player) -> Session?   yields
DataService.EndSession(player)
DataService.SaveNow(player, reason)
DataService.GetSession(player) -> Session?
DataService.BeforeSave    Signal(player, data, reason)
DataService.SaveStalled   Signal(player, secondsSinceLastSave)

PlayerDataService.Get(player) -> data?
PlayerDataService.GetAsync(player, timeout?) -> data?
PlayerDataService.IsLoaded(player) -> boolean
PlayerDataService.Update(player, mutator, reason?) -> boolean
PlayerDataService.UpdateKeys(player, keys, mutator, reason?) -> boolean
PlayerDataService.Save(player, reason)
PlayerDataService.SendFullState(player)
PlayerDataService.GetAll() -> {[Player]: data}
PlayerDataService.ProfileLoaded     Signal(player, data)
PlayerDataService.ProfileUnloading  Signal(player, data)
PlayerDataService.Changed           Signal(player, reason, keys?)
```

Rule for later steps: **reads use `Get`, writes use `UpdateKeys`** (or `Update`
when unsure what changed — it marks everything dirty, costing one wider diff
rather than a desynced client). A write that bypasses both is a write the
client never hears about; there is no polling fallback by design.

### StarterPlayerScripts/SAD_Client/UI

| Object | Type | Purpose |
|---|---|---|
| `Theme` | ModuleScript | Design tokens **and** the pure scale/breakpoint functions |
| `Create` | ModuleScript | Declarative `Instance.new` wrapper; parents last |
| `Widgets` | ModuleScript | Panel, BottomButton, RailButton, Chip, ActionPrompt, Layout, SetNumber |

### StarterPlayerScripts/SAD_Client/Controllers

| Object | Type | Purpose |
|---|---|---|
| `StateController` | ModuleScript | The client's mirror of its own profile slice |
| `UIController` | ModuleScript | Owns `SAD_UI`, the 5 layers, scaling, one-screen-at-a-time |
| `HUDController` | ModuleScript | Top bar, rails, bottom bar, action prompt, carry panel |
| `InputController` | ModuleScript | Keyboard/gamepad/touch → named actions |
| `EggCarryController` | ModuleScript | Reads carry state off the world; carry panel and chase readout |
| `CameraController` | ModuleScript | Camera shake, applied as an offset after Roblox's camera step |
| `ParkController` | ModuleScript | Income floaters, computed locally from the replicated profile |
| `ShopController` | ModuleScript | The three upgrade boards; prices rendered, never sent |
| `TeleportController` | ModuleScript | The zone wheel, the PARK teleport, gate-barrier visibility |

```
UIController.Layer(name) -> Frame        -- hud|screen|prompt|notification|takeover
UIController.Register(name, screen) / Open / Close / Toggle / CloseAll / GetOpen
UIController.Breakpoint  -> "compact"|"medium"|"wide"
UIController.BreakpointChanged  Signal(breakpoint, logicalWidth)

HUDController.SetAction(text?, progress?)
HUDController.SetChaseMode(active)
HUDController.SetCompass(text?)
HUDController.SetEventBanner(text?)

InputController.Action   Signal(action, state, inputObject?)
InputController.Fire(action, state?)     -- HUD buttons route through here
InputController.DeviceKind -> "Touch"|"Keyboard"|"Gamepad"|"Console"
```

`SAD_UI` is created at **runtime into PlayerGui**, not placed in StarterGui.

```
StateController.Get() -> state
StateController.GetPath(path) -> value?
StateController.IsReady() -> boolean
StateController.Observe(path, fn) -> { Disconnect }
StateController.Resync()  -- yields
StateController.Ready    Signal()
StateController.Changed  Signal(paths)
```

`Observe` is the pattern every UI element uses: it fires immediately with the
current value, then on every change at or under that path. No polling anywhere.

### StarterPlayerScripts/SAD_Client

| Object | Type |
|---|---|
| `Bootstrap` | **LocalScript** — the only LocalScript in the project |
| `Controllers` | Folder — empty; populated one controller per build step |

## Declared deviations from the frozen contract

| # | Change | Reason | Doc updated |
|---|---|---|---|
| 1 | Added `Log` as shared module #8 | Every service needs scoped, level-filtered logging from day one; retrofitting across 24 services later is worse | docs/09 §1 |
| 2 | `Service.Init()` → `Service.Init(app)` | StealService↔ParkService need each other; direct requires in both directions deadlock. `app` injects `Get/Log/Net/Config` | docs/09 §2 |
| 3 | Secret odds string `1 IN 5,263,157` → `1 IN 5,263,158` | `Format.Odds` rounds 100,000,000/19 to nearest. The doc example now matches what the code prints | docs/04 §4 |
| 4 | Save-failure handling: "retry 5× with backoff" → a `SaveStalled` signal | ProfileStore retries writes internally; a manual retry loop on top would fight it. A single failure is not observable — a long silence is, and that is the signal that matters | docs/09 §5 |
| 5 | **Removed `ZoneConfig.SpeciesPool`.** `DinoConfig.Zones` is the single source of truth; `BuildZoneIndex()` derives the pools at boot | Two tables describing one relationship drift apart the first time someone adds a dinosaur in a hurry, and the drift is silent | docs/11 §4 |
| 6 | V1 zone weight vectors carry **0** for Mythic and Ancient, folded into Legendary | V1 ships no species in those tiers. Non-zero weight for an unhatchable tier is exactly what validator rule 6 refuses to boot on. Design targets restored in V1.1/V1.3 | docs/01 §1.1 |
| 7 | Several species placed in earlier zones than docs/01 assigns (marked `V1_PLACEMENT`) | docs/01 assigns zones assuming all ten exist. With four, a Legendary has to be reachable somewhere or Zone 4's Legendary weight rolls a rarity that cannot hatch | docs/01 §3 |
| 8 | Park starts at **4** placement slots, not 8 | docs/12 said 8, docs/05's upgrade track said 4→30. Resolved to the economy model, which the whole cost curve is built on | docs/12 §2 |
| 9 | Dino Storage maxes at **205**, not 200 | 25 base + 12 levels × 15 = 205. The docs' endpoint and its own level maths disagreed | docs/05 §5, docs/06 §1 |
| 10 | Added `Patch` as shared module #9; diff/apply is shared code, not written twice | The delta producer and consumer must agree exactly. Separate implementations let them disagree — a numeric key stringified on one side, a removal mishandled on the other — and desync an inventory in a way that reads as a gameplay bug | docs/09 §1, §4 |
| 11 | `StateDelta` carries an **array** of patches, not one `{path, value}` | One packet per flush instead of one per changed field. A realistic gameplay tick produces 10 patches | docs/09 §3.2 |
| 12 | Added `SAD_Client/UI/` (Theme, Create, Widgets) beside `Controllers` | Forty `Instance.new` calls inline in a controller is unreadable, and three controllers sharing a button style needs one place to define it | docs/09 §1 |
| 13 | `SAD_UI` is created at runtime in `PlayerGui`, not placed in `StarterGui` | The UI is built in code, so there is nothing to place. A PlayerGui-parented ScreenGui survives respawn inherently — no `ResetOnSpawn` left to get wrong | docs/09 §1 |
| 14 | Breakpoints renamed `phone/tablet/desktop` → `compact/medium/wide` | They measure available room, not device class. Device names invite device-sniffing, which is how UI ends up wrong on the one configuration nobody tested | docs/08 §4 |
| 15 | **The enclosure grid is mathematical, not 64 parts per plot** | docs/13 called for 64 tile parts — 1,536 anchored parts across the ring to express a coordinate transform. One textured surface plus `ParkConfig` maths instead | docs/02 §3 |
| 16 | Added `ParkConfig` (plot geometry, grid maths, visual tiers) | Shared, because the client's placement preview must land where the server puts the dinosaur. Two copies of a grid origin is two grids | docs/09 §1 |
| 17 | `Players.CharacterAutoLoads = false`; characters spawned after plot assignment | Otherwise a player materialises at the world origin and is visibly teleported — in the first second of the game, against FTUE beat 1 | docs/00 §3 |
| 18 | Plot ring radius **derived** from `PlotCount × (PlotSize + PlotGap)`, gap raised 20 → 30 | A hand-picked radius overlaps plots the moment `PlotCount` changes. 20 studs of gap left only 6 studs of separating-axis margin | docs/02 §3 |
| 19 | Added `AssetBuilder` as shared module #10 | Placeholder models make ConfigValidator rule 7 a real check instead of a permanently skipped one, and unblock Steps 11–12 before any art exists. Only fills what is missing, so the art handover can be one species at a time | docs/09 §1 |
| 20 | Zone ring uses **10 reserved slots** at a derived radius of 950 | Zones 5–10 then land in their final positions without moving a landmark players have learned. Doc 02's hand-drawn compass arrangement is replaced by an even ring ordered by difficulty, which the doc itself asks for ("clockwise by difficulty") | docs/02 §1 |
| 21 | Nest positions come from a golden-angle spiral, not hand-placed anchors | Deterministic (players learn the map), evenly spread without random clustering, and provably non-overlapping even if `NestCount` is raised | docs/02 §2.3 |
| 22 | Carried eggs are **client**-owned physics, not server-owned as docs/09 §6 said | A part welded to a character joins that character's assembly; there is no way to keep server ownership. Safe because the model is cosmetic — the CarryToken is the only authority | docs/09 §6 |
| 23 | Carry state reaches the client through **model attributes**, not a new remote | The welded model is already replicated to everyone, so observers get the rarity aura for free and there is no extra packet to keep in sync with the truth. Avoids adding to the frozen remote list | docs/09 §3 |
| 24 | Nest prompts fire `NestService.PickupRequested` instead of claiming directly | Step 7 wired them straight to `ClaimEgg` as a standalone test. Claiming without minting a token destroys an egg and gives nothing, so the whole pickup belongs to `EggService` | — |
| 25 | Guardians are **anchored and moved by CFrame**, not driven by `Humanoid:MoveTo` as docs/09 §6 said | The placeholder models have no rig, a Humanoid each costs far more than the steering does, and CFrame movement is unambiguously server-authoritative — no assembly whose ownership could drift to a client | docs/09 §6 |
| 26 | The guardian cap **recycles the longest-running chase**; no client-side Ghost Chase | A cosmetic guardian that cannot catch anyone is a lie the player eventually notices. Recycling bounds cost identically, guarantees every steal gets a real guardian, and letting the player who has run longest get away is a gift rather than a punishment | docs/09 §6 |
| 27 | Added `ZoneConfig.GuardianSpeedBonus` (+0.00 / +0.04 / +0.08 / +0.12) | Without it the risk skulls on a nest sign are decoration — see the finding below | docs/03 §2 |
| 28 | Guardian archetypes carry `CanGuard`; swimmers and apex tiers are excluded | A Plesiosaurus guarding a land nest cannot leave water and would stand motionless beside it. That is not a chase, it is a statue, and nothing throws | docs/03 §3 |
| 29 | Added `GameConfig.EggStorageCap` (50) | docs/10 bounded `Dinos` at 235 entries but never bounded `Eggs`. An unbounded table grows until a DataStore write fails — the worst failure mode, arriving late and looking like nothing | docs/10 §2 |
| 30 | docs/00's loop diagram amended: the chase resolves by **escape**, then you return home to bank | Measured: the 250-stud leash fires before the gate for ~92 % of park-to-zone angles. Guardians chasing across the map would be expensive and would make the leash dead code. The gate stays decisive for **player raids** | docs/00 §2, docs/03 §1.4 |
| 31 | `IncubationService.BeginIncubation`, not `.Start` | Every service's `Start(app)` belongs to Bootstrap's lifecycle. One function cannot be both the lifecycle hook and the public API | — |
| 32 | docs/05's worked income example corrected: **34,962** F/s, not 44,747 | It labelled its Feeding Trough multiplier "L8 (×2.1)", but §5 of the same document defines that track as +8 %/level — L8 is ×1.64 and ×2.1 would be L13. The example could not be reproduced from its own table, and its stated total was also 20 off its own arithmetic | docs/05 §2 |
| 33 | Added `Economy` as shared module #11; `DinosaurService.IncomeOf`/`SellValueOf` now re-export it | Same reasoning as `Patch` (#10). The client draws income floaters locally from the replicated profile rather than receiving a packet per tick, so it must reach exactly the number the server banks. A second implementation of a six-term multiplication chain drifts the first time either gains a term. The old names still work, so nothing that called them had to change | docs/09 §1 |
| 34 | A hatched dinosaur **auto-places** if a slot and a tile are free | Otherwise a new player's first hatch produces a park that looks identical and earns nothing until they find a placement menu that does not exist until Step 13. FTUE beat 8 promises visible income from the first hatch; auto-placement is what keeps that promise before there is any UI | docs/00 §3 |
| 35 | The Collection Totem's single prompt **collects if anything is banked, otherwise places the best stored dinosaur** | One prompt is the whole park interface until Step 13. Two prompts on one totem, one of which is usually a no-op, is worse than one that always does the useful thing | docs/12 §2 |
| 36 | `HUDController.ShowHatch` generalised to `ShowReveal(config)` | The offline-earnings summary is the same panel with different content. Two near-identical 90-line panel builders is where they drift apart | docs/08 §6 |
| 37 | Added `Stats` as shared module #12; eleven `EffectAt` call sites now read it | docs/13 asks for a "PlayerStats aggregation" and docs/11 §5 says each `Effect.Kind` is read into it. Six files were each doing their own version, and the ones with a rebirth grant or a cap folded it in locally — eleven places to forget the cap the twelfth time, failing silently as a stat that is wrong in one system only. Shared rather than server-only because the shop draws "now → next" on the client and it has to be the number the player actually gets | docs/09 §1, docs/11 §5 |
| 38 | Added `Profile.BankedRate` (schema field, no migration) | The bank pays for seconds that have already elapsed, so it must pay for them at the rate in force while they elapsed. Without it, any rate change pays retroactively — see finding 13. Added to `ProfileTemplate` rather than through a migration because docs/10 §3's own rule is that a new field with a sensible default is Reconcile's job, not a migration's. Withheld from replication: the client renders the *live* rate, which it derives from its own dinosaurs | docs/10 §1 |
| 39 | Rebirth costs rounded to 3 significant figures, like every other price | `250000 × 5.2^n` gives `6760000.000000001` at rebirth 3 and `182790400` at rebirth 5. A price is a thing a player reads and a thing a comparison is made against: unrounded, it renders with a tail of digits and a player holding exactly 6,760,000 cannot afford a 6,760,000 rebirth. Rebirth 5 moves 182,790,400 → 183,000,000 | docs/05 §6 |
| 40 | Added `GameConfig.LuckPerNode` (0.005) | It was an unnamed `0.005` inline in `EggService`. `Stats` folds it and the shop previews it, so it needed a name in the one place both can see | docs/10 §1 |
| 41 | The Bone Market and the gate defence board are built in world geometry | docs/02 §1.1 deferred the Bone Market to "the systems that need it"; this is that system. Both carry a `ShopBoard` attribute the client reads straight off the prompt — opening a menu is not a server concern, so there is no remote for it, and the purchase remotes validate the board independently anyway | docs/02 §1.1, docs/06 §5 |
| 42 | Added `Profile.Shrines` (schema field, no migration) | docs/02 §2.2 makes the shrine — not the purchase — what puts a zone on the Obelisk, so the two states are genuinely different and one table cannot hold both. Replicated, because the zone wheel has to draw the difference between *locked*, *paid for but never visited*, and *ready* | docs/10 §1 |
| 43 | **A teleport is refused while a guardian is chasing you** | docs/08 §2.2 says PARK "teleports you home" and docs/00 §3 makes teleports load-bearing for tempo — but a teleport that works mid-chase deletes the chase: steal, tap, bank, with the only risk in the game skipped by a button. Refusing it keeps exactly the split deviation #30 already drew: the chase resolves by escape, and the unopposed walk home afterwards is tax. Teleports remove the tax. Carrying an egg is *not* itself a reason to refuse — once you have escaped, you have earned the trip | docs/02 §2.2, docs/03 §1.4 |
| 44 | The locked-gate barrier is **cosmetic**; a positional check is the real gate | A part cannot be solid for one player and passable for another, so a barrier that actually blocked would block everyone forever. The client hides the ones it has unlocked (a client-side Transparency does not replicate) and `ZoneService` walks a trespasser back out at 2 Hz. Both halves ship together, and the server half is the one that is authoritative | docs/02 §2.1 |
| 45 | `ZoneService` is a submodule of `NestService`, not a service in the roster | docs/13 §Step 14 says "a small `ZoneService` inside `NestService`". It owns no loop of its own beyond the trespass sweep and works entirely on the world `NestService` built moments earlier, so `NestService` forwards `Init` and `Start` to it. Keeps the roster at the 24 docs/09 §2 publishes | docs/09 §1 |
| 46 | docs/00's loop timing corrected: **21 s typical / 33 s furthest**, not 23 s | Step 10 projected 23 s before the destinations existed. Measured against the real ones, the projection had priced a typical nest rather than the walk to the far side of a 350-stud zone. Still inside the 45-second target at every nest in the game, and less than half the 86 s on foot | docs/00 §3 |

## Verification

`./tests/run.sh` — syntax-checks all 55 source files and runs **2,768
assertions** outside Roblox. Last run: **2,768 passed, 0 failed.**

| Spec | Covers |
|---|---|
| `step1_spec` (83) | `Format`, `TableUtil`, `RNG`, `Signal`, `Trove` |
| `step2_spec` (150) | Template drift, migration chain + failure modes, full load path |
| `step3_spec` (731) | Every content number against the design docs, the full coverage matrix, and 18 deliberately broken configs the validator must reject |
| `step4_spec` (183) | The `Patch` round-trip property across 13 state transitions, depth limits, native key types, the replication allowlist against the real schema, and the settings schema |
| `step5_spec` (96) | The 64px touch-target guarantee across 12 real device viewports, scale and breakpoint maths, design-token ordering |
| `step6_spec` (142) | Tile round trip for all 64 tiles, footprint bounds for every size at every anchor, plot ring non-overlap at 24 and 48 plots, and the plot depth budget |
| `step7_spec` (356) | Zone ring clearance at the full 10-zone build-out, deterministic nest spacing, sign odds against the real weight tables, guardian selection, risk ratings |
| `step8_spec` (96) | The published carry-speed table line by line, multi-carry stacking, Strong Back, luck composition and caps, roll distributions, the luck tail guard |
| `step9_spec` (274) | Archetype table integrity, guardian eligibility, the escape guarantee, and a simulated straight-line chase for every archetype in Zone 1 and Zone 4 |
| `step10_spec` (31) | Storage bounds, deposited-egg shape against the schema, travel distances, how often being chased home is reachable, and measured loop tempo |
| `step11_spec` (298) | Mutation distributions against published weights, Prime pairing and ceiling, weather modifiers, species-roll coverage for every zone × rarity, the master income formula, the incubation ladder |
| `step12_spec` (57) | Footprint occupancy under a fully packed grid, the banking formula against its own cap, offline earnings at every rebirth level, slot caps, and the day-one income curve measured against docs/05 §8 |
| `step14_spec` (76) | Every unlock gate against docs/02 §2.1, all four gate kinds driven through an injected zone, teleport destinations proven to land outside the zone they travel to, zone-square clearance against the park ring, the re-measured loop tempo, and the Day-1-reaches-Zone-4 claim against the published income curve |
| `step13_spec` (100) | Every price in the game against integrality, monotonicity and determinism; all 14 published max effects; `Stats.Of` against every single-field helper on three profiles; the Upgrades/Defences split asserted in both directions; Buy Max bounds and the never-negative rule; the retroactive-income guard; and docs/05 §5's 180-second constraint measured across a rebirth run |

Bugs the specs caught before they shipped:

1. `ProfileTemplate.ExpectedKeys` was declared *inside* the template table,
   so Reconcile would have written that helper list into every player's save.
   The template now contains nothing but profile fields, and the spec asserts
   it (including that no function appears anywhere in it).
2. `Migrations.CurrentVersion()` used `#Migrations.Chain`. The `#` operator is
   undefined on a table with a hole, so adding migration 3 while forgetting 2
   would report a silently wrong version. Replaced with an explicit contiguous
   walk plus `Migrations.Validate()`, which `DataService` asserts at boot.
3. Validator rule 6 fired immediately on the first V1 content pass, exactly as
   predicted in the blueprint: every zone carried Mythic and Ancient weight
   while V1 ships no species in those tiers, and Zone 1 rolled Epic and
   Legendary with nothing in range to hatch. Resolved by deviations #6 and #7
   rather than by weakening the rule.
4. `Replication.Flush` called `require(script.Parent)` inside the 5 Hz loop.
   Safe, but a require in a hot path; hoisted into `Init`, where the parent has
   provably finished loading.
5. The first HUD scale pass applied its touch-target floor only below a 700px
   width, so an iPhone 14 in landscape (844px) fell past it and would have got
   61px buttons — under the documented 64px minimum. The floor is now derived
   from `MinTouchTarget / BottomButtonHeight` and applies universally, making
   the guarantee structural rather than dependent on a device check being
   right. Asserted across 12 real viewports.
6. `PlotBuilder` used `CFrame.lookAt(position, hubCentre)` to orient plots.
   `CFrame.LookVector` is the CFrame's local **−Z**, so that put every park's
   gate, incubator row and spawn pad facing *away* from the hub. The LookVector
   now aims outward so local +Z faces the hub.
7. The first plot layout had a 96-stud enclosure grid inside a 120-stud plot
   with a −14 offset, so it poked 2 studs through the back wall, and the vault
   row sat on top of it. Neither throws — it renders as dinosaurs clipping into
   pedestals. Tile size is now 10 and the whole depth budget is asserted.
8. `NestBuilder.RespawnEgg` recovered the nest's anchor position by un-rotating
   the bowl's CFrame. That works until the bowl changes shape, then respawned
   eggs drift somewhere else. The anchor is now stored as an attribute, and one
   `createEgg` path serves both the initial build and respawn — two
   construction paths is two sets of attributes to forget to set.
9. Step 7 left nest prompts wired straight to `NestService.ClaimEgg`. Once
   Step 8 introduced carry tokens that became a bug that destroys an egg and
   hands the player nothing — the prompt now fires a signal `EggService` owns.

10. **The chase did not work.** The Step 9 simulation showed that *no guardian
    could catch a player running in a straight line* — every archetype ratio
    sits at or below 1.04, and the two-second acceleration ramp costs more
    ground than 1.04 recovers in forty seconds. Zone difficulty was purely
    cosmetic: a Zone 4 chase was identical to a Zone 1 one. Three fixes, all
    driven by the measurement:
    - `ZoneConfig.GuardianSpeedBonus` scales guardians by zone, so the risk
      skulls mean something.
    - Ability **wind-ups** at 30 % speed — the tell that makes "dodge sideways"
      possible, and the cost that keeps a 1.8× charge fair.
    - Abilities wait **one full cooldown** before first use. A Charger that
      charged on frame one closed an 18-stud head start in three seconds,
      before the player had run anywhere.

    Result: Zone 1 catches 3 of 13 fleeing thieves (17.5–26.4 s), Zone 4
    catches 10 of 13 (9.6–19.5 s). Every one inside the 10–30 second window
    docs/00 publishes.

11. **The map is too big to walk the loop.** Measured park-gate-to-nest
    distances: 177 studs when a park happens to face a zone, **576 typical**,
    1,443 opposite. That makes the walking micro-loop **86 seconds** against
    docs/00's 45-second target. This is not a bug to fix by shrinking the map —
    docs/02 already puts a Zone Shrine in every zone that registers it on the
    Teleport Obelisk, and docs/08 puts a PARK button on the bottom bar. With
    both, the loop is **23 seconds**. Step 14 is therefore load-bearing for the
    game's tempo, not a convenience, and docs/00 now says so.

12. **A documented example the code could not reproduce.** Asserting docs/05's
    worked income calculation against the implementation failed: the example
    used a Feeding Trough multiplier of ×2.1 while labelling it L8, but the
    upgrade track in the same document gives L8 = ×1.64. Both the label and the
    stated total were wrong. This is the kind of error that quietly erodes
    trust in an economy document, because every number in it looks equally
    authoritative — the spec now pins the example *and* the multiplier it
    depends on, so changing the track fails here rather than silently
    invalidating the doc.

13. **docs/05's headline curve is not reachable by placing dinosaurs.** The
    Step 12 spec started by checking only the *shape* of early income, which
    passed while sitting four to five times under the published table. Pushing
    the check to reproduce docs/05 §8's actual rows showed why: the 5-minute
    and 20-minute rows come out of placement alone, but the 1-hour row (380
    F/s from 10 dinosaurs) cannot — ten Rares are 300 F/s. It becomes
    reachable at Feeding Trough L3, ×1.24, which costs about 10.8 K against
    the 95 K that row says has been earned. So the table was right and its
    framing was wrong: it describes a player who has been *spending*, which
    its own "First upgrade" milestone at five minutes already implies. The
    document now says so, and the spec pins all three rows plus the multiplier
    they depend on. Worth recording because the first version of this check
    would have passed forever without noticing.

14. **The bank could be made to pay retroactively — a money printer.** The
    lazy bank computed `BankedFossils + rate × (now − BankedAt)` using the
    rate *at the moment of reading*. So a player could idle with a weak park
    for a full bank period, place their best dinosaur, and have the entire
    idle window instantly re-pay at the new rate: a full bank, for free, and
    repeatable by storing and re-placing. Buying Feeding Trough did the same
    thing without even needing a dinosaur.

    Found while building Step 13, because buying an income upgrade is a rate
    change and the step could not be correct without answering it. The fix is
    a schema field: `BankedRate` is frozen when the interval opens, accrual
    uses it, and `EconomyService.SettleBank` closes the interval at the old
    rate before anything changes it. The mirror case is fixed too — the cap
    now bounds *accrual* rather than the stored balance, so storing a dinosaur
    shrinks the cap without confiscating money already banked.

15. **The three defence tracks would have read as level 0 forever.** docs/10 §1
    puts them in `data.Defences`; every other track is in `data.Upgrades`. The
    first draft of `Stats` read `data.Upgrades` for all fourteen. A bought
    Fence would have applied nothing at all, silently, and nobody would have
    found out until someone raided a park in Step 15. `UpgradeConfig.StoreFor`
    now owns the answer, and the spec asserts it in both directions — that a
    level in `Defences` counts, and that one misfiled into `Upgrades` does not.

16. **docs/05 §5's hard constraint, measured.** "At every point in the curve,
    the cheapest un-maxed upgrade costs less than 180 seconds of the player's
    current income."

    My first model said it failed badly — 37 of 160 purchases over the limit,
    worst case a 64-minute wait. That model was wrong: it ignored rebirth,
    and `Upgrades` and `Defences` are both absent from
    `RebirthConfig.Preserved`, so the tree resets on every rebirth. A run is
    the only window in which "the cheapest un-maxed upgrade" means anything.

    Re-measured to the published Rebirth 1 at three hours: **the constraint
    holds for the whole FTUE window (88 levels, worst wait 148 s, zero
    breaches), and for 115 of 116 purchases across a full run.** The single
    exception is Feeding Trough L13 at 2 h 51 m — 874,000 Fossils against
    ~4,700/sec, so 185 s against a target of 180. A 3 % overshoot, at the last
    purchase before the player rebirths anyway.

    Left as-is and written up rather than silently retuned: dropping that
    track's growth from 1.66 to 1.65 closes it, at the cost of a slightly
    cheaper income multiplier, and that trade is a design call rather than a
    test to be edited. The spec asserts "at most one breach, and under 189 s",
    so a content change that makes it materially worse fails loudly.

    The same measurement produced the number that explains why rebirth exists:
    **maxing every track in the game costs 1.67 B Fossils, while rebirth 1
    costs 250 K.** The upgrade tree is deliberately two thousand times cheaper
    than the first reset, which is what makes the reset the real sink.

17. **Rebirth costs were floats.** `250000 × 5.2^n` gives
    `6760000.000000001` at rebirth 3. Upgrade prices go through
    `RoundSignificant`; rebirth prices did not, so they would have rendered
    with a tail of digits and a player holding exactly 6,760,000 Fossils would
    have been told they could not afford a 6,760,000 rebirth. Now rounded the
    same way, and asserted as exact whole numbers rather than "near" — which
    is what caught it, since step3_spec had pinned the raw float.

18. **Teleporting would have deleted the chase.** docs/08 §2.2 gives the PARK
    button one job — "teleports you home" — and docs/00 §3 makes teleports
    load-bearing for the loop's tempo. Neither document says what happens if
    you press it *while a guardian is chasing you*, and the obvious
    implementation lets you: steal an egg, tap PARK, bank it. That is the
    entire risk of the core loop removed by a button, and it would not have
    thrown, failed a test, or looked wrong in a screenshot.

    Resolved by refusing a teleport while a chase is active — which turns out
    to be exactly the line deviation #30 already drew in Step 9: the chase
    resolves by *escape*, and the walk home afterwards is unopposed. Teleports
    remove the unopposed walk, which is tax, and leave the escape, which is
    the game. Carrying an egg is deliberately *not* itself a reason to refuse.

    Step 15's raid case is the same shape, so the check is a registry
    (`ZoneService.RegisterBlocker`) rather than a hardcoded condition.

19. **The loop is 33 seconds, not the 23 I projected.** Step 10 recorded that
    zone teleports and the PARK button would bring the walking loop from 86 s
    to 23 s. Measured against destinations that now exist rather than against
    a plan, it is **21 s to a typical nest and 33 s to the furthest one** —
    because the projection had priced a typical nest rather than the walk to
    the far side of a 350-stud zone. Still inside docs/00's 45-second target
    at every nest in the game, and less than half the on-foot figure, so the
    conclusion stands and the number was wrong. docs/00 now carries both
    figures and says which is which.

20. **Zone squares clear the park ring by 70 studs.** Step 7 asserted zones do
    not overlap *each other*; nothing had checked zones against parks, because
    they were built by different modules in different steps. It matters from
    this step on: `ZoneService` shoves anyone standing inside a locked zone
    back out, so a zone square reaching the park ring would teleport a player
    out of their own park, repeatedly, with a toast telling them their park is
    locked. Measured: park outer edge 633, nearest zone corner 703. Asserted
    both analytically and by sampling all 24 plot centres, so a change to
    either ring's radius fails here rather than in someone's park.

**Known gap, stated rather than faked:** docs/02 wants zone difficulty to come
partly from localised hazards — mud pools at −35 %, ice momentum. Those need
real geometry that the blockout does not have, and a blanket zone-wide slow
would do nothing, because guardian speed is sampled from the thief's already-
slowed speed. So today the entire difficulty curve rests on
`GuardianSpeedBonus`. The hazards pass is still owed.

**One thing the specs surfaced that is worth knowing, not fixing:** with Mythic
and Ancient zeroed for V1, the highest luck powers in play are Legendary and
Secret, both 0.55 — so a maxed-luck V1 player improves their Secret odds as much
as their Legendary odds. At 1 in 5,263,158 in Zone 1 that is a rounding error in
absolute terms, and it corrects itself when those tiers ship in V1.1/V1.3. The
tail guard proper (Secret and Titan gain less than Mythic and Ancient) is
asserted against the design-target weights, since it cannot be measured on a
vector where those tiers are zero.

Not covered offline (need Roblox): `Net`, `Log`, both Bootstraps, and every
ProfileStore-dependent path. See the Studio test lists in SETUP.md.

## Open questions for the developer

1. **Roblox place / experience** — is one created yet? Gamepass and dev product
   IDs in `ProductConfig` are placeholders until it exists.
2. ~~**ProfileStore dependency**~~ — **resolved:** using ProfileStore. Verify the
   API surface listed in SETUP.md against the version you install.
3. **Art pipeline** — are dinosaur models being made, commissioned, or bought
   from the Creator Store? This determines whether Step 7 blocks on assets.
4. **Team size and target launch date** — changes how aggressively V1 should be
   trimmed further.

Only #3 blocks anything, and not until Step 7.
