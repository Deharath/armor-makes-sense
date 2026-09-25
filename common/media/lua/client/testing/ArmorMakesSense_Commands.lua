ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Testing = ArmorMakesSense.Testing or {}

local Testing = ArmorMakesSense.Testing
Testing.Commands = Testing.Commands or {}

local Commands = Testing.Commands
local C = {}

local function ctx(name)
    return C[name]
end

local function getBenchRunner()
    local testing = ArmorMakesSense and ArmorMakesSense.Testing
    return testing and testing.BenchRunner or nil
end

-- -----------------------------------------------------------------------------
-- Context wiring
-- -----------------------------------------------------------------------------

function Commands.setContext(context)
    C = context or {}
    local BenchRunner = getBenchRunner()
    if BenchRunner and type(BenchRunner.setContext) == "function" then
        BenchRunner.setContext(C)
    end
end

function Commands.gearSave(name)
    local player = ctx("getLocalPlayer")()
    if not player then
        ctx("logError")("gear save failed: no local player")
        return false
    end
    local profileName = tostring(name or "default")
    if profileName == "" then
        profileName = "default"
    end
    local state = ctx("ensureState")(player)
    local entries = ctx("snapshotWornItems")(player)
    state.gearProfiles[profileName] = entries
    ctx("log")(string.format("[GEAR] saved profile=%s entries=%d", profileName, #entries))
    return true
end

-- -----------------------------------------------------------------------------
-- Gear profile commands
-- -----------------------------------------------------------------------------

local function getOrLoadProfile(state, profileName)
    local entries = state.gearProfiles and state.gearProfiles[profileName]
    if not entries then
        local builtIn = ctx("getBuiltInGearProfile")(profileName)
        if builtIn then
            state.gearProfiles[profileName] = builtIn
            entries = builtIn
            ctx("log")(string.format("[GEAR] loaded built-in profile=%s entries=%d", profileName, #entries))
        end
    end
    return entries
end

function Commands.gearWear(name)
    local player = ctx("getLocalPlayer")()
    if not player then
        ctx("logError")("gear wear failed: no local player")
        return false
    end
    local profileName = tostring(name or "default")
    if profileName == "" then
        profileName = "default"
    end
    local state = ctx("ensureState")(player)
    local entries = getOrLoadProfile(state, profileName)
    if not entries then
        ctx("logError")(string.format("gear wear failed: profile '%s' not found", profileName))
        return false
    end
    local worn, missing, spawned = ctx("wearProfile")(player, entries)
    ctx("log")(string.format("[GEAR] wore profile=%s worn=%d missing=%d spawned=%d", profileName, worn, missing, spawned))
    return true
end

function Commands.gearClear()
    local player = ctx("getLocalPlayer")()
    if not player then
        ctx("logError")("gear clear failed: no local player")
        return false
    end
    ctx("safeMethod")(player, "clearWornItems")
    if type(triggerEvent) == "function" then
        pcall(triggerEvent, "OnClothingUpdated", player)
    end
    ctx("log")("[GEAR] cleared worn items")
    return true
end

function Commands.testUnlock()
    local player = ctx("getLocalPlayer")()
    if not player then
        ctx("logError")("test unlock failed: no local player")
        return false
    end
    local state = ctx("ensureState")(player)
    state.testLock = {
        mode = nil,
        wetness = nil,
        bodyTemp = nil,
        untilMinute = 0,
    }
    ctx("setWetness")(player, 0.0)
    ctx("setBodyTemperature")(player, 37.0)
    ctx("log")("[debug] test lock cleared")
    return true
end

-- -----------------------------------------------------------------------------
-- Environment lock and diagnostics commands
-- -----------------------------------------------------------------------------

function Commands.lockEnv(tempC, wetnessPct, minutes)
    local player = ctx("getLocalPlayer")()
    if not player then
        ctx("logError")("env lock failed: no local player")
        return false
    end
    local state = ctx("ensureState")(player)
    local temp = ctx("clamp")(tonumber(tempC) or 37.0, 34.0, 41.0)
    local wet = ctx("clamp")(tonumber(wetnessPct) or 0.0, 0.0, 100.0)
    local lockMinutes = ctx("clamp")(tonumber(minutes) or 120.0, 1.0, 720.0)
    state.testLock = {
        mode = "envlock",
        wetness = wet,
        bodyTemp = temp,
        untilMinute = ctx("getWorldAgeMinutes")() + lockMinutes,
    }
    ctx("setWetness")(player, wet)
    ctx("setBodyTemperature")(player, temp)
    ctx("log")(string.format("[debug] env lock set temp=%.2f wet=%.1f min=%.0f", temp, wet, lockMinutes))
    return true
end

function Commands.mark(label)
    local player = ctx("getLocalPlayer")()
    local tag = tostring(label or "mark")
    if tag == "" then
        tag = "mark"
    end
    if not player then
        ctx("log")(string.format("[MARK] label=%s no_player=true", tag))
        return false
    end
    local profile = ctx("computeWornProfile")(player)
    local static = ctx("getStaticCombatSnapshot")(player)
    ctx("log")(string.format(
        "[MARK] label=%s t=%.2f burden_kg=%.2f drivers=%d end=%.4f fatigue=%.4f thirst=%.4f temp=%.2f wet=%.1f str=%d fit=%d wpnSkill=%d wpn=%s",
        tag,
        ctx("getWorldAgeMinutes")(),
        tonumber(profile.burdenKg) or 0,
        tonumber(profile.driverCount) or 0,
        tonumber(ctx("getEndurance")(player)) or -1,
        tonumber(ctx("getFatigue")(player)) or -1,
        tonumber(ctx("getThirst")(player)) or -1,
        tonumber(ctx("getBodyTemperature")(player)) or -1,
        tonumber(ctx("getWetness")(player)) or -1,
        tonumber(static.strength) or -1,
        tonumber(static.fitness) or -1,
        tonumber(static.weaponSkill) or -1,
        tostring(static.weaponName)
    ))
    return true
end

-- -----------------------------------------------------------------------------
-- Equilibrium reset
-- -----------------------------------------------------------------------------

function Commands.resetEquilibrium()
    local player = ctx("getLocalPlayer")()
    if not player then
        ctx("logError")("reset equilibrium failed: no local player")
        return false
    end
    local partsReset = ctx("resetCharacterToEquilibrium")(player)
    ctx("log")(string.format(
        "[RESET] equilibrium applied parts=%d end=%.3f fatigue=%.3f thirst=%.3f temp=%.2f wet=%.1f",
        partsReset,
        tonumber(ctx("getEndurance")(player)) or -1,
        tonumber(ctx("getFatigue")(player)) or -1,
        tonumber(ctx("getThirst")(player)) or -1,
        tonumber(ctx("getBodyTemperature")(player)) or -1,
        tonumber(ctx("getWetness")(player)) or -1
    ))
    return true
end

local function getItemOrScriptNumber(item, scriptItem, methodName)
    local value = tonumber(ctx("safeMethod")(item, methodName))
    if value ~= nil then
        return value
    end
    return tonumber(ctx("safeMethod")(scriptItem, methodName)) or 0
end

function Commands.discomfortAudit()
    local player = ctx("getLocalPlayer")()
    if not player then
        ctx("logError")("discomfort audit failed: no local player")
        return false
    end

    local wornItems = ctx("safeMethod")(player, "getWornItems")
    local count = tonumber(wornItems and ctx("safeMethod")(wornItems, "size")) or 0
    local totalWorn = 0
    local nonZeroWearable = 0
    local nonZeroRigid = 0
    local labels = {}

    for i = 0, count - 1 do
        local worn = ctx("safeMethod")(wornItems, "get", i)
        local item = worn and ctx("safeMethod")(worn, "getItem")
        if item then
            totalWorn = totalWorn + 1
            local scriptItem = ctx("safeMethod")(item, "getScriptItem")
            -- SpeedRebalance zeroes script discomfort at boot; audit the authored value.
            local fullType = tostring(ctx("safeMethod")(item, "getFullType") or "")
            local discomfort = ctx("getOriginalDiscomfort")(fullType)
                or getItemOrScriptNumber(item, scriptItem, "getDiscomfortModifier")
            if discomfort > 0.0001 then
                local wornLocation = ctx("safeMethod")(worn, "getLocation")
                local wearable = ctx("isWearableItem")(item, wornLocation)
                if wearable then
                    nonZeroWearable = nonZeroWearable + 1
                end
                local signal = ctx("itemToBurdenSignal")(item, wornLocation)
                local rigid = signal ~= nil and signal.rigid == true
                if rigid then
                    nonZeroRigid = nonZeroRigid + 1
                end
                labels[#labels + 1] = string.format(
                    "%s(%.3f,%s,%s)",
                    fullType ~= "" and fullType or tostring(ctx("safeMethod")(item, "getType") or "unknown"),
                    discomfort,
                    wearable and "wearable" or "non-wearable",
                    rigid and "rigid" or "non-rigid"
                )
            end
        end
    end

    table.sort(labels)
    ctx("log")(string.format(
        "[DISCOMFORT_AUDIT] worn=%d nonZeroWearable=%d nonZeroRigid=%d",
        totalWorn,
        nonZeroWearable,
        nonZeroRigid
    ))
    if #labels > 0 then
        ctx("log")("[DISCOMFORT_AUDIT] items: " .. table.concat(labels, ", "))
    end
    return true
end

-- -----------------------------------------------------------------------------
-- UI probe commands
-- -----------------------------------------------------------------------------

local function collectUIProbeCurrentGear(logItems, logTag)
    local player = ctx("getLocalPlayer")()
    if not player then
        ctx("logError")("ui probe failed: no local player")
        return nil
    end

    local wornItems = ctx("safeMethod")(player, "getWornItems")
    local count = tonumber(wornItems and ctx("safeMethod")(wornItems, "size")) or 0
    local itemCount = 0

    for i = 0, count - 1 do
        local worn = ctx("safeMethod")(wornItems, "get", i)
        local item = worn and ctx("safeMethod")(worn, "getItem")
        if item then
            local wornLocation = tostring(ctx("safeMethod")(worn, "getLocation") or "")
            local signal = ctx("itemToBurdenSignal")(item, wornLocation)
            if signal then
                local fullType = tostring(ctx("safeMethod")(item, "getFullType") or ctx("safeMethod")(item, "getType") or "unknown")
                itemCount = itemCount + 1

                if logItems then
                    ctx("log")(string.format(
                        "%s item=%s loc=%s burden_kg=%.3f mass_kg=%.3f bulk_kg=%.3f rigid_kg=%.3f airflow=%.3f",
                        logTag or "[UI_PROBE]",
                        fullType,
                        wornLocation ~= "" and wornLocation or "none",
                        tonumber(signal.burdenKg) or 0,
                        tonumber(signal.massKg) or 0,
                        tonumber(signal.bulkKg) or 0,
                        tonumber(signal.rigidKg) or 0,
                        tonumber(signal.airflowResistance) or 0
                    ))
                end
            end
        end
    end

    local state = ctx("ensureState")(player)
    local runtime = ctx("getUiRuntimeSnapshot")(state)
    if type(runtime) ~= "table" then
        ctx("logError")("ui probe failed: no production runtime snapshot yet")
        return nil
    end

    return {
        pieces = itemCount,
        burdenKg = tonumber(runtime.burdenKg),
        airflow = tonumber(runtime.airflowResistance),
        thermal = tonumber(runtime.thermalResistance),
        heat = tonumber(runtime.heat),
        loadFraction = tonumber(runtime.loadFraction),
        hotPressure = tonumber(runtime.hotPressure),
        coldSuitability = tonumber(runtime.coldSuitability),
        updatedMinute = tonumber(runtime.updatedMinute),
    }
end

function Commands.uiProbeCurrentGear()
    local summary = collectUIProbeCurrentGear(true, "[UI_PROBE]")
    if not summary then
        return false
    end
    ctx("log")(string.format(
        "[UI_PROBE] total pieces=%d burden_kg=%s airflow=%s thermal=%s heat=%s load_fraction=%s hot_pressure=%s cold_suitability=%s updated_minute=%s source=production_runtime",
        summary.pieces,
        tostring(summary.burdenKg or "na"),
        tostring(summary.airflow or "na"),
        tostring(summary.thermal or "na"),
        tostring(summary.heat or "na"),
        tostring(summary.loadFraction or "na"),
        tostring(summary.hotPressure or "na"),
        tostring(summary.coldSuitability or "na"),
        tostring(summary.updatedMinute or "na")
    ))
    return true
end

-- -----------------------------------------------------------------------------
-- Bench runner command passthroughs
-- -----------------------------------------------------------------------------

function Commands.benchRun(presetId, optsTable)
    local BenchRunner = getBenchRunner()
    if not BenchRunner or type(BenchRunner.run) ~= "function" then
        ctx("logError")("bench run failed: bench runner unavailable")
        return false
    end
    return BenchRunner.run(presetId, optsTable)
end

function Commands.benchStop()
    local BenchRunner = getBenchRunner()
    if not BenchRunner or type(BenchRunner.stop) ~= "function" then
        ctx("logError")("bench stop failed: bench runner unavailable")
        return false
    end
    return BenchRunner.stop()
end

return Commands
