# Armor Makes Sense - Design Principles

## Purpose

AMS makes protective equipment a physical tradeoff. Protection should affect
movement capacity, heat regulation, breathing, melee strain, and recovery. It
should not impose an unrelated psychological penalty.

## Core Principles

### Use Existing Character Systems

AMS expresses equipment cost through Project Zomboid systems that already
represent physical condition:

- endurance
- fatigue recovery
- thermoregulation
- muscle strain
- movement and combat speed modifiers

AMS does not add a separate burden moodle or custom character resource.

### Scale Cost With Activity

Equipment should have limited impact at rest and greater impact during sustained
activity. Walking remains inexpensive under ordinary conditions. Running,
sprinting, heat strain, restrictive breathing equipment, and repeated melee
attacks expose the load more clearly.

### Preserve Useful Protection

Armor should remain valuable in dangerous situations. AMS is intended to make
equipment choice contextual, not to make protection categorically inefficient.

### Preserve Vanilla Ownership

AMS supplements rather than replaces the following vanilla behaviors:

- melee stamina cost
- non-clothing discomfort
- thermoregulation
- bed quality and sleep traits
- base muscle strain

## System Responsibilities

| System | AMS responsibility |
|---|---|
| Endurance | Increase movement drain and reduce regeneration according to load and environment |
| Thermal pressure | Convert sustained heat strain into additional exertion cost and recognize useful cold insulation |
| Breathing | Scale respiratory restriction with ventilation demand |
| Muscle strain | Add load from equipment worn on the melee swing chain |
| Sleep | Reduce fatigue recovery according to rigidity and vanilla sleep recovery rate |
| Speed | Apply curated regional run-speed and combat-speed modifiers |
| Equipment slots | Remove selected layering conflicts without allowing incompatible combinations |

## Discomfort Policy

AMS sets `DiscomfortModifier` to zero on wearable script items and caches the
original value for its own load calculations. It does not clamp the live
`DISCOMFORT` character stat.

Non-clothing discomfort sources remain active, including poor sleep surfaces,
wetness, temperature effects, corpse dragging, and vehicle over-encumbrance.

## Non-Goals

AMS does not:

- add stress, panic, or unhappiness as an armor cost
- add arbitrary accuracy or damage penalties
- apply continuous timed endurance drain to melee combat
- guarantee curated balance for every third-party item
- replace vanilla temperature, fatigue, or muscle-strain systems

## Balance Target

The intended equipment curve is:

- negligible impact for light clothing
- modest sustained cost for practical protective gear
- clear endurance and recovery cost for heavy or restrictive loadouts
- strong situational pressure from heat, sprinting, sealed breathing equipment,
  and sleeping in rigid armor
