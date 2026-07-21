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

`client/testing/ArmorMakesSense_DevPanel.lua` provides a live in-game workbench
for the current player. Open it from the world context menu as `AMS Developer`
or call `AMS_DevPanel()` from the Lua console.

The panel displays:

- runtime authority and snapshot age;
- player endurance, fatigue, body temperature, and wetness;
- worn physical, breathing, sealed, and rigidity signals plus effective thermal resistance;
- effective load, thermal state, endurance corrections, and sleep effects;
- the largest current physical-load drivers;
- active environment-lock and benchmark state.

The utility column provides environment presets, equilibrium reset, diagnostic
marks, current-gear probes, support-report export, built-in gear application,
and benchmark start/stop controls. In multiplayer the panel remains available
for server-snapshot inspection, but state-changing controls are disabled.

The panel is part of `client/testing/` and is removed from Workshop builds.

## Global API Surface

`client/testing/ArmorMakesSense_API.lua` exports global helpers that delegate into the command or bench modules:

Environment and state helpers:
- `ams_test_unlock`
- `ams_lock_env`
- `ams_env_now`
- `ams_mark`
- `ams_reset_equilibrium`

Gear helpers:
- `ams_gear_save`
- `ams_gear_wear`
- `ams_gear_wear_spawn`
- `ams_gear_wear_virtual`
- `ams_gear_clear`
- `ams_gear_list`
- `ams_gear_reload_builtin`
- `ams_gear_dump`

Probe helpers:
- `ams_fitness_probe`
- `ams_discomfort_audit`
- `ams_ui_probe`

Benchmark helpers:
- `ams_bench_run`
- `ams_bench_status`
- `ams_bench_stop`
- `ams_bench_set_list`
- `ams_bench_scenario_list`
- `ams_bench_wear_set`

## Command Layer

`client/testing/ArmorMakesSense_Commands.lua` is the operator-facing command layer.

Command groups:
- gear profile save/load/wear/clear/dump
- environment lock and unlock
- mark/reset helpers
- discomfort audit
- current-gear runtime probe
- benchmark start/status/stop and preset introspection

The command module coordinates player state, gear helpers, and bench runner state.

Destructive character, body-damage, and muscle-strain resets live in
`client/testing/ArmorMakesSense_Reset.lua`; the production Stats module contains
only runtime stat and body-state IO.

Equilibrium reset and benchmark preparation heal injuries and normalize live
needs. They are intended for a disposable test character, not an active save.
Scenario preparation sets its required calorie target explicitly; the removed
"nutrition baseline" helper only wrote each current value back to itself.

## Gear and Weapon Helpers

### Gear Profiles

`client/testing/ArmorMakesSense_Gear.lua` manages wearable-set materialization:
- snapshots exact item and body-location objects, plus stable type/location text for logs
- indexes inventory and worn items by full type
- resolves wearable body locations
- applies saved or built-in gear profiles in three modes:
  - `inventory`
  - `spawn`
  - `virtual`
- prepends a baseline clothing set before profile application

### Temporary Bench Weapons

`client/testing/ArmorMakesSense_Weapons.lua`:
- selects and equips an eligible endurance-using melee weapon from a candidate list
- marks spawned weapons in modData
- clears previously spawned benchmark weapons before equipping a new one

## Point Probes

`client/testing/ArmorMakesSense_Benches.lua` contains targeted probes outside the full benchmark runner:
- `fitnessProbe()` logs exercise stiffness timers, arm stiffness, heavy-load moodle, and vanilla strain factor
- helper readers expose arm stiffness, perk levels, and static combat snapshots

The retired `ams_sleep_bench` command was removed because it implemented an old
sleep formula instead of calling the production sleep model. Sleep behavior is
covered by the production-function characterization suite and real-sleep
benchmark scenarios.

## External Characterization Suite

The repo-local Lua suite under `tests/` executes production shared modules with
small PZ boundary fixtures. Run it from the mod root:

```bash
tests/run_tests.sh
```

The suite locks current behavior for:

- armor and breathing classification;
- per-item and aggregate worn-gear load;
- thermal resistance, transient heat pressure, cold suitability, activity, and muscle-strain calculations;
- sleep planning, sleep snapshots, endurance recovery, and activity drain;
- shared simulation slicing, active catch-up caps, sleep-only operation,
  failures, aborts, and SP/server parity;
- versioned MP snapshot encode/decode round trips;
- development-bootstrap initialization and global API binding;
- release source shape, including the absence of testing references and
  packaging-time Main rewrites.

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
- preset definitions with set list, scenario list, repeat count, speed, and mode
- run-plan resolution and validation
- set-definition to wear-entry translation

`client/testing/ArmorMakesSense_BenchScenarios.lua` defines scenario scripts as ordered block lists:
- setup blocks such as `prepare_state`, `equip_set`, and weather locks
- measurement blocks such as `sample_once`
- activity blocks such as native treadmill movement, standing combat, and real sleep
- async detection for runtime-polled scenarios

The `benchmark_thermal_transient_v1` preset compares naked, civilian, and heavy
sets after `60`, `180`, and `360` seconds of running, followed by three minutes
of rest. The durations are aligned with AMS's once-per-game-minute production
cadence; sub-minute runs cannot produce deterministic runtime samples. Each step
first waits for a fresh production snapshot, measures one run activity, and
retains separate `before`, `after_run`, and `after_3m_rest` samples. The rest
window completes only on the first production tick at or after its target, so
its final sample is fresh. It records effective resistance, hot pressure,
thermal strain scale, cold suitability, and thermal contribution.

### Runtime Orchestration

`client/testing/ArmorMakesSense_BenchRunner.lua`:
- resolves presets into concrete run plans
- allocates run ids and runner state
- exposes `run`, `tick`, `status`, `stop`, `setList`, `scenarioList`, and `wearSet`
- coordinates scenario processing, snapshot streaming, and final report production
- rejects multiplayer execution and validates every catalog/scenario reference before changing game state

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
- weapon-selection hooks for combat scenarios

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
  standing combat scenario requests 24 swings within 420 seconds
- emits per-step summaries and exit reasons

### Snapshot and Reporting Pipeline

`client/testing/ArmorMakesSense_BenchRunnerSnapshot.lua`:
- appends structured benchmark lines into an in-memory snapshot
- writes parser metadata before opening streamed benchmark markers in `benchlogs/`
- preserves the stream as the final artifact and appends completion metadata;
  the compact in-memory snapshot is only a fallback when streaming is unavailable
  or fails

`client/testing/ArmorMakesSense_BenchRunnerReport.lua`:
- normalizes per-step results
- computes means, standard deviations, and coefficient-of-variation stats
- derives marginal comparisons against baseline sets
- logs benchmark reports for downstream parsing

`client/testing/ArmorMakesSense_BenchUtils.lua` provides:
- safe method dispatch
- boolean coercion
- metric formatting
- shared time access

Scenario durations are game-world seconds. Requested game speed accelerates
their wall-clock execution only. Unknown block and activity kinds fail the run;
they are never skipped or treated as completed work. Tick exceptions enter the
normal runner stop path so speed, weather, outfit, and native-driver state are
cleaned up.
The runner pins time once during each step's preparation, rebases AMS elapsed
time to that clock, and then lets time advance continuously through runtime
alignment and activity. Native activity startup does not reapply the pin.
The optional stat-profile input is rejected because mutating live XP without an
exact rollback is unsafe.

## Output and Parsing

Benchmark streams and snapshots are written under
`Zomboid/Lua/benchlogs/`. Workspace parsers and report helpers are under
`../tools/armor_makes_sense/scripts/`:

- `parse_bench.py`: parse benchmark snapshots
- `parse_debug.py`: extract bounded diagnostic windows

`parse_bench.py --diag-thermal` reports the retained transient sample tags.
`parse_bench.py --diag-breathing` reports the live smoothed metabolic rate beside
immediate metabolic demand, normalized effort, effort ramp, airflow/seal inputs,
and the open and sealed breathing contributions.
It also reports the cumulative AMS endurance correction separately from total
endurance change, which still includes vanilla movement drain.
The breathing presets use dedicated scenarios that align to a fresh production
tick and retain mid-activity samples every 30 game seconds; their result does
not depend on a single post-stop snapshot.
The sleep preset accepts only fatigue-threshold recovery as a valid completion;
external wakes, entry failures, and safety timeouts are rejected. It retains a
ten-game-minute recovery trace, which is sufficient to inspect the fatigue
curve without producing minute-by-minute multi-megabyte artifacts.
`--check-targets` requires an explicit calibrated JSON file; no built-in target
bands are assumed. Missing runs, incomplete runs, empty target specs, failed
targets, and failed baseline checks return nonzero exit status.

The core combat target compares `stiffness_per_swing` against the naked
baseline. Endurance drain per swing is not an AMS combat target because vanilla
owns melee endurance loss and AMS no longer applies a combat drain band.
