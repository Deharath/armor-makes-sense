# Armor Makes Sense - Multiplayer Reference

## Authority Model

| Context | Responsibility |
|---|---|
| Singleplayer client | Gameplay calculations and UI state |
| Multiplayer server | Endurance, sleep fatigue, wake correction, melee strain, and snapshot production |
| Multiplayer client | On-demand UI snapshots and server-authoritative sleep reconciliation |

The MP client never advances the gameplay model. Shared model code under
`common/media/lua/shared/` is used by both the SP client and MP server, while
the server remains the only multiplayer authority for gameplay stats.

## Server Runtime

`server/ArmorMakesSense_MPServerRuntime.lua` registers these events:

| Event | Use |
|---|---|
| `OnClientCommand` | Queue snapshot requests or accept bounded sleep bed-type hints |
| `EveryOneMinute` | Advance awake players and refresh their server-side snapshot cache |
| `OnWeaponSwing` | Apply melee strain using the latest cached worn profile |
| `OnPlayerUpdate` | Gate one global sleep-player scan per wall-clock second |
| `OnGameBoot` | Runtime identity log |

Active non-sleep catch-up is capped at one game minute. Sleep catch-up remains
time-based. Shared input failures discard pending catch-up. A lightweight
cumulative AMS endurance-loss guard aborts an invocation at `0.12`; it does not
allocate or retain per-slice incident traces.

`shared/ArmorMakesSense_Simulation.lua` owns elapsed accumulation, catch-up
capping, bounded slicing, and sleep/endurance call order. The server coordinator
owns PZ input sampling, stat synchronization, cache updates, and transport.
Sleeping players are skipped by `EveryOneMinute` and advanced by the throttled
sleep scan, so the two schedulers do not duplicate sleep work.

The cached worn profile is refreshed during normal model sampling. Weapon swings
reuse a profile for up to one wall-clock second instead of traversing all worn
items on every attack, while bounding how long a recent equipment change can
affect strain calculation.

## Client Runtime

`client/ArmorMakesSense_MPClientRuntime.lua` has no module-load event side
effects. The multiplayer bootstrap explicitly registers only:

| Event | Use |
|---|---|
| `OnServerCommand` | Decode an addressed snapshot or compact sleep-state update |
| `OnConnected` | Clear local snapshot state and ensure UI hooks |
| `OnCreatePlayer` | Clear that local player's cache and ensure UI hooks |

The transport runtime does not subscribe to `OnClothingUpdated` or
`EveryOneMinute`. Clothing changes only dirty the client UI. The panel rebuilds
gear burden, breathing restriction, rigidity, and driver rows immediately from
the local worn-item collection; it does not send a clothing-triggered request.
The visible panel requests dynamic server telemetry only when its cache is
missing or older than 30 seconds. A hidden panel therefore generates no snapshot
traffic. Support-report export also asks for one when no cached server snapshot
exists and tells the player to retry after it arrives.

## Snapshot Protocol

Protocol constants live in `shared/ArmorMakesSense_MPCompat.lua`.
`shared/ArmorMakesSense_MPSnapshotCodec.lua` exclusively owns the full snapshot
wire mapping.

| Constant | Value |
|---|---|
| Network module | `ArmorMakesSenseRuntime` |
| Request command | `request_snapshot` |
| Response command | `snapshot` |
| Sleep command | `sleep_state` |
| Client and server request floor | 5 wall-clock seconds per player |
| Pending request timeout | 60 wall-clock seconds |
| UI cache freshness window | 30 wall-clock seconds |
| Snapshot schema | `5` |

### Client Requests

A request has no client-selected metadata. Player identity comes from PZ's
player-aware command dispatch.

Only one request may be pending on the client. Further UI collections reuse that
pending state for up to 60 seconds rather than resending. Both client and server
also enforce a five-second request floor per player.

A request is presentation-only: its handler never advances authoritative
physiology, changes endurance, creates a sleep session, or accepts a
client-selected lifecycle reason. It samples current worn gear and telemetry
against an isolated projection state, then returns that snapshot immediately.
This refreshes burden and breathing presentation without changing endurance
baselines, pending catch-up, sleep state, or thermal smoothing state.

### Server Responses

Full snapshots are player-addressed and sent only to satisfy queued demand.
There are no automatic connect, create-player, clothing, minute, or sleep full
snapshot pushes.

Each response carries aggregate load, numeric thermal and breathing telemetry,
endurance telemetry, activity, update minute, and optional physical cost-driver
rows. It does not carry sleep state, fatigue, client reasons, incident sequence,
or incident traces. Every response includes `snapshot_schema_version`; the
client rejects missing or unsupported schemas.

## Sleep and Wake Synchronization

Sleep authority uses a separate compact `sleep_state` command rather than a full
UI snapshot.

- `OnPlayerUpdate` may scan the online-player collection at most once per
  wall-clock second, regardless of player count or event frequency.
- Each sleeping player is advanced at most once per wall-clock second.
- Native fatigue synchronization and compact sleep-state sends occur at most
  once per five wall-clock seconds while sleeping.
- A detected wake completes the final elapsed interval as sleep, sends native
  fatigue once, and sends one `WakeTransition` sleep-state message.
- A server-declared wake runs vanilla `SleepingEvent:wakeUp(player, true)` on the
  client, preserving vanilla cleanup without echoing another wake packet.
- Bed-type hints are accepted only while the player is asleep, are limited to
  recognized vanilla prefixes and 64 characters, and are rate-limited to one
  every two wall-clock seconds per player.

When the sleep model is disabled, or CMS owns fatigue coordination, AMS sends no
sleep fatigue synchronization and performs no client fatigue/wake correction.
`ArmorMakesSense_SleepOwnership.lua` owns this handoff.

## Multiplayer Transient State

Client state in the weak-key `multiplayer_client` store includes:

- last request and snapshot wall-clock times;
- one pending-request flag;
- the latest decoded `mpServerSnapshot`.

Server state in the weak-key `multiplayer_server` store includes:

- update, catch-up, endurance, thermal, and sleep timing state;
- the latest runtime snapshot cache;
- one optional pending snapshot request;
- the cached worn profile and its wall-clock timestamp;
- sleep fatigue-sync, real-time update, wake-edge, and bed-hint state.

Neither store is saved. First access removes the obsolete
`ArmorMakesSenseState` player blob without importing it.

## Option Resolution

The MP server resolves `ArmorMakesSense.DEFAULTS` first and then matching
`SandboxVars.ArmorMakesSense` values. Public multiplayer gameplay toggles cover
thermal burden, muscle strain, and sleep penalties.

## Development Diagnostics

Development builds retain the explicit MP ping and diagnostic-dump harnesses.
Workshop packaging excludes files below client/server `diagnostics/` and
client `testing/`.

## Modules

- `client/ArmorMakesSense_MPClientRuntime.lua`: demand-driven client transport
  and compact sleep reconciliation
- `server/ArmorMakesSense_MPServerRuntime.lua`: gameplay authority, cache owner,
  and bounded schedulers
- `server/ArmorMakesSense_MPSnapshotBuilder.lua`: authoritative snapshot shaping
- `server/ArmorMakesSense_MPRequestPolicy.lua`: request throttling, queueing, and
  completion
- `shared/ArmorMakesSense_MPCompat.lua`: protocol constants
- `shared/ArmorMakesSense_SleepOwnership.lua`: AMS/CMS sleep authority policy
- `shared/ArmorMakesSense_MPSnapshotCodec.lua`: schema-versioned full snapshot
  codec
- `client/diagnostics/ArmorMakesSense_MPDiagnosticsClient.lua`: diagnostic dump
  client
- `server/diagnostics/ArmorMakesSense_MPDiagnosticsServer.lua`: diagnostic dump
  server
- `client/diagnostics/ArmorMakesSense_MPClientHarness.lua`: ping client
- `server/diagnostics/ArmorMakesSense_MPServerHarness.lua`: ping server
