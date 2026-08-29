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

## Running the offline specs

Syntax-checks every source file and runs **1,230 assertions** without Studio:

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

This is not a substitute for the in-Studio tests above. `Net`, `Log`, both
Bootstraps and everything ProfileStore-dependent need Roblox to exercise.
