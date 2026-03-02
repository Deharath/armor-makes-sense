# Armor Makes Sense

**Build 42 singleplayer mod for Project Zomboid.**

Armor is a physical tradeoff, not a psychological penalty. This mod replaces vanilla's discomfort system with physical costs: endurance drain, muscle strain, breathing restriction, thermal pressure, and sleep recovery penalties -- all through vanilla's existing systems.

No stress penalties. Just physics.

## What It Does

**Discomfort zeroed.** Vanilla's discomfort modifier is set to zero on all wearable items at boot. Armor no longer causes stress or unhappiness.

**Speed rebalance.** Run speed and combat speed modifiers are normalised by body region for known protective gear. Leg armor affects running. Arm and shoulder armor affect combat speed. Light pads stay neutral.

**Endurance drain.** Heavier armor increases endurance usage during movement and combat. Walking is almost free. Sprinting in full plate is not.

**Thermal pressure.** Armor traps heat. In hot weather you overheat faster. In cold weather, insulating armor helps. The system is intentionally asymmetric.

**Breathing restriction.** Gas masks and respirators restrict airflow. The penalty scales with exertion: invisible at rest, noticeable in sustained combat.

**Muscle strain.** Heavy arm and shoulder armor adds fatigue per swing. A chest plate doesn't slow your swing, but gauntlets and shoulder pads do. Better-crafted armor restricts less than crude scrap.

**Sleep recovery.** Sleeping in rigid armor slows fatigue recovery. It's an emergency choice, not a default.

## UI

- **Tooltips** show burden level and breathing restriction for each armor piece
- **Burden tab** in the character info panel breaks down total loadout cost
- **Help button** explains each mechanic in plain language

## Installation

Subscribe on [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3677430162), or copy `common/` and `42/` into your PZ mods directory.

Requires Project Zomboid Build 42 (42.14.0+). Singleplayer only.

## Compatibility

- Singleplayer only
- Build 42.14.0+
- Armor from other mods should work -- items are classified based on their defense stats, weight, and item properties (not yet tested with all armor mods)
- Compatible with [Starlit Library](https://steamcommunity.com/sharedfiles/filedetails/?id=3378285185) -- uses its tooltip hook when available

## Documentation

| Document | Contents |
|---|---|
| [Design Manifesto](docs/design/armor_makes_sense-design_manifesto.md) | Core philosophy and design goals |
| [Technical Reference](docs/design/armor_makes_sense-technical_appendix.md) | Architecture, models, load channels, config values |

## Testing

The `testing/` directory contains a full in-game benchmark harness: scenario catalogs, a native movement/combat driver, step pipelines, snapshot writer, and report aggregation. This ships with the GitHub release but not the Workshop build.

Run benchmarks via console commands (see `testing/ArmorMakesSense_Commands.lua`). Parse results with `tools/parse_bench.py`.

## License

MIT

## Author

Deharath
