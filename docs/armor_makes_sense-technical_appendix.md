# Armor Makes Sense — Technical Appendix (v1.1.4)

_As of March 7, 2026_  
`SCRIPT_VERSION=1.1.4`  
`SCRIPT_BUILD=ams-b42-2026-03-07-v114`

## Scope

Armor Makes Sense (AMS) is a Build 42 armor-physiology mod with singleplayer and multiplayer runtime paths. `StarlitLibrary` is a hard dependency and provides the tooltip injection hook used by the UI layer.

The codebase is organized around five technical references:
- Runtime systems: [armor_makes_sense-runtime_reference.md](./armor_makes_sense-runtime_reference.md)
- Multiplayer runtime and diagnostics: [armor_makes_sense-mp_reference.md](./armor_makes_sense-mp_reference.md)
- UI and presentation behavior: [armor_makes_sense-ui_reference.md](./armor_makes_sense-ui_reference.md)
- Testing and benchmark tooling: [armor_makes_sense-testing_reference.md](./armor_makes_sense-testing_reference.md)
- Design intent: [armor_makes_sense-design_manifesto.md](./armor_makes_sense-design_manifesto.md)

## Design Summary

Core design intent:
- replace vanilla discomfort gameplay pressure with physical costs
- keep discomfort pinned to zero
- model endurance pressure, thermal pressure, breathing restriction, melee muscle strain, and sleep recovery slowdown

Runtime split:
- singleplayer uses the full client runtime (`Runtime`, `Tick`, `Combat`, client `Physiology`)
- multiplayer uses a server runtime (`MPServerRuntime`) for endurance, fatigue, discomfort suppression, and melee strain
- multiplayer clients request and cache server snapshots through `MPClientRuntime` for UI display
- shared load/model code lives in `shared/` so SP and MP use the same armor profile math

## Build Layout

- Mod root (`ArmorMakesSense/`): metadata and assets (`mod.info`, `poster.png`, `ams_icon.png`)
- `common/`: source-of-truth Lua, translations, testing, diagnostics, and media
- `42/`: override layer containing `42/mod.info`
- `42/media`: empty

## Reference Map

### Runtime Reference

[armor_makes_sense-runtime_reference.md](./armor_makes_sense-runtime_reference.md) covers:
- runtime wiring and client lifecycle
- option precedence and persistent state
- armor classification and load model
- physiology, environment, strain, sleep, and recovery trace
- slot compatibility, speed rebalance, and configuration defaults

### Multiplayer Reference

[armor_makes_sense-mp_reference.md](./armor_makes_sense-mp_reference.md) covers:
- SP/MP boot split and server runtime structure
- snapshot protocol and client cache behavior
- MP diagnostics harness and dump tooling
- context injection paths and MP-facing module map

### UI Reference

[armor_makes_sense-ui_reference.md](./armor_makes_sense-ui_reference.md) covers:
- tooltip rows and thresholds
- burden panel tiers and composition
- cost-driver display
- tab injection and fallback window behavior

### Testing Reference

[armor_makes_sense-testing_reference.md](./armor_makes_sense-testing_reference.md) covers:
- global `ams_*` API entrypoints
- command layer and gear helpers
- point probes
- benchmark catalog, scenarios, runtime orchestration, environment sampling, native drivers, snapshot streaming, and report generation

## Module Inventory

### Entry / Shared / Runtime
- `client/ArmorMakesSense_Main.lua` — client boot facade: defines `SCRIPT_VERSION` / `SCRIPT_BUILD`, requires modules in load order, builds the client context, wires modules, registers SP runtime events, and exposes the public API surface
- `client/ArmorMakesSense_MPClientRuntime.lua` — MP client snapshot transport/UI bridge
- `server/ArmorMakesSense_MPServerRuntime.lua` — MP gameplay/runtime path and snapshot sender

### Shared
- `shared/ArmorMakesSense_Config.lua` — tuning defaults
- `shared/ArmorMakesSense_ModOptionsShared.lua` — sandbox and PZAPI ModOptions integration
- `shared/ArmorMakesSense_MPCompat.lua` — MP constants and command names
- `shared/ArmorMakesSense_ArmorClassifier.lua` — armor-vs-civilian classification
- `shared/ArmorMakesSense_BreathingClassifier.lua` — respiratory classification
- `shared/ArmorMakesSense_LoadModelShared.lua` — shared item-to-load and profile aggregation
- `shared/ArmorMakesSense_EnvironmentShared.lua` — shared MP environment/activity sampling
- `shared/ArmorMakesSense_PhysiologyShared.lua` — shared endurance/thermal/breathing/sleep formulas
- `shared/ArmorMakesSense_StrainShared.lua` — shared melee strain logic
- `shared/ArmorMakesSense_SlotCompat.lua` — custom body locations and compatibility rules
- `shared/ArmorMakesSense_SpeedRebalance.lua` — discomfort suppression, speed overrides, and reslots

### Client core and models
- `client/core/ArmorMakesSense_Utils.lua` — utility helpers
- `client/core/ArmorMakesSense_Environment.lua` — client environment and activity sampling
- `client/core/ArmorMakesSense_LoadModel.lua` — client load-model wrapper
- `client/core/ArmorMakesSense_UI.lua` — tooltip and burden UI
- `client/core/ArmorMakesSense_ContextFactory.lua` — client context builder
- `client/core/ArmorMakesSense_ContextBinder.lua` — context injector
- `client/core/ArmorMakesSense_ContextRefs.lua` — stable context references
- `client/core/ArmorMakesSense_Bootstrap.lua` — thin binding/runtime helpers
- `client/core/ArmorMakesSense_State.lua` — options and per-player state
- `client/core/ArmorMakesSense_Tick.lua` — per-minute tick pipeline
- `client/core/ArmorMakesSense_Combat.lua` — combat event forwarding
- `client/core/ArmorMakesSense_Strain.lua` — SP strain overlay
- `client/core/ArmorMakesSense_WearDebug.lua` — worn-item telemetry
- `client/core/ArmorMakesSense_Runtime.lua` — SP lifecycle management
- `client/core/ArmorMakesSense_Stats.lua` — stat IO and bench reset helpers
- `client/models/ArmorMakesSense_Physiology.lua` — SP physiology model and UI runtime snapshot production

### Diagnostics
- `client/diagnostics/ArmorMakesSense_MPDiagnosticsClient.lua` — client diagnostics receive/logging path
- `client/diagnostics/ArmorMakesSense_MPClientHarness.lua` — client harness ping path
- `server/diagnostics/ArmorMakesSense_MPDiagnosticsServer.lua` — server diagnostics dump and minute summaries
- `server/diagnostics/ArmorMakesSense_MPServerHarness.lua` — server harness pong path

### Testing and benchmarking
- `client/testing/ArmorMakesSense_API.lua` — global test API binder
- `client/testing/ArmorMakesSense_Commands.lua` — command layer
- `client/testing/ArmorMakesSense_Gear.lua` — gear snapshotting and profile application
- `client/testing/ArmorMakesSense_Weapons.lua` — temporary benchmark melee weapons
- `client/testing/ArmorMakesSense_Benches.lua` — point probes
- `client/testing/ArmorMakesSense_BenchCatalog.lua` — set/preset catalog and run-plan resolver
- `client/testing/ArmorMakesSense_BenchScenarios.lua` — scenario block catalog
- `client/testing/ArmorMakesSense_BenchUtils.lua` — testing helper primitives
- `client/testing/ArmorMakesSense_BenchRunnerRuntime.lua` — runner state tables and native tick pump
- `client/testing/ArmorMakesSense_BenchRunnerEnv.lua` — environment setup and metric collection
- `client/testing/ArmorMakesSense_BenchRunnerSnapshot.lua` — stream logging and snapshot artifacts
- `client/testing/ArmorMakesSense_BenchRunnerReport.lua` — aggregate report generation
- `client/testing/ArmorMakesSense_BenchRunnerNative.lua` — native movement/combat driver
- `client/testing/ArmorMakesSense_BenchRunnerStep.lua` — per-step executor and gate evaluator
- `client/testing/ArmorMakesSense_BenchRunner.lua` — top-level benchmark orchestration
