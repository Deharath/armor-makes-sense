# Armor Makes Sense - Runtime Reference

## Client Runtime Wiring

`Bootstrap.resolveClientRole()` requires the PZ `isClient()` role detector.
`Bootstrap.registerClientRuntime()` then registers exactly one client runtime:

- `singleplayer`: `Core.Runtime`
- `multiplayer`: `ArmorMakesSense.MPClientRuntime`

Loading the MP client module does not register events or initialize player
state. Development builds add their excluded benchmark handlers after the
production role has been selected.

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

The singleplayer `Runtime.registerEvents` path:
- requires `Events.EveryOneMinute.Add`
- also hooks `OnPlayerUpdate` and `OnPlayerAttackFinished` when available
- requires `getPlayer`

Missing runtime prerequisites leave the client runtime disabled for that session.

The MP registration path requires its server-command, connection,
create-player, clothing-update, and minute events. The MP runtime imports the
shared client UI and options modules directly for installation and invalidation.

## Per-Minute and Per-Frame Loops

`EveryOneMinute` path:
- `tickPlayer(player)`

`OnPlayerUpdate` path:
- sleep-time per-frame `tickPlayer`

Development builds register separate benchmark and environment-lock handlers
from `client/testing/ArmorMakesSense_00_DevBootstrap.lua`. Production runtime
handlers do not inspect or mutate development state.

## Tick Pipeline (`Tick.tickPlayer`)

Called once per game minute from `EveryOneMinute` and per-frame during sleep from `OnPlayerUpdate`.

1. `ensureState(player)` and `getOptions()`
2. `UI.update(player, nil, options)`
3. `runPlayerStartupChecks(player)`
4. shared elapsed-time accumulation and active catch-up capping
5. worn-profile, activity, and posture sampling: `computeWornProfile`,
   `resolveActivity`, and `getPostureLabel`
6. `UI.update(player, profile, options)`
7. `Simulation.advance()` applies bounded sleep slices and, while awake,
   endurance slices

Profile, activity, and posture are sampled once outside the catch-up slice loop.
The activity sampler reads only live movement state and resolved options; it has
no combat latch, authority state, world-time input, or mutable module context.

## Shared Simulation Advance

`ArmorMakesSense_Simulation.lua` is context-free. Both SP and the MP server use
it for:

- elapsed-time accumulation into `pendingCatchupMinutes`;
- the one-minute cap and live-endurance anchor for stale active catch-up;
- `DtMaxMinutes` slicing and `DtCatchupMaxSlices` limits;
- sleep-before-endurance model ordering;
- structured attempted, committed, discarded, failure, and abort results.

The MP server supplies incident capture and snapshot projection as its awake
per-slice callback. SP needs no callback. Both authorities use the same
sleep-only policy without an endurance callback; sleep fatigue remains
authority-owned while MP wall-clock transport throttles stay in the server
coordinator.

All production client and shared gameplay modules are free of mutable runtime
contexts. They require their collaborators directly. Tests use real module
contracts with small player/stat fixtures and focused method substitution
instead of replacing a module-wide dependency table.

## Combat Event Path

`OnPlayerAttackFinished` applies strain overlay when all runtime guards pass:
- singleplayer runtime selected and active (`isRuntimeDisabled == false`)
- attacker is non-nil
- attacker identity matches `getLocalPlayer()`
- `options.EnableMuscleStrainModel` is enabled
- event supplies a non-nil eligible melee weapon

Combat events do not alter AMS activity state or apply a timed endurance drain.
They apply one armor strain overlay per completed swing. Vanilla owns melee
stamina loss, attack metabolism, and hit-count-dependent base muscle strain.
AMS breathing retains vanilla's smoothed metabolic rate for combat and other
work, so those activities need no AMS combat latch or remembered activity state.

## Option Resolution and Precedence

Both SP and MP authority use `Options.get()` with this precedence:
1. `ArmorMakesSense.DEFAULTS`
2. `SandboxVars.ArmorMakesSense`

The resolver returns a fresh table and accepts overrides only for known keys,
using the default value's type to parse each override.

## Transient Singleplayer State

`ArmorMakesSense_RuntimeState.lua` holds SP state in a weak-key table indexed by
player identity. The state is session-only and includes:

- `lastUpdateGameMinutes`
- `pendingCatchupMinutes`
- `lastEnduranceObserved`
- `uiRuntimeSnapshot`
- `sleepSnapshot`, `wasSleeping`
- `thermalModelState`

Development builds add test locks, gear profiles, and the compact benchmark
handle to this transient SP state. The obsolete saved AMS blob is deleted on
first player access and is never migrated.

## Armor Classification (`ArmorClassifier`)

Signals:
- defense:
  - `scratch * 0.30`
  - `bite * 0.75`
  - `bullet * 1.25`
  - `neck * 0.45`
- protective evidence from tags, display category, blood clothing cues, keywords, and location hints

Decision gates:
- civilian floor: no indicators + `weight < 1.5` + `discomfort <= 0.05` => not armor
- strong defense (`defScore >= 8` or `bullet >= 1` or `bite >= 4` or `scratch >= 8`) => armor
- protective tag => armor
- keyword match + (`weight >= 1.2` or medium defense or `discomfort > 0.15`) => armor
- location match + strong defense + `weight >= 1.0` => armor

## Wearable Burden Model (`LoadModel.itemToBurdenSignal`)

Inputs:
- defense stats and cached original discomfort
- run/combat speed modifiers
- absent run/combat modifiers resolve to the neutral multiplier `1.0`; they do
  not imply complete movement loss
- vanilla worn encumbrance-equivalent weight (`equipped -> actual -> legacy`);
  `getEquippedWeight()` is intentionally preferred because the formulas were
  calibrated against vanilla's `0.3` equipped/worn multiplier, not raw mass
- classifier outputs
- original run/combat modifiers cached before AMS applies direct movement
  overrides

Explicit third-party tags:
- `AMSIncludeBurden`: include a cosmetic or wearable container
- `AMSExcludeBurden`: exclude a wearable
- `AMSArmor`: force the armor-like rigidity category

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
- `gasmasknofilter`, `respiratornofilter`, and `scbanotank` explicitly select
  the no-filter state even when the item type does not contain `nofilter`
- keyword identity matches include `gasmask`, `respirator`, `weldingmask`,
  `hazmat`, `dustmask`, `surgicalmask`, and `bandanamask`
- generic `head` / `neck` slots do not contribute breathing load by themselves

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

Mask slots suppress ordinary physical burden. Their effective insulation and
wind resistance remain represented by vanilla thermoregulator nodes.

Rigidity split:
- non-armor rigidity: `weight * 5 + discomfort * 12`
- armor rigidity: `discomfort * 16 + defenseScore * 0.60 + weight * 3.5`

Per-item clamps:
- `physicalLoad`: `0..28`
- `airflowResistance`: `0..8` (armor) / `0..12` (non-armor path)
- `sealedRestriction`: `0..1`
- `rigidityLoad`: `0..64`

## Worn-Gear Analysis (`LoadModel.analyzeWornGear`)

One traversal of `player:getWornItems()` produces:

- `profile`: aggregate gameplay totals;
- `rows`: normalized rows for every worn item, including excluded items with zero signals;
- `costDrivers`: rows at or above the physical-load display threshold;
- `equipmentSignature` and `wornCount`: stable incident-trace identity.

UI, support reports, and MP authority consume this canonical result instead of
maintaining separate worn-item collectors. `computeWornProfile(player)` returns
`analyzeWornGear(player).profile`.

### Profile Aggregation

Across worn items:
- sum channels: `physical`, `airflow`, `rigidity`
- maximum channel: `sealedRestriction`
- `swingChainLoad`: shoulder/forearm/elbow/hand/arm locations with discomfort scaling
- `rigidityLoad`: per-item rigidity weighted by sleep-contact surface
- `driverCount`: items meeting the physical cost-driver display threshold

Sleep-contact weights:
- torso/back/chest/cuirass = `1.0`
- shoulder/hip/thigh/leg/belt = `0.5`
- forearm/hand/elbow/shin/calf/foot/shoe = `0.15`
- mask/head/neck/eye/ear = `0.0`
- unknown slots = `0.7`

```lua
discFactor = clamp(0.5 + discomfort * 5.0, 0.25, 3.0)
swingChain += physicalLoad * discFactor
```

Aggregate clamps:
- `physical/upperBody/swingChain/rigidity`: `0..600`
- `airflow`: `0..30`
- `sealedRestriction`: `0..1`

## Endurance / Thermal / Breathing Physiology (`Physiology`)

### Effective Load Composition

```lua
effectiveLoad = physicalLoad + thermalContribution + breathingContribution
thermalContribution = thermalResistance * thermalStrainScale * ThermalContributionMax
```

### Breathing Effort

Breathing effort combines vanilla `Thermoregulator.getMetabolicRate()` with an
immediate floor from AMS's existing native movement label. PZ's public
`getMetabolicTarget()` cannot be sampled here: vanilla resets that scratch value
to `-1` at the end of every thermoregulator update, before Lua events can read
it. Missing rate telemetry falls back to the vanilla rest value `1.5`.

```lua
movementDemand = ({ walk = 3.1, run = 6.9, sprint = 9.5 })[activityLabel] or 1.5
metabolicDemand = max(metabolicRate, movementDemand)
metabolicNorm = clamp((metabolicDemand - 1.5) / (9.5 - 1.5), 0, 1)
effortRamp = smoothstep01((metabolicNorm - BreathingEffortOnset) / (1 - BreathingEffortOnset))
```

The `1.5` and `9.5` anchors are vanilla's default and 15 km/h metabolic rates.
The default onset `0.20` is vanilla's 5 km/h walking rate (`3.1` MET), so
walking remains free while harder work ramps smoothly toward sprint effort.
The movement floor makes ventilation react on the next AMS update rather than
waiting several minutes for the thermal rate to converge. The rate can still
raise demand for attacks, work, carried capacity, energy, and endurance through
vanilla's own model. AMS adds no attack probe or combat-specific demand state.

### Breathing Contribution

```lua
dynamicLoad    = airflowResistance * BreathingDynamicLoadWeight * effortRamp
sealedDynamic  = airflowResistance * BreathingSealedDynamicLoadWeight * effortRamp * sealedRestriction
breathingContribution = dynamicLoad + sealedDynamic

effectiveLoad = effectiveLoad + breathingContribution
```

Airflow resistance is additive across worn respiratory items. Sealed
restriction is aggregated by maximum, so stacking unsealed respirators cannot
create a sealed effect. Contribution is monotonic: more airflow resistance can
never produce less breathing burden at the same effort and seal state.

### Thermal Pressure Model

The thermal sampler reads vanilla thermoregulator telemetry:
- core temperature and body heat delta;
- shivering from the negative secondary heat balance;
- effective insulation and wind resistance for each thermal node.

Node insulation and wind resistance already reflect vanilla's clothing
coverage, layers, condition, holes, and wetness. AMS averages each signal by
the node's `getSkinSurface()` share so small regions do not count as much as
large ones.

```lua
insulationNorm = clamp((insulation - 0.10) / 0.30, 0, 1)
windNorm       = clamp((windResistance - 0.08) / 0.30, 0, 1)
thermalResistance = 0.70 * insulationNorm + 0.30 * windNorm

heatFlow = clamp(bodyHeatDelta / 0.55, 0, 1)
coreHeat = clamp((coreTemp - 37.55) / 1.20, 0, 1)
hotDrive = max(heatFlow, coreHeat)
```

`hotPressure` is an asymmetric EMA advanced by elapsed game minutes. Its
per-minute alpha is `0.55` while rising and `0.38` while falling. A new state
initializes from `coreHeat`, preventing one short positive body-heat sample
from being treated as established heat strain.

```lua
pressureNorm = clamp((hotPressure - 0.18) / 0.82, 0, 1)
thermalStrainScale = smoothstep(pressureNorm)
thermalContribution = thermalResistance * thermalStrainScale * ThermalContributionMax
```

Cold need is the maximum normalized signal from negative body heat delta, core
temperature below `36.90C`, and shivering. When cold need reaches `0.16`, AMS
reports `coldSuitability = thermalResistance * (1 - shivering)`. This is a UI
and diagnostic signal only; AMS applies neither a cold penalty nor a protective
endurance bonus.

When thermoregulator telemetry is unavailable, thermal state is marked
unavailable and contributes zero. Disabling the thermal model also makes its
contribution zero.

Runtime snapshot thermal state:
- hot if `hotPressure > 0.24`
- cold-helpful if `coldSuitability > 0.45`
- otherwise neutral

### Endurance Regen Throttling

Activation:
- `loadNorm = clamp(softNorm(effectiveLoad - ArmorLoadMin, 50.0, 2.5), 0, 2.8)`

```lua
postureScale    = 0.90 or 1.00
topoffScale     = clamp(0.55 + (1 - endurance) * 0.45, 0.55, 1.0)
regenActivityScale = 1.0 / 0.70 / 0.40

regenPenalty = clamp(
    EnduranceRegenPenalty * (0.45 + 0.35*loadNorm)
        * postureScale * topoffScale * regenActivityScale * activityLoadScale,
    0, 0.85
)
controlled = previous + naturalDelta * (1 - regenPenalty)
```

### Endurance Drain

```lua
activityLoadScale = clamp(0.55 + 0.45 * activityFactor, 0.45, 1.85)
drainPerMinute = BaseEnduranceDrainPerMinute * (1 + 1.6*loadNorm) * activityDrainScale * activityLoadScale
drainApplied   = drainPerMinute * dtMinutes
```

Activity drain scale:
- walk: `0.06`, `0.02`, or `0` depending on endurance/env/load conditions
- run: `0.335`
- sprint: `0.58`

`dtMinutes <= 0` samples only telemetry/snapshot fields. It does not throttle
regen, apply drain, call compat endurance drain, or write the live endurance
stat.

When `EnableThermalModel` is disabled, thermal contribution is `0`.

### Idle Recovery Bounds

During vanilla idle recovery (`naturalDelta > 0`):
- `controlled >= previous`
- `controlled <= endurance`

### Final Endurance Correction

- clamp to `0..1`
- write threshold: `0.0002`

## Sleep Penalty (`applySleepTransition`)

Sleep start stores rigidity, bed type, start time, and fatigue in
`state.sleepSnapshot`.

`SleepModel` converts normalized `{fatigue, traits, bedType, rigidity, minutes}`
into a named result containing vanilla recovery, penalty fraction, and extra
fatigue:

```lua
rigidityNorm = softNorm(rigidityLoad, 80.0, 2.0)
fatigueScale = max(0.1, 1 - fatigue)
counteractRatePerHour = rigidityNorm * SleepRigidityFatigueRate * fatigueScale
penaltyFraction = clamp(counteractRatePerHour / vanillaRecoveryRatePerHour, 0, 0.95)
extraFatigue = vanillaRecoveredFatigue * penaltyFraction
```

`vanillaRecoveryRatePerHour` accounts for fatigue, bed quality, Insomniac,
Night Owl, Needs Less Sleep, and Needs More Sleep. Standalone AMS writes the
extra fatigue during sleep. When CMS owns fatigue coordination or the code is
running on an MP client, AMS returns the penalty fraction without writing the
stat locally.

The standalone fatigue write is monotonic: the `0.85` armor-penalty cap never
lowers a player whose current fatigue is already at or above that value.

The sleep hook wraps vanilla planning rather than copying
`onSleepWalkToComplete`. Vanilla owns safety checks, actions, sounds, fades, and
sleep startup; AMS adjusts only the resulting wake duration and MP session
metadata. When vanilla delegates an allowed multiplayer sleep to the server,
AMS also skips local `SleepingEvent` initialization.

Wake processing clears `sleepSnapshot`. The MP server also reconciles bed-based
wake adjustment when required by the shared compatibility contract.

## Activity and Posture Sampling (`Environment`)

`Environment.resolveActivity(player, options)`:
- priority: sleep > sprint > run > walk > idle;
- returns one `{label, factor}` result;
- maps idle/walk/run/sprint to the configured activity factors; sleep returns
  factor `0`.

`Environment.getPostureLabel(player)`:
- returns `"sleep"`, `"sit_ground"`, `"sit_vehicle"`, or `"stand"`

## Muscle Strain Overlay (`Strain`)

Eligibility (`isMeleeStrainEligible`):
- weapon exists
- weapon is not bare hands
- weapon uses endurance
- weapon is not ranged/aimed firearm

Extra strain:

```lua
load = clamp(profile.swingChainLoad or profile.physicalLoad, 0, 600)
t    = clamp((load - MuscleStrainLoadStart)/(MuscleStrainLoadFull - MuscleStrainLoadStart), 0, 1)
extra = MuscleStrainMaxExtra * (t * sqrt(t))
```

- `MuscleStrainMaxExtra`: `0..0.35`
- sandbox `muscleStrainFactor <= 0` yields zero overlay contribution
- applied once per event via `player:addCombatMuscleStrain(weapon, 1, extra)`
- SP and MP call the same three-argument application policy; event delivery is
  the attack proof, while vanilla owns its separate hit-count-dependent strain

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

`SpeedRebalance`:
- caches original non-zero discomfort in `ArmorMakesSense._originalDiscomfort`
- sets `DiscomfortModifier = 0.00` for known overrides and global wearables
- normalizes run/combat speed modifiers for curated gear
- applies slot reslots to AMS custom locations

Runtime behavior:
- AMS does not clamp the live `DISCOMFORT` stat; vanilla non-clothing discomfort
  sources such as bad sleep surfaces, wetness, temperature moodles, dragging
  corpses, and vehicle over-encumbrance remain active.

## Configuration Defaults (`ArmorMakesSense.DEFAULTS`)

- `ArmorLoadMin = 5.0`
- `BaseEnduranceDrainPerMinute = 0.0033`
- `EnduranceRegenPenalty = 0.45`
- `EnableThermalModel = true`
- `EnableMuscleStrainModel = true`
- `EnableSleepPenaltyModel = true`
- `MuscleStrainMaxExtra = 0.15`
- `MuscleStrainLoadStart = 3.0`
- `MuscleStrainLoadFull = 22.0`
- `ThermalContributionMax = 14.0`
- `BreathingEffortOnset = 0.20`
- `BreathingDynamicLoadWeight = 0.70`
- `BreathingSealedDynamicLoadWeight = 1.00`
- `SleepRigidityFatigueRate = 0.0045`
- `ActivityIdle = 0.35`
- `ActivityWalk = 0.75`
- `ActivityJog = 1.00`
- `ActivitySprint = 1.35`
- `DtMaxMinutes = 3`
- `DtCatchupMaxSlices = 240`
