# Build Progress

Running record of everything that exists, so nothing gets renamed or rebuilt by
accident. Updated at the end of every build step.

## Status: **Step 2 of 24 complete.** Awaiting the Studio Play test before Step 3.

## Completed

| Date | Item | Notes |
|---|---|---|
| 2026-08-29 | Game Design Blueprint (docs 00–15) | Full design, economy, architecture, MVP, build order |
| 2026-08-29 | **Step 1** — project skeleton & shared modules | 11 files, 83 offline assertions |
| 2026-08-29 | **Step 2** — DataService & PlayerDataService | ProfileStore-backed persistence, 150 more assertions |

## Build steps (see docs/13-build-order.md)

| Step | Name | Status |
|---:|---|---|
| 1 | Project skeleton & shared modules | ✅ **done** |
| 2 | DataService & PlayerDataService | ✅ **done** |
| 3 | Config modules & ConfigValidator | ⬜ |
| 4 | State replication | ⬜ |
| 5 | HUD skeleton | ⬜ |
| 6 | Park plots | ⬜ |
| 7 | Nests & the world | ⬜ |
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
| `Modules/Types` | ModuleScript | Luau types incl. the full `Profile` shape |
| `Modules/Log` | ModuleScript | `Log.debug/info/warn/error/banner(scope, msg, ...)` |
| `Modules/Signal` | ModuleScript | `new/Connect/Once/Fire/Wait/DisconnectAll` |
| `Modules/Trove` | ModuleScript | `new/Add/Connect/Extend/Remove/Clean` |
| `Modules/TableUtil` | ModuleScript | `DeepCopy/Reconcile/Merge/Count/SortedKeys/DeepFreeze/DeepEquals` |
| `Modules/Format` | ModuleScript | `Number/Comma/Time/Clock/Odds/Percent/Multiplier` |
| `Modules/RNG` | ModuleScript | `new/WeightedPick/ApplyLuck/ApplyModifiers/Chance/Shuffle/Pick/ProbabilityOf` |
| `Modules/Net` | ModuleScript | Remote inventory, rate limits, arg validation |
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
PlayerDataService.Save(player, reason)
PlayerDataService.GetAll() -> {[Player]: data}
PlayerDataService.ProfileLoaded     Signal(player, data)
PlayerDataService.ProfileUnloading  Signal(player, data)
PlayerDataService.Changed           Signal(player, reason)
```

Rule for later steps: **reads use `Get`, writes use `Update`.** Step 4's
replication layer listens to `Changed`, so a write that bypasses `Update` is a
write the client never hears about.

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

## Verification

`./tests/run.sh` — syntax-checks all 15 source files and runs **233 assertions**
outside Roblox. Last run: **233 passed, 0 failed.**

| Spec | Covers |
|---|---|
| `step1_spec` (83) | `Format`, `TableUtil`, `RNG`, `Signal`, `Trove` |
| `step2_spec` (150) | Template drift, migration chain + failure modes, full load path |

Bugs the specs caught before they shipped:

1. `ProfileTemplate.ExpectedKeys` was declared *inside* the template table,
   so Reconcile would have written that helper list into every player's save.
   The template now contains nothing but profile fields, and the spec asserts
   it (including that no function appears anywhere in it).
2. `Migrations.CurrentVersion()` used `#Migrations.Chain`. The `#` operator is
   undefined on a table with a hole, so adding migration 3 while forgetting 2
   would report a silently wrong version. Replaced with an explicit contiguous
   walk plus `Migrations.Validate()`, which `DataService` asserts at boot.

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
