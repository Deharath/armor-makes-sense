# Armor Makes Sense

Armor Makes Sense (AMS) is a Project Zomboid Build 42 mod that replaces
wearable discomfort penalties with physical equipment costs.

## Requirements

- Project Zomboid Build 42.20.0 or later
- No required library mods

## Features

- **Burden in kilograms:** Each worn item costs its effective mass, weighted by
  where it sits on the body and by its original vanilla bulk. Vanilla footwear
  gets realistic pair weights, so boots cost more than trainers. The cost is
  scaled by the character's body mass and Strength.
- **Endurance:** Burden makes every endurance drain cost more and slows
  recovery: a little while standing, more while walking. Sitting is free.
  Vanilla keeps ownership of melee stamina costs.
- **Heat:** Insulation slows recovery and adds drain while the character is
  overheating. Insulation can reduce cold strain.
- **Breathing:** Respirators, gas masks and sealed suits add drain at high
  exertion. Walking and resting are free.
- **Muscle strain and swing speed:** Protective mass on the swing chain
  (shoulders, arms, forearms, elbows, hands) adds melee strain and slows
  swings by 1% per kg, up to 5%.
- **Sleep in stiff gear:** Gear vanilla marks as uncomfortable (armor, pads,
  helmets, crafted burlap) reduces fatigue recovery when worn to bed.
  Vanilla keeps ownership of sleep planning, wake time and bed quality.
- **Wearable discomfort removal:** Sets `DiscomfortModifier` to zero on
  wearable items, leaving non-clothing discomfort sources intact.
- **Equipment layering:** Moves selected items to eight AMS body locations to
  remove unnecessary vanilla slot conflicts.

## User Interface

- Wearable tooltips show burden as pips, plus breathing restriction when
  applicable.
- The character information window includes a Burden tab: a one-line verdict,
  a body map of where the weight sits, rows for load, endurance per pace, heat,
  breathing, melee and sleep, and the heaviest worn items with a tip on what to
  take off.
- The Burden tab can export an AMS support report.

## Multiplayer

AMS supports singleplayer, hosted co-op, and dedicated servers. Gameplay
calculations are server-authoritative. The Burden tab reads gear from the
client's worn items instantly and takes heat from a server snapshot, which is
requested only while the tab or support export needs it.

## Configuration

Sandbox settings:

- physical load scale (0–3)
- heat, breathing, muscle strain and sleep penalty toggles

## Installation

Subscribe on the [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3677430162).

For a manual installation, place the complete `ArmorMakesSense` directory in
the Project Zomboid mods directory. Keep `mod.info`, `common/`, and `42/` in the
same mod directory.

## Compatibility

AMS derives burden for third-party wearables from item weight, body location,
movement modifiers and tags. Modded armor therefore works without a dedicated
patch. Items can opt out with `AMSExcludeBurden`, opt in with
`AMSIncludeBurden`, or be marked rigid for the sleep penalty with `AMSArmor`.
Otherwise rigidity follows the item's vanilla `DiscomfortModifier`. Slot changes
apply only to items listed by AMS.

The shared `MakesSenseCompat` protocol coordinates endurance and sleep effects
when Caffeine Makes Sense or Nutrition Makes Sense is installed.

## Documentation

| Document | Purpose |
|---|---|
| [Design Principles](docs/armor_makes_sense-design_manifesto.md) | Gameplay goals and non-goals |
| [Technical Overview](docs/armor_makes_sense-technical_appendix.md) | Architecture and module ownership |
| [Runtime Reference](docs/armor_makes_sense-runtime_reference.md) | Gameplay models and formulas |
| [Multiplayer Reference](docs/armor_makes_sense-mp_reference.md) | Authority, transport, and diagnostics |
| [UI Reference](docs/armor_makes_sense-ui_reference.md) | Tooltip and Burden panel behavior |
| [Testing Reference](docs/armor_makes_sense-testing_reference.md) | Development commands and benchmark infrastructure |

## Development Testing

Development builds include the in-game test and benchmark modules under
`common/media/lua/client/testing/`. Workshop builds exclude testing and
diagnostic modules. Release staging validates the exclusion and copies runtime
Lua unchanged; it does not rewrite Main.

Workspace tooling is under `../tools/armor_makes_sense/`. See the
[Testing Reference](docs/armor_makes_sense-testing_reference.md) for the Lua API
and benchmark pipeline.

Run `tests/run_tests.sh` from the mod root for deterministic shared-model, UI and
MP snapshot codec checks, and `tests/test_release_shape.sh` for release-shape
guards.

## License

MIT

## Author

Deharath
