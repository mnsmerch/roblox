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

## Step 13 — upgrades and the shop

| Studio object | Source file |
|---|---|
| `SAD_Shared/Modules/Stats` | `src/ReplicatedStorage/SAD_Shared/Modules/Stats.lua` *(new)* |
| `Services/UpgradeService` | `src/.../Services/UpgradeService/init.lua` *(new)* |
| `SAD_Client/Controllers/ShopController` | `src/.../Controllers/ShopController.lua` *(new)* |
| `SAD_Shared/Config/GameConfig` | *(re-paste — `LuckPerNode`)* |
| `SAD_Shared/Config/UpgradeConfig` | *(re-paste — `StoreFor`, `LevelIn`)* |
| `SAD_Shared/Config/RebirthConfig` | *(re-paste — rounded costs)* |
| `SAD_Shared/Config/ConfigValidator` | *(re-paste — rule 9 handler hook)* |
| `SAD_Shared/Modules/Economy` | *(re-paste — banking at `BankedRate`)* |
| `Services/DataService/ProfileTemplate` | *(re-paste — `BankedRate`)* |
| `Services/PlayerDataService/Replication` | *(re-paste — `BankedRate` withheld)* |
| `Services/EconomyService` | *(re-paste — `SettleBank`)* |
| `Services/DinosaurService` | *(re-paste — reads `Stats`)* |
| `Services/MutationService` | *(re-paste — reads `Stats`)* |
| `Services/IncubationService` | *(re-paste — reads `Stats`)* |
| `Services/EggService` | *(re-paste — reads `Stats`)* |
| `Services/NestService/WorldBuilder` | *(re-paste — the Bone Market)* |
| `Services/ParkService/PlotBuilder` | *(re-paste — the defence board)* |
| `SAD_Shared/Modules/Types` | *(re-paste — `BankedRate`)* |

`Stats` is a ModuleScript beside `Economy`. Install it **first** — six other
files require it, and each one errors at boot without it. `UpgradeService` is a
Folder containing a ModuleScript named `init`, the same shape as
`EconomyService`.

**This step re-pastes more files than any before it**, because `Stats` replaced
eleven scattered copies of the same `UpgradeConfig.EffectAt(...)` expression.
None of those services changed behaviour — they read the same number from one
place instead of computing it themselves.

---

## Step 14 — zones and teleports

| Studio object | Source file |
|---|---|
| `Services/NestService/ZoneService` | `src/.../Services/NestService/ZoneService.lua` *(new)* |
| `SAD_Client/Controllers/TeleportController` | `src/.../Controllers/TeleportController.lua` *(new)* |
| `SAD_Shared/Config/ZoneConfig` | *(re-paste — `UnlockCheck`)* |
| `SAD_Shared/Modules/Types` | *(re-paste — `Shrines`)* |
| `Services/DataService/ProfileTemplate` | *(re-paste — `Shrines`)* |
| `Services/PlayerDataService/Replication` | *(re-paste — `Shrines` replicated)* |
| `Services/NestService` | *(re-paste — forwards Init/Start)* |
| `Services/NestService/WorldBuilder` | *(re-paste — Obelisk, barriers, tags)* |

`ZoneService` is a **ModuleScript beside** `WorldBuilder` and `NestBuilder`
under `NestService`, not a service in its own right — `NestService` forwards
`Init` and `Start` to it, so it never appears in Bootstrap's roster. That is
what docs/13 §Step 14 specifies.

---

## Step 15 — player raiding

| Studio object | Source file |
|---|---|
| `Services/StealService` | `src/.../Services/StealService/init.lua` *(new)* |
| `SAD_Shared/Config/GameConfig` | *(re-paste — the raid and shield constants)* |
| `SAD_Shared/Modules/Stats` | *(re-paste — `SecurityLevel`, `RaidHoldSecs`)* |
| `SAD_Shared/Modules/Types` | *(re-paste — four raid fields)* |
| `Services/DataService/ProfileTemplate` | *(re-paste — four raid fields)* |
| `Services/PlayerDataService/Replication` | *(re-paste — all four withheld)* |
| `Services/ParkService` | *(re-paste — `DinoRendered`)* |
| `Services/DinosaurService` | *(re-paste — `params.Acquired`)* |
| `SAD_Client/Controllers/HUDController` | *(re-paste — `OnStealAlert`)* |
| `SAD_Client/Controllers/ParkController` | *(re-paste — hides own raid prompts)* |

`StealService` is a Folder containing a ModuleScript named `init`, the same
shape as `EconomyService` and `UpgradeService`. There is **no new controller** —
the raid banners live in `HUDController`, which already owns the flash banner
and the reveal panel, and the prompt-hiding lives in `ParkController`, which
already owns park-side visuals.

---

## Step 16 — notifications and announcements

| Studio object | Source file |
|---|---|
| `SAD_Shared/Config/NotificationConfig` | `src/ReplicatedStorage/SAD_Shared/Config/NotificationConfig.lua` *(new)* |
| `Services/NotificationService` | `src/.../Services/NotificationService/init.lua` *(new)* |
| `Services/BroadcastService` | `src/.../Services/BroadcastService/init.lua` *(new)* |
| `SAD_Client/Controllers/NotificationController` | `src/.../Controllers/NotificationController.lua` *(new)* |
| `SAD_Client/Controllers/SoundController` | `src/.../Controllers/SoundController.lua` *(new)* |
| `SAD_Shared/Modules/AssetBuilder` | *(re-paste — the `Sounds` folder)* |
| `Services/EconomyService` | *(re-paste — uses NotificationService)* |
| `Services/UpgradeService` | *(re-paste — uses NotificationService)* |
| `Services/IncubationService` | *(re-paste — cross-server hatch announcements)* |
| `Services/EggService` | *(re-paste — uses NotificationService)* |
| `Services/StealService` | *(re-paste — the raid alert)* |
| `Services/NestService/ZoneService` | *(re-paste — uses NotificationService)* |
| `SAD_Client/Controllers/EggCarryController` | *(re-paste — hands `Notify` over)* |

`NotificationService` and `BroadcastService` are Folders containing a
ModuleScript named `init`. Both are already in Bootstrap's roster at positions
6 and 7, so no edit there.

**This step removes a handler as well as adding one.** `EggCarryController` had
a placeholder `Net.On("Notify", …)` since Step 8; `NotificationController` now
owns that remote. Re-paste `EggCarryController` or you will get every
notification twice.

**Cross-server messaging needs API access.** Game Settings → Security → *Enable
Studio Access to API Services*. Without it the game runs normally and logs
`Cross-server announcements are OFF` — that is the designed degradation, not a
failure.

---

## Step 17 — weather

| Studio object | Source file |
|---|---|
| `SAD_Shared/Config/WeatherConfig` | `src/ReplicatedStorage/SAD_Shared/Config/WeatherConfig.lua` *(new)* |
| `Services/WeatherService` | `src/.../Services/WeatherService/init.lua` *(new)* |
| `SAD_Client/Controllers/WeatherController` | `src/.../Controllers/WeatherController.lua` *(new)* |
| `SAD_Shared/Config/ConfigValidator` | *(re-paste — rule 11)* |
| `Services/MutationService` | *(re-paste — the zone boost)* |
| `Services/IncubationService` | *(re-paste — passes the egg's origin zone)* |
| `Services/NestService` | *(re-paste — weather-scaled respawn)* |
| `SAD_Client/Bootstrap` | *(re-paste — `WeatherController` in the roster)* |

`WeatherService` is a Folder containing a ModuleScript named `init`, already in
Bootstrap's roster at position 21. `WeatherController` is **new to the client
roster** — re-paste `Bootstrap` (the LocalScript) or it will never load.

---

## Step 18 — server events

| Studio object | Source file |
|---|---|
| `SAD_Shared/Config/EventConfig` | `src/ReplicatedStorage/SAD_Shared/Config/EventConfig.lua` *(new)* |
| `Services/EventService` | `src/.../Services/EventService/init.lua` *(new)* |
| `Services/EventService/Handlers/MeteorImpact` | `src/.../Handlers/MeteorImpact.lua` *(new)* |
| `Services/EventService/Handlers/Stampede` | `src/.../Handlers/Stampede.lua` *(new)* |
| `Services/EventService/Handlers/NestFrenzy` | `src/.../Handlers/NestFrenzy.lua` *(new)* |
| `Services/EventService/Handlers/AmberRain` | `src/.../Handlers/AmberRain.lua` *(new)* |
| `SAD_Shared/Config/ConfigValidator` | *(re-paste — rules 8 and 11 both fixed)* |
| `SAD_Shared/Config/RarityConfig` | *(re-paste — `TierAbove`)* |
| `Services/EggService` | *(re-paste — `SpawnEventEgg`)* |
| `Services/MutationService` | *(re-paste — guaranteed mutations)* |
| `Services/IncubationService` | *(re-paste — carries the flag)* |
| `Services/NestService` | *(re-paste — `EventRespawnMultiplier`)* |
| `Services/WildAIService` | *(re-paste — `EventSpeedMultiplier`)* |
| `SAD_Client/Controllers/HUDController` | *(re-paste — banner priority)* |
| `SAD_Client/Controllers/WeatherController` | *(re-paste — banner priority)* |

`EventService` is a **Folder** containing a ModuleScript named `init` **and a
Folder named `Handlers`** holding the four handler ModuleScripts — the same
nesting as `DataService/Migrations`. The handler names must match
`EventConfig`'s `Handler` field exactly; rule 8 fails boot if they do not.

**Re-paste `ConfigValidator` even if nothing else.** Rule 11 was added in Step
17 but its function was never defined, so it has been a `nil` hole in the rule
list since — registered, never run, silent. That is fixed here along with the
guard that makes the same omission impossible to repeat.

---

## Step 19 — quests, dailies and the Index

| Studio object | Source file |
|---|---|
| `SAD_Shared/Modules/Time` | `src/ReplicatedStorage/SAD_Shared/Modules/Time.lua` *(new)* |
| `SAD_Shared/Config/QuestConfig` | `src/.../Config/QuestConfig.lua` *(new)* |
| `SAD_Shared/Config/DailyConfig` | `src/.../Config/DailyConfig.lua` *(new)* |
| `SAD_Shared/Config/IndexConfig` | `src/.../Config/IndexConfig.lua` *(new)* |
| `Services/QuestService` | `src/.../Services/QuestService/init.lua` *(new)* |
| `Services/QuestService/RewardGrant` | `src/.../QuestService/RewardGrant.lua` *(new)* |
| `Services/DailyService` | `src/.../Services/DailyService/init.lua` *(new)* |
| `Services/IndexService` | `src/.../Services/IndexService/init.lua` *(new)* |
| `SAD_Client/Controllers/QuestController` | `src/.../Controllers/QuestController.lua` *(new)* |
| `SAD_Client/Controllers/IndexController` | `src/.../Controllers/IndexController.lua` *(new)* |
| `SAD_Shared/Modules/Stats` | *(re-paste — bonus slots and boosts)* |
| `SAD_Shared/Modules/Types` | *(re-paste — three fields)* |
| `SAD_Shared/Config/ConfigValidator` | *(re-paste — two dead skip labels removed)* |
| `Services/DataService/ProfileTemplate` | *(re-paste — three fields)* |
| `Services/PlayerDataService/Replication` | *(re-paste — all three replicated)* |

`QuestService` is a **Folder** containing `init` **and** `RewardGrant`.
`DailyService` and `IndexService` reach `RewardGrant` through
`QuestService.RewardGrant` — the same shape `NestService.Zones` uses.

`Time` must be installed **before** `QuestService` and `DailyService`, and
`DailyConfig` before `Stats` (which now reads boost definitions from it).

---

## Step 20 — rebirth

| Studio object | Source file |
|---|---|
| `Services/RebirthService` | `src/.../Services/RebirthService/init.lua` *(new)* |
| `SAD_Client/Controllers/RebirthController` | `src/.../Controllers/RebirthController.lua` *(new)* |
| `SAD_Shared/Config/RebirthConfig` | *(re-paste — three lists, `Validate`, the shared preview)* |
| `Services/DataService` | *(re-paste — exposes `Template`)* |
| `SAD_Client/Controllers/HUDController` | *(re-paste — the ♻️ rail button)* |
| `SAD_Client/Controllers/InputController` | *(re-paste — R)* |
| `SAD_Client/Bootstrap` | *(re-paste — `RebirthController` in the roster)* |

**Re-paste `RebirthConfig` before anything else.** `Preserved` is no longer an
array of names — it is a keyed table of *reasons*, alongside two new tables
`Reset` and `Partial`, and `RebirthService` refuses to start unless the three
together cover every field in the profile exactly once.

`RebirthController` is **new to the client roster** — re-paste the client
`Bootstrap` or it will never load.

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

## Step 13 test

**1. Boot.** Play. New lines:

```
[SAD/S][UpgradeService] Ready. 14 tracks across 3 boards
[SAD/S][Boot] Loaded 12 service(s): ...
[SAD/C][ShopController] Ready. 14 tracks across 3 boards
[SAD/C][Boot] Loaded 8 controller(s): ...
```

The config report should also now show rule 9 checking handlers rather than
skipping them: `ok  [R9] 14 upgrade track(s) validated`.

**2. Three ways in.** Press **4**, or tap **SHOP** on the bottom bar, or walk to
one of the two Bone Market stalls in the hub — the stalls open the shop on
*their* tab. The defence board is mounted on your own park's gate wall.

**3. Buy something.** Grant yourself Fossils first:

```lua
local Econ = require(game.ServerScriptService.SAD_Server.Services.EconomyService)
local p = game.Players:GetPlayers()[1]
Econ.AddFossils(p, 500000, "test")
```

Each row reads `L3  x1.24 income  →  x1.32 income` with the price on the button.
Buy one: the level moves, the Fossil counter drops, a toast confirms it. The row
redraws from the profile, not from the response — so it is correct even if the
toast is missed.

**4. Buy Max never overspends.** The second button reads `BUY 4 · 12.4K` — how
many levels this balance covers, and the exact total. Press it: you get four
levels and 12.4 K leaves your wallet. Then check the boundary:

```lua
local Up = require(game.ServerScriptService.SAD_Server.Services.UpgradeService)
local PDS = require(game.ServerScriptService.SAD_Server.Services.PlayerDataService)
PDS.Update(p, function(d) d.Fossils = 799 end, "test")   -- one short of L1
print(Up.Buy(p, "dinoSlots", 26))                         -- 0, 0, not enough Fossils
print(PDS.Get(p).Fossils)                                 -- still 799, never negative
```

**5. Each effect actually applies.** docs/13's test for this step. Buy a level,
then read the stat back — the value must move, and must match what the shop row
previewed:

```lua
local Stats = require(game.ReplicatedStorage.SAD_Shared.Modules.Stats)
Econ.AddFossils(p, 1e9, "test")
for _, id in ipairs({"dinoSlots","incubators","feedingTrough","runnersLegs","eggPouch","eggSense"}) do
    Up.Buy(p, id, 3)
end
local s = Stats.Of(PDS.Get(p))
print(s.DinoSlots, s.Incubators, s.ParkIncomeMult, s.MoveSpeedMult, s.EggCapacity, s.Luck)
```

Runner's Legs is the visible one: your character speeds up the moment it is
bought, without a respawn.

**6. Defences go in the other table.** The defence board writes to `Defences`,
not `Upgrades`, and the stats read it from there:

```lua
Up.Buy(p, "fence", 3)
local d = PDS.Get(p)
print(d.Defences.fence, d.Upgrades.fence)          -- 3, nil
print(Stats.StealHoldBonus(d))                      -- 3.0
```

Then confirm the remotes police their own board — this is why there are two:

```lua
-- In the CLIENT console (F9), try to buy a defence through the upgrade remote:
local Net = require(game.ReplicatedStorage.SAD_Shared.Modules.Net)
Net.FireServer("RequestBuyUpgrade", "fence", 5)
```

Nothing happens, and the server logs `sent 'fence' to the upgrade remote`.

**7. An income upgrade must not pay backwards.** The important one. With a
placed dinosaur:

```lua
PDS.Update(p, function(d) d.BankedAt = os.time() - 300 end, "test")
print(Econ.GetBanked(p))          -- five minutes at the CURRENT rate
Up.Buy(p, "feedingTrough", 10)
print(Econ.GetBanked(p))          -- must NOT have jumped
```

The second figure must be essentially the first. If buying Feeding Trough
inflates the existing bank, `SettleBank` is not running before the level
changes — and store/re-place becomes a money printer.

**8. Levels survive a rejoin.** Buy several, press Stop, Play again. Levels and
Fossils are where you left them, and the shop redraws from the loaded profile.

### What to watch for

| Symptom | Cause |
|---|---|
| Shop opens empty | `Stats` not installed, so `ShopController` failed at require |
| A row shows `MAXED` at level 0 | `MaxLevel` misread — check the track in `UpgradeConfig` |
| Buy Max charges more than it showed | `CostRange` and `CostOf` disagreeing; both must sum *rounded* prices |
| Bought a Fence, nothing changed | Level written to `Upgrades`; it belongs in `Defences` |
| Bank jumps when buying Feeding Trough | `SettleBank` not called before the level write (test 7) |
| `Effect.Kind ... has no handler` at boot | A new track without a `Stats.KindToField` entry — that is rule 9 working |

---

## Step 14 test

**1. Boot.** Play. New lines:

```
[SAD/S][ZoneService] Ready. 4 shrine(s), 1 obelisk(s), 4 zone(s)
[SAD/C][TeleportController] Ready. 6 destination(s)
```

**2. A locked zone refuses the walk.** Walk to Rocky Canyon and step through
its gate. Within half a second you are back outside it with a toast:
`ROCKY CANYON IS LOCKED · 5K Fossils to open`. The shimmering barrier across
the gate is scenery — it does not stop you, the server does.

**3. Unlock it where you are standing.** The gate itself carries a prompt:
`Unlock · ROCKY CANYON · 5K Fossils`. Grant yourself the money first:

```lua
local Econ = require(game.ServerScriptService.SAD_Server.Services.EconomyService)
Econ.AddFossils(game.Players:GetPlayers()[1], 10000, "test")
```

Hold the prompt. A full-screen reveal fires, the barrier vanishes *for you*,
and you can walk in. Check the barrier is still up for a second player — it is
a per-client transparency, not a server change.

**4. Unlocking is not the same as discovering.** Open the wheel (**5**, the
**GO** button, or the Obelisk beside spawn). Rocky Canyon now says
`Walk there once to put it on your Obelisk` and cannot be selected. Walk to the
shrine in its far corner and hold the prompt: `+500` and the card lights up.
That is the beat that teaches the map before the game lets you skip it.

**5. Teleport.** Pick Rocky Canyon from the wheel. You arrive **outside** its
gate, not inside — so the walk through the gate is always the same walk.
Then tap **PARK** (or press **1**) and you are home instantly.

**6. Teleporting mid-chase is refused.** The important one. Steal an egg so a
guardian aggros, then tap PARK:

```
CANNOT TRAVEL · not while you are being chased
```

If that teleport succeeds, the chase system is bypassed and the game has no
risk in it at all. Escape first, and the same tap works.

**7. Teleports do not trip the movement detector.** docs/13 flags this for this
step. Teleport several times in a row across the map and watch Output: there
must be no `SuspiciousMovement` flags.

```lua
local Sec = require(game.ServerScriptService.SAD_Server.Services.SecurityService)
print(Sec.GetFlagCount(game.Players:GetPlayers()[1]))   -- 0
```

**8. A locked zone rejects the teleport too**, not just the walk:

```lua
local Nest = require(game.ServerScriptService.SAD_Server.Services.NestService)
local p = game.Players:GetPlayers()[1]
print(Nest.Zones.Teleport(p, "frozen"))     -- false, zone is locked
print(Nest.Zones.Teleport(p, "atlantis"))   -- false, no such destination
```

**9. Server-side is the only side.** From the **client** console (F9), try to
teleport into a zone you have not bought:

```lua
local Net = require(game.ReplicatedStorage.SAD_Shared.Modules.Net)
Net.FireServer("RequestTeleport", "frozen")
```

You do not move. The client sends a destination id and nothing else; every gate
is re-checked on the server.

### What to watch for

| Symptom | Cause |
|---|---|
| Pushed out of your own park | A zone square overlapping the park ring — `step14_spec` asserts 70 studs of clearance |
| Teleport lands you inside the zone | `DestinationCFrame` using local −Z; +Z faces the hub |
| Barrier still visible after unlocking | `TeleportController` not observing `ZonesUnlocked`, or `SAD_World` not found |
| Shrine gives the bonus twice | `Shrines[zoneId]` not checked before granting |
| `SuspiciousMovement` after every teleport | `SecurityService.Exempt` called after `PivotTo` instead of before |
| Wheel lists a zone you cannot use | Correct — locked and unvisited zones stay listed, showing what they need |

---

## Step 15 test

**Two clients, always.** In Studio: **Test → Clients and Servers → 2 players →
Start**. Nothing in this step can be verified with one.

**1. Boot.** Play. New line:

```
[SAD/S][StealService] Ready. Hold 3.0-9.0s, 600s same-victim cooldown
```

**2. Everyone starts shielded.** For the first 15 minutes of a session no raid
is possible — that is the point. Clear both shields to test:

```lua
local PDS = require(game.ServerScriptService.SAD_Server.Services.PlayerDataService)
for _, p in game.Players:GetPlayers() do
    PDS.Update(p, function(d)
        d.ShieldUntil = 0
        d.NewPlayerProtectionDone = true
    end, "test")
end
```

New Player Protection has to go too, or every fresh account is immune.

**3. The alert fires before anything is taken.** Walk Player 2 into Player 1's
park. Player 1 gets `PLAYER2 IS IN YOUR PARK!` on the flash banner. That warning
is the counterplay — a raid the victim cannot see coming is one they cannot
answer.

**4. Hold to lift.** Player 1 needs a placed dinosaur first (hatch one, or use
`DinosaurService.Create` + `PlaceBest`). Player 2 approaches it: the prompt reads
**Steal**, and holding it fills a ring for 3 seconds on an undefended park.
Player 1 sees `PLAYER2 IS TAKING YOUR ...`. On completion the dinosaur vanishes
from the enclosure, appears on Player 2's back, and a name tag reads
`PLAYER2 IS STEALING A ...` visible from anywhere.

Player 2 is now visibly slower and **cannot teleport**:

```
CANNOT TRAVEL · not while you are carrying a dinosaur
```

**5. Own-park prompts are hidden.** Player 1 should see **no** Steal prompt on
their own dinosaurs. Player 2 sees them. That is a client-side `Enabled`, so
check it on both screens.

**6. Reach your gate.** Player 2 walks home and crosses their own gate:
ownership transfers, the dinosaur auto-places in their park, Player 1 gets a
`ROBBED` panel with an insurance figure. Count the dinosaurs across both
profiles before and after — the total must be identical.

```lua
local function total()
    local n = 0
    for _, p in game.Players:GetPlayers() do
        for _ in PDS.Get(p).Dinos do n += 1 end
    end
    return n
end
print(total())
```

**7. Tagging returns it.** Repeat the raid, but have Player 1 touch Player 2
while they carry. Three seconds later the dinosaur flies home and Player 2 gets
`TAGGED!`. Try tagging from across the map — the server measures the distance
itself and refuses.

**8. Disconnecting loses nothing.** Raid again, then close Player 2's window
mid-carry. Player 1's dinosaur comes back. Then the harder case: raid, and have
**Player 1** leave mid-carry. The raid voids and the dinosaur returns with them
— an offline park cannot be robbed, so it cannot be robbed halfway either.

**9. The rules that make it fair.** Each of these should refuse with a reason:

```lua
local Steal = require(game.ServerScriptService.SAD_Server.Services.StealService)
local p1, p2 = table.unpack(game.Players:GetPlayers())

print(Steal.CanRaid(p2, p2.UserId))    -- that is your own park
print(Steal.CanRaid(p2, p1.UserId))    -- wait 90s   (straight after a raid)
Steal.GrantShield(p1, 600, "test")
print(Steal.CanRaid(p2, p1.UserId))    -- their park is shielded
```

**10. The Vault is absolute.** Vault a dinosaur and try to take it:

```lua
print(Steal.Vault(p1, "<uid>", 1))     -- true
```

Its Steal prompt refuses with *it is vaulted*, at any security level, forever.
Confirm it still earns — a vaulted dinosaur is protected, not benched.

**11. Defences buy time, they never block.** Give Player 1 the full defence
board and re-raid:

```lua
local Up = require(game.ServerScriptService.SAD_Server.Services.UpgradeService)
local Econ = require(game.ServerScriptService.SAD_Server.Services.EconomyService)
Econ.AddFossils(p1, 1e9, "test")
for _, id in ipairs({"fence","guardTower","camera"}) do Up.Buy(p1, id, 5) end
local Stats = require(game.ReplicatedStorage.SAD_Shared.Modules.Stats)
print(Stats.SecurityLevel(PDS.Get(p1)), Stats.RaidHoldSecs(PDS.Get(p1)))  -- 3.75, 7.5
```

The hold is now 7.5 s, and the Guard Tower auto-tags Player 2 within 40 studs
of the plot without Player 1 doing anything.

### What to watch for

| Symptom | Cause |
|---|---|
| Dinosaur count changes across a raid | The transfer is not atomic — removal must precede minting, with a rollback if storage is full |
| Owner can sell a dinosaur being carried | `IsLocked` not checked in that mutation path |
| Thief teleports home carrying | The `raid` blocker was not registered on `NestService.Zones` |
| Steal prompt on your own dinosaurs | `RaidOwnerUserId` attribute set after parenting, so the client missed it |
| Hold completes after leaving the park | `tickHolds` cancels on leaving; the client ring alone is not authoritative |
| Carry survives death | `CharacterRemoving` not connected for players already in the server at boot |
| Mercy Shield never fires | `RobbedAt` stamps pruned with an inclusive cutoff, or the window read as minutes |

---

## Step 16 test

**1. Boot.** Play. New lines:

```
[SAD/S][BroadcastService] Subscribed to 'SAD_Announce' as 1a2b3c4d. Budget 6/60s
[SAD/S][NotificationService] Ready. 4 severities, cross-server on
[SAD/C][SoundController] Ready, silent. Drop Sound instances named after the 12 slots ...
[SAD/C][NotificationController] Ready. 4 severities
```

`SoundController` reporting **silent** is correct — there are no audio files
yet, and no asset ids were invented to stand in for them.

**2. Each severity, on demand.** In the command bar:

```lua
local N = require(game.ServerScriptService.SAD_Server.Services.NotificationService)
local p = game.Players:GetPlayers()[1]

N.Toast(p, "Upgrade purchased", "Feeding Trough L4")
task.wait(1)
N.Banner(p, "MYTHIC HATCHED!")
task.wait(1)
N.Takeover(p, { Title = "NO WAY!", Subtitle = "You hatched a Titan", Headline = "1 IN 2,000,000" })
task.wait(1)
N.Alert(p, "SOMEONE IS STEALING YOUR ALPHA UTAHRAPTOR!")
```

Toast slides in top-right and leaves after 3 s. Banner is full-width for 5 s.
Takeover is the centre panel. The **alert stays up** — that is the severity's
whole definition. Clear it:

```lua
N.Clear(p, "alert")
```

**3. Toasts stack, oldest first out.** Fire five in a row; three are on screen
at any moment and the oldest is the one that goes.

```lua
for i = 1, 5 do N.Toast(p, "Toast " .. i) task.wait(0.2) end
```

**4. Takeovers queue, then drop.** docs/13's test for this step:

```lua
for i = 1, 5 do
    N.Takeover(p, { Title = "TAKEOVER " .. i, Headline = tostring(i) })
end
```

They play **one at a time**, in order, and only the first four ever appear —
one showing plus three queued. The fifth is dropped, not delayed. Check the
depth from the client console (F9) while they run:

```lua
local NC = require(game.Players.LocalPlayer.PlayerScripts.SAD_Client.Controllers.NotificationController)
print(NC.GetQueueDepth())    -- 3 during the burst, 0 once it drains
```

**5. Muting works, and cannot reach an alert.** Turn off other people's
announcements and confirm your own park alert still arrives:

```lua
local PDS = require(game.ServerScriptService.SAD_Server.Services.PlayerDataService)
PDS.Update(p, function(d) d.Settings.RareAnnouncements = false end, "test")
N.All({ Kind = "banner", Text = "SOMEONE ELSE HATCHED A MYTHIC" })   -- silent
N.Alert(p, "SOMEONE IS IN YOUR PARK!")                               -- still shows
```

**6. A malformed payload is dropped, not crashed.** These must all be no-ops
with no error in Output:

```lua
N.Send(p, "not a table")
N.Send(p, {})
N.Send(p, { Kind = "shout", Text = "unknown severity" })   -- renders as a toast
N.Send(p, { Text = "hi", Nested = { a = 1 }, Duration = 0/0 })
```

**7. Cross-server.** This is the one that needs a **published place**, not a
Studio session: a single Studio run is a single server, so a message published
there has nobody to arrive at. Publish, then open the game in two browser tabs
and hatch a Secret or Titan in one:

```lua
local Inc = require(game.ServerScriptService.SAD_Server.Services.IncubationService)
PDS.Update(p, function(d)
    d.Eggs.testegg = { Rarity = "titan", Origin = "frozen", AcquiredAt = os.time() }
end, "test")
Inc.BeginIncubation(p, "testegg", 1)
PDS.Update(p, function(d) d.Incubators[1].HatchAt = os.time() - 1 end, "test")
Inc.Claim(p, 1)
```

The other tab gets the same takeover. Check the counters on both servers:

```lua
local B = require(game.ServerScriptService.SAD_Server.Services.BroadcastService)
print(B.IsAvailable(), B.GetStats())   -- Published / Dropped / Received / Failed
```

**8. The budget refuses rather than throttling.** Publish more than six in a
minute and the rest are dropped locally, with a warning naming the budget:

```lua
for i = 1, 10 do B.Publish({ Kind = "banner", Text = "flood " .. i }) end
```

Output shows `Publish budget spent (6/60s) - dropping`. That is the design:
Roblox's own throttle drops silently, so the refusal happens here where it can
be counted.

**9. Sound is wired but silent.** Drop any `Sound` instance named `Hatch` into
`SAD_Shared/SAD_Assets/Sounds` and hatch something — it plays. The boot line
changes to `Ready. 1 of 12 slots have audio`. Nothing else in the game changes.

### What to watch for

| Symptom | Cause |
|---|---|
| Every notification appears twice | `EggCarryController` still has its Step 8 `Net.On("Notify")` |
| Takeovers overlap | `pumpTakeovers` re-entered — only one may be busy at a time |
| Alert never goes away | Nothing called `Clear` with the same `Tag`; raids clear on every exit path |
| `Cross-server announcements are OFF` | API services disabled — expected in a default Studio session |
| Cross-server works but the sender sees it twice | The `From` stamp is not being compared against `game.JobId` |
| Nothing plays on any action | Correct until `SAD_Assets/Sounds` has files in it |

---

## Step 17 test

**1. Boot.** Play. New lines:

```
[SAD/S][WeatherService] Ready. 4 weathers, rolling every 8m 0s, Clear 60% of the time
[SAD/S][WeatherService] Clear for 8m 0s
[SAD/C][WeatherController] Ready. Lighting is local; 4 looks
```

Sixty percent, not the 45 % docs/04 §2 prints — that 45 % is exact across all
eleven weathers, and V1 ships four. See the note now in docs/04 §2.

**2. Force each weather.** docs/13's test for this step:

```lua
local W = require(game.ServerScriptService.SAD_Server.Services.WeatherService)
W.Set("rainstorm", 60)
```

The sky greys and the fog closes to 900 studs over three seconds, the event
banner reads `RAINSTORM · 1m 0s` and counts down, and **you move visibly
slower**. Then `W.Set("blizzard", 60)` — everything goes white and the fog
closes to 260. Then `W.Set("clear")`.

**3. Lighting restores.** The one docs/13 names as this step's hazard. After
cycling every weather and returning to Clear, `Lighting` must be exactly what
it was at boot:

```lua
-- Before touching anything, in the CLIENT console (F9):
print(game.Lighting.Ambient, game.Lighting.Brightness, game.Lighting.FogEnd)
-- ...cycle all four weathers, end on clear, wait 3 s for the tween...
print(game.Lighting.Ambient, game.Lighting.Brightness, game.Lighting.FogEnd)
```

Identical. Lighting is captured once at boot and written only on the client,
which is why: a server that dies mid-blizzard leaves everyone in fog until it
restarts, and a client that does the same fixes itself on rejoin.

**4. The mutation shift is measurable.** 10,000 rolls per weather:

```lua
local Mut = require(game.ServerScriptService.SAD_Server.Services.MutationService)
local function count(weather, zone)
    local seen = {}
    for _ = 1, 10000 do
        local m = Mut.RollIn(0, weather, nil, zone)
        seen[m] = (seen[m] or 0) + 1
    end
    return seen
end
print("clear electric:", count("clear").electric)              -- ~150
print("storm electric:", count("thunderstorm").electric)       -- ~2,800
print("blizzard frozen:", count("blizzard").frozen)            -- ~3,400
print("valley frozen:",  count("blizzard", "frozen").frozen)   -- ~4,500
```

That last pair is the **×40 cap doing its job**: Blizzard is Frozen ×25 and the
Frozen Valley doubles it to ×50, which the cap trims to ×40. Uncapped the last
number would be near 5,500.

**5. Rainstorm speeds nest respawns.** Take an egg from a nest, note how long
the bowl stays empty in Clear, then repeat during a Rainstorm — 25 % shorter.
The multiplier is read when the timer is *set*, so weather ending mid-timer
never lengthens an egg already on its way back.

**6. Lightning knocks eggs loose.** Carry an egg through a Thunderstorm. Every
12 seconds there is a 10 % chance you drop everything, with a banner. Standing
empty-handed in a storm is never punished — being struck with nothing to lose
teaches nothing.

**7. The countdown lands before the weather does.** Set a short one and watch:

```lua
W.Set("clear", 25)   -- the next roll is 20 s after this ends
```

A `... IN 20s` banner fires, and only then does the sky change. The point of a
countdown is that people can move before it arrives.

**8. Weather survives a join.** With a Blizzard running, have a second player
join. They get the blizzard sky immediately, not the next roll — otherwise
most of a session is spent looking at whatever `Lighting` shipped with.

**9. Boot validation.** The config report should now include:

```
ok  [R11] 4 weather(s) validated against their mutation modifiers
```

Add a weather to `WeatherConfig` without one in `MutationConfig.WeatherModifiers`
and boot fails naming it. That pairing is the only reason two tables describing
one thing is safe here.

### What to watch for

| Symptom | Cause |
|---|---|
| Fog never clears | `WeatherController` writing keys it did not capture in `baseline` |
| Sky is right but nothing feels different | Effects applied client-side; they are server truth |
| Rain slow does not stack with a carried egg | Weather setting `WalkSpeed` directly instead of using the modifier stack |
| Nest respawn unchanged in rain | `NestService.RespawnMultiplier` resolved in `Init`, before `WeatherService` loads |
| Two exotics back to back | The forced 3-minute Clear gap is not being applied |
| Blizzard is no worse in Frozen Valley | The egg's `Origin` zone is not reaching `MutationService.Roll` |
| Fog still on with LowGraphics | The `Settings.LowGraphics` observer is not re-applying the look |

---

## Step 18 test

**1. Boot.** Play. New lines, and one changed one:

```
[SAD/S][EventService] Ready. 4 event(s), every 12m 0s-18m 0s
ok  [R8] all event handlers resolve
ok  [R11] 4 weather(s) validated against their mutation modifiers
```

`R11` appearing at all is the fix — it was registered in Step 17 and never ran.
If either line is missing, the handlers folder or the config is not where the
validator looks.

**2. Force each event.** The scheduler waits 12–18 minutes, so drive it
directly:

```lua
local E = require(game.ServerScriptService.SAD_Server.Services.EventService)
print(E.Begin("nestFrenzy"))
```

`Begin`, not `Start` — `Start(app)` belongs to Bootstrap's lifecycle, the same
collision `IncubationService` hit in Step 11.

- **Nest Frenzy** — take an egg and watch the bowl refill in about three
  seconds; guardians visibly lag. Then `E.Stop()` and confirm both go back:

  ```lua
  local Nest = require(game.ServerScriptService.SAD_Server.Services.NestService)
  local AI = require(game.ServerScriptService.SAD_Server.Services.WildAIService)
  print(Nest.EventRespawnMultiplier, AI.EventSpeedMultiplier)   -- 1, 1
  ```

  A multiplier left behind is a permanently trivial game and nothing throws.

- **Meteor Impact** — a dark disc grows on a random zone for 15 seconds, then
  a crater and eight eggs. Grab one: it is an ordinary loose egg from that
  moment, with the same prompt, carry and deposit. Hatch it — it is
  **guaranteed** to be mutated.

- **Dinosaur Stampede** — a marked lane from the hub to a zone, forty runners
  streaming along it. Hold the prompt on one: you get a dinosaur, it places
  itself, and the second attempt says *You have already captured one*.

- **Amber Rain** — chunks fall over the hub for two minutes. Walk into one for
  Fossils and DNA. Uncollected amber sinks into the ground rather than piling
  up.

**3. Nothing overlaps.** While one runs, a second must refuse:

```lua
E.Begin("nestFrenzy")
print(E.Begin("amberRain"))   -- false, an event is already running
```

**4. The scoreboard, and the floor.** Let an event finish. Everyone who scored
gets a takeover with the top five and their own place and reward. Then check
the guarantee docs/04 §3.1 makes:

```lua
-- Score once, from a fresh account with no park at all.
E.Begin("amberRain")
E.Score(game.Players:GetPlayers()[1], 1)
E.Stop("finished")
```

That player must still be paid — 500 Fossils, the flat floor. Three minutes of
zero income is zero, and they are exactly who the guarantee exists for.

**5. Rewards cannot be collected twice.** docs/13's hazard. Score, then leave
and rejoin mid-event, then let it end:

```lua
print(E.GetScores())   -- your old score is gone; participation is per-session
```

The rejoined player has no score and collects nothing for what the previous
session did. Rewards are read and cleared in one step, so a second payout sees
an empty table.

**6. An empty server ends the event.** The other hazard. Start an event, close
every client, and watch Output:

```
[SAD/S][EventService] Nest Frenzy ended (empty), 0 participant(s)
```

No scoreboard, no payout, and the geometry is gone — an event running its
meteor into an empty world is pure cost.

**7. A player joining mid-event sees it.** With an event running, have a second
client join. They get the current `EventState` immediately, not at the next
event.

**8. Teardown is complete.** After any event ends:

```lua
print(workspace.SAD_Runtime.Events:GetChildren())   -- {}
```

Empty. The handler's `Stop` and the Trove both run — the Trove is what
guarantees it, because a handler that errors halfway through its own teardown
must not leave a meteor in the sky.

**9. A missing handler fails boot.** Rename `Handlers/Stampede` and Play:

```
[SAD/S] ERROR  [R8] event 'stampede' names handler 'Stampede', which does not exist
```

Rename it back.

### What to watch for

| Symptom | Cause |
|---|---|
| An event never fires on its own | The scheduler waits 12–18 minutes; use `Begin` to test |
| Guardians stay slow after Nest Frenzy | `Stop` not restoring, or restoring to 1 instead of the previous value |
| Two events at once | Something calling `Begin` directly while one runs; the scheduler itself waits |
| Rewards paid twice | Scores read without being cleared in the same step |
| Meteor eggs vanish at event end | Correct — they are loose eggs on `EggService`'s own timer, not the event's |
| `R11` missing from the boot report | `ConfigValidator` not re-pasted, or `WeatherConfig` not passed to it |
| Amber never spawns | `Tick` not being called — the handler must return a table with `Start` **and** `Stop` |

---

## Step 19 test

**1. Boot.** Play. New lines:

```
[SAD/S][IndexService] Ready. 35 species to discover, 6 milestone(s)
[SAD/S][QuestService] Ready. 12 daily, 6 weekly, 15 metrics
[SAD/S][DailyService] Ready. 7-day cycle, 5 streak milestone(s)
[SAD/C][QuestController] Ready. 12 daily, 6 weekly in the pools
[SAD/C][IndexController] Ready. 35 species across 4 pages
```

`15 metrics` is the check that matters: `QuestService` **asserts** at boot that
the metrics quests name and the emitters that feed them are the same set. Add a
quest with a metric nothing emits and the server refuses to start.

**2. Three screens.** Left rail: 🎁 Daily, ✅ Quests, 📖 Index.

- **Quests** — three dailies and three weeklies with live progress bars.
- **Daily** — seven rows, the next one claimable, the rest done or locked,
  with a countdown to the next UTC midnight.
- **Index** — one page per zone, undiscovered species as `???` with their
  rarity and odds still shown.

**3. Progress is automatic.** Steal an egg and watch `Steal 5 wild eggs` move.
Collect income and watch `Collect income 5 times`. Nothing is polled — each
metric is one signal connection.

**4. Claim once, and only once.** docs/13's hazard:

```lua
local Q = require(game.ServerScriptService.SAD_Server.Services.QuestService)
local p = game.Players:GetPlayers()[1]
Q.Bump(p, "incomeCollected", 99)
print(Q.Claim(p, "collect5"))   -- true
print(Q.Claim(p, "collect5"))   -- false, already claimed
```

Fossils move exactly once. The claim is marked **before** the grant, which is
the whole defence: two calls racing both read an unclaimed state, but only the
first write survives to reach the reward.

**5. Cross a UTC day boundary.** docs/13's other hazard, and the one that needs
faking time:

```lua
local PDS = require(game.ServerScriptService.SAD_Server.Services.PlayerDataService)
local D = require(game.ServerScriptService.SAD_Server.Services.DailyService)
local Time = require(game.ReplicatedStorage.SAD_Shared.Modules.Time)

print(D.Claim(p))                      -- true, day 1
print(D.Claim(p))                      -- false, come back tomorrow

-- Pretend it is tomorrow by passing the time in rather than waiting.
local tomorrow = os.time() + 86400
print(D.Claim(p, tomorrow))            -- true, day 2, streak 2
print(PDS.Get(p).Daily.Streak)         -- 2
```

**6. Break a streak and rebuild it.**

```lua
local later = os.time() + 86400 * 3    -- skipped a day
print(D.Claim(p, later))               -- true
local d = PDS.Get(p).Daily
print(d.Streak, d.DayIndex, d.BestStreak)   -- 1, 1, 2
```

The cycle restarts at day 1 and the streak at 1, but **BestStreak does not
move** — docs/05 §7's "resets on a missed day; streak bonus persists".

**7. Discover a species.** Hatch anything you have not hatched before. A
takeover fires: `NEW SPECIES · Dryosaurus · 4 / 35`. Reach ten and an Index
milestone pays out on top.

```lua
local Idx = require(game.ServerScriptService.SAD_Server.Services.IndexService)
print(Idx.Discovered(PDS.Get(p)), Idx.Total(), Idx.Completion(PDS.Get(p)))
```

**Total is 35, not 60.** A player who finds every species in V1 reads 100 %.

**8. Rewards are one function.** Grant one by hand and watch every field land:

```lua
local RG = require(game.ServerScriptService.SAD_Server.Services.QuestService).RewardGrant
print(RG.Give(p, { Fossils = 1000, Dna = 25, Egg = "rare",
    Boost = { Id = "luckPotion", Secs = 900 }, LuckNodes = 1 }, "test"))
```

Then confirm the boost is *real*, not decorative:

```lua
local Stats = require(game.ReplicatedStorage.SAD_Shared.Modules.Stats)
print(Stats.Luck(PDS.Get(p)))                        -- includes +1.0
print(Stats.Luck(PDS.Get(p), os.time() + 1000))      -- expired, back down
```

**9. Fossils scale with rebirths, DNA does not.** docs/05 §7:

```lua
PDS.Update(p, function(d) d.Rebirths = 10 end, "test")
print(RG.Give(p, { Fossils = 1000, Dna = 25 }, "test"))  -- 10,000 Fossils, 25 DNA
```

### What to watch for

| Symptom | Cause |
|---|---|
| Server refuses to boot naming a metric | A quest names a metric nothing emits — that is `ValidateEmitters` working |
| A streak breaks on a double-claim | "same day" being treated as a break; `Time.StreakState` names three cases, not two |
| The day rolls at the wrong hour | Something using `os.date` or a duration instead of `Time.DayIndex` |
| Quests reshuffle on a server hop | The roll must be seeded on `(userId, day)`, never randomly |
| A claimed quest can be claimed again | The claim marked *after* the grant instead of before |
| Index reads 58 % when everything is found | A hardcoded denominator of 60 instead of `IndexConfig.Total` |
| A Luck Potion does nothing | `DailyConfig` not installed before `Stats`, so boost definitions do not resolve |

---

## Step 20 test

**1. Boot.** Play. New lines:

```
[SAD/S][RebirthService] Ready. Rebirth 1 costs 250K and 3 dinosaur(s)
[SAD/C][RebirthController] Ready. Rebirth 1 costs 250K
```

If the server refuses to start naming a profile field, that is the coverage
assertion working — every field must be classified as Preserved, Reset or
Partial before a rebirth is allowed to touch the profile.

**2. The confirm screen.** ♻️ on the left rail, or **R**. Three columns: what
you keep, what you lose, what you gain. The button greys and says *what* is
short — `NEED 180K MORE` or `NEED 2 MORE DINOSAURS`.

Every number on it comes from `RebirthConfig.Preview`, the same function the
reset uses. That matters here more than anywhere else in the game: it is the
one screen where a player deletes their park on the strength of what it says.

**3. Rebirth at exactly the threshold.** docs/13's test:

```lua
local PDS = require(game.ServerScriptService.SAD_Server.Services.PlayerDataService)
local RB = require(game.ServerScriptService.SAD_Server.Services.RebirthService)
local p = game.Players:GetPlayers()[1]

PDS.Update(p, function(d) d.Fossils = 249999 end, "test")
print(RB.CanRebirth(p))    -- false, 250K Fossils
PDS.Update(p, function(d) d.Fossils = 250000 end, "test")
print(RB.CanRebirth(p))    -- true (with 3 dinosaurs)
```

**4. Vaulted dinosaurs and the Index survive.** The heart of it:

```lua
local Steal = require(game.ServerScriptService.SAD_Server.Services.StealService)
Steal.Vault(p, "<uid>", 1)

local before = PDS.Get(p)
local index, dna = 0, before.DNA
for _ in before.Index do index += 1 end

print(RB.Perform(p))

local after = PDS.Get(p)
print(after.Rebirths, after.Fossils)          -- 1, 0
print(after.Dinos)                             -- only the vaulted one
local n = 0 for _ in after.Index do n += 1 end
print(n == index, after.DNA == dna)             -- true, true
```

**5. The anti-abuse fields survive too.** The four that were unclassified
until this step — without them, a rebirth clears a same-victim cooldown:

```lua
PDS.Update(p, function(d) d.StealCooldowns["999"] = os.time() + 600 end, "test")
-- ...rebirth...
print(PDS.Get(p).StealCooldowns["999"])   -- still there
```

**6. The multiplier applies.** docs/13's test:

```lua
local Stats = require(game.ReplicatedStorage.SAD_Shared.Modules.Stats)
local Econ = require(game.ReplicatedStorage.SAD_Shared.Modules.Economy)
local d = PDS.Get(p)
print(Econ.IncomeOf(next(d.Dinos) and d.Dinos[next(d.Dinos)], d))
-- 15% higher than the same dinosaur at rebirth 0
```

**7. A mid-carry rebirth is rejected.** The other docs/13 test. Pick up a wild
egg, then:

```lua
print(RB.CanRebirth(p))   -- false, not carrying anything
```

Same with a stolen dinosaur on your back. Both would be destroyed by the reset
with no record of them anywhere.

**8. The Rebirth Cache.** After the reset, check storage:

```lua
for uid, egg in PDS.Get(p).Eggs do print(uid, egg.Rarity, egg.Origin) end
```

One egg, `Origin = "rebirth"`, one tier below the best rarity you have **ever**
hatched (floor Rare) — read from `Stats.RarestRarity`, which is Preserved, so
it scales with a career rather than the run just deleted.

**9. Zones re-lock.** In V1 no zone is rebirth-gated, so a rebirth returns you
to the free zone and Canyon/Swamp/Frozen must be re-bought — 450 K on top of
the 250 K rebirth. That is docs/05 §6's own rule; it stops applying the moment
Zone 5 ships, because from then on the floor rises with the rebirth count.

**10. One write.** Watch Output during a rebirth: exactly one profile write for
the transaction itself, then an immediate save. There is no moment at which the
Fossils are gone and the multiplier has not arrived.

### What to watch for

| Symptom | Cause |
|---|---|
| Server refuses to boot naming a profile field | The coverage assertion working — classify it in `RebirthConfig` |
| A cooldown or streak resets on rebirth | That field is in `Reset` and should be in `Preserved` |
| A vaulted dinosaur is lost | `BonusVaultSlots` not counted, or `Dinos` treated as fully Reset |
| The preview promises more than the reset keeps | Something computing the preview separately instead of calling `RebirthConfig.Preview` |
| A rebirth is lost to a crash seconds later | `PlayerDataService.Save` not called immediately after |
| Rebirth succeeds while carrying | `EggService.GetCarryCount` / `StealService.IsCarrying` not checked |

---

## Running the offline specs

Syntax-checks every source file and runs **3,552 assertions** without Studio:

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
| `tests/step13_spec.lua` | Every price against integrality and monotonicity, all 14 published max effects, `Stats` block-vs-helper agreement, the Upgrades/Defences split in both directions, Buy Max bounds, the retroactive-income guard, and docs/05 §5's 180-second constraint across a rebirth run |
| `tests/step14_spec.lua` | Every unlock gate against docs/02 §2.1, all four gate kinds driven through an injected zone, teleport destinations proven to land outside their zone, zone-vs-park-ring clearance, the re-measured loop tempo, and the Day-1-reaches-Zone-4 claim |
| `tests/step15_spec.lua` | The hold formula against docs/03 §4.2 including V1's real ceiling, shield stacking proven un-permanent, record pruning under 500 entries, the stealable rules, the power floor in both directions, the transfer's conservation property, vault slots, and every raid cooldown |
| `tests/step16_spec.lua` | All four severities against docs/08 §5, a strict priority order, the takeover queue proven to drop rather than grow, unknown kinds falling back downward, payload sanitising against nesting/NaN/long keys and idempotence, and the `MessagingService` budget against both docs/09 §7.7 and Roblox's own floor |
| `tests/step17_spec.lua` | The published weather table, the Clear share for V1 *and* the full eleven, the roll distribution over 20,000 picks, the mutation shift over 20,000 hatches per weather, the ×40 cap proven to trim the one V1 interaction that reaches it, and Prime's chance proven flat while its count rises |
| `tests/step18_spec.lua` | The published event table, the clamped no-repeat rule simulated over 2,000 rolls, the participation-reward floor for an earning player and a broke one, double-collection modelled as the statement order it depends on, every ConfigValidator rule asserted to actually report, rules 8 and 11 each driven to a failure, and `TierAbove` against the zone weights the crater reads |
| `tests/step19_spec.lua` | UTC day and week boundaries against real calendar dates, every day of a week walked, streaks through a 40-day run and a break, the published 7-day chest with its rebirth scaling, quest id uniqueness across both pools, the seeded roll's determinism and reachability, double-claim modelled as the statement order it depends on, and the Index denominator proven to be what exists rather than what is planned |
| `tests/step20_spec.lua` | The three classification lists proven to cover the schema exactly once and driven to a failure in each of their three ways, docs/05 §6's keep/lose/gain lists by name, the cost curve and every capped grant, the Rebirth Cache against both readings of a contradictory doc, which zones survive with and without a rebirth-gated zone in the world, vault survival under a binding slot count, and the preview reconciled against what the player actually owns |

This is not a substitute for the in-Studio tests above. `Net`, `Log`, both
Bootstraps and everything ProfileStore-dependent need Roblox to exercise.
