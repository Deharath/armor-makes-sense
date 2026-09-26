# Armor Makes Sense - Multiplayer Reference

## Authority Model

| Context | Responsibility |
|---|---|
| Singleplayer client | Gameplay calculations and UI state |
| Multiplayer server | Endurance, sleep fatigue penalties, melee strain, and snapshot production |
| Multiplayer client | On-demand UI snapshots and local presentation |

The MP client never advances the gameplay model. Shared model code under
`common/media/lua/shared/` is used by both the SP client and MP server, while
the server remains the only multiplayer authority for gameplay stats.

## Server Runtime

`server/ArmorMakesSense_MPServerRuntime.lua` registers these events:

| Event | Use |
|---|---|
| `OnClientCommand` | Accept throttled snapshot requests and send projected snapshots |
| `EveryOneMinute` | Run the authoritative physiology tick for each online player |
| `OnWeaponSwing` | Mark the tick window as fighting, then apply melee strain using the latest cached worn profile |

Each minute, the server resolves options, analyzes worn gear, calls
`Physiology.tick(player, mpState, options, profile, worldAgeMinutes)`, attaches
cost-driver rows, and stores the result as `mpState.runtimeSnapshot`. If the
sleep model added fatigue during the tick, the server calls
`syncPlayerStats(player, 16)` so vanilla stat sync carries the fatigue change.

The shared tick rebases instead of applying an endurance adjustment when there
is no previous minute, elapsed time is zero, the player is asleep, or elapsed
time is greater than `MaxStepMinutes` (30 by default). Sleeping still runs the
sleep penalty step, but endurance scaling is skipped for that minute.

The cached worn profile is refreshed during normal model sampling. Weapon swings
reuse a profile for up to one wall-clock second instead of traversing all worn
items on every attack, while bounding how long a recent equipment change can
affect strain calculation.

## Client Runtime

`client/ArmorMakesSense_MPClientRuntime.lua` has no module-load event side
effects. The multiplayer bootstrap explicitly registers only:

| Event | Use |
|---|---|
| `OnServerCommand` | Decode an addressed snapshot |
| `OnConnected` | Clear local snapshot state and ensure UI hooks |
| `OnCreatePlayer` | Clear that local player's cache and ensure UI hooks |

The transport runtime does not subscribe to clothing or minute events. Clothing
changes only dirty the client UI. The panel rebuilds deterministic gear burden,
breathing restriction, rigidity, cost drivers, and per-pace presentation scales
from the local worn-item collection; it does not send a clothing-triggered
request.

The visible panel requests dynamic server telemetry only when its cache is
missing or older than 30 seconds. A hidden panel generates no snapshot traffic.
Support-report export asks for one when no cached server snapshot exists and
tells the player to retry after it arrives.

`BurdenPanel`'s `collectSnapshot` uses the cached server snapshot as a thermal
source only. In multiplayer, it calls
`Physiology.projectWithServerThermal(player, options, profile, serverSnapshot)`:
the client's current worn items provide burden, respiratory restriction, sleep
penalty, cost drivers, and local presentation scales, while `heat`,
`thermalResistance`, `hotPressure`, and `coldSuitability` come from the latest
server snapshot. If no server snapshot is cached yet, only the Heat row shows a
waiting state. Gameplay remains server-authoritative.

## Snapshot Protocol

Protocol constants live in `shared/ArmorMakesSense_MPCompat.lua`.
`shared/ArmorMakesSense_MPSnapshotCodec.lua` exclusively owns the full snapshot
wire mapping.

| Constant | Value |
|---|---|
| Network module | `ArmorMakesSenseRuntime` |
| Request command | `request_snapshot` |
| Response command | `snapshot` |
| Client and server request floor | 5 wall-clock seconds per player |
| Pending request timeout | 60 wall-clock seconds |
| UI cache freshness window | 30 wall-clock seconds |
| Snapshot schema | `8` |

### Client Requests

A request has an empty argument table. Player identity comes from PZ's
player-aware command dispatch.

Only one request may be pending on the client. Further UI collections reuse that
pending state for up to 60 seconds rather than resending. Both client and server
also enforce a five-second request floor per player.

A request is presentation-only. Its handler never advances authoritative
physiology or changes endurance. It samples current worn gear, computes a
read-only projection through `Physiology.project`, stores it in
`mpState.runtimeSnapshot`, and returns it immediately.

### Server Responses

Full snapshots are player-addressed and sent only to satisfy queued demand.
There are no automatic connect, create-player, clothing, or minute full snapshot
pushes.

The Burden tab consumes the snapshot's thermal fields as server-authoritative
presentation context and recomputes gear-derived display values locally. The
wire payload still includes the full runtime shape for diagnostics, support
reports, and parser stability.

Every response includes `snapshot_schema_version`; the client rejects missing or
unsupported schemas. The codec maps these numeric fields:

| Wire field | Runtime field |
|---|---|
| `burden_kg` | `burdenKg` |
| `arm_kg` | `armKg` |
| `rigid_kg` | `rigidKg` |
| `driver_count` | `driverCount` |
| `body_kg` | `bodyKg` |
| `strength` | `strength` |
| `load_fraction` | `loadFraction` |
| `heat` | `heat` |
| `thermal_resistance` | `thermalResistance` |
| `hot_pressure` | `hotPressure` |
| `cold_suitability` | `coldSuitability` |
| `airflow_resistance` | `airflowResistance` |
| `sealed_restriction` | `sealedRestriction` |
| `breathing_severity` | `breathingSeverity` |
| `rest_regen_scale` | `restRegenScale` |
| `walk_regen_scale` | `walkRegenScale` |
| `run_drain_scale` | `runDrainScale` |
| `sprint_drain_scale` | `sprintDrainScale` |
| `fight_drain_scale` | `fightDrainScale` |
| `sleep_penalty_fraction` | `sleepPenaltyFraction` |
| `natural_delta` | `naturalDelta` |
| `ams_delta` | `amsDelta` |
| `regen_scale` | `regenScale` |
| `drain_scale` | `drainScale` |
| `nms_regen_scale` | `nmsRegenScale` |
| `nms_drain` | `nmsDrain` |
| `dt_minutes` | `dtMinutes` |
| `updated_minute` | `updatedMinute` |

String fields are `activity_label` and `posture_label`. Boolean
`breathing_enabled` maps to `breathingEnabled`.

Driver rows are optional and use:

| Wire field | Runtime field |
|---|---|
| `label` | `label` |
| `full_type` | `fullType` |
| `burden_kg` | `burdenKg` |

Projection responses use codec defaults for tick-only fields such as
`natural_delta`, `ams_delta`, `regen_scale`, `drain_scale`, `nms_regen_scale`,
`nms_drain`, and `dt_minutes`.

## Request Policy

`server/ArmorMakesSense_MPRequestPolicy.lua` is intentionally small:

| Function | Behavior |
|---|---|
| `acceptSnapshotRequest(mpState, nowSecond, intervalSeconds)` | Rejects requests inside the server request floor and records the accepted wall-clock second |
| `queueSnapshotRequest(mpState)` | Sets `pendingSnapshotRequest = true` |
| `canFlushSnapshot(mpState, snapshot)` | Requires a pending request and a table snapshot |
| `completeSnapshotRequest(mpState)` | Clears the pending flag |

The server refreshes a projection immediately after queueing an accepted
request, then flushes that snapshot if encoding and send succeed.

## Sleep Penalty Synchronization

Sleep planning and wake behavior are vanilla. AMS only applies the stiff-gear
fatigue recovery penalty on the MP server's authoritative minute tick.

When AMS adds extra fatigue and CMS does not own fatigue coordination, the
server uses vanilla stat synchronization for the fatigue stat. When CMS
advertises `fatigue_coordinator`, AMS publishes the penalty fraction through the
compatibility callback and does not write fatigue itself.

No AMS network command carries sleep planning, bed choice, wake timing, or live
fatigue. UI snapshots include `sleep_penalty_fraction` only for presentation.

## Multiplayer Transient State

Client state in the weak-key `multiplayer_client` store includes:

- last request and snapshot wall-clock times;
- one pending-request flag;
- the latest decoded `mpServerSnapshot`.

Server state in the weak-key `multiplayer_server` store includes:

- timing baselines used by the physiology tick;
- fatigue and thermal model state;
- the latest `runtimeSnapshot`;
- one optional pending snapshot request;
- the cached worn profile and its wall-clock timestamp.

Neither store is saved. First access removes the obsolete
`ArmorMakesSenseState` player blob without importing it.

## Option Resolution

The MP server resolves `ArmorMakesSense.DEFAULTS` first and then matching
`SandboxVars.ArmorMakesSense` values. Public multiplayer gameplay options cover
physical load scale, thermal burden, breathing pressure, muscle strain, and
sleep penalties.

## Development Diagnostics

Development builds retain the explicit MP ping and diagnostic-dump harnesses.
The diagnostic server logs `[DUMP]`, `[DUMP_ITEM]`, `[SLEEP]`, and
`[SLEEP_ANOM]` lines using the current burden, breathing, thermal, endurance,
and sleep-penalty fields. Workshop packaging excludes files below
client/server `diagnostics/` and client `testing/`.

## Modules

- `client/ArmorMakesSense_MPClientRuntime.lua`: demand-driven client transport
- `server/ArmorMakesSense_MPServerRuntime.lua`: gameplay authority, cache owner,
  projection refresh, and snapshot sender
- `server/ArmorMakesSense_MPRequestPolicy.lua`: request throttling, queueing,
  and completion flags
- `shared/ArmorMakesSense_MPCompat.lua`: protocol constants
- `shared/ArmorMakesSense_MPSnapshotCodec.lua`: schema-versioned full snapshot
  codec
- `client/diagnostics/ArmorMakesSense_MPDiagnosticsClient.lua`: diagnostic dump
  client
- `server/diagnostics/ArmorMakesSense_MPDiagnosticsServer.lua`: diagnostic dump
  server
- `client/diagnostics/ArmorMakesSense_MPClientHarness.lua`: ping client
- `server/diagnostics/ArmorMakesSense_MPServerHarness.lua`: ping server
