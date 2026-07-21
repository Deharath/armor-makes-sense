# Armor Makes Sense

Armor Makes Sense (AMS) is a Project Zomboid Build 42 mod that replaces
wearable discomfort penalties with physical equipment costs.

## Requirements

- Project Zomboid Build 42.19.0 or later
- No required library mods

## Features

- **Wearable discomfort removal:** Sets `DiscomfortModifier` to zero on
  wearable items while preserving non-clothing discomfort sources.
- **Equipment burden:** Derives physical load from item weight, protection,
  original discomfort, and movement modifiers.
- **Endurance:** Increases movement cost and reduces endurance regeneration.
  Vanilla remains responsible for melee stamina costs.
- **Thermal pressure:** Adds exertion cost when insulating equipment contributes
  to heat strain. Insulation can reduce cold strain.
- **Breathing restriction:** Applies exertion-dependent penalties to
  respirators, gas masks, and sealed suits.
- **Muscle strain:** Adds melee strain from protective equipment worn on the
  swing chain, including shoulders, arms, forearms, elbows, and hands.
- **Sleep recovery:** Reduces fatigue recovery while sleeping in rigid gear.
- **Speed rebalance:** Applies curated run-speed and combat-speed modifiers by
  protected body region.
- **Equipment layering:** Moves selected items to eight AMS body locations to
  remove unnecessary vanilla slot conflicts.

## User Interface

- Wearable tooltips show burden and breathing restriction when applicable.
- The character information window includes a Burden tab with aggregate load,
  thermal state, breathing restriction, sleep impact, and cost drivers.
- The Burden tab can export an AMS support report.

## Multiplayer

AMS supports singleplayer, hosted co-op, and dedicated servers. Multiplayer
gameplay calculations are server-authoritative. Clients receive snapshots for
the Burden UI and apply server-authoritative sleep and wake corrections.

## Configuration

The sandbox settings expose independent toggles for:

- thermal pressure
- muscle strain
- sleep penalties

## Installation

Subscribe on the [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3677430162).

For a manual installation, place the complete `ArmorMakesSense` directory in
the Project Zomboid mods directory. Keep `mod.info`, `common/`, and `42/` in the
same mod directory.

## Compatibility

AMS classifies third-party wearable equipment from item properties, including
protection, weight, tags, body location, and movement modifiers. Unknown armor
can therefore receive AMS burden without a dedicated patch. Curated speed
rebalance and slot changes apply only to items listed by AMS.

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

Run `tests/run_tests.sh` from the mod root for deterministic shared-model and MP
snapshot codec characterization checks.

## License

MIT

## Author

Deharath
