# 05 — Economy Model

## 1. Currencies

Exactly **two** in-game currencies. Anything more is confusing for a 7-year-old.

| Currency | Symbol | Source | Sink |
|---|---|---|---|
| **Fossils** | 🦴 amber-gold | Passive dinosaur income, quests, dailies, events, offline income, selling | Upgrades, zone unlocks, defences, auctions, incubator slots |
| **DNA** | 🧬 green vial | Selling dinosaurs, Amber Rain, index milestones, duplicates | Fusion (Stars), mutation rerolls, permanent luck nodes |

**Robux** is the third, platform currency. There is no premium *soft* currency
— no "gems" that Robux buys and that also drip free. That pattern is designed to
obscure real prices and I'm not building it. Robux buys boosts and convenience
directly, at a stated price.

Fossils are the throughput currency; DNA is the *depth* currency. They never
convert into each other.

---

## 2. The master income formula

```lua
incomePerSecond =
      RarityBase[rarity]                 -- 2 … 200,000
    * SpeciesFactor                      -- 0.80 … 1.30
    * MutationMultiplier                 -- 1 … 150 (× second mutation if Prime)
    * StarMultiplier                     -- 1 + 0.35 * (stars - 1)   (stars 1-5)
    * (1 + 0.15 * rebirths)              -- permanent, additive
    * ParkIncomeMultiplier               -- from the Feeding Trough upgrade track
    * EnclosureBonus                     -- 1.00 / 1.10 / 1.25 by enclosure tier
    * WeatherIncomeMultiplier            -- 1.0, or 1.2 in Heatwave
    * GamepassIncomeMultiplier           -- 1.0 or 2.0 (Double Income)
```

Park total = sum over all **placed** dinosaurs. Stored dinosaurs earn nothing —
this is what makes placement slots the core sink.

**Worked example.** A rebirth-6 player with a Star-3 Golden Mythic Emberback
Spinosaurus (SF 1.20), Feeding Trough L8 (×2.1), Steel enclosure (×1.25), no
gamepass, clear weather:

```
2200 × 1.20 × 2 × (1+0.35×2) × (1+0.15×6) × 2.1 × 1.25 × 1.0 × 1.0
= 2200 × 1.20 × 2 × 1.70 × 1.90 × 2.1 × 1.25
= 44,747 Fossils/sec
```

That one dinosaur out-earns an entire early park by ~4 orders of magnitude,
which is exactly the feeling we want when a Mythic hatches.

---

## 3. Income collection

Income accrues into a **Bank** on the park's Collection Totem, visible as a
growing pile of amber that physically stacks higher.

- Bank cap = `60 × parkIncomePerSecond × (1 + 0.5 × BankUpgradeLevel)`, i.e. one
  minute of income at level 0, up to six minutes at max. This forces the player
  back to their park regularly — the "come home" beat of the loop — without
  being punishing.
- Tapping the totem collects everything with a coin-cascade VFX and a rising
  chime pitched by amount.
- Individual dinosaurs also spawn small `+N` floaters at random intervals so the
  park always looks alive. Floaters are **cosmetic only** — the real number is
  the server-side bank. Never let a client-side visual be the source of truth.
- **Auto-Collect** is a *free* upgrade (not a gamepass), unlocked at rebirth 2,
  which empties the bank into your wallet every 30 s. VIP starts with it.

## 4. Offline income

```
offlineFossils = parkIncomePerSecond
               * min(secondsAway, offlineCapSeconds)
               * offlineRate
offlineCapSeconds = 4h + 1h per rebirth, capped at 12h
offlineRate       = 0.60   (1.00 with VIP)
```

Return screen: `YOUR DINOSAURS EARNED 2,450,000 FOSSILS WHILE YOU WERE AWAY!`
with a per-dinosaur breakdown and a big Collect button.

60 % of active rate means a fully idle player progresses at well under half the
speed of an active one, so the chase still matters — but a kid who can only play
20 minutes a day still feels progress every session.

---

## 5. Upgrade costs

All upgrades use `cost(n) = Base × Growth^(n-1)`, rounded to 3 significant
figures. Growth is deliberately varied so the "best next buy" changes over time.

| Track | Levels | Base | Growth | Per level | Max effect |
|---|---:|---:|---:|---|---|
| **Dino Slots** | 26 (4→30) | 800 | 1.72 | +1 placement slot | 30 slots |
| **Park Size** | 6 | 25,000 | 4.10 | unlocks a grid ring | 8×8 full grid |
| **Incubators** | 6 (2→8) | 3,500 | 2.55 | +1 incubator | 8 |
| **Incubator Speed** | 15 | 1,200 | 1.61 | −4 % hatch time | −60 % |
| **Incubator Genetics** | 15 | 6,000 | 1.78 | +5.33 % MutLuck | +80 % |
| **Egg Sense** (luck) | 15 | 4,000 | 1.83 | +5 % Luck | +75 % |
| **Feeding Trough** (income) | 20 | 2,000 | 1.66 | +8 % park income | ×2.6 |
| **Runner's Legs** (speed) | 12 | 1,500 | 1.90 | +2 % move speed | +24 % |
| **Strong Back** (carry) | 10 | 5,000 | 1.95 | −6 % carry penalty | −60 % |
| **Egg Pouch** (capacity) | 4 (1→5) | 9,000 | 3.40 | +1 carried egg | 5 |
| **Bank Size** | 10 | 3,000 | 1.75 | +0.5 min of storage | 6 min |
| **Dino Storage** | 12 (25→200) | 4,500 | 1.80 | +15 storage | 200 |
| **Nest Radar** | 8 | 12,000 | 2.05 | +18 studs egg-detection ring on minimap | +144 studs |
| **Fence** | 5 | 15,000 | 2.80 | +1.0 s raid time | +5 s |
| **Guard Tower** | 5 | 60,000 | 3.10 | −4 s tag cooldown | 25 s → 5 s |
| **Camera** | 5 | 40,000 | 2.90 | +60 studs alert range | +300 studs |
| **Alarm Horn** | 3 | 120,000 | 3.60 | friend alerts | — |
| **Electric Fence** | 3 | 400,000 | 4.20 | −10 % thief speed | −30 % |

**Design check — is there always something to buy?** At every point in the
curve, the cheapest un-maxed upgrade costs less than **180 seconds** of the
player's current income. Verified against the simulation in §8. This is a hard
constraint; any new upgrade added later must be re-checked against it.

---

## 6. Rebirth

```
rebirthCost(n) = 250,000 * 5.2^(n-1)     -- Fossils, must also own n+2 dinosaurs
```

| Rebirth | Fossil cost | Approx. time to reach (active) |
|---:|---:|---|
| 1 | 250 K | ~2.5 h |
| 2 | 1.30 M | ~4 h |
| 3 | 6.76 M | ~6 h |
| 5 | 183 M | ~14 h |
| 8 | 25.7 B | ~2.5 days |
| 12 | 18.8 T | ~1 week |
| 20 | 5.4 × 10¹⁹ | ~1 month |

**What resets:** Fossils, all Fossil-purchased upgrade levels, placed and
stored dinosaurs *except* Vault Pedestal residents (up to 5), zone unlocks
above the highest **rebirth-gated** zone you qualify for.

**What never resets:** Index progress, DNA, Stars on Vaulted dinosaurs, quests,
dailies, gamepasses, statistics, badges, settings, Vault Slot count.

**What you gain per rebirth:**

| Benefit | Per rebirth | Cap |
|---|---|---|
| Income multiplier | +15 % additive | none |
| Luck | +5 % | +75 % (R15) |
| Mutation luck | +3 % | +45 % (R15) |
| Move speed | +2 % | +40 % (R20) |
| Offline cap | +1 h | 12 h |
| Dino slots | +1 every 2 rebirths | +10 |
| Vault slots | at R3, R7, R12, R20 | 5 total |
| Name tag tier | R1/5/10/20/40 | Bone → Amber → Obsidian → Prismatic → Titan |

**Anti-repetition rule.** Every rebirth grants a **Rebirth Cache**: one
guaranteed egg of the highest rarity you have ever hatched, minus one tier
(min Rare). So rebirth 8 hands a Mythic player an Epic egg immediately — you
never restart from literally nothing, and the early grind compresses each time.

---

## 7. Reward values

### Daily rewards (7-day cycle, resets on a missed day; streak bonus persists)

Fossil rewards scale with player power (`R` = rebirth count) so they stay
relevant: `dailyFossils = base × (1 + 0.9 × R)`.

| Day | Reward |
|---|---|
| 1 | 2,500 Fossils |
| 2 | 6,000 Fossils + 1 Luck Potion (15 min, +100 % Luck) |
| 3 | 15,000 Fossils + 25 DNA |
| 4 | 40,000 Fossils + 1 Mutation Serum (10 min, +150 % MutLuck) |
| 5 | 100,000 Fossils + 1 Rare Egg + 1 Park Shield (10 min) |
| 6 | 250,000 Fossils + 75 DNA + 1 Instant Hatch token |
| 7 | **1 guaranteed Epic Amber Egg** + 500,000 Fossils + 150 DNA + 2× Luck (30 min) |

**Streak rewards** at 7 / 14 / 30 / 60 / 100 consecutive days: cosmetic titles,
+1 permanent Vault Slot at 30, an exclusive **Amberling Compsognathus** skin at
60, and an exclusive **Fossilkeeper Triceratops** (Mythic, non-tradeable) at 100.

### Daily quests (3 active, reroll 1 per day free)

| Quest | Reward |
|---|---|
| Steal 5 wild eggs | 8,000 F |
| Hatch 10 dinosaurs | 12,000 F |
| Earn 100,000 Fossils | 15,000 F |
| Steal a dinosaur from another player | 20,000 F + 1 Shield |
| Discover a new species | 25,000 F + 10 DNA |
| Participate in a server event | 18,000 F + 1 Luck Potion |
| Visit another player's park | 5,000 F |
| Escape 3 chases without being caught | 14,000 F |
| Place 3 dinosaurs | 10,000 F |
| Collect income 5 times | 6,000 F |
| Survive a raid attempt | 22,000 F |
| Hatch an egg during a special weather | 20,000 F + 15 DNA |

All Fossil values are multiplied by `(1 + 0.9 × rebirths)`.

### Weekly quests (3 active, Monday reset)

| Quest | Reward |
|---|---|
| Steal 100 wild eggs | 400,000 F + 200 DNA |
| Hatch 5 Epic or better | 600,000 F + 1 Legendary Egg |
| Complete 20 daily quests | 750,000 F + 1 permanent +1 % Luck node |
| Steal 10 dinosaurs from players | 500,000 F + 2 Shields |
| Participate in 15 server events | 450,000 F + 300 DNA |
| Reach a new zone | 1,000,000 F |

### Index milestones

| Species discovered | Reward |
|---:|---|
| 10 | +1 % permanent Luck, 50 DNA |
| 20 | +1 % Luck, 1 Epic Egg, 150 DNA |
| 30 | +1 % Luck, +1 Dino Slot, 400 DNA |
| 40 | +1 % Luck, 1 Legendary Egg, 1,000 DNA |
| 50 | +1 % Luck, +1 Vault Slot, 2,500 DNA |
| 60 (all) | +1 % Luck, exclusive **Curator's Fossilborn Rex** (Ancient), title `Curator`, 10,000 DNA |

Per-rarity completion sets grant a further +2 % Luck each (9 sets → +18 %).

---

## 8. Economy simulation — the shape of the curve

Modelled for an *active* player (≈ 12 eggs/hour in early zones, falling to
≈ 7/hour in late zones as chases get longer).

| Elapsed | Zone | Placed dinos | Income/sec | Total earned | Milestone |
|---|---|---:|---:|---:|---|
| 5 min | 1 | 3 | 6 | 900 | First upgrade |
| 20 min | 2 | 6 | 45 | 11 K | Zone 2 |
| 1 h | 3 | 10 | 380 | 95 K | First Rare, Zone 3 |
| 2 h | 3–4 | 14 | 2,100 | 620 K | Zone 4, first Epic |
| 3 h | 4 | 16 | 5,400 | 1.6 M | **Rebirth 1** |
| 6 h | 5 | 18 | 34,000 | 12 M | Zone 5, first Legendary |
| 12 h | 6 | 22 | 480,000 | 340 M | Rebirth 3–4 |
| 24 h | 6–7 | 24 | 6.2 M | 6.8 B | Zone 7, first Mythic |
| 3 days | 8 | 27 | 190 M | 480 B | Rebirth 7 |
| 1 week | 9 | 30 | 14 B | 62 T | Rebirth 11, first Ancient |
| 1 month | 10 | 36 | 9 × 10¹⁵ | ~10¹⁹ | Rebirth 20+, Secret hunting |

**Growth rate:** roughly **×3.5 income per hour** in the first 6 hours, easing
to **×2.2 per hour** by day 2, and **×1.35 per hour** by week 2. Fast enough to
feel explosive on day one; slow enough that week-one players still have a
mountain to climb.

**Number formatting:** short-scale suffixes to Sx (sextillion), then switch to
`aa, ab, ac…` notation. Cap display at 15 characters. Store all currency as
Lua numbers (doubles, exact to 2⁵³) and hard-clamp at `1e30`; anything beyond
that saturates with a `MAX` display. Never store currency as a string, and
never let a client send a currency delta.

---

## 9. Inflation control (the sinks)

Idle-game economies die when income outruns sinks. Four valves:

1. **Geometric upgrade costs** with growth ≥ 1.6 always outrun linear income
   gains within a track.
2. **Rebirth** hard-resets the Fossil supply — the primary deflation event.
3. **Fossil Auction** event removes Fossils from the winner permanently.
4. **Zone costs** at ×8–10 per zone act as staged walls.

Monitoring: log `EconomySnapshot` hourly per player (see
[14-analytics.md](14-analytics.md)). If median Fossils-held rises faster than
median upgrade-cost-tier for 3 consecutive days, growth constants get raised
before content gets added.
