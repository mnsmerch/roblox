# 15 — Visual Style, Audio, Animation & Viral Design

## 1. Visual style

**"Chunky Cartoon Paleo."** Bold, saturated, slightly toy-like. Reads clearly at
a 200×200 thumbnail size and at 30 fps on a cheap phone.

| Rule | Detail |
|---|---|
| Silhouette first | Every dinosaur must be identifiable as a black shape. If two species share a silhouette, one gets a horn, crest or tail change |
| Proportions | Heads ~1.3× realistic scale, eyes large and forward, limbs shortened. Cute-menacing, never scary |
| Colours | 3-colour palette per species: body, accent, belly. High saturation, mid value. No muddy browns |
| Materials | `SmoothPlastic` and `Neon` only. No `Metal`, no realistic textures. Consistency beats fidelity |
| Outlines | A thin dark rim via a slightly scaled inverted-normal shell on hero dinosaurs only (Legendary+), for the "sticker" look |
| Environment | Zones are colour-coded and readable from 800 studs. Each zone commits to one dominant hue |
| Lighting | `Future` lighting, warm key. Each zone overrides Ambient/Fog. Blood Moon and Eclipse are dramatic full-scene shifts |
| VFX budget | Rarity effects downgrade past 120 studs; Low Graphics disables all but rarity colour |

**Rare dinosaurs must be visually louder, not just numerically better.**
Legendary gets a light beam; Mythic gets embers and a heat shimmer; Ancient gets
floating rune stones; Secret gets a reality tear that visually *bends* the
skybox behind it; Titan is 3× scale with a ground-shake and a darkened sky over
the owner's park. A Titan in a park should be recognisable from the spawn plaza.

## 2. Animation requirements

**Per dinosaur (6 core clips):** Idle, Walk, Run, Roar, Eat, Sleep.
Rigged as R15-style but simplified — most dinosaurs need only 8–12 motors.

**Shared archetype clips (reused across species):**
Charge wind-up · Charge · Tail sweep · Dive swoop · Burrow/emerge ·
Spit · Honk · Stomp · Pack flank-call · Titan roar (camera-shaking)

**Player clips:**
Carry Egg (idle/walk/run — egg held overhead, arms up, comedic waddle) ·
Carry Dinosaur (bigger, staggering, worse the heavier it is) ·
Trip / ragdoll · Winded stagger · Steal hold (straining) ·
Place dinosaur · Collect income (fist pump)

**Sequences:**
Egg wobble → crack → burst (3 tiers of intensity by rarity) ·
Mutation transformation (2 s, colour wash + particle bloom) ·
Titan hatch (7 s cinematic with a camera cut) ·
Rebirth (park fades, amber sweeps, park rebuilds) ·
Guardian de-aggro (stops, huffs, shakes head, trots home)

**Priority order for a small team:** Idle/Walk/Run for all species → Carry Egg →
Trip → Roar → Egg crack → everything else. The first four carry 90 % of the
game's readability.

## 3. Sound design

| Sound | Character |
|---|---|
| Egg pickup | A short *shluck* + a rising 3-note chime pitched by rarity |
| Rarity sting | 9 distinct stings, each longer and more layered than the last. Titan's is 4 seconds with a choir |
| Guardian aggro roar | Species-specific, low-passed at distance, with camera shake inside 80 studs |
| Chase music | Layered: a base loop, plus a percussion layer that fades in as the guardian closes. **Distance is audible** — this is the most important audio decision in the game |
| Caught | A comedic *bonk* + slide whistle. Never a failure sound |
| Safe | A bright bell + crowd cheer sample |
| Incubation tick | A soft heartbeat that speeds up in the final 10 s |
| Egg crack | 3 escalating cracks then a burst |
| Hatch | Rarity sting + species roar |
| Mutation | A shimmering reverse-cymbal into a distinct per-mutation motif |
| Income collect | Coin cascade, pitch rising with amount, capped so big collections don't shriek |
| Upgrade | A satisfying mechanical *ka-chunk* |
| Rebirth | A long amber swell |
| Rare egg spawned | A distant, spatialised chime from the direction of the nest |
| Titan announcement | Sub-bass hit + horn, ducks all other audio for 1.5 s |
| Raid alert (yours) | An urgent klaxon, distinct from every other sound in the game |
| Weather transitions | A 3-second ambience crossfade per weather |

**Anti-annoyance rules:** every repeating SFX has a per-player cooldown; income
collect is capped at 8 chimes per collection regardless of amount; server
announcements duck to −12 dB if three fire within 10 seconds; every sound
category respects the settings sliders; ambience never loops with an audible
seam.

## 4. Designed viral moments

Each of these is a *mechanic*, not a hope.

| Moment | The mechanic that guarantees it |
|---|---|
| **"RUN!!!"** | Chase music that audibly tracks guardian distance + a red vignette that pulses faster as it closes. The clip is dramatic without the player doing anything |
| **"NO WAY!"** | Secret/Titan hatches take over every screen on the server with the odds printed in 90 px type. The number is the screenshot |
| **The gold egg chase** | Epic+ eggs emit a visible beam and broadcast the carrier's name. Three players converging on one thief happens *by design*, several times an hour |
| **The loose egg scramble** | A caught thief drops the egg and it stays grabbable for 10 seconds. Free chaos, zero extra systems |
| **"He stole my T-Rex!"** | A carried dinosaur is visible from anywhere with a name-tag caption. The owner's chase is a clip from both sides |
| **The Titan reveal** | 3× scale, sky darkening, ground shake. Whoever owns one is a landmark |
| **Meteor moment** | A 15-second telegraphed shadow before impact — long enough for everyone to sprint toward it and film the landing |
| **The stampede** | 40 dinosaurs down a marked lane through the hub. Everyone gets knocked over. Pure slapstick |
| **The Glitch Compy** | A Secret that can drop from Zone 1. Guarantees that "brand new player hits 1-in-5-million" clips exist and spread |
| **Prime hatch** | Two mutations at once, ✦ badge, cross-server takeover. The rarest brag in the game |
| **The near-miss** | Guardian rubber-banding keeps it visibly on-screen. Escapes *look* close because they are engineered to be |
| **"Thanks!"** | Server boost purchases get a screen full of floating hearts naming the buyer. Generosity is visible |

**Thumbnail brief.** A single frame containing: a huge T-Rex mid-roar, a player
sprinting toward camera clutching a glowing gold egg, a second player reaching
for a dinosaur on a pedestal in a colourful park behind them. No text needed —
the concept must be legible in one second at phone size. That thumbnail is a
design constraint on the art direction, not an afterthought.
