# 02 — Map Design & Zones

## 1. Map topology

A **hub-and-spoke wheel**. The hub is the social/economic core; ten zones sit on
a ring around it, ordered clockwise by difficulty so a player physically walks
"further out" as they progress. Everything is on one continuous baseplate — no
place-teleports — so distant zones are *visible* from the hub. Seeing the
Volcanic Crater smoking on the horizon at minute two is the single strongest
progression motivator in the whole map.

```
                        Z9 SKY ISLANDS (floating, above Z8/Z10)
                                    ▲
        Z7 ANCIENT RUINS      Z8 METEOR WASTELAND      Z10 TITAN TERRITORY
                  ╲                  │                    ╱
        Z6 LOST JUNGLE ──────  ██ THE HUB ██  ────── Z5 VOLCANIC CRATER
                  ╱                  │                    ╲
        Z1 JURASSIC PLAINS    Z2 ROCKY CANYON       Z4 FROZEN VALLEY
                                     │
                             Z3 SWAMP LANDS
```

**Scale target:** hub ≈ 400×400 studs. Each zone ≈ 350×350 studs. Full map
≈ 2200×2200 studs. Run time hub→Z1 entrance ≈ 6 s; hub→Z10 entrance ≈ 40 s
(before teleports are unlocked).

### 1.1 The Hub contains

| Landmark | Purpose | Placement |
|---|---|---|
| **Spawn Plaza** | A giant amber-encased fossil; players spawn here | dead centre |
| **Park Ring** | 24 park plots in a circle facing inward, each with a numbered arch | inner ring |
| **The Bone Market** | Upgrade shop, boost shop, gamepass board | north of plaza |
| **The Fossil Lab** | Sell / Fusion / DNA / mutation reroll | east |
| **Leaderboard Colosseum** | 8 leaderboards + 3 golden statues of the server's top players | west |
| **Event Arena** | Sunken bowl where map-centre events spawn | south |
| **Signpost Ring** | 10 lit signposts, one per zone, showing unlock cost + best rarity | outer edge |
| **Teleport Obelisk** | Fast-travel to any discovered zone | beside spawn |

Park plots face *inward* on purpose: standing in the plaza you can see every
other player's park skyline at once. That's the status engine.

### 1.2 Navigation rules

- Every zone entrance has a **150-stud-tall glowing gate** in that zone's colour.
- A permanent compass strip at the top of the HUD points at your park.
- Distant zones use `StreamingEnabled` with billboard LOD proxies so a phone
  still sees the volcano silhouette without loading its geometry.
- Zone unlock is **per player**; a locked gate shows a force-field and the cost.

---

## 2. The ten zones

| # | Zone | Id | Theme colour | Rarity ceiling | Hazard / mechanic |
|---|---|---|---|---|---|
| 1 | Jurassic Plains | `plains` | `#7ED957` | Mythic (1 in 10.5 k) | none — flat, wide, forgiving |
| 2 | Rocky Canyon | `canyon` | `#C98A4B` | Mythic | Narrow ledges; falling rocks knock the egg loose |
| 3 | Swamp Lands | `swamp` | `#4C7A5A` | Ancient | Mud pools: −35 % speed. Bridges are the safe route |
| 4 | Frozen Valley | `frozen` | `#8FD9F5` | Ancient | Ice: momentum sliding. Blizzard pockets blind you |
| 5 | Volcanic Crater | `volcano` | `#FF6B2C` | Secret | Lava geysers launch you (fun, not fatal); ash slows |
| 6 | Lost Jungle | `jungle` | `#1E8C5A` | Secret | Dense canopy hides nests; vines you can swing on |
| 7 | Ancient Ruins | `ruins` | `#C6B57E` | Secret | Pressure-plate traps; collapsing floors |
| 8 | Meteor Wasteland | `wasteland` | `#8E5BD4` | Secret | Radiation zones: +mutation chance but a slow debuff |
| 9 | Sky Islands | `sky` | `#9FD6FF` | Titan | Floating platforms, jump pads, wind gusts, fall = respawn at gate |
| 10 | Titan Territory | `titan` | `#FFD24A` | Titan (1 in 8.3 k) | Permanent quake; Titan guardians roam between nests |

### 2.1 Unlock gating

Deliberately mixed gates so progress never depends on one axis alone.

| Zone | Fossils | Rebirths | Other |
|---|---:|---:|---|
| 1 | free | 0 | — |
| 2 | 5,000 | 0 | — |
| 3 | 45,000 | 0 | — |
| 4 | 400,000 | 0 | — |
| 5 | 3,500,000 | 1 | — |
| 6 | 28,000,000 | 2 | — |
| 7 | 220,000,000 | 4 | Index ≥ 25 % |
| 8 | 1,800,000,000 | 6 | Index ≥ 40 % |
| 9 | 15,000,000,000 | 9 | Index ≥ 55 %, own 1 Mythic |
| 10 | 140,000,000,000 | 13 | Index ≥ 70 %, own 1 Ancient |

Zones 1–4 are pure money → a Day-1 player reaches Zone 4. Zone 5 introduces the
rebirth gate at roughly the 3-hour mark, which is exactly when players are ready
to be *taught* what rebirth is.

### 2.2 Zone contents

Each zone contains:

- **6–14 nest sites** at fixed anchor points (`NestAnchor` tagged parts).
- **1–3 Landmark props** for navigation (a crashed helicopter, a giant skull
  arch, a frozen mammoth, a broken obelisk).
- **1 Shortcut** back toward the hub — a zipline, river, or drop tube. Shortcuts
  are the skill expression of the chase: knowing them turns a 25-second panic
  into a 12-second flex.
- **1 Zone Shrine.** Interact once to permanently register the zone on your
  Teleport Obelisk and grant a small one-time Fossil bonus.

### 2.3 Nests

A nest is a `Model` at a `NestAnchor` with:

- **Nest sign** — a floating billboard showing: guardian species, a **Risk**
  rating (1–5 skulls), and the zone's top three possible rarities with odds.
  This is the "read before you commit" moment; it makes stealing a *decision*.
- **1–3 eggs** visible in the nest, each an independent steal target.
- **1 guardian** (occasionally 2–3 for Pack Hunter archetypes) patrolling.
- **Respawn:** an emptied nest refills after `NestRespawn = 45 s` (Zone 1) up to
  `180 s` (Zone 10). During the Nest Frenzy event this drops to 3 s server-wide.

**Zone-scaled nest counts and respawn:**

| Zone | Nests | Eggs/nest | Respawn | Guardians/nest | Base Luck bonus |
|---|---:|---:|---:|---:|---:|
| 1 | 14 | 3 | 45 s | 1 | +0 % |
| 2 | 12 | 3 | 55 s | 1 | +2 % |
| 3 | 12 | 2 | 70 s | 1–2 | +4 % |
| 4 | 10 | 2 | 85 s | 1–2 | +6 % |
| 5 | 10 | 2 | 100 s | 2 | +9 % |
| 6 | 9 | 2 | 115 s | 2 | +12 % |
| 7 | 8 | 2 | 130 s | 2 | +15 % |
| 8 | 8 | 1 | 145 s | 2–3 | +18 % |
| 9 | 7 | 1 | 160 s | 2 | +21 % |
| 10 | 6 | 1 | 180 s | 3 | +25 % |

---

## 3. Player park plots

24 plots ringing the hub, assigned on join, released on leave. A plot is a
**flat 120×120 stud pad** with:

- **Park Gate** — the safe-zone threshold. Crossing it inward ends any wild
  chase and deposits carried eggs.
- **Safe Dome** — a translucent hemisphere, visible only when a shield is
  active, in the owner's shield colour.
- **Enclosure Grid** — an 8×8 grid of placement tiles. Dinosaurs occupy 1×1
  through 4×4 tiles. Park Size upgrades unlock tiles outward from centre.
- **Incubator Row** — up to 8 incubator pads along the gate wall, deliberately
  the *first* thing a visitor sees.
- **Vault Pedestals** — 1–5 raised, caged pedestals. Dinosaurs here are
  **unstealable**. Glowing gold, obviously precious, obviously taunting.
- **Collection Totem** — tap to collect banked Fossils.
- **Defence Slots** — fences, towers, cameras (see [03-stealing.md](03-stealing.md) §5).
- **Decoration slots** — cosmetic only (V1.4+).

**Park visual tiers** (auto-applied by total park value, no purchase needed):
Dirt Lot → Wooden Ranch → Stone Preserve → Steel Facility → Amber Kingdom →
Titan Sanctuary. Each retextures ground, fences and gate. This is free, visible
progression that makes a returning player's park look different, which is a
strong D7 hook.
