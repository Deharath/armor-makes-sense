ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Core = ArmorMakesSense.Core or {}

local Core = ArmorMakesSense.Core
Core.State = Core.State or {}

local State = Core.State
local C = {}

-- -----------------------------------------------------------------------------
-- Options + per-player state management
-- -----------------------------------------------------------------------------

local function ctx(name)
    return C[name]
end

function State.setContext(context)
    C = context or {}
end

function State.getOptions()
    local options = {}
    local defaults = ctx("defaults") or {}
    for key, value in pairs(defaults) do
        options[key] = value
    end

    if SandboxVars and SandboxVars.ArmorMakesSense then
        for key, value in pairs(SandboxVars.ArmorMakesSense) do
            if options[key] ~= nil then
                if type(options[key]) == "boolean" then
                    options[key] = ctx("toBoolean")(value)
                elseif type(options[key]) == "number" then
                    local parsed = tonumber(value)
                    if parsed then
                        options[key] = parsed
                    end
                elseif type(options[key]) == "string" then
                    options[key] = tostring(value)
                end
            end
        end
    end

    if PZAPI and PZAPI.ModOptions and PZAPI.ModOptions.getOptions then
        local modOptions = PZAPI.ModOptions:getOptions(ctx("modOptionsId"))
        if modOptions then
            for key, defaultValue in pairs(options) do
                local option = ctx("safeMethod")(modOptions, "getOption", key)
                if option then
                    local value = ctx("safeMethod")(option, "getValue")
                    if value ~= nil then
                        if type(defaultValue) == "boolean" then
                            options[key] = ctx("toBoolean")(value)
                        elseif type(defaultValue) == "number" then
                            local parsed = tonumber(value)
                            if parsed then
                                options[key] = parsed
                            end
                        elseif type(defaultValue) == "string" then
                            options[key] = tostring(value)
                        end
                    end
                end
            end
        end
    end

    return options
end

function State.logOptionsSnapshot(options)
    return
end

function State.ensureState(player)
    local modData = ctx("safeMethod")(player, "getModData")
    if not modData then
        return {}
    end
    modData[ctx("modKey")] = modData[ctx("modKey")] or {}
    local state = modData[ctx("modKey")]

    state.version = 2
    state.lastUpdateGameMinutes = tonumber(state.lastUpdateGameMinutes) or ctx("getWorldAgeMinutes")()
    state.pendingCatchupMinutes = math.max(0, tonumber(state.pendingCatchupMinutes) or 0)
    local suppressMinute = tonumber(state.lastDiscomfortSuppressMinute)
    if suppressMinute ~= nil then
        state.lastDiscomfortSuppressMinute = math.floor(suppressMinute)
    else
        state.lastDiscomfortSuppressMinute = nil
    end
    state.lastEnduranceObserved = tonumber(state.lastEnduranceObserved)
    state.lastArmorLoad = tonumber(state.lastArmorLoad) or 0
    state.uiRuntimeSnapshot = type(state.uiRuntimeSnapshot) == "table" and state.uiRuntimeSnapshot or nil
    state.mpServerSnapshot = type(state.mpServerSnapshot) == "table" and state.mpServerSnapshot or nil
    state.mpClient = type(state.mpClient) == "table" and state.mpClient or nil
    state.sleepSnapshot = state.sleepSnapshot
    state.wasSleeping = ctx("toBoolean")(state.wasSleeping)
    state.recoveryTrace = state.recoveryTrace or {
        active = false,
        startMinute = 0,
        startEndurance = 0,
        peakEndurance = 0,
        lowEndurance = 1,
        startPhysicalLoad = 0,
        startArmorPieces = 0,
        postureStart = "stand",
        sitMinutes = 0,
        standMinutes = 0,
        sampleMinutes = 0,
    }
    state.testLock = state.testLock or {
        mode = nil,
        wetness = nil,
        untilMinute = 0,
    }
    state.autoRunner = state.autoRunner or {
        active = false,
        runId = 0,
        profile = "core",
        index = 0,
        phaseStartMinute = 0,
        phaseEndMinute = 0,
        phaseMinutes = 0,
        phaseInitIndex = 0,
        phases = nil,
        phaseStats = nil,
        runStats = nil,
        requestedSpeed = nil,
        originalSpeed = nil,
        startedMinute = 0,
        expectedEndMinute = 0,
    }
    -- Bench runner runtime lives outside modData; keep only a tiny active handle and purge legacy blobs.
    local bench = state.benchRunner
    if type(bench) == "table" then
        local hasLegacyRuntimeBlob = bench.steps ~= nil
            or bench.snapshot ~= nil
            or bench.stepResults ~= nil
            or bench.baselineOutfit ~= nil
            or bench.nativeDriver ~= nil
            or bench.weatherOverride ~= nil
        local active = bench.active == true
        local id = tostring(bench.id or "")
        if hasLegacyRuntimeBlob or not active or id == "" then
            state.benchRunner = nil
        else
            state.benchRunner = {
                active = true,
                id = id,
                preset = tostring(bench.preset or ""),
                label = tostring(bench.label or ""),
                mode = tostring(bench.mode or "lab"),
                speedReq = tonumber(bench.speedReq) or 0,
                startedAt = tonumber(bench.startedAt) or tonumber(state.lastUpdateGameMinutes) or 0,
                index = math.max(0, math.floor(tonumber(bench.index) or 0)),
                total = math.max(0, math.floor(tonumber(bench.total) or 0)),
                repeats = math.max(1, math.floor(tonumber(bench.repeats) or 1)),
                scriptVersion = tostring(bench.scriptVersion or "0.0.0"),
                scriptBuild = tostring(bench.scriptBuild or "na"),
            }
        end
    else
        state.benchRunner = nil
    end
    state.gearProfiles = state.gearProfiles or {}

    return state
end

return State
