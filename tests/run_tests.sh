#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export AMS_ROOT="${ROOT_DIR}"

tests=(
  test_item_models.lua
  test_environment_strain.lua
  test_thermal_model.lua
  test_physiology.lua
  test_sleep_ownership.lua
  test_calculation_models.lua
  test_mp_snapshot_codec.lua
  test_mp_sleep_wake.lua
  test_runtime_state.lua
  test_options.lua
  test_stats_authority.lua
  test_local_player_ownership.lua
  test_simulation.lua
  test_ui_tooltip.lua
  test_sleep_hooks.lua
  test_slot_compat.lua
  test_speed_rebalance_lifecycle.lua
  test_tick_coordinator.lua
  test_client_bootstrap.lua
  test_dev_panel.lua
  test_dev_bootstrap.lua
  test_gear.lua
  test_bench_catalog.lua
  test_bench_runner_env.lua
  test_bench_runner_snapshot.lua
  test_bench_runner_step.lua
)

for test_name in "${tests[@]}"; do
  lua "${ROOT_DIR}/tests/${test_name}"
done

"${ROOT_DIR}/tests/test_release_shape.sh"

echo "all AMS characterization tests passed"
