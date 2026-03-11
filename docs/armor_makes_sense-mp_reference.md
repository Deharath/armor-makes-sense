# Armor Makes Sense — Multiplayer Reference (v1.2.2)

_As of March 11, 2026_  
`SCRIPT_VERSION=1.2.2`  
`SCRIPT_BUILD=ams-b42-2026-03-11-v122`

## Boot Structure

`ArmorMakesSense_Main.lua` is the client entry facade. On client load it:
- requires shared modules (`Config`, `MPCompat`, classifier/load/physiology shared helpers)
- requires client core/model/testing modules
- builds and injects the shared context for client-side systems
- registers the SP client runtime

Server runtime:
- `server/ArmorMakesSense_MPServerRuntime.lua` loads when `isServer() == true`
- it requires `MPCompat`, `LoadModelShared`, `EnvironmentShared`, `StrainShared`, and `PhysiologyShared`
- it binds a reduced shared context directly inside the server module instead of using the client context factory/binder stack

## Runtime Modes

Singleplayer:
- `Runtime.registerEvents` owns local gameplay loops
- formulas apply to `getPlayer()`

Multiplayer server:
- `MPServerRuntime` owns gameplay authority
- `EveryOneMinute` advances player state and catch-up slices
- `OnClientCommand` handles snapshot requests
- client session-start requests (`OnConnected`, `OnCreatePlayer`) reset stale per-player catch-up so offline world time is not replayed on reconnect
- `OnWeaponSwing` applies armor-based strain overlay
- `OnPlayerUpdate` enforces discomfort invariant between snapshot sends

Multiplayer client:
- `MPClientRuntime` registers `OnServerCommand`, `OnConnected`, `OnCreatePlayer`, `OnClothingUpdated`, `EveryOneMinute`, and `OnPlayerUpdate`
- it ensures UI hooks exist, requests fresh snapshots, expires stale cache entries, and marks the Burden UI dirty when new data arrives
- UI data comes from the cached server snapshot

## Snapshot Protocol

Constants in `ArmorMakesSense_MPCompat.lua`:
- network module: `ArmorMakesSenseRuntime`
- request command: `request_snapshot`
- response command: `snapshot`
- request cadence constant: `SNAPSHOT_FALLBACK_SECONDS = 2`
- state key: `ArmorMakesSenseState`

Client flow:
- load/connect/player-create/clothing changes request a snapshot immediately
- repeated requests are throttled to the cadence defined by `SNAPSHOT_FALLBACK_SECONDS`
- cache expiry is `max(10, fallback * 4)` seconds

Server flow:
- `MPServerRuntime` recomputes or reuses the latest runtime snapshot for the requesting player
- fresh request snapshots run the shared physiology path at `dt=0` so UI/runtime fields refresh without applying gameplay drain
- if shared input preparation fails, pending catch-up is discarded instead of being allowed to accumulate into a large replay backlog
- the snapshot payload includes:
  - `loadNorm`
  - `physicalLoad`
  - `thermalLoad`
  - `breathingLoad`
  - `rigidityLoad`
  - `armorCount`
  - `effectiveLoad`
  - `thermalPressureScale`
  - `enduranceEnvFactor`
  - `updatedMinute`
  - thermal hot/cold flags
  - physical cost drivers

Client storage:
- parsed snapshots are stored in `player:getModData()[STATE_KEY].mpServerSnapshot`

UI behavior:
- burden, thermal, breathing, and sleep panel data read from the latest server snapshot
- missing or expired snapshots return the panel to its waiting state

## Multiplayer Option Resolution

Server/MP (`MPServerRuntime.getOptions()`) precedence:
1. `ArmorMakesSense.DEFAULTS`
2. `SandboxVars.ArmorMakesSense`

Client/SP uses the same sandbox-backed gameplay toggles.

## Multiplayer State

Client-side MP state:
- `mpClient.lastRequestWallSecond`
- `mpClient.lastSnapshotWallSecond`
- `mpServerSnapshot`

Server-side MP state:
- `mpServer.lastUpdateGameMinutes`
- `mpServer.lastEnduranceObserved`
- `mpServer.pendingCatchupMinutes`
- `mpServer.runtimeSnapshot`
- `mpServer.lastSnapshotSentSecond`
- `mpServer.recentCombatUntilMinute`
- `mpServer.thermalModelState`

## Diagnostics Stack

The diagnostics modules expose runtime state and per-item attribution for MP inspection.

### Harness Layer

`client/diagnostics/ArmorMakesSense_MPClientHarness.lua`:
- registers on load, connect, player-create, and minute events
- sends one-shot `harness_ping` requests
- exposes `ams_mp_ping(reason)`

`server/diagnostics/ArmorMakesSense_MPServerHarness.lua`:
- listens for `harness_ping` on `OnClientCommand`
- replies with `diag` pong payloads containing server minute, script version, and build
- logs player identity and request reason

### Diagnostic Dump Path

`client/diagnostics/ArmorMakesSense_MPDiagnosticsClient.lua`:
- exposes `ams_mp_diag_dump(reason)`
- exposes `ams_mp_diag_last()`
- stores the last dump locally and logs a compact summary on receipt

`server/diagnostics/ArmorMakesSense_MPDiagnosticsServer.lua`:
- listens for `diag_dump_request`
- builds payloads from `mpServer.runtimeSnapshot`, `mpServer.uiRuntimeSnapshot`, live stats, and per-item load signals
- returns payloads over `diag_dump`

Server dump payload contents:
- player identity and online id
- script version/build and world minute
- live endurance, fatigue, and thirst
- aggregate AMS loads
- runtime modifiers
- activity label
- thermal flags
- pending catch-up time
- physical cost drivers
- per-item rows derived from `LoadModel.itemToArmorSignal`

Optional minute summaries:
- `MPDiagnosticsServer` can emit one-line summaries for all online players
- gate: `_G.ams_enable_mp_diag_minute_summary == true`
- output form: log lines

## Context Injection

AMS uses context injection for most gameplay/model code.

Client/SP context path:
- `ArmorMakesSense_ContextFactory.lua` builds the full context table
- `ArmorMakesSense_ContextBinder.lua` injects it into modules that expose `setContext`
- `ArmorMakesSense_ContextRefs.lua` holds stable references
- `ArmorMakesSense_Bootstrap.lua` provides thin binding/runtime registration helpers

MP server context path:
- `MPServerRuntime` constructs a smaller ad-hoc context with clamp/softNorm helpers, stat IO, environment readers, load-model entry points, and MP-specific `ensureState`
- it injects that context into `LoadModelShared`, `EnvironmentShared`, `StrainShared`, and `PhysiologyShared`

## MP-Facing Module Map

- `client/ArmorMakesSense_MPClientRuntime.lua` — snapshot transport and UI bridge
- `server/ArmorMakesSense_MPServerRuntime.lua` — gameplay authority and snapshot sender
- `shared/ArmorMakesSense_MPCompat.lua` — MP constants
- `shared/ArmorMakesSense_LoadModelShared.lua` — shared load-model math
- `shared/ArmorMakesSense_EnvironmentShared.lua` — shared environment sampling
- `shared/ArmorMakesSense_PhysiologyShared.lua` — shared physiology formulas
- `shared/ArmorMakesSense_StrainShared.lua` — shared strain logic
- `client/diagnostics/ArmorMakesSense_MPDiagnosticsClient.lua` — client diagnostics receive/logging
- `client/diagnostics/ArmorMakesSense_MPClientHarness.lua` — client harness ping path
- `server/diagnostics/ArmorMakesSense_MPDiagnosticsServer.lua` — server diagnostics dump/minute summaries
- `server/diagnostics/ArmorMakesSense_MPServerHarness.lua` — server harness pong path
