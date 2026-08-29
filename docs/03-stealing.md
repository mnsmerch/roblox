# 03 — Stealing: Wild Eggs, Chase AI, and Player Raiding

The two stealing systems are deliberately different in feel. **Wild theft is
PvE and always winnable.** **Park raiding is PvP and always survivable.**

---

## 1. Wild egg theft — the signature moment

### 1.1 Sequence

| Step | Timing | What happens |
|---|---|---|
| Approach | — | Nest sign shows guardian, risk skulls, rarity odds |
| Hold to grab | **0.6 s hold** (ProximityPrompt) | Guardian's head snaps toward you mid-hold — the "oh no" beat |
| Pickup | t=0 | **Rarity rolled server-side.** Egg parents to your character, held overhead |
| Aura | t=0 | Epic+ eggs emit a visible coloured beam. Everyone on the server can see what you're holding |
| Aggro | t=0.2 s | Guardian roars (camera shake in 80 studs), begins chase |
| Broadcast | t=0.3 s | Legendary+ → server toast: `DAVID JUST GRABBED A LEGENDARY EGG!` |
| Chase | 10–30 s | Speed penalty applied. Guardian pursues with archetype behaviour |
| Resolve | — | Reach your Park Gate → **SAFE**. Or get caught → egg drops |
| Deposit | — | Egg auto-slots into a free incubator, or into egg storage |

### 1.2 Carry penalty

`moveSpeed = base * (1 - CarryPenalty)` where `CarryPenalty` scales with rarity:

| Rarity | Penalty | Effective speed (base 20) |
|---|---:|---:|
| Common | 0 % | 20.0 |
| Uncommon | 4 % | 19.2 |
| Rare | 9 % | 18.2 |
| Epic | 15 % | 17.0 |
| Legendary | 22 % | 15.6 |
| Mythic | 29 % | 14.2 |
| Ancient | 35 % | 13.0 |
| Secret | 40 % | 12.0 |
| Titan | 45 % | 11.0 |

The `Strong Back` upgrade track reduces penalty by up to 60 % (multiplicatively:
a maxed player carries a Titan egg at 20 × (1 − 0.45×0.4) = 16.4).

Carrying **more than one** egg stacks penalties at 40 % effectiveness per extra
egg, so multi-carry is a real risk/reward call rather than a free upgrade.

### 1.3 Getting caught

The guardian tags you → **you trip**. Ragdoll for 1.5 s, 6 s of "Winded"
(−25 % speed), egg pops out and bounces. Then:

- Any player (including you) can re-grab the loose egg for **10 seconds**.
- After 10 s it returns to its nest and is re-rollable.
- The guardian **de-aggros after 3 seconds** and walks home. It does not
  camp you.
- **You lose nothing permanent.** Ever.

That last rule is why the chase can be brutal without being toxic. It also
creates the best PvP moment in the game for free: a loose Mythic egg on the
ground with three players sprinting at it.

### 1.4 Safe zone rules

- The wild chase ends the instant your character's HRP crosses **your own** Park
  Gate plane. Guardians will not enter any park plot.
- Guardians also de-aggro if you leave the zone boundary for > 8 s **or** you
  exceed 250 studs from the nest **or** 45 s elapse (`ChaseTimeout`).
- Other players' parks are **not** safe from your guardian — running into a
  rival's park to hide doesn't work, and their guardian-free zone doesn't
  protect you. (It does stop the guardian at *their* gate too, but you're then
  standing in a park where you can be raided.)
- Hub is neutral: guardians stop at the zone gate, so the hub is always safe
  from PvE but never from PvP.

---

## 2. Guardian behaviour — designed to be funny, not punishing

Global tuning rules:

- Guardian base speed is set **relative to the thief's current speed**, sampled
  at aggro, so upgrades never make chases trivial and low-level players are
  never outrun instantly. `guardianSpeed = thiefSpeed * SpeedRatio` where
  `SpeedRatio` is 0.88–1.06 by archetype.
- Guardians accelerate over 2 s (they *lumber* into a run). This gives a
  guaranteed head start and reads as comedic.
- A guardian that is > 120 studs behind gets a "rubber band" +15 % for 3 s so it
  stays on screen. Tension without unfairness.
- Guardians never one-shot. There is no health, no damage, no death.

---

## 3. Chase archetypes

| Archetype | SpeedRatio | Signature behaviour |
|---|---:|---|
| **Grazer** | 0.88 | Gives up early (25 s timeout). Comedy: stops to eat a bush mid-chase |
| **Skitterer** | 1.02 | Tiny, fast, harmless-looking; swarms in a zigzag |
| **Sprinter** | 1.04 | Straight-line speed, terrible cornering — beat it with turns |
| **Grazer/Honker** | 0.92 | Every 6 s a honk that slows you 15 % for 2 s |
| **Bulldozer** | 0.90 | Smashes through rocks/fences, opening shortcuts *for you* by accident |
| **Charger** | 0.95 | Winds up 1 s, then a 2.5 s charge at 1.8× speed in a straight line. Dodge sideways |
| **Spiker** | 0.90 | Tail sweep in a 12-stud arc, knocks the egg loose without tripping you |
| **Pack Hunter** | 1.00 | 2–3 units that flank; one cuts you off. The scariest and best-looking chase |
| **Spitter** | 0.94 | Ranged goo every 4 s; a hit slows you 30 % for 2 s |
| **Wader** | 0.96 | +25 % speed in water, −10 % on land. Stay dry |
| **Swimmer** | 1.06 in water, 0 on land | Cannot leave water. Terrifying in Z3/Z6, harmless once you're out |
| **Dive Bomber** | 1.02 | Flies, ignores terrain, swoops every 5 s. Dodge by strafing on the swoop tell |
| **Ambusher** | 0.98 | Starts *ahead* of you by predicting your park direction |
| **Slasher** | 0.97 | Long reach (14 studs). Must be out-distanced, not out-turned |
| **Stomper** | 0.86 | Slow, but each footfall creates a 3 s knockback shockwave in 20 studs |
| **Apex** | 0.94 base, 1.35 in 3 s bursts every 8 s | The classic T-Rex burst. Sprint on the cooldown |
| **Leviathan** | 1.00 | Burrows and re-emerges 30 studs ahead. Unpredictable |
| **Glitcher** | 0.99 | Teleports 8 studs randomly every 2 s. Chaotic and hilarious |
| **Blinker** | 1.05 | Void Raptor: teleports directly behind you every 6 s |
| **Rewinder** | 1.00 | Chrono Rex: every 10 s, snaps *you* back to where you were 2 s ago |
| **Titan** | 0.82 | Enormous, slow, but its roar every 7 s stuns you 1.2 s and shakes every screen in the zone |

Suffix `+` variants (Mythic/Ancient guardians) add +0.04 SpeedRatio and reduce
their ability cooldowns by 25 %.

### 3.1 AI implementation notes (efficiency)

Full detail in [09-tech-architecture.md](09-tech-architecture.md) §6. Summary:

- Guardians are **dormant** (no scripts, no physics loop, anchored) until an egg
  in their nest is taken. Idle nests cost nothing.
- Chase logic runs on a **6 Hz** `Heartbeat`-accumulated tick, not per-frame.
- `PathfindingService` is used only for the **initial** path and re-pathed at
  most every 1.5 s **or** on a blocked-path signal — never per tick.
- Between re-paths, guardians steer with simple seek + a 3-ray obstacle
  whisker. This is what makes them feel animalistic anyway.
- Movement is server-side `Humanoid:MoveTo` on a `Model` with `PrimaryPart`
  network-owned by the **server** (never the thief — that's an exploit vector).
- Hard cap: `MAX_ACTIVE_GUARDIANS = 20` per server. Beyond that, new steals
  spawn a "Ghost Chase" — a purely cosmetic client-side guardian that still
  produces the chase feel at zero server cost, and cannot catch you. Rare enough
  that nobody notices; keeps a 40-player server at frame rate.

---

## 4. Player raiding

### 4.1 What is stealable

| Target | Stealable? |
|---|---|
| Dinosaur **placed** in an enclosure | **Yes** |
| Dinosaur on a **Vault Pedestal** | **No, ever** |
| Dinosaur in **storage** (inventory) | No |
| Egg **incubating** | No |
| Egg **carried in the world** | **Yes** — knock the carrier over |
| Banked / collected Fossils | No |

Restricting theft to *placed* dinosaurs and *carried* eggs keeps the rule
explainable in one sentence and means a player's income is only at risk for
things they chose to display.

### 4.2 Raid sequence

1. Walk into another player's park (parks are always enterable).
2. Owner immediately gets `SOMEONE IS IN YOUR PARK!` + a minimap dot.
3. Stand on an enclosure and **hold**. Hold time = `3 s + SecurityLevel × 1.2 s`
   (3 s → 9 s at max security). A giant progress ring is visible to everyone.
4. On completion the dinosaur is lifted onto your back — visible from anywhere,
   with a name tag: `DAVID IS STEALING A MYTHIC ALPHA UTAHRAPTOR`.
5. You are slowed by that dinosaur's `CarryPenalty` **+ 10 %** (raiding is
   heavier than egg-carrying) and you **cannot sprint**.
6. Ownership does **not** transfer yet. You must reach **your own Park Gate**.
7. Owner (or anyone the owner has as a friend in-server) can **tag** you by
   touching you → dino drops and teleports home after 3 s.
8. Reach your gate → ownership transfers, dinosaur auto-places in a free slot,
   `StealCompleted` fires, both players get a notification.
9. If the thief **disconnects while carrying**, the dinosaur returns to its
   owner after a 30-second server-side grace timer. No dupes, no loss.

### 4.3 The rules that make this fair

| Rule | Value | Why |
|---|---|---|
| One carry at a time | 1 dinosaur | No smash-and-grab of a whole park |
| Same-victim cooldown | 10 min | Can't be farmed by one player |
| Global steal cooldown | 90 s | Can't chain-rob the whole server |
| Power floor | Cannot rob a player whose **park value < 25 %** of yours | Stops whales farming beginners |
| Vault Slots | 1 base, +1 at rebirth 3/7/12/20 (max 5), +2 gamepass | Your favourite is *never* at risk |
| New Player Protection | 60 min of playtime **or** until first Rare hatch, whichever is later | Time to understand the game |
| Session shield | 15 min on every join | Lets you set up without being ambushed |
| Mercy Shield | Robbed 3× in 15 min → automatic 10 min shield | Hard anti-griefing floor |
| Daily free shields | 3 × 10 min from quests | Agency without paying |
| Shield stack cap | **2 hours max**, purchased or not | Nobody can buy permanent invulnerability |
| Offline parks | Fully raid-immune | You cannot be robbed while logged out |

That last one matters a lot: **offline players cannot be raided at all.** Their
park still renders and still earns offline income, but it's shielded. This
removes the single biggest source of "I logged in and everything was gone."

### 4.4 Compensation

When you are successfully robbed you receive **Insurance**: 25 % of the stolen
dinosaur's sell value in Fossils, plus a `Revenge Mark` on the thief for 30
minutes. While marked, stealing *from that specific thief* has its hold time
halved and ignores the same-victim cooldown. This turns being robbed into a
revenge quest instead of a loss.

---

## 5. Park defence

Defences never *block* a raid — they buy the owner time to respond. All are
Fossil purchases, none are gamepasses.

| Defence | Levels | Effect |
|---|---:|---|
| **Fence** | 5 | Thief must vault it: +1.0 s per level to escape time |
| **Guard Tower** | 5 | Auto-tags a carrying thief once every 25 s within 40 studs (drops the dino) — level reduces cooldown |
| **Camera** | 5 | Extends intruder-detection alert range; L5 pings you the moment they enter the *hub ring* |
| **Alarm Horn** | 3 | Alerts all your in-server friends, who can also tag the thief |
| **Electric Fence** | 3 | −30 % thief speed while inside your park |

`SecurityLevel` = sum of all defence levels ÷ 4, capped at 5, and feeds the raid
hold time formula in §4.2.

---

## 6. Anti-exploit surface for stealing

Listed here because it's the highest-value cheat target in the game. Enforcement
detail in [09-tech-architecture.md](09-tech-architecture.md) §7.

| Attack | Mitigation |
|---|---|
| Client claims a pickup from across the map | Server re-checks `(HRP.Position - egg.Position).Magnitude <= 18` at the moment of grant |
| Teleport to nest, grab, teleport home | Server tracks per-player position samples at 4 Hz; any displacement > `maxSpeed × dt × 1.6` invalidates carry state and logs `SuspiciousMovement` |
| Spam pickup remote | Central rate limiter: `RequestPickupEgg` = 2/sec, burst 3 |
| Two clients claim the same egg | Egg has a server-side `ClaimedBy` field set inside a single-threaded claim function; second claim is rejected |
| Dupe by leaving mid-carry | Carry state lives **only** on the server as a `CarryToken`; on disconnect the token is resolved (wild egg → nest, stolen dino → owner) before the profile releases |
| Dupe by leaving mid-deposit | Deposit is a single atomic server function: remove token → append to profile → save flag. No client step in between |
| Fake "I reached my gate" | Gate crossing is detected **server-side** by a `Region3`/`GetPartBoundsInBox` check on the server tick, never by a client remote |
| Client-side rarity roll | Rarity is rolled on the server at pickup with `Random.new()` seeded per-server; the client is only *told* the result |
