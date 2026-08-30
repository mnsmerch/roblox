# Getting it running

Three ways to test, in increasing order of setup cost.

---

## 1. Right now, no Studio, no setup (30 seconds)

```bash
./tests/run.sh
```

Syntax-checks all 98 source files and runs **5,076 assertions**: the economy
maths, the migration chain, the replication round-trip, the touch-target
guarantee across 12 device viewports, the park grid maths.

It fetches the Luau CLI on first run. This catches most logic errors, but it
cannot catch anything Roblox-dependent — remotes, DataStores, geometry, the
HUD actually rendering. For that you need Studio.

---

## 2. Studio via Rojo — **recommended** (~10 minutes, once)

Rojo syncs `src/` into Studio live. After the one-time setup, every future step
appears in Studio automatically instead of being 5 more files to paste.

**a. Install Rojo.** Either:
- Download the binary from `rojo-rbx/rojo` releases and put it on your PATH, or
- `cargo install rojo` if you have Rust, or
- Use [Aftman](https://github.com/LPGhatguy/aftman): `aftman add rojo-rbx/rojo`

**b. Install the Rojo Studio plugin.** Search "Rojo" in the Studio Toolbox
plugin marketplace, or run `rojo plugin install`.

**c. Clone and serve:**

```bash
git clone https://github.com/mnsmerch/roblox.git steal-a-dinosaur
cd steal-a-dinosaur
git checkout claude/steal-dinosaur-game-n47sq3
rojo serve
```

**d. In Studio:** new baseplate place → Plugins tab → Rojo → **Connect**.

The whole tree appears. `default.project.json` in the repo root maps it.

> I have not been able to run Rojo in my environment, so treat this path as
> unverified convenience. If it misbehaves, option 3 is the source of truth.

**e. Then do the two things Rojo cannot do for you** — see *Studio setup* below.

---

## 3. Studio by hand (~45 minutes, once)

`SETUP.md` has the complete tree and a file-by-file mapping table per step.
Build the folders first, then paste in step order (1 → 24). Three things to get
right:

- **Object types matter.** `Bootstrap` under `SAD_Server` is a **Script**; under
  `SAD_Client` it is a **LocalScript**. Everything else is a **ModuleScript**.
- **`init.lua` means a child, not a sibling.** `DataService/init.lua` is the
  ModuleScript named `DataService`; `ProfileTemplate` and `Migrations` go
  *inside* it. Same for `PlayerDataService`, `ParkService` and every other
  service folder.
- **`DebugExploitClient` is a LocalScript and must be `Disabled`.** It goes
  directly under `SAD_Client`, beside `Bootstrap` — not inside `Controllers`.
  Rojo sets `Disabled` for you from its `.meta.json`.

---

## Studio setup (needed for options 2 and 3)

**a. Enable API access.** Home → Game Settings → Security:
- *Enable Studio Access to API Services* → **On** (DataStores)
- *Allow HTTP Requests* → **On**

**b. Install ProfileStore.** Get the **ProfileStore** module from
`MadStudioRoblox/ProfileStore` (GitHub) or the Creator Store, and place it at
`ServerScriptService/SAD_Server/ProfileStore`.

Make sure it is **ProfileStore**, not ProfileService — they have different APIs
and this code targets ProfileStore. If what you downloaded has
`:LoadProfileAsync` / `:Release()`, that is ProfileService; tell me and I will
adapt `DataService`.

*No API access?* Set `GameConfig.UseMockDataInStudio = true` to run against an
in-memory store. Data is discarded on stop — fine for looking around, useless
for testing saves.

**c. Delete the default `SpawnLocation`** if your baseplate has one.
`CharacterAutoLoads` is off; players are spawned into their own park.

**d. Set `MaxPlayers` to 6** — Home → Game Settings → Basic Info. There are six
park plots, one per player, and a seventh player would join with nowhere to
live. `ParkService` asserts the two config copies of that number at boot and
warns if the place setting disagrees.

---

## Smoke test: press Play

You should see, in order:

```
[SAD/S] ======== Steal a Dinosaur v0.1.0 starting ========
[SAD/S][Net] Published 40 events and 4 functions
[SAD/S] ======== Config validation ========
  ok      [R1] 4 zone weight vector(s) sum to 100000000
  ok      [R6] all 28 rollable zone x rarity combinations have species
  ...
  8 passed, 0 warning(s), 0 error(s), 3 skipped
[SAD/S][DataService] Store 'SAD_Profiles_v1' ready, schema v1
[SAD/S][ParkService] Built 6 plots at radius 286 in N ms
[SAD/S][PlayerDataService] YourName is a NEW player
[SAD/S][ParkService] Assigned YourName to Plot01
[SAD/S] ======== Server boot complete (N ms) ========
[SAD/C][UIController] SAD_UI mounted with 5 layers
[SAD/C][HUDController] HUD live
[SAD/C] ======== Client boot complete (N ms) ========
```

…followed by a line from each of the 25 services and 19 controllers.

**Zero errors is the pass condition.** Two warnings are *expected* and correct:

```
[SAD/S][PurchaseService] Ready, but 6 gamepass(es) and 8 product(s) have no AssetId…
[SAD/S][LeaderboardService] No DataStore access for 'richest'…   (only without API access)
```

The first is deliberate — no asset id is invented anywhere in this project. The
second disappears once Studio API access is on.

On screen: you spawn inside your own park facing in, gate behind you, incubator
row ahead, enclosure grid beyond, vault pedestals at the back. A Fossils chip
top-left, five buttons along the bottom, rails down both sides, and Professor
Rok hopping beside you with an arrow over your gate.

> **Nothing below this line has actually been run.** Every step's expected
> output in SETUP.md is derived from the code, not observed. The first Play test
> is genuinely the first Play test — expect to find things, and tell me what
> Output says rather than working around it.

---

## What is there to see (all 24 steps)

Written, spec-covered, and **never run in Studio**. In roughly the order you
will meet it:

| | Try it |
|---|---|
| Data saves and loads | Set Fossils, stop, Play again — it persists |
| Session locking | Same account in two servers is refused |
| Content validation | Break a rarity weight by 1 — the server refuses to boot |
| Your park | You spawn inside it: incubators, enclosure grid, vault pedestals |
| Hub, 4 zones, 48 nests | Walk out; read a nest sign's odds and risk skulls |
| **The tutorial** | Professor Rok, one arrow, 12 beats — the first thing you'll see |
| Stealing an egg | Hold E at a nest; it appears above your head, rarity flashes |
| Carry weight | A Titan egg drops you from 20 to 11 studs/s |
| **The chase** | A dinosaur wakes, roars, and runs you down. Escape or trip over |
| **The loop closes** | Run home through your gate — SAFE! — and the egg is yours |
| **The hatch** | Species, mutation and odds, all three revealed at once |
| Placement and income | Drop it on a tile; Fossils tick up; tap the totem |
| Upgrades | 🛒 — three boards, 14 tracks, prices you can actually afford |
| Zones and teleports | Unlock Canyon, use the Obelisk, find a shrine |
| **Raiding other players** | Two clients: hold to steal a placed dinosaur, get tagged |
| Weather | Four weathers on an 8-minute roll; Blizzard shifts your mutation odds |
| Server events | Meteor Impact, Stampede, Nest Frenzy, Amber Rain |
| Quests, dailies, Index | ✅ 📖 🎁 on the left rail |
| Rebirth | ♻️ — a keep / lose / gain screen before you delete your park |
| The store | 💎 — browsable, honest, and every row reads COMING SOON |
| Leaderboards | 🏆, and four pillars plus three gold statues west of the plaza |
| Settings | ⚙️ — 13 rows, all generated from the schema |
| The map | 🗺️ or **M** — zones, your park, unlock costs; a small disc on tablet and desktop |
| Dinosaurs that move | They breathe, stride and lean by archetype; a Charger crouches before it charges |
| The exploit sweep | `_G.SAD_DebugExploit.Run()` in Studio |

**Known holes:** no sounds or real art, and no animation *assets* — nothing in
this project invents an asset id. Dinosaurs do move: they breathe when still,
stride when running and crouch before a charge, all procedurally, because the
placeholder models have no rig for a real animation to play on. No localised
zone hazards either, so zone difficulty rests entirely on guardian speed.

---

## The five-minute version

If you just want to see it move:

```bash
./tests/run.sh                    # proves the logic
rojo serve                        # then Connect in Studio
```

plus ProfileStore and API access, then Play.

**Expect the first Play to fail somewhere.** 95 files across 24 steps have never
been loaded by Roblox once. The likely first three, in order:

1. **`[SAD] ProfileStore is not installed`** — the boot aborts on purpose.
   Install it, or set `GameConfig.UseMockDataInStudio = true` to look around
   without it.
2. **A `Boot aborted:` line naming one service.** `GameConfig.StrictBoot` is
   `true`, so one bad service stops everything — deliberately, in Studio. The
   line names the service and the phase (`require`, `Init` or `Start`).
3. **A missing Roblox API or a changed signature.** Paste the error; do not
   work around it. A wrong assumption about Roblox is exactly the thing the
   offline specs cannot catch, and it is worth fixing at the source.

The single most informative test is the one in `SETUP.md` under **Step 3**:
change one rarity weight by 1 and watch the server refuse to boot with
`zone 'plains' weights sum to 100000001`. That is the content pipeline defending
itself, and it is the thing that will save you the most time later.
