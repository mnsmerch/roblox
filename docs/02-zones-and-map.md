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

**Scale, as built.** Every radius is derived rather than chosen, so changing a
count cannot silently overlap anything:

| Ring | Extent | Derived from |
|---|---|---|
| Hub plaza | 0 → 226 | reaches the park ring's inner edge |
| Park ring | 226 → 346 | `6 × (120 + 180) ÷ 2π` = 286 centre |
| Walk | 346 → 525 | 179 studs of open ground |
| Zone ring | 525 → 875 | 700 centre, zones 350 across |

Zones occupy **10 reserved slots** even though V1 fills four, so zones 5–10 drop
into their eventual positions without moving a landmark a player has learned.
Slot 1 is on +X and they run anticlockwise in zone order, so progressing means
physically walking further around the ring. At the full ten-zone build-out
neighbouring zones still clear each other by 168 studs — asserted in
`tests/step7_spec.lua`.

### 1.1 The Hub contains

| Landmark | Purpose | Placement |
|---|---|---|
| **Spawn Plaza** | A giant amber-encased fossil; players spawn here | dead centre |
| **Park Ring** | 6 park plots in a circle facing inward, each with a numbered arch | inner ring |
| **The Bone Market** | Upgrade shop, boost shop, gamepass board | north of plaza |
| **The Fossil Lab** | Sell / Fusion / DNA / mutation reroll | east |
| **Leaderboard Colosseum** | 8 leaderboards + 3 golden statues of the server's top players | west |
| **Event Arena** | Sunken bowl where map-centre events spawn | south |
| **Signpost Ring** | 10 lit signposts, one per zone, showing unlock cost + best rarity | outer edge |
| **Teleport Obelisk** | Fast-travel to any discovered zone | beside spawn |

*(**Six plots, not 24.** The first Studio session showed why: a ring of tiny
parks stretching to the horizon across an empty plain. `RingRadius` is derived
from the plot count, so 24 plots forced a 573-stud ring, a 520-stud plaza, a
950-stud zone ring, and a walk to Jurassic Plains of up to 1,348 studs — 67
seconds against a beat budgeted at 15. Six is what the games this one is aimed
at run: Grow a Garden around 8, Steal an Egg around 6. It also makes "standing
in the plaza you can see every other player's park skyline at once" true, which
at 24 it was not — they were dots. Everything followed: ring 286, plaza 226,
zone ring 700, longest walk 811.*

*Server size must match: `MaxPlayers = 6` in Game Settings, asserted at boot.)*

*(V1 builds **4** pillars, one per shipped board — docs/12's Richest, Highest
Income, Most Eggs Stolen, Highest Rebirth — plus all 3 statues. The arc spacing
is derived from the board count, so V1.4's four extra boards space themselves.
Four blank slabs would teach a player nothing, the same reason the Index counts
what exists rather than what is planned.)*

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

- **6–14 nest sites** at parts tagged `SAD_NestAnchor`. Positions come from a
  **golden-angle spiral**: deterministic, so a nest is in the same place every
  session and players learn the map, and evenly spread without the clustering
  random scatter produces. No seeds and no hand-tuning; the spec asserts a
  minimum 26-stud gap holds even if `NestCount` is raised to 24.
- **1–3 Landmark props** for navigation (a crashed helicopter, a giant skull
  arch, a frozen mammoth, a broken obelisk).
- **1 Shortcut** back toward the hub — a zipline, river, or drop tube. Shortcuts
  are the skill expression of the chase: knowing them turns a 25-second panic
  into a 12-second flex.
- **1 Zone Shrine.** Interact once to permanently register the zone on your
  Teleport Obelisk and grant a small one-time Fossil bonus (500 F).

> **Unlocked and discovered are different things.** Paying a zone's gate lets
> you walk in; touching its shrine is what puts it on the Obelisk. So the first
> trip to any zone is always walked, which is what teaches the map before the
> game lets you skip it. The profile tracks the two separately
> (`ZonesUnlocked` and `Shrines`).
>
> **A teleport is refused while a guardian is chasing you.** Otherwise the PARK
> button deletes the chase — steal, tap, bank, with the only risk in the game
> skipped. Teleports remove the *unopposed* walk home after an escape, which is
> tax; they do not remove the escape, which is the game. This follows the same
> line docs/03 §1.4 draws.
>
> **The gate barrier is scenery.** A part cannot be solid for one player and
> passable for another, so the force-field across a locked gate is cosmetic
> (each client hides the ones it has unlocked) and the server walks a
> trespasser back out from a positional check. Both halves ship together.

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

6 plots ringing the hub, assigned on join, released on leave, **generated
procedurally** by `PlotBuilder` — 24 identical plots is exactly what you do not
want hand-placed in a `.rbxl`: it cannot be diffed, a fix has to be applied to
every plot, and changing the ring radius means moving everything.

The ring radius is **derived**, not chosen: 6 plots each 120 wide with 180 studs
of clearance need 1,800 studs of circumference, so the ring sits at 1800 ÷ 2π ≈
**286**. Picking a radius by hand is how plots overlap the moment `PlotCount`
changes — and being derived is what let the drop from 24 plots to 6 resize the
whole world correctly without a single other distance being retuned by hand.
`tests/step6_spec.lua` asserts non-overlap via a separating-axis test at both
the shipped count and 48 plots.

A plot is a **flat 120×120 stud pad** with:

- **Park Gate** — the safe-zone threshold. Crossing it inward ends any wild
  chase and deposits carried eggs.
- **Safe Dome** — a translucent hemisphere, visible only when a shield is
  active, in the owner's shield colour.
- **Enclosure Grid** — an 8×8 grid of 10-stud placement tiles. Dinosaurs occupy
  1×1 through 4×4. **The grid is mathematical, not physical**: one textured
  surface part plus `ParkConfig.TileToOffset` / `OffsetToTile`. Sixty-four parts
  per plot would be 1,536 anchored parts across the ring to express a
  coordinate transform. Park Size upgrades unlock tiles outward from centre
  (V1.4; all 64 are available in V1, with `dinoSlots` limiting quantity).
- **Incubator Row** — up to 8 incubator pads along the gate wall, deliberately
  the *first* thing a visitor sees.
- **Vault Pedestals** — 1–5 raised, caged pedestals. Dinosaurs here are
  **unstealable**. Glowing gold, obviously precious, obviously taunting.
- **Collection Totem** — tap to collect banked Fossils.
- **Defence Slots** — fences, towers, cameras (see [03-stealing.md](03-stealing.md) §5).
- **Decoration slots** — cosmetic only (V1.4+).

**Plot depth budget** (local Z, gate at +60 to back wall at −60), asserted
arithmetically so a fixture can never poke through a wall or land on the grid:

| Row | Front | Back |
|---|---:|---:|
| Spawn pad | +58 | +50 |
| Incubator row | +50 | +42 |
| Enclosure grid | +38 | −42 |
| Vault pedestals | −49.5 | −58.5 |

**Park visual tiers** (auto-applied by total park value, no purchase needed):
Dirt Lot → Wooden Ranch → Stone Preserve → Steel Facility → Amber Kingdom →
Titan Sanctuary. Each retextures ground, fences and gate. This is free, visible
progression that makes a returning player's park look different, which is a
strong D7 hook.
