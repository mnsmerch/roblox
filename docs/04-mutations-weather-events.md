# 04 — Mutations, Weather, and Server Events

## 1. Mutation system

**When it rolls:** at **hatch**, not at pickup. This is deliberate — it means
weather at the moment of hatching matters, so players deliberately *hoard eggs
until a Blood Moon*. That's a free retention mechanic that costs nothing to
build and creates server-wide coordinated excitement ("DON'T HATCH YET").

**Weights out of 100,000,000** (`MUTATION_WEIGHT_TOTAL`):

| Mutation | Weight | Odds | Income × | Visual |
|---|---:|---:|---:|---|
| *(none)* | 78,000,000 | 78 % | 1.0 | — |
| Golden | 12,000,000 | 1 in 8.3 | **2×** | Metallic gold skin, coin sparkles |
| Crystal | 4,000,000 | 1 in 25 | **3×** | Translucent quartz shell, refracts light |
| Frozen | 2,000,000 | 1 in 50 | **3.5×** | Ice coating, breath fog, snow trail |
| Electric | 1,500,000 | 1 in 67 | **4×** | Arcing bolts, blue glow, static crackle |
| Toxic | 1,000,000 | 1 in 100 | **4.5×** | Sickly green, dripping ooze, bubbling puddles |
| Volcanic | 700,000 | 1 in 143 | **5×** | Cracked magma skin, ember trail, heat haze |
| Diamond | 400,000 | 1 in 250 | **6×** | Faceted white gem, prismatic flash |
| Radioactive | 200,000 | 1 in 500 | **8×** | Neon green pulse, geiger tick SFX |
| Ghost | 100,000 | 1 in 1,000 | **10×** | 40 % transparent, floats 2 studs, no footsteps |
| Shadow | 50,000 | 1 in 2,000 | **12×** | Pure black silhouette, purple eyes, smoke |
| Rainbow | 30,000 | 1 in 3,333 | **15×** | Animated hue-cycling, rainbow trail |
| Solar | 10,000 | 1 in 10,000 | **20×** | Blinding gold corona, lights up the park |
| Lunar | 6,000 | 1 in 16,667 | **22×** | Silver-blue, moon-phase mark, night bloom |
| Blood Moon | 2,500 | 1 in 40,000 | **28×** | Crimson, dripping aura, red fog |
| Galaxy | 1,000 | 1 in 100,000 | **35×** | Starfield skin, orbiting planets |
| Celestial | 350 | 1 in 285,714 | **60×** | White-gold wings of light, choir SFX |
| Ancient | 100 | 1 in 1,000,000 | **80×** | Living stone + gold inlay, rune circle |
| Void | 50 | 1 in 2,000,000 | **150×** | Black hole distortion, eats nearby light |
| **Total** | **100,000,000** | | | |

### 1.1 Mutation stacking — my recommendation

Uncapped stacking breaks the economy (a Void Ancient Celestial would be
150×80×60 = 720,000×) and confuses younger players. **Cap at two.**

**"Prime" rule:** after a non-`none` mutation is rolled, there is a flat
**1 in 2,000** chance to roll a second, different mutation from the same table
(excluding `none` and the first). A Prime dinosaur:

- displays as `Void Golden Tyrannosaurus Rex` (rarer mutation first),
- multiplies both (`150 × 2 = 300×`),
- gets a **✦ Prime** badge and a distinct hatch jingle,
- always triggers a cross-server announcement regardless of tier.

Realistic ceiling: a Prime Void + Celestial is 150 × 60 = 9,000×, at roughly
1 in 1.7 billion hatches. That is a "once per game lifetime, worldwide" event —
exactly the right kind of legend, and the maths stays bounded.

### 1.2 Mutation luck

A separate stat, `MutLuck`, that only redistributes *within* the mutation table:

```
scaledWeight[m] = baseWeight[m] * (1 + MutLuck * MutPower[m])
MutPower: none = -0.6, tier1-3 (Golden/Crystal/Frozen) = 0.0,
          tier4-8 = 0.45, tier9-14 = 0.75, tier15-18 (Galaxy+) = 0.50
```
Cap `MutLuck <= 4.0`. Sources: `Incubator Genetics` upgrade (+80 % max), rebirth
(+3 %/rebirth), gamepass `Mutation Master` (+50 %), dev product 2× Mutation
(+100 %), weather (see below), Zone 8 radiation field (+60 % while the egg was
*picked up* there), Amber Serum consumable (+150 %, 10 min).

### 1.3 Rerolling

At the Fossil Lab, spend DNA to reroll a placed dinosaur's mutation. Cost =
`RerollBase[rarity] × (1.8 ^ rerollsOnThisDino)`, so rerolling the same Titan
forever is impossible. The result can be *worse* — clearly warned, double
confirm. This is the main DNA sink and it makes duplicate Commons valuable.

---

## 2. Weather system

One weather is always active. Rolls every **8 minutes**; `Clear` is weighted so
that roughly 45 % of the time nothing special is happening (special needs to
feel special). Duration 4–7 minutes for exotic weather, then a forced ≥ 3 min
`Clear` gap.

| Weather | Weight | Duration | Effect |
|---|---:|---:|---|
| **Clear** | 4,500 | — | Baseline |
| **Rainstorm** | 1,400 | 6 m | −10 % ground speed; nests respawn 25 % faster |
| **Thunderstorm** | 900 | 5 m | **Electric ×25 weight.** Random lightning knocks eggs loose |
| **Heatwave** | 700 | 6 m | +20 % Fossil income; guardians −8 % speed (sluggish) |
| **Blizzard** | 650 | 5 m | **Frozen ×25.** Fog cuts render distance; Frozen Valley ×2 |
| **Meteor Shower** | 550 | 5 m | **+40 % rare-egg weight server-wide** (luck +0.9). Meteorites drop bonus eggs |
| **Volcanic Ash** | 500 | 6 m | **Volcanic ×25.** Ash slows everyone incl. guardians |
| **Radiation Storm** | 350 | 5 m | **Radioactive ×30, Toxic ×15.** Wasteland nests upgrade one rarity tier |
| **Aurora** | 250 | 7 m | **Celestial ×20, Lunar ×12.** Beautiful; everyone stops to look |
| **Blood Moon** | 130 | 6 m | **Blood Moon ×40, Shadow ×20.** Sky red, all guardians +10 % speed, steal rewards ×1.5 |
| **Solar Eclipse** | 70 | 4 m | **Secret rarity weight ×8, Solar ×30.** The single rarest weather. Full server announcement, everyone sprints to nests |

Weather is **server-wide and identical for everyone** — that's what makes it
social. Announced with a 20-second countdown banner and a distinct sting.

**Interaction rule:** weather multiplies mutation *weights* before luck is
applied, then everything renormalises. Weather cannot exceed a `×40` cap on any
single mutation, and Prime chance is never modified by weather.

---

## 3. Server events

Events fire every **12–18 minutes** (randomised), never overlapping, with a
**60-second countdown** and a map marker. Weighted selection with a
no-repeat-within-3 rule.

| # | Event | Weight | Length | What happens | Rewards |
|---|---|---:|---:|---|---|
| 1 | **Meteor Impact** | 160 | 3 m | A meteor lands at a random zone with a 15 s telegraphed shadow. Crater spawns 8 mutated eggs (guaranteed mutation, Radioactive weight ×20) | Eggs, first-to-arrive bonus |
| 2 | **Dinosaur Stampede** | 160 | 2 m | A herd of 40 dinosaurs charges hub→zone along a marked lane. Tag one mid-run to capture it | Free dinosaur (Rare–Legendary), knockback comedy |
| 3 | **Nest Frenzy** | 150 | 3 m | Every nest server-wide respawns in 3 s and guardians are 20 % slower | Pure volume — best farming window |
| 4 | **Great Migration** | 120 | 4 m | One random zone's nests are upgraded **one full rarity tier** | Best odds window in the game |
| 5 | **Titan Egg Event** | 90 | 5 m | A colossal egg descends into the Event Arena. Players hold it to charge a bar; being tagged by others resets *your* contribution | Guaranteed Ancient+, small chance of Titan |
| 6 | **Volcano Eruption** | 90 | 4 m | Zone 5 erupts; lava bombs land map-wide; Volcanic eggs spawn everywhere | Volcanic-mutation eggs |
| 7 | **Boss Dinosaur (Alpha Hunt)** | 80 | 5 m | A 4× scale Apex spawns in the Arena with a shared "Exhaustion" bar. Players sprint-tag it to drain the bar. It cannot hurt you — only knock you flying | Rewards by contribution tier; top contributor gets an Ancient egg |
| 8 | **Amber Rain** | 80 | 2 m | Amber chunks rain over the hub; collect for Fossils + DNA | Fossils, DNA — the catch-up mechanic |
| 9 | **Time Portal** | 60 | 4 m | A portal opens in the hub into a pocket Prehistoric Arena with 20 dense nests and no zone gating — *any* player can enter | Access to high-tier eggs regardless of progression |
| 10 | **Sky Fall** | 55 | 3 m | Flying dinosaurs circle the map dropping eggs on parachutes | Eggs, chaotic scramble |
| 11 | **Fossil Auction** | 40 | 3 m | A mystery egg (rarity hidden, guaranteed Epic+) is auctioned. Players bid Fossils; only the winner pays | Big Fossil sink — economy control valve |
| 12 | **Blackout Raid** | 30 | 3 m | **Opt-in only.** Participants' shields drop and all steal rewards are ×3 and hold times halved. Non-participants are untouched and invisible to raiders | High-risk PvP for players who want it |

**Blackout Raid must be opt-in.** A forced server-wide shield drop is the
fastest way to make a 9-year-old quit. Opt-in turns the same mechanic into a
consensual arena, and the players who opt in are exactly the ones who make
clips.

### 3.1 Event feel rules

- Every event ends with a **contribution scoreboard** (top 5 by name).
- Nobody who participates receives *nothing*. Minimum participation reward is
  always ≥ 3 minutes of that player's income.
- Events never require a zone unlock to participate in — they are the main
  catch-up mechanism for new players and the main reason to stay logged in.
- Countdown notification at 60 s, 30 s, 10 s with escalating audio.

---

## 4. Announcement rules (frozen)

| Trigger | Scope | Format |
|---|---|---|
| Legendary hatch | server toast | `🦴 DAVID hatched a LEGENDARY Spinosaurus!` |
| Mythic hatch | server banner + SFX | `🔥 MYTHIC! DAVID hatched Emberback Spinosaurus!` |
| Ancient hatch | banner + camera cut to their park | `🗿 ANCIENT! ...` |
| Secret hatch | full-screen takeover + **cross-server** | `NO WAY! DAVID HATCHED A VOID RAPTOR! — 1 IN 5,263,157` |
| Titan hatch | takeover + cross-server + badge | `⚡ A TITAN HAS HATCHED ⚡` |
| Mutation ≥ Galaxy | banner + cross-server | `🌌 GALAXY MUTATION! DAVID's Triceratops — 1 IN 100,000` |
| Prime mutation | banner + cross-server | `✦ PRIME ✦ DAVID hatched a VOID GOLDEN T-REX!` |
| Legendary+ egg grabbed | server toast | `DAVID JUST GRABBED A MYTHIC EGG — CATCH HIM!` |
| Mythic+ dinosaur stolen from a player | server banner | `DAVID STOLE SARAH's MYTHIC ALPHA UTAHRAPTOR!` |
| Server boost purchased | banner + thank-you prompt | `DAVID ACTIVATED 2× SERVER LUCK FOR 10 MINUTES! 🎉` |
| Weather: Blood Moon / Eclipse / Aurora | banner | `🌑 BLOOD MOON — SHADOW MUTATIONS ×20` |
| Event countdown | banner | `☄️ METEOR IMPACT IN 60 SECONDS!` |

**Always show the odds** on rare announcements. "1 IN 5,263,157" is the number
people screenshot. Cross-server delivery uses `MessagingService` with a
per-server rate budget and a client-side queue that never shows more than one
takeover at a time.
