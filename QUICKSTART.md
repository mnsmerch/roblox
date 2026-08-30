# Getting it running

Three ways to test, in increasing order of setup cost.

---

## 1. Right now, no Studio, no setup (30 seconds)

```bash
./tests/run.sh
```

Syntax-checks all 61 source files and runs **2,964 assertions**: the economy
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
Build the folders first, then paste in step order (1 → 6). The two things to get
right:

- **Object types matter.** `Bootstrap` under `SAD_Server` is a **Script**; under
  `SAD_Client` it is a **LocalScript**. Everything else is a **ModuleScript**.
- **`init.lua` means a child, not a sibling.** `DataService/init.lua` is the
  ModuleScript named `DataService`; `ProfileTemplate` and `Migrations` go
  *inside* it. Same for `PlayerDataService` and `ParkService`.

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

---

## Smoke test: press Play

You should see, in order:

```
[SAD/S] ======== Steal a Dinosaur v0.1.0 starting ========
[SAD/S][Net] Published 38 events and 4 functions
[SAD/S] ======== Config validation ========
  ok      [R1] 4 zone weight vector(s) sum to 100000000
  ok      [R6] all 28 rollable zone x rarity combinations have species
  ...
  8 passed, 0 warning(s), 0 error(s), 3 skipped
[SAD/S][DataService] Store 'SAD_Profiles_v1' ready, schema v1
[SAD/S][ParkService] Built 24 plots at radius 573 in N ms
[SAD/S][PlayerDataService] YourName is a NEW player
[SAD/S][ParkService] Assigned YourName to Plot01
[SAD/S] ======== Server boot complete (N ms) ========
[SAD/C][UIController] SAD_UI mounted with 5 layers
[SAD/C][HUDController] HUD live
[SAD/C] ======== Client boot complete (N ms) ========
```

**Zero errors and zero warnings is the pass condition.**

On screen: you spawn inside your own park facing in, gate behind you, incubator
row ahead, enclosure grid beyond, vault pedestals at the back. A Fossils chip
top-left and five buttons along the bottom.

---

## What actually works today (Steps 1–6)

| Works | Try it |
|---|---|
| Data saves and loads | Set Fossils, stop, Play again — it persists |
| Session locking | Same account in two servers is refused |
| Schema migration + reconcile | Delete a field, rejoin, it comes back |
| Content validation | Break a weight by 1 — the server refuses to boot |
| State replication | Change Fossils server-side, watch the HUD count up |
| The security boundary | Receipt ids are absent client-side |
| Settings round trip | `RequestSetSetting` clamps, rejects, and persists |
| Responsive HUD | Drag the viewport narrow, rails fold away |
| 24 park plots | Two clients get two plots; leaving frees one |
| Park occupancy | Walk through a gate, `ParkEntered` fires |
| Grid ↔ world maths | Drop a marker on tile (4,4), it lands square |
| Hub, 4 zones, 48 nests | Walk out of your park; read a nest sign's odds |
| Egg claiming + respawn | Hold E on an egg; wait 45s and it comes back |
| Placeholder art | 35 dinosaur models and 10 eggs generate themselves |
| Stealing an egg | Hold E at a nest; it appears above your head |
| Carry weight | A Titan egg drops you from 20 to 11 studs/s |
| Loose eggs | Press Q — anyone can grab it for 10 seconds |
| Anti-cheat | Set your own WalkSpeed and get flagged, dropped, snapped back |
| **The chase** | A dinosaur wakes, roars, and runs you down. Escape or trip over |
| Zone difficulty | Frozen Valley guardians genuinely catch you; Jurassic Plains ones mostly do not |
| **The loop closes** | Run home through your gate — SAFE! — and the egg is yours |
| Incubation | Walk to a pad, watch the countdown — its length tells you the tier |
| **The hatch** | Species, mutation and odds, all three revealed at once |

**Not built yet:** placing dinosaurs, income, upgrades, stealing from players.
Steps 12–24. The bottom-bar buttons log `No screen registered` —
that warning is correct, the screens arrive in Step 13.

---

## The five-minute version

If you just want to see it move:

```bash
./tests/run.sh                    # proves the logic
rojo serve                        # then Connect in Studio
```

plus ProfileStore and API access, then Play.

The single most informative test is the one in `SETUP.md` under **Step 3**:
change one rarity weight by 1 and watch the server refuse to boot with
`zone 'plains' weights sum to 100000001`. That is the content pipeline defending
itself, and it is the thing that will save you the most time later.
