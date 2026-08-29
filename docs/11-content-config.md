# 11 — Content Configuration Format

The point of this doc: **adding a dinosaur, mutation, zone, quest or event must
never require touching a system script.** Content is data. Systems read data.

## 1. `DinoConfig` — adding a dinosaur

```lua
--!strict
-- ReplicatedStorage/SAD_Shared/Config/DinoConfig
local DinoConfig = {}

DinoConfig.Species = {
    trex = {
        Id             = "trex",
        DisplayName    = "Tyrannosaurus Rex",
        Rarity         = "legendary",
        SpeciesFactor  = 1.30,
        Zones          = { "jungle", "ruins" },
        Size           = "4x4",
        VisualScale    = 1,
        ChaseArchetype = "apex",
        ModelName      = "Dino_Trex",
        EggModelName   = "Egg_Legendary",
        Anims = {
            Idle = "rbxassetid://0", Walk = "rbxassetid://0",
            Run  = "rbxassetid://0", Roar = "rbxassetid://0",
            Eat  = "rbxassetid://0", Sleep = "rbxassetid://0",
        },
        Sfx = { Roar = "rbxassetid://0", Step = "rbxassetid://0" },
        MutationsAllowed = "all",
        IndexOrder     = 46,
        Description    = "The king. Everyone stops what they're doing.",
    },
    -- ... 59 more
}

return DinoConfig
```

**To add a dinosaur:** append one table, drop `Dino_<Name>` into
`ReplicatedStorage/SAD_Shared/SAD_Assets/Dinos`, and add its id to the
appropriate `ZoneConfig` pool. Nothing else. `ConfigValidator` will fail the
boot loudly if the model, rarity or zone id doesn't resolve — which is exactly
what you want on a Tuesday when you're adding 12 dinosaurs at once.

## 2. `RarityConfig`

```lua
RarityConfig.Order = { "common","uncommon","rare","epic","legendary",
                       "mythic","ancient","secret","titan" }

RarityConfig.Tiers = {
    legendary = {
        Id = "legendary", DisplayName = "Legendary",
        Color = Color3.fromHex("FFB020"),
        BaseIncome = 500, SellFossils = 22000, SellDna = 120,
        IncubationSecs = 1200, CarryPenalty = 0.22,
        AnnounceKind = "toast",          -- nil | "toast" | "banner" | "takeover"
        CrossServer  = false,
        HatchSfx = "rbxassetid://0", EggAura = "Aura_Legendary",
        AutoLock = true,
        LuckPower = 0.55,
    },
    -- ...
}

RarityConfig.WeightTotal = 100000000
RarityConfig.ZoneWeights = {
    plains = { common=62000000, uncommon=27000000, rare=9000000, epic=1800000,
               legendary=190000, mythic=9500, ancient=480, secret=19, titan=1 },
    -- one entry per zone; ConfigValidator asserts each sums to WeightTotal
}
```

## 3. `MutationConfig`

```lua
MutationConfig.WeightTotal = 100000000
MutationConfig.PrimeChance  = 2000        -- 1 in N after a non-none roll
MutationConfig.MaxStack     = 2

MutationConfig.List = {
    void = {
        Id = "void", DisplayName = "Void",
        Weight = 50, Multiplier = 150,
        Color = Color3.fromHex("140A20"),
        Vfx = "Mut_Void", Sfx = "rbxassetid://0",
        MutPower = 0.50,
        AnnounceKind = "banner", CrossServer = true,
    },
    -- ...
}

MutationConfig.WeatherModifiers = {
    bloodmoon = { bloodmoon = 40, shadow = 20 },
    thunderstorm = { electric = 25 },
    -- [weatherId] = { [mutationId] = weightMultiplier }
}
MutationConfig.WeatherModifierCap = 40
```

## 4. `ZoneConfig`

```lua
ZoneConfig.Zones = {
    plains = {
        Id = "plains", DisplayName = "Jurassic Plains", Order = 1,
        Color = Color3.fromHex("7ED957"),
        Unlock = { Fossils = 0, Rebirths = 0, IndexPercent = 0, OwnRarity = nil },
        NestCount = 14, EggsPerNest = 3, RespawnSecs = 45,
        GuardiansPerNest = { min = 1, max = 1 },
        LuckBonus = 0.00,
        Hazards = {},                      -- e.g. { "mud", "ice", "lava" }
        SpeciesPool = { "compsognathus","microraptor", ... },
        WorldModel = "Zone01",
        Music = "rbxassetid://0", Ambience = "rbxassetid://0",
    },
}
```

Nest anchors live in the world model as parts tagged `SAD_NestAnchor` with
attributes `ZoneId` and `NestIndex`. `NestService` reads them with
`CollectionService` at boot — so a builder can move or add nests in Studio
without a code change.

## 5. `UpgradeConfig`

```lua
UpgradeConfig.Tracks = {
    feedingTrough = {
        Id = "feedingTrough", DisplayName = "Feeding Trough",
        Board = "park",                     -- park | explorer | defence
        MaxLevel = 20, BaseCost = 2000, Growth = 1.66,
        Currency = "Fossils",
        Effect = { Kind = "parkIncomeMult", PerLevel = 0.08, Base = 1.0 },
        Icon = "rbxassetid://0",
        Describe = function(level) return ("+%d%% park income"):format(level*8) end,
    },
}
```

`Effect.Kind` is read by `UpgradeService` into a computed `PlayerStats` table
that every other service queries. Adding a new upgrade means adding a track and
a matching `Kind` handler in one place (`UpgradeService.EffectHandlers`).

## 6. `EventConfig` and `WeatherConfig`

```lua
EventConfig.Events = {
    meteor = {
        Id = "meteor", DisplayName = "Meteor Impact",
        Weight = 160, DurationSecs = 180, CountdownSecs = 60,
        Handler = "MeteorImpact",           -- module name in EventService.Handlers
        Announce = "☄️ METEOR IMPACT IN 60 SECONDS!",
        MinPlayers = 2, NoRepeatWithin = 3,
    },
}
EventConfig.IntervalRange = { min = 720, max = 1080 }   -- seconds
```

Each event's behaviour is a module in
`ServerScriptService/SAD_Server/Services/EventService/Handlers/`, implementing
`Start(ctx)`, `Tick(ctx, dt)`, `Finish(ctx)`. Adding event #13 means adding one
config entry plus one handler module. No scheduler changes.

`WeatherConfig` follows the same shape with `Effects` describing stat deltas:

```lua
bloodmoon = {
    Id = "bloodmoon", DisplayName = "Blood Moon",
    Weight = 130, DurationSecs = 360,
    Effects = { GuardianSpeedMult = 1.10, StealRewardMult = 1.5 },
    Lighting = { Ambient = ..., ClockTime = 0, FogColor = ... },
    Announce = "🌑 BLOOD MOON — SHADOW MUTATIONS ×20",
}
```

## 7. `QuestConfig`

```lua
QuestConfig.Daily = {
    stealEggs5 = {
        Id = "stealEggs5", DisplayName = "Steal 5 wild eggs",
        Stat = "EggsStolen", Target = 5, Scope = "daily",
        Reward = { Fossils = 8000, Dna = 0, Items = {} },
        Weight = 100,
    },
}
```

Quests read from the same `Stats` counters the profile already tracks, with a
per-period baseline snapshot. That means **a new quest requires no new
tracking code** as long as it targets an existing stat — and adding a stat is a
one-line schema migration.

## 8. `ConfigValidator` (runs at boot, Studio and live)

Asserts, and refuses to start the game if any fails:

1. Every `RarityConfig.ZoneWeights[zone]` sums to `WeightTotal`.
2. `MutationConfig.List` weights sum to `WeightTotal`.
3. Every `DinoConfig.Species[*].Rarity` exists in `RarityConfig.Tiers`.
4. Every `DinoConfig.Species[*].Zones[*]` exists in `ZoneConfig.Zones`.
5. Every `ZoneConfig.Zones[*].SpeciesPool[*]` exists in `DinoConfig.Species`.
6. Every zone × rarity combination reachable by the weight table has at least
   one species available in that zone's pool. *(This is the bug that would
   otherwise ship: a Titan rolls in Zone 1 and there's nothing to hatch.)*
7. Every `ModelName` / `EggModelName` resolves in `SAD_Assets`.
8. Every `EventConfig.Events[*].Handler` module exists.
9. Every `UpgradeConfig` `Effect.Kind` has a handler.
10. Every `ProductConfig` id is a positive integer and unique.

In Studio it prints a full report; in production it fails the boot and logs to
`AnalyticsService` so we find out from telemetry rather than from players.
