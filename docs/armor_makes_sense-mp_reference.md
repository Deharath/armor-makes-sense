# Armor Makes Sense - Multiplayer Reference

## Authority Model

| Context | Responsibility |
|---|---|
| Singleplayer client | Gameplay calculations and UI state |
| Multiplayer server | Endurance, sleep fatigue, wake correction, melee strain, and snapshots |
| Multiplayer client | Snapshot requests, UI cache, and server-authoritative sleep reconciliation |

The MP client does not run the local gameplay mutation path. Shared model code
under `common/media/lua/shared/` is used by both the SP client and MP server.
Shared utilities and character-stat IO are required directly; the server no
longer installs its own copies into model contexts.

## Server Runtime

`server/ArmorMakesSense_MPServerRuntime.lua` registers these events:

| Event | Use |
|---|---|
| `OnClientCommand` | Snapshot requests and sleep bed-type hints |
| `EveryOneMinute` | Per-player model advancement and normal snapshot push |
| `OnWeaponSwing` | Per-swing armor strain |
| `OnPlayerUpdate` | Sleep updates and asleep-to-awake detection |
| `OnGameBoot` | Runtime identity log |

Active non-sleep catch-up is capped at one game minute. When pending active
catch-up exceeds the cap, the server anchors `lastEnduranceObserved` to the live
stat and discards the excess. Sleep catch-up remains time-based.

Shared-input failures discard pending catch-up. The incident recorder also
aborts an invocation when AMS-only endurance loss crosses its burst threshold.

Elapsed accumulation, active catch-up capping, bounded slicing, and
sleep/endurance call order come from `shared/ArmorMakesSense_Simulation.lua`,
the same operation used by singleplayer. The server coordinator owns input
sampling, sleep-only policy, incident callbacks, native stat synchronization,
and snapshot transport.
The sleep-only policy is also used by SP, so armor does not throttle endurance
recovery while a player is asleep in either authority mode.

All AMS-owned server runtime modules are direct requirements. Missing shared
models, protocol constants, codecs, or incident schema stop initialization
instead of selecting an empty or reduced behavior path.

## Client Runtime

`client/ArmorMakesSense_MPClientRuntime.lua` has no module-load side effects.
The client bootstrap calls `MPClientRuntime.registerEvents()` only when
`isClient()` selects the multiplayer role. The singleplayer runtime is not
registered in that session.

MP registration requires:

| Event | Use |
|---|---|
| `OnServerCommand` | Parse snapshots and incident traces |
| `OnConnected` | Reset cache and request initial state |
| `OnCreatePlayer` | Reset cache for the local player and request state |
| `OnClothingUpdated` | Request a rate-limited refresh for local clothing changes |
| `EveryOneMinute` | Expire stale state and request recovery only when needed |

Clothing events for remote players are ignored. A healthy client consumes
server minute pushes without sending a matching minute request.

The MP runtime imports the shared client UI and options modules directly. It
installs UI hooks when the local player is available and marks the UI dirty
when snapshot state changes.

## Snapshot Protocol

Protocol constants are defined in `shared/ArmorMakesSense_MPCompat.lua`.
`shared/ArmorMakesSense_MPSnapshotCodec.lua` is the only snapshot wire-field
encoder and decoder.

| Constant | Value |
|---|---|
| Network module | `ArmorMakesSenseRuntime` |
| Request command | `request_snapshot` |
| Response command | `snapshot` |
| Request throttle | 2 wall-clock seconds |
| Client cache expiry | 10 wall-clock seconds |
| Snapshot schema | `2` |

### Client Requests

A request contains:

- reason
- latest known incident sequence

Load, connect, create-player, and clothing requests share the same request
throttle. `EveryOneMinute` requests `SnapshotRecovery` only when the cached
snapshot is absent or expired.

### Server Responses

The server returns aggregate load, activity, numeric environment and endurance
telemetry, fatigue, sleep state, physical cost drivers, and optional incident data.
Every response includes `snapshot_schema_version`. The client rejects a missing
or unsupported schema instead of interpreting a partial payload.

The response contains these field groups:

| Group | Fields |
|---|---|
| Load | physical, airflow resistance, sealed restriction, rigidity, effective load, driver count |
| Thermal | availability, effective resistance, hot pressure, strain scale, cold suitability, contribution |
| Breathing | smoothed metabolic rate, immediate metabolic demand, normalized effort, effort ramp, open and sealed contribution |
| Endurance | before, after, natural delta, applied delta, applied time, pending catch-up |
| State | activity label, update minute, fatigue, sleeping flag, reason |
| Attribution | physical cost drivers and optional incident trace |

Request-triggered refreshes run the physiology model with `dtMinutes = 0`.
This updates telemetry without applying drain, changing regeneration, invoking
NMS endurance contribution, or writing endurance.

## Sleep and Wake Synchronization

The server tracks the sleep edge independently from general runtime sleep state.

- Sleeping snapshots are capped at one per wall-clock second across all server
  update sources.
- Native FATIGUE synchronization while sleeping is capped at one send per five
  wall-clock seconds.
- An asleep-to-awake transition produces a `WakeTransition` snapshot and native
  FATIGUE synchronization with mask `16`.
- Sleeping and wake-transition snapshots may update client fatigue.
- Awake snapshots with other reasons do not lower client fatigue.
- A server-declared wake runs vanilla `SleepingEvent:wakeUp(player, true)`,
  preserving fade-in, event cleanup, bed effects, and sleep bookkeeping without
  echoing another wake packet.
- The client bed-type hint is applied to the server player, allowing vanilla's
  continuous sleep recovery to use the same bed multiplier on both sides.

These limits are wall-clock based, so accelerated co-op sleep does not multiply
network traffic.

Wake fatigue is derived and synchronized by the server. Released runtime does
not accept a client-supplied fatigue correction; the development-only sleep
diagnostic command is handled only by the excluded diagnostics modules. When
the server did not observe a native bed wake adjustment, it synthesizes the
versioned mean adjustment without mistaking ordinary final recovery for it.
When the AMS sleep model is disabled, or CMS advertises fatigue coordination,
AMS sends no sleep fatigue synchronization and performs no client wake or
fatigue reconciliation.

The shared `ArmorMakesSense_SleepOwnership.lua` module owns this handoff. CMS
planner and wake-adjustment capabilities remain independent from continuous
fatigue authority; an unrelated capability cannot accidentally disable AMS MP
fatigue synchronization.

## Multiplayer Transient State

Client state is stored in the weak-key `multiplayer_client` store:

- `mpClient.lastRequestWallSecond`
- `mpClient.lastSnapshotWallSecond`
- `mpServerSnapshot`

Server state is stored separately in the weak-key `multiplayer_server` store:

- `lastUpdateGameMinutes`
- `lastEnduranceObserved`
- `pendingCatchupMinutes`
- `runtimeSnapshot`
- `lastWakeSyncAsleepFlag`
- `lastSleepSnapshotSentWallSecond`
- `lastSleepFatigueSyncWallSecond`
- `lastSleepRealtimeUpdateWallSecond`
- `thermalModelState`
- `incidentRecorder`

Neither store is saved. The first state access removes the obsolete
`ArmorMakesSenseState` player blob without importing its timing, catch-up, or
snapshot values.

## Option Resolution

The MP server resolves options in this order:

1. `ArmorMakesSense.DEFAULTS`
2. matching values from `SandboxVars.ArmorMakesSense`

The public MP gameplay toggles are thermal burden, muscle strain, and sleep
penalties.

The server weapon-swing handler calls the shared strain application policy.
That policy honors both the AMS toggle and vanilla `muscleStrainFactor`; the
server does not reproduce eligibility or magnitude calculations. Weapon swings
do not create endurance, breathing, or activity state on the server.

## Incident Capture

`server/ArmorMakesSense_MPIncidentRecorder.lua` keeps a bounded per-player ring
buffer. It freezes a trace for abnormal time steps, catch-up, natural endurance
drops, or AMS-applied endurance drops. The client sends only the request reason
and its latest incident sequence; the server sends a trace only when the client
is behind.

The client appends the latest trace to the exported support report. Incident
capture is part of the release runtime and has no separate player-facing UI.

## Development Diagnostics

Development builds provide:

- `ams_mp_ping(reason)` through the client/server harness pair
- `ams_mp_diag_dump(reason)` to request a server state dump
- `ams_mp_diag_last()` to read the latest client-held dump
- optional server minute summaries gated by
  `_G.ams_enable_mp_diag_minute_summary == true`

The Workshop packaging process excludes files under the client and server
`diagnostics/` directories. Staging validates that remaining Lua has no
development references and does not rewrite runtime source files.

## Modules

- `client/ArmorMakesSense_MPClientRuntime.lua`: client transport and
  reconciliation
- `server/ArmorMakesSense_MPServerRuntime.lua`: gameplay authority
- `server/ArmorMakesSense_MPIncidentRecorder.lua`: bounded incident capture
- `shared/ArmorMakesSense_MPCompat.lua`: protocol constants
- `shared/ArmorMakesSense_SleepOwnership.lua`: AMS/CMS sleep authority policy
- `shared/ArmorMakesSense_MPSnapshotCodec.lua`: versioned snapshot wire codec
- `shared/ArmorMakesSense_MPIncidentSchema.lua`: trace schema and thresholds
- `client/core/ArmorMakesSense_IncidentTrace.lua`: client trace cache and report
  formatter
- `client/diagnostics/ArmorMakesSense_MPDiagnosticsClient.lua`: diagnostic dump
  client
- `server/diagnostics/ArmorMakesSense_MPDiagnosticsServer.lua`: diagnostic dump
  server
- `client/diagnostics/ArmorMakesSense_MPClientHarness.lua`: ping client
- `server/diagnostics/ArmorMakesSense_MPServerHarness.lua`: ping server
