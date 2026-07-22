# Armor Makes Sense - Technical Overview

## Scope

AMS has separate singleplayer and multiplayer execution paths backed by shared
load and physiology modules. The server owns multiplayer gameplay state. The
client owns presentation, local singleplayer execution, and development tools.

## Reference Documents

- [Runtime Reference](./armor_makes_sense-runtime_reference.md): classification,
  load aggregation, physiology, strain, sleep, slots, and configuration
- [Multiplayer Reference](./armor_makes_sense-mp_reference.md): authority,
  snapshot transport, network state, and diagnostics
- [UI Reference](./armor_makes_sense-ui_reference.md): tooltips, Burden panel,
  refresh behavior, and controller handling
- [Testing Reference](./armor_makes_sense-testing_reference.md): test API,
  benchmark runner, scenarios, and report pipeline
- [Design Principles](./armor_makes_sense-design_manifesto.md): gameplay goals
  and non-goals

## Runtime Architecture

### Singleplayer

`ArmorMakesSense_Main.lua` loads the client entrypoints, registers the
compatibility provider, and asks `ArmorMakesSense_Bootstrap.lua` to select
exactly one client role. Production modules require their collaborators
directly. `ArmorMakesSense_ClientRuntime.lua` owns client lifecycle state,
logging, version reporting, and role-aware player-state access. In singleplayer,
`EveryOneMinute` advances the gameplay model,
`OnPlayerUpdate` handles sleep-time updates, and combat events apply the local
muscle-strain overlay. Sleeping advances fatigue recovery penalties but pauses
the endurance pipeline. The SP runtime registers only
handlers with active behavior; its former no-op weapon-swing subscription was
removed.

Development builds load `testing/ArmorMakesSense_00_DevBootstrap.lua` separately.
It owns test-module imports, command contexts, global console bindings,
environment locks, equilibrium resets, and benchmark pumps. None of those paths
are present in Main or the production runtime modules.
Its event registrations replace earlier development handlers after Lua reload,
and benchmark speed restoration uses PZ's configured `getTrueMultiplier` value.

### Multiplayer

`ArmorMakesSense_MPServerRuntime.lua` owns endurance, sleep fatigue, wake
correction, and melee strain. Its weapon-swing handler delegates eligibility,
vanilla-option gating, magnitude, and stat application to the same shared
strain policy used in SP. Clients request snapshots at session boundaries,
after local clothing changes, or when cached state is missing or stale. Normal
updates are pushed by the server. Requests carry only their reason and the
client's latest incident sequence. Responses transport numeric thermal signals;
the client derives hot/cold presentation from those values.

The MP client runtime is inert when loaded. The production bootstrap calls its
explicit registration entrypoint only when `isClient()` identifies a
multiplayer client. SP gameplay handlers are not registered in that role. The
MP runtime requires the shared client UI directly and owns its refresh calls.

The MP server and SP client use the same shared load, environment, strain,
physiology, and simulation-advance modules. Coordinators sample PZ state and
own UI, incident, and network side effects; the shared advance operation owns
elapsed accumulation, active catch-up limits, slicing, and model call order.
Both coordinators omit the endurance callback during sleep.

### Vanilla Runtime Contracts

The model integrations were checked against the installed Project Zomboid
42.19.0 runtime. Vanilla alone initializes `SleepingEvent`; AMS never calls
`setPlayerFallAsleep` after vanilla has started sleep because that API resets
sleep-event state and reapplies the delay-to-sleep timer. When a planner penalty
is active, AMS only extends vanilla's existing wake time. With the penalty
disabled, it leaves the planned wake time untouched. Active multiplayer sleep
clients send only a bed-type hint and preserve the server-delegated
`SleepAllowed` branch.
The server applies that hint to the vanilla player so continuous bed recovery
matches the client, while AMS retains only the bounded wake reconciliation
needed when the server does not observe vanilla's client-side wake adjustment.
Authoritative MP wake reconciliation calls vanilla `SleepingEvent:wakeUp` with
packet echo suppressed instead of directly editing player sleep fields. AMS
does not claim this authority when its sleep model is disabled or CMS owns
fatigue coordination.

All AMS/CMS sleep handoffs resolve through
`ArmorMakesSense_SleepOwnership.lua`. Planner, continuous-fatigue, and
wake-adjustment ownership are separate capabilities; gameplay coordinators do
not duplicate compatibility probes or capability names.

Thermoregulator node samples are weighted by vanilla `ThermalNode` skin
surface. Equal weighting is used only when `getSkinSurface()` is unavailable.
This matches vanilla's use of body-part surface area in heat calculations and
prevents small regions from dominating whole-body telemetry.

Physical load intentionally starts from `InventoryItem.getEquippedWeight()`.
In the checked runtime this applies vanilla's `0.3` equipped-or-worn
encumbrance multiplier. AMS tuning was calibrated against that value; replacing
it with raw item mass would be a model rebalance, not an accuracy correction.

Shared gameplay modules import `ArmorMakesSense_UtilsShared.lua` and
`ArmorMakesSense_StatsShared.lua` directly. They do not accept mutable runtime
contexts. Activity sampling describes movement and sleep only. Combat events
apply one shared per-swing armor strain policy and create no sampled state.
Breathing demand takes the greater of vanilla's smoothed thermoregulator rate
and the 3.1/6.9/9.5 MET anchor for the existing native walk/run/sprint label.
The public metabolic-target getter is not used because vanilla clears that
scratch field before Lua events can sample it. AMS does not maintain a parallel
combat or exertion latch.

The shared load model requires both equipment classifiers directly. It computes
armor signals once per included item and evaluates those signals through the
classifier's pure decision entrypoint; runtime contexts do not carry duplicate
keyword tables or fallback classification formulas.

Worn equipment is normalized as burden rather than gated by the armor label.
`itemToBurdenSignal` records why a row was included and why it was classified
as armor-like. The explicit `AMSIncludeBurden`, `AMSExcludeBurden`, and
`AMSArmor` tags form the narrow override contract for third-party gear.
Physical calculations read movement modifiers cached before AMS applies its
direct speed rebalance, so movement policy cannot feed back into burden.
Thermal resistance is sampled separately from vanilla's effective
thermoregulator nodes and is not inferred from item defense or movement stats.

The worn profile has one canonical name per channel: `physicalLoad`,
`airflowResistance`, `sealedRestriction`, `rigidityLoad`, and `swingChainLoad`.
`driverCount` names the number of physical cost drivers. Thermal resistance is
physiology telemetry, not a worn-profile channel. Historical aliases and the
ambiguous precomputed combined load are not published.

Respiratory equipment publishes two distinct signals: additive
`airflowResistance` and explicit `sealedRestriction`. Worn profiles sum airflow
but take the maximum sealed restriction. Physiology never infers a sealed state
from an aggregate numeric threshold, and breathing cannot reduce unrelated
physical burden.

Server snapshots are encoded and decoded by
`ArmorMakesSense_MPSnapshotCodec.lua`. The codec owns the wire-field mapping,
driver-row mapping, defaults, and schema validation. Schema version 4 is a hard
contract; clients reject snapshots with a missing or different version.

Simulation is explicitly fail-open. Results distinguish attempted, committed,
and discarded slices/minutes; a failed slice is discarded because a callback
may already have partially mutated PZ state. Stat writes use one server-first
execution-role resolver, so a listen server retains authority while a pure MP
client cannot write gameplay stats.

## Source Layout

| Path | Contents |
|---|---|
| `mod.info` | Root metadata |
| `common/media/lua/shared/` | Shared configuration, classification, models, compatibility, and slot rules |
| `common/media/lua/client/` | Client entrypoints, UI, SP runtime, diagnostics, and testing |
| `common/media/lua/server/` | MP authority and server diagnostics |
| `common/media/sandbox-options.txt` | Server-authoritative gameplay toggles |
| `42/mod.info` | Build 42 metadata override |

`common/` is the runtime source of truth. `42/` contains metadata only and does
not duplicate `common/media`.

## Module Ownership

### Entry Points

- `client/ArmorMakesSense_Main.lua`: client startup, sleep hooks, and
  compatibility provider
- `client/core/ArmorMakesSense_Bootstrap.lua`: client role detection and
  exclusive runtime registration
- `client/ArmorMakesSense_MPClientRuntime.lua`: MP snapshot transport and client
  reconciliation with explicit, side-effect-free registration
- `server/ArmorMakesSense_MPServerRuntime.lua`: MP gameplay authority and
  snapshot production
- `client/ArmorMakesSense_SleepHooks.lua`: sleep planner integration and MP bed-type
  hint transport

### Shared Model

- `ArmorMakesSense_Config.lua`: default tuning values
- `ArmorMakesSense_UtilsShared.lua`: numeric, boolean, protected-method, role,
  world-time, and wall-clock helpers used by both authorities, classifiers,
  sleep hooks, and script-item rebalance code
- `ArmorMakesSense_Options.lua`: canonical typed sandbox-option resolution for
  SP and MP authority
- `ArmorMakesSense_StatsShared.lua`: character stat, body-state, and metabolic
  telemetry IO with MP client writes blocked at the authority boundary
- `ArmorMakesSense_ArmorClassifier.lua`: canonical armor signals and classification
- `ArmorMakesSense_BreathingClassifier.lua`: canonical respiratory equipment signals
- `ArmorMakesSense_LoadModelShared.lua`: per-item signals and canonical worn-gear analysis for gameplay, UI, MP snapshots, and reports
- `ArmorMakesSense_EnvironmentShared.lua`: activity and posture sampling
- `ArmorMakesSense_ThermalModel.lua`: effective node resistance, sustained hot
  pressure, cold suitability, and thermal contribution
- `ArmorMakesSense_BreathingModel.lua`: pure metabolic-effort and respiratory contribution result
- `ArmorMakesSense_EnduranceModel.lua`: pure regeneration and drain composition result
- `ArmorMakesSense_SleepModel.lua`: pure vanilla-recovery and rigidity-penalty result
- `ArmorMakesSense_PhysiologyShared.lua`: PZ sampling, model composition,
  compatibility coordination, result application, and runtime snapshots
- `ArmorMakesSense_Simulation.lua`: elapsed-time accumulation, active catch-up
  policy, bounded slicing, and shared sleep/endurance advancement
- `ArmorMakesSense_StrainShared.lua`: melee strain eligibility and magnitude
- `ArmorMakesSense_SpeedRebalance.lua`: discomfort removal, curated speed values,
  and item reslots
- `ArmorMakesSense_SlotCompat.lua`: custom body locations and compatibility rules
- `ArmorMakesSense_Compat.lua`: `MakesSenseCompat` registry
- `ArmorMakesSense_MPCompat.lua`: MP protocol constants and build identity
- `ArmorMakesSense_RuntimeState.lua`: isolated transient SP, MP-client, and
  MP-server state stores
- `ArmorMakesSense_MPSnapshotCodec.lua`: versioned server snapshot wire codec
- `ArmorMakesSense_MPIncidentSchema.lua`: incident trace schema and thresholds
- `client/testing/ArmorMakesSense_BenchRunnerSnapshot.lua`: streamed benchmark
  artifact writer with compact snapshot fallback; successful streams are finalized
  in place so transient samples and probes remain available to parsers
- benchmark step preparation owns time pinning and rebases the simulation clock;
  activity drivers preserve that continuous timeline instead of resetting it

### Client Core

- `ArmorMakesSense_ClientRuntime.lua`: client lifecycle flags, logging,
  version metadata, protected PZ calls, and role-aware state lookup
- `ArmorMakesSense_State.lua`: options and per-player state initialization
- `ArmorMakesSense_Tick.lua`: singleplayer scheduling, input sampling, and UI
- `ArmorMakesSense_Runtime.lua`: event registration and lifecycle guards
- `ArmorMakesSense_Combat.lua`: singleplayer combat event handling
- `ArmorMakesSense_UI.lua`: Burden panel, character-tab integration, help, and
  support export
- `ArmorMakesSense_UITooltip.lua`: wearable-item tooltip patching and AMS
  burden and breathing rows
- `ArmorMakesSense_SupportReport.lua`: support report collection and formatting
- `ArmorMakesSense_IncidentTrace.lua`: mirrored MP incident storage and report
  formatting

Production client modules do not use mutable dependency contexts. The
development benchmark modules retain their separate context because their job
is to run controlled substitutions and scenarios rather than game runtime.

### Diagnostics and Testing

- `client/diagnostics/` and `server/diagnostics/`: MP ping, dump, and sleep
  diagnostics for development builds
- `client/testing/`: command API, gear helpers, scenarios, benchmark execution,
  snapshots, and reports
- `client/testing/ArmorMakesSense_00_DevBootstrap.lua`: development-only module
  loading, context construction, global API binding, and event pumps
- `client/testing/ArmorMakesSense_DevPanel.lua`: development-only live model
  inspector and operator controls for environment, gear, reports, and
  benchmarks; protected single-value reads are collapsed before numeric
  conversion to avoid Kahlua treating extra return slots as a numeric base
- `client/testing/ArmorMakesSense_Reset.lua`: destructive equilibrium and body
  reset helpers used by controlled tests
- benchmark catalogs and scenarios are validated before execution; unknown
  blocks or activities, missing production runtime telemetry, and incomplete
  parser inputs fail closed instead of producing zero-filled measurements
- real-sleep benchmarks accept only fatigue-threshold recovery; external wakes,
  failed entry, and safety timeouts are invalid measurements
- native benchmark movement is explicitly cancelled before path state is
  cleared; transient thermal runs use minute-aligned activity windows and end
  their rest sample on a fresh production tick
- coordinate resets use PZ's `teleportTo` lifecycle; climate overrides preserve
  the previous admin channel state; benchmark cleanup restores the exact worn
  item objects and emits the vanilla clothing-update event
- benchmark plans do not support perk/XP mutation; controlled equilibrium reset
  remains intentionally destructive and is for disposable test characters
- `server/ArmorMakesSense_MPIncidentRecorder.lua`: bounded release-path incident
  capture used by support reports

Workshop packaging excludes the development testing and diagnostics modules.
It validates that remaining Lua has no development references and does not
rewrite source files during staging.

## State and Authority

Runtime state is held in three weak-key tables indexed by player identity. It is
not written to player `modData` or save files.

- SP state stores timing, endurance baselines, runtime snapshots, and sleep state.
- MP client state stores request timing and the latest server snapshot.
- MP server state stores authority timing, catch-up, sleep synchronization,
  thermal state, runtime snapshots, and bounded incident data.

On first access for a player, `ArmorMakesSense_RuntimeState.lua` deletes the
obsolete `ArmorMakesSenseState` save blob without importing any values from it.
Reloads and reconnects therefore start with current time and live stats instead
of replaying saved catch-up state.

Active non-sleep catch-up is capped at one game minute. Sleep catch-up remains
time-based because fatigue recovery advances during accelerated sleep.

## Configuration

`ArmorMakesSense_Config.lua` defines tuning defaults. Public sandbox options are
limited to these model toggles:

- `ArmorMakesSense.EnableThermalModel`
- `ArmorMakesSense.EnableMuscleStrainModel`
- `ArmorMakesSense.EnableSleepPenaltyModel`

Both SP and MP resolve `ArmorMakesSense.DEFAULTS` first and then apply matching
values from `SandboxVars.ArmorMakesSense`.

## Makes Sense Compatibility

AMS registers these `MakesSenseCompat` capabilities:

- `endurance_coordinator`
- `sleep_penalty_provider`
- `sleep_planner_penalty_provider`

Nutrition Makes Sense can provide an endurance contribution that AMS composes
before the final endurance write. Caffeine Makes Sense can own fatigue and sleep
coordination; when it does, AMS supplies penalty fractions and does not write
the coordinated fatigue result independently.

## Version Identity

Release identity is defined in:

- `mod.info`
- `42/mod.info`
- `shared/ArmorMakesSense_MPCompat.lua`

The workspace sync tool validates alignment across all three locations.
