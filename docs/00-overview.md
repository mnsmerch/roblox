# 00 — Overview, Pillars, Core Loop, FTUE

## 1. Identity — what makes this *not* a reskin

Steal a Brainrot is "buy a thing on a conveyor, put it on a stand, someone
steals it." Grow a Garden is "plant, wait, harvest." Both are **passive**
acquisition games — the acquisition step is a purchase or a timer.

Steal a Dinosaur's acquisition step is an **active skill moment**: you have to
physically outrun a dinosaur while carrying its egg. That single change cascades
into a different game:

| Design element | Competitors | Steal a Dinosaur |
|---|---|---|
| How you get a unit | Buy / plant | **Survive a chase** |
| Rarity reveal | Instant on purchase | **Rolled at pickup, revealed over incubation time** — the slower it hatches, the better it is |
| Risk | Only PvP | **PvE chase + PvP raid** — two independent tension sources |
| The unit itself | Static prop | A living AI creature that walks your park |
| Public status | Item on a stand | A **park skyline** — a Titan is visible from across the map |
| Protection | Timer shield | Timer shield **+ Vault Slots** (owner-chosen unstealable pedestals) |

**Three pillars.** Every feature must serve at least one:

1. **RUN.** The chase is the game's signature verb. Loud, funny, 15–25 seconds.
2. **REVEAL.** Rarity, species and mutation are three separate reveals spread
   over time so the dopamine hits three times per egg, not once.
3. **RIVALRY.** Everything valuable is visible, and almost everything visible is
   stealable. Your park is a scoreboard other people can attack.

**Tone.** Loud, colorful, slapstick. Dinosaurs are cartoon-chunky with big eyes
and stubby arms. Getting caught is a comedy beat (you trip, egg bounces away,
dinosaur does a victory stomp) — never a punishment screen. Nothing in this game
is scary; a 7-year-old should laugh when the T-Rex catches them.

---

## 2. Core gameplay loop

```
        ┌──────────────────────────────────────────────────────────┐
        │                                                          │
        ▼                                                          │
  COLLECT Fossils  ──►  SPEND on upgrades / zones                  │
  from your park             │                                     │
        ▲                    ▼                                     │
        │              TRAVEL to a zone                            │
        │                    │                                     │
        │                    ▼                                     │
        │            FIND a nest ──► read Risk & Rarity Potential   │
        │                    │                                     │
        │                    ▼                                     │
        │            STEAL the egg  ──► [RARITY REVEAL #1]          │
        │                    │                                     │
        │                    ▼                                     │
        │            ██ THE CHASE ██  (guardian AI, 15–25s)         │
        │                    │           other players see your     │
        │                    │           egg aura and may hunt you  │
        │                    ▼                                     │
        │            REACH your Park Gate (safe zone)               │
        │                    │                                     │
        │                    ▼                                     │
        │            INCUBATE ──► timer length telegraphs rarity    │
        │                    │                                     │
        │                    ▼                                     │
        │            HATCH ──► [REVEAL #2 species] [#3 mutation]    │
        │                    │      ↳ server announcement if rare   │
        │                    ▼                                     │
        │            PLACE in park ──► generates Fossils/sec        │
        │                    │                                     │
        └────────────────────┘                                     │
                             │                                     │
                             ▼                                     │
        RAID another park ───────► steal a placed dinosaur ─────────┘
        DEFEND your park
        JOIN server events / weather windows
        COMPLETE the Index ──► REBIRTH ──► harder zones
```

**Loop timings (the rhythm the game should feel like):**

- Micro-loop (**~45 s**): travel → steal → chase → deposit.
- Small loop (**~4 min**): a full egg from nest to placed dinosaur.
- Medium loop (**~20 min**): enough Fossils for a meaningful upgrade or zone.
- Macro loop (**~3–6 h**): a rebirth.
- Meta loop (**weeks**): Index completion, Secret/Titan hunting, leaderboard.

---

## 3. First-time player experience (target: 2m 30s to "I get it")

The FTUE is a **guided version of the real loop** — no separate tutorial sandbox.
The guide is **Professor Rok**, a small cartoon Compsognathus with a hard hat who
hops beside you and speaks in ≤ 8-word speech bubbles. He is skippable at any
time and disappears permanently after step 10.

| # | Beat | Time | On-screen text | What it teaches |
|---|---|---|---|---|
| 1 | Spawn directly *inside your own empty park*, gate open, big glowing arrow | 0:00 | "This is YOUR park!" | Ownership |
| 2 | Arrow points out the gate to Jurassic Plains (25 studs away) | 0:10 | "Follow me!" | The world is close |
| 3 | Walk to a highlighted **Starter Nest** with one green egg | 0:25 | "See that egg? TAKE IT." | The verb |
| 4 | Hold E / tap the button to grab | 0:35 | Rarity flash: **COMMON** | Reveal #1 |
| 5 | A cartoon Parasaurolophus honks and chases (deliberately slow, cannot catch you on the first steal) | 0:38 | **"RUN!!!"** full-screen | The pillar |
| 6 | Sprint back through your gate; a shield dome flashes | 0:55 | "SAFE!" | Safe zone rule |
| 7 | Walk onto the Incubator pad, egg auto-deposits | 1:05 | "Eggs hatch in here." | Incubation |
| 8 | Tutorial egg hatches in a forced **10 seconds** with full crack VFX | 1:20 | Reveal: species + "No mutation" | Reveals #2/#3 |
| 9 | Drag the dinosaur onto a glowing empty enclosure pad | 1:40 | "Put him in the park!" | Placement |
| 10 | Fossils tick up visibly; tap the pile to collect | 1:55 | "+120 Fossils!" | Income |
| 11 | Upgrade board pre-highlighted, first upgrade costs exactly what you now have | 2:15 | "Buy this!" | The sink |
| 12 | Rok waves goodbye, zone signposts light up, freedom | 2:30 | "Go get a BIG one!" | Release |

**FTUE rules:**
- The first chase is unlosable. The guardian's speed is capped below the
  player's. The player must *feel* the chase, not fail it.
- No menu is opened for the player during the FTUE except the upgrade board.
- Total forced reading: under 60 words.
- If a player skips, they still receive the tutorial egg in their inventory.
- Completion is tracked (`TutorialCompleted`); target **> 80 %**.

---

## 4. Session design — what a player accomplishes in X minutes

| Session | Player should have… |
|---|---|
| **5 min** | 2–4 eggs stolen, 1–2 dinosaurs placed, 1 upgrade bought, seen one server announcement |
| **20 min** | Zone 2 unlocked, ~6 dinosaurs placed, 3 upgrades, first Rare, one quest done |
| **60 min** | Zone 3–4, first Epic or Legendary, first mutation, witnessed a weather event and a server event, first raid attempt on/by another player |
| **Day 1** | Zone 3–4, 12+ dinosaurs, daily reward day 1, ~35 % of the Common/Uncommon index, first robbery survived or suffered |
| **Day 3** | First **Rebirth**, Zone 5, first Mythic chase attempt |
| **Week 1** | Rebirth 3–5, Zone 6–7, several mutations, index ~50 %, on a friends leaderboard |
| **Month 1** | Rebirth 12+, Zone 9–10, hunting Secrets, index 85 %+, appears on a server statue |

---

## 5. Retention design

| Day | Hook |
|---|---|
| **D1** | The FTUE's three reveals + first server announcement someone else triggers ("I want that") |
| **D2** | Daily reward D2 + a *carried-over incubating egg* that finishes offline (a reason to reopen), + first daily quest set |
| **D3** | Rebirth becomes reachable; Zone 4 visible-but-locked |
| **D7** | Day-7 daily reward = a guaranteed **Epic Amber Egg**; weekly quest payout; first Index milestone reward |
| **D14** | Zone 7 (rebirth-gated), Fusion/Star system becomes relevant as duplicates pile up |
| **D30** | Titan Territory, seasonal limited dinosaur rotation, leaderboard statues |

**Anti-timer principle.** At most **one** of a player's active goals may be a
pure wall-clock wait. Incubation is that one. Everything else (upgrades, zones,
index, rebirth) must be advanced by *playing*, never by waiting. If a player has
nothing to do but wait, the design has failed.

---

## 6. Design guardrails (non-negotiable)

1. **No dead ends.** There is always a purchasable upgrade priced at ≤ 3 minutes
   of the player's current income.
2. **Never lose a rare permanently to PvE.** A guardian catching you costs you
   the egg *back to its nest* — you can re-steal it. It never deletes it.
3. **PvP losses are capped.** Vault Slots exist so a player's single most
   precious dinosaur is never stealable.
4. **No pay-to-win wall.** Every gamepass effect exists in a free form at lower
   magnitude. See [07-monetization.md](07-monetization.md).
5. **Mobile-first UI.** If it doesn't work one-thumbed on a phone, it doesn't
   ship.
6. **Server-authoritative everything.** See
   [09-tech-architecture.md](09-tech-architecture.md) §7.
