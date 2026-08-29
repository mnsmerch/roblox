# 14 — Analytics

Roblox provides `AnalyticsService` with `LogCustomEvent`, `LogEconomyEvent`,
`LogFunnelStepEvent`, `LogOnboardingFunnelStepEvent` and `LogProgressionEvent`.
`AnalyticsService` is used for the funnels Roblox's own dashboard understands;
everything else goes to `LogCustomEvent` and, if we later want deeper analysis,
an external sink.

**I'll verify each method's exact current signature against the Creator
Documentation at implementation time (Step 24) rather than guessing here** —
these APIs have changed shape before, and a wrong signature fails silently,
which is the worst failure mode for telemetry.

---

## 1. Events to log

### Onboarding funnel (`LogOnboardingFunnelStepEvent`)

| Step | Name |
|---:|---|
| 1 | `TutorialStarted` |
| 2 | `TutorialReachedZone` |
| 3 | `TutorialEggStolen` |
| 4 | `TutorialEscaped` |
| 5 | `TutorialEggDeposited` |
| 6 | `TutorialHatched` |
| 7 | `TutorialDinoPlaced` |
| 8 | `TutorialIncomeCollected` |
| 9 | `TutorialUpgradeBought` |
| 10 | `TutorialCompleted` |

Step-to-step drop-off here is the single most valuable number in the game.

### Progression (`LogProgressionEvent`)

`ZoneUnlocked` (zoneId), `RebirthCompleted` (n), `IndexMilestone` (n),
`FirstRarity` (rarity tier — logged once per tier per player).

### Economy (`LogEconomyEvent`)

Every Fossil and DNA flow, tagged source/sink:
`income_collect`, `income_offline`, `quest`, `daily`, `event`, `sell`,
`upgrade`, `defence`, `zone_unlock`, `reroll`, `fuse`, `auction`,
`robux_pack`, `insurance`, `rebirth_reset`.

### Custom events (`LogCustomEvent`)

**Core loop**
`EggStolen` (rarity, zone, guardianArchetype) ·
`EggLost` (rarity, zone, cause: caught|dropped|timeout|pvp) ·
`ChaseStarted` / `ChaseEscaped` / `ChaseCaught` (duration, archetype) ·
`EggDeposited` · `IncubationStarted` · `EggHatched` (rarity, species, mutation,
mutation2, wasPrime, weather) · `DinoPlaced` · `DinoStored` · `DinoSold` ·
`DinoFused`

**PvP**
`StealAttempted` (targetPower, myPower) · `StealCompleted` ·
`StealFailed` (cause: tagged|cancelled|disconnect) · `PlayerRobbed` ·
`RaidSurvived` · `ShieldActivated` (source) · `MercyShieldTriggered` ·
`VaultUsed` · `RevengeMarkUsed`

**Content engagement**
`ZoneEntered` · `ServerEventStarted` · `ServerEventJoined` (eventId) ·
`ServerEventReward` (tier) · `WeatherStarted` (weatherId) ·
`QuestCompleted` · `DailyClaimed` (day, streak) · `IndexDiscovered` (species)

**Monetization**
`ShopOpened` (tab) · `GamepassPromptShown` · `GamepassPurchased` (id, price) ·
`ProductPromptShown` · `ProductPurchased` (id, price) ·
`ServerBoostPurchased` (id, playersInServer) · `ThanksSent`

**Health**
`SessionStart` (device, isNew) · `SessionEnd` (durationSecs, reason) ·
`DataLoadFailed` · `DataSaveFailed` (attempts) · `SchemaMigrated` (from, to) ·
`ExploitFlag` (kind, remote) · `SuspiciousMovement` (delta) ·
`ConfigValidationFailed` (rule) · `FrameTimeSample` (p50, p10, deviceClass) ·
`EconomySnapshot` (hourly: fossils, income/s, rebirths, zone, placedCount)

---

## 2. The metrics that actually matter

Ranked by how much a bad number costs us.

| # | Metric | Target | If it's bad |
|---:|---|---|---|
| 1 | **Tutorial completion** | ≥ 75 % | The first 3 minutes are broken. Fix before anything else |
| 2 | **Day 1 retention** | ≥ 32 % | The first session doesn't deliver a reveal. Check first-rare timing |
| 3 | **Day 7 retention** | ≥ 10 % | The mid-game is thin. Check rebirth-1 timing and Index pace |
| 4 | **Median session length** | ≥ 16 min | Loop friction. Check chase length and travel time |
| 5 | **Sessions per DAU** | ≥ 2.1 | Nothing is pulling players back. Check incubation timing and events |
| 6 | **Eggs stolen / session** | 10–20 | Below → chases are too punishing. Above → they're trivial |
| 7 | **Chase escape rate** | 62–75 % | The whole difficulty curve lives in this one number |
| 8 | **Time to first Rare** | 12–25 min | The first real dopamine hit |
| 9 | **Time to Rebirth 1** | 2.5–4 h | Off → the whole economy curve is wrong |
| 10 | **Conversion** | 3–6 % | Shop discoverability or value |
| 11 | **ARPDAU** | ~9 R$ | |
| 12 | **ARPPU** | 350–650 R$ | Above 900 → over-monetizing whales; add low-tier value |
| 13 | **Robbed-then-churned rate** | < 8 % | The protection systems aren't working. This is the one that kills kids' games |
| 14 | **Crash-free sessions** | ≥ 99.5 % | |
| 15 | **p10 frame rate (mobile)** | ≥ 45 fps | |

**Metric 13 deserves special attention.** Cross-reference `PlayerRobbed` with
`SessionEnd` within 10 minutes and with next-day return. If being robbed
measurably drives churn, the response is to strengthen Vault Slots, Mercy
Shields and Insurance — not to remove stealing, which is the game's identity.

---

## 3. Funnels to build

1. **Onboarding:** join → tutorial start → each of the 10 beats → first free
   action → 5-minute mark → 15-minute mark.
2. **First steal:** enter zone → approach nest → hold started → hold completed →
   chase → escaped → deposited → hatched → placed. Drop-off between "hold
   started" and "hold completed" measures whether the risk read is scaring
   people off.
3. **Monetization:** shop opened → item viewed → prompt shown → purchased.
4. **Progression:** Zone 1 → 2 → 3 → 4 → Rebirth 1 → Zone 5.
5. **Retention cohorts:** by acquisition day, by device class, by whether they
   completed the tutorial, and by whether they were robbed on day 1.

---

## 4. Sampling & cost

- `FrameTimeSample` and `EconomySnapshot` are sampled at **10 %** of players.
- High-frequency loop events (`EggStolen`, `EggHatched`) are logged in full —
  they're the core dataset.
- No personally identifying data is logged. UserIds only, never usernames, never
  chat content.
- All logging is wrapped in `pcall` and is entirely fire-and-forget. **Analytics
  must never be able to break gameplay** — if a log call throws, the game
  continues and the failure itself is counted locally.
