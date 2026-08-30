# Build Progress

Running record of everything that exists, so nothing gets renamed or rebuilt by
accident. Updated at the end of every build step.

## Status: **Step 23 of 24 complete.** The loop is playable, resettable, purchasable, ranked and taught. Awaiting the Studio Play tests before Step 24.

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
| 2026-08-30 | **Step 15** — player raiding | The full raid state machine, shields, Vault, 109 more assertions |
| 2026-08-30 | **Step 16** — notifications & announcements | Four severities, the queue, MessagingService, 87 more assertions |
| 2026-08-30 | **Step 17** — weather | 4 weathers, the 8-minute roll, local Lighting, 85 more assertions |
| 2026-08-30 | **Step 18** — server events | Scheduler, 4 handlers, contribution rewards, 98 more assertions |
| 2026-08-30 | **Step 19** — quests, dailies, Index | UTC days, streaks, milestones, 281 more assertions |
| 2026-08-30 | **Step 20** — rebirth | The one-write reset, the shared preview, 124 more assertions |
| 2026-08-30 | **Step 21** — purchases | 6 passes, 8 products, the receipt ring, 162 more assertions |
| 2026-08-30 | **Step 22** — leaderboards | 4 boards, the throttle, the Colosseum, 113 more assertions |
| 2026-08-30 | **Step 23** — tutorial | 12 beats, four bends, the server-owned step, 259 more assertions |

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
| 15 | Player raiding | ✅ **done** |
| 16 | Notifications & announcements | ✅ **done** |
| 17 | Weather | ✅ **done** |
| 18 | Server events | ✅ **done** |
| 19 | Quests, dailies, index | ✅ **done** |
| 20 | Rebirth | ✅ **done** |
| 21 | Purchases | ✅ **done** |
| 22 | Leaderboards | ✅ **done** |
| 23 | Tutorial | ✅ **done** |
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
| `Config/NotificationConfig` | ModuleScript | The 4 severities, queue limits, publish budget, payload sanitising |
| `Config/WeatherConfig` | ModuleScript | 4 V1 weathers: weights, durations, non-mutation effects |
| `Config/EventConfig` | ModuleScript | 4 V1 events: weights, durations, params, handler names |
| `Config/QuestConfig` | ModuleScript | 12 daily + 6 weekly quests; the metric list QuestService asserts against |
| `Config/DailyConfig` | ModuleScript | The 7-day chest, streak milestones, boost definitions |
| `Config/IndexConfig` | ModuleScript | Milestones, rarity sets, and a **counted** completion denominator |
| `Config/ProductConfig` | ModuleScript | 6 gamepasses + 8 products, their effects, and **no invented asset ids** |
| `Config/LeaderboardConfig` | ModuleScript | 4 boards, the value ceiling, and the budget arithmetic that sets the schedule |
| `Config/TutorialConfig` | ModuleScript | The 12 beats, the four bends, and the advance check — all pure |
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
| `Modules/Stats` | ModuleScript | Every derived player number: upgrades + rebirth grants + boosts + caps. Pure |
| `Modules/Time` | ModuleScript | UTC day and week indices, and the three streak cases. Pure |
| `Modules/AssetBuilder` | ModuleScript | Placeholder egg + dinosaur models; only fills what is missing |
| `SAD_Assets/{Dinos,Eggs,Effects,UI}` | Folders | Empty until Step 7 |

### Created at runtime (do NOT build by hand)

`ReplicatedStorage/SAD_Net` with `Events` (29 client→server + 11 server→client
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
| `Services/StealService` | ModuleScript | The raid state machine, tagging, shields, Vault, insurance |
| `Services/NotificationService` | ModuleScript | The one place a notification is created |
| `Services/BroadcastService` | ModuleScript | **The only file that knows MessagingService exists** |
| `Services/WeatherService` | ModuleScript | The roll, the countdown, and every effect that changes an outcome |
| `Services/EventService` | ModuleScript | Scheduler, participation, scoreboards, rewards |
| `Services/EventService/Handlers` | Folder | `MeteorImpact`, `Stampede`, `NestFrenzy`, `AmberRain` |
| `Services/QuestService` | ModuleScript | Rolls, progress, claims, rerolls |
| `Services/QuestService/RewardGrant` | ModuleScript | **The one place a reward is paid out** |
| `Services/DailyService` | ModuleScript | The 7-day chest and the streak |
| `Services/IndexService` | ModuleScript | Discovery, completion %, milestones and rarity sets |
| `Services/RebirthService` | ModuleScript | Eligibility, the one-write reset, grants, the Cache |
| `Services/PurchaseService` | ModuleScript | **The only file that touches MarketplaceService.** Receipts, ownership, server boosts |
| `Services/LeaderboardService` | ModuleScript | **The only file that touches OrderedDataStore.** Throttled writes, the 60 s read cache |
| `Services/TutorialService` | ModuleScript | Owns the step number; checks every advance against real state |

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
StealService.IsCarrying(player) -> token?
StealService.CanRaid(thief, ownerUserId) -> ok, reason?
StealService.HoldSecondsFor(thief, ownerData, ownerUserId) -> seconds
StealService.Begin(thief, ownerUserId, dinoUid) -> ok, reason?
StealService.Cancel(thief, reason?)
StealService.Tag(tagger, thiefUserId) -> ok, reason?
StealService.IsLocked(ownerUserId, uid) -> boolean
StealService.Vault(player, uid, slot) -> ok, reason?
StealService.GrantShield(player, seconds, reason) -> until
StealService.IsShielded(data, now?) -> boolean
StealService.StealStarted / StealCompleted / StealFailed   Signals

Stats.SecurityLevel(data) -> 0..5      -- defence board sum / 4
Stats.RaidHoldSecs(data) -> seconds    -- 3 + SecurityLevel x 1.2

ParkService.DinoRendered  Signal(owner, uid, model)
DinosaurService.Create(player, params)  -- params.Acquired = "hatch" | "steal"
```

**The dinosaur never leaves its owner until the gate.** While carried it stays
in the owner's profile — taken off the grid, and locked server-side against
sale, vaulting and storage. The carry is a token in server memory only. So
there is no moment when it belongs to nobody, and a crash mid-carry leaves it
with its owner rather than deleting it.

**The consequence, stated plainly:** the owner must be online for a raid to
complete. If they leave mid-carry the raid voids. This follows from docs/03
§4.3's "offline parks are fully raid-immune", and it does mean a player can
save a dinosaur by disconnecting — see the note under Open questions.

```
NotificationService.Toast(player, title, subtitle?, opts?)
NotificationService.Banner(player, text, opts?)
NotificationService.Takeover(player, { Title, Subtitle, Headline, ... })
NotificationService.Alert(player, text, opts?)      -- until Clear
NotificationService.Clear(player, tag)
NotificationService.Send(player, payload)           -- the raw form
NotificationService.All(payload, exclude?)          -- this server
NotificationService.Announce(payload)               -- every server
NotificationService.GetCounts() -> { toast, banner, takeover, alert }

BroadcastService.Publish(payload) -> queued
BroadcastService.IsAvailable() -> boolean
BroadcastService.GetStats() -> { Published, Dropped, Received, Failed }
BroadcastService.Received  Signal(payload)

NotificationConfig.Severities / Order / Fallback / UntilResolved
NotificationConfig.Resolve(kind?) -> kind
NotificationConfig.DurationOf(kind, override?) -> seconds
NotificationConfig.Outranks(a, b) -> boolean
NotificationConfig.Sanitise(payload) -> payload?

NotificationController.Handle(payload)
NotificationController.Clear(tag)
NotificationController.GetQueueDepth() -> number

SoundController.Play(slot, opts?) -> played
SoundController.PlayNotification(kind) -> played
SoundController.SetCategoryVolume(category, volume)
SoundController.IsAvailable(slot) -> boolean
```

**Severity is a server decision; the queue is a client one.** The client never
promotes a toast into a takeover — a client that could decide what was worth
dimming the screen for is a client that can dim everyone's screen for nothing.
What it owns is how many fit, what drops, and what this player has muted.

**`NotificationConfig.Sanitise` runs on both sides.** The server sanitises on
the way out and the client on the way in — the same function, so a payload that
arrived over `MessagingService` has exactly the guarantees a local one does.

**No asset ids are invented.** `SoundController` names 12 slots and looks each
one up by name in `SAD_Shared/SAD_Assets/Sounds`. Drop a `Sound` named `Hatch`
in and hatching has a sound; until then the call is a no-op. Same stance
`AssetBuilder` takes for models.

```
WeatherConfig.Weathers / Order / RollInterval / CountdownSecs / MinClearGapSecs
WeatherConfig.Get(weatherId?) -> entry
WeatherConfig.RollableWeights() -> { [id] = weight }
WeatherConfig.ClearShare() -> fraction
WeatherConfig.EffectOf(weatherId?, key, default) -> value
WeatherConfig.ZoneBoost(weatherId?, zoneId?) -> multiplier
WeatherConfig.DurationOf(weatherId?) -> seconds

WeatherService.Current() -> weatherId
WeatherService.EndsAt() -> os.time()
WeatherService.Set(weatherId, durationSecs?)
WeatherService.Roll() -> weatherId
WeatherService.EffectOf(key, default) -> value
WeatherService.Changed  Signal(weatherId, endsAt)

MutationService.RollIn(mutLuck, weatherId?, rng?, zoneId?)   -- zoneId is new
MutationService.Roll(player, zoneId?)                        -- zoneId is new
NestService.RespawnMultiplier() -> number

WeatherController.OnWeatherChanged(info)
WeatherController.Current() / Remaining()
```

**Effects are server truth; visuals are local.** Everything that changes an
outcome — mutation weights, walk speed, nest respawn, lightning — happens in
`WeatherService`. The sky happens in `WeatherController`, on each client, from
the replicated weather id.

**Mutation weights are still only in `MutationConfig.WeatherModifiers`.**
`WeatherConfig` holds weights, durations and non-mutation effects. Two tables
describing one thing is what deviation #5 removed elsewhere, so this pair only
survives because ConfigValidator rule 11 asserts they name the same weathers
at boot.

```
EventConfig.Events / Order / MinGapSecs / MaxGapSecs / CountdownSecs
EventConfig.CountdownBeats / NoRepeatWithin / MinRewardIncomeSecs
EventConfig.Get(eventId?) -> entry?
EventConfig.RollableWeights(exclude?) -> { [id] = weight }
EventConfig.ExclusionDepth() -> number     -- clamped to leave two choices
EventConfig.Param(eventId, key, default) -> value

EventService.Current() -> entry?
EventService.EndsAt() -> os.time()
EventService.Begin(eventId) -> ok, reason?    -- NOT Start; see deviation #61
EventService.Stop(reason?)
EventService.Score(player, points)
EventService.GetScores() -> { { Player, Name, Score } }   sorted
EventService.Roll() -> eventId?
EventService.Started / Ended   Signals

EggService.SpawnEventEgg(params, position) -> uid
RarityConfig.TierAbove(rarityId, steps?) -> rarityId
MutationService.RollIn(mutLuck, weatherId?, rng?, zoneId?, guaranteed?)
NestService.EventRespawnMultiplier   -- a field, set and restored by a handler
WildAIService.EventSpeedMultiplier   -- likewise
HUDController.SetEventBanner(text?, priority?)
HUDController.BannerPriority = { Weather = 1, Event = 2 }
```

**The handler pattern.** One ModuleScript per event in `EventService/Handlers`,
named by `EventConfig`'s `Handler` field, returning `Start(ctx)` / optional
`Tick(ctx, dt)` / `Stop(ctx)`. `ctx` carries the entry, its Params, a Trove
that `Stop` must leave empty, `ctx.Get(name)` for other services, and
`ctx.Score(player, points)` — the only way to record participation. A handler
never touches profiles, currency or notifications.

**Rewards are granted once, to whoever is still here.** Participation is keyed
by the Player *object* and lives only in memory for one event, so a rejoin is
a different key with no score. Rewards are paid and the table cleared in one
step.

```
Time.DayIndex(now) / WeekIndex(now)            -- UTC, integer division
Time.SecondsUntilNextDay(now) / NextWeek(now)
Time.StreakState(lastClaimDay, today) -> "continue" | "same" | "break"

QuestConfig.Find(questId) -> kind, quest       -- ids are unique across pools
QuestConfig.ScaleFossils(base, rebirths)
DailyConfig.RewardFor(dayIndex) / StreakRewardAt(streak) / GetBoost(id)
IndexConfig.Total(dinoConfig) / Discovered(data) / CompletionPercent(data, cfg)
IndexConfig.PendingMilestones(data) / PendingSets(data, dinoConfig)

QuestService.Refresh(player, now?)
QuestService.Bump(player, metric, amount?)
QuestService.Claim(player, questId) -> ok, reason?
QuestService.Reroll(player, questId) -> ok, reason?
QuestService.ValidateEmitters() -> problem?    -- asserted at Start
QuestService.RewardGrant                       -- shared with the other two
QuestService.QuestCompleted  Signal(player, kind, questId)

DailyService.Available(data, now?) -> ok, reason?
DailyService.NextDayIndex(data, now?) -> 1..7
DailyService.Claim(player, now?) -> ok, reason?
DailyService.Claimed  Signal(player, dayIndex, streak, summary)

IndexService.Completion(data) / Discovered(data) / Total()
IndexService.CheckMilestones(player) -> granted
IndexService.SpeciesDiscovered  Signal(player, speciesId, entry)

RewardGrant.Give(player, reward, reason) -> summary
Stats.BoostTotal(data, kind, now?) -> number
```

**One emitter table, not fifteen listeners.** Every quest is a `Metric` and a
`Target`; `QuestService.EMITTERS` maps each metric to the signal that
increments it, and `ValidateEmitters` asserts at boot that the two sets are
identical. A metric with no emitter is a quest nobody can finish; an emitter
with no metric is a counter nobody reads. Neither throws, so boot refuses both.

**Claims are marked before they are granted.** Quests, dailies and Index
milestones all do this in the same order, and it is the whole defence against
double-claim: two calls racing both read an unclaimed state, but only the first
write survives to reach the reward.

**Rewards are data, paid by one function.** `RewardGrant.Give` is the only code
that reads a reward table. Written three times, the rebirth scaling gets
applied in two of them and the third pays a flat rate forever.

```
RebirthConfig.Preserved / Reset / Partial     -- keyed tables of REASONS
RebirthConfig.Validate(template) -> problem?  -- asserted at boot
RebirthConfig.ZonesAfter(unlocked, rebirths, zoneConfig) -> kept, lost
RebirthConfig.DinosAfter(data) -> kept
RebirthConfig.CacheRarity(data, rarityConfig) -> rarityId?
RebirthConfig.Preview(data, zoneConfig, rarityConfig) -> { Cost, Keeps, Loses, Gains }

RebirthService.CanRebirth(player) -> ok, reason?, requirements
RebirthService.Preview(player) -> preview
RebirthService.Perform(player) -> ok, reason?
RebirthService.Rebirthed  Signal(player, newCount)

DataService.Template                          -- the ProfileTemplate, read-only
```

**Every profile field is classified exactly once.** `Preserved`, `Reset` and
`Partial` must together cover the whole template, and `RebirthService` refuses
to start if they do not. A new field cannot default to being destroyed — the
same discipline the replication allowlist uses.

**The preview is pure and shared.** `RebirthConfig.Preview` is what the confirm
screen draws and what the reset performs. On the one screen where a player
deletes their park on the strength of what it says, two implementations is a
contract the game might not honour.

**One write.** `Perform` decides everything first — what survives, what returns
to its default, the Cache egg — and applies it in a single `UpdateKeys`
callback that does no arithmetic and yields nowhere. There is no state the
profile can be left in halfway.

### Step 21 — purchases

```
ProductConfig.Gamepasses / Products           -- keyed by OUR string key, never the asset id
ProductConfig.GetPass(key) / GetProduct(key)
ProductConfig.ByAssetId(assetId) -> kind, entry
ProductConfig.IsConfigured(entry) -> boolean  -- AssetId > 0
ProductConfig.Unconfigured() -> passes, products
ProductConfig.EffectModes                     -- add | multiply | max, per effect
ProductConfig.EffectTotal(owned, effect, default) -> number
ProductConfig.HasPass(owned, key) -> boolean
ProductConfig.CountPasses() / CountProducts() -> number

PurchaseService.Owns(player, key) -> boolean
PurchaseService.RefreshOwnership(player)
PurchaseService.Prompt(player, key)
PurchaseService.Thank(player, buyerUserId) -> ok, reason?
PurchaseService.Purchased  Signal(player, kind, key)

Economy.OfflineRateFor(data) -> number
IncubationService.FinishNow(player, all?) -> count
```

**Ownership is keyed by our key, not the asset id.** `Profile.Gamepasses` stores
`{ vip = true }`. A DataStore round trip mangles a table with sparse numeric
keys, and the asset id legitimately differs between a test place and the live
one — keying on it would invalidate every save the day the game is published.

**No asset id is invented.** All 14 entries ship with `AssetId = 0`, meaning
*not configured yet*: the experience does not exist (open question #1). A
plausible-looking id is a prompt that fails silently or, worse, one that charges
for somebody else's product. `PurchaseService` refuses to prompt or process an
unconfigured id and says so at boot; ConfigValidator rule 10 warns rather than
failing, because a game with no store must still be entirely playable.

**`processReceipt` makes four guarantees, in this order.** (1) A profile that is
not loaded returns `NotProcessedYet` — Roblox will re-deliver. (2) A receipt
already in the 100-entry ring returns `PurchaseGranted` *without* granting
again. (3) The receipt is recorded and the grant applied in **one** write. (4)
The save is awaited before returning `PurchaseGranted`. Any other ordering pays
twice or loses a purchase, and `tests/step21_spec.lua` crashes the sequence at
each of the four steps to prove it.

**How each effect combines is declared, not inferred.** `ProductConfig.
EffectModes` names `add`, `multiply` or `max` per effect, and a require-time
assertion fails any pass granting a numeric effect with no mode. See finding 36.

### Step 22 — leaderboards

```
LeaderboardConfig.Boards / Order              -- 4 of docs/02's 8
LeaderboardConfig.Get(boardId) / Count()
LeaderboardConfig.MaxValue                    -- 2^53, same as Economy.MaxFossils
LeaderboardConfig.StoreValue(raw) -> integer  -- floor, clamp, NaN-safe
LeaderboardConfig.ValueFor(boardId, data) -> integer   -- pure, shared
LeaderboardConfig.ReadIntervalFor(players) -> seconds
LeaderboardConfig.BudgetCheck(players) -> { WritesPerMin, ReadsPerMin, Fits, ... }
LeaderboardConfig.StatueBoard / StatueCount / PageSize

LeaderboardService.Get(boardId) -> board?          cached, may be stale
LeaderboardService.GetAll() -> { [boardId]: board }
LeaderboardService.GetStatues() -> { {UserId, Name, Value, Rank} }
LeaderboardService.SelfEntry(player, boardId) -> { Value, Rank? }
LeaderboardService.FlushPlayer(player) / RefreshNow(boardId?)
LeaderboardService.BoardsRefreshed  Signal()

LeaderboardController.Fetched  Signal(payload)
LeaderboardController.GetPayload() -> payload?
```

**Writes are throttled AND change-checked, and the second one does most of the
work.** A player earning every second for an hour costs 15 requests against a
naive 14,400 — 960× fewer. The first throttled tick writes all four boards; the
eleven after it write only the value that moved. An idle player costs four
requests ever. A throttle alone would spend four every five minutes forever.

**60 seconds is a floor, not a period.** Reads are per-server while the read
budget scales with players, so a nearly empty server is the binding case and
the one nobody tests. V1's four boards fit at one player; docs/02's eight would
not, so the interval is derived from the board count — see finding 41.

**There is no rank query, and nothing pretends otherwise.** `OrderedDataStore`
returns pages and has no rank API. A player in the cached top 100 gets their
real rank; one outside it gets their value and the words. See the service
header for why a sampled rank would be worse than none.

**`ValueOf` is pure and shared** for the same reason `RebirthConfig.Preview` is:
the server writes the number and the client pins it under the list, and two
implementations would show a player a figure that disagrees with the board they
are standing in front of. It is never *trusted* from the client, only displayed.

### Step 23 — tutorial

```
TutorialConfig.Beats / StepCount / TotalWords
TutorialConfig.Get(step) / IsActive(data) / StepOf(data)
TutorialConfig.ForcedRarity(data) -> "common"?      beat 4
TutorialConfig.ForcedHatchSecs(data) -> 10?         beat 8
TutorialConfig.ChaseSpeedCap(data, thiefSpeed) -> number?   beats 5-6
TutorialConfig.TopUpFor(data, cost) -> number       beat 11
TutorialConfig.CanAdvance(data, toStep, facts) -> ok, reason?
TutorialConfig.ValidateRequirements(known) -> ok, problem?

TutorialService.State(player) / IsActive(player)
TutorialService.Advance(player, toStep) -> ok, reason?
TutorialService.Skip(player) -> ok, reason?
TutorialService.FactsFrom(data, live) / Facts(player)
TutorialService.ValidateFacts()                     asserted at Start
TutorialService.StepChanged  Signal(player, step, beat?)
TutorialService.Finished     Signal(player, skipped)

ParkConfig.PlotSearchOrder(zoneRingSlot?, zoneSlotCount?) -> { index }
```

**It drives the real systems; it does not replace them.** There is no tutorial
sandbox, no second pickup path and no fake hatch. The four things docs/00 §3
bends are pure functions of the profile, consulted by `EggService`,
`IncubationService` and `WildAIService` at the point each already computes that
number — and every one of them returns nil for anybody not mid-tutorial, which
the spec asserts for a graduate, a skipper and a profile with no tutorial state
at all. That is the difference between a modifier and a fork.

**The step number is server state.** `RequestTutorialStep` carries a number and
nothing else — it is the client saying "I think I finished that one", and the
server checks it against what the player has actually done. Nine of the eleven
advancing beats are gated on real state. A jump, a replay and a re-entry after
finishing are all refused, which matters because `Tutorial.Completed` is the
metric docs/00 targets at >80 % and beat 11 pays a Fossil top-up.

**The chase cap is a cap, not a speed.** It can only ever make a chase easier,
so a slow archetype does not get a tutorial speed *boost* — which would be the
opposite of the promise. Measured: the fastest archetype runs at 21.2 against a
thief's 20 and would catch them; capped, every one of the 20 is below 20.

**No beat can deadlock.** A beat requiring something the server never computes
would sit there being asked and refused forever. `TutorialService.ValidateFacts`
asserts the requirement set and the computed set match at boot — the same
coverage discipline the replication allowlist and `RebirthConfig`'s three lists
use — and the spec drives it to a real failure.

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
| `NotificationController` | ModuleScript | The queue: three visual weights, one takeover at a time |
| `SoundController` | ModuleScript | 12 named slots, looked up by name; no asset ids invented |
| `WeatherController` | ModuleScript | Lighting, locally, so it always reverts |
| `QuestController` | ModuleScript | The quest board and the daily chest |
| `IndexController` | ModuleScript | The book, one page per zone |
| `RebirthController` | ModuleScript | The keep/lose/gain confirm screen |
| `PurchaseController` | ModuleScript | The Robux store, the honesty panel, the server-boost banner and Thanks. **Prompts; never grants** |
| `LeaderboardController` | ModuleScript | The boards screen and the Colosseum's pillars and statues, from one cached fetch |
| `TutorialController` | ModuleScript | Professor Rok, one world arrow, one objective line, skip. **Asks; never decides** |

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
| 47 | Added four raid fields to the profile (`StealCooldowns`, `RevengeMarks`, `RobbedAt`, `GlobalStealAt`) | Every one of them is bypassed by rejoining if it lives in memory: a same-victim cooldown that resets on reconnect is not a cooldown. Keys are userIds as **strings**, because a table with sparse numeric keys does not survive DataStore's JSON round trip. All four withheld from replication — who you may raid is a server decision, and the prompt already carries the reason | docs/10 §1 |
| 48 | **A carried dinosaur stays in its owner's profile until the gate** | docs/03 §4.6 defers ownership to the gate and §4.9 promises no loss on disconnect; both fall out of this one choice. The alternative — remove at lift, re-add at the gate — has a window where the dinosaur exists only in server memory, and a crash there deletes it. This way the worst case is the owner keeps it, which is the direction an error should fall. Requires a server-side lock so the owner cannot sell it mid-raid | docs/03 §4.2, §6 |
| 49 | An **owner who leaves mid-carry voids the raid** | There is no loaded profile to transfer from, and editing an unlocked profile from another session is exactly what ProfileStore's session locking prevents. Consistent with docs/03 §4.3 making offline parks fully raid-immune. Does mean disconnecting saves your dinosaur — recorded under Open questions rather than hidden | docs/03 §4.2 |
| 50 | `DinosaurService.Create` gained `params.Acquired` and `params.HatchedAt` | A stolen dinosaur was counting as hatched: it inflated the thief's `DinosHatched` (a leaderboard stat), reset the dinosaur's age to today, and could end New Player Protection, whose condition is "until first Rare **hatch**". Additive to a frozen API, not a rename | docs/10 §1 |
| 51 | No `RaidController`; raid UI lives in `HUDController` and `ParkController` | The alerts are banners and reveal panels, which `HUDController` already owns; hiding your own Steal prompts is a park-side visual, which `ParkController` already owns. Adding a controller for eleven message handlers would put raid code in three places instead of two | docs/09 §1 |
| 52 | `SecurityLevel` sums the defence **board**, not a fixed list of three ids | So the V1.4 pass that adds Alarm Horn and Electric Fence raises the raid hold ceiling to its published 9 s with no code change — and so V1's real ceiling of 7.5 s is a fact about the content rather than a hardcoded number | docs/03 §5 |
| 53 | Added `NotificationConfig` as config module #11 | The severity durations are read on both sides — the server stamps them, the client counts them down — so they cannot live on either side alone. It also holds the payload sanitiser, which docs/09 §7.7 requires on receive and which is only trustworthy if it is literally the same function that ran on send | docs/09 §1, §7.7 |
| 54 | `Kind = "reveal"` renamed to `Kind = "takeover"` | "reveal" was a placeholder I introduced in Step 12 before the severities existed; docs/08 §5 names four severities and reveal is not one of them. Renamed at the step that formalises the vocabulary rather than leaving a fifth kind that means the same as one of the four. `HUDController.ShowReveal` keeps its name — it is the renderer, and "reveal" describes what it draws | docs/08 §5 |
| 55 | `SoundController` contains **no asset ids** | There is no audio yet, and an invented `rbxassetid://` is a silent 404 that looks like working code. Slots are looked up by name in `SAD_Assets/Sounds`, so the audio pass is a folder of files rather than a code change — the same stance `AssetBuilder` takes for models | docs/15 §3 |
| 56 | `EggCarryController`'s placeholder `Notify` handler removed | It was explicitly marked "Step 16's NotificationController takes this over". Two handlers on one remote renders everything twice | — |
| 57 | Added `WeatherConfig` as config module #12, with mutation weights deliberately left out of it | Weights, durations and non-mutation effects have no home; mutation multipliers already have one in `MutationConfig.WeatherModifiers` and belong with the mutations. Splitting them is the thing deviation #5 warned about, so ConfigValidator rule 11 asserts the two tables name the same weathers at boot — the split is only safe because something checks it | docs/09 §1, docs/04 §2 |
| 58 | Added `WeatherController` to the client roster (#18) | docs/09 §1's client list has no home for weather visuals, and docs/13 §Step 17 asks for them to be local: "the effects are server truth, only the visuals are local". Beyond trust, it bounds the hazard docs/13 names — Lighting driven from the server and left wrong is wrong for everyone until a restart; the same mistake locally corrects itself on rejoin. It also lets `Settings.LowGraphics` suppress fog per player, which a server-wide Lighting change cannot | docs/09 §1, docs/13 §Step 17 |
| 59 | `MutationService.RollIn` and `.Roll` gained an optional `zoneId` | docs/04 §2's Blizzard is "Frozen ×25" everywhere and "Frozen Valley ×2" on top, so the roll has to know where the egg came from. Additive to a frozen API, like `params.Acquired` in Step 15. `IncubationService` passes the egg's `Origin`, not the player's position — a Valley egg carries the Valley's weather home with it | docs/04 §2 |
| 60 | Added ConfigValidator **rule 11**: the two weather tables must agree | See #57. It also catches a modifier naming an unshipped mutation, and a weather with zero weight or no duration — each of which ships as a weather that silently does nothing | docs/11 §5 |
| 61 | `EventService.Begin(eventId)`, not `.Start` | Exactly the collision `IncubationService` hit in Step 11 (deviation #31): `Start(app)` belongs to Bootstrap's lifecycle and Bootstrap looks for it by name, so the public function is the one that moves | — |
| 62 | Added `EventConfig` as config module #13, and `EventService/Handlers` as a folder of modules | docs/13 §Step 18 specifies "`EventService` + `Handlers/`". Handlers are *discovered* rather than listed, so adding an event is a config entry plus a module and never an edit to the service — and ConfigValidator rule 8, written in Step 3 and skipped ever since, finally has its inputs | docs/09 §1, docs/13 §Step 18 |
| 63 | The no-repeat-within-3 rule is **clamped to leave two choices** | With four events, excluding the last three leaves exactly one — a fixed rotation, not a weighted roll. `ExclusionDepth` relaxes to the published 3 as events are added, so this corrects itself rather than needing to be remembered | docs/04 §3 |
| 64 | Meteor Impact ships its guaranteed mutation but not its Radioactive ×20 skew | Radioactive is a V1.6 mutation (docs/12). Skewing towards something that cannot be rolled is a line of code that does nothing — the skew arrives with the mutation it skews towards | docs/04 §3 |
| 65 | Added `RarityConfig.TierAbove`, the counterpart to `TierBelow` | The crater upgrades what it drops by one tier, and V1.1's Great Migration upgrades a whole zone the same way. My first draft guarded with `RarityConfig.TierAbove and ...`, which would have made the upgrade a permanent silent no-op | docs/04 §3 |
| 66 | `HUDController.SetEventBanner` gained a `priority` | Weather (Step 17) and events (Step 18) both want the one banner slot. An event outranks weather because it is rarer, shorter and has something to do about it; and only the holder may clear it, or weather's 1 Hz countdown would stamp over an event banner a fraction of a second after it appeared | docs/08 §2 |
| 67 | Added `Time` as shared module #13 | "Which UTC day is it" is read by the server deciding whether a chest may be claimed and by the client drawing the countdown to it. Two implementations is a UI that says READY over a button that refuses. Pure integer division on `os.time()` — no `os.date`, no locale, no daylight saving, none of which is the same on two machines | docs/09 §1, docs/13 §Step 19 |
| 68 | Added `QuestConfig`, `DailyConfig` and `IndexConfig` (config modules #14–16) | All three were already named in docs/09 §1's tree and reserved in ConfigValidator's optional list | docs/09 §1 |
| 69 | `RewardGrant` lives under `QuestService` and is exposed as `QuestService.RewardGrant` | Three services hand out overlapping rewards. Written three times, docs/05 §7's rebirth scaling gets applied in two of them. Owned by its largest consumer and shared the same way `NestService.Zones` is | docs/09 §1 |
| 70 | Added `Profile.BonusDinoSlots`, `BonusVaultSlots` and `Titles` | Index milestones and streak rewards grant permanent slots and cosmetic titles (docs/05 §7), and none of the three had anywhere to live. Step 21's gamepasses add to the same two counters rather than inventing a third source | docs/10 §1 |
| 71 | `Stats.Luck` and `.MutLuck` now fold in active boosts, and take an optional `now` | A Luck Potion granted into `Boosts` that no stat reads is a reward that does nothing — the decorative failure this project keeps removing. Boosts are stored as an **expiry**, so an expired one contributes nothing without needing to be swept first: correctness does not depend on cleanup, which matters because the client computes stats too and cannot write to the profile | docs/05 §7 |
| 72 | Two dead entries removed from `ConfigValidator.OPTIONAL_CONFIGS` | `Quest` and `Daily` were skip labels for a skip that never happened, because no rule read either config. After findings #29 and #30 — both about registered-but-inert validation — leaving them would have been the same decoration. Their invariants are asserted where they can fail loudly instead | — |
| 73 | `RebirthConfig.Preserved` is now a keyed table of reasons, joined by `Reset` and `Partial` | An array of names cannot say *why*, and more importantly cannot be checked for coverage. The three tables must be the exact union of the profile template, asserted at boot — see finding #33 for what that caught | docs/05 §6, docs/09 §4 |
| 74 | The keep/lose/gain preview lives in `RebirthConfig`, shared, not in the service | It is the one screen where a player deletes their park on the strength of what it says. Computing it twice is a contract the game might not honour. Same dependency-free-by-argument shape `ZoneConfig.UnlockCheck` uses | docs/13 §Step 20 |
| 75 | Added `RebirthController` to the client roster (#19) | docs/09 §1's client list has no home for a confirm screen, and docs/13 §Step 20 asks for one. On the left rail rather than the bottom bar: rebirth is the rarest thing a player does and the one they should never press by accident | docs/09 §1 |
| 76 | `DataService.Template` exposes the ProfileTemplate | `RebirthConfig.Validate` needs the schema to check its coverage against. Read-only by convention; DataService is still the only thing that writes through it | docs/09 §1 |
| 77 | docs/05 §6's Rebirth Cache example corrected: a Mythic career caches a **Legendary**, not an Epic | The rule says "minus one tier" and the example says a Mythic player gets an Epic, which is minus two. The rule is the mechanism and the example is prose illustrating it, so the rule wins and `CacheTiersBelowBest = 1` stands. The generosity question is real, though — flipping that constant to 2 is the whole change, and the spec asserts both readings | docs/05 §6 |
| 78 | Added `ProductConfig` as config module #17, keyed by our string keys | `Profile.Gamepasses` cannot be keyed by asset id: a DataStore round trip mangles sparse numeric keys, and the id differs between a test place and the live one, so keying on it would invalidate every save on publish day | docs/09 §1, docs/07 §2 |
| 79 | Every `AssetId` ships as **0**, meaning not configured | The experience does not exist yet (open question #1). An invented `rbxassetid` is a prompt that fails silently or charges for somebody else's product — the same stance `SoundController` takes for audio (#55). `PurchaseService` refuses to prompt or process one, and rule 10 warns rather than failing so a store-less game stays fully playable | docs/07, docs/11 §5 |
| 80 | ConfigValidator **rule 10** treats `AssetId == 0` as unconfigured | Without this the rule fails the boot of a game that is deliberately store-less. Anything non-zero is still held to being a unique positive integer, so a typo'd or duplicated id fails loudly the moment a real one is pasted in | docs/11 §5 |
| 81 | Added `ProductConfig.EffectModes`; `EffectTotal` no longer infers the mode from the default | See finding #36. Inference was right for five effects of eight and silently wrong for `OfflineRate`. A require-time assertion now fails any pass granting a numeric effect with no declared mode | docs/07 §2 |
| 82 | Added `Economy.OfflineRateFor(data)`; `OfflineEarnings` uses it when no rate is passed | VIP's 100 % offline rate has to reach the calculation that pays it, and the calculation is shared — the client draws the same figure the server banks. The explicit-rate parameter stays, so existing callers and the specs are unchanged | docs/07 §2, docs/05 §4 |
| 83 | Added `IncubationService.FinishNow(player, all?)` | The Instant Hatch products bring `HatchAt` forward and then go through the ordinary `Claim`, so the reveal, the mutation roll and the storage check are the same code paths a free hatch uses. A separate grant path is how a paid hatch quietly stops rolling mutations | docs/07 §3 |
| 84 | `PurchaseService` is the only file that references `MarketplaceService` | Ownership, receipts and prompts in one place means one rate limit, one cache, and one `ProcessReceipt` — Roblox permits exactly one callback, and a second assignment silently replaces the first | docs/09 §1 |
| 85 | Added remotes `RequestThanks` (c2s) and `ServerBoost` (s2c) | docs/07 §4's Thanks button and the gold banner that precedes it. Net now publishes 40 events and 4 functions | docs/09 §3 |
| 86 | Gamepass effects fold into `Stats` and `Economy`, not into a parallel paid path | `DinoSlots`, `Incubators`, `IncubationMult`, `ParkIncomeMult`, `Luck` and `MutLuck` all gain a `passTotal` term at the point they are already composed. A pass that reads its own numbers is a pass that stops matching the rest of the game the first time a cap moves | docs/07 §2 |
| 87 | Added `PurchaseController` to the client roster (#20), on the left rail as 💎 and on **6** | docs/13 §Step 21 asks for "server-wide boost purchases + the Thanks button", and both remotes would otherwise be declared and inert. The store itself has to live somewhere too: the Bone Market spends Fossils and mixing a Robux prompt into it is exactly the confusion docs/07 §1 rule 7 exists to prevent | docs/09 §1, docs/07 §4 |
| 88 | The store's row order lives in `ProductConfig`, not the controller | A hash table has no order, so a store that iterates one moves its rows between sessions. More importantly an order the client owns cannot be checked against the catalogue: `PassOrder` and `ProductOrder` are asserted at require time to cover it exactly once, so a pass added without a listing fails loudly instead of silently never appearing for sale | docs/07 §2–3 |
| 89 | Added `Settings.SeenStoreNotice` (schema + template, no migration) | docs/07 §1 rule 7's panel is "the first time a player opens the shop", which needs somewhere durable to record that it has been shown or it becomes a nag. In `Settings` because there is already a validated remote for writing one and because a player can turn it back on. A new field with a sensible default is Reconcile's job, not a migration's — the same call `BankedRate` made (#38) | docs/06 §8, docs/07 §1 |
| 90 | Added `LeaderboardConfig` as config module #18 | The value formula is read on both sides — the server writes it to the store, the client pins it under the list — so it cannot live on either alone. It also holds the budget arithmetic, which is the only way "does this fit" is a measured number rather than a hope | docs/09 §1, docs/10 §4 |
| 91 | V1 builds **4** Colosseum pillars, not docs/02's 8 | One per shipped board. Four blank slabs are something a player walks up to and learns nothing from, and the arc spacing is derived from the count so V1.4's four space themselves — the same call the Index made about its denominator | docs/02 §1.1 |
| 92 | The value ceiling is **2^53**, not docs/13's 9e18 | 9e18 is under int64 but far above where a Lua double stops representing consecutive integers, so a value near it would already have been rounded before the store saw it. 2^53 is the largest ceiling where every integer below survives the trip | docs/10 §4, docs/13 §Step 22 |
| 93 | `Economy.MaxFossils` 1e30 → 2^53 | Its own comment said "exact to 2^53… the clamp is a safety net", and 1e30 is fifteen orders of magnitude past that, so the net caught nothing it claimed to. See finding 39 for the consequence | docs/05 §6 |
| 94 | The read interval is **derived from the board count**, with docs/10's 60 s as a floor | Reads are per-server and the read budget is not, so the tightest case is an empty server. Four boards fit at one player; eight do not. Derived rather than fixed so the build-out slows itself instead of silently failing — see finding 41 | docs/10 §4 |
| 95 | `EconomyService.SettleBank` now records `Stats.PeakIncomePerSec` | Nothing had ever written it, and the Highest Income board reads it — see finding 38. Recorded here because this is the one function every rate change goes through, and peak rather than current so selling a park to fund a rebirth does not drop you off the board | docs/10 §1 |
| 96 | Added `LeaderboardController` to the client roster (#21) | docs/09 §1's client list has no home for the boards screen, and the Colosseum's SurfaceGuis are presentation over server truth — the same call `WeatherController` made about Lighting. One fetch feeds both surfaces | docs/09 §1, docs/02 §1.1 |
| 97 | docs/05 §6's rebirth-20 row corrected: **1.00 × 10¹⁹**, not 5.4 × 10¹⁹ | The formula is `250,000 × 5.2^(n-1)`; the table's row applied the exponent as n. Every other row in the table reproduces from the formula, so the row was the error, not the formula | docs/05 §6 |
| 98 | Added `TutorialConfig` as config module #19 | The four bends have to be readable by `EggService`, `IncubationService` and `WildAIService` without any of them depending on `TutorialService` — a config they all already require is the only shape that does not create three new service edges. It also makes every bend pure, so "is this a no-op for a graduate" is a spec assertion rather than a claim | docs/09 §1, docs/00 §3 |
| 99 | `RequestTutorialStep(0)` is the **skip** signal | docs/00 §3 needs a skip and Step 4 froze the remote list. Overloading the existing remote rather than adding a `RequestTutorialSkip` that carries no argument at all: the rate limit, the argument validation and the handler already exist, and 0 is not a valid step | docs/09 §3 |
| 100 | docs/08 §6's "the step auto-completes" ships as "the client keeps asking" | A client that could declare a step complete could declare the LAST one complete and take the grant. After 60 s the ask repeats rather than the client deciding; a player who has done the thing advances on the next ask, one who has not sees the enlarged arrow and the hint. The player-facing behaviour docs/08 describes is preserved; the authority is not moved | docs/08 §6 |
| 101 | Beat 11 **tops the player up** to the first upgrade's price | docs/00's beat 10 shows "+120 Fossils!" and beat 11 says the upgrade "costs exactly what you now have"; the cheapest track is 800, so both cannot be literal. A top-up rather than a grant, so a player who earned 700 gets 100 and one who has 800 gets nothing — "exactly what you now have" stays true either way | docs/00 §3 |
| 102 | The tutorial's skip egg is granted through `RewardGrant` | Step 19 made it "the one place a reward is paid out". A tutorial egg written straight into `Profile.Eggs` would skip the storage cap, the notification and the analytics that every other granted egg goes through | docs/05 §7 |
| 103 | Added `ParkConfig.PlotSearchOrder`; plots are claimed nearest-the-free-zone-first | docs/00 §3 budgets 15 s for the walk out to Jurassic Plains and the blockout makes it 10–67 s depending on plot. Sorting the claim order front-loads the short walks — measured, the first eight joiners walk 33 % less. It does not reduce total walking and does not fix the worst case; see finding 42 | docs/00 §3, docs/02 §1.1 |
| 104 | Added `TutorialService` (server) and `TutorialController` (client) | docs/13 §Step 23 asks for "`TutorialController` + a small server validator in `PlayerDataService`". The validator is a service instead: it needs signals from `WildAIService` and `EconomyService`, a remote handler, and a boot-time coverage assertion, none of which belong in the data layer. `PlayerDataService` stays the thing that reads and writes profiles | docs/09 §1, docs/13 §Step 23 |

## Verification

`./tests/run.sh` — syntax-checks all 91 source files and runs **4,090
assertions** outside Roblox. Last run: **4,090 passed, 0 failed.**

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
| `step23_spec` (259) | docs/00 §3's twelve beats by id and order, the word count against its own 60-word budget, all four bends proven to be no-ops for a graduate, a skipper and a stateless profile, the chase cap driven against every one of the 20 archetypes with the fastest proven to catch an uncapped player, the top-up at four balances, the advance check driven beat by beat with and without each condition, the two cheats (jump and replay) refused, the deadlock guard driven to a real failure, and beat 2's walk measured against docs/00's fifteen-second budget |
| `step22_spec` (113) | The four V1 boards against docs/12's list and docs/10 §4's reserved store names, every board's value read off a profile including the emptied park that must keep its Income place, the clamp driven with NaN/infinity/negatives/strings, the rebirth curve's crossing of the ceiling located exactly, request rates computed at five player counts with the binding case proven to be an empty server, the eight-board build-out proven not to fit at a fixed 60 s, an hour of constant earning simulated to 15 requests against a naive 14,400, the rank contract for a player outside the top 100, and the Colosseum's geometry against the plaza and the park ring at 1, 4 and 8 pillars |
| `step21_spec` (162) | `processReceipt` modelled as a state machine and crashed at each of its four steps, with the wrong ordering proven to pay twice; the receipt ring's bound; the catalogue counted against docs/12's V1 scope; **no asset id invented**, asserted; docs/07 §1's ethics rules wherever they can be measured; the ×2.6 cap against what V1 reaches *and* against a simulated second income pass; the uncapped slot channel measured across the slot track; Fossil Packs proven to scale to the buyer at both ends of the curve; server purchases; VIP's offline rate all the way through to the hourly payout; every gamepass effect proven to declare a combination mode; and both store orders proven to cover the catalogue exactly once |
| `step20_spec` (123) | The three classification lists proven to cover the schema exactly once and driven to a failure in each of their three ways, docs/05 §6's keep/lose/gain lists by name, the cost curve and every capped grant reaching its cap, the Rebirth Cache against both readings of a contradictory doc, which zones survive with and without a rebirth-gated zone in the world, vault survival under a binding slot count, and the preview reconciled against what the player actually owns |
| `step19_spec` (263) | UTC day and week boundaries against real calendar dates and every day of a week walked, streaks through a 40-day run and a break, the published 7-day chest with its rebirth scaling, quest id uniqueness across both pools, the seeded roll's determinism and full reachability, double-claim modelled as the statement order it depends on, and the Index denominator proven to be what exists rather than what is planned |
| `step18_spec` (98) | The published event table, the clamped no-repeat rule simulated over 2,000 rolls, the participation floor for an earning player and a broke one, double-collection modelled as the statement order it depends on, every ConfigValidator rule asserted to actually report a result, rules 8 and 11 each driven to a real failure, and `TierAbove` against the zone weights the crater reads |
| `step17_spec` (85) | The published weather table, the Clear share for V1 *and* for the full eleven, the roll distribution over 20,000 picks, the mutation shift over 20,000 hatches per weather, the ×40 cap proven to trim the one V1 interaction that reaches it, Prime's chance proven flat while its count rises, and the two weather tables asserted to name the same set |
| `step16_spec` (87) | All four severities against docs/08 §5, a strict and unique priority order, the takeover queue proven to drop rather than grow, unknown kinds falling back *downward*, payload sanitising against nesting, functions, NaN, infinity, numeric keys and over-long keys, sanitiser idempotence, and the `MessagingService` budget against both docs/09 §7.7 and Roblox's own documented floor |
| `step15_spec` (85) | The hold formula against docs/03 §4.2 including V1's real ceiling and the V1.4 arithmetic, shield stacking proven un-permanent under fifty grants, record pruning under 500 entries, the stealable rules, the power floor in both directions, the transfer's conservation property with its rollback, vault slots, carry weight, and every published cooldown |
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

21. **The published raid hold ceiling is unreachable in V1.** docs/03 §4.2
    says "3 s → 9 s at max security", and §5 defines SecurityLevel as the sum
    of all defence levels ÷ 4, capped at 5. Nine seconds needs SecurityLevel 5,
    which needs 20 defence levels. V1 ships three tracks of five — fifteen — so
    a fully defended park holds a raider for **7.5 seconds, not 9**.

    Not a bug in either place: the missing five levels are Alarm Horn and
    Electric Fence, which docs/03 §5 lists and `UpgradeConfig` already defers
    to V1.4. What was missing was anyone noticing the two documents describe
    different content sets. `Stats.SecurityLevel` sums the defence *board*
    rather than a fixed list of three ids, so the ceiling rises to 9 s the day
    those tracks ship, and the spec asserts both the V1 number and the V1.4
    arithmetic so it stops being a gap without anyone remembering it was one.

22. **A stolen dinosaur was counting as a hatched one.** The raid transfer mints
    the dinosaur into the thief's profile through `DinosaurService.Create`,
    which increments `DinosHatched` and stamps `HatchedAt = os.time()`. So
    every raid inflated a leaderboard stat, reset the dinosaur's age to today,
    and could end the thief's New Player Protection — whose condition is
    literally "until first Rare **hatch**". Three wrong things from one reused
    function. `Create` now takes `params.Acquired`, additive to the frozen API.

23. **Where a carried dinosaur lives decides whether raids can dupe.** The
    obvious implementation removes it from the owner at lift and adds it to the
    thief at the gate — and in between it exists only in server memory, so a
    crash deletes it outright. Keeping it in the owner's profile until the gate
    makes the worst case "the owner keeps their dinosaur", which is the
    direction an error should fall, and makes docs/03 §4.9's no-loss promise
    structural rather than a timer.

    It creates a second problem that had to be solved with it: the owner can
    still see the entry, so they could sell, vault or store it out from under a
    raid in progress — and if the transfer then completed, that is a dupe. The
    server-side `locked` registry is that guard, and it is checked in every
    owner-side mutation path.

24. **docs/09's publish budget was six per minute; I had written twenty.**
    Caught by asserting the spec against the *document* rather than against
    the code. Six is right and I moved the code to it: the measurement in the
    same spec shows a full server hatching flat out generates about **0.0015
    announcements per minute** — only Secret and Titan cross servers, at 1 in
    80,000 in the hardest V1 zone — so six is four thousand times what the game
    can produce. A budget with that much headroom should be the tighter number,
    not the looser one.

    Worth recording as a habit rather than a bug: when the code and a frozen
    document disagree and the document is defensible, the code moves.

25. **`SoundController` names twelve slots and contains no asset ids.** There
    is no audio yet. The tempting shortcut is a table of plausible
    `rbxassetid://` numbers, which produces a game that logs nothing, plays
    nothing, and looks finished. Instead each slot is looked up by name in
    `SAD_Assets/Sounds` and the boot line says `Ready, silent` with a count.
    The audio handover is then a folder of files with the right names, and the
    absence is visible in the log rather than inferred from the quiet.

26. **The published 45% Clear share needs all eleven weathers.** docs/04 §2
    weights Clear "so that roughly 45% of the time nothing special is
    happening". That is exact — 4,500 against 5,500 of exotic weight — across
    the full table. V1 ships three exotics summing to 2,950, so **Clear is
    60%**.

    Same shape as Step 15's raid hold ceiling: neither the document nor the
    config is wrong, they describe different content sets. And here the V1
    number is arguably the better one — with only three exotics to draw from,
    seeing one every other roll is what would stop them feeling special. The
    weights are unchanged, so shipping the remaining seven restores 45%
    exactly. Both numbers are asserted, so the day the table fills out this
    fails and gets updated rather than drifting.

27. **"Prime chance is never modified by weather" is about the chance, not the
    count — and my first test measured the count.** It failed: 2 Primes in
    clear against 8 in a thunderstorm over 40,000 rolls, which looked like
    weather leaking into Prime.

    It is not. Prime is only rolled once a mutation has already landed, so a
    weather that doubles the mutation rate doubles the number of rolls that
    reach the Prime check while leaving the 1-in-2,000 untouched. The count
    *should* rise. Re-measured as a conditional rate over 300,000 rolls:
    1 in 1,927 in clear and 1 in 1,994 in a thunderstorm. Both halves are now
    asserted — that the count rises, and that the rate does not — because
    asserting only one of them is how this misread happened in the first place.

28. **The ×40 mutation cap had nothing to do in V1 until it did.** V1's largest
    weather modifier is Frozen at ×25, comfortably under the cap, so nothing
    would ever have exercised it — a limit that never binds is a limit nobody
    notices has stopped working.

    docs/04 §2's Blizzard row also says "Frozen Valley ×2", which is the one
    V1 interaction that reaches it: ×25 → ×50 → trimmed to ×40. Implementing
    that reading gives the cap a job and makes it measurable: 34% Frozen in a
    blizzard elsewhere against 45% in the Valley, where uncapped would be 55%.

29. **A validation rule spent an entire step registered and never running.**
    Rule 11 was added to `ConfigValidator.RULES` in Step 17, but the script
    that was supposed to define its function errored before writing — so
    `RULES` contained a `nil` in the middle of the array. A nil in an array is
    not an error; it is a hole that generalized iteration steps straight over.
    No crash, no skip, no line in the boot report. The rule simply did not
    exist, and Step 17's spec never touched the validator, so nothing caught
    it for a whole step.

    This is the Step 2 `#`-on-a-table-with-a-hole finding arriving from the
    other direction. Two guards now, because one of them would have caught
    only half of it:

    - `RULES` asserts at load that every entry is a function and that the
      count matches, so a registered-but-undefined rule cannot reach a
      running game;
    - `Run` fails any rule that reports neither a pass, a skip nor an error,
      because a rule that produces no output has silently done nothing —
      which is also how a rule missing the *config it reads* fails.

    `tests/step18_spec.lua` asserts each rule id appears in the report by
    name rather than counting them, since a count passes just as happily when
    the wrong rule is the missing one.

30. **Rule 8 had been skipping since Step 3.** Written then, with a
    `c.EventHandlers` hook reserved for exactly this step and no way to supply
    it. Now that `EventService/Handlers` exists, the validator resolves the
    folder and rule 8 fails boot on an event naming a handler that is not
    there. Worth noting alongside #29: of the eleven rules, two were
    effectively decorative until this step, and only one of them was
    decorative *on purpose*.

31. **docs/06's Index denominator is 60; V1 ships 35.** "Completion % =
    discovered species ÷ 60" is the finished game. Hardcoding it would show a
    V1 player who has found *every dinosaur that exists* a completion of 58 % —
    which is not pending, it is wrong.

    `IndexConfig.Total` counts `DinoConfig` instead, so finding everything
    reads 100 %, and milestones 40/50/60 are simply unreachable until the
    species ship. The spec asserts both the count and which three milestones
    are reachable, so shipping species 36–60 fails here and gets updated
    rather than drifting.

    The same reasoning applies in reverse to rarity completion sets: an
    *empty* set is not complete. V1 has no Mythic or Ancient species, and
    paying +2 % Luck for having found nothing would be the 60-species
    denominator bug from the other direction.

32. **A boost that no stat reads is a reward that does nothing.** docs/05 §7's
    daily chest hands out Luck Potions and Mutation Serums on days 2 and 4.
    The profile has had a `Boosts` table since Step 2 and nothing ever read it,
    so granting one would have been the same decorative failure as an upgrade
    with no handler (finding at Step 13) or a validation rule with no config
    (#29).

    `Stats.Luck` and `.MutLuck` now fold in active boosts. Stored as an
    **expiry** rather than a duration, which has a property worth naming: an
    expired boost contributes nothing *without needing to be cleaned up*.
    Correctness does not depend on a sweep — which matters because the client
    computes stats too and cannot write to the profile.

33. **Eleven profile fields would have been destroyed by the first rebirth.**
    `RebirthConfig.Preserved` was written at Step 3 as a list of names, and
    everything absent from it reset. The schema has grown eleven fields since
    — and every one of them defaulted to RESET simply by nobody having
    mentioned it.

    Six should not have:

    - **`StealCooldowns`, `RevengeMarks`, `RobbedAt`, `GlobalStealAt`** — the
      four anti-abuse fields from Step 15. Resetting them makes a rebirth a
      way to clear a same-victim cooldown, the 90-second global cooldown, and
      the Mercy Shield history that protects a player being farmed. That is
      the most consequential: a cooldown a rebirth can clear is not a cooldown.
    - **`BonusDinoSlots`, `BonusVaultSlots`, `Titles`** — permanent grants
      from Index milestones and streaks, which themselves never reset. Losing
      them means "permanent" was only true until the next rebirth.
    - **`Shrines`** — map knowledge, the same category as the Index.
    - **`Boosts`** — an active Luck Potion, often minutes old.

    docs/13 calls a half-applied rebirth "the worst bug in the game", and this
    is the shape it actually takes: not a torn write, but a field nobody
    decided about. Fixed structurally rather than by fixing the list —
    `Preserved`, `Reset` and `Partial` must now be the exact union of the
    profile template, with a reason on every entry, and `RebirthService`
    refuses to start if they are not. A field added in a later step cannot
    default to being destroyed.

    Same discipline the replication allowlist has used since Step 4. It is
    worth noting that the allowlist *did* catch every one of these fields at
    the time they were added, because it asserts coverage; the rebirth list
    did not, because it did not.

34. **docs/05 §6's Rebirth Cache rule and its example disagree.** The rule is
    "minus one tier (min Rare)"; the example is "rebirth 8 hands a Mythic
    player an Epic egg", which is minus **two**. Mythic − 1 is Legendary.

    The rule wins — it is the mechanism, and `CacheTiersBelowBest = 1` has
    implemented it since Step 3 — so the doc's example is corrected rather
    than the config. But the generosity question is a real design call: a free
    Legendary every rebirth is a lot more than a free Epic. Flipping that
    constant to 2 is the whole change, and the spec asserts both readings so
    the consequence of switching is already written down.

35. **A V1 rebirth costs 700 K, not the 250 K it advertises.** docs/05 §6 says
    zone unlocks reset "above the highest rebirth-gated zone you qualify for".
    No V1 zone is rebirth-gated — Zone 5 is the first and it is V1.1 — so a
    rebirth returns the player to the free zone and Canyon, Swamp and Frozen
    must be re-bought for 450 K on top of the 250 K rebirth itself.

    That is the design's own rule applied to the content that exists, so it is
    recorded rather than changed, and it corrects itself the moment Zone 5
    ships: from then on the floor rises with the rebirth count and a rebirth
    re-locks nothing. Worth knowing before launch, because a player reading
    "250 K" on the confirm screen and losing 700 K of progress has a fair
    complaint — which is why the confirm screen now names the re-buy cost
    explicitly.

36. **VIP would have earned 160 % offline — more than it earns playing.**
    `ProductConfig.EffectTotal` decided additive-vs-multiplicative by looking
    at the default it was handed: `default == 1` meant multiply, anything else
    meant add. That is right for five of the eight effects and silently wrong
    for `OfflineRate`, whose default is `Economy.OfflineRate` (0.60) and whose
    VIP value is 1.0 — so it **added** them and paid 1.60.

    The bug is the inference itself, not the arithmetic: a rule that reads a
    caller's argument to guess a config's semantics is right by coincidence.
    `ProductConfig.EffectModes` now declares `add`, `multiply` or `max` per
    effect, `OfflineRate` is `max` (the best owned rate replaces the baseline
    and two passes granting it do not stack), and a require-time assertion
    fails any pass granting a numeric effect with no mode — so the V1.1 passes
    cannot reintroduce this.

37. **The ×2.6 stacking cap is correct, shipped, and currently unreached — and
    it does not govern the channel that actually matters.** docs/07 §2 caps
    "the combined multiplicative effect of all owned gamepasses on income" at
    ×2.6. V1 ships six of the twelve passes and exactly one of them, Double
    Income, touches that channel, so the whole catalogue multiplies to exactly
    ×2.0 and `math.min` never binds. Same family as the ×40 mutation cap and
    the 9 s raid hold: the doc describes the finished catalogue, V1 ships a
    subset. The spec asserts what V1 reaches *and* that the cap trims a
    simulated second income pass, so it will not rot.

    Measuring the *player's* throughput rather than the per-dinosaur rate found
    the more interesting half. The passes also buy +8 slots, and the slot
    channel is additive and uncapped:

    | Free player's slot level | Slots free / paid | Overall |
    |---:|---|---:|
    | 0 (brand-new account) | 4 / 12 | ×6.00 |
    | 5 | 9 / 17 | ×3.78 |
    | 12 | 16 / 24 | ×3.00 |
    | 26 (track complete) | 30 / 38 | ×2.53 |

    So the doc's ×2.6 is accurate for a player who has played — the advantage
    converges on it — and the gap is widest on a fresh account, where the free
    path has barely started. Left uncapped deliberately: capping slots would
    mean confiscating placement space a player has already bought and built a
    park around. Recorded in docs/07 §2 so it is a known shape rather than a
    surprise found after launch.

38. **The Highest Income board would have ranked every player at zero.**
    `Stats.PeakIncomePerSec` has been in the profile template since Step 2 and
    *nothing had ever written it*. It is the column docs/10 §4 assigns to
    `SAD_LB_Income`, so the board would have shipped sorting a field that is
    permanently 0 — a leaderboard where everybody ties, which reads as a broken
    DataStore rather than as a missing line of code.

    Written now in `EconomyService.SettleBank`, the one function every rate
    change goes through. Peak rather than current, deliberately: a player who
    sells their park to fund a rebirth should not drop off the board for the
    ten minutes it takes to rebuild, and a board that punishes the thing the
    game most wants you to do is working against the design.

    Same family as findings 29, 30 and 32: something registered and inert.

39. **`Economy.MaxFossils` was 1e30, and its own comment said 2^53.** The
    comment read "Fossils are stored as Lua doubles, exact to 2^53… the clamp
    is a safety net" — above a clamp fifteen orders of magnitude past 2^53. It
    caught nothing the sentence above it claimed to care about.

    The reason it matters is not overflow. A double does not overflow at 1e20;
    it stops representing consecutive integers, so a balance up there simply
    **stops counting** — earning a Fossil changes nothing and the player
    watches a frozen number with no error anywhere. Now 2^53, the same ceiling
    `LeaderboardConfig.MaxValue` uses.

    Its consequence is a real design constraint, recorded rather than papered
    over: docs/05 §6's curve is 250,000 × 5.2ⁿ⁻¹, which crosses 2^53 between
    rebirth 15 and 16, so **15 is the effective rebirth ceiling** whatever the
    table says. Rebirth 20 at 1.00 × 10¹⁹ is past int64 entirely and could not
    be stored on a leaderboard even if it could be reached. Fixing it is a
    design decision rather than a code one — drop the growth factor to ~4.0 and
    the crossing moves past rebirth 20, or state the ceiling as the intended
    end of the curve. Nobody reaches rebirth 15 in V1's content, so there is
    time to choose. (Correcting that table also turned up an off-by-one in it:
    the rebirth-20 row had applied the exponent as n rather than n − 1.)

40. **`Count()` and `ReadIntervalFor` read different lists.** `Count` closed
    over the local array the boards were built into; `ReadIntervalFor` read
    `LeaderboardConfig.Order`. Identical until something replaces the public
    field — which is exactly what the spec's eight-board simulation did, and
    the two then disagreed silently for the rest of the run.

    Caught because the spec restored the catalogue by reassigning the field and
    a later assertion counted four boards as eight. Both now read the public
    field, and the spec mutates in place and asserts the restore.

    Worth stating generally: a public field and a private copy of the same list
    are one refactor away from disagreeing, and the disagreement is silent.

41. **The eight-board build-out would exhaust an empty server's read budget.**
    Writes scale with players and so does the write budget, so a full server is
    never the problem — measured, 30 players use under a tenth of it. Reads do
    not scale with players, because the cache is server-wide, while the read
    budget (`GetSortedAsync`: 5 + 2 × players per minute) does. So the tightest
    case is **one player**, and it is the one nobody tests.

    V1's four boards at 60 s cost 4/min against a budget of 7 and fit. docs/02
    §1.1's eight would cost 8/min and would not — they would start failing on a
    nearly empty server, which is also the server a developer tests on.

    So the period is derived from the board count rather than fixed, with
    docs/10's 60 s as a floor: V1 is unaffected and the eight-board build-out
    stretches itself to ~92 s. Same shape as the clamped no-repeat rule in
    Step 18 — a number that corrects itself as content ships rather than one
    somebody has to remember.

42. **docs/00's FTUE beat 2 is off by roughly fifty times.** The table says the
    gate to Jurassic Plains is "25 studs away" and budgets fifteen seconds for
    the walk. The blockout puts the park ring at 573 and the zone's near edge
    at 775, so the real walk is **202 studs from the closest plot and 1,348
    from the furthest** — 10 seconds against 67, at walkspeed 20.

    Sixty-seven seconds is 45 % of the whole 2m30 FTUE budget spent on one beat,
    for a player whose only mistake was being handed the wrong plot.

    Half of it is fixed here: `ParkConfig.PlotSearchOrder` claims plots nearest
    the free zone first instead of in index order. Be precise about what that
    buys, because it is easy to overclaim — it does **not** reduce walking. A
    full server hands out all 24 plots either way and the average over the whole
    ring is identical to the stud. What it does is front-load the short walks,
    and measured, the first eight joiners walk 33 % less than index order sent
    them. Servers are rarely full, so that is the case worth improving.

    The other half is not fixable in config and is left stated: the last joiner
    on a full server still walks the long way, and no plot ordering changes
    that. It needs a level-design decision — a second Plains entrance, or the
    tutorial granting an Obelisk hop — so it is recorded rather than guessed at.

43. **The "stateless profile" fixture was quietly not stateless.** Building it
    as `profile({ Tutorial = nil })` looks like it removes the field. It does
    not: `pairs` skips a nil value, so the override never ran and the fixture
    was an ordinary step-1 profile. Four assertions about a profile with no
    tutorial state were really four assertions about a profile mid-tutorial —
    and they failed, which is the only reason it was noticed.

    Worth recording because it is a property of the language rather than of this
    code, and every spec in this project builds fixtures the same way: an
    override table can add and change fields but can never remove one. The
    fixture now deletes the key after construction, and the case it was written
    for — an old save reaching a server before Reconcile fills the field — is
    genuinely covered.

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
5. **Disconnecting saves your dinosaur, and that is a decision, not an
   oversight.** A raid voids if the owner leaves mid-carry, because there is no
   loaded profile to transfer from and writing to an unlocked one from another
   session is what ProfileStore's locking exists to prevent. It follows from
   docs/03 §4.3's "offline parks are fully raid-immune" — but it does mean an
   attentive victim can alt-F4 out of any raid.

   Three ways to close it if you want it closed, in increasing cost:
   *(a)* accept it, on the grounds that it costs the victim their session and
   their income while the thief loses only the attempt; *(b)* apply a short
   leaving penalty — a lost shield, or a cooldown before their park earns
   again; *(c)* transfer through a server-authoritative pending queue that
   completes on the victim's next login, which is the only version that truly
   closes it and the only one that can strand a dinosaur if the queue is ever
   lost. I built (a) because it is the one the design documents already imply.
   Worth a decision before launch rather than after the first complaint.

Only #3 blocks anything, and not until Step 7.
