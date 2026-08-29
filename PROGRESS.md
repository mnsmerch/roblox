# Build Progress

Running record of everything that exists, so nothing gets renamed or rebuilt by
accident. Updated at the end of every build step.

## Status: **Step 7 of 24 complete.** Awaiting the Studio Play test before Step 8.

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
| 8 | Egg pickup & carrying | ⬜ |
| 9 | Guardian AI & the chase | ⬜ |
| 10 | Safe zone & deposit | ⬜ |
| 11 | Incubation & hatching | ⬜ |
| 12 | Placement & income | ⬜ |
| 13 | Upgrades & shop | ⬜ |
| 14 | Zones & teleports | ⬜ |
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
| `Modules/Types` | ModuleScript | Luau types incl. the full `Profile` shape |
| `Modules/Log` | ModuleScript | `Log.debug/info/warn/error/banner(scope, msg, ...)` |
| `Modules/Signal` | ModuleScript | `new/Connect/Once/Fire/Wait/DisconnectAll` |
| `Modules/Trove` | ModuleScript | `new/Add/Connect/Extend/Remove/Clean` |
| `Modules/TableUtil` | ModuleScript | `DeepCopy/Reconcile/Merge/Count/SortedKeys/DeepFreeze/DeepEquals` |
| `Modules/Format` | ModuleScript | `Number/Comma/Time/Clock/Odds/Percent/Multiplier` |
| `Modules/RNG` | ModuleScript | `new/WeightedPick/ApplyLuck/ApplyModifiers/Chance/Shuffle/Pick/ProbabilityOf` |
| `Modules/Net` | ModuleScript | Remote inventory, rate limits, arg validation |
| `Modules/Patch` | ModuleScript | Structural diff + apply, shared by both sides of replication |
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
| `HUDController` | ModuleScript | Top bar, rails, bottom bar, action prompt; binds via Observe |
| `InputController` | ModuleScript | Keyboard/gamepad/touch → named actions |

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

## Verification

`./tests/run.sh` — syntax-checks all 39 source files and runs **1,824
assertions** outside Roblox. Last run: **1,824 passed, 0 failed.**

| Spec | Covers |
|---|---|
| `step1_spec` (83) | `Format`, `TableUtil`, `RNG`, `Signal`, `Trove` |
| `step2_spec` (150) | Template drift, migration chain + failure modes, full load path |
| `step3_spec` (731) | Every content number against the design docs, the full coverage matrix, and 18 deliberately broken configs the validator must reject |
| `step4_spec` (183) | The `Patch` round-trip property across 13 state transitions, depth limits, native key types, the replication allowlist against the real schema, and the settings schema |
| `step5_spec` (96) | The 64px touch-target guarantee across 12 real device viewports, scale and breakpoint maths, design-token ordering |
| `step6_spec` (142) | Tile round trip for all 64 tiles, footprint bounds for every size at every anchor, plot ring non-overlap at 24 and 48 plots, and the plot depth budget |
| `step7_spec` (356) | Zone ring clearance at the full 10-zone build-out, deterministic nest spacing, sign odds against the real weight tables, guardian selection, risk ratings |

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
