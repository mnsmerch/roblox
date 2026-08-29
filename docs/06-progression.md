# 06 — Progression Systems

Numbers live in [05-economy.md](05-economy.md). This doc covers the *systems*.

## 1. Inventory

Four tabs, one screen, thumb-reachable.

| Tab | Contents | Actions |
|---|---|---|
| **Eggs** | Carried + stored eggs, each showing rarity aura, source zone, and incubation time remaining | Incubate, Instant Hatch, Drop |
| **Dinosaurs** | Every owned dinosaur, filterable by rarity / mutation / zone / placed | Place, Store, Sell, Favorite, Lock, Vault, Fuse, Inspect |
| **Boosts** | Potions, serums, shields, instant-hatch tokens | Use |
| **Items** | Event tokens, keys, cosmetics | Use / Equip |

**Locking.** A locked dinosaur cannot be sold, fused, rerolled or traded. Any
dinosaur that is Legendary+ is **auto-locked on hatch**; unlocking requires a
double confirm with the sell value shown in full. This single rule prevents the
most common "I misclicked and sold my Titan" support ticket.

**Favorite** is separate from Lock — it's a sort pin only.

**Storage.** 25 unplaced dinosaurs base → 200 via the Dino Storage track. At
90 % full the HUD shows a persistent warning and the Sell screen offers a
"Sell all Commons below Star 2" bulk action (with a confirm and a preview of
exactly what will be sold). **Nothing is ever auto-deleted.** If storage is
full, new hatches queue in the incubator and the incubator refuses new eggs —
a visible, fixable blockage instead of silent loss.

---

## 2. Selling → DNA (recommended over any alternative)

Selling gives **both** Fossils and DNA (values in
[05-economy.md](05-economy.md) §2). This is the right answer versus
Fossils-only or DNA-only because:

- Fossils make Commons immediately useful to a new player (a real coin drip).
- DNA gives the same Commons *long-term* value, so a rebirth-15 player still
  bothers to steal from Zone 1 during a Nest Frenzy.
- One action, two currencies, zero extra UI. Kids get it instantly.

**Sell multipliers:** ×(1 + 0.35 × (stars−1)) and ×(mutation multiplier ^ 0.5)
— mutations raise sell value on a square root so selling a Void dinosaur is
lucrative but never better than keeping it.

---

## 3. Fusion & Stars — the leveling replacement

**I recommend against dinosaur XP levels.** XP means every dinosaur has a hidden
second progress bar, players hoard for the wrong reasons, and "why is my T-Rex
worse than his T-Rex" becomes a constant question. Fusion does the same job with
a rule a child can repeat: **five of the same makes one better one.**

### The Fossil Lab

| Action | Input | Output | Cost |
|---|---|---|---|
| **Fuse** | 5 × same species, same rarity, same star level | 1 × same species at **Star +1** | DNA: 20 × 4^(star−1) |
| **Reroll Mutation** | 1 dinosaur | same dinosaur, new mutation roll | DNA: `RerollBase[rarity] × 1.8^rerolls` |
| **Splice** (V1.2) | 10 × any Common | 1 random Uncommon egg | 50 DNA |
| **Luck Nodes** | — | permanent +0.5 % Luck, 20 nodes max | DNA: 500 × 1.6^n |

**Stars 1–5**, each `+35 %` income (Star 5 = ×2.4). Fusing preserves the
*highest* mutation among the five inputs (clearly shown before confirming), so
fusing is never a downgrade — that's important, because a system where players
can accidentally destroy value is a system they stop touching.

Total to reach Star 5 from Star 1: 5⁴ = **625** copies. That's intentionally
enormous for high rarities and completely achievable for Commons — a Star 5
Golden Gallimimus becomes a genuine flex object.

---

## 4. Dinosaur Index

A book UI, one page per zone, 60 species total.

Each entry shows: silhouette (undiscovered) or full art, name, rarity, zone,
best mutation you've owned, star record, times hatched, and its rarity odds.

**Tracked per species:**
- `discovered` (ever hatched)
- `mutationsSeen` (set of mutation ids)
- `bestStar`
- `count`

Completion % = discovered species ÷ 60, shown on the HUD. Mutation completion is
a separate, optional 100 %-plus track (60 species × 18 mutations = 1,080 entries)
purely for the obsessives — with no gating attached, so it never feels
mandatory.

Rewards in [05-economy.md](05-economy.md) §7.

---

## 5. Upgrade UI grouping

Three boards in the hub so the list is never one intimidating column:

- **Bone Market — Park:** Dino Slots, Park Size, Incubators, Incubator Speed,
  Incubator Genetics, Feeding Trough, Bank Size, Dino Storage
- **Bone Market — Explorer:** Runner's Legs, Strong Back, Egg Pouch, Egg Sense,
  Nest Radar
- **Park Gate — Defence:** Fence, Guard Tower, Camera, Alarm Horn, Electric Fence

Each row shows current level, effect now → effect after, cost, and a
**"Buy Max"** button (server validates the whole batch in one transaction).

---

## 6. Trading — my recommendation: **ship it in V1.5, not V1**

Trading is the single biggest source of scams, bots, and moderation load in
Roblox economy games, and it is *not* required for the core loop to work. It
also directly undermines the stealing fantasy in the first weeks, when scarcity
is what makes theft exciting.

**Ship V1 without trading.** Add it in V1.5 once values have stabilised, with:

| Protection | Rule |
|---|---|
| Eligibility | 3 h in-game playtime **and** rebirth ≥ 2 **and** Roblox account ≥ 30 days |
| Value display | Every dinosaur shows a server-computed **Fossil Value** (income × 600, mutation-adjusted). No player-set prices |
| Fairness warning | If one side's total value is < 40 % of the other, a red full-width warning appears and the confirm button is delayed 5 s |
| Double confirm | Both sides confirm; **any change to the offer resets both confirms** |
| Anti-swap | The final confirm screen is a static server-rendered snapshot; the offer is locked server-side for the 5 s window |
| Locked items | Cannot be traded. Vaulted cannot be traded |
| Cooldown | 60 s between completed trades; 20 trades/day cap |
| History | Last 50 trades viewable in-game with timestamps and item names |
| Disconnect | Trade voids atomically; nothing moves unless both profiles commit |
| No Robux-for-item | Explicitly disallowed and reported via chat filter heuristics |

Until V1.5, the **gifting-free** economy is a feature, not a gap: everything you
own, you stole.

---

## 7. New Player Protection (exact rule)

A player is protected until **all** of:
- 60 minutes of accumulated in-game playtime, **and**
- they have hatched at least one **Rare** or better, **and**
- they have completed the tutorial.

Whichever finishes last ends protection. On top of that:
- Every join grants a **15-minute session shield**.
- Protection status is shown as a shield icon with a countdown on the HUD.
- When protection ends, a friendly popup explains raiding *and* points at the
  Vault Pedestal: "Put your favourite dino in the Vault — nobody can ever take
  it." Turning the scary moment into a tutorial moment.

---

## 8. Settings

Persisted in the profile (`Settings` table). All default to on except where
noted.

| Setting | Type | Notes |
|---|---|---|
| Music volume | 0–100 | default 60 |
| SFX volume | 0–100 | default 80 |
| Rare-hatch announcements | on/off | server takeovers still show |
| Steal notifications | on/off | your *own* park alerts cannot be disabled |
| Trade requests | on/off | V1.5+ |
| Camera shake | on/off | accessibility |
| Particles | High / Medium / Off | |
| Low graphics mode | on/off | also culls distant dinosaur models |
| Show other players' name tags | on/off | |
| Damage/knockback screen effects | on/off | accessibility |
| UI scale | 80–130 % | accessibility |
| Auto-collect income | on/off | if unlocked |

**Low Graphics Mode** is auto-suggested on first join if the device reports a
low `WorkspaceQualityLevel` or is mobile with < 3 GB RAM (approximated via
`UserInputService.TouchEnabled` + measured frame time over the first 20 s).
