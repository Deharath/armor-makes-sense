# Armor Makes Sense — Testing Reference (v1.1.4)

_As of March 7, 2026_  
`SCRIPT_VERSION=1.1.4`  
`SCRIPT_BUILD=ams-b42-2026-03-07-v114`

## Testing Surface

The testing stack exposes a scripting surface for repeatable local experiments, controlled gear application, UI probes, and benchmark orchestration.

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
- `ams_ui_probe_suite`
- `ams_ui_probe_set_list`
- `ams_ui_probe_wear_set`
- `ams_ui_probe_wear_set_default`

Benchmark helpers:
- `ams_sleep_bench`
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
- UI probes
- benchmark start/status/stop and preset introspection

The command module coordinates player state, gear helpers, and bench runner state.

## Gear and Weapon Helpers

### Gear Profiles

`client/testing/ArmorMakesSense_Gear.lua` manages wearable-set materialization:
- snapshots worn items as `{ fullType, location }`
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
- `sleepBench()` runs a controlled local sleep-penalty experiment over a chosen gear set and environment lock
- helper readers expose arm stiffness, perk levels, and static combat snapshots

## Benchmark System

The benchmark system is a declarative runner for repeatable AMS measurements. It combines set/preset catalogs, scenario blocks, controlled environment setup, native movement/combat drivers, sampled telemetry, and statistical reporting.

### Catalogs and Run Planning

`client/testing/ArmorMakesSense_BenchCatalog.lua` defines:
- canonical set definitions (`naked`, civilian baselines, mask cases, armor profiles, auto-imported built-in gear profiles)
- preset definitions with set list, scenario list, repeat count, speed, and mode
- run-plan resolution and validation
- set-definition to wear-entry translation

`client/testing/ArmorMakesSense_BenchScenarios.lua` defines scenario scripts as ordered block lists:
- setup blocks such as `prepare_state`, `equip_set`, and weather locks
- measurement blocks such as `sample_once`
- activity blocks such as native treadmill movement, standing combat, and real sleep
- async detection for runtime-polled scenarios

### Runtime Orchestration

`client/testing/ArmorMakesSense_BenchRunner.lua`:
- resolves presets into concrete run plans
- allocates run ids and runner state
- exposes `run`, `tick`, `status`, `stop`, `setList`, `scenarioList`, and `wearSet`
- coordinates scenario processing, snapshot streaming, and final report production

`client/testing/ArmorMakesSense_BenchRunnerRuntime.lua`:
- maps active/pending executions by run id
- mirrors a compact bench handle into player modData
- owns the native `OnTick` pump used by treadmill/native-driver scenarios

### Environment, Movement, and Step Execution

`client/testing/ArmorMakesSense_BenchRunnerEnv.lua` supplies:
- coordinate reads and teleports
- outdoor/vehicle/climbing reads
- climate and thermoregulator sampling
- clothing-condition reads
- native activity stance helpers
- weather override application and refresh
- set equip/restore helpers
- aggregate metric collection

`client/testing/ArmorMakesSense_BenchRunnerNative.lua` supplies:
- capability checks for pathing, facing, aiming, and attack APIs
- patrol/treadmill path construction
- movement/combat driver state
- stall accounting and phase timelines
- weapon-selection hooks for combat scenarios

`client/testing/ArmorMakesSense_BenchRunnerStep.lua`:
- applies bench stat profiles and reset logic
- logs before/after/mid-activity samples
- runs activity blocks and tracks async completion
- evaluates validity gates such as movement uptime, attack success ratio, and valid sample ratio
- emits per-step summaries and exit reasons

### Snapshot and Reporting Pipeline

`client/testing/ArmorMakesSense_BenchRunnerSnapshot.lua`:
- appends structured benchmark lines into an in-memory snapshot
- opens and writes stream log files in `benchlogs/`
- writes the final bench snapshot file with run metadata and counters

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

## Testing and Benchmark Modules

- `client/testing/ArmorMakesSense_API.lua` — global test API binder
- `client/testing/ArmorMakesSense_Commands.lua` — command layer
- `client/testing/ArmorMakesSense_Gear.lua` — gear snapshotting and profile application
- `client/testing/ArmorMakesSense_Weapons.lua` — temporary benchmark melee weapons
- `client/testing/ArmorMakesSense_Benches.lua` — point probes
- `client/testing/ArmorMakesSense_BenchCatalog.lua` — set/preset catalog and run-plan resolver
- `client/testing/ArmorMakesSense_BenchScenarios.lua` — scenario block catalog
- `client/testing/ArmorMakesSense_BenchUtils.lua` — helper primitives
- `client/testing/ArmorMakesSense_BenchRunnerRuntime.lua` — runner state tables and native tick pump
- `client/testing/ArmorMakesSense_BenchRunnerEnv.lua` — environment setup and metric collection
- `client/testing/ArmorMakesSense_BenchRunnerSnapshot.lua` — stream logging and snapshot artifacts
- `client/testing/ArmorMakesSense_BenchRunnerReport.lua` — aggregate report generation
- `client/testing/ArmorMakesSense_BenchRunnerNative.lua` — native movement/combat driver
- `client/testing/ArmorMakesSense_BenchRunnerStep.lua` — per-step executor and gate evaluator
- `client/testing/ArmorMakesSense_BenchRunner.lua` — top-level benchmark orchestration
