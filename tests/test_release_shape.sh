#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_PATHS=(
  "${ROOT_DIR}/common/media/lua/client"
  "${ROOT_DIR}/common/media/lua/shared"
  "${ROOT_DIR}/common/media/lua/server"
)

forbidden='testing/ArmorMakesSense|ArmorMakesSense\.Testing|tickBenchRunner|testLock|autoRunner|benchRunner|gearProfiles|resetCharacterToEquilibrium|resetMuscleStrain'
if rg -n "${forbidden}" "${RUNTIME_PATHS[@]}" -g '*.lua' -g '!**/testing/**' -g '!**/diagnostics/**'; then
  echo "release runtime still contains development references" >&2
  exit 1
fi

if ! rg -q 'function DevBootstrap\.initialize' "${ROOT_DIR}/common/media/lua/client/testing/ArmorMakesSense_00_DevBootstrap.lua"; then
  echo "development bootstrap entrypoint missing" >&2
  exit 1
fi

mp_runtime="${ROOT_DIR}/common/media/lua/client/ArmorMakesSense_MPClientRuntime.lua"
if rg -n '^registerEvents\(\)' "${mp_runtime}"; then
  echo "MP client runtime still self-registers during module load" >&2
  exit 1
fi
if ! rg -q 'function MPClientRuntime\.registerEvents' "${mp_runtime}"; then
  echo "MP client runtime registration entrypoint missing" >&2
  exit 1
fi
if rg -n 'setAsleep|setAsleepTime|setForceWakeUpTime' "${mp_runtime}"; then
  echo "MP wake reconciliation still bypasses vanilla SleepingEvent cleanup" >&2
  exit 1
fi
if ! rg -q 'sleepingEvent:wakeUp\(playerObj, true\)' "${mp_runtime}"; then
  echo "MP wake reconciliation does not use vanilla's authoritative wake path" >&2
  exit 1
fi

legacy_state_key='ArmorMakesSenseState'
if rg -n "${legacy_state_key}" \
  "${ROOT_DIR}/common/media/lua/client" \
  "${ROOT_DIR}/common/media/lua/shared" \
  "${ROOT_DIR}/common/media/lua/server" \
  -g '*.lua' \
  -g '!**/testing/**' \
  -g '!**/diagnostics/**' \
  -g '!ArmorMakesSense_RuntimeState.lua'; then
  echo "release runtime still accesses the legacy persisted state key" >&2
  exit 1
fi

simulation_module='ArmorMakesSense_Simulation'
if ! rg -q "require \"${simulation_module}\"" "${ROOT_DIR}/common/media/lua/client/core/ArmorMakesSense_Tick.lua"; then
  echo "singleplayer coordinator does not use the shared simulation advance path" >&2
  exit 1
fi
if ! rg -q "require \"${simulation_module}\"" "${ROOT_DIR}/common/media/lua/server/ArmorMakesSense_MPServerRuntime.lua"; then
  echo "MP server coordinator does not use the shared simulation advance path" >&2
  exit 1
fi
if rg -n 'ACTIVE_ENDURANCE_CATCHUP_(MAX|RESET_THRESHOLD)_MINUTES' \
  "${ROOT_DIR}/common/media/lua/client" \
  "${ROOT_DIR}/common/media/lua/server" \
  -g '*.lua'; then
  echo "runtime coordinator duplicates shared catch-up constants" >&2
  exit 1
fi

if rg -n 'SLEEP_WAKE_DIAG_COMMAND|sleep_wake_diag' \
  "${ROOT_DIR}/common/media/lua/shared/ArmorMakesSense_MPCompat.lua" \
  "${ROOT_DIR}/common/media/lua/server/ArmorMakesSense_MPServerRuntime.lua"; then
  echo "released MP runtime still accepts diagnostic wake-fatigue authority" >&2
  exit 1
fi
if ! rg -q 'Strain\.applyArmorStrainOverlay' "${ROOT_DIR}/common/media/lua/server/ArmorMakesSense_MPServerRuntime.lua"; then
  echo "MP server does not use the shared strain application policy" >&2
  exit 1
fi
if rg -n 'Strain\.(isMeleeStrainEligible|computeArmorStrainExtra)' \
  "${ROOT_DIR}/common/media/lua/server/ArmorMakesSense_MPServerRuntime.lua"; then
  echo "MP server duplicates shared strain calculation steps" >&2
  exit 1
fi
if rg -n 'recentCombatUntilMinute|combatActivityPending|COMBAT_LATCH_ATTACK_SECONDS|getActivity(Label|Factor)|noteCombatActivity' \
  "${ROOT_DIR}/common/media/lua/client" \
  "${ROOT_DIR}/common/media/lua/server" \
  "${ROOT_DIR}/common/media/lua/shared" \
  -g '*.lua' \
  -g '!**/testing/**' \
  -g '!**/diagnostics/**'; then
  echo "released runtime still uses split or timer-based activity state" >&2
    exit 1
fi
if rg -n 'EnvironmentShared|resolveActivity|combatActivityPending' \
  "${ROOT_DIR}/common/media/lua/client/core/ArmorMakesSense_Combat.lua"; then
  echo "SP combat event still mutates sampled activity state" >&2
  exit 1
fi
if rg -n 'recoveryTrace|updateRecoveryTrace' \
  "${ROOT_DIR}/common/media/lua/client" \
  "${ROOT_DIR}/common/media/lua/server" \
  "${ROOT_DIR}/common/media/lua/shared" \
  -g '*.lua' \
  -g '!**/testing/**' \
  -g '!**/diagnostics/**'; then
  echo "released runtime still contains the write-only recovery trace" >&2
  exit 1
fi
if rg -n 'pendingSleepSession|SLEEP_SESSION_COMMAND|sleep_for|wake_hour|clientWorldMinute|clientFatigue' \
  "${ROOT_DIR}/common/media/lua/client" \
  "${ROOT_DIR}/common/media/lua/server" \
  "${ROOT_DIR}/common/media/lua/shared" \
  -g '*.lua' \
  -g '!**/testing/**' \
  -g '!**/diagnostics/**'; then
  echo "released runtime still carries unused sleep-session metadata" >&2
    exit 1
fi

if ! rg -q 'safeCall\(playerObj, "setBedType", bedType\)' \
  "${ROOT_DIR}/common/media/lua/server/ArmorMakesSense_MPServerRuntime.lua"; then
  echo "MP sleep bed hint is not applied to vanilla server recovery" >&2
  exit 1
fi
if rg -n 'getClientActivityLabel|world_minute|activity_label|script_version|script_build' \
  "${ROOT_DIR}/common/media/lua/client/ArmorMakesSense_MPClientRuntime.lua"; then
  echo "MP snapshot requests still carry server-ignored client metadata" >&2
  exit 1
fi
if rg -n 'lastSnapshotSentSecond|thermalHot|thermalCold|thermal_hot|thermal_cold' \
  "${ROOT_DIR}/common/media/lua/server/ArmorMakesSense_MPServerRuntime.lua" \
  "${ROOT_DIR}/common/media/lua/shared/ArmorMakesSense_MPSnapshotCodec.lua"; then
  echo "MP runtime still carries unused snapshot state or derived thermal booleans" >&2
  exit 1
fi
if rg -n 'lastAsleepFlag|Deliberate duplicate of ArmorMakesSense_Utils|local function safe(Method|Call)' \
  "${ROOT_DIR}/common/media/lua/server/ArmorMakesSense_MPServerRuntime.lua" \
  "${ROOT_DIR}/common/media/lua/client/ArmorMakesSense_SleepHooks.lua" \
  "${ROOT_DIR}/common/media/lua/shared/ArmorMakesSense_ArmorClassifier.lua" \
  "${ROOT_DIR}/common/media/lua/shared/ArmorMakesSense_BreathingClassifier.lua" \
  "${ROOT_DIR}/common/media/lua/shared/ArmorMakesSense_SpeedRebalance.lua"; then
  echo "runtime still carries legacy wake migration or duplicate protected-call utilities" >&2
  exit 1
fi
if ! rg -q 'Environment\.resolveActivity' \
  "${ROOT_DIR}/common/media/lua/client/core/ArmorMakesSense_Tick.lua" \
  || ! rg -q 'Environment\.resolveActivity' \
  "${ROOT_DIR}/common/media/lua/server/ArmorMakesSense_MPServerRuntime.lua"; then
  echo "SP and MP coordinators do not both consume shared activity results" >&2
  exit 1
fi
if rg -n 'breathingLoad|breathing_load|BreathingSealLoad(Start|Span)' \
  "${ROOT_DIR}/common/media/lua/client" \
  "${ROOT_DIR}/common/media/lua/server" \
  "${ROOT_DIR}/common/media/lua/shared" \
  -g '*.lua' \
  -g '!**/testing/**' \
  -g '!**/diagnostics/**'; then
  echo "released runtime still infers respiratory category from aggregate breathing load" >&2
    exit 1
fi
if rg -n 'massLoad|wearabilityLoad|armorCount|upperBodyLoad|combinedLoad|itemToArmorSignal|computeArmorProfile' \
  "${ROOT_DIR}/common/media/lua" \
  -g '*.lua'; then
  echo "historical worn-profile aliases or misleading API names remain" >&2
  exit 1
fi
if rg -n 'processedMinutes|\.slices\b' \
  "${ROOT_DIR}/common/media/lua/shared/ArmorMakesSense_Simulation.lua"; then
  echo "simulation still conflates attempted and committed work" >&2
  exit 1
fi
if rg -n 'ZombRand|HaloTextHelper|ISTimedActionQueue|IsoPlayer\.allPlayersAsleep|save\(true\)' \
  "${ROOT_DIR}/common/media/lua/client/ArmorMakesSense_SleepHooks.lua"; then
  echo "AMS sleep hook still owns copied vanilla workflow" >&2
  exit 1
fi
if rg -n 'sleep_planner_coordinator|fatigue_coordinator|sleep_wake_adjustment_coordinator' \
  "${ROOT_DIR}/common/media/lua/client/ArmorMakesSense_SleepHooks.lua" \
  "${ROOT_DIR}/common/media/lua/client/ArmorMakesSense_MPClientRuntime.lua" \
  "${ROOT_DIR}/common/media/lua/server/ArmorMakesSense_MPServerRuntime.lua" \
  "${ROOT_DIR}/common/media/lua/shared/ArmorMakesSense_PhysiologyShared.lua"; then
  echo "sleep gameplay modules bypass shared ownership policy" >&2
  exit 1
fi
for model in BreathingModel EnduranceModel SleepModel; do
  if ! rg -q "require \"ArmorMakesSense_${model}\"" \
    "${ROOT_DIR}/common/media/lua/shared/ArmorMakesSense_PhysiologyShared.lua"; then
    echo "physiology does not compose required calculation model: ${model}" >&2
    exit 1
  fi
done

shared_models=(
  "${ROOT_DIR}/common/media/lua/shared/ArmorMakesSense_LoadModelShared.lua"
  "${ROOT_DIR}/common/media/lua/shared/ArmorMakesSense_EnvironmentShared.lua"
  "${ROOT_DIR}/common/media/lua/shared/ArmorMakesSense_StrainShared.lua"
  "${ROOT_DIR}/common/media/lua/shared/ArmorMakesSense_PhysiologyShared.lua"
)
if rg -n 'setContext|ctx\(' "${shared_models[@]}"; then
  echo "shared gameplay models still use mutable runtime context" >&2
  exit 1
fi
for shared_model in "${shared_models[@]}"; do
  if ! rg -q 'require "ArmorMakesSense_UtilsShared"' "${shared_model}"; then
    echo "shared gameplay model does not require shared utilities: ${shared_model}" >&2
    exit 1
  fi
done
if [[ -e "${ROOT_DIR}/common/media/lua/client/core/ArmorMakesSense_Utils.lua" \
   || -e "${ROOT_DIR}/common/media/lua/client/core/ArmorMakesSense_Stats.lua" ]]; then
  echo "client-only utility or stat adapters remain after shared cutover" >&2
  exit 1
fi

legacy_context_modules=(
  "${ROOT_DIR}/common/media/lua/client/core/ArmorMakesSense_ContextFactory.lua"
  "${ROOT_DIR}/common/media/lua/client/core/ArmorMakesSense_ContextBinder.lua"
  "${ROOT_DIR}/common/media/lua/client/core/ArmorMakesSense_ContextRefs.lua"
)
for legacy_module in "${legacy_context_modules[@]}"; do
  if [[ -e "${legacy_module}" ]]; then
    echo "legacy client context module remains: ${legacy_module}" >&2
    exit 1
  fi
done
if rg -n 'setContext|ctx\(|moduleCall' \
  "${ROOT_DIR}/common/media/lua/client" \
  -g '*.lua' \
  -g '!**/testing/**' \
  -g '!**/diagnostics/**'; then
  echo "release client runtime still uses mutable context dispatch" >&2
  exit 1
fi

obsolete_client_lifecycle='logOptionsSnapshot|setSystemEnabled|isSystemEnabled|function Combat\.onWeaponSwing'
if rg -n "${obsolete_client_lifecycle}" "${ROOT_DIR}/common/media/lua/client" -g '*.lua' -g '!**/testing/**'; then
  echo "obsolete client lifecycle scaffolding returned" >&2
  exit 1
fi

if rg -n 'SandboxVars.*ArmorMakesSense' \
  "${ROOT_DIR}/common/media/lua/client" \
  "${ROOT_DIR}/common/media/lua/shared" \
  "${ROOT_DIR}/common/media/lua/server" \
  -g '*.lua' \
  -g '!ArmorMakesSense_Options.lua' \
  -g '!**/testing/**'; then
  echo "runtime parses AMS sandbox options outside the shared resolver" >&2
  exit 1
fi
if rg -n 'local function getWallClockSeconds' \
  "${ROOT_DIR}/common/media/lua/client" \
  "${ROOT_DIR}/common/media/lua/server" \
  -g '*.lua'; then
  echo "runtime duplicates the shared wall-clock resolver" >&2
  exit 1
fi

ui_module="${ROOT_DIR}/common/media/lua/client/core/ArmorMakesSense_UI.lua"
tooltip_module="${ROOT_DIR}/common/media/lua/client/core/ArmorMakesSense_UITooltip.lua"
if ! rg -q 'require "core/ArmorMakesSense_UITooltip"' "${ui_module}"; then
  echo "Burden UI does not install the dedicated tooltip integration" >&2
  exit 1
fi
if rg -n 'ISToolTipInv|DoTooltipEmbedded|AMSTooltipPatched|installTooltipHook' "${ui_module}"; then
  echo "tooltip patching leaked back into the Burden UI module" >&2
  exit 1
fi
if ! rg -q 'function UITooltip\.install' "${tooltip_module}"; then
  echo "tooltip integration entrypoint missing" >&2
  exit 1
fi
if rg -n 'function Stats\.set(Thirst|Discomfort|Wetness|BodyTemperature)' \
  "${ROOT_DIR}/common/media/lua/shared/ArmorMakesSense_StatsShared.lua"; then
  echo "development-only body-state setters leaked into production StatsShared" >&2
  exit 1
fi
if [[ ! -f "${ROOT_DIR}/common/media/lua/client/testing/ArmorMakesSense_TestStats.lua" ]]; then
  echo "development body-state setter module missing" >&2
  exit 1
fi

PACKAGING_PATHS=(
  "${ROOT_DIR}/../tools/mod_sync/sync_local_mod.sh"
  "${ROOT_DIR}/../tools/armor_makes_sense/scripts/workshop_publish_common.ps1"
)
rewrite_pattern='WriteAllLines\(\$mainLua|sed -i .+testing|stripped testing requires from Main'
if rg -n "${rewrite_pattern}" "${PACKAGING_PATHS[@]}"; then
  echo "release tooling still rewrites Main.lua" >&2
  exit 1
fi

echo "ams release source-shape checks passed"
