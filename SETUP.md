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

## Running the offline specs

Syntax-checks every source file and runs **233 assertions** without Studio:

```bash
./tests/run.sh
```

Fetches the Luau CLI on first run.

| Spec | Covers |
|---|---|
| `tests/step1_spec.lua` | `Format`, `TableUtil`, `RNG`, `Signal`, `Trove` |
| `tests/step2_spec.lua` | `ProfileTemplate` drift, the migration chain and its failure modes, and the full migrate → reconcile → write-in-place load path against a realistic old save |

This is not a substitute for the in-Studio tests above. `Net`, `Log`, both
Bootstraps and everything ProfileStore-dependent need Roblox to exercise.
