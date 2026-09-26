# Armor Makes Sense - Runtime Reference

This document describes what AMS computes and when. Module ownership and
vanilla contracts are in the [Technical Overview](armor_makes_sense-technical_appendix.md);
the MP transport is in the [Multiplayer Reference](armor_makes_sense-mp_reference.md).

## Model in One Paragraph

Each worn item has an effective mass in kg (its **burden**). Summed and
compared with the character's body mass and Strength, burden gives a **load
fraction**. AMS never invents its own endurance curve. Once per game minute it
observes vanilla's endurance change and scales it. Load amplifies every
endurance drain and slows recovery: gently while standing, more while walking;
sitting is free. Insulation while overheating (**heat**) slows recovery
everywhere and adds drain. Restrictive respiratory gear (**breathing**) adds
drain at high exertion. Stiff gear (vanilla discomfort) gives back part of
vanilla's fatigue recovery while asleep. Swing-chain mass adds melee muscle
strain and a small combat-speed penalty. Vanilla keeps ownership of the base
melee stamina cost (which the drain scale amplifies like any other drain),
sleep planning, wake time, bed quality and encumbrance.

## Client Runtime Wiring

`Bootstrap.resolveClientRole()` requires PZ's `isClient()` role detector.
`Bootstrap.registerClientRuntime()` then registers exactly one client runtime:

- `singleplayer`: `Core.Runtime`
- `multiplayer`: `ArmorMakesSense.MPClientRuntime`

Loading the MP client module does not register events or initialize player
state. Development builds add their excluded benchmark handlers after the
production role is selected.

`Runtime.registerEvents` (SP) requires `Events.EveryOneMinute.Add` and
`getPlayer`. It also hooks `OnPlayerAttackFinished` when available. Missing
prerequisites leave the client runtime disabled for the session.

`MPClientRuntime.registerEvents` requires `OnServerCommand`, `OnConnected` and
`OnCreatePlayer`. The MP client runs no gameplay; it caches server snapshots
for the UI.

`ArmorMakesSense_SpeedRebalance.lua` binds to `OnGameBoot`, `OnMainMenuEnter`
and `OnGameStart`, keeps its handlers, and replaces them on Lua reload.

`ArmorMakesSense_SlotCompat.lua` registers custom body locations at module
load and retries after local-player creation if the Java location APIs were
not ready. Initialization completes only once all eight custom locations
resolve.

## Authoritative Tick (`Physiology.tick`)

One tick per game minute per player:

- SP: `Runtime.onEveryOneMinute` calls `Tick.tickPlayer` for each local player.
- MP: the server's `EveryOneMinute` handler ticks every online player.

`Tick.tickPlayer(player)`:

1. `ClientRuntime.ensureState(player)`; stop if startup checks fail.
2. `Options.get()` and `LoadModel.computeWornProfile(player, options)`.
3. `Physiology.tick(player, state, options, profile, worldAgeMinutes)`.
4. `UI.update(player, profile, options)`.

`Physiology.tick(player, state, options, profile, nowMinutes)`:

1. Record `state.lastTickMinute`; elapsed = now − previous tick minute.
2. `SleepModel.step` (runs every tick, awake or asleep).
3. Sample posture and activity.
4. **Rebase** instead of applying when asleep, on the first tick, when elapsed
   is zero, or when elapsed exceeds `MaxStepMinutes` (30). Rebasing stores the
   current endurance as the next baseline and refreshes the snapshot. A load,
   teleport, time skip, or bench reset therefore never becomes a retroactive
   endurance charge.
5. Otherwise advance heat by the elapsed minutes, build the snapshot, and
   apply `EnduranceModel.calculate` to the observed endurance delta (see
   below). Write endurance only when it differs by more than `0.00001`, then
   report the result to NMS if present.
6. Store the controlled endurance as the next baseline and the snapshot as
   `state.uiRuntimeSnapshot`.

`Physiology.project(player, state, options, profile)` builds the same snapshot
with no side effects. It advances a copy of the heat state by zero minutes. SP
UI refreshes and MP snapshot requests use it.

### Snapshot Fields

| Group | Fields |
|---|---|
| Context | `activityLabel`, `postureLabel`, `updatedMinute` |
| Gear | `burdenKg`, `armKg`, `rigidKg`, `driverCount`, `airflowResistance`, `sealedRestriction` |
| Carrier | `bodyKg`, `strength`, `loadFraction` |
| Heat | `heat`, `thermalResistance`, `hotPressure`, `coldSuitability` |
| Breathing | `breathingSeverity`, `breathingEnabled` |
| Per-pace preview | `restRegenScale`, `standRegenScale`, `walkRegenScale`, `runDrainScale`, `sprintDrainScale`, `sleepPenaltyFraction` |
| Applied tick only | `naturalDelta`, `amsDelta`, `regenScale`, `drainScale`, `nmsRegenScale`, `nmsDrain`, `dtMinutes`, `metabolicRate`, `breathingEffortRamp`, `breathingPressure` |

The per-pace preview answers "what would this loadout cost at each pace right
now", independent of what the character is doing. The Burden tab reads these
fields.

## Combat Event Path

SP `OnPlayerAttackFinished` and MP server `OnWeaponSwing` apply the strain
overlay when the attacker is the local (SP) or event (MP) player, the muscle
strain model is enabled, and the weapon is eligible. Combat does not change AMS
activity state or add a timed endurance drain. Vanilla owns the base melee
stamina loss, attack metabolism and hit-count-dependent base muscle strain.
Swing stamina lands in the minute's observed endurance delta, so the tick
multiplies it by `drainScale` like any other drain: fighting in heavy gear
costs more endurance.

## Option Resolution

SP and the MP server both use `Options.get()`:

1. copy `ArmorMakesSense.DEFAULTS` (`shared/ArmorMakesSense_Config.lua`);
2. apply `SandboxVars.ArmorMakesSense` overrides for known keys, parsed by
   the default value's type.

Each call returns a fresh table.

## Transient State

`ArmorMakesSense_RuntimeState.lua` keeps session-only state in a weak-key
table indexed by player identity:

| Owner | Fields |
|---|---|
| Physiology | `lastTickMinute`, `lastEnduranceObserved`, `thermalModelState`, `uiRuntimeSnapshot` |
| SleepModel | `lastFatigueObserved`, `sleepWasAsleep`, `sleepPenaltyFraction`, `lastSleepExtraFatigue` |

The MP server keeps the same fields under the player's `mpServer` role state,
plus `runtimeSnapshot` (with drivers) and a one-second worn-profile cache.
Development builds add test locks, gear profiles and the benchmark handle. The
obsolete saved AMS blob is deleted on first player access and never migrated.

## Wearable Burden (`LoadModel.computeItemSignal`)

Burden is an item's effective mass in kg: its mass, weighted by where it sits
on the body, plus bulk read from its original vanilla penalties.

```lua
massKg    = max(0, weight - BurdenItemMassAllowanceKg)                  -- 0.5 kg
bulkKg    = runPenalty * BurdenBulkPerRunPenalty                        -- x 6
          + originalDiscomfort * BurdenBulkPerDiscomfort                -- x 4
burdenKg  = massKg * placementFactor(location) + bulkKg
runPenalty = max(0, 1 - RunSpeedModifier)   -- 0 for shoe locations
```

The per-item allowance keeps ordinary garments near zero. Original discomfort
is read from `ArmorMakesSense._originalDiscomfort`, cached before
SpeedRebalance zeroes it. Footwear run modifiers describe soles and traction,
not bulk.

`weight` is the script weight, except for vanilla footwear. Vanilla leaves
every shoe at the 1.0 kg script default, so AMS authors pair weights in
`AUTHORED_MASS_KG` (work boots 2.0, army boots and wellies 1.8, leather and
cowboy boots 1.6, hiking and riding boots 1.4, dress shoes 0.9, trainers 0.7,
sandals 0.5, slippers and flip-flops 0.3). Only the burden model reads them;
inventory weight is untouched and modded footwear keeps its own weight.

Placement factor (first matching body-location fragment wins, default 1.0):

| Region | Fragments | Factor |
|---|---|---|
| Trunk (and any unmatched location) | `jacket`, `sweater` | 1.0 |
| Full suits | `fullsuit`, `boilersuit`, `torso1legs1` | 1.3 |
| Feet and lower leg | `shoe`, `sock`, `ankle`, `calf`, `knee`, `shin`, `gaiter` | 2.0 |
| Thigh | `thigh` | 1.5 |
| Legwear | `pants`, `legs` | 1.4 |
| Skirts and shorts | `skirt`, `shorts` | 1.3 |
| Hands | `hand`, `finger`, `wrist` | 1.6 |
| Forearm and elbow | `forearm`, `elbow` | 1.4 |
| Upper arm | `arm` | 1.3 |
| Shoulder, head, face, neck | `shoulder`, `hat`, `head`, `mask`, `eye`, `ear`, `nose`, `gorget`, `neck`, `scarf` | 1.2 |

Inclusion:

- `AMSExcludeBurden` excludes an item.
- Cosmetic items and inventory containers are excluded unless tagged
  `AMSIncludeBurden`. Worn bags stay under vanilla encumbrance.
- `AMSArmor` marks an item rigid regardless of discomfort.

Derived channels per item:

- `rigid` is true when the item's original vanilla `DiscomfortModifier` is
  above 0 (armor, helmets, pads, masks, crafted burlap and tarp) or it carries
  `AMSArmor`. Defense stats do not matter: a leather jacket protects but is fine
  to sleep in.
- `rigidKg = weight * sleepContact(location)` for rigid items, 0 otherwise. Sleep contact (first matching group wins): head, face and neck
  0.0; forearm, hand, wrist, finger, elbow, shin, calf, knee, gaiter and feet
  0.4; shoulder, hip, thigh, leg, pants and belt 0.7; torso, back, chest,
  cuirass, vest, jacket, sweater, jersey and full suits 1.0; unknown 0.7.
- `swingChain` is true for shoulder, arm, forearm, elbow, hand, wrist and
  finger locations, excluding `shoulderholster`.
- `airflowResistance` and `sealedRestriction` come from the respiratory
  classifier.

Signals are cached by `fullType|location|weight`; `clearSignalCache()` resets
the cache.

Respiratory classification (`BreathingClassifier`):
- slot classes:
  - `mask` -> face covering
  - `maskeyes` -> face covering
  - `maskfull` -> face covering floor
  - `fullsuithead` -> sealed suit
- respiratory tags:
  - `gasmask`, `gasmasknofilter`
  - `respirator`, `respiratornofilter`
  - `weldingmask`
  - `hazmatsuit`, `scba`, `scbanotank`
- respiratory tag classes take precedence
- `gasmasknofilter`, `respiratornofilter`, and `scbanotank` explicitly select
  the no-filter state even when the item type does not contain `nofilter`
- keyword identity matches include `gasmask`, `respirator`, `weldingmask`,
  `hazmat`, `dustmask`, `surgicalmask`, and `bandanamask`
- generic `head` / `neck` slots do not add breathing restriction by themselves

Class outputs are `{airflowResistance, sealedRestriction}`:
- face covering: `{0, 0}`
- respirator with filter: `{3.30, 0}`
- respirator without filter: `{0.90, 0}`
- sealed mask with filter: `{3.75, 1}`
- sealed mask without filter: `{1.35, 0}`
- sealed suit: `{3.75, 1}`

The sealed flag describes an actual filtered seal. Removing the filter lowers
airflow resistance and removes the sealed restriction instead of inferring a
seal from the remaining numeric load.

## Worn-Gear Analysis (`LoadModel.analyzeWornGear`)

One traversal of `player:getWornItems()` returns:

- `profile`: `burdenKg`, `massKg`, `bulkKg`, `armKg` (swing-chain burden),
  `rigidKg`, `airflowResistance` (summed, capped at 12), `sealedRestriction`
  (maximum), `driverCount`;
- `rows`: one normalized row per worn item, excluded items included;
- `costDrivers`: items at or above 1.5 kg burden (`COST_DRIVER_THRESHOLD_KG`),
  heaviest first;
- `equipmentSignature` and `wornCount` for diagnostics.

`computeWornProfile(player, options)` returns `analyzeWornGear(...).profile`.
UI, support reports, strain and MP authority all read this one result.

## Load Fraction (`LoadModel.loadFraction`)

```lua
excessKg       = max(0, burdenKg - BurdenClothingAllowanceKg)            -- 3.5 kg
strengthFactor = max(0.2, StrengthFactorBase - StrengthFactorPerLevel * strength)  -- 1.3 - 0.06 * str
loadFraction   = excessKg / bodyKg * strengthFactor * PhysicalLoadScale
```

`bodyKg` is the character's nutrition weight clamped to 50–90 kg; `strength`
is the Strength perk level (default 5). The same kit is therefore easier for a
heavier or stronger character. The 90 kg ceiling stands in for lean mass:
extra body fat does not help carry armor. The 3.5 kg allowance keeps a
T-shirt, jeans and leather boots free. At strength 5 the factor is 1.0.
`PhysicalLoadScale` is the sandbox multiplier (0–3).

## Endurance (`EnduranceModel`)

`EnduranceModel.scales(options, input)` with `loadFraction`, `heat`,
`breathing` (pressure), `activityLabel` and `resting`:

```lua
physicalRegen = 1
if activity == "walk" and not resting then
    physicalRegen = max(WalkRegenFloor, 1 - WalkRegenLoadWeight * loadFraction)   -- floor -0.5, weight 2.0
elseif not resting then
    physicalRegen = max(0, 1 - StandRegenLoadWeight * loadFraction^2)             -- weight 1.0
end
thermalRegen   = 1 - ThermalRegenPenaltyMax * heat                               -- 0.5
physicalDrain  = DrainLoadWeight * loadFraction                                  -- 1.0
thermalDrain   = ThermalDrainWeight * heat                                       -- 0.25
breathingDrain = BreathingDrainWeight * breathing                                -- 0.35

regenScale        = max(0, physicalRegen) * thermalRegen
walkDrainFraction = max(0, -physicalRegen)
drainScale        = 1 + physicalDrain + thermalDrain + breathingDrain
```

`EnduranceModel.calculate(options, input)` applies the scales to vanilla's
observed change since the previous tick:

```lua
natural = current - previous
if natural > 0 then        -- vanilla recovered
    controlled = previous + natural * regenScale * nmsRegenScale - natural * walkDrainFraction
elseif natural < 0 then    -- vanilla drained
    controlled = previous + natural * drainScale
end
controlled = clamp(controlled - nmsDrain, 0, 1)
```

Consequences:

- Sitting and vehicle seats (`resting`) recover at the vanilla rate; only heat
  slows them.
- Standing still slows recovery with the square of the load and never turns it
  into drain: under 1% for a vest, about 13% for full crafted plate.
- Drain uses one load weight whatever the pace. Vanilla already drains faster
  paces harder, and the extra metabolic cost of a carried load is close to a
  fixed share of movement cost (Pandolf). Drain therefore does not depend on
  the activity sampled at the tick, which can differ from what the player did
  during the minute (a game minute is 2.5 s at a 1-hour day, 30 s at 12 hours).
- The weight is 1.0 because burden is already trunk-equivalent kg: placement
  factors carry the extra cost of limb mass. Running cost grows with total
  mass, so a load of 20% of body mass costs about 20% more (Pandolf's walking
  estimate is lower still). A vest-and-uniform police loadout drains about
  x1.08, a soldier x1.11, a full SWAT kit x1.21 and full crafted metal x1.42
  (80 kg, Strength 5).
- Melee swings are drains too, so the same multiplier applies to fighting.
- Past the walk floor (load fraction above 0.5 at default weights), walking
  turns part of vanilla's recovery into drain.
- With no vanilla change there is no AMS change.
- With no previous observation, nothing is applied (`canApply = false`).

NMS composes through `MakesSenseCompat`:
`computeEnduranceContribution` supplies `regenScale` and `extraDrain`, and
`recordEnduranceResult` receives the controlled value.

## Breathing (`BreathingModel`)

```lua
severity = clamp(airflowResistance / 3.75, 0, 1) * (0.75 + 0.25 * sealedRestriction)
demand   = max(metabolicRate, movementDemand)   -- idle 1.5, walk 3.1, run 6.9, sprint 9.5
effort   = clamp((demand - 1.5) / (9.5 - 1.5), 0, 1)
ramp     = effort > onset and smoothstep((effort - onset) / (1 - onset)) or 0   -- onset 0.20
pressure = EnableBreathingModel and severity * ramp or 0
```

`3.75` is the airflow resistance of a filtered, sealed gas mask, so that mask
is full severity. The 1.5 and 9.5 anchors are vanilla's rest and 15 km/h
metabolic rates. The 0.20 onset is vanilla's 5 km/h walking rate, so walking
and resting are free and harder work ramps smoothly to sprint effort. The
movement floor makes breathing react on the next tick instead of waiting for
vanilla's smoothed metabolic rate. The metabolic rate still raises demand for
work, attacks and other exertion.

`breathingSeverity` in snapshots is the gear rating (sprint severity). It is
reported even when the channel is disabled; `pressure` is then zero.

## Heat (`ThermalModel`)

The thermal sampler reads vanilla thermoregulator telemetry:
- core temperature, body heat delta/rate, and heat generation;
- skin temperature, perspiration, vasodilation, fluid demand, and shivering;
- external air and air-with-wind temperature;
- effective UI insulation and wind resistance for each thermal node.

Node insulation and wind resistance already reflect vanilla's clothing
coverage, layers, condition, holes, and wetness. AMS averages each signal by
the node's `getSkinSurface()` share so small regions do not count as much as
large ones.

```lua
thermalResistance = 0.70 * insulationUI + 0.30 * windResistanceUI

peripheralHeat = 0.22*skinHot + 0.18*perspiration
               + 0.08*vasodilation + 0.06*fluidDemand
coreEvidence   = 0.32*bodyHeat + 0.30*coreHeat
               + 0.14*coreTrend + 0.12*heatGeneration

ambientContext = clamp((ambientAir - 22) / (38 - 22), 0, 1)
contextualPeripheral = peripheralHeat * (0.06 + 0.94*ambientContext)
hotDrive = clamp(contextualPeripheral + 0.35*coreEvidence, 0, 1)
```

Peripheral cooling effort is contextualized by ambient temperature. Core and
body-heat signals can escalate established evidence, but no single saturated
field can make ordinary summer clothing look like severe armor heat burden.

`hotPressure` is an asymmetric EMA advanced by elapsed game minutes. Its
per-minute alpha is `0.55` while rising and `0.38` while falling. A new state
initializes from `coreHeat`, preventing one short positive body-heat sample
from being treated as established heat strain.

```lua
pressureNorm = clamp((hotPressure - 0.18) / 0.82, 0, 1)
thermalStrainScale = smoothstep(pressureNorm)
heat = clamp(thermalResistance * thermalStrainScale, 0, 1)
```

`heat` is the share of full heat stress the worn insulation is responsible
for. It feeds the endurance scales below.

Cold need is the maximum normalized signal from negative body heat delta, core
temperature below `36.90C`, and shivering. When cold need reaches `0.16`, AMS
records `coldSuitability = thermalResistance * (1 - shivering)` for diagnostics
only; AMS applies neither a cold penalty nor a protective endurance bonus.

When thermoregulator telemetry is unavailable, thermal state is marked
unavailable and `heat` is zero. Disabling the thermal model also makes `heat`
zero.

## Sleep Penalty (`SleepModel`)

Only rigid (stiff) gear matters while asleep:

```lua
penaltyFraction = EnableSleepPenaltyModel and min(SleepPenaltyMax, rigidKg * SleepPenaltyPerRigidKg) or 0   -- 0.5 cap, 0.025/kg
```

`SleepModel.step` runs on every authoritative tick:

- While asleep, and asleep on the previous tick, it measures vanilla's fatigue
  recovery since the last observation. It then adds back
  `recovered * penaltyFraction` as fatigue. Rising fatigue is never penalized.
- The penalized value becomes the next baseline.
- When CMS advertises `fatigue_coordinator`, AMS writes no fatigue. CMS reads
  the fraction through the `computeSleepPenaltyContribution` callback instead.
- The MP server syncs fatigue with `syncPlayerStats(player, 16)` after a write.

Sleep planning, wake time, bed choice and bed quality are vanilla's.
`estimateSleepPlannerPenalty` exposes the same fraction to CMS's planner.

## Activity and Posture (`Environment`)

- `resolveActivity(player)`: `sleep` > `sprint` > `run` > `walk` > `idle`.
- `getPostureLabel(player)`: `sleep`, `sit_vehicle`, `sit` (ground, furniture
  or resting), or `stand`. This mirrors vanilla's posture split in
  `IsoPlayer.updateEndurance`.
- `isResting(posture)`: true for `sit` and `sit_vehicle`.

## Muscle Strain Overlay (`Strain`)

Eligible weapons are melee weapons that use endurance: not bare hands, not
ranged or aimed firearms.

```lua
t     = clamp((armKg - MuscleStrainArmKgStart) / (MuscleStrainArmKgFull - MuscleStrainArmKgStart), 0, 1)   -- 1 kg .. 8 kg
extra = MuscleStrainMaxExtra * t * sqrt(t)                                                                 -- 0.15, clamped 0..0.35
```

The overlay is applied once per swing via
`player:addCombatMuscleStrain(weapon, 1, extra)`. It is skipped when vanilla's
`muscleStrainFactor` sandbox value is zero or below.

## Custom Body Locations (`SlotCompat`)

Registered custom locations:
- `ams:shoulderpad_left`
- `ams:shoulderpad_right`
- `ams:sport_shoulderpad`
- `ams:sport_shoulderpad_on_top`
- `ams:forearm_left`
- `ams:forearm_right`
- `ams:cuirass`
- `ams:torso_extra_vest_bullet`

Compatibility work:
- custom<->vanilla exclusivity
- custom<->custom exclusivity
- hideModel parity rules
- render index placement near matching vanilla locations

## Speed Rebalance and Wearable Discomfort

At boot `SpeedRebalance`:

- caches each wearable's original `DiscomfortModifier` in
  `ArmorMakesSense._originalDiscomfort` and sets it to `0.00`. The burden model
  reads the cached value as bulk, so vanilla's accumulating discomfort would
  otherwise double-count;
- sets `CombatSpeedModifier` by one rule: swing-chain locations lose 1% per kg
  of burden, capped at 5%; everything else swings at full speed;
- leaves `RunSpeedModifier` alone, because vanilla does not read it for
  movement;
- applies the AMS body-location reslots.

Re-application is idempotent. AMS never clamps the live `DISCOMFORT` stat, so
non-clothing discomfort (bad beds, wetness, temperature, corpse dragging,
vehicle over-encumbrance) stays vanilla.

## Configuration Defaults (`ArmorMakesSense.DEFAULTS`)

| Key | Default | Sandbox |
|---|---|---|
| `PhysicalLoadScale` | 1.0 | yes (0–3) |
| `EnableThermalModel` | true | yes |
| `EnableBreathingModel` | true | yes |
| `EnableMuscleStrainModel` | true | yes |
| `EnableSleepPenaltyModel` | true | yes |
| `BurdenItemMassAllowanceKg` | 0.5 | |
| `BurdenBulkPerRunPenalty` | 6.0 | |
| `BurdenBulkPerDiscomfort` | 4.0 | |
| `BurdenClothingAllowanceKg` | 3.5 | |
| `BodyMassMinKg` / `BodyMassMaxKg` | 50 / 90 | |
| `StrengthFactorBase` / `StrengthFactorPerLevel` | 1.3 / 0.06 | |
| `WalkRegenLoadWeight` / `WalkRegenFloor` | 2.0 / −0.5 | |
| `StandRegenLoadWeight` | 1.0 | |
| `DrainLoadWeight` | 1.0 | |
| `ThermalRegenPenaltyMax` / `ThermalDrainWeight` | 0.5 / 0.25 | |
| `BreathingEffortOnset` / `BreathingDrainWeight` | 0.20 / 0.35 | |
| `MuscleStrainMaxExtra` | 0.15 | |
| `MuscleStrainArmKgStart` / `MuscleStrainArmKgFull` | 1.0 / 8.0 | |
| `SleepPenaltyMax` / `SleepPenaltyPerRigidKg` | 0.5 / 0.025 | |
| `MaxStepMinutes` | 30 | |
