# Build Progress

Running record of everything that exists, so nothing gets renamed or rebuilt by
accident. Updated at the end of every build step.

## Status: **Design phase complete. Awaiting "START BUILDING".**

## Completed

| Date | Item | Notes |
|---|---|---|
| 2026-08-29 | Game Design Blueprint (docs 00–15) | Full design, economy, architecture, MVP, build order |

## Build steps (see docs/13-build-order.md)

| Step | Name | Status |
|---:|---|---|
| 1 | Project skeleton & shared modules | ⬜ not started |
| 2 | DataService & PlayerDataService | ⬜ |
| 3 | Config modules & ConfigValidator | ⬜ |
| 4 | State replication | ⬜ |
| 5 | HUD skeleton | ⬜ |
| 6 | Park plots | ⬜ |
| 7 | Nests & the world | ⬜ |
| 8 | Egg pickup & carrying | ⬜ |
| 9 | Guardian AI & the chase | ⬜ |
| 10 | Safe zone & deposit | ⬜ |
| 11 | Incubation & hatching | ⬜ |
| 12 | Placement & income | ⬜ |
| 13 | Upgrades & shop | ⬜ |
| 14 | Zones & teleports | ⬜ |
| 15 | Player raiding | ⬜ |
| 16 | Notifications & announcements | ⬜ |
| 17 | Weather | ⬜ |
| 18 | Server events | ⬜ |
| 19 | Quests, dailies, index | ⬜ |
| 20 | Rebirth | ⬜ |
| 21 | Purchases | ⬜ |
| 22 | Leaderboards | ⬜ |
| 23 | Tutorial | ⬜ |
| 24 | Polish, analytics, hardening | ⬜ |

## Open questions for the developer

1. **Roblox place / experience** — is one created yet? Gamepass and dev product
   IDs in `ProductConfig` are placeholders until it exists.
2. **ProfileStore dependency** — OK to take the third-party module (recommended),
   or build the custom DataStore wrapper described in
   `docs/09-tech-architecture.md` §5?
3. **Art pipeline** — are dinosaur models being made, commissioned, or bought
   from the Creator Store? This determines whether Step 7 blocks on assets.
4. **Team size and target launch date** — changes how aggressively V1 should be
   trimmed further.

None of these block Step 1.
