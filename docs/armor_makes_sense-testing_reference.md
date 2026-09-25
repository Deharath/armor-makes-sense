# Armor Makes Sense - Testing Reference

## Testing Surface

The development build exposes Lua commands for controlled gear application, UI
probes, point measurements, and benchmark orchestration. Workshop packaging
excludes `client/testing/`.

`client/testing/ArmorMakesSense_00_DevBootstrap.lua` is the only development
entrypoint. On game start it loads the testing modules, constructs their
context, binds the global command API, and registers the benchmark and
environment-lock event pumps. It also initializes the development panel.
Production Main and core runtime modules do not reference the testing namespace.

`tests/test_client_bootstrap.lua` characterizes exclusive SP/MP selection,
single registration, and failure when the PZ role detector is unavailable.
`tests/test_dev_bootstrap.lua` separately verifies the additional development
event pumps, true game-speed capture, and hot-reload registration cleanup.

Production load, environment, strain, physiology, and client coordinator tests
exercise direct module imports. Player state, world time, and character stats
are represented at the PZ boundary; no production module exposes `setContext`
for test substitution. Tests replace named module methods only for the duration
of a process when a PZ boundary must be controlled.

Paths in this document are relative to `common/media/lua/`.

## Development Panel

`client/testing/ArmorMakesSense_DevPanel.lua` is the only development
interface; there are no console globals. Open it from the world context menu
as `AMS Developer`.

The panel displays:

- runtime authority and snapshot age;
- player endurance, fatigue, body temperature, and wetness;
- worn burden, arm, rigid, breathing, sealed, and thermal signals;
- load fraction, heat, endurance scales, and sleep penalty;
- the largest current burden drivers;
- active environment-lock and benchmark state.

The utility column provides environment presets, equilibrium reset, diagnostic
marks, the current-gear probe, the discomfort audit, support-report export,
gear profiles (a saved outfit plus built-ins), and benchmark start/stop. In
multiplayer the panel remains available for server-snapshot inspection, but
state-changing controls are disabled.

The panel is part of `client/testing/` and is removed from Workshop builds.

## Command Layer

`client/testing/ArmorMakesSense_Commands.lua` backs the panel buttons:
environment lock and unlock, equilibrium reset, marks, gear save/wear/clear,
discomfort audit, current-gear probe, and benchmark run/stop. Gear profiles are
always worn virtually: items already worn are reused, missing items are created
at full condition.

Destructive character, body-damage, and muscle-strain resets live in
`client/testing/ArmorMakesSense_Reset.lua`; the production Stats module contains
only runtime stat and body-state IO.

Equilibrium reset and benchmark preparation heal injuries and normalize live
needs. They are intended for a disposable test character, not an active save.
Scenario preparation sets its required calorie target explicitly.

## Gear and Weapon Helpers

### Gear Profiles

`client/testing/ArmorMakesSense_Gear.lua` manages wearable-set materialization:
- snapshots exact item and body-location objects, plus stable type/location text
  for logs
- indexes inventory and worn items by full type
- resolves wearable body locations
- applies saved or built-in gear profiles in three modes:
  - `inventory`
  - `spawn`
  - `virtual`
- prepends a baseline clothing set before profile application

### Temporary Bench Weapons

`client/testing/ArmorMakesSense_Weapons.lua`:
- selects and equips an eligible endurance-using melee weapon from a candidate
  list
- marks spawned weapons in modData
- clears previously spawned benchmark weapons before equipping a new one

## Point Probes

`client/testing/ArmorMakesSense_Benches.lua` contains targeted probes outside
the full benchmark runner:
- `fitnessProbe()` logs exercise stiffness timers, arm stiffness, heavy-load
  moodle, and vanilla strain factor
- helper readers expose arm stiffness, perk levels, and static combat snapshots

Sleep behavior is covered by production-function characterization tests and
real-sleep benchmark scenarios.

## External Characterization Suite

The repo-local Lua suite under `tests/` executes production shared modules with
small PZ boundary fixtures. Run it from the mod root:

```bash
tests/run_tests.sh
```

`tests/run_tests.sh` currently runs:

| Test | Coverage |
|---|---|
| `test_item_models.lua` | Armor, breathing, burden, and worn-profile item models |
| `test_environment_strain.lua` | Activity/posture sampling and muscle strain |
| `test_thermal_model.lua` | Thermal resistance, hot pressure, cold suitability, and heat |
| `test_physiology.lua` | Authoritative minute tick, projection, endurance, sleep, and compat traces |
| `test_calculation_models.lua` | Pure endurance, breathing, and sleep calculations |
| `test_presentation_policy.lua` | Shared 4-pip bands and percent formatting |
| `test_mp_snapshot_codec.lua` | Schema 7 encode/decode and driver rows |
| `test_mp_request_policy.lua` | Server request throttle and pending flags |
| `test_runtime_state.lua` | Weak-key stores and saved-state purge |
| `test_options.lua` | Defaults and sandbox overrides |
| `test_logger.lua` | Logging behavior |
| `test_stats_authority.lua` | Stat IO and MP-client write blocking |
| `test_local_player_ownership.lua` | Local-player ownership helpers |
| `test_ui_tooltip.lua` | Tooltip row construction and wrappers |
| `test_burden_view.lua` | Burden tab view model: verdict priority, B42 placeholder format, paired-item grouping, channel attribution, pace values, MP heat pending, disabled channels, removal tip, body-part spread and location fallback |
| `test_burden_panel.lua` | Burden tab panel: exact sizing without clipping, tab-strip width floor on vanilla views, body map values, gear-row, channel-row and body-part hover, help routing |
| `test_slot_compat.lua` | Custom body-location compatibility |
| `test_speed_rebalance_lifecycle.lua` | Script rebalance registration and values |
| `test_tick_coordinator.lua` | SP tick coordinator behavior |
| `test_client_bootstrap.lua` | SP/MP role selection and runtime registration |
| `test_dev_panel.lua` | Development panel data and controls |
| `test_dev_bootstrap.lua` | Development bootstrap and event pumps |
| `test_gear.lua` | Gear helper behavior |
| `test_bench_catalog.lua` | Benchmark sets, presets, and validation |
| `test_bench_runner_env.lua` | Environment, runtime metric, and gear helpers |
| `test_bench_runner_snapshot.lua` | Benchmark snapshot streaming |
| `test_bench_runner_step.lua` | Step summaries, validity, tick ledger, input retries, and async activities |
| `test_bench_runner_report.lua` | Endurance cost, monotonicity, stability, and separation |
| `test_release_shape.sh` | Lean 2.0 structural guards |

Fixture expectations are characterization values, not an independent formula
implementation. When balance intentionally changes, update the production code
and expected values in the same reviewed patch.

## Benchmark System

The benchmark system is a declarative runner for repeatable AMS measurements.
It combines set and preset catalogs, scenario blocks, controlled environments,
native movement and combat drivers, telemetry, and statistical reporting.

### Catalogs and Run Planning

`client/testing/ArmorMakesSense_BenchCatalog.lua` defines:
- canonical set definitions, including naked and civilian baselines, masks,
  armor profiles, and imported built-in gear profiles
- preset definitions with set list, scenario list, and repeat count; every
  preset runs at speed 16, except `sleep` (8x, not yet validated faster),
  standing combat, and every sprint block (8x). Swing detection and sprint
  start-up need real frames; at 16x a 2-minute sprint spans only 12-40 frames
  and misses its sprint-uptime gate
- run-plan resolution and validation
- set-definition to wear-entry translation

`client/testing/ArmorMakesSense_BenchScenarios.lua` defines scenario scripts as
ordered block lists:
- setup blocks such as `prepare_state`, `equip_set`, and weather locks
- measurement blocks such as `sample_once`
- activity blocks such as native treadmill movement, standing combat, and real
  sleep

Scenarios are built by small factories. Every treadmill scenario waits for a
fresh production tick before its `before` sample, so the first measured minute
is not a partial one. Hot, cold, and windless-cold variants differ only by
weather profile.

| Preset | Sets | Scenarios | Repeats |
|---|---|---|---|
| `core` | naked, civilian baseline, civilian leather, military surplus, bulletproof vest, heavy | treadmill run/sprint, standing combat | 1 |
| `recovery` | same as `core` | stand and walk recovery after a sprint | 1 |
| `thermal` | naked, civilian winter layer, heavy | hot and cold walk/run | 1 |
| `thermal_nowind` | same as `thermal` | windless cold walk/run | 1 |
| `thermal_transient` | naked, civilian baseline, heavy | run 60/180/360 s, then 3 min rest | 2 |
| `breathing` | naked, respirator and gas mask with and without filters | breathing walk/run/sprint | 1 |
| `breathing_quick` | same as `breathing` | breathing run | 1 |
| `sleep` | same as `core` | 16 h real sleep from fatigue 0.8 | 3 |
| `smoke` | naked, heavy | treadmill run, standing recovery | 1 |

The `recovery` scenarios sprint for two minutes to open an endurance deficit,
wait for a production tick, then take a `sample_once` block with
`baseline = true`. That sample restarts the step deltas, so `endDelta` measures
only the following five minutes of standing (`recovery_stand`) or walking
(`recovery_walk`). They calibrate `StandRegenLoadWeight`, `WalkRegenFloor`, and
`DrainLoadWeight`; treadmill scenarios start at full endurance and cannot show
regen.

### Tick Ledger and Endurance Cost

From the baseline sample to the end of the step, the step keeps a ledger of
every production tick: the vanilla endurance change (`naturalDelta`), the AMS
correction (`amsDelta`), and the endurance right after the tick. `STEP_DONE`
reports:

| Key | Meaning |
|---|---|
| `tick_count` | Production ticks inside the measured window |
| `tick_gaps` | Minutes skipped between observed ticks; should be 0 |
| `natural_total` | Sum of vanilla endurance changes |
| `ams_total` | Sum of AMS corrections |
| `realized_scale` | Observed endurance change / `natural_total` |
| `tick_closure` | Observed change minus `natural_total + ams_total`; near 0 |
| `arm_strain_gain` | Arm stiffness added during the window, decay removed |
| `game_sec_per_frame` | Mean game time per frame, the effective integration step |
| `wall_sec` | Real seconds the step took; `AMS_BENCH_DONE` has the run total |

`realized_scale` is the multiplier AMS actually applied. Unlike raw `endDelta`,
it does not depend on how long the character spent sprinting versus running,
so endurance presets need one repeat. The report and `--brief` turn it into an
endurance cost: drain steps cost `realized_scale`, regen steps cost its inverse
(slower recovery costs more). Naked is about 1.0. When `|natural_total|` is
below 0.001, as in a walk that starts at full endurance, the ratio is rounding
noise and `realized_scale` is `na`.

### Speed Invariance

Game speed decides only how much game time passes per frame. The measurements
are built so that step size does not change them:
- endurance is the per-tick ratio above, so vanilla's own per-frame
  integration cancels out
- vanilla arm stiffness decays every frame by `0.002 * multiplier`, so a net
  start/end delta shrinks when swings are spread over more game time. The
  ledger instead sums per-frame increases and adds back the previous frame's
  decay; `stiffness_per_swing` is `arm_strain_gain / achieved_swings`
- `game_sec_per_frame` and `wall_sec` show the cost and step size of each run

To validate a speed change, rerun `core` and compare costs and
`stiffness_per_swing` with an earlier run. Costs should match to three
decimals.

The `thermal_transient` preset compares naked, civilian, and heavy
sets after `60`, `180`, and `360` seconds of running, followed by three minutes
of rest. The durations are aligned with AMS's once-per-game-minute production
cadence; sub-minute runs cannot produce deterministic runtime samples. Each step
first waits for a fresh production snapshot, measures one run activity, and
retains separate `before`, `after_run`, and `after_3m_rest` samples. The rest
window completes only on the first production tick at or after its target, so
its final sample is fresh. It records effective resistance, hot pressure,
thermal strain scale, cold suitability, and heat.

### Runtime Orchestration

`client/testing/ArmorMakesSense_BenchRunner.lua`:
- resolves presets into concrete run plans
- allocates run ids and runner state
- exposes `run`, `tick`, `stop`, `noteDisturbance`, and `curtainStatus`
- coordinates scenario processing, snapshot streaming, and final report
  production
- rejects multiplayer execution and validates every catalog/scenario reference
  before changing game state
- re-runs a step whose measured window saw player input, up to two times

`client/testing/ArmorMakesSense_BenchCurtain.lua` covers the screen while a run
is active. The mouse is then over UI, so world hover, clicks, context menus,
and zoom never reach the character. The top strip shows the preset, step, set,
scenario, attempt, elapsed time, ETA, and a `Stop` button. Java still reads the
aim key and the keyboard under any Lua panel, so a right-click or key press is
reported to the runner. If that happens after the step's baseline sample, the
step logs `[AMS_BENCH_STEP_RETRY]` instead of `STEP_DONE` and runs again. After
two retries, it logs normally and is rejected with `gate_failed=input_disturbed`.
The curtain is not always-on-top, so the pause menu stays usable.

`client/testing/ArmorMakesSense_BenchRunnerRuntime.lua`:
- maps active/pending executions by run id
- mirrors a compact bench handle into transient development state
- owns the native `OnTick` pump used by treadmill/native-driver scenarios

### Environment, Movement, and Step Execution

`client/testing/ArmorMakesSense_BenchRunnerEnv.lua` supplies:
- coordinate reads and vanilla `teleportTo` resets
- outdoor/vehicle/climbing reads
- climate and thermoregulator sampling
- clothing-condition reads
- native activity stance helpers
- weather override application and refresh
- set equip/restore helpers
- aggregate metric collection

`BenchRunnerEnv.RUNTIME_METRICS` writes these runtime wire keys for parsers:

| Wire key | Runtime field |
|---|---|
| `burden_kg` | `burdenKg` |
| `arm_kg` | `armKg` |
| `rigid_kg` | `rigidKg` |
| `body_kg` | `bodyKg` |
| `strength` | `strength` |
| `load_fraction` | `loadFraction` |
| `heat` | `heat` |
| `thermal_resistance` | `thermalResistance` |
| `thermal_hot_pressure` | `hotPressure` |
| `cold_suitability` | `coldSuitability` |
| `airflow_resistance_runtime` | `airflowResistance` |
| `sealed_restriction_runtime` | `sealedRestriction` |
| `breathing_severity` | `breathingSeverity` |
| `metabolic_rate` | `metabolicRate` |
| `breathing_effort_ramp` | `breathingEffortRamp` |
| `breathing_pressure` | `breathingPressure` |
| `walk_regen_scale` | `walkRegenScale` |
| `rest_regen_scale` | `restRegenScale` |
| `stand_regen_scale` | `standRegenScale` |
| `run_drain_scale` | `runDrainScale` |
| `sprint_drain_scale` | `sprintDrainScale` |
| `regen_scale` | `regenScale` |
| `drain_scale` | `drainScale` |
| `end_natural_delta` | `naturalDelta` |
| `end_applied_delta` | `amsDelta` |
| `nms_regen_scale` | `nmsRegenScale` |
| `nms_drain` | `nmsDrain` |
| `sleep_penalty_fraction` | `sleepPenaltyFraction` |
| `runtime_dt_min` | `dtMinutes` |
| `runtime_updated_min` | `updatedMinute` |
| `runtime_snapshot_age_min` | derived snapshot age |

`collectMetrics(player)` returns live stats, strain, climate, clothing
condition, `driverCount`, `loadFraction`, and a numeric `runtime` table copied
from the latest production snapshot or a read-only projection.

Native movement cleanup follows the vanilla timed-action contract: cancel the
active `PathFindBehavior2`, then clear the player's path. This prevents a
finished treadmill step from resuming during later wait or setup blocks.
Weather control uses only vanilla's admin override channel and restores its
previous enabled state and value. Outfit cleanup restores the original item
objects at their original body locations and emits `OnClothingUpdated`.

`client/testing/ArmorMakesSense_BenchRunnerNative.lua` supplies:
- capability checks for pathing, facing, aiming, and attack APIs
- patrol/treadmill path construction
- movement/combat driver state
- stall accounting and phase timelines
- bench weapon selection for combat scenarios

The driver imports its helpers directly from `BenchUtils`, `BenchRunnerEnv`,
and `BenchRunnerRuntime`; it takes no per-call dependency bundle.

`client/testing/ArmorMakesSense_BenchRunnerStep.lua`:
- applies scenario reset logic without rewriting character perks or XP
- logs before/after/mid-activity samples
- runs activity blocks and tracks async completion
- evaluates validity gates such as clock continuity, movement uptime, attack
  success ratio, and valid sample ratio
- classifies walk, run, and sprint from the same player flags used by vanilla
  thermoregulation, and rejects steps that miss their requested intensity
- rejects non-sleep measurements without a production runtime load snapshot
- requires combat scenarios to complete their full requested swing count; the
  standing combat scenario requests 12 swings at 8x, with a 1200-second timeout
  for a stuck driver. It completes on swing count because swing rate per game
  second depends on frame rate
- keeps the tick ledger described above
- emits per-step summaries and exit reasons

`summarizeStep(startMetrics, endMetrics)` returns endurance, thirst, fatigue,
temperature, strain, and arm-stiffness deltas plus `loadFraction` and the
`runtime` table from the end sample.

### Snapshot and Reporting Pipeline

`client/testing/ArmorMakesSense_BenchRunnerSnapshot.lua`:
- appends structured benchmark lines into an in-memory snapshot
- writes parser metadata before opening streamed benchmark markers in
  `benchlogs/`
- preserves the stream as the final artifact and appends completion metadata;
  the compact in-memory snapshot is only a fallback when streaming is
  unavailable or fails

`client/testing/ArmorMakesSense_BenchRunnerReport.lua`:
- normalizes per-step results
- computes means, standard deviations, and coefficient-of-variation stats
- derives marginal comparisons against baseline sets
- checks monotonicity (naked <= civilian <= vest <= heavy), heavy/light ratio,
  and separation on endurance cost; sleep checks monotonicity on sleep duration
- checks stability on cost CV when a set has two or more valid repeats;
  single-repeat sets are `single`, and the run's stability is `na`
- logs benchmark reports for downstream parsing

`client/testing/ArmorMakesSense_BenchUtils.lua` provides:
- `clamp` and `safeMethod`, taken directly from `ArmorMakesSense.Utils`
- boolean coercion
- metric formatting
- threshold resolution shared by validity gates and the report
- shared time access

Validity-gate defaults live in `BenchRunnerStep`; report thresholds live in
`BenchRunnerReport`. Both read overrides from the run's `thresholds` option.

Scenario durations are game-world seconds. Requested game speed accelerates
their wall-clock execution only. Unknown block and activity kinds fail the run;
they are never skipped or treated as completed work. Tick exceptions enter the
normal runner stop path so speed, weather, outfit, and native-driver state are
cleaned up.

The runner pins time once during each step's preparation, rebases AMS elapsed
time to that clock, and then lets time advance continuously through runtime
alignment and activity. Native activity startup does not reapply the pin.
Benchmarks never change perks or XP.

The panel runs presets with their defaults. `BenchRunner.run(presetId, opts)`
also accepts `sets`, `scenarios`, `classes`, `current_set`, `repeats`,
`speed`, `label`, `thresholds`, `benchVerbose`, `midActivitySamples`,
`midActivityVerbose`, `midActivityEverySec`,
`pinnedTimeOfDay` (hour, or `false` to skip pinning; default 10), and
`nativeAttackCooldownSec`; only these spellings are read. Explicit `sets` may
name any catalog set, not only the preset's.

## Output and Parsing

Benchmark streams and snapshots are written under `Zomboid/Lua/benchlogs/`.
Workspace parsers and report helpers are under
`../tools/armor_makes_sense/scripts/`:

- `parse_bench.py`: parse benchmark snapshots
- `parse_debug.py`: extract bounded diagnostic windows

`parse_bench.py` output modes include:

| Option | Purpose |
|---|---|
| `--brief` | Compact text tables with ratios against naked baselines |
| `--validity` | Rejected steps and reasons |
| `--diag-load` | Load, heat, breathing, and endurance-scale diagnostics |
| `--diag-burden` | Burden kg, arm kg, rigid kg, carrier, load, and sleep penalty |
| `--diag-thermal` | Transient thermal sample diagnostics |
| `--diag-breathing` | Breathing effort, restriction, severity, pressure, and AMS endurance totals |
| `--diag-order` | Endurance ordering: natural delta, applied delta, regen/drain scales, and NMS contribution |

The thermal diagnostics report retained transient sample tags. Breathing
diagnostics report live smoothed metabolic rate, effort ramp, airflow/seal
inputs, severity, pressure, AMS applied total, AMS tick count, and total
endurance change. The breathing presets align to a fresh production tick and
retain mid-activity samples every 30 game seconds; their result does not depend
on a single post-stop snapshot.

The sleep preset accepts only fatigue-threshold recovery as a valid completion;
external interruptions, entry failures, and safety timeouts are rejected. It
retains a ten-game-minute recovery trace, which is sufficient to inspect the
fatigue curve without producing minute-by-minute multi-megabyte artifacts.

`--check-targets` requires an explicit calibrated JSON file; no built-in target
bands are assumed. Missing runs, incomplete runs, empty target specs, failed
targets, and failed baseline checks return nonzero exit status.

`parse_debug.py` parses current diagnostic key/value lines in bounded windows.
It recognizes UI probes, first snapshot logs, diagnostic request/receive lines,
server `[DUMP]` and `[DUMP_ITEM]` rows, and sleep diagnostic/anomaly rows. It
uses `burden_kg >= 1.0` to count qualifying UI drivers and reports
`sleep_anomalies` when `[SLEEP_ANOM]` lines are present.

The core combat target compares `stiffness_per_swing` against the naked
baseline. Endurance drain per swing is not an AMS combat target because vanilla
owns melee endurance loss and AMS applies only the shared muscle-strain overlay.
