ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.RuntimeState = ArmorMakesSense.RuntimeState or {}

local RuntimeState = ArmorMakesSense.RuntimeState

RuntimeState.ROLE_SINGLEPLAYER = "singleplayer"
RuntimeState.ROLE_MP_CLIENT = "multiplayer_client"
RuntimeState.ROLE_MP_SERVER = "multiplayer_server"
RuntimeState.LEGACY_KEY = "ArmorMakesSenseState"

local function newWeakKeyStore()
    return setmetatable({}, { __mode = "k" })
end

RuntimeState._stores = RuntimeState._stores or {
    [RuntimeState.ROLE_SINGLEPLAYER] = newWeakKeyStore(),
    [RuntimeState.ROLE_MP_CLIENT] = newWeakKeyStore(),
    [RuntimeState.ROLE_MP_SERVER] = newWeakKeyStore(),
}
RuntimeState._legacyPurged = RuntimeState._legacyPurged or newWeakKeyStore()

local function getModData(player)
    if not player then
        return nil
    end
    local okResolve, method = pcall(function()
        return player.getModData
    end)
    if not okResolve or type(method) ~= "function" then
        return nil
    end
    local okCall, modData = pcall(method, player)
    if not okCall or type(modData) ~= "table" then
        return nil
    end
    return modData
end

function RuntimeState.purgeLegacy(player)
    if not player or RuntimeState._legacyPurged[player] then
        return false
    end

    local modData = getModData(player)
    if not modData then
        return false
    end
    RuntimeState._legacyPurged[player] = true
    local hadLegacyState = modData[RuntimeState.LEGACY_KEY] ~= nil
    modData[RuntimeState.LEGACY_KEY] = nil
    return hadLegacyState
end

local function getRoleStore(role)
    return RuntimeState._stores[role]
end

function RuntimeState.get(player, role)
    if not player then
        return nil
    end
    local store = getRoleStore(role)
    if not store then
        return nil
    end
    RuntimeState.purgeLegacy(player)
    local state = store[player]
    if type(state) ~= "table" then
        state = {}
        store[player] = state
    end
    return state
end

function RuntimeState.peek(player, role)
    if not player then
        return nil
    end
    local store = getRoleStore(role)
    if not store then
        return nil
    end
    RuntimeState.purgeLegacy(player)
    return store[player]
end

function RuntimeState.clear(player, role)
    local store = getRoleStore(role)
    if not store or not player then
        return false
    end
    local existed = store[player] ~= nil
    store[player] = nil
    return existed
end

return RuntimeState
