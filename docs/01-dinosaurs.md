# 01 — Rarity System & Dinosaur Roster

## 1. Rarity ladder (9 tiers)

I reordered your list: **Ancient before Secret**. Reason — *Ancient* reads as
"the deep-history capstone of normal progression" and fits the fossil theme, so
it works as the tier a dedicated player can realistically grind to. *Secret*
should mean "you weren't supposed to see this," which only works if it sits
above the grindable ceiling. *Titan* stays at the top as the event/apex tier.

| # | Rarity | Hex | Visual identity | Announcement |
|---|---|---|---|---|
| 1 | **Common** | `#E8E4D9` Bone White | Flat colour, no VFX | none |
| 2 | **Uncommon** | `#5FD35F` Fern | Faint dust puff on step | none |
| 3 | **Rare** | `#3FA9F5` Sky | Soft blue rim light | none |
| 4 | **Epic** | `#A050F0` Amethyst | Purple sparkle trail | park-local popup |
| 5 | **Legendary** | `#FFB020` Amber Gold | Gold aura + light beam | **server toast** |
| 6 | **Mythic** | `#FF4B3E` Magma | Ember particles, screen-shake roar | **server banner + sound** |
| 7 | **Ancient** | `#17C6A3` Fossil Teal | Stone-crack skin, floating runes | **server banner + camera cut** |
| 8 | **Secret** | `#1A1A24` Void Black w/ white glitch | Reality-tear VFX, silhouette flickers | **server takeover + cross-server** |
| 9 | **Titan** | `#FFD24A` Prismatic | 3× scale, ground shakes, sky darkens | **server takeover + cross-server + badge** |

### 1.1 Base hatch weights

Weights are integers out of **100,000,000** (`RARITY_WEIGHT_TOTAL`). Integer
weights avoid float drift and make luck maths exact. Each **zone** has its own
weight vector; higher zones shift mass upward. Three representative vectors:

| Rarity | Zone 1 (Jurassic Plains) | Zone 5 (Volcanic Crater) | Zone 10 (Titan Territory) |
|---|---:|---:|---:|
| Common | 62,000,000 | 24,000,000 | 0 |
| Uncommon | 27,000,000 | 33,000,000 | 12,000,000 |
| Rare | 9,000,000 | 26,000,000 | 30,000,000 |
| Epic | 1,800,000 | 12,000,000 | 33,000,000 |
| Legendary | 190,000 | 4,300,000 | 18,000,000 |
| Mythic | 9,500 | 620,000 | 6,000,000 |
| Ancient | 480 | 74,000 | 880,000 |
| Secret | 19 | 5,600 | 108,000 |
| Titan | 1 | 400 | 12,000 |
| **Total** | **100,000,000** | **100,000,000** | **100,000,000** |

Zone-1 Titan odds are **1 in 100,000,000** — effectively "a new player will
never get one, but the number on the nest sign says it's *possible*," which is
exactly the hook. Zone-10 Titan is **1 in 8,333**, a realistic endgame chase.

Zones 2, 3, 4, 6, 7, 8, 9 interpolate between these; the full table lives in
`RarityConfig.ZoneWeights` (see [11-content-config.md](11-content-config.md)).

> **V1 shipping values differ from this table.** Version 1 ships no Mythic and
> no Ancient species, so those tiers carry weight **0** in the live V1 vectors
> and their mass is folded into Legendary. A non-zero weight for a tier with no
> species to hatch is precisely what ConfigValidator rule 6 refuses to boot on.
> The V1 numbers live in `RarityConfig.ZoneWeights`; the table above is the
> design target that V1.1 and V1.3 restore as those species ship.
>
> V1 Zone 1: Common 62,000,000 · Uncommon 27,000,000 · Rare 9,000,000 ·
> Epic 1,800,000 · Legendary 199,980 · Secret 19 · Titan 1.

### 1.2 Luck formula

One player stat, `Luck` (a percentage, additive from all sources). It must not
be allowed to trivialise the tail, so weights scale by **tier distance**:

```
scaledWeight[r] = baseWeight[r] * (1 + Luck * LuckPower[r])
LuckPower = { Common=-0.5, Uncommon=-0.25, Rare=0.15, Epic=0.35,
              Legendary=0.55, Mythic=0.70, Ancient=0.80,
              Secret=0.55, Titan=0.40 }
```
Then renormalise. Negative powers on Common/Uncommon mean luck *drains* the
bottom into the middle. Secret and Titan deliberately have **lower** luck power
than Mythic/Ancient, so a maxed-luck whale improves Titan odds by far less than
they improve Mythic odds. Hard cap: `Luck <= 5.0` (i.e. +500 %).

Luck sources (all additive, max realistic F2P ≈ +180 %):

| Source | Max |
|---|---|
| `EggSense` upgrade track (15 levels) | +75 % |
| Rebirths (+5 % each, capped) | +75 % |
| Index milestones (6 × +5 %) | +30 % |
| Zone base luck bonus (Z10) | +25 % |
| Daily/quest Luck Potions | +100 % (15 min) |
| Friends in server (+3 % each, max 4) | +12 % |
| Weather (Solar Eclipse) | +150 % |
| Server Luck Boost (any player buys) | +100 % |
| Gamepass `Lucky Player` | +35 % |
| Dev product 2× Luck | +100 % |

---

## 2. Income by rarity

`BaseIncome` is Fossils per second for a Star-1, un-mutated dinosaur.

| Rarity | Base F/sec | ×prev | Sell value (Fossils) | Sell value (DNA) | Incubation |
|---|---:|---:|---:|---:|---:|
| Common | 2 | — | 60 | 1 | 30 s |
| Uncommon | 8 | 4.0× | 260 | 3 | 1 m |
| Rare | 30 | 3.8× | 1,100 | 10 | 3 m |
| Epic | 120 | 4.0× | 4,800 | 35 | 8 m |
| Legendary | 500 | 4.2× | 22,000 | 120 | 20 m |
| Mythic | 2,200 | 4.4× | 110,000 | 450 | 45 m |
| Ancient | 10,000 | 4.5× | 600,000 | 1,800 | 1 h 30 m |
| Secret | 45,000 | 4.5× | 3,000,000 | 7,500 | 3 h |
| Titan | 200,000 | 4.4× | 15,000,000 | 30,000 | 6 h |

Incubation length is the **rarity tell**. A player who sees a 45-minute timer
knows they got a Mythic before the species reveal. This is intentional and is
one of the game's best anticipation devices.

Each species carries a `SpeciesFactor` between **0.80 and 1.30** that multiplies
`BaseIncome`, so two Legendaries aren't identical and there is a "best in tier"
to chase.

---

## 3. The roster — 60 dinosaurs at launch

Columns: **SF** = SpeciesFactor · **Zones** = where its eggs can appear ·
**Size** = park footprint (1×1, 2×2, 3×3, 4×4) · **Chase** = guardian AI
archetype (see [03-stealing.md](03-stealing.md) §3).

### Common — 10 · `#E8E4D9`

| Species | SF | F/sec | Zones | Size | Chase archetype |
|---|---:|---:|---|---|---|
| Compsognathus | 0.80 | 1.6 | 1 | 1×1 | Skitterer |
| Microraptor | 0.85 | 1.7 | 1, 9 | 1×1 | Glider |
| Hypsilophodon | 0.90 | 1.8 | 1 | 1×1 | Skitterer |
| Coelophysis | 0.95 | 1.9 | 1, 2 | 1×1 | Sprinter |
| Dryosaurus | 1.00 | 2.0 | 1 | 1×1 | Grazer |
| Othnielia | 1.00 | 2.0 | 1 | 1×1 | Grazer |
| Protoceratops | 1.10 | 2.2 | 1, 2 | 1×1 | Bulldozer |
| Psittacosaurus | 1.15 | 2.3 | 1, 2 | 1×1 | Grazer |
| Gallimimus | 1.25 | 2.5 | 1, 2 | 2×2 | Sprinter |
| Struthiomimus | 1.30 | 2.6 | 1, 2 | 2×2 | Sprinter |

### Uncommon — 9 · `#5FD35F`

| Species | SF | F/sec | Zones | Size | Chase archetype |
|---|---:|---:|---|---|---|
| Oviraptor | 0.85 | 6.8 | 1, 2 | 1×1 | Skitterer |
| Ornithomimus | 0.90 | 7.2 | 2 | 2×2 | Sprinter |
| Dilophosaurus | 0.95 | 7.6 | 2, 3 | 2×2 | Spitter |
| Maiasaura | 1.00 | 8.0 | 2 | 2×2 | Grazer |
| Pachycephalosaurus | 1.05 | 8.4 | 2, 3 | 2×2 | Charger |
| Corythosaurus | 1.10 | 8.8 | 2, 3 | 2×2 | Honker |
| Iguanodon | 1.15 | 9.2 | 2, 3 | 2×2 | Bulldozer |
| Parasaurolophus | 1.20 | 9.6 | 1, 2, 3 | 2×2 | Honker |
| Deinonychus | 1.30 | 10.4 | 3 | 2×2 | Pack Hunter |

### Rare — 8 · `#3FA9F5`

| Species | SF | F/sec | Zones | Size | Chase archetype |
|---|---:|---:|---|---|---|
| Kentrosaurus | 0.85 | 25.5 | 3 | 2×2 | Spiker |
| Plesiosaurus | 0.90 | 27.0 | 3, 4 | 2×2 | Swimmer |
| Pteranodon | 0.95 | 28.5 | 3, 9 | 2×2 | Dive Bomber |
| Stegosaurus | 1.05 | 31.5 | 3 | 3×3 | Spiker |
| Suchomimus | 1.10 | 33.0 | 3, 4 | 3×3 | Wader |
| Baryonyx | 1.15 | 34.5 | 3, 4 | 3×3 | Wader |
| Ankylosaurus | 1.20 | 36.0 | 3, 4 | 3×3 | Bulldozer |
| Velociraptor | 1.30 | 39.0 | 2, 3, 4 | 2×2 | Pack Hunter |

### Epic — 7 · `#A050F0`

| Species | SF | F/sec | Zones | Size | Chase archetype |
|---|---:|---:|---|---|---|
| Dimetrodon | 0.85 | 102 | 4, 5 | 2×2 | Bulldozer |
| Quetzalcoatlus | 0.95 | 114 | 5, 9 | 4×4 | Dive Bomber |
| Carnotaurus | 1.05 | 126 | 4, 5 | 3×3 | Sprinter |
| Allosaurus | 1.10 | 132 | 4, 5 | 3×3 | Ambusher |
| Triceratops | 1.15 | 138 | 4, 5 | 3×3 | Charger |
| Therizinosaurus | 1.20 | 144 | 5, 6 | 4×4 | Slasher |
| Utahraptor | 1.30 | 156 | 4, 5, 6 | 3×3 | Pack Hunter |

### Legendary — 6 · `#FFB020`

| Species | SF | F/sec | Zones | Size | Chase archetype |
|---|---:|---:|---|---|---|
| Brachiosaurus | 0.85 | 425 | 6 | 4×4 | Stomper |
| Argentinosaurus | 0.95 | 475 | 6, 7 | 4×4 | Stomper |
| Mosasaurus | 1.05 | 525 | 6, 7 | 4×4 | Swimmer |
| Spinosaurus | 1.15 | 575 | 6, 7 | 4×4 | Wader |
| Giganotosaurus | 1.20 | 600 | 7 | 4×4 | Apex |
| Tyrannosaurus Rex | 1.30 | 650 | 6, 7 | 4×4 | Apex |

### Mythic — 6 · `#FF4B3E`

Exaggerated alphas. Visually 1.4× their base species with unique gear/scars.

| Species | SF | F/sec | Zones | Size | Chase archetype |
|---|---:|---:|---|---|---|
| Alpha Utahraptor | 0.90 | 1,980 | 7, 8 | 3×3 | Pack Hunter+ |
| Warlord Triceratops | 0.95 | 2,090 | 7, 8 | 4×4 | Charger+ |
| Storm Quetzalcoatlus | 1.05 | 4,620* | 8, 9 | 4×4 | Dive Bomber+ |
| Abyss Mosasaurus | 1.10 | 2,420 | 8 | 4×4 | Swimmer+ |
| Emberback Spinosaurus | 1.20 | 2,640 | 8 | 4×4 | Wader+ |
| Bonecrusher Giganotosaurus | 1.30 | 2,860 | 8, 10 | 4×4 | Apex+ |

\* Storm Quetzalcoatlus SF is 1.05 → 2,310 F/s; the 4,620 shown is its
Sky-Islands-placement bonus (×2 when placed on a Sky Deck park tile, a Zone 9
unlock). Documented as a deliberate placement-synergy exception.

### Ancient — 5 · `#17C6A3`

| Species | SF | F/sec | Zones | Size | Chase archetype |
|---|---:|---:|---|---|---|
| Stoneheart Ankylosaurus | 0.90 | 9,000 | 7, 8 | 4×4 | Bulldozer+ |
| Tarpit Titanosaur | 1.00 | 10,000 | 8 | 4×4 | Stomper+ |
| Primordial Therizinosaurus | 1.10 | 11,000 | 8, 9 | 4×4 | Slasher+ |
| Fossilborn Rex | 1.20 | 12,000 | 9, 10 | 4×4 | Apex+ |
| Ancient Leviathan | 1.30 | 13,000 | 10 | 4×4 | Leviathan |
| | | | | | |

### Secret — 5 · `#1A1A24`

Never listed on nest signs. The sign shows `???` and the nest visually
"glitches" for 2 seconds before a Secret is rolled — a warning frame players
will learn to recognise and scream about.

| Species | SF | F/sec | Zones | Size | Chase archetype |
|---|---:|---:|---|---|---|
| Glitch Compsognathus | 0.60 | 27,000 | any | 1×1 | Glitcher |
| Void Raptor | 1.00 | 45,000 | 6–10 | 3×3 | Blinker |
| Chrono Rex | 1.10 | 49,500 | 7–10 | 4×4 | Rewinder |
| Galaxy Mosasaurus | 1.20 | 54,000 | 8–10 | 4×4 | Swimmer+ |
| Celestial Spinosaurus | 1.30 | 58,500 | 9–10 | 4×4 | Wader+ |

**Glitch Compsognathus** is the joke Secret — a tiny Common-looking Compy with a
corrupted texture that occasionally teleports 3 studs. Low SF, but it can drop
from *any* zone including Zone 1, giving brand-new players a real (1 in ~5.3 M)
lottery ticket on their very first egg. This is the single best clip-generator in
the game and it costs almost nothing to build.

### Titan — 4 · `#FFD24A`

3× scale. Visible from anywhere on the map. Placing one darkens the sky over
your park and adds a permanent roar ambience audible to visitors.

| Species | SF | F/sec | Zones | Size | Chase archetype |
|---|---:|---:|---|---|---|
| Inferno Rex | 0.90 | 180,000 | 5, 8, 10 | 4×4 (3× visual) | Titan |
| Omega Giganotosaurus | 1.05 | 210,000 | 10 | 4×4 (3× visual) | Titan |
| Titan Rex | 1.15 | 230,000 | 10, events | 4×4 (3× visual) | Titan |
| Worldeater Argentinosaurus | 1.30 | 260,000 | 10, events | 4×4 (3× visual) | Titan |

---

## 4. Per-dinosaur data fields (frozen schema)

Every entry in `DinoConfig` must define exactly these keys — see
[11-content-config.md](11-content-config.md) for the literal Lua table shape.

```
Id              string   stable, never changes, e.g. "trex"
DisplayName     string   "Tyrannosaurus Rex"
Rarity          string   RarityConfig id
SpeciesFactor   number   0.80 – 1.30
Zones           {string} zone ids whose nests can roll this
Size            string   "1x1" | "2x2" | "3x3" | "4x4"
VisualScale     number   1 for most, 3 for Titans
ChaseArchetype  string   AI archetype id
ModelName       string   asset name in ReplicatedStorage/SAD_Assets/Dinos
EggModelName    string   asset name in .../Eggs
IdleAnim/WalkAnim/RunAnim/RoarAnim/EatAnim/SleepAnim   string (anim ids)
Sfx             {Roar, Step, Hatch}
CarryPenalty    number   0.00 – 0.45 movement multiplier loss when carrying
MutationsAllowed  {string}|"all"
IndexOrder      number   sort order in the collection book
```
