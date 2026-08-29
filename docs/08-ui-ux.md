# 08 — UI / UX Architecture

## 1. Principles

1. **The HUD is never more than 7 elements.** Anything else lives behind one tap.
2. **One-thumb reachable.** All primary buttons sit in the bottom 35 % of the
   screen on touch devices.
3. **Colour carries meaning.** Rarity colours from
   [01-dinosaurs.md](01-dinosaurs.md) are used *only* for rarity, nowhere else.
4. **Numbers are always readable.** Rounded suffixes, never raw digits over 5
   characters.
5. **Nothing blocks the chase.** During a chase, all menus auto-close and the
   HUD reduces to: escape arrow, timer, egg icon, guardian distance.

## 2. Screen map

```
                    ┌─────────────── TOP BAR ───────────────┐
                    │ 🦴 Fossils   🧬 DNA   ⭐R7   🛡️14:22   │
                    └───────────────────────────────────────┘
  ┌── LEFT RAIL ──┐        ⚑ compass strip → YOUR PARK        ┌─ RIGHT RAIL ─┐
  │ 🎁 Daily      │                                            │ ⛅ Weather   │
  │ ✅ Quests     │        ☄️ METEOR IMPACT IN 0:42            │ 🏆 Leaders   │
  │ 📖 Index      │        (event banner, only when active)    │ 👥 Friends   │
  │ ⚙️ Settings   │                                            │ 🗺️ Minimap   │
  └───────────────┘                                            └──────────────┘

                    ┌──────── ACTION ZONE (contextual) ───────┐
                    │        [ HOLD TO STEAL ]  ◯ 62 %        │
                    └─────────────────────────────────────────┘
  ┌──────────────────── BOTTOM BAR (5 big buttons) ───────────────────┐
  │  🏠 PARK   🥚 EGGS(3)   🦖 DINOS   🛒 SHOP   🚀 TELEPORT          │
  └───────────────────────────────────────────────────────────────────┘
```

### 2.1 Top bar (always visible)

| Element | Behaviour |
|---|---|
| Fossils | Tweens up on collect; flashes gold on big gains |
| DNA | Hidden until the player first earns DNA (progressive disclosure) |
| Rebirth badge | Tap → rebirth screen with a progress ring |
| Shield timer | Only shown while shielded; tap → protection explainer |

### 2.2 Bottom bar (5 buttons, ~72 px tall on mobile)

| Button | Opens |
|---|---|
| **PARK** | Teleports you home. Long-press → park management overlay |
| **EGGS** | Egg inventory + incubator grid. Badge shows carried count |
| **DINOS** | Dinosaur inventory with filters |
| **SHOP** | Tabs: Upgrades / Boosts / Robux / Defence |
| **TELEPORT** | Zone wheel — discovered zones lit, locked ones show the cost |

### 2.3 Contextual action zone

The only element that changes. States:

| State | Shows |
|---|---|
| Near a nest | Nest info card + `HOLD TO STEAL` with a fill ring |
| Carrying an egg | Rarity chip, big arrow to your park, distance, guardian proximity bar |
| Being chased | Full-screen red vignette pulsing with guardian distance; `RUN!` |
| In your park, near an empty pad | `PLACE DINOSAUR` |
| In another park, on an enclosure | `HOLD TO STEAL` with hold timer + a visible alert-sent icon |
| Near the Collection Totem | `COLLECT 42.3K` |
| In a raid on you | `INTRUDER!` banner + `TAG THEM` |

## 3. Menus (all are one screen, no nesting deeper than 2)

| Menu | Layout |
|---|---|
| **Park** | Top-down grid view; drag dinosaurs to tiles; locked tiles show unlock cost inline |
| **Eggs** | Incubator row across the top with live timers; egg storage grid below |
| **Dinos** | Grid of cards; filter chips (rarity / mutation / placed / starred); multi-select for bulk sell |
| **Shop** | 4 tabs, each a vertical list of wide rows: icon, name, effect now→next, price, buy |
| **Index** | Book with zone tabs; 60 slots; silhouettes for undiscovered |
| **Quests** | Daily (3) and Weekly (3) cards with progress bars and a claim button |
| **Daily** | 7 chest tiles in a row; today's pulses |
| **Rebirth** | Big preview of "what you keep / what you lose / what you gain", one confirm |
| **Leaderboards** | 8 tabs, top 100 each, your rank pinned at the bottom |
| **Settings** | Sliders and toggles, one column |

## 4. Platform specifics

### The touch-target guarantee (structural, not aspirational)

`Theme.ScaleFor` derives its lower clamp from `MinTouchTarget /
BottomButtonHeight` rather than from a hand-picked number or a device check. At
any scale at or above that floor, a bottom-bar button is at least **64 real
pixels** tall — on every viewport, including ones nobody thought to test.
`tests/step5_spec.lua` asserts it across twelve real device resolutions from a
480×270 window to 4K.

The consequence is deliberate: on a very small screen the UI is *larger*
relative to the screen. There is less to show and every target still has to be
thumb-sized.

Breakpoints are named for available **room** (`compact` / `medium` / `wide`),
not device class, and are measured in logical pixels (viewport ÷ scale). Two
viewports with the same room get the same layout — that is what responsive
means, and naming them "phone" and "tablet" would invite device-sniffing, which
is how UI ends up wrong on the one configuration nobody tested.

### Mobile (primary target)

- Bottom bar buttons ≥ 64×64 px with ≥ 8 px gaps.
- `HOLD TO STEAL` is a thumb-sized circle bottom-right, above the jump button.
- Left rail collapses into a single `☰` at < 500 px logical width.
- The minimap is tap-to-expand, not always-on.
- No hover states anywhere. Every tooltip is also reachable by long-press.
- Sprint is automatic while a chase is active (no extra button to find).

### Tablet

- Same as mobile with the left rail expanded and a persistent minimap.

### PC

- Keyboard: `E` interact, `Shift` sprint, `Q` drop egg, `1-5` bottom bar,
  `Tab` inventory, `M` map, `Esc` close.
- Mouse hover tooltips on every stat.

### Console

- Gamepad: `A` interact/hold, `X` drop, `LB/RB` cycle menus, `Y` teleport,
  `View` map. Full D-pad menu navigation with a visible focus ring.
- Safe-area inset of 5 % on all edges.
- All text ≥ 20 px at 1080p (10-foot readability).

## 5. Notifications

Three severities, three visual weights, one queue that never stacks.

| Type | Look | Duration | Examples |
|---|---|---:|---|
| **Toast** | Small, top-right, slides in | 3 s | `+250 DNA`, `Upgrade purchased`, `Quest complete` |
| **Banner** | Full-width, top, colour-coded, with SFX | 5 s | `MYTHIC HATCHED!`, `BLOOD MOON`, `METEOR IN 60s` |
| **Takeover** | Centre-screen, dims the world, camera flourish | 4 s + skip | Secret / Titan / Prime hatches only |
| **Alert** | Red pulsing bar + haptic on mobile | until resolved | `SOMEONE IS STEALING YOUR ALPHA UTAHRAPTOR!` |

Rules: max 1 takeover at a time (others queue, max queue 3, then drop); banners
never cover the action zone; a player's *own* park alerts cannot be muted; the
notification queue is client-side but every entry originates from a server event.

## 6. Onboarding UI

- Professor Rok is a 3D character, not a UI panel — he physically leads.
- Objective text is one line in a fixed spot under the top bar.
- A single animated arrow in world space, never a maze of highlights.
- Every FTUE step has a 25-second timeout after which the arrow enlarges and
  a hint appears; after 60 s the step auto-completes so nobody gets stuck.

## 7. Accessibility

- Rarity is never communicated by colour alone — every rarity chip also carries
  its name and a distinct icon shape.
- UI scale 80–130 %.
- Camera shake, screen flash and particle density all individually disableable.
- No pure red/green pairs for critical state.
- All hold interactions have a visible numeric progress percentage.
