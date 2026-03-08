# Armor Makes Sense — Runtime Reference (v1.1.4)

_As of March 7, 2026_  
`SCRIPT_VERSION=1.1.4`  
`SCRIPT_BUILD=ams-b42-2026-03-07-v114`

## Client Runtime Wiring

`ArmorMakesSense_SpeedRebalance.lua` binds to:
- `Events.OnGameBoot`
- `Events.OnMainMenuEnter`
- `Events.OnGameStart`

Each run:
- applies per-item speed overrides
- zeroes script discomfort on known gear
- zeroes discomfort globally for wearable script items
- applies AMS body-location reslots

`ArmorMakesSense_SlotCompat.lua` registers custom body locations and compatibility rules at module load.

`Runtime.registerEvents`:
- requires `Events.EveryOneMinute.Add`
- also hooks `OnPlayerUpdate`, `OnWeaponSwing`, and `OnPlayerAttackFinished` when available
- requires `getPlayer`

Missing runtime prerequisites leave the client runtime disabled for that session.

## Per-Minute and Per-Frame Loops

`EveryOneMinute` path:
- `tickPlayer(player)`
- discomfort invariant (`setDiscomfort(0.0)`)
- benchmark runner tick

`OnPlayerUpdate` path:
- minute-throttled discomfort invariant
- benchmark runner tick
- sleep-time per-frame `tickPlayer`
- active test-lock overrides

## Tick Pipeline (`Tick.tickPlayer`)

Called once per game minute from `EveryOneMinute` and per-frame during sleep from `OnPlayerUpdate`.

1. `ensureState(player)` and `getOptions()`
2. `UI.update(player, nil, options)`
3. `runPlayerStartupChecks(player)`
4. auto-runner phase read
5. `logWearChanges(player, state, options, nowMinutes)`
6. delta-time accumulation into `pendingCatchupMinutes`
7. test-lock enforcement
8. profile/environment sampling: `computeArmorProfile`, `getHeatFactor`, `getWetFactor`, `getActivityFactor`, `getActivityLabel`, `getPostureLabel`
9. `UI.update(player, profile, options)`
10. catch-up slice loop:
   - `applySleepTransition`
   - `applyEnduranceModel`
   - `updateRecoveryTrace`
   - auto-runner stat accumulation

Profile and environment are sampled once outside the catch-up slice loop.

## Combat Event Path

`OnPlayerAttackFinished` applies strain overlay when all runtime guards pass:
- singleplayer runtime active (`isRuntimeDisabled == false` and not multiplayer)
- attacker is non-nil
- attacker identity matches `getLocalPlayer()`
- `options.EnableMuscleStrainModel` is enabled
- weapon matches the equipped hand weapon (`getUseHandWeapon` or `getPrimaryHandItem`)

`OnWeaponSwing` is registered as a pass-through event hook.

## Option Resolution and Precedence

Client/SP (`State.getOptions()`) precedence:
1. `ArmorMakesSense.DEFAULTS`
2. `SandboxVars.ArmorMakesSense`

`DebugLogging` follows game debug mode (`isDebugEnabled()` / `getCore():isDebug*`).

## Persistent Per-Player State

State lives in `player:getModData()["ArmorMakesSenseState"]` and includes:
- `version` (`2`)
- `lastUpdateGameMinutes`
- `pendingCatchupMinutes`
- `lastDiscomfortSuppressMinute`
- `lastEnduranceObserved`
- `lastArmorLoad`
- `uiRuntimeSnapshot`
- `sleepSnapshot`, `wasSleeping`
- `recoveryTrace`
- `testLock`
- `autoRunner`
- `gearProfiles`
- `benchRunner`
- `recentCombatUntilMinute`
- `thermalModelState`

## Armor Classification (`ArmorClassifier`)

Signals:
- defense:
  - `scratch * 0.30`
  - `bite * 0.75`
  - `bullet * 0.35`
  - `neck * 0.45`
- thermal:
  - `thermalScore = insulation * 10 + wind * 8`
- protective evidence from tags, display category, blood clothing cues, keywords, and location hints

Decision gates:
- civilian floor: no indicators + `weight < 1.5` + `discomfort <= 0.05` => not armor
- strong defense (`defScore >= 8` or `bullet >= 1` or `bite >= 4` or `scratch >= 8`) => armor
- protective tag => armor
- keyword match + (`weight >= 1.2` or medium defense or `discomfort > 0.15`) => armor
- location match + strong defense + `weight >= 1.0` => armor

## Item Signal Model (`LoadModel.itemToArmorSignal`)

Inputs:
- defense stats and cached original discomfort
- insulation, wind, water
- run/combat speed modifiers
- weight (`equipped -> actual -> legacy`)
- classifier outputs

Exclusions:
- cosmetic items
- inventory containers

Derived penalties:
- `runPenalty = max(0, 1 - runSpeedMod)`
- `combatPenalty = max(0, 1 - combatSpeedMod)`
- shoe slots contribute `0` run penalty to load

Base formulas:

```lua
weightContrib = max(0, weight - 0.30) * 8.0
weightScale   = clamp(weight / 0.8, 0.15, 1.0)

physicalLoad =
  weightContrib
  + max(discomfort,0) * 12.0
  + runPenaltyForLoad * 42.0
  + combatPenalty * 24.0
  + defenseScore * 0.06 * weightScale

thermalLoad =
  (thermalScore * 0.72)
  + (max(discomfort,0) * 1.10)
  + (defenseScore * 0.16)
  + (runPenaltyForLoad * 10.0)
  + (combatPenalty * 7.0)
  + (max(water,0) * 0.25)
```

Breathing classification:
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
- keyword identity matches include `gasmask`, `respirator`, `weldingmask`, `hazmat`, `dustmask`, `surgicalmask`, `bandanamask`
- generic `head` / `neck` slots do not contribute breathing load by themselves

Class outputs:
- face covering: `0 breathing`, `0 thermal`
- respirator with filter: `3.30 breathing`, `1.35 thermal`
- respirator without filter: `0.90 breathing`, `0.45 thermal`
- sealed mask with filter: `3.75 breathing`, `1.35 thermal`
- sealed mask without filter: `1.35 breathing`, `0.45 thermal`
- sealed suit: `3.75 breathing`, `1.35 thermal`

Rigidity split:
- non-armor rigidity: `weight * 5 + discomfort * 12`
- armor rigidity: `discomfort * 16 + defenseScore * 0.60 + weight * 3.5`

Per-item clamps:
- `physicalLoad`: `0..28`
- `thermalLoad`: `0..20`
- `breathingLoad`: `0..8` (armor) / `0..12` (non-armor path)
- `rigidityLoad`: `0..64`

## Profile Aggregation (`LoadModel.computeArmorProfile`)

Across worn items:
- sum channels: `physical`, `thermal`, `breathing`, `rigidity`
- `upperBodyLoad`: all locations except clearly lower-body
- `swingChainLoad`: shoulder/forearm/elbow/hand/arm locations with discomfort scaling
- `rigidityLoad`: per-item rigidity weighted by sleep-contact surface

Sleep-contact weights:
- torso/back/chest/cuirass = `1.0`
- shoulder/hip/thigh/leg/belt = `0.5`
- forearm/hand/elbow/shin/calf/foot/shoe = `0.15`
- mask/head/neck/eye/ear = `0.0`
- unknown slots = `0.7`

```lua
discFactor = clamp(0.5 + discomfort * 5.0, 0.25, 3.0)
swingChain += physicalLoad * discFactor
combinedLoad = clamp(physical + thermal*0.45 + breathing*0.90, 0, 320)
```

Aggregate clamps:
- `physical/upperBody/swingChain/thermal/rigidity`: `0..600`
- `breathing`: `0..30`

## Endurance / Thermal / Breathing Physiology (`Physiology`)

### Effective Load Composition

```lua
effectiveLoad = massLoad + thermalContribution + breathingContribution
thermalContribution = wearabilityLoad * ThermalEnduranceWeight * thermalPressureScale
```

### Ventilation Demand

`resolveVentilationDemand`:
- activity-normalized demand in `0.20..0.90`
- label floors/caps:
  - walk: `<= 0.48`
  - combat: `>= 0.58`
  - run: `>= 0.62`
  - sprint: `>= 0.90`
- `isAttackStarted` floors demand to `BreathingCombatDemandFloor`
- final clamp: `0.15..1.0`

### Breathing Contribution

```lua
maskNorm   = clamp((breathingLoad - BreathingPenaltyLoadStart) / BreathingPenaltyLoadSpan, 0, 1)
sealedNorm = clamp((breathingLoad - BreathingSealLoadStart) / BreathingSealLoadSpan, 0, 1)
demandRamp = smoothstep01((ventDemand - threshold) / (1-threshold))

staticRelief   = min(breathingLoad, BreathingReliefMaxLoad) * BreathingStaticReliefWeight * maskNorm
dynamicLoad    = breathingLoad * BreathingDynamicLoadWeight * demandRamp * (0.35 + 0.65*maskNorm)
sealedDynamic  = breathingLoad * BreathingSealedDynamicLoadWeight * demandRamp * sealedNorm

effectiveLoad = max(0, effectiveLoad - staticRelief + dynamicLoad + sealedDynamic)
```

### Thermal Pressure Model

Thermal pressure uses thermoregulator telemetry when available:
- core and skin temperatures
- perspiration and shivering
- vaso state
- insulation, wind, wetness
- body heat delta, core trend, ambient context

Mechanics:
- asymmetric EMA smoothing
- hot and cold gates
- cold appropriateness reducing residual cold burden
- `thermalPressureScale` from smoothstep pressure
- `enduranceEnvFactor` clamped to `0.70..2.40`

Runtime snapshot thermal state:
- hot if `hotStrain > 0.15`
- cold-helpful if `coldAppropriateness > 0.30`
- otherwise neutral

### Endurance Regen Throttling

Activation:
- `loadNorm = clamp(softNorm(effectiveLoad - ArmorLoadMin, 50.0, 2.5), 0, 2.8)`

```lua
postureScale    = 0.90 or 1.00
topoffScale     = clamp(0.55 + (1 - endurance) * 0.45, 0.55, 1.0)
regenActivityScale = 1.0 / 0.70 / 0.40

regenPenalty = clamp(
    EnduranceRegenPenalty * (0.45 + 0.35*loadNorm) * envFactor
        * postureScale * topoffScale * regenActivityScale * activityLoadScale,
    0, 0.85
)
controlled = previous + naturalDelta * (1 - regenPenalty)
```

### Endurance Drain

```lua
activityLoadScale = clamp(0.55 + 0.45 * activityFactor, 0.45, 1.85)
drainPerMinute = BaseEnduranceDrainPerMinute * (1 + 1.6*loadNorm) * activityDrainScale * envFactor * activityLoadScale
drainApplied   = drainPerMinute * dtMinutes
```

Activity drain scale:
- walk: `0.06`, `0.02`, or `0` depending on endurance/env/load conditions
- combat: `0.20`
- run: `0.335`
- sprint: `0.58`

### Idle Recovery Bounds

During vanilla idle recovery (`naturalDelta > 0`):
- `controlled >= previous`
- `controlled <= endurance`

### Final Endurance Correction

- clamp to `0..1`
- write threshold: `0.0002`

## Sleep Penalty (`applySleepTransition`)

- sleep start snapshots `rigidityLoad`
- sleeping applies:

```lua
rigidityNorm = softNorm(rigidityLoad, 80.0, 2.0)
fatigueScale = max(0.1, 1 - fatigue)
counteract   = rigidityNorm * SleepRigidityFatigueRate * fatigueScale * dtMinutes / 60
setFatigue(min(0.85, fatigue + counteract))
```

- wake clears the sleep snapshot

## Recovery Trace (`Physiology.updateRecoveryTrace`)

Tracks idle endurance recovery telemetry while:
- player is idle
- player is awake
- endurance is below `0.985`

Recorded fields:
- `sampleMinutes`, `sitMinutes`, `standMinutes`
- `peakEndurance`, `lowEndurance`
- `startPhysicalLoad`, `startArmorPieces`

Termination:
- full recovery (`endurance >= 0.985`)
- non-idle activity

## Environment Sampling (`Environment`)

`Environment.getHeatFactor(player, options)`:
- thermoregulator-based hot pressure path
- core body temperature band alternate path
- returns `1.0 + (hotPressure * HeatAmplifierStrength)`

`Environment.getWetFactor(player, options)`:
- reads wetness `0..100`
- returns `1.0 + (wetNorm * WetAmplifierStrength)`

`Environment.getActivityLabel(player)`:
- priority: sprint > run > walk > combat (latched) > idle
- combat latch: attack 15 seconds, aiming 6 seconds

`Environment.getActivityFactor(player, options)`:
- maps to `ActivityIdle`, `ActivityWalk`, `ActivityJog`, `ActivitySprint`
- stationary attack-started or aiming uses `ActivityJog`

`Environment.getPostureLabel(player)`:
- returns `"sleep"`, `"sit_ground"`, `"sit_vehicle"`, or `"stand"`

## Muscle Strain Overlay (`Strain`)

Eligibility (`isMeleeStrainEligible`):
- weapon exists
- weapon is not bare hands
- weapon uses endurance
- weapon is not ranged/aimed firearm
- player is actively attacking melee unless bypassed

Extra strain:

```lua
load = clamp(profile.swingChainLoad or profile.upperBodyLoad or profile.physicalLoad, 0, 600)
t    = clamp((load - MuscleStrainLoadStart)/(MuscleStrainLoadFull - MuscleStrainLoadStart), 0, 1)
extra = MuscleStrainMaxExtra * (t * sqrt(t))
```

- `MuscleStrainMaxExtra`: `0..0.35`
- sandbox `muscleStrainFactor <= 0` yields zero overlay contribution
- applied via `player:addCombatMuscleStrain(weapon, hitCount, extra)`

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

## Speed Rebalance and Discomfort Suppression

`SpeedRebalance`:
- caches original non-zero discomfort in `ArmorMakesSense._originalDiscomfort`
- sets `DiscomfortModifier = 0.00` for known overrides and global wearables
- normalizes run/combat speed modifiers for curated gear
- applies slot reslots to AMS custom locations

Runtime invariant:
- `Runtime.enforceDiscomfortInvariant` clamps discomfort to zero at runtime

## Configuration Defaults (`ArmorMakesSense.DEFAULTS`)

- `ArmorLoadMin = 5.0`
- `BaseEnduranceDrainPerMinute = 0.0033`
- `EnduranceRegenPenalty = 0.45`
- `HeatAmplifierStrength = 0.25`
- `WetAmplifierStrength = 0.18`
- `EnableMuscleStrainModel = true`
- `EnableSleepPenaltyModel = true`
- `MuscleStrainMaxExtra = 0.15`
- `MuscleStrainLoadStart = 3.0`
- `MuscleStrainLoadFull = 22.0`
- `ThermalEnduranceWeight = 0.35`
- `BreathingDemandThreshold = 0.52`
- `BreathingCombatDemandFloor = 0.50`
- `BreathingPenaltyLoadStart = 1.20`
- `BreathingPenaltyLoadSpan = 2.20`
- `BreathingSealLoadStart = 3.45`
- `BreathingSealLoadSpan = 0.20`
- `BreathingReliefMaxLoad = 3.30`
- `BreathingStaticReliefWeight = 0.25`
- `BreathingDynamicLoadWeight = 5.10`
- `BreathingSealedDynamicLoadWeight = 29.00`
- `SleepRigidityFatigueRate = 0.0045`
- `ActivityIdle = 0.35`
- `ActivityWalk = 0.75`
- `ActivityJog = 1.00`
- `ActivitySprint = 1.35`
- `DtMaxMinutes = 3`
- `DtCatchupMaxSlices = 240`
