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

## Running the offline specs

Verifies the pure module logic without Studio (83 assertions):

```bash
./tests/run.sh
```

Fetches the Luau CLI on first run. This is not a substitute for the in-Studio
test above — it covers `Format`, `TableUtil`, `RNG`, `Signal` and `Trove` only.
