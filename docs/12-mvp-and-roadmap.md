# 12 — MVP Definition & Roadmap

## 1. The V1 principle

V1 must contain **the full emotional loop** — steal, run, reveal, place, get
robbed — plus enough rarity ceiling that the viral announcement moments exist on
day one. It must *not* contain systems that only matter after 20 hours of play.

The test I applied to every feature: *"If this is missing, does a player still
scream at their screen in the first hour?"* If no, it's cut from V1.

---

## 2. Version 1.0 — LAUNCH

### IN

**Core loop (complete)**
- Player park with 8 placement slots, 2 incubators, 1 Vault Pedestal
- Wild egg stealing with the full pickup → rarity roll → carry → chase → deposit
  → incubate → hatch → place → income cycle
- Guardian chase AI with **8 archetypes** (Grazer, Skitterer, Sprinter, Charger,
  Bulldozer, Pack Hunter, Wader, Apex)
- Player raiding with shields, Vault, cooldowns, insurance, and the full
  protection ruleset
- Passive income, income bank, Collection Totem, offline income

**Content**
- **Zones 1–4** (Jurassic Plains, Rocky Canyon, Swamp Lands, Frozen Valley)
- **30 dinosaurs**: all 10 Common, all 9 Uncommon, all 8 Rare, 3 Epic
  (Triceratops, Carnotaurus, Allosaurus) — *plus* the ultra-rare hooks below
- **All 9 rarity tiers exist.** Legendary+ are reachable from Zone 4 nests via
  the tail of the weight table, using 4 extra models:
  Tyrannosaurus Rex (Legendary), Spinosaurus (Legendary),
  **Void Raptor (Secret)**, **Titan Rex (Titan)**
  → **34 models total at launch**
- **8 mutations**: Golden, Crystal, Frozen, Electric, Diamond, Rainbow, Galaxy,
  Void. (Enough spread to make the multiplier ladder legible.) Prime stacking IN
- **4 weathers**: Clear, Rainstorm, Thunderstorm, Blizzard
- **4 server events**: Meteor Impact, Dinosaur Stampede, Nest Frenzy, Amber Rain

**Progression**
- 11 upgrade tracks: Dino Slots, Incubators, Incubator Speed, Incubator
  Genetics, Egg Sense, Feeding Trough, Runner's Legs, Strong Back, Egg Pouch,
  Bank Size, Dino Storage
- 3 defence tracks: Fence, Guard Tower, Camera
- Rebirth (full system, including Rebirth Cache)
- Dinosaur Index (34 entries) with milestone rewards at 10/20/30
- 7-day daily rewards + streaks
- 8 daily quests (3 active), 4 weekly quests (3 active)
- Selling → Fossils + DNA. **DNA sink in V1 = mutation reroll only**

**Systems**
- Full data persistence with session locking and migrations
- Complete security layer (all 5 validation layers, carry tokens, movement
  plausibility, ProcessReceipt idempotency)
- Server + cross-server announcements
- 4 leaderboards: Richest, Highest Income, Most Eggs Stolen, Highest Rebirth
- Full HUD, 9 menus, mobile/tablet/PC/console input
- Tutorial (12 beats)
- Analytics (all events in [14-analytics.md](14-analytics.md))

**Monetization**
- 6 gamepasses: VIP, Double Income, Lucky Player, +6 Dino Slots, +2 Incubators,
  Fast Hatch
- 8 dev products: Luck Boost, Mutation Boost, Instant Hatch, Instant Hatch All,
  Fossil Pack S/M, Park Shield, **SERVER: 2× Luck**

### OUT of V1 (and why)

| Cut | Why |
|---|---|
| Zones 5–10 | Nobody reaches Zone 5 inside 3 hours; ship them as the update drumbeat |
| 26 dinosaurs | Content is the cheapest post-launch update. Launch lean, patch weekly |
| Fusion / Stars | Only matters once duplicates pile up — that's day 4+ |
| Trading | Scam and moderation surface; see [06-progression.md](06-progression.md) §6 |
| Boss / Titan Egg / Time Portal / Volcano / Sky Fall / Auction / Blackout | 4 events is enough rhythm; each extra is a week of polish |
| Park decorations & themes | Pure cosmetics; the free park visual tiers already carry the progression feel |
| Electric Fence, Alarm Horn | Defence depth before players understand defence basics |
| Sky Islands flying traversal | Whole new movement system |
| 11 mutations, 7 weathers | Diminishing returns on day-one excitement |
| Guilds / parties | Social systems need a population first |

**Estimated V1 build: 9–12 weeks** for a small team, or ~24 build steps of the
order in [13-build-order.md](13-build-order.md).

---

## 3. Roadmap

| Version | Theme | Contents | Target |
|---|---|---|---|
| **1.0** | Launch | Above | Week 0 |
| **1.0.x** | Stabilise | Live-ops: economy tuning from telemetry, exploit patches, crash fixes. **No new content for 10 days** | Week 0–2 |
| **1.1** | *More Dinosaurs* | +12 species (remaining Epics + all Legendaries), Zone 5 Volcanic Crater, Volcanic + Toxic mutations, Heatwave + Volcanic Ash weather, Volcano Eruption event | Week 3 |
| **1.2** | *The Fossil Lab* | Fusion + Stars, DNA Luck Nodes, Splice, bulk sell, Dino Storage expansion, Index mutation tracking | Week 5 |
| **1.3** | *Chaos* | Boss Dinosaur, Titan Egg, Time Portal, Sky Fall events; Blood Moon + Solar Eclipse + Aurora weather; Shadow/Solar/Lunar/Blood Moon/Celestial/Ancient mutations; +6 Mythic species | Week 8 |
| **1.4** | *Build Your Park* | Zone 6 Lost Jungle + Zone 7 Ancient Ruins, park decorations, park themes, park naming (filtered), Electric Fence + Alarm Horn, 4 more leaderboards + statues | Week 11 |
| **1.5** | *Trading* | Full trading system with every protection in [06-progression.md](06-progression.md) §6, value index, trade history | Week 14 |
| **1.6** | *Wasteland* | Zone 8 Meteor Wasteland, Radiation Storm, all 5 Ancient species, radiation mechanics, Fossil Auction event | Week 17 |
| **2.0** | *Titans* | Zone 9 Sky Islands + Zone 10 Titan Territory, flying traversal, all Titans + remaining Secrets, **second prestige: Fossil Ascension**, guilds/Dino Teams, Blackout Raid, seasonal rotation | Week 22 |
| **2.x** | Seasons | 6-week seasons: 3 limited dinosaurs, a limited mutation, a season pass (free track + paid track), a rotating event | Ongoing |

**Content cadence after 2.0:** one balance patch weekly, one content drop every
2 weeks, one season every 6 weeks. The config-driven architecture in
[11-content-config.md](11-content-config.md) is what makes that cadence
survivable.

---

## 4. Launch readiness gates

Ship only when **all** are true:

| Gate | Threshold |
|---|---|
| Tutorial completion | ≥ 75 % in playtest |
| Crash-free sessions | ≥ 99.5 % |
| Frame rate | ≥ 45 fps p10 on a 2019 mid-range Android, 30 players |
| Data loss | 0 incidents across a 500-session soak |
| Exploit sim | `DebugExploitClient` produces 0 state changes |
| Economy | Simulated day-1 curve within ±20 % of [05-economy.md](05-economy.md) §8 |
| Save/load | 100 % round-trip fidelity across all migrations |
| Mobile UI | Every action completable one-thumbed on a 5.5" screen |
| Moderation | No unfiltered user text anywhere |
