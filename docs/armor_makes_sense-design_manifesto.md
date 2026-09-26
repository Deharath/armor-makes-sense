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
- combat speed modifiers

AMS does not add a separate burden moodle or custom character resource.

### Burden Is Mass

An item's cost is its effective mass: how much it weighs, where it sits on the
body, and how bulky vanilla already says it is. The same kit costs less for a
heavier or stronger character. Players should be able to predict the cost by
picking the item up.

### Scale Cost With Activity

Equipment should have limited impact at rest and greater impact during sustained
activity. Sitting is free, and walking remains inexpensive under ordinary
conditions. Running,
sprinting, heat strain, restrictive breathing equipment, and repeated melee
attacks expose the load more clearly.

### Preserve Useful Protection

Armor should remain valuable in dangerous situations. AMS is intended to make
equipment choice contextual, not to make protection categorically inefficient.

### Preserve Vanilla Ownership

AMS supplements rather than replaces the following vanilla behaviors:

- base melee stamina cost (AMS scales it with load like any other drain)
- non-clothing discomfort
- thermoregulation
- bed quality, sleep traits, sleep planning and wake time
- base muscle strain
- encumbrance from carried inventory and worn bags

### Show Tiers, Not Numbers

Player UI shows pips and tiers. Exact values belong in the support report.

## System Responsibilities

| System | AMS responsibility |
|---|---|
| Endurance | Increase drain (fighting at half the load share) and reduce regeneration according to load and environment |
| Thermal pressure | Convert sustained heat strain into additional exertion cost and recognize useful cold insulation |
| Breathing | Scale respiratory restriction with ventilation demand |
| Muscle strain | Add load from equipment worn on the melee swing chain |
| Sleep | Reduce fatigue recovery in proportion to rigid armor worn to bed |
| Swing speed | Slow melee swings by swing-chain mass, 1% per kg up to 5% |
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
