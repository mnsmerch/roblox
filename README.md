# STEAL A DINOSAUR

A Roblox collection / stealing / passive-income game.

> **Status:** Steps 1–10 of 24 complete. Steal an egg, survive the chase, keep it. See [PROGRESS.md](PROGRESS.md) for what exists,
> [QUICKSTART.md](QUICKSTART.md) to run it, and [SETUP.md](SETUP.md) for the
> per-step Studio detail.

## The 8-second pitch

You own a Dinosaur Park. Dinosaurs in your park print money. You don't buy
dinosaurs — you **steal their eggs from wild nests** while a very angry mother
dinosaur chases you home. Then other players try to steal your dinosaurs.

## Try it

**[QUICKSTART.md](QUICKSTART.md)** — three ways to run it, from a 30-second
offline test to a full Studio setup.

```bash
./tests/run.sh    # 2,225 assertions, no Studio needed
```

## Repository layout

```
src/      Luau source, mirroring the Roblox Studio tree exactly
tests/    Offline specs — ./tests/run.sh (no Studio needed)
docs/     The design blueprint (below)
SETUP.md      Per-step Studio placement and test lists
QUICKSTART.md How to get it running at all
```

## Documentation index

| Doc | Contents |
|---|---|
| [00-overview.md](docs/00-overview.md) | Pillars, core loop, FTUE, session & retention design |
| [01-dinosaurs.md](docs/01-dinosaurs.md) | Rarity system, full 60-dinosaur roster, stats |
| [02-zones-and-map.md](docs/02-zones-and-map.md) | Map layout, 10 zones, unlock gating |
| [03-stealing.md](docs/03-stealing.md) | Wild egg theft, chase AI, player raiding, protection |
| [04-mutations-weather-events.md](docs/04-mutations-weather-events.md) | Mutation table, 10 weathers, 12 server events |
| [05-economy.md](docs/05-economy.md) | The full math model with real starting numbers |
| [06-progression.md](docs/06-progression.md) | Upgrades, rebirth, index, quests, dailies, fusion |
| [07-monetization.md](docs/07-monetization.md) | Gamepasses, dev products, Robux prices, ethics rules |
| [08-ui-ux.md](docs/08-ui-ux.md) | Full UI architecture across PC / mobile / tablet / console |
| [09-tech-architecture.md](docs/09-tech-architecture.md) | Studio folder tree, services, remotes, security |
| [10-data-schema.md](docs/10-data-schema.md) | Save schema, versioning, migrations |
| [11-content-config.md](docs/11-content-config.md) | How to add a dinosaur without touching a system |
| [12-mvp-and-roadmap.md](docs/12-mvp-and-roadmap.md) | Exactly what ships in V1, then V1.1 → V2.0 |
| [13-build-order.md](docs/13-build-order.md) | 24 numbered build steps |
| [14-analytics.md](docs/14-analytics.md) | Events to log, funnels, the 10 metrics that matter |
| [15-art-audio-animation.md](docs/15-art-audio-animation.md) | Visual style, SFX list, animation list, viral moments |

## Naming contract

Every folder, ModuleScript, RemoteEvent, config key and data field named in
[09-tech-architecture.md](docs/09-tech-architecture.md) and
[10-data-schema.md](docs/10-data-schema.md) is **frozen**. Systems will be built
against those exact names. If a name must change, it gets changed in the doc
first, with a stated reason, before any code moves.
