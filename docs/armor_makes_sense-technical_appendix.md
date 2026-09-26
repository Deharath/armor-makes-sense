# Armor Makes Sense - Technical Overview

## Scope

AMS has separate singleplayer and multiplayer execution paths backed by shared
load and physiology modules. The server owns multiplayer gameplay state. The
client owns presentation, local singleplayer execution, and development tools.

## Reference Documents

- [Runtime Reference](./armor_makes_sense-runtime_reference.md): classification,
  load aggregation, physiology, strain, sleep, slots, and configuration
- [Multiplayer Reference](./armor_makes_sense-mp_reference.md): authority,
  demand-driven snapshot transport, and network state
- [UI Reference](./armor_makes_sense-ui_reference.md): tooltips, Burden panel,
  refresh behavior, and controller handling
- [Testing Reference](./armor_makes_sense-testing_reference.md): test API,
  benchmark runner, diagnostics, and report pipeline
- [Design Principles](./armor_makes_sense-design_manifesto.md): gameplay goals
  and non-goals

## Runtime Architecture

### Singleplayer

`ArmorMakesSense_Main.lua` loads the client entrypoints, registers the
compatibility provider, and asks `ArmorMakesSense_Bootstrap.lua` to select
exactly one client role. Production modules require their collaborators
directly. `ArmorMakesSense_ClientRuntime.lua` owns client lifecycle state,
logging, version reporting, protected calls, and role-aware player-state access.

In singleplayer, `EveryOneMinute` calls `core/ArmorMakesSense_Tick.lua` for each
active local player. The tick samples worn gear, runs
`Physiology.tick(player, state, options, profile, nowMinutes)`, and refreshes
UI. `OnPlayerAttackFinished` marks the tick window as fighting through
`Physiology.recordAttack` and applies the attacking local player's
muscle-strain overlay through `ArmorMakesSense_StrainShared.lua`.

Sleeping is handled inside the same minute tick. The sleep model observes
vanilla fatigue recovery, applies only the stiff-gear recovery penalty, and
causes the endurance path to rebase rather than scale an endurance delta.
Planning, bed choice, and sleep duration remain vanilla.

Development builds load `testing/ArmorMakesSense_00_DevBootstrap.lua`
separately. It owns test-module imports, command contexts, global console
bindings, environment locks, equilibrium resets, development-panel startup, and
benchmark pumps. Those paths are not imported by the production runtime.

### Multiplayer

`server/ArmorMakesSense_MPServerRuntime.lua` is the multiplayer authority for
endurance, sleep fatigue penalties, melee strain, and snapshot production. It
registers `OnClientCommand`, `EveryOneMinute`, and `OnWeaponSwing`:

- `EveryOneMinute` samples each online player, runs the shared physiology tick,
  stores `mpState.runtimeSnapshot`, attaches cost drivers, and syncs fatigue
  with `syncPlayerStats(player, 16)` when AMS added sleep fatigue.
- `OnClientCommand` accepts `request_snapshot`, checks
  `ArmorMakesSense_MPRequestPolicy.lua`, refreshes a read-only projection, and
  sends the encoded snapshot.
- `OnWeaponSwing` marks the tick window as fighting, then uses the latest
  cached worn profile for up to one wall-clock second and applies the shared
  strain overlay.

The MP client never advances gameplay. `ArmorMakesSense_MPClientRuntime.lua`
registers only `OnServerCommand`, `OnConnected`, and `OnCreatePlayer` when the
bootstrap selects the multiplayer role. The visible Burden panel requests
dynamic server telemetry when its cache is missing or older than 30 wall-clock
seconds. Local clothing changes dirty the UI; deterministic item rows and gear
burden are rebuilt locally without a request.

Both SP and MP use one authoritative tick per game minute. If there is no prior
minute, elapsed time is zero, the player is asleep, or elapsed time exceeds
`MaxStepMinutes` (30 by default), the physiology state is rebased instead of
applying an endurance adjustment. `Physiology.project` is read-only and is used
for UI refreshes and MP snapshot requests.

### Vanilla Runtime Contracts

The model integrations were checked against the installed Project Zomboid
42.20.0 runtime.

Thermoregulator node samples use vanilla's normalized `getInsulationUI()` and
`getWindresistUI()` values and are weighted by `ThermalNode` skin surface. The
raw getters are not used because their values contain nonlinear per-garment
transforms and layer bonuses and are not bounded to the model's 0-1 resistance
scale. Equal weighting is used only when `getSkinSurface()` is unavailable.

Shared gameplay modules import `ArmorMakesSense_UtilsShared.lua` and
`ArmorMakesSense_StatsShared.lua` directly. They do not accept mutable runtime
contexts. Stat writes use the shared execution-role resolver, so a server or
singleplayer client can write gameplay stats while a pure MP client cannot.

Activity sampling mirrors vanilla posture and movement flags: sleep, seated
rest, standing, walk, run, and sprint. Breathing demand uses the greater of the
thermoregulator metabolic rate and AMS movement anchors for the sampled
activity. AMS does not maintain a parallel combat or exertion latch.

The shared load model computes signals once per included item and caches them
by full type, body location, and actual weight. Rigidity comes from the item's
original vanilla discomfort; respiratory data comes from the breathing
classifier.

Worn equipment is normalized as effective kilograms rather than gated by the
armor label. The explicit `AMSIncludeBurden`, `AMSExcludeBurden`, and
`AMSArmor` tags are the override contract for third-party gear. Cosmetic items
and containers are excluded unless explicitly included. Physical calculations
read the original discomfort values cached before AMS zeroes script discomfort,
so movement and discomfort policy cannot feed back into burden.

Respiratory equipment publishes additive `airflowResistance` and maxed
`sealedRestriction`. Physiology never infers a sealed state from an aggregate
numeric threshold, and breathing cannot reduce unrelated burden.

Server snapshots are encoded and decoded by
`ArmorMakesSense_MPSnapshotCodec.lua`. The codec owns the wire-field mapping,
driver-row mapping, defaults, and schema validation. Schema version 8 is the
hard contract; clients reject snapshots with a missing or different version.

## Source Layout

| Path | Contents |
|---|---|
| `mod.info` | Root metadata |
| `common/media/lua/shared/` | Shared configuration, classification, models, compatibility, and slot rules |
| `common/media/lua/client/` | Client entrypoints, UI, SP runtime, diagnostics, and testing |
| `common/media/lua/server/` | MP authority and server diagnostics |
| `common/media/sandbox-options.txt` | Server-authoritative gameplay options |
| `42/mod.info` | Build 42 metadata override |

`common/` is the runtime source of truth. `42/` contains metadata only and does
not duplicate `common/media`.

## Module Ownership

### Entry Points

- `client/ArmorMakesSense_Main.lua`: client startup, slot/speed initialization,
  UI installation, and compatibility provider registration
- `client/core/ArmorMakesSense_Bootstrap.lua`: client role detection and
  exclusive runtime registration
- `client/ArmorMakesSense_MPClientRuntime.lua`: MP snapshot transport with
  explicit, side-effect-free registration
- `server/ArmorMakesSense_MPServerRuntime.lua`: MP gameplay authority,
  projection snapshots, fatigue sync, and strain handling

### Shared Model

- `ArmorMakesSense_Config.lua`: default tuning values
- `ArmorMakesSense_UtilsShared.lua`: numeric, boolean, protected-method, role,
  world-time, and wall-clock helpers
- `ArmorMakesSense_Options.lua`: canonical typed sandbox-option resolution for
  SP and MP authority
- `ArmorMakesSense_StatsShared.lua`: endurance/fatigue/stat IO and metabolic
  telemetry with MP-client writes blocked
- `ArmorMakesSense_BreathingClassifier.lua`: canonical respiratory equipment
  signals
- `ArmorMakesSense_LoadModelShared.lua`: per-item burden signals, worn-profile
  aggregation, carrier resolution, and load fraction
- `ArmorMakesSense_EnvironmentShared.lua`: activity and posture sampling
- `ArmorMakesSense_ThermalModel.lua`: effective thermal resistance, hot
  pressure, cold suitability, and `heat`
- `ArmorMakesSense_BreathingModel.lua`: respiratory severity, effort ramp, and
  breathing pressure
- `ArmorMakesSense_EnduranceModel.lua`: observed-delta recovery and drain
  scaling
- `ArmorMakesSense_SleepModel.lua`: stiff-gear fatigue recovery penalty
- `ArmorMakesSense_PhysiologyShared.lua`: PZ sampling, model composition,
  compatibility callbacks, stat writes, and runtime snapshots
- `ArmorMakesSense_StrainShared.lua`: melee strain eligibility and arm-burden
  magnitude
- `ArmorMakesSense_SpeedRebalance.lua`: discomfort removal, combat-speed rule,
  item reslots, and shoulder-pad tooltip cleanup
- `ArmorMakesSense_SlotCompat.lua`: custom body locations and compatibility
  rules
- `ArmorMakesSense_Compat.lua`: `MakesSenseCompat` registry
- `ArmorMakesSense_MPCompat.lua`: MP protocol constants and build identity
- `ArmorMakesSense_RuntimeState.lua`: isolated transient SP, MP-client, and
  MP-server weak-key state stores
- `ArmorMakesSense_MPSnapshotCodec.lua`: schema-versioned server snapshot wire
  codec
- `server/ArmorMakesSense_MPRequestPolicy.lua`: request acceptance, queueing,
  and completion flags

### Client Core

- `ArmorMakesSense_ClientRuntime.lua`: client lifecycle flags, logging, version
  metadata, protected PZ calls, and role-aware state lookup
- `ArmorMakesSense_State.lua`: options and per-player state initialization
- `ArmorMakesSense_Tick.lua`: singleplayer minute scheduling, load sampling,
  physiology tick, and UI refresh
- `ArmorMakesSense_Runtime.lua`: SP event registration and lifecycle guards
- `ArmorMakesSense_Combat.lua`: singleplayer combat event handling
- `ArmorMakesSense_Draw.lua`: shared pip drawing vocabulary
- `ArmorMakesSense_BurdenView.lua`: pure Burden tab view model
- `ArmorMakesSense_BurdenPanel.lua`: Burden tab drawing, body map, and support
  export button
- `ArmorMakesSense_UI.lua`: character-tab integration, fallback window, and help
- `ArmorMakesSense_PresentationPolicy.lua`: shared LOAD, ITEM, HEAT,
  BREATHING, SLEEP, and ARM pip bands
- `ArmorMakesSense_UITooltip.lua`: wearable tooltip pip rows and optional shared
  tooltip-controller provider
- `ArmorMakesSense_SupportReport.lua`: support report collection and formatting

Production client modules do not use mutable dependency contexts. Development
benchmark modules retain a separate context because their job is to run
controlled substitutions and scenarios rather than game runtime.

### Diagnostics and Testing

- `client/diagnostics/` and `server/diagnostics/`: MP ping and diagnostic dump
  harnesses for development builds
- `client/testing/`: command API, gear helpers, scenarios, benchmark execution,
  snapshots, and reports
- `client/testing/ArmorMakesSense_00_DevBootstrap.lua`: development-only module
  loading, context construction, global API binding, and event pumps
- `client/testing/ArmorMakesSense_DevPanel.lua`: development-only live model
  inspector and operator controls for environment, gear, reports, and
  benchmarks
- `client/testing/ArmorMakesSense_Reset.lua`: destructive equilibrium and body
  reset helpers used by controlled tests
- `client/testing/ArmorMakesSense_TestStats.lua`: development-only thirst,
  discomfort, wetness, and body-temperature setters

Workshop packaging excludes development testing and diagnostics modules. Release
shape validation rejects development references in production Lua.

## Load, Physiology, and Presentation Fields

`ArmorMakesSense_LoadModelShared.lua` computes each included worn item's burden:

```text
burdenKg = max(0, weightKg - 0.5) * placementFactor + bulkKg
bulkKg = originalRunPenalty * 6 + originalDiscomfort * 4
```

Placement is body-location based: trunk locations are near 1.0, full-body and
leg locations are higher, swing-chain arm/hand locations are higher, and feet
cost the most per kilogram. Footwear run modifiers are ignored as burden input
because they describe soles and traction. Cost drivers are items with
`burdenKg >= 1.5` (`LoadModel.COST_DRIVER_THRESHOLD_KG`).

The worn profile publishes these gameplay channels:

| Field | Meaning |
|---|---|
| `burdenKg` | Total effective kilograms from included worn items |
| `massKg` | Mass above the per-item allowance |
| `bulkKg` | Burden from cached vanilla run penalty and discomfort |
| `armKg` | Swing-chain effective kilograms used by melee strain |
| `rigidKg` | Weight of stiff gear (vanilla discomfort above 0) multiplied by sleep-contact share |
| `airflowResistance` | Sum of respiratory airflow restriction |
| `sealedRestriction` | Maximum sealed-suit or sealed-mask restriction |
| `driverCount` | Number of cost drivers at or above 1.5 effective kg |

`loadFraction` is carrier-relative:

```text
max(0, burdenKg - 3.5) / bodyKg * (1.3 - 0.06 * Strength) * PhysicalLoadScale
```

Body mass is clamped to 50-90 kg and Strength to 0-10. `PhysicalLoadScale` is a
sandbox multiplier from 0 to 3.

`ArmorMakesSense_ThermalModel.lua` returns `heat` as retained thermal resistance
multiplied by current heat strain, clamped to 0-1. It also exposes thermal
resistance, hot pressure, and cold suitability for presentation and reports.

`ArmorMakesSense_BreathingModel.lua` returns respiratory severity from airflow
and seal, then multiplies it by an exertion ramp above the default 0.2 onset.
Walking sits at the onset, so pressure appears under harder exertion or higher
metabolic demand. `EnableBreathingModel` gates pressure, not severity.

`ArmorMakesSense_EnduranceModel.lua` observes vanilla's endurance change since
the prior authoritative tick. Positive deltas are recovery and are scaled down:
by the square of the load while standing (never below zero), linearly while
walking, where the configured floor can turn recovery into drain. Negative
deltas are amplified by one load weight whatever the pace, plus heat and
breathing pressure. Seated postures recover at the vanilla rate, while heat can
affect both recovery and drain.
Nutrition Makes Sense contributions compose through `MakesSenseCompat` as
`regenScale` and `extraDrain`.

`ArmorMakesSense_SleepModel.lua` uses only `rigidKg`. While the player is
asleep, `penaltyFraction = min(0.5, rigidKg * 0.025)` by default. AMS observes
vanilla fatigue recovery and adds back that fraction as fatigue unless Caffeine
Makes Sense advertises `fatigue_coordinator`, in which case CMS reads the same
fraction from the sleep contribution callback.

`ArmorMakesSense_StrainShared.lua` uses `armKg`: no extra strain at or below 1
kg, ramping to `MuscleStrainMaxExtra` 0.15 at 8 kg with a `t^1.5` curve.

`ArmorMakesSense_SpeedRebalance.lua` zeroes `DiscomfortModifier` on every
wearable at boot after caching the original value for burden. It leaves
`RunSpeedModifier` alone and sets `CombatSpeedModifier` by one rule: swing-chain
locations lose 1% per effective kg, capped at 5%.

## Runtime Snapshots

`Physiology.tick` and `Physiology.project` produce the runtime snapshot used by
UI, reports, MP transport, diagnostics, and benchmarks.

Base snapshot fields:

| Field | Meaning |
|---|---|
| `activityLabel`, `postureLabel` | Current sampled activity and posture |
| `burdenKg`, `armKg`, `rigidKg`, `driverCount` | Worn-profile summary |
| `bodyKg`, `strength`, `loadFraction` | Carrier and load fraction |
| `heat`, `thermalResistance`, `hotPressure`, `coldSuitability` | Thermal model output |
| `airflowResistance`, `sealedRestriction` | Respiratory gear inputs |
| `breathingSeverity`, `breathingEnabled` | Breathing presentation state |
| `restRegenScale`, `standRegenScale`, `walkRegenScale` | Recovery scales for sitting, standing and walking |
| `runDrainScale`, `sprintDrainScale` | Drain scales for run and sprint |
| `sleepPenaltyFraction` | Current stiff-gear fatigue recovery penalty |
| `updatedMinute` | World-age minute when the snapshot was produced |

After a real endurance tick, the snapshot also carries `naturalDelta`,
`amsDelta`, `regenScale`, `drainScale`, `nmsRegenScale`, `nmsDrain`,
`dtMinutes`, `metabolicRate`, `breathingEffortRamp`, and `breathingPressure`.
Projection snapshots omit those tick-only values and the codec supplies defaults
when they are sent over MP.

## State and Authority

Runtime state is held in three weak-key tables indexed by player identity. It is
not written to player `modData` or save files.

- SP state stores timing, endurance/fatigue baselines, thermal smoothing state,
  and the latest UI runtime snapshot.
- MP client state stores request timing, one pending flag, and the latest
  decoded `mpServerSnapshot`.
- MP server state stores authoritative timing, fatigue baselines, thermal
  smoothing state, the latest runtime snapshot, one optional pending snapshot
  request, and a cached worn profile.

On first access for a player, `ArmorMakesSense_RuntimeState.lua` deletes the
obsolete `ArmorMakesSenseState` save blob without importing values from it.
Reloads and reconnects therefore start from current time and live stats.

## Console Output

Production modules route console output through `ArmorMakesSense_Logger.lua`.
A release session emits one boot identity for its active role, confirmations for
explicit user actions such as writing a support report, and actionable warnings
or errors. Normal option state, successful hook installation, UI and slot
initialization, rebalance summaries, snapshots, and synchronization are silent.
Routine lifecycle details use the `DEBUG` level and appear only when PZ debug
mode is active or the loaded mod id is `ArmorMakesSenseDev`.

Release-shape validation keeps production Lua free of development-only references,
removed runtime modules, stale field vocabulary, and broad MP-client snapshot
subscriptions.

## Configuration

`ArmorMakesSense_Config.lua` defines tuning defaults. Public sandbox options are
limited to these model controls:

| Option | Type | Range/default |
|---|---|---|
| `ArmorMakesSense.PhysicalLoadScale` | double | 0-3, default 1.0 |
| `ArmorMakesSense.EnableThermalModel` | boolean | default true |
| `ArmorMakesSense.EnableBreathingModel` | boolean | default true |
| `ArmorMakesSense.EnableMuscleStrainModel` | boolean | default true |
| `ArmorMakesSense.EnableSleepPenaltyModel` | boolean | default true |

Both SP and MP resolve `ArmorMakesSense.DEFAULTS` first and then apply matching
values from `SandboxVars.ArmorMakesSense` through `ArmorMakesSense_Options.lua`.

## Makes Sense Compatibility

AMS always registers this `MakesSenseCompat` capability:

- `endurance_coordinator`

When `EnableSleepPenaltyModel` is enabled at startup, AMS additionally
registers:

- `sleep_penalty_provider`
- `sleep_planner_penalty_provider`

Nutrition Makes Sense can provide an endurance contribution that AMS composes
before the final endurance write. Caffeine Makes Sense can own fatigue
coordination; when it does, AMS supplies penalty fractions and does not write
fatigue independently.

## Version Identity

Release identity is defined in:

- `mod.info`
- `42/mod.info`
- `shared/ArmorMakesSense_MPCompat.lua`

The workspace sync tool validates alignment across all three locations.
