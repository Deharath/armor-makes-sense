ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Core = ArmorMakesSense.Core or {}

local Core = ArmorMakesSense.Core
Core.State = Core.State or {}

local State = Core.State
local Utils = require "ArmorMakesSense_UtilsShared"
local RuntimeState = require "ArmorMakesSense_RuntimeState"

-- -----------------------------------------------------------------------------
-- Options + per-player state management
-- -----------------------------------------------------------------------------

function State.ensureState(player)
    local state = RuntimeState.get(player, RuntimeState.ROLE_SINGLEPLAYER)
    if not state then
        return {}
    end

    state.lastUpdateGameMinutes = tonumber(state.lastUpdateGameMinutes) or Utils.getWorldAgeMinutes()
    state.pendingCatchupMinutes = math.max(0, tonumber(state.pendingCatchupMinutes) or 0)
    state.lastEnduranceObserved = tonumber(state.lastEnduranceObserved)
    state.uiRuntimeSnapshot = type(state.uiRuntimeSnapshot) == "table" and state.uiRuntimeSnapshot or nil
    state.wasSleeping = Utils.toBoolean(state.wasSleeping)
    return state
end

return State
