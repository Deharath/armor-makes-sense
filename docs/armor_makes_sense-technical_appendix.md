# Armor Makes Sense — Technical Appendix (v1.0.3)

_As of March 3, 2026_  
`SCRIPT_VERSION=1.0.3`  
`SCRIPT_BUILD=ams-b42-2026-03-03-v052`

## Scope

Armor Makes Sense (AMS) is Build 42, singleplayer-focused armor physiology. Hard dependency: `StarlitLibrary` (required in `mod.info`; provides the `onFillItemTooltip` event used for tooltip injection).

Runtime no-ops in multiplayer (`isClient()` or `isServer()`):
- `Runtime.onEveryOneMinute` returns early in MP.
- `Runtime.onPlayerUpdate` returns early in MP.
- `Combat.onPlayerAttackFinished` returns early in MP.

Core design intent:
- Replace vanilla discomfort gameplay pressure with physical costs.
- Keep discomfort pinned to zero while modeling:
  - endurance pressure,
  - thermal pressure,
  - breathing restriction,
  - melee muscle strain,
  - sleep recovery slowdown.

## Build Layout

- Mod root (`ArmorMakesSense/`): canonical metadata/assets (`mod.info`, `poster.png`, `ams_icon.png`).
- `common/`: source-of-truth Lua/translations/media.
- `42/`: override layer. Current state is `42/mod.info` only; it references root assets (`../poster.png`, `../ams_icon.png`).
- `42/media` currently has no active content.

## Boot, Wiring, and Runtime Guards

### Shared-time hooks

`ArmorMakesSense_SpeedRebalance.lua` binds to:
- `Events.OnGameBoot`
- `Events.OnMainMenuEnter`
- `Events.OnGameStart`

Each run:
- applies per-item speed overrides,
- zeroes script discomfort on known gear,
- zeroes discomfort globally for all wearable script items,
- applies custom AMS body-location reslots.

`ArmorMakesSense_SlotCompat.lua` runs at module load and registers custom body locations + compatibility rules.

### Client runtime registration

`Runtime.registerEvents`:
- requires `Events.EveryOneMinute.Add`
- also hooks `OnPlayerUpdate`, `OnWeaponSwing`, and `OnPlayerAttackFinished` when available
- startup checks also require `getPlayer` global.

If required checks fail, AMS sets runtime disabled and skips further lifecycle handling.

### Per-minute and per-frame loops

`EveryOneMinute` path:
- `tickPlayer(player)`
- force discomfort invariant (`setDiscomfort(0.0)` once/minute)
- benchmark runner tick

`OnPlayerUpdate` path:
- minute-throttled discomfort invariant
- benchmark runner tick
- while asleep: runs `tickPlayer` per-frame so sleep penalties apply during accelerated sleep windows
- applies active test-lock overrides

### Tick Pipeline (`Tick.tickPlayer`)

Called once per game minute (from `EveryOneMinute`) and per-frame while asleep (from `OnPlayerUpdate`). Full execution order:

1. **State + options**: `ensureState(player)`, `getOptions()`, cache debug/enable flags.
2. **UI layer update** (pre-loop): `UI.update(player, nil, options)` — installs tooltip/tab/clothing hooks on first call.
3. **Startup checks**: `runPlayerStartupChecks(player)` — verifies stat bindings on first tick.
4. **Auto-runner phase check**: reads autotest phase overrides if active.
5. **Wear debug**: `logWearChanges(player, state, options, nowMinutes)`.
6. **Time delta**: `elapsedMinutes = nowMinutes - state.lastUpdateGameMinutes`, accumulated into `pendingCatchupMinutes`.
7. **Test-lock enforcement**: if active and within time window, force wetness/bodyTemp; if expired, clear and reset.
8. **Profile + environment sampling** (once, before loop): `computeArmorProfile`, `getHeatFactor`, `getWetFactor`, `getActivityFactor`, `getActivityLabel`, `getPostureLabel`. Auto-runner may override activity/posture.
9. **UI layer update** (with profile): `UI.update(player, profile, options)`.
10. **Catchup slice loop** (up to `DtCatchupMaxSlices` iterations, each capped at `DtMaxMinutes`):
    - `applySleepTransition(player, state, options, dtMinutes, profile, heatFactor, wetFactor)`
    - `applyEnduranceModel(player, state, options, dtMinutes, profile, heatFactor, wetFactor, activityFactor, activityLabel, postureLabel)`
    - `updateRecoveryTrace(state, options, sliceNowMinutes, dtMinutes, profile, activityLabel, postureLabel, endurance)`
    - Auto-runner stat accumulation (if active).

Profile and environment are sampled once outside the loop (not per-slice). This is intentional -- re-sampling per-slice during catchup would read stale game state.

### Combat event path

`OnPlayerAttackFinished` applies strain overlay only when all checks pass:
- runtime enabled and SP (early return on `isRuntimeDisabled` or `isMultiplayer`),
- attacker is non-nil,
- attacker identity matches `getLocalPlayer()` (prevents processing NPC/remote attacks),
- muscle strain model enabled (`options.EnableMuscleStrainModel`),
- weapon is non-nil and matches currently equipped hand weapon (`getUseHandWeapon` or `getPrimaryHandItem`).

`OnWeaponSwing` is currently registered with a pass-through handler (no-op).

## Option Resolution and Precedence

`State.getOptions()` precedence order:
1. `ArmorMakesSense.DEFAULTS`
2. `SandboxVars.ArmorMakesSense` (typed conversion)
3. `PZAPI.ModOptions:getOptions("ArmorMakesSense")` (typed conversion)

Special rule:
- `DebugLogging` is **not** taken from mod options; it is forced from game debug mode (`isDebugEnabled()` / `getCore():isDebug*`).

## Persistent Per-Player State

State lives in `player:getModData()["ArmorMakesSenseState"]` and includes:
- `version` (currently `2`)
- `lastUpdateGameMinutes`
- `pendingCatchupMinutes`
- `lastDiscomfortSuppressMinute`
- `lastEnduranceObserved`
- `lastArmorLoad`
- `uiRuntimeSnapshot`
- `sleepSnapshot`, `wasSleeping`
- `recoveryTrace` — idle recovery session tracker (see Recovery Trace section)
- `testLock` — test automation overrides (`mode`, `wetness`, `bodyTemp`, `untilMinute`)
- `autoRunner` — autotest runner state (`active`, `runId`, `profile`, `index`, phase timing, stats, speed overrides)
- `gearProfiles` — cached gear profile data for test/bench use
- compact `benchRunner` runtime handle — only stores active flag, id, preset/label/mode, timing, and version info; legacy runtime blobs are purged on load
- `recentCombatUntilMinute` — combat latch expiry (set by Environment activity label, not persisted across sessions)
- `thermalModelState` — thermal EMA smoothing + signal gate state (hot/cold EMA, gate active flags, cache)

## Armor Classification (`ArmorClassifier`)

Signals:
- defense:
  - `scratch * 0.30`
  - `bite * 0.75`
  - `bullet * 0.35`
  - `neck * 0.45`
- thermal:
  - `thermalScore = insulation * 10 + wind * 8`
- protective evidence from:
  - tags (`gasmask`, `respirator`, `hazmatsuit`, `weldingmask`, `bulletproof`, etc.)
  - display category (`protectivegear`)
  - blood clothing cues (`helmet`/`mask`)
- keyword and location hint matches

Decision gates:
- civilian floor: no indicators + `weight < 1.5` + `discomfort <= 0.05` => not armor
- strong defense (`defScore >= 8` or `bullet >= 1` or `bite >= 4` or `scratch >= 8`) => armor
- protective tag => armor
- keyword match + (`weight >= 1.2` or medium defense or `discomfort > 0.15`) => armor
- location match + strong defense + `weight >= 1.0` => armor

## Item Signal Model (`LoadModel.itemToArmorSignal`)

Inputs:
- defense stats, discomfort (from cached original discomfort when available),
- insulation/wind/water,
- run/combat speed modifiers,
- weight (priority: equipped -> actual -> legacy),
- classifier outputs.

Exclusions:
- cosmetic items skipped,
- inventory containers skipped.

Derived penalties:
- `runPenalty = max(0, 1 - runSpeedMod)`
- `combatPenalty = max(0, 1 - combatSpeedMod)`
- shoe slots nullify run penalty contribution to load.

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

Breathing increments:
- breathing-tag hit: `+2.40 breathing`, `+0.90 thermal`
- mask name/location hit: `+0.90 breathing`, `+0.45 thermal`
- `maskeyes`/`maskfull`: `+0.45 breathing`
- helmet/head cue: `+0.30 breathing`

Armor/non-armor split:
- non-armor rigidity: `weight * 5 + discomfort * 12`
- armor rigidity: `discomfort * 16 + defenseScore * 0.60 + weight * 3.5`
- protective-tag bonus on armor items: `+0.90 physical`, `+0.60 thermal`

Mask slot handling:
- if location contains `mask`, force `physicalLoad=0`, `thermalLoad=0` (breathing path remains active).

Per-item clamps:
- `physicalLoad`: `0..28`
- `thermalLoad`: `0..20`
- `breathingLoad`: `0..8` (armor) / `0..12` (non-armor path)
- `rigidityLoad`: `0..64`

## Profile Aggregation (`LoadModel.computeArmorProfile`)

Across worn items:
- sum channels: `physical`, `thermal`, `breathing`, `rigidity`
- `upperBodyLoad`: includes locations unless clearly lower-body
- `swingChainLoad`: shoulder/forearm/elbow/hand/arm locations, scaled by discomfort factor:

```lua
discFactor = clamp(0.5 + discomfort * 5.0, 0.25, 3.0)
swingChain += physicalLoad * discFactor
```

Armor piece count:
- increments when item `physicalLoad >= 1.5`

Aggregate clamps:
- `physical/upperBody/swingChain/thermal/rigidity`: `0..600`
- `breathing`: `0..30`

Derived summary:

```lua
combinedLoad = clamp(physical + thermal*0.45 + breathing*0.90, 0, 320)
```

## Endurance / Thermal / Breathing Physiology (`Physiology`)

### Effective load composition

```lua
effectiveLoad = massLoad + thermalContribution + breathingContribution

thermalContribution = wearabilityLoad * ThermalEnduranceWeight * thermalPressureScale
```

Then breathing penalty modifies `effectiveLoad`.

### Ventilation demand

`resolveVentilationDemand`:
- starts from activity-normalized demand in `0.20..0.90` domain,
- label floors/caps:
  - walk: `<= 0.48`
  - combat: `>= 0.58`
  - run: `>= 0.62`
  - sprint: `>= 0.90`
- if `isAttackStarted`: floor to `BreathingCombatDemandFloor` (default `0.50`)
- final clamp: `0.15..1.0`

### Breathing load contribution

When `breathingLoad > 0`:

```lua
maskNorm   = clamp((breathingLoad - BreathingPenaltyLoadStart) / BreathingPenaltyLoadSpan, 0, 1)
sealedNorm = clamp((breathingLoad - BreathingSealLoadStart) / BreathingSealLoadSpan, 0, 1)
demandRamp = smoothstep01((ventDemand - threshold) / (1-threshold))  -- only above threshold

staticRelief   = min(breathingLoad, BreathingReliefMaxLoad) * BreathingStaticReliefWeight * maskNorm
dynamicLoad    = breathingLoad * BreathingDynamicLoadWeight * demandRamp * (0.35 + 0.65*maskNorm)
sealedDynamic  = breathingLoad * BreathingSealedDynamicLoadWeight * demandRamp * sealedNorm

effectiveLoad = max(0, effectiveLoad - staticRelief + dynamicLoad + sealedDynamic)
```

### Thermal pressure model

Uses thermoregulator telemetry when available (core/skin temps, perspiration, shivering, vaso state, insulation/wind, body heat delta, core trend, ambient, wetness). Key mechanics:
- asymmetric EMA smoothing:
  - hot: rise `0.55`, fall `0.20`
  - cold: rise `0.48`, fall `0.18`
- gates:
  - hot on/off: `0.08 / 0.04`
  - cold on/off: `0.07 / 0.03`
- cold appropriateness reduces residual cold burden under protective insulation conditions
- `thermalPressureScale` uses smoothstep on composite pressure
- `enduranceEnvFactor` is derived and clamped `0.70..2.40`

UI-facing thermal state in runtime snapshot:
- hot if `hotStrain > 0.15`
- cold-helpful if `coldAppropriateness > 0.30`
- else neutral

### Endurance regen throttling

Activation:
- `loadNorm = clamp(softNorm(effectiveLoad - ArmorLoadMin, 50.0, 2.5), 0, 2.8)`

If natural endurance delta is positive and load is active:

```lua
postureScale    = 0.90  -- if idle + sitting
                  1.00  -- if idle + standing
topoffScale     = clamp(0.55 + (1 - endurance) * 0.45, 0.55, 1.0)
regenActivityScale = 1.0  -- default
                     0.70 -- walk + stressed (envFactor >= 1.12 or endurance <= 0.58)
                     0.40 -- walk + non-stressed

regenPenalty = clamp(
    EnduranceRegenPenalty * (0.45 + 0.35*loadNorm) * envFactor
        * postureScale * topoffScale * regenActivityScale * activityLoadScale,
    0, 0.85
)
controlled = previous + naturalDelta * (1 - regenPenalty)
```

### Endurance drain

Non-idle only. Activity load scale (shared by regen and drain):

```lua
activityLoadScale = clamp(0.55 + 0.45 * activityFactor, 0.45, 1.85)
```

Activity drain scale:
- walk:
  - `0.06` if `(envFactor >= 1.18 OR endurance <= 0.60 OR enduranceMoodle >= 2) AND (loadNorm >= 2.0 OR envFactor >= 1.18)`
  - `0.02` if `envFactor >= 1.05 AND loadNorm >= 2.4 AND endurance <= 0.60`
  - `0` otherwise (walking in light armor produces no AMS drain)
- combat: `0.20`
- run: `0.335`
- sprint: `0.58`

Drain formula:

```lua
drainPerMinute = BaseEnduranceDrainPerMinute * (1 + 1.6*loadNorm) * activityDrainScale * envFactor * activityLoadScale
drainApplied   = drainPerMinute * dtMinutes
```

### Idle recovery safety clamp

When the player is idle and vanilla is naturally recovering endurance (`naturalDelta > 0`), AMS enforces two bounds:
- `controlled` never drops below `previous` (AMS cannot slow idle recovery below the previous tick's endurance),
- `controlled` never exceeds `endurance` (AMS cannot grant more than vanilla's natural recovery).

This guarantees AMS never makes standing-idle recovery slower than vanilla baseline.

### Final endurance correction

- clamp to `0..1`
- write only if change exceeds `0.0002`.

## Sleep penalty (`applySleepTransition`)

- On sleep start: snapshot `rigidityLoad`.
- While asleep:

```lua
rigidityNorm = softNorm(rigidityLoad, 80.0, 2.0)
fatigueScale = max(0.1, 1 - fatigue)
counteract   = rigidityNorm * SleepRigidityFatigueRate * fatigueScale * dtMinutes / 60
setFatigue(min(0.85, fatigue + counteract))
```

- On wake: clears sleep snapshot.

## Recovery Trace (`Physiology.updateRecoveryTrace`)

Tracks idle endurance recovery sessions for debug telemetry. Activates when the player is idle, not sleeping, and endurance is below `0.985`. While active, it accumulates:
- `sampleMinutes`, `sitMinutes`, `standMinutes` (posture breakdown)
- `peakEndurance`, `lowEndurance` (range during recovery)
- `startPhysicalLoad`, `startArmorPieces` (load at session start)

The trace terminates on:
- full recovery (`endurance >= 0.985`) — logs completion with duration/posture stats,
- non-idle activity — logs early stop with reason.

This is a debug/telemetry feature only; it does not affect gameplay.

## Environment Sampling (`Environment`)

`Environment.getHeatFactor(player, options)`:
- Attempts thermoregulator-based hot pressure: reads average skin temperature, perspiration, vasodilation, fluids multiplier, and core temperature from thermoregulator nodes.
- Falls back to core body temperature band scaling if thermoregulator is unavailable.
- Returns `1.0 + (hotPressure * HeatAmplifierStrength)`.

`Environment.getWetFactor(player, options)`:
- Reads wetness (0-100), normalizes, returns `1.0 + (wetNorm * WetAmplifierStrength)`.

`Environment.getActivityLabel(player)`:
- Priority: sprint > run > walk > combat (latched) > idle.
- Combat latch: `isAttackStarted` holds combat label for 15 seconds, `isAiming` holds for 6 seconds. Sprint/run/walk clear the latch.

`Environment.getActivityFactor(player, options)`:
- Maps activity to the corresponding `Activity*` option value (`ActivityIdle`, `ActivityWalk`, `ActivityJog`, `ActivitySprint`).
- Attack-started or aiming while stationary maps to `ActivityJog`.

`Environment.getPostureLabel(player)`:
- Returns `"sleep"`, `"sit_ground"`, `"sit_vehicle"`, or `"stand"`.

## Muscle Strain Overlay (`Strain`)

Eligibility (`isMeleeStrainEligible`):
- weapon exists,
- not bare hands,
- uses endurance,
- not ranged/aimed firearm,
- player is actively attacking melee (unless explicitly bypassed).

Extra strain amount:

```lua
load = clamp(profile.swingChainLoad or profile.upperBodyLoad or profile.physicalLoad, 0, 600)
t    = clamp((load - MuscleStrainLoadStart)/(MuscleStrainLoadFull - MuscleStrainLoadStart), 0, 1)
extra = MuscleStrainMaxExtra * (t * sqrt(t))
```

- `MuscleStrainMaxExtra` hard-clamped to `0..0.35`.
- If sandbox `muscleStrainFactor <= 0`, overlay is disabled.
- Applies via `player:addCombatMuscleStrain(weapon, hitCount, extra)`.

## UI Details and Thresholds

### Tooltip rows

Injected through Starlit `onFillItemTooltip` listener.

Display conditions:
- Burden row if `physicalLoad >= 1.5` (bar normalized to `TOOLTIP_BAR_MAX=28`)
- Breathing row if `breathingLoad >= 1.2`
  - `1.2..3.44`: Restricted
  - `>=3.45`: Heavily Restricted

Shoulderpad tooltip cleanup removes stale vanilla backpack-conflict rows.

### Burden panel tiers

Panel burden tier thresholds (`physicalLoad`):
- `<7`: Negligible
- `<20`: Light
- `<45`: Moderate
- `<75`: Heavy
- otherwise: Extreme

Panel thermal labels use runtime snapshot:
- Burdensome if `hotStrain > 0.15`
- Helpful if `coldAppropriateness > 0.30`
- else Neutral

Sleep estimate shown when `rigidityLoad >= 10` using:

```lua
rigidityNorm = rigidity / (rigidity + 80.0) * 2.0
sleepPct = floor(rigidityNorm * 6.75 + 0.5)
```

`Cost Drivers` are worn items with `physicalLoad >= 1.5`, sorted descending.

Clothing change detection:
- `Events.OnClothingUpdated` hook marks the burden panel dirty for immediate re-render.

Tab behavior:
- attempts injection into character info tabs (patches `ISCharacterInfoWindow.createChildren`),
- retroactively attaches to any already-created instance,
- falls back to standalone `AMSBurdenWindow` on injection failure.

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
- explicit custom<->vanilla and custom<->custom exclusivity sets,
- hideModel parity rules,
- render index placement near corresponding vanilla locations.

## Speed Rebalance and Discomfort Suppression

`SpeedRebalance` responsibilities:
- cache original non-zero discomfort by fullType in `ArmorMakesSense._originalDiscomfort`,
- set `DiscomfortModifier = 0.00` for known overrides and global wearables,
- normalize run/combat speed modifiers for curated gear list,
- apply slot reslot map to custom AMS locations.

Runtime invariant:
- discomfort is also clamped at runtime (`Runtime.enforceDiscomfortInvariant`) to ensure zero discomfort even if external systems mutate it.

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
- `SleepRigidityFatigueRate = 0.003`
- `ActivityIdle = 0.35`
- `ActivityWalk = 0.75`
- `ActivityJog = 1.00`
- `ActivitySprint = 1.35`
- `DtMaxMinutes = 3`
- `DtCatchupMaxSlices = 240`

## Context-Injection Architecture

All core and model modules use a shared context-injection pattern. Each module stores a local `C = {}` table and exposes `setContext(context)` to receive it. Internal functions access shared dependencies via `ctx("name")` which returns `C[name]`.

`ArmorMakesSense_ContextFactory.lua` builds the context table containing:
- shared utilities (`safeMethod`, `clamp`, `toBoolean`, `lower`, `log`, etc.),
- stat IO functions (`getEndurance`, `setEndurance`, `getFatigue`, `setFatigue`, etc.),
- environment readers (`getWorldAgeMinutes`, `getBodyTemperature`, `getWetness`, etc.),
- model entry points (`computeArmorProfile`, `itemToArmorSignal`, `getUiRuntimeSnapshot`, etc.),
- config references (`defaults`, `modKey`, `scriptVersion`, `scriptBuild`),
- lifecycle helpers (`ensureState`, `getOptions`, `isRuntimeDisabled`, `isMultiplayer`, etc.).

`ArmorMakesSense_ContextBinder.lua` iterates over all modules that expose `setContext` and injects the context from the factory.

`ArmorMakesSense_ContextRefs.lua` holds stable references to context entries for cross-module lookup without re-traversing the context table.

`ArmorMakesSense_Bootstrap.lua` provides two helpers:
- `bindApi(api, context)` — calls `setContext` and optional `bindGlobals` on a module.
- `registerRuntimeEvents(mod, runtime)` — delegates to `Runtime.registerEvents`.

## Module Inventory (Current Load Graph)

### Entry point
- `ArmorMakesSense_Main.lua` — boot facade: defines `SCRIPT_VERSION` / `SCRIPT_BUILD`, requires all modules in load order, builds the full context table via ContextFactory, wires all modules via ContextBinder/Bootstrap, registers lifecycle events, and exposes the public API surface.

### Shared
- `ArmorMakesSense_Config.lua` — `ArmorMakesSense.DEFAULTS` table (all tuning constants).
- `ArmorMakesSense_ModOptionsShared.lua` — optional PZ mod-options integration (declares sandbox/PZAPI option definitions).
- `ArmorMakesSense_ArmorClassifier.lua` — armor-vs-civilian classification: `computeArmorLikeSignals`, `evaluateArmorLike`, `hasAnyProtectiveTag`.
- `ArmorMakesSense_SlotCompat.lua` — registers custom body locations (`ams:*`), exclusivity rules, hideModel parity, render index placement.
- `ArmorMakesSense_SpeedRebalance.lua` — global discomfort zeroing, per-item speed overrides, slot reslots to AMS custom locations.

### Client core
- `ArmorMakesSense_Utils.lua` — shared utility functions: `safeMethod`, `clamp`, `softNorm`, `toBoolean`, `lower`, `containsAny`, logging helpers.
- `ArmorMakesSense_Environment.lua` — environment and activity sampling: `getHeatFactor` (thermoregulator-aware hot pressure), `getWetFactor`, `getActivityFactor`, `getActivityLabel` (with combat latch: attack 15s / aim 6s holdover), `getPostureLabel`.
- `ArmorMakesSense_LoadModel.lua` — item-to-load transformation (`itemToArmorSignal`) and profile aggregation (`computeArmorProfile`).
- `ArmorMakesSense_UI.lua` — tooltip injection (via Starlit `onFillItemTooltip`), burden panel/tab rendering, help window, `OnClothingUpdated` hook for UI refresh.
- `ArmorMakesSense_ContextFactory.lua` — builds the shared context table with all cross-module references.
- `ArmorMakesSense_ContextBinder.lua` — injects context into all modules that expose `setContext`.
- `ArmorMakesSense_ContextRefs.lua` — stable context reference holder for cross-module lookup.
- `ArmorMakesSense_Bootstrap.lua` — thin wiring helpers: `bindApi` and `registerRuntimeEvents`.
- `ArmorMakesSense_State.lua` — option resolution (`getOptions`), per-player persistent state (`ensureState`), modData schema management.
- `ArmorMakesSense_Tick.lua` — per-minute tick pipeline (see Tick Pipeline section).
- `ArmorMakesSense_Combat.lua` — combat event forwarding: `onWeaponSwing` (pass-through), `onPlayerAttackFinished` (strain overlay dispatch).
- `ArmorMakesSense_Strain.lua` — muscle strain: eligibility check (`isMeleeStrainEligible`), extra strain computation, overlay application.
- `ArmorMakesSense_WearDebug.lua` — worn-item telemetry: tracks per-player worn item counts for change detection and debug logging.
- `ArmorMakesSense_Runtime.lua` — lifecycle management: startup checks, event registration/teardown, MP guards, discomfort invariant, sleep per-frame tick, test-lock enforcement.
- `ArmorMakesSense_Stats.lua` — character stat IO: read/write for endurance, fatigue, thirst, discomfort, wetness, body temperature via dual-path (direct method / `CharacterStat` enum). Also provides `resetCharacterToEquilibrium` (full stat/health/nutrition/thermoregulator reset for bench use) and `resetMuscleStrain`.

### Model
- `ArmorMakesSense_Physiology.lua` — endurance model (`applyEnduranceModel`), thermal pressure (`resolveThermalPressureScale` with thermoregulator telemetry), breathing restriction, sleep penalty (`applySleepTransition`), recovery trace tracking, UI runtime snapshot.

### Testing/bench stack
- `ArmorMakesSense_Gear.lua`
- `ArmorMakesSense_Commands.lua`
- `ArmorMakesSense_API.lua`
- `ArmorMakesSense_Benches.lua`
- `ArmorMakesSense_Weapons.lua`
- `ArmorMakesSense_BenchCatalog.lua`
- `ArmorMakesSense_BenchScenarios.lua`
- `ArmorMakesSense_BenchUtils.lua`
- `ArmorMakesSense_BenchRunnerRuntime.lua`
- `ArmorMakesSense_BenchRunnerEnv.lua`
- `ArmorMakesSense_BenchRunnerSnapshot.lua`
- `ArmorMakesSense_BenchRunnerReport.lua`
- `ArmorMakesSense_BenchRunnerNative.lua`
- `ArmorMakesSense_BenchRunnerStep.lua`
- `ArmorMakesSense_BenchRunner.lua`
