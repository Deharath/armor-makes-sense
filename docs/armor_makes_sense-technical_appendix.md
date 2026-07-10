# Armor Makes Sense — Technical Appendix (v1.2.8)

_As of April 2, 2026_  
`SCRIPT_VERSION=1.2.8`
`SCRIPT_BUILD=ams-b42-2026-05-04-v128`

## Scope

Armor Makes Sense (AMS) is a Build 42 armor-physiology mod with singleplayer and multiplayer runtime paths. The UI layer owns its inventory-tooltip integration directly by patching `ISToolTipInv.render` for wearable items only and populating `ObjectTooltip` layouts through vanilla `DoTooltipEmbedded`.

The codebase is organized around five technical references:
- Runtime systems: [armor_makes_sense-runtime_reference.md](./armor_makes_sense-runtime_reference.md)
- Multiplayer runtime and diagnostics: [armor_makes_sense-mp_reference.md](./armor_makes_sense-mp_reference.md)
- UI and presentation behavior: [armor_makes_sense-ui_reference.md](./armor_makes_sense-ui_reference.md)
- Testing and benchmark tooling: [armor_makes_sense-testing_reference.md](./armor_makes_sense-testing_reference.md)
- Design intent: [armor_makes_sense-design_manifesto.md](./armor_makes_sense-design_manifesto.md)

## Design Summary

Core design intent:
- replace vanilla discomfort gameplay pressure with physical costs
- remove worn item discomfort as an armor cost while preserving non-clothing vanilla discomfort
- model endurance pressure, thermal pressure, breathing restriction, melee muscle strain, and sleep recovery slowdown
- keep mild thermal drift near neutral so ordinary walking does not constantly flip armor between helpful and burdensome
- prefer sustained core/body-heat evidence over short-lived movement warmth when classifying hot-side thermal burden

Runtime split:
- singleplayer uses the full client runtime (`Runtime`, `Tick`, `Combat`, client `Physiology`)
- multiplayer uses a server runtime (`MPServerRuntime`) for endurance, fatigue, wake-edge sync, and melee strain
- multiplayer clients cache server-pushed snapshots through `MPClientRuntime`
  for UI display; minute polling is recovery-only when the cache is missing or
  stale, while local clothing refresh requests are coalesced and remote-player
  clothing events are ignored
- multiplayer session-start snapshot requests (`OnConnected`, `OnCreatePlayer`) reset stale per-player catch-up so offline time is not replayed as live endurance drain
- MP snapshot refresh runs the shared physiology path at `dt=0` so runtime snapshot fields stay current without applying gameplay drain
- if MP shared-input preparation fails, the server drops pending catch-up instead of retrying an unbounded stale backlog
- release builds keep a hidden server-first MP incident recorder that freezes suspicious endurance events and mirrors them into support reports without exposing separate debug UI
- mirrored incident traces stay on one `seq` while the server is still filling the post-trigger window, so clients must accept fuller same-seq payloads and the recorder must keep repeated suspicious rows instead of treating them as duplicates
- active, non-sleep endurance replay is capped to one game minute; stale active catch-up is discarded after anchoring the endurance baseline to the current stat so one current activity label cannot replay a long backlog
- the MP runtime also applies one conservative burst-drain guard: if AMS-only endurance loss becomes abnormal inside a single server update invocation, replay stops and the remaining pending replay is discarded
- combat is contextual state, not a locomotion drain band: vanilla 42.18 owns melee stamina per swing/hit, while AMS uses recent combat for regen, breathing context, UI/snapshot attribution, and armor strain
- stationary aiming does not start or refresh AMS combat context and does not raise the activity factor
- shared load/model code lives in `shared/` so SP and MP use the same armor profile math
- custom sandbox options must use dotted ids such as `ArmorMakesSense.EnableThermalModel`; `page = ArmorMakesSense` only affects sandbox UI grouping and does not create `SandboxVars.ArmorMakesSense`

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
- tab injection, controller tab switching, and fallback window behavior

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
- `server/ArmorMakesSense_MPIncidentRecorder.lua` — MP incident ring buffer, trigger detection, and frozen-trace export
- `media/sandbox-options.txt` — custom sandbox option definitions for server-authoritative AMS gameplay toggles

### Shared
- `shared/ArmorMakesSense_Config.lua` — tuning defaults
- `shared/ArmorMakesSense_Compat.lua` — cross-mod compat registry bootstrap
- `shared/ArmorMakesSense_MPCompat.lua` — MP constants and command names
- `shared/ArmorMakesSense_MPIncidentSchema.lua` — MP incident trace shape, thresholds, and trigger ids
- `shared/ArmorMakesSense_ArmorClassifier.lua` — armor-vs-civilian classification
- `shared/ArmorMakesSense_BreathingClassifier.lua` — respiratory classification
- `shared/ArmorMakesSense_LoadModelShared.lua` — shared item-to-load and profile aggregation
- `shared/ArmorMakesSense_EnvironmentShared.lua` — shared MP environment/activity sampling
- `shared/ArmorMakesSense_PhysiologyShared.lua` — shared endurance/thermal/breathing/sleep formulas
- `shared/ArmorMakesSense_StrainShared.lua` — shared melee strain logic
- `shared/ArmorMakesSense_SlotCompat.lua` — custom body locations and compatibility rules
- `shared/ArmorMakesSense_SpeedRebalance.lua` — worn item discomfort zeroing, speed overrides, and reslots

### Client core and models
- `client/core/ArmorMakesSense_Utils.lua` — utility helpers
- `client/core/ArmorMakesSense_Environment.lua` — client environment and activity sampling
- `client/core/ArmorMakesSense_LoadModel.lua` — client load-model wrapper
- `client/core/ArmorMakesSense_UI.lua` — local inventory-tooltip patch and burden UI
- `client/core/ArmorMakesSense_ContextFactory.lua` — client context builder
- `client/ArmorMakesSense_Main.lua` — client boot facade and runtime registration; sleep planner hooks are now installed only after a confirmed local player exists
- `client/ArmorMakesSense_SleepHooks.lua` — planner hooks for manual and auto-sleep; installed on the same delayed local-player seam as CMS so MP bed sleep uses the corrected wrapper path instead of the old eager boot seam
- `client/core/ArmorMakesSense_ContextBinder.lua` — context injector
- `client/core/ArmorMakesSense_ContextRefs.lua` — stable context references
- `client/core/ArmorMakesSense_Bootstrap.lua` — thin binding/runtime helpers
- `client/core/ArmorMakesSense_State.lua` — options and per-player state
- `client/core/ArmorMakesSense_Tick.lua` — per-minute tick pipeline
- `client/core/ArmorMakesSense_Combat.lua` — combat event forwarding
- `client/core/ArmorMakesSense_Strain.lua` — SP strain overlay
- `client/core/ArmorMakesSense_IncidentTrace.lua` — client-held mirrored MP incident traces and support-report section formatter
- `client/core/ArmorMakesSense_WearDebug.lua` — worn-item telemetry
- `client/core/ArmorMakesSense_Runtime.lua` — SP lifecycle management
- `client/core/ArmorMakesSense_Stats.lua` — stat IO and bench reset helpers
- `client/models/ArmorMakesSense_Physiology.lua` — SP physiology model and UI runtime snapshot production

### Diagnostics
- `client/diagnostics/ArmorMakesSense_MPDiagnosticsClient.lua` — MP-client-only diagnostics receive/logging path
- `client/diagnostics/ArmorMakesSense_MPClientHarness.lua` — MP-client-only harness ping path
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

## Cross-Mod Compat

AMS now participates in the shared `MakesSenseCompat` protocol when the other
`Makes Sense` mods are loaded.

- AMS remains the endurance coordinator in stacked mode because it already owns
  the catch-up loop and final endurance write.
- NMS now feeds deprivation-based endurance suppression and activity drain into
  AMS through compat callbacks instead of racing the live endurance stat.
- AMS now expresses sleep-in-armor as a penalty fraction against vanilla sleep
  recovery, which lets standalone AMS stay vanilla-shaped while also giving the
  planner a coherent signal.
- AMS now mirrors CMS’s split between planner and runtime sleep logic:
  planner penalty is estimated from current rigidity and fatigue before sleep,
  while active sleep penalty is applied continuously during the sleep window.
- in multiplayer, AMS now uses the same delayed local-player install seam as CMS
  and only installs its own sleep planner hooks when CMS is not already the
  compat coordinator. When AMS is the fallback coordinator, it uses the shared
  compat penalty aggregation path instead of a mod-specific planner shortcut.
- the active fatigue write stays authoritative on the server. The MP client
  still resolves the penalty fraction for planning and diagnostics, but does not
  apply the fatigue write locally.
- on wake, AMS now prefers the actually observed wake fatigue result when the
  wake transition has already changed fatigue. When CMS is absent, the
  authoritative MP server ignores observed deltas that point opposite the
  expected bed-quality direction and synthesizes the missing bed-based delta
  once; when CMS is present, AMS backs off and lets CMS coordinate that wake
  adjustment.
- MP wake fatigue now uses a hard server-authoritative cutover:
  - MP clients no longer synthesize wake fatigue or call local `wakeUp` paths
  - MP server tracks asleep→awake transitions on `OnPlayerUpdate` with a
    dedicated wake-sync asleep marker, instead of reusing generic runtime sleep
    bookkeeping that other snapshot updates can consume
  - MP server pushes an immediate `WakeTransition` snapshot from the same
    authoritative runtime
  - while sleeping, `OnPlayerUpdate` pushes realtime (`~1s`) sleep sync snapshots
    so client fatigue cannot drift far during fast-forward tails; all sleeping
    snapshot sources share the same wall-clock send cap
  - MP server also sends native `syncPlayerStats` for FATIGUE on wake edge so the
    waking client receives vanilla stat authority immediately
  - while sleeping, MP server sends native FATIGUE stat sync at most once per
    five wall-clock seconds, so accelerated game minutes cannot multiply packet
    traffic while the snapshot path keeps the client current
  - snapshots now include authoritative fatigue, and MP clients apply that
    value for `WakeTransition` and sleeping snapshots
  - awake non-wake snapshots never lower local fatigue; they only serve wake-edge
    correction to prevent post-wake false dips
  - wake-transition snapshots also reconcile local sleep flags
    (`asleep=false`, `asleepTime=0`, `forceWakeUpTime=-1`) when the server
    declares the player awake
  - this keeps SP behavior unchanged while removing MP client prediction drift
    and random-range mismatch against vanilla wake fatigue
- when CMS is present, AMS no longer writes sleep fatigue directly.
- instead, AMS exposes sleep penalty fractions and CMS composes them into its
  canonical fatigue path during the actual sleep window.
- AMS now also exposes explicit AMS-vs-NMS endurance attribution for the shared
  dev compat trace instead of hiding both sources inside one combined applied
  delta.
