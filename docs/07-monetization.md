# 07 — Monetization

## 1. Ethics rules (these constrain every item below)

1. **No gamepass gates progression.** Every paid effect exists free at lower
   magnitude, or is convenience only.
2. **No paid invulnerability.** Shields are capped at 2 hours stacked
   regardless of spend. You can never buy your way out of the game's PvP.
3. **No loot boxes with hidden odds.** Every purchasable egg states its exact
   rarity table on the buy screen, before payment.
4. **No paid-only rarity.** There is no dinosaur obtainable *only* with Robux.
   Event eggs use the same table as the event's free eggs.
5. **No FOMO countdown pressure on children.** Limited items rotate on a
   published schedule; nothing uses a fake "3 LEFT!" scarcity display.
6. **Every server-wide purchase benefits everyone**, and credits the buyer by
   name. Spending should make you popular, not powerful.
7. **First-purchase clarity.** The first time a player opens the shop, a plain
   panel says: "You never need to spend Robux to get any dinosaur in this game."

## 2. Gamepasses

| Gamepass | Robux | Effect |
|---|---:|---|
| **VIP** | 499 | 100 % offline rate (vs 60 %), +1 incubator, +2 dino slots, auto-collect from level 1, chat tag, VIP park arch, 25,000 Fossils/day |
| **Double Income** | 799 | ×2 park income |
| **Lucky Player** | 649 | +35 % Luck |
| **Mutation Master** | 799 | +50 % MutLuck |
| **+6 Dino Slots** | 399 | +6 placement slots |
| **+2 Incubators** | 349 | +2 incubators |
| **Fast Hatch** | 299 | −25 % incubation time |
| **Egg Pouch +2** | 249 | Carry 2 extra eggs |
| **Vault Slots +2** | 349 | 2 extra unstealable pedestals |
| **Sprint Boots** | 299 | +20 % move speed |
| **Park Theme: Amber Kingdom** | 199 | Cosmetic retexture, available at any park value |
| **Titan Nametag** | 249 | Cosmetic animated nametag |

Total catalogue ≈ 4,700 Robux. Deliberately no bundle above 799 — large single
prices are how children's games get bad press.

**Stacking cap:** the combined multiplicative effect of all owned gamepasses on
income is capped at **×2.6** so a full-catalogue buyer is roughly a 2.6× faster
player, not a 20× one.

**What the cap governs, measured (Step 21).** The cap applies to the *direct*
income multiplier channel. V1 ships six of the twelve passes above and exactly
one of them — Double Income — touches that channel, so V1's whole catalogue
multiplies to ×2.0 and the cap is correct but currently unreached. It binds the
day a second income pass ships.

A buyer's real throughput advantage is income × *slots*, and the slot channel is
additive and uncapped. Measured against a free player at the same point on the
Dinosaur Slots track:

| Free player's slot level | Slots free / paid | Overall multiple |
|---:|---|---:|
| 0 (brand-new account) | 4 / 12 | ×6.00 |
| 5 | 9 / 17 | ×3.78 |
| 12 | 16 / 24 | ×3.00 |
| 26 (track complete) | 30 / 38 | ×2.53 |

So ×2.6 is accurate for a player who has actually played — the advantage
converges on it — and the gap is widest on a fresh account, where the free path
has barely started. That shape is the intended one under §1 rule 1: the passes
are a head start, not a ceiling. It is left uncapped deliberately; capping slots
would mean confiscating placement space a player has already bought and built
their park around.

## 3. Developer products

| Product | Robux | Effect |
|---|---:|---|
| Luck Boost — 2× for 15 min | 49 | Personal |
| Mutation Boost — 2× for 15 min | 79 | Personal |
| Instant Hatch (one egg) | 29 | |
| Instant Hatch All | 99 | |
| Fossil Pack — Small | 49 | 10 min of your current income |
| Fossil Pack — Medium | 199 | 45 min |
| Fossil Pack — Large | 799 | 3 h |
| Park Shield — 30 min | 79 | Capped by the 2 h stack rule |
| Extra Daily Quest Reroll | 25 | |
| Event Egg | 149 | One egg from the current event's table, odds displayed |
| **SERVER: 2× Luck, 10 min** | 199 | Everyone. `DAVID ACTIVATED 2× SERVER LUCK!` |
| **SERVER: 2× Mutation, 10 min** | 249 | Everyone |
| **SERVER: Nest Frenzy, 3 min** | 249 | Triggers the event for everyone |
| **SERVER: Change Weather** | 149 | Buyer picks from a menu; everyone gets it |

**Fossil Packs are scaled to the buyer's own income**, not fixed amounts. This is
the single most important economy decision in the monetization design: it means
a pack is never a shortcut past a wall, and it never breaks the curve for a
rebirth-20 player or trivialises the early game for a new one.

## 4. Server-wide purchases as social design

Server products are the profit centre *and* the community glue. When someone
buys one:

- A full-width gold banner names them.
- Every player gets a one-tap **"Thanks!"** button that sends a floating heart
  above the buyer and gives the *thanker* 500 Fossils (so people actually press
  it).
- The buyer gets a temporary crown above their head.
- A `ServerBoostPurchased` analytics event fires with the resulting session
  extension, so we can measure the retention lift these produce.

Expected outcome, based on how this pattern performs in comparable titles:
server products should be ~35–45 % of revenue while being the least resented
items in the shop.

## 5. Price ladder rationale

- **25–99 R$**: impulse. Should be > 60 % of *transactions*.
- **149–299 R$**: considered. The gamepass entry tier.
- **399–799 R$**: committed. Capped here on purpose.

Target metrics: conversion **3–6 %**, ARPPU **~450 R$**, ARPDAU **~9 R$**.
If ARPPU climbs above ~900 R$ we are over-monetizing whales and should add value
to the low tier rather than raise prices.

## 6. What I deliberately did *not* include

| Rejected | Why |
|---|---|
| Randomised paid crates | Gambling mechanics aimed at minors |
| Robux-only dinosaurs | Violates rule 4; poisons the Index |
| Paid permanent shield | Kills the game's core tension for everyone else |
| Energy / stamina timers sold off | Artificial friction as a product |
| "Gems" premium soft currency | Obscures real prices |
| Pay-to-skip rebirth | Rebirth *is* the game's long arc |
| Trade tax paid in Robux | Encourages off-platform trading |
