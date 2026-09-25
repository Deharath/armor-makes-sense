#!/usr/bin/env bash
set -euo pipefail

# Structural guards for the 2.0 runtime shape. Behavior lives in the Lua tests.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUA="${ROOT_DIR}/common/media/lua"
RUNTIME_PATHS=("${LUA}/client" "${LUA}/shared" "${LUA}/server")
RELEASE_GLOBS=(-g '*.lua' -g '!**/testing/**' -g '!**/diagnostics/**')
TICK="${LUA}/client/core/ArmorMakesSense_Tick.lua"
MP_SERVER="${LUA}/server/ArmorMakesSense_MPServerRuntime.lua"
MP_CLIENT="${LUA}/client/ArmorMakesSense_MPClientRuntime.lua"
UI="${LUA}/client/core/ArmorMakesSense_UI.lua"

fail() {
  echo "$1" >&2
  exit 1
}

if rg -n 'testing/ArmorMakesSense|ArmorMakesSense\.Testing|tickBenchRunner|testLock|autoRunner|benchRunner|gearProfiles|resetCharacterToEquilibrium|resetMuscleStrain' \
  "${RUNTIME_PATHS[@]}" "${RELEASE_GLOBS[@]}"; then
  fail "release runtime still contains development references"
fi
rg -q 'function DevBootstrap\.initialize' "${LUA}/client/testing/ArmorMakesSense_00_DevBootstrap.lua" \
  || fail "development bootstrap entrypoint missing"

# 2.0 amputations stay amputated.
for removed in \
  "${LUA}/client/ArmorMakesSense_SleepHooks.lua" \
  "${LUA}/shared/ArmorMakesSense_SleepOwnership.lua" \
  "${LUA}/shared/ArmorMakesSense_SleepPhysiology.lua" \
  "${LUA}/shared/ArmorMakesSense_Simulation.lua" \
  "${LUA}/server/ArmorMakesSense_MPSnapshotBuilder.lua" \
  "${LUA}/client/core/ArmorMakesSense_Utils.lua" \
  "${LUA}/client/core/ArmorMakesSense_Stats.lua" \
  "${LUA}/client/core/ArmorMakesSense_ContextFactory.lua" \
  "${LUA}/client/core/ArmorMakesSense_ContextBinder.lua" \
  "${LUA}/client/core/ArmorMakesSense_ContextRefs.lua"; do
  [[ -e "${removed}" ]] && fail "removed module returned: ${removed}"
done
if rg -n 'setAsleep|setAsleepTime|setForceWakeUpTime|setPlayerFallAsleep|wakeUp\(' "${RUNTIME_PATHS[@]}" "${RELEASE_GLOBS[@]}"; then
  fail "release runtime drives vanilla sleep state; sleep planning belongs to vanilla"
fi
if rg -n 'physicalLoad|loadNorm|effectiveLoad|thermalContribution|breathingContribution|swingChainLoad|rigidityLoad|ThermalContributionMax|ActivityIdle|DtMaxMinutes|DtCatchupMaxSlices' \
  "${LUA}" -g '*.lua' -g '*.txt' -g '*.json'; then
  fail "1.x load-point vocabulary remains"
fi
if rg -n 'ArmorMakesSenseState' "${RUNTIME_PATHS[@]}" "${RELEASE_GLOBS[@]}" -g '!ArmorMakesSense_RuntimeState.lua'; then
  fail "release runtime still accesses the legacy persisted state key"
fi

# One physiology tick shared by SP and the MP server.
rg -q 'Physiology\.tick\(' "${TICK}" || fail "SP coordinator does not use Physiology.tick"
rg -q 'Physiology\.tick\(' "${MP_SERVER}" || fail "MP server does not use Physiology.tick"
rg -q 'Physiology\.project\(' "${MP_SERVER}" || fail "MP snapshot requests do not use the read-only projector"
client_command_body="$(sed -n '/local function onClientCommand/,/^end/p' "${MP_SERVER}")"
if rg -q 'Physiology\.tick|tickPlayer' <<<"${client_command_body}"; then
  fail "MP snapshot requests still advance gameplay"
fi
rg -q 'Strain\.applyArmorStrainOverlay' "${MP_SERVER}" || fail "MP server does not use the shared strain overlay"
rg -q 'require "ArmorMakesSense_MPRequestPolicy"' "${MP_SERVER}" || fail "MP server does not use the request policy"
rg -q 'RequestPolicy\.queueSnapshotRequest' "${MP_SERVER}" || fail "MP server does not queue bounded snapshot requests"
rg -q 'Codec\.SCHEMA_VERSION = 7' "${LUA}/shared/ArmorMakesSense_MPSnapshotCodec.lua" \
  || fail "MP snapshot schema is not the 2.0 schema"
if rg -n '^registerEvents\(\)' "${MP_CLIENT}"; then
  fail "MP client runtime self-registers during module load"
fi
rg -q 'function MPClientRuntime\.registerEvents' "${MP_CLIENT}" || fail "MP client registration entrypoint missing"
if rg -n '"OnClothingUpdated"|"EveryOneMinute"' "${MP_CLIENT}"; then
  fail "MP client subscribes snapshot transport to broad events"
fi
if rg -n 'SLEEP_WAKE_DIAG_COMMAND|sleep_wake_diag' "${LUA}/shared/ArmorMakesSense_MPCompat.lua" "${MP_SERVER}"; then
  fail "released MP runtime accepts diagnostic wake-fatigue authority"
fi

for model in BreathingModel EnduranceModel SleepModel ThermalModel LoadModelShared; do
  rg -q "require \"ArmorMakesSense_${model}\"" "${LUA}/shared/ArmorMakesSense_PhysiologyShared.lua" \
    || fail "physiology does not compose ${model}"
done
shared_models=(
  "${LUA}/shared/ArmorMakesSense_LoadModelShared.lua"
  "${LUA}/shared/ArmorMakesSense_EnvironmentShared.lua"
  "${LUA}/shared/ArmorMakesSense_StrainShared.lua"
  "${LUA}/shared/ArmorMakesSense_PhysiologyShared.lua"
)
if rg -n 'setContext|ctx\(' "${shared_models[@]}"; then
  fail "shared gameplay models use mutable runtime context"
fi
if rg -n 'setContext|ctx\(|moduleCall' "${LUA}/client" "${RELEASE_GLOBS[@]}"; then
  fail "release client runtime uses mutable context dispatch"
fi
if rg -n 'SandboxVars.*ArmorMakesSense' "${RUNTIME_PATHS[@]}" -g '*.lua' -g '!ArmorMakesSense_Options.lua' -g '!**/testing/**'; then
  fail "runtime parses AMS sandbox options outside the shared resolver"
fi
if rg -n 'local function getWallClockSeconds' "${LUA}/client" "${LUA}/server" -g '*.lua'; then
  fail "runtime duplicates the shared wall-clock resolver"
fi

# Presentation: pips through the shared policy, no numeric diagnostics on the player UI.
BURDEN_VIEW="${LUA}/client/core/ArmorMakesSense_BurdenView.lua"
BURDEN_PANEL="${LUA}/client/core/ArmorMakesSense_BurdenPanel.lua"
for presenter in "${BURDEN_VIEW}" "${BURDEN_PANEL}" "${LUA}/client/core/ArmorMakesSense_UITooltip.lua"; do
  rg -q 'require "ArmorMakesSense_PresentationPolicy"' "${presenter}" \
    || fail "presentation surface bypasses the shared policy: ${presenter}"
done
rg -q 'require "core/ArmorMakesSense_Draw"' "${BURDEN_PANEL}" || fail "Burden tab does not use the shared pip drawing"
rg -q 'exportFn\(self:resolvePlayer\(\)\)' "${BURDEN_PANEL}" || fail "support export loses split-screen player identity"
rg -q 'Physiology\.projectWithServerThermal' "${BURDEN_PANEL}" || fail "MP Burden tab does not use the local worn profile"
rg -q 'BurdenPanel\.new' "${UI}" || fail "character-info tab does not host the Burden panel"

diagnostic_clients=(
  "${LUA}/client/diagnostics/ArmorMakesSense_MPDiagnosticsClient.lua"
  "${LUA}/client/diagnostics/ArmorMakesSense_MPClientHarness.lua"
)
if rg -n -U 'pcall\(\s*sendClientCommand,\s*tostring' "${diagnostic_clients[@]}"; then
  fail "development diagnostics use the obsolete client-command overload"
fi

echo "ams release shape checks passed"
