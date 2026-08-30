# Studio Setup — Step 1

Two ways to get the code into Roblox Studio. **Option A is authoritative** — it
is the one I have verified the structure of. Option B is a convenience if you
already use Rojo.

---

## Option A — Manual (no extra tools)

### 1. Enable DataStore access (needed from Step 2, do it now)

`Home → Game Settings → Security → Enable Studio Access to API Services` → On.
Also `Allow HTTP Requests` → On.

### 2. Build the tree

Create these objects with **exactly** these names. Names are frozen —
`docs/09-tech-architecture.md` is the contract.

**In `ReplicatedStorage`:**

```
ReplicatedStorage
└── SAD_Shared                (Folder)
    ├── Config                (Folder)
    │   └── GameConfig        (ModuleScript)
    ├── Modules               (Folder)
    │   ├── Types             (ModuleScript)
    │   ├── Log               (ModuleScript)
    │   ├── Signal            (ModuleScript)
    │   ├── Trove             (ModuleScript)
    │   ├── TableUtil         (ModuleScript)
    │   ├── Format            (ModuleScript)
    │   ├── RNG               (ModuleScript)
    │   └── Net               (ModuleScript)
    └── SAD_Assets            (Folder)
        ├── Dinos             (Folder)
        ├── Eggs              (Folder)
        ├── Effects           (Folder)
        └── UI                (Folder)
```

> `ReplicatedStorage/SAD_Net` is **not** created by hand. `Net.Init()` builds it
> and every remote inside it at server boot. Do not add it manually — the server
> destroys and rebuilds it on start.

**In `ServerScriptService`:**

```
ServerScriptService
└── SAD_Server                (Folder)
    ├── Bootstrap             (Script)     ← a Script, not a ModuleScript
    └── Services              (Folder)     ← empty for now
```

**In `StarterPlayer → StarterPlayerScripts`:**

```
StarterPlayerScripts
└── SAD_Client                (Folder)
    ├── Bootstrap             (LocalScript)  ← a LocalScript
    └── Controllers           (Folder)       ← empty for now
```

### 3. Paste the code

| Studio object | Source file |
|---|---|
| `SAD_Shared/Config/GameConfig` | `src/ReplicatedStorage/SAD_Shared/Config/GameConfig.lua` |
| `SAD_Shared/Modules/Types` | `src/ReplicatedStorage/SAD_Shared/Modules/Types.lua` |
| `SAD_Shared/Modules/Log` | `src/ReplicatedStorage/SAD_Shared/Modules/Log.lua` |
| `SAD_Shared/Modules/Signal` | `src/ReplicatedStorage/SAD_Shared/Modules/Signal.lua` |
| `SAD_Shared/Modules/Trove` | `src/ReplicatedStorage/SAD_Shared/Modules/Trove.lua` |
| `SAD_Shared/Modules/TableUtil` | `src/ReplicatedStorage/SAD_Shared/Modules/TableUtil.lua` |
| `SAD_Shared/Modules/Format` | `src/ReplicatedStorage/SAD_Shared/Modules/Format.lua` |
| `SAD_Shared/Modules/RNG` | `src/ReplicatedStorage/SAD_Shared/Modules/RNG.lua` |
| `SAD_Shared/Modules/Net` | `src/ReplicatedStorage/SAD_Shared/Modules/Net.lua` |
| `SAD_Server/Bootstrap` | `src/ServerScriptService/SAD_Server/Bootstrap.server.lua` |
| `SAD_Client/Bootstrap` | `src/StarterPlayer/StarterPlayerScripts/SAD_Client/Bootstrap.client.lua` |

The `.server.lua` / `.client.lua` suffixes are a naming convention that records
the object type. In Studio both objects are simply named `Bootstrap`.

---

## Option B — Rojo

`default.project.json` in the repo root maps `src/` onto the tree above.

```bash
rojo serve
```

then connect from the Rojo Studio plugin. File suffixes map as usual:
`.lua` → ModuleScript, `.server.lua` → Script, `.client.lua` → LocalScript.

I have not been able to run Rojo in this environment, so treat Option B as
untested convenience and Option A as the source of truth. If the two ever
disagree, Option A wins.

---

## Step 2 — install ProfileStore

`DataService` depends on **ProfileStore**, an open-source session-locking
DataStore wrapper by loleris (MadStudioRoblox). It is a community module, **not
a Roblox API** — it has to be added to the place by hand.

Get it from the `MadStudioRoblox/ProfileStore` GitHub repository, or from the
Roblox Creator Store. Take the **ProfileStore** module (the successor to
ProfileService), not ProfileService itself — the two have different APIs and
this code is written against ProfileStore.

Place it here, named exactly `ProfileStore`:

```
ServerScriptService
└── SAD_Server
    ├── Bootstrap        (Script)
    ├── ProfileStore     (ModuleScript)   ← the third-party module
    └── Services         (Folder)
        ├── DataService          (ModuleScript)
        │   ├── ProfileTemplate  (ModuleScript)
        │   └── Migrations       (ModuleScript)
        └── PlayerDataService    (ModuleScript)
```

It must live under `ServerScriptService` so it never replicates to clients.
`Bootstrap` only auto-requires modules inside `Services`, so `ProfileStore`
sitting alongside is correct — it is required by `DataService`, not by
`Bootstrap`.

`DataService` is a **ModuleScript with two ModuleScript children**, not a
folder. `ProfileTemplate` and `Migrations` go *inside* it.

| Studio object | Source file |
|---|---|
| `Services/DataService` | `src/.../Services/DataService/init.lua` |
| `Services/DataService/ProfileTemplate` | `src/.../Services/DataService/ProfileTemplate.lua` |
| `Services/DataService/Migrations` | `src/.../Services/DataService/Migrations.lua` |
| `Services/PlayerDataService` | `src/.../Services/PlayerDataService.lua` |

### ProfileStore API surface used

`DataService` is the only file that touches ProfileStore, and it uses exactly
these members. I could not run them against the real module in my environment,
so **verify these against the version you install** — if any name differs, all
the fixes are in that one file:

```
ProfileStore.New(storeName, template)
store.Mock                                  -- Studio-only, in-memory
store:StartSessionAsync(key, { Cancel = fn })
profile.Data
profile.OnSessionEnd                        -- :Connect(fn)
profile:AddUserId(userId)
profile:Save()
profile:EndSession()
```

If the module you install exposes `:LoadProfileAsync` / `:Release()` /
`:ListenToRelease()` instead, you have **ProfileService**, not ProfileStore.
Either fetch ProfileStore or tell me and I will adapt `DataService`.

### No API access? 

Set `GameConfig.UseMockDataInStudio = true` to run against ProfileStore's
in-memory mock store. **Mock data is discarded when you stop the session** — it
exists so you can keep building without DataStore access, not to test saving.
Set it back to `false` before testing persistence, and never publish with it on.

---

## Step 3 — config modules

Seven new ModuleScripts, all under `ReplicatedStorage/SAD_Shared/Config`
alongside the existing `GameConfig`:

| Studio object | Source file |
|---|---|
| `Config/RarityConfig` | `src/.../Config/RarityConfig.lua` |
| `Config/MutationConfig` | `src/.../Config/MutationConfig.lua` |
| `Config/DinoConfig` | `src/.../Config/DinoConfig.lua` |
| `Config/ZoneConfig` | `src/.../Config/ZoneConfig.lua` |
| `Config/UpgradeConfig` | `src/.../Config/UpgradeConfig.lua` |
| `Config/RebirthConfig` | `src/.../Config/RebirthConfig.lua` |
| `Config/ConfigValidator` | `src/.../Config/ConfigValidator.lua` |

`Bootstrap` also changed this step — re-paste
`src/ServerScriptService/SAD_Server/Bootstrap.server.lua`. It now runs
`ConfigValidator` before loading any service.

---

## Step 4 — replication

**One restructure:** `PlayerDataService` becomes a ModuleScript **with a child**,
the same shape as `DataService`. In Studio, add a ModuleScript named
`Replication` inside the existing `PlayerDataService`.

| Studio object | Source file |
|---|---|
| `SAD_Shared/Modules/Patch` | `src/.../Modules/Patch.lua` *(new)* |
| `Services/PlayerDataService` | `src/.../PlayerDataService/init.lua` *(re-paste)* |
| `Services/PlayerDataService/Replication` | `src/.../PlayerDataService/Replication.lua` *(new)* |
| `SAD_Client/Controllers/StateController` | `src/.../Controllers/StateController.lua` *(new)* |
| `Config/GameConfig` | *(re-paste — gained `SettingsSchema`)* |

`Bootstrap` is unchanged this step; `StateController` is already in
`CONTROLLER_ORDER`.

---

## Step 5 — the HUD

A new `UI` folder under `SAD_Client`, sibling to `Controllers`:

```
StarterPlayerScripts
└── SAD_Client
    ├── Bootstrap        (LocalScript)
    ├── UI               (Folder)          ← new
    │   ├── Theme        (ModuleScript)
    │   ├── Create       (ModuleScript)
    │   └── Widgets      (ModuleScript)
    └── Controllers      (Folder)
        ├── StateController
        ├── UIController      ← new
        ├── HUDController     ← new
        └── InputController   ← new
```

| Studio object | Source file |
|---|---|
| `SAD_Client/UI/Theme` | `src/.../SAD_Client/UI/Theme.lua` |
| `SAD_Client/UI/Create` | `src/.../SAD_Client/UI/Create.lua` |
| `SAD_Client/UI/Widgets` | `src/.../SAD_Client/UI/Widgets.lua` |
| `SAD_Client/Controllers/UIController` | `src/.../Controllers/UIController.lua` |
| `SAD_Client/Controllers/HUDController` | `src/.../Controllers/HUDController.lua` |
| `SAD_Client/Controllers/InputController` | `src/.../Controllers/InputController.lua` |

**Nothing goes in StarterGui.** `SAD_UI` is created at runtime into `PlayerGui`
by `UIController`. `Bootstrap` is unchanged — all three controllers are already
in `CONTROLLER_ORDER`.

---

## Step 6 — park plots

`ParkService` becomes a ModuleScript **with a child**, like `DataService`.

| Studio object | Source file |
|---|---|
| `SAD_Shared/Config/ParkConfig` | `src/.../Config/ParkConfig.lua` *(new)* |
| `Services/ParkService` | `src/.../ParkService/init.lua` *(new)* |
| `Services/ParkService/PlotBuilder` | `src/.../ParkService/PlotBuilder.lua` *(new)* |

**Nothing goes in Workspace.** All 24 plots are generated at boot into
`Workspace/SAD_World/ParkPlots`, and the previous ring is destroyed on each
run — so a Studio re-run never leaves a duplicate behind.

If your place still has the default **Baseplate** and **SpawnLocation**, delete
the SpawnLocation (`CharacterAutoLoads` is now off and players are spawned into
their own park) and keep or delete the Baseplate as you like — the plots have
their own ground. Step 7 builds the hub and zones.

---

## Step 7 — the world and nests

| Studio object | Source file |
|---|---|
| `SAD_Shared/Modules/AssetBuilder` | `src/.../Modules/AssetBuilder.lua` *(new)* |
| `SAD_Shared/Config/ZoneConfig` | *(re-paste — gained ring geometry)* |
| `SAD_Shared/Config/ConfigValidator` | *(re-paste — rule 7 is now live)* |
| `SAD_Server/Bootstrap` | *(re-paste — runs AssetBuilder before validation)* |
| `Services/NestService` | `src/.../NestService/init.lua` *(new)* |
| `Services/NestService/WorldBuilder` | `src/.../NestService/WorldBuilder.lua` *(new)* |
| `Services/NestService/NestBuilder` | `src/.../NestService/NestBuilder.lua` *(new)* |

`NestService` is a ModuleScript with **two** ModuleScript children.

Nothing goes in Workspace by hand — the hub, four zones and 48 nests generate at
boot, and the previous world is destroyed each run. `SAD_Assets` fills itself
with placeholder models.

---

## Step 8 — pickup and carrying

| Studio object | Source file |
|---|---|
| `Services/SecurityService` | `src/.../SecurityService/init.lua` *(new)* |
| `Services/EggService` | `src/.../EggService/init.lua` *(new)* |
| `SAD_Client/Controllers/EggCarryController` | `src/.../Controllers/EggCarryController.lua` *(new)* |
| `SAD_Shared/Config/GameConfig` | *(re-paste — movement and carry constants)* |
| `Services/NestService` | *(re-paste — prompts now signal instead of claiming)* |
| `SAD_Client/Controllers/HUDController` | *(re-paste — carry panel)* |

`SecurityService` and `EggService` are ModuleScripts with no children.

> **Step 7's egg test changes.** Nest prompts no longer claim an egg by
> themselves — holding one now mints a carry token and welds the egg to you.
> That is Step 7's behaviour being superseded, not broken.

---

## Step 9 — the chase

| Studio object | Source file |
|---|---|
| `SAD_Shared/Config/ChaseConfig` | `src/.../Config/ChaseConfig.lua` *(new)* |
| `Services/WildAIService` | `src/.../WildAIService/init.lua` *(new)* |
| `SAD_Client/Controllers/CameraController` | `src/.../Controllers/CameraController.lua` *(new)* |
| `SAD_Shared/Config/ZoneConfig` | *(re-paste — `GuardianSpeedBonus`)* |
| `Services/EggService` | *(re-paste — speed modifiers)* |
| `Services/NestService/NestBuilder` | *(re-paste — guardian eligibility filter)* |
| `SAD_Client/Controllers/HUDController` | *(re-paste — chase banner + vignette)* |
| `SAD_Client/Controllers/EggCarryController` | *(re-paste — chase handling)* |

---

## Step 10 — safe zone and deposit

No new files. Re-paste four:

| Studio object | Why |
|---|---|
| `SAD_Shared/Config/GameConfig` | `EggStorageCap` |
| `Services/EggService` | `DepositAll`, the gate hook, loss stats |
| `Services/WildAIService` | escape/catch stats |
| `SAD_Client/Controllers/HUDController` | the `Flash` banner |
| `SAD_Client/Controllers/EggCarryController` | `Notify` handling |

---

## Step 11 — incubation and hatching

| Studio object | Source file |
|---|---|
| `Services/MutationService` | `src/.../MutationService/init.lua` *(new)* |
| `Services/DinosaurService` | `src/.../DinosaurService/init.lua` *(new)* |
| `Services/IncubationService` | `src/.../IncubationService/init.lua` *(new)* |
| `SAD_Client/Controllers/HUDController` | *(re-paste — hatch reveal)* |
| `SAD_Client/Controllers/EggCarryController` | *(re-paste — `HatchResult`)* |

All three services are ModuleScripts with no children.

---

## Step 12 — placement and income

| Studio object | Source file |
|---|---|
| `SAD_Shared/Modules/Economy` | `src/ReplicatedStorage/SAD_Shared/Modules/Economy.lua` *(new)* |
| `Services/EconomyService` | `src/.../Services/EconomyService/init.lua` *(new)* |
| `Services/DinosaurService` | *(re-paste — place/store/sell)* |
| `Services/ParkService` | *(re-paste — dinosaur rendering, totem)* |
| `Services/IncubationService` | *(re-paste — auto-place on hatch)* |
| `SAD_Client/Controllers/ParkController` | `src/.../Controllers/ParkController.lua` *(new)* |
| `SAD_Client/Controllers/HUDController` | *(re-paste — `ShowReveal`, offline summary)* |
| `SAD_Client/Controllers/EggCarryController` | *(re-paste — reveal call sites)* |

`Economy` is a ModuleScript beside `Patch` in `SAD_Shared/Modules`. It must be
installed **before** `EconomyService`, `DinosaurService` and `ParkController`,
all three of which require it. `EconomyService` is a Folder named
`EconomyService` containing a ModuleScript named `init` — the same shape as
`DataService` and `ParkService`.

---

## Step 1 test

Press **Play**. The Output window should show, in order:

```
[SAD/S] ======== Steal a Dinosaur v0.1.0 starting ========
[SAD/S][Net] Published 38 events and 4 functions
[SAD/S][Boot] Not built yet (24): SecurityService, DataService, ...
[SAD/S][Boot] Loaded 0 service(s):
[SAD/S] ======== Server boot complete (N ms) ========
[SAD/C] ======== Steal a Dinosaur v0.1.0 client starting ========
[SAD/C][Net] Connected to remote tree
[SAD/C][Boot] Not built yet (17): StateController, SoundController, ...
[SAD/C][Boot] Loaded 0 controller(s):
[SAD/C] ======== Client boot complete (N ms) ========
```

Then check `ReplicatedStorage → SAD_Net` exists at runtime with `Events`
(38 RemoteEvents) and `Functions` (4 RemoteFunctions).

**Zero errors and zero warnings is the pass condition.**

### What to check if it fails

| Symptom | Cause |
|---|---|
| `SAD_Net never replicated` on the client | The server `Bootstrap` is a ModuleScript, or is disabled, or is not under `SAD_Server` |
| `Infinite yield possible on 'SAD_Shared'` | `SAD_Shared` is not directly under `ReplicatedStorage`, or is misspelled |
| `attempt to index nil with 'Modules'` | `Modules`/`Config` folder name typo |
| Client boots before the server | Expected on a real server; `Net.Init()` waits up to 30 s. If it times out, the server Bootstrap errored — read the server output first |
| `must return a table` | A service/controller file is missing its `return` |

---

## Step 2 test

With ProfileStore installed and API access enabled, press **Play**.

**1. Boot and first load.** Output should include:

```
[SAD/S][DataService] Store 'SAD_Profiles_v1' ready, schema v1
[SAD/S][DataService] Session started for YourName (schema v1)
[SAD/S][PlayerDataService] YourName is a NEW player
[SAD/S][PlayerDataService] Loaded YourName | Fossils 0 | Rebirths 0 | Playtime 0s | New: true
[SAD/S][Boot] Loaded 2 service(s): DataService, PlayerDataService
```

**2. Persistence round trip.** In the **command bar** (server context, while
playing):

```lua
local PDS = require(game.ServerScriptService.SAD_Server.Services.PlayerDataService)
local p = game.Players:GetPlayers()[1]
PDS.Update(p, function(d) d.Fossils = 500 d.Stats.EggsStolen = 7 end, "manual test")
PDS.Save(p, "manual test")
print("Fossils:", PDS.Get(p).Fossils)
```

Stop, Play again. Expect `New: false`, `Fossils 500`, and a non-zero playtime.

**3. Clean shutdown.** Press Stop and look for:

```
[SAD/S] ======== Shutdown - flushing sessions ========
[SAD/S][DataService] Session ended for YourName
[SAD/S][DataService] All sessions flushed
```

`%d session(s) did not flush before the shutdown deadline` means saves are not
completing — investigate before shipping anything else.

**4. Reconcile.** Simulate an old save that predates a field:

```lua
local PDS = require(game.ServerScriptService.SAD_Server.Services.PlayerDataService)
local p = game.Players:GetPlayers()[1]
PDS.Get(p).DNA = nil          -- pretend this field did not exist yet
PDS.Save(p, "reconcile test")
```

Stop, Play. `PDS.Get(p).DNA` should be back at `0`, and `Fossils` still `500`.

**5. Schema guard (optional but worth seeing once).** Set
`GameConfig.SchemaVersion = 2` and Play. The boot must **abort** with
`Schema mismatch: template is v2 but the migration chain ends at v1`. Set it
back to `1`. This is the check that stops a schema bump from locking every
player out.

### What to watch for

| Symptom | Cause |
|---|---|
| `ProfileStore is not installed` | Module missing, or not named exactly `ProfileStore`, or not directly under `SAD_Server` |
| `Could not acquire a session lock` | The same account has a live session elsewhere. Wait ~30 s and rejoin — this is the lock doing its job |
| Kicked with "opened in another server" | Same as above, from the other direction. Expected behaviour, not a bug |
| Data not persisting between Play sessions | API Services disabled, or `UseMockDataInStudio` is still `true` |
| `attempt to call nil` inside ProfileStore | You have ProfileService, not ProfileStore |
| Values reset after a crash | Only saves since the last successful write are lost. Confirm autosave lines appear roughly every 3 minutes |

**Session locking cannot be fully tested in Studio** — it needs the same
account in two separate servers. Test it in a published place with two devices,
or trust ProfileStore's own test suite for it.

---

## Step 3 test

Press **Play**. Between the remote tree and the service list you should now see:

```
[SAD/S] ======== Config validation ========
  ok      [R1] 4 zone weight vector(s) sum to 100000000
  ok      [R2] 9 shipped mutation(s) sum to 100000000
  ok      [R3] 34 species reference known rarities
  ok      [R4] all species zone references resolve
  ok      [R5] zones, pools and weight vectors line up
  ok      [R6] all 28 rollable zone x rarity combinations have species
  ok      [R9] 14 upgrade track(s) validated
  ok      [S] structural checks complete
  skipped SAD_Assets (Step 7) - not built yet
  skipped EventConfig (Step 18) - not built yet
  skipped ProductConfig (Step 21) - not built yet
  8 passed, 0 warning(s), 0 error(s), 3 skipped
```

**Zero errors is the pass condition.** Any error aborts the boot on purpose.

### See the validator do its job

Worth breaking once, so you recognise the failure when it happens for real.
In `RarityConfig`, change Zone 1's `epic` weight from `1800000` to `1800001`
and Play:

```
  ERROR   [R1] zone 'plains' weights sum to 100000001, expected 100000000 (off by 1)
[SAD] Boot aborted: 1 content error(s). Fix the config, not the code.
```

Then try the important one. Put `mythic = 9500` back into Zone 1 (and drop
`legendary` to `190480` so it still sums):

```
  ERROR   [R6] zone 'plains' rolls mythic at weight 9500 but has NO mythic
          species (that tier ships after V1 - set its weight to 0 until then)
```

That is the bug this rule exists for. Without it the game boots happily, and
one player in three weeks watches a 45-minute incubation finish and receive
nothing. Undo both edits afterwards.

### Inspect the content from the command bar

```lua
local C = game.ReplicatedStorage.SAD_Shared.Config
local Dino = require(C.DinoConfig)
local Rarity = require(C.RarityConfig)

print("species:", Dino.Count())
print("Zone 4 Legendaries:", table.concat(Dino.SpeciesFor("frozen", "legendary"), ", "))
print("Zone 1 Titan odds: 1 in", 1e8 / Rarity.ZoneWeights.plains.titan)

local trex = Dino.Get("trex")
print(trex.DisplayName, "earns", Rarity.Tiers[trex.Rarity].BaseIncome * trex.SpeciesFactor, "F/s")
```

### What to watch for

| Symptom | Cause |
|---|---|
| `ConfigValidator` infinite yield | Not directly under `SAD_Shared/Config`, or misspelled |
| `R6` errors after you add a dinosaur | Its rarity has no coverage in a zone that rolls it. Add a zone to the species, or zero that tier's weight |
| `R1` errors after a weight edit | The vector no longer sums to 100,000,000. The tool is the point — adjust another tier to compensate |
| `attempt to index nil with 'Species'` | A config was pasted into the wrong object name |

---

## Step 4 test

**1. Boot.** Play. Expect:

```
[SAD/S][Replication] 25 field(s) replicated, 5 withheld
[SAD/S][Replication] Flushing at 5 Hz
[SAD/S][Replication] Sent full state to YourName
[SAD/C][StateController] State ready
[SAD/C][Boot] Loaded 1 controller(s): StateController
```

**2. The mirror arrived.** In the **client** console (F9 → Client, or the
command bar set to client context):

```lua
local S = require(game.Players.LocalPlayer.PlayerScripts.SAD_Client.Controllers.StateController)
print(S.IsReady(), S.GetPath({ "Fossils" }), S.GetPath({ "Settings", "MusicVolume" }))
print("withheld:", S.GetPath({ "ProcessedReceipts" }))  --> nil, correctly
```

**3. A delta lands.** Server command bar:

```lua
local PDS = require(game.ServerScriptService.SAD_Server.Services.PlayerDataService)
local p = game.Players:GetPlayers()[1]
PDS.UpdateKeys(p, { "Fossils" }, function(d) d.Fossils += 777 end, "test")
```

The client's `Fossils` should change within a frame or two — currency flushes
immediately rather than waiting for the 5 Hz tick.

**4. Observe fires.** Client console:

```lua
local S = require(game.Players.LocalPlayer.PlayerScripts.SAD_Client.Controllers.StateController)
S.Observe({ "Fossils" }, function(v) print("Fossils ->", v) end)
```

It prints once immediately, then again on every server-side change. This is the
pattern every HUD element in Step 5 uses.

**5. Nothing leaks.** Confirm the five withheld fields are absent client-side:

```lua
for _, k in { "ProcessedReceipts", "RobuxSpent", "LastSeen", "FirstJoinAt", "SchemaVersion" } do
    print(k, S.GetPath({ k }))   -- all nil
end
```

**6. The boundary assert.** Add a junk field to `ProfileTemplate`
(`Wibble = 0`) and Play. The server must **refuse to boot**:

```
Replication: profile field(s) Wibble are neither replicated nor withheld.
Add each to REPLICATED or WITHHELD in Replication.lua - this is a security decision.
```

Remove it afterwards. This is the guard that stops a future field silently
reaching clients — or silently failing to.

**7. Settings round trip.** Client console:

```lua
game.ReplicatedStorage.SAD_Net.Events.RequestSetSetting:FireServer("MusicVolume", 15)
task.wait(0.5)
print(S.GetPath({ "Settings", "MusicVolume" }))   --> 15
```

Then try to break it — all four must leave the value at 15:

```lua
local E = game.ReplicatedStorage.SAD_Net.Events.RequestSetSetting
E:FireServer("MusicVolume", 9999)      -- clamped to 100
E:FireServer("MusicVolume", "loud")    -- wrong type, dropped
E:FireServer("Fossils", 999999999)     -- not a setting, dropped
E:FireServer("Particles", "Ultra")     -- not an allowed option, dropped
```

The third one is the important one: `Fossils` is not in `SettingsSchema`, so the
setting path cannot be used to write currency.

### What to watch for

| Symptom | Cause |
|---|---|
| `State ready` never prints | Server `Replication` failed its boot assert — read the server output first |
| Client state is empty but no error | `StateController` not inside `SAD_Client/Controllers`, or misnamed |
| `requested module was required recursively` | `Replication` pasted as a sibling of `PlayerDataService` instead of a child |
| Deltas arrive but nothing updates | A write used raw table access instead of `Update`/`UpdateKeys` |
| Client sees a stale value forever | That write bypassed `UpdateKeys`; there is no polling fallback by design |

---

## Step 5 test

**1. Boot.** Play. Expect:

```
[SAD/C][UIController] SAD_UI mounted with 5 layers
[SAD/C][InputController] 11 action(s) bound
[SAD/C][HUDController] HUD built
[SAD/C][HUDController] HUD live
[SAD/C][Boot] Loaded 4 controller(s): StateController, UIController, HUDController, InputController
```

On screen: a Fossils chip top-left, five buttons along the bottom, four icons
down each side. **DNA, the rebirth badge and the shield timer are absent** —
that is progressive disclosure working, not a bug.

**2. The counter is live and animates.** Server command bar:

```lua
local PDS = require(game.ServerScriptService.SAD_Server.Services.PlayerDataService)
local p = game.Players:GetPlayers()[1]
PDS.UpdateKeys(p, { "Fossils" }, function(d) d.Fossils = 1234567 end, "test")
```

The chip should count *up* to `1.23M` over about half a second rather than
snapping. Then reveal the hidden chips:

```lua
PDS.Update(p, function(d)
    d.DNA = 250
    d.Rebirths = 7
    d.ShieldUntil = os.time() + 90
end, "test")
```

DNA and `R7` appear; the shield chip appears and counts down `01:30 → 00:00`,
then hides itself.

**3. Responsive layout.** Drag the Studio viewport narrow and watch the left
rail fold into a `☰` button, and the right rail disappear entirely. Widen it
and both come back. The Output logs each transition:

```
[SAD/C][UIController] Breakpoint compact (792 logical px, scale 0.84)
```

**4. The accessibility scale.** Client console:

```lua
game.ReplicatedStorage.SAD_Net.Events.RequestSetSetting:FireServer("UiScale", 130)
```

The whole HUD grows. Try `80`, then `9999` (clamps to 130), then `"big"`
(dropped — wrong type).

**5. Input parity.** Press `1` through `5`. Each should behave exactly as
tapping the matching bottom-bar button, because both route through
`InputController.Fire`. Nothing opens yet — the screens arrive in Step 13 — so
watch for the warning that proves the wiring:

```
[SAD/C][UIController] No screen registered as 'ToggleShop' - not built yet?
```

**6. The action prompt.** Client console:

```lua
local H = require(game.Players.LocalPlayer.PlayerScripts.SAD_Client.Controllers.HUDController)
H.SetAction("HOLD TO STEAL", 0.62)   -- appears with a 62% fill
task.wait(2)
H.SetChaseMode(true)                 -- bottom bar and rails vanish
task.wait(2)
H.SetChaseMode(false)
H.SetAction(nil)
```

Step 8 drives this for egg pickup and Step 9 for chases; it exists now so those
steps add behaviour rather than layout.

**7. Survives respawn.** Reset your character. The HUD must stay — that is the
whole reason `SAD_UI` lives in `PlayerGui` rather than `StarterGui`.

### What to watch for

| Symptom | Cause |
|---|---|
| No HUD at all | `UI` folder is inside `Controllers` instead of beside it |
| `unknown layer 'hud'` | `Theme` pasted into the wrong object |
| Buttons look tiny on a phone | Something overrode `Theme.ScaleFor` — the floor is derived, not hand-set |
| HUD vanishes on respawn | `SAD_UI` was hand-created in StarterGui as well; delete it |
| Emoji render as boxes | Expected on some platforms — Step 24 swaps in real icon assets |

---

## Step 6 test

**1. Boot.** Play. Expect:

```
[SAD/S][ParkService] Built 24 plots at radius 573 in N ms
[SAD/S][ParkService] Assigned YourName to Plot01
[SAD/S][ParkService] Occupancy sampling at 4 Hz
```

You should spawn **inside a park**, facing in, with a gate behind you, an
incubator row in front, the enclosure grid beyond it and vault pedestals at the
back. The gate sign reads `YourName's Park`.

There should be **no visible teleport** — you materialise in the park rather
than appearing at the origin and being moved. That is `CharacterAutoLoads` being
off and the character spawned by hand once a plot is assigned.

**2. Plots face inward.** Walk out of your gate toward the middle of the ring.
Every other park's gate should be facing you. That is the status engine from
docs/02 §1.1 — a Titan in anyone's park will be visible from the plaza.

**3. Two players get two plots.** Use **Test → Clients and Servers → 2 players**.
Each gets a different plot, each spawns in their own, and each sign shows the
right name. Then stop one client and confirm the plot frees:

```
[SAD/S][ParkService] Released Player2 from Plot02
```

Its sign returns to `Empty Plot`.

**4. Occupancy fires at gates.** Server command bar:

```lua
local Park = require(game.ServerScriptService.SAD_Server.Services.ParkService)
Park.ParkEntered:Connect(function(p, owner) print(p.Name, "entered park of", owner) end)
Park.ParkExited:Connect(function(p, owner) print(p.Name, "left park of", owner) end)
```

Walk in and out of your gate, then into another player's. This is what Step 10
uses to end a chase and deposit an egg, and Step 15 to complete a raid — and it
is computed from position server-side, never from a `Touched` event, which a
client can fire by hand.

**5. Grid maths matches geometry.**

```lua
local Park = require(game.ServerScriptService.SAD_Server.Services.ParkService)
local p = game.Players:GetPlayers()[1]
local plot = Park.GetPlot(p)

-- Stand somewhere on the grid, then:
local root = p.Character.HumanoidRootPart
print("tile:", Park.WorldToTile(plot, root.Position))

-- And the inverse: drop a marker on tile (4,4)
local marker = Instance.new("Part")
marker.Anchored, marker.CanCollide, marker.Size = true, false, Vector3.new(9, 1, 9)
marker.Color = Color3.fromRGB(95, 211, 95)
marker.CFrame = Park.GetTileCFrame(plot, 4, 4)
marker.Parent = workspace
```

The marker should land squarely on a grid square. Try a footprint too —
`Park.GetTileCFrame(plot, 5, 5, "4x4")` sits in the middle of a 4×4 block.

**6. The shield dome.**

```lua
Park.SetShieldVisible(Park.GetPlot(game.Players:GetPlayers()[1]), true)
```

**7. Visual tiers.** `Park.SetVisualTier(plot, 2e6)` turns the park to stone.
Free progression that a returning player notices; Step 12 drives it from real
park value.

### What to watch for

| Symptom | Cause |
|---|---|
| Gates face outward | `PlotBuilder.OriginOf` was edited — `CFrame.LookVector` is local **−Z**, so the LookVector must point *outward* for +Z to face the hub |
| Spawning at the origin and falling | A leftover `SpawnLocation` in Workspace, or `CharacterAutoLoads` re-enabled |
| Two players on one plot | Something yields inside `claimPlot` — it must run start to finish in one resumption |
| Plots overlap | `PlotCount` raised without re-running the specs; the ring radius is derived and the spec checks separation |
| `No free plot` errors | Place `MaxPlayers` exceeds `ParkConfig.PlotCount` |

---

## Step 7 test

**1. Boot.** Play. New lines:

```
[SAD/S][AssetBuilder] Placeholders: 35 dino(s), 10 egg(s) built, 0 real asset(s) kept
  ok      [R7] 35 species models and the wild egg resolve
[SAD/S][NestService] Built hub and 4 zone(s) in N ms
[SAD/S][NestService] Built 48 nest(s) from 48 anchor(s), 122 egg(s) available
[SAD/S][NestService] Respawn ticking at 1 Hz
```

Rule 7 is no longer skipped — it now checks all 35 species models plus the
generic wild egg.

**2. Look at the world.** Walk out of your park toward the middle, then turn
around. Four coloured zones sit on an outer ring, each with a **150-stud glowing
gate** you can read from the plaza: JURASSIC PLAINS, ROCKY CANYON, SWAMP LANDS,
FROZEN VALLEY. Roads run from each gate back toward the park ring.

**3. Read a nest sign.** Walk into Jurassic Plains and find a nest — a sunken
bowl with three pale eggs and a sign post. The sign shows:

```
JURASSIC PLAINS · NEST 4
Guardian: Parasaurolophus        Risk: 💀
TITAN      1 IN 100,000,000
SECRET     1 IN 5,263,158
LEGENDARY  1 IN 500
```

Those odds are read from the same weight table you will actually be rolled
against. Walk to Frozen Valley and compare — Titan there is 1 in 2,000,000.

**4. Take an egg.** Hold `E` on one for 0.6 seconds. It disappears. Nothing else
happens yet — the rarity roll, the carry and the chase are Steps 8 and 9.

**5. It comes back.** Wait 45 seconds in Jurassic Plains and the egg respawns
with a working prompt. Frozen Valley takes 85.

**6. Distance is checked server-side.** From the **client** console, try to take
an egg from across the map:

```lua
local egg = workspace.SAD_Runtime.Nests:GetChildren()[1].Eggs:GetChildren()[1]
egg.Shell.StealPrompt:InputHoldBegin()
```

Standing far away, nothing happens. The prompt enforces range on the *client*,
which an exploiter simply removes; the server check in `ClaimEgg` is the copy
that matters.

**7. One egg, one claimant.** Server command bar:

```lua
local Nest = require(game.ServerScriptService.SAD_Server.Services.NestService)
local p = game.Players:GetPlayers()[1]
local nest = Nest.GetNestsInZone("plains")[1]
print(Nest.ClaimEgg(p, nest.Id, 1))   --> true  nil   (if you are standing near it)
print(Nest.ClaimEgg(p, nest.Id, 1))   --> false already taken
```

**8. Inspect the nests.**

```lua
local Nest = require(game.ServerScriptService.SAD_Server.Services.NestService)
print("eggs available:", Nest.CountAvailableEggs())
for _, n in Nest.GetNestsInZone("frozen") do
    print(n.Id, n.GuardianSpeciesId, "risk", n.Risk)
end
```

### What to watch for

| Symptom | Cause |
|---|---|
| `Egg_Wild is missing` | `AssetBuilder` not pasted, or Bootstrap not re-pasted |
| `R7` failures | A species model name that does not resolve — usually a hand-added species without a matching asset |
| Zones overlap the park ring | `ZoneConfig.RingRadius` lowered; the spec checks the clearance |
| Nests stacked on each other | `NestCount` raised past what the spiral can space |
| Eggs never respawn | The 1 Hz tick errored — check Output for `Respawn tick failed` |
| Tags missing on a hand-built zone | `SAD_NestAnchor` must be on the anchor parts themselves; duplicating a tagged model in Studio drops the tag |

---

## Step 8 test

**1. Boot.** Play. New lines:

```
[SAD/S][SecurityService] Movement plausibility at 4 Hz, tolerance 1.6x, correction on
[SAD/S][EggService] Ready. Loose eggs last 10s
[SAD/C][EggCarryController] Watching for carried eggs
```

**2. Steal an egg.** Walk into Jurassic Plains, hold `E` on one for 0.6 s.

- The egg appears **above your head**
- The carry panel shows its rarity in that rarity's colour, and the distance to
  your park
- Output logs the roll and your luck:
  `took a common egg from Nest_plains_04 (luck 0.00)`

**3. Feel the weight.** Common eggs cost nothing. To feel a heavy one, force a
rare roll from the server command bar:

```lua
local Egg = require(game.ServerScriptService.SAD_Server.Services.EggService)
local Nest = require(game.ServerScriptService.SAD_Server.Services.NestService)
local p = game.Players:GetPlayers()[1]

-- Stand next to a nest, then:
print(p.Character.Humanoid.WalkSpeed)          --> 20 before
Egg.TryPickup(p, Nest.GetNestsInZone("plains")[1].Id, 1)
print(p.Character.Humanoid.WalkSpeed)          --> lower, by rarity
print("penalty:", Egg.GetCarryPenalty(p))
```

A Titan egg leaves you at **11.0** studs/s against a base of 20 — the published
table in docs/03 §1.2, which `tests/step8_spec.lua` asserts line by line.

**4. Drop it, and watch anyone take it.** Press `Q`. The egg lands on the
ground with a *Grab Egg* prompt that **any** player can use, for 10 seconds,
after which it returns to its nest. With two clients, drop a rare egg in front
of the other player and let them take it.

**5. Capacity.** Try to take a second egg with a level-0 pouch:

```lua
print(Egg.TryPickup(p, Nest.GetNestsInZone("plains")[2].Id, 1))  --> false  hands full
```

Then raise it and try again:

```lua
local PDS = require(game.ServerScriptService.SAD_Server.Services.PlayerDataService)
PDS.UpdateKeys(p, { "Upgrades" }, function(d) d.Upgrades.eggPouch = 4 end, "test")
print(Egg.GetCapacity(p))   --> 5
```

Two eggs stack visually above your head, and the second costs only 40% of its
own weight.

**6. Luck actually moves the odds.**

```lua
PDS.UpdateKeys(p, { "Upgrades" }, function(d) d.Upgrades.eggSense = 15 end, "test")
print("luck:", Egg.ComputeLuck(p, "plains"))   --> 0.75

local counts = {}
for _ = 1, 20000 do
    local r = Egg.RollRarityIn("plains", 0.75)
    counts[r] = (counts[r] or 0) + 1
end
print("common:", counts.common, "epic:", counts.epic)
```

Compare against luck 0 — commons fall, epics roughly double.

**7. Leaving mid-carry costs you the egg.** Take an egg, then stop the client.
The server logs `Returned ...'s carried egg(s) to their nests` and the egg is
back in its nest. **It is not in your inventory on rejoin** — a carried egg is
never in the profile, so disconnecting cannot bank it.

**8. The movement guard.** In the **client** console:

```lua
game.Players.LocalPlayer.Character.Humanoid.WalkSpeed = 200
```

Run around. Within a second or two the server logs
`flagged: SuspiciousMovement`, drops anything you were carrying, and after five
flags snaps you back. It never kicks you — false positives happen on poor
connections, and disconnecting a child over network jitter is not an acceptable
trade.

### What to watch for

| Symptom | Cause |
|---|---|
| Holding a prompt does nothing | `NestService` not re-pasted — prompts now fire a signal that `EggService` listens for |
| Egg appears but speed does not change | `Humanoid` missing, or another script setting `WalkSpeed` after us |
| Egg stays after respawn | `EggService` not re-pasted; a carried egg is dropped on respawn by design |
| Constant `SuspiciousMovement` flags | Something moves characters without calling `SecurityService.Exempt` |
| `hands full` on the first egg | A stale token — check `Egg.GetCarryCount(p)` |

---

## Step 9 test

**1. Boot.** Play. New lines:

```
[SAD/S][WildAIService] Chase AI ready: decisions at 6 Hz, cap 20 guardians
[SAD/C][CameraController] Camera shake ready
```

**2. Get chased.** Take an egg in Jurassic Plains. A dinosaur spawns at the
nest and comes after you. The HUD strips to a red vignette and `RUN!
PARASAUROLOPHUS`, the camera shakes, and the vignette **pulses harder as it
closes**.

```
[SAD/S][WildAIService] YourName is being chased by a parasaurolophus in plains
                       (18.4 studs/s vs their 20.0)
```

Note the speed: it is a ratio of *your* speed at the moment you grabbed the egg.

**3. Escape.** Three ways, all real:
- Run to **your own park gate** → `reached safety`
- Leave the zone and stay out **8 seconds** → `lost them outside the zone`
- Get **250 studs from the nest** → `too far from the nest`
- Or just outlast it — most Zone 1 guardians give up

**4. Get caught.** Stand still. You trip over, go limp for 1.5 s, are winded
(−25 % speed) for 6 s, and **every egg you were carrying lands on the ground**
where anyone can take it for 10 seconds. Nothing is destroyed and nothing is
deducted.

**5. Feel the difficulty curve.** Unlock Frozen Valley and steal there:

```lua
local PDS = require(game.ServerScriptService.SAD_Server.Services.PlayerDataService)
local p = game.Players:GetPlayers()[1]
PDS.UpdateKeys(p, { "ZonesUnlocked" }, function(d) d.ZonesUnlocked.frozen = true end, "test")
```

Zone 4 guardians carry a **+0.12 speed bonus**. Running in a straight line is no
longer enough — 10 of 13 archetypes will run you down there, against 3 of 13 in
Jurassic Plains.

**6. Watch an ability.** Find a Pachycephalosaurus (charger) or Dilophosaurus
(spitter) nest. Seven seconds into the chase the guardian **winds up** — it
visibly slows, the camera jolts — and then charges at 1.8×. The wind-up is your
cue to turn sideways.

**7. The cap.**

```lua
local AI = require(game.ServerScriptService.SAD_Server.Services.WildAIService)
print("active chases:", AI.GetActiveCount())
```

At 20 concurrent chases a new steal recycles the longest-running one — whoever
has been running longest gets away.

**8. Guardians never enter parks.** Run into *another* player's park while
chased. The guardian stops at their gate. You are safe from it — and standing in
someone else's park.

### What to watch for

| Symptom | Cause |
|---|---|
| No guardian appears | `WildAIService` not pasted, or the nest has no `GuardianSpeciesId` |
| Guardian stands still | Its archetype cannot guard — `NestBuilder` not re-pasted |
| Guardian floats or sinks | Ground raycast hitting a runtime folder; check the filter in `Init` |
| Caught instantly | `LastAbilityAt` not seeded to `os.clock()` — abilities must wait one cooldown |
| Chase never ends | Check Output for the reason; every ending is logged |
| Camera does not shake | `CameraShake` setting off, or `CameraController` missing |

---

## Step 10 test

**1. Complete the loop.** Steal an egg in Jurassic Plains, escape, and walk back
through your own park gate. A green **SAFE!** banner appears and the egg is in
your inventory:

```
[SAD/S][EggService] YourName banked 1 egg(s)
```

```lua
local PDS = require(game.ServerScriptService.SAD_Server.Services.PlayerDataService)
local d = PDS.Get(game.Players:GetPlayers()[1])
for uid, egg in d.Eggs do print(uid, egg.Rarity, egg.Origin) end
print("stolen:", d.Stats.EggsStolen, "lost:", d.Stats.EggsLost)
```

**2. Someone else's gate does not count.** Walk through another player's gate
while carrying. The guardian stops at their wall — but nothing deposits, and the
egg is still above your head. You are now standing in someone else's park with
something worth taking.

**3. No double deposits.** Stand in your own gateway and walk back and forth
across the line. `EggsStolen` increases exactly once per egg — `ParkEntered`
fires once per transition, not once per sample.

**4. Storage refuses rather than destroys.**

```lua
local d = PDS.Get(game.Players:GetPlayers()[1])
for i = 1, 50 do d.Eggs["filler" .. i] = { Rarity = "common", Origin = "plains", AcquiredAt = 0 } end
```

Now steal an egg and walk home. You get a red *Egg storage full* alert, and the
egg **stays above your head** — nothing is destroyed. Clear the filler and walk
through the gate again to bank it.

**5. The escape/catch ratio.** This is the number that tells you whether the
chase is tuned. docs/14 targets a 62–75 % escape rate:

```lua
local d = PDS.Get(game.Players:GetPlayers()[1])
print(string.format("escaped %d, caught %d (%.0f%%)", d.Stats.ChasesEscaped, d.Stats.ChasesCaught,
    d.Stats.ChasesEscaped / math.max(1, d.Stats.ChasesEscaped + d.Stats.ChasesCaught) * 100))
```

**6. Feel the walk.** Time a run to a zone whose gate is on the far side of the
ring. It is long — deliberately. Zone teleports (Step 14) are what bring the
loop from ~86 seconds to ~23.

### What to watch for

| Symptom | Cause |
|---|---|
| No SAFE! banner | `HUDController`/`EggCarryController` not re-pasted |
| Egg deposits at any gate | `ownerUserId == player.UserId` check removed |
| `EggsStolen` climbing while loitering | `ParkEntered` firing per sample instead of per transition |
| Deposit silently loses an egg | Should be impossible — `TakeToken` and the profile write are one block |

---

## Step 11 test

**1. Boot.** Play. New lines:

```
[SAD/S][MutationService] Ready. Prime chance 1 in 2000, weather 'clear'
[SAD/S][DinosaurService] Ready. 35 species available
[SAD/S][IncubationService] Ready. Incubator pads are live
```

**2. The full loop, end to end.** Steal an egg, escape, run home through your
gate. **SAFE!** — and it auto-starts in an incubator. Walk to the glowing blue
pad: the prompt shows a live countdown (`30s` for a Common). When it reaches
zero the prompt becomes **HATCH!**

Hold it. A panel appears with three lines: the species, its tier and income, and
the odds.

**3. The timer is the tell.** Steal several eggs and look at the pads before
hatching any. A 3-minute countdown is a Rare; 20 minutes is a Legendary. You
know what you have before you know *what* you have — which is the point.

**4. Force a rare hatch** rather than waiting for one:

```lua
local Inc = require(game.ServerScriptService.SAD_Server.Services.IncubationService)
local PDS = require(game.ServerScriptService.SAD_Server.Services.PlayerDataService)
local p = game.Players:GetPlayers()[1]

PDS.Update(p, function(d)
    d.Eggs.testegg = { Rarity = "titan", Origin = "frozen", AcquiredAt = os.time() }
end, "test")
Inc.BeginIncubation(p, "testegg", 1)

-- Then skip the six-hour wait:
PDS.Update(p, function(d) d.Incubators[1].HatchAt = os.time() - 1 end, "test")
print(Inc.Claim(p, 1))
```

A server-wide takeover banner fires and the reveal shows `1 IN 2,000,000`.

**5. Offline timers.** Start a 3-minute Rare, then **stop the session**. Wait a
minute in real time, Play again. The countdown has moved on — timers use
`os.time()`, so an egg keeps cooking while you are away.

**6. Mutations.** Force a hundred hatches and count:

```lua
local Mut = require(game.ServerScriptService.SAD_Server.Services.MutationService)
local counts = {}
for _ = 1, 10000 do
    local m = Mut.RollIn(0, "clear")
    counts[m] = (counts[m] or 0) + 1
end
for id, n in counts do print(id, n) end
```

About 80 % `none`, 12 % `golden`. Then try a storm — `Mut.RollIn(0, "thunderstorm")`
takes electric from 1.5 % to roughly 28 %.

**7. Storage refuses rather than destroys.**

```lua
PDS.Update(p, function(d)
    for i = 1, 30 do
        d.Dinos["filler" .. i] = { SpeciesId = "compsognathus", Rarity = "common", Stars = 1, Placed = false }
    end
end, "test")
```

Now hatch a ready egg. You get *Dinosaur storage full*, and the egg **stays in
its incubator, still ready**. Nothing is lost.

**8. Inspect what you hatched.**

```lua
local Dino = require(game.ServerScriptService.SAD_Server.Services.DinosaurService)
local d = PDS.Get(p)
for uid, entry in d.Dinos do
    print(uid, Dino.DisplayNameOf(entry), entry.Rarity,
        string.format("%.1f F/s", Dino.IncomeOf(entry, d)), entry.Locked and "LOCKED" or "")
end
```

Legendary and above are **auto-locked on hatch** — that is the rule that stops
the "I misclicked and sold my Titan" support ticket.

### What to watch for

| Symptom | Cause |
|---|---|
| No prompt on the incubator pads | `IncubationService` not pasted, or the plot has no `Incubators` folder |
| Prompt says Incubate but nothing happens | No eggs in storage — bank one first |
| Countdown frozen | Timers use `os.time()`; a frozen one means the 1 Hz refresh errored |
| Hatch produces nothing | Dinosaur storage full — check Output for the alert |
| `attempt to call a nil value (Start)` | `BeginIncubation` is the public API; `Start(app)` belongs to Bootstrap |

---

## Step 12 test

**1. Boot.** Play. New lines:

```
[SAD/S][EconomyService] Ready. Bank is lazy; auto-collect unlocks at rebirth 2
[SAD/S][Boot] Loaded 11 service(s): ...
[SAD/C][Boot] Loaded 7 controller(s): ...
```

**2. The loop now pays.** Steal an egg, bank it, hatch it. The dinosaur
**places itself** on the first free tile — you should see it appear in your park
with a name tag over it, and a small `+2 F` floater start drifting up off it
every couple of seconds. Nothing was clicked to make that happen; that is
deliberate, so a new player's first hatch produces visible income before they
have found any menu.

**3. The totem is the only button.** Walk to the Collection Totem at the front
of your plot. Its prompt reads **Collect 47 F** when there is anything banked,
and **Place Dinosaur** when there is not and you have one in storage. Hold it —
Fossils jump in the top bar and the bank resets to zero.

**4. The bank is lazy, and that is testable.** In the command bar:

```lua
local Econ = require(game.ServerScriptService.SAD_Server.Services.EconomyService)
local p = game.Players:GetPlayers()[1]
print(Econ.GetBanked(p))   -- banked, rate, cap
task.wait(10)
print(Econ.GetBanked(p))   -- banked has grown by rate * 10
```

Nothing ticks between those two prints. The second number is computed from
`BankedAt`, not accumulated — which is why 30 players cost the same as 1.

**5. The cap is real.** Leave a park earning for longer than
`4h + 1h per rebirth` of accrual and the banked figure stops. Force it:

```lua
local PDS = require(game.ServerScriptService.SAD_Server.Services.PlayerDataService)
PDS.Update(p, function(d) d.BankedAt = os.time() - 86400 end, "test")
print(Econ.GetBanked(p))   -- banked == cap exactly, not a day's worth
```

**6. Offline income.** With a placed dinosaur, press **Stop**, wait two minutes
in real time, then **Play**. A summary panel appears: time away, the rate it was
earning at, the 60 % offline rate applied, and a Collect button. The figure must
match `rate × secondsAway × 0.60`, capped.

**7. Placement refuses cleanly.** Fill the grid:

```lua
PDS.Update(p, function(d)
    for i = 1, 40 do
        d.Dinos["filler" .. i] = { SpeciesId = "compsognathus", Rarity = "common", Stars = 1, Placed = false }
    end
end, "test")
local Dino = require(game.ServerScriptService.SAD_Server.Services.DinosaurService)
for _ = 1, 40 do print(Dino.PlaceBest(p)) end
```

Expect placements until the grid or the slot cap runs out, then a clean
`no room on the grid` / `no free slots` reason — never an overlap, never a dinosaur
rendered on top of another.

**8. Income matches on both sides.** The floaters are computed on the client
from the replicated profile using the *same* `Economy.IncomeOf` the server
banks with. Compare:

```lua
-- server
print(Econ.GetRate(p))
```
```lua
-- client console (F9)
local Econ = require(game.ReplicatedStorage.SAD_Shared.Modules.Economy)
local State = require(game.Players.LocalPlayer.PlayerScripts.SAD_Client.Controllers.StateController)
print(Econ.ParkIncomeRate(State.Get()))
```

These must print the same number. If they diverge, the client is reading a
field the replication allowlist withholds — that is a replication bug, not a
maths bug.

### What to watch for

| Symptom | Cause |
|---|---|
| Floaters but the bank never grows | `EconomyService.InvalidateRate` not firing on `DinoPlaced` — the cached rate is stale at 0 |
| Bank resets on rejoin | `BeforeSave` not folding the pending bank into `BankedFossils` |
| Dinosaurs overlap | `FindFreeFootprint` called with the wrong size, or `Placed`/`TileX` written without going through `Place` |
| Totem prompt does nothing | Nothing banked *and* nothing in storage — that is the correct no-op |
| Offline summary shows a huge number | Cap not applied; check `RebirthConfig` offline-cap track |
| Client and server rates differ | A replication allowlist gap, see test 8 |

---

## Running the offline specs

Syntax-checks every source file and runs **2,580 assertions** without Studio:

```bash
./tests/run.sh
```

Fetches the Luau CLI on first run.

| Spec | Covers |
|---|---|
| `tests/step1_spec.lua` | `Format`, `TableUtil`, `RNG`, `Signal`, `Trove` |
| `tests/step2_spec.lua` | `ProfileTemplate` drift, the migration chain and its failure modes, and the full migrate → reconcile → write-in-place load path against a realistic old save |
| `tests/step3_spec.lua` | Every content number against the design docs, the full zone × rarity coverage matrix, and 18 deliberately broken configs the validator must reject |
| `tests/step4_spec.lua` | The `Patch` round-trip property across 13 state transitions, depth limits, native key types, the replication allowlist against the real schema, and the settings schema |
| `tests/step5_spec.lua` | The 64px touch-target guarantee across 12 real device viewports, scale and breakpoint maths, and design-token ordering |
| `tests/step6_spec.lua` | Tile round trip for all 64 tiles, footprint bounds for every size at every anchor, plot ring non-overlap, and the plot depth budget |
| `tests/step7_spec.lua` | Zone ring clearance at the full 10-zone build-out, deterministic nest spacing, sign odds against the real weight tables, guardian selection and risk ratings |
| `tests/step8_spec.lua` | The published carry-speed table line by line, multi-carry stacking, Strong Back, luck composition and caps, rarity roll distributions, and the luck tail guard |
| `tests/step9_spec.lua` | Archetype table integrity, guardian eligibility, the escape guarantee, and a simulated straight-line chase for every archetype in Zone 1 and Zone 4 |
| `tests/step10_spec.lua` | Storage bounds, deposited-egg shape against the schema, travel distances, how often being chased home is reachable, and measured loop tempo |
| `tests/step11_spec.lua` | Mutation distributions against their published weights, Prime pairing rules and ceiling, weather modifiers, species-roll coverage for every zone × rarity, the master income formula, and the incubation ladder |
| `tests/step12_spec.lua` | Footprint occupancy under a packed grid, the banking formula against its own cap, offline earnings at every rebirth, slot caps, and the day-one income curve against docs/05 |

This is not a substitute for the in-Studio tests above. `Net`, `Log`, both
Bootstraps and everything ProfileStore-dependent need Roblox to exercise.
