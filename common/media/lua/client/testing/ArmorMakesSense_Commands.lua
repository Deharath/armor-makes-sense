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

function Commands.gearWear(name, mode)
    local player = ctx("getLocalPlayer")()
    if not player then
        ctx("logError")("gear wear failed: no local player")
        return false
    end
    local profileName = tostring(name or "default")
    if profileName == "" then
        profileName = "default"
    end
    local wearMode = tostring(mode or "inventory")
    local state = ctx("ensureState")(player)
    local entries = getOrLoadProfile(state, profileName)
    if not entries then
        ctx("logError")(string.format("gear wear failed: profile '%s' not found", profileName))
        return false
    end
    local worn, missing, spawned = ctx("wearProfile")(player, entries, wearMode)
    ctx("log")(string.format("[GEAR] wore profile=%s mode=%s worn=%d missing=%d spawned=%d", profileName, wearMode, worn, missing, spawned))
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

function Commands.gearList()
    local player = ctx("getLocalPlayer")()
    if not player then
        ctx("logError")("gear list failed: no local player")
        return false
    end
    local state = ctx("ensureState")(player)
    local profiles = state.gearProfiles or {}
    local names = {}
    for k, v in pairs(profiles) do
        names[#names + 1] = string.format("%s(%d)", tostring(k), #(v or {}))
    end
    table.sort(names)
    ctx("log")("[GEAR] profiles: " .. table.concat(names, ", "))
    return true
end

function Commands.gearReloadBuiltin(name)
    local player = ctx("getLocalPlayer")()
    if not player then
        ctx("logError")("gear reload built-in failed: no local player")
        return false
    end
    local profileName = tostring(name or "")
    if profileName == "" then
        ctx("logError")("gear reload built-in failed: provide profile name")
        return false
    end
    local builtIn = ctx("getBuiltInGearProfile")(profileName)
    if not builtIn then
        ctx("logError")(string.format("gear reload built-in failed: no built-in profile '%s'", profileName))
        return false
    end
    local state = ctx("ensureState")(player)
    state.gearProfiles[profileName] = builtIn
    ctx("log")(string.format("[GEAR] reloaded built-in profile=%s entries=%d", profileName, #builtIn))
    return true
end

function Commands.gearDump(name)
    local player = ctx("getLocalPlayer")()
    if not player then
        ctx("logError")("gear dump failed: no local player")
        return false
    end
    local profileName = tostring(name or "default")
    if profileName == "" then
        profileName = "default"
    end
    local state = ctx("ensureState")(player)
    local entries = getOrLoadProfile(state, profileName)
    if not entries then
        ctx("logError")(string.format("gear dump failed: profile '%s' not found", profileName))
        return false
    end

    local baseline = ctx("getBaselineWearEntries")()
    local baselineTypes = {}
    local profileTypes = {}
    for _, entry in ipairs(baseline) do
        baselineTypes[#baselineTypes + 1] = tostring(entry.fullType or "")
    end
    for _, entry in ipairs(entries) do
        profileTypes[#profileTypes + 1] = tostring(entry.fullType or "")
    end
    table.sort(baselineTypes)
    table.sort(profileTypes)

    ctx("log")(string.format(
        "[GEAR] dump profile=%s baselineCount=%d profileCount=%d totalWear=%d",
        profileName,
        #baselineTypes,
        #profileTypes,
        #baselineTypes + #profileTypes
    ))
    ctx("log")("[GEAR] baseline items: " .. table.concat(baselineTypes, ", "))
    ctx("log")("[GEAR] profile items: " .. table.concat(profileTypes, ", "))
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

function Commands.envNow()
    local player = ctx("getLocalPlayer")()
    if not player then
        ctx("logError")("env read failed: no local player")
        return false
    end
    ctx("log")(string.format(
        "[debug] env now temp=%.2f wet=%.1f",
        tonumber(ctx("getBodyTemperature")(player)) or -1,
        tonumber(ctx("getWetness")(player)) or -1
    ))
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
        "[MARK] label=%s t=%.2f phy=%.2f pieces=%d end=%.4f fatigue=%.4f thirst=%.4f temp=%.2f wet=%.1f str=%d fit=%d wpnSkill=%d wpn=%s",
        tag,
        ctx("getWorldAgeMinutes")(),
        tonumber(profile.physicalLoad) or 0,
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
    local nonZeroArmorLike = 0
    local labels = {}

    for i = 0, count - 1 do
        local worn = ctx("safeMethod")(wornItems, "get", i)
        local item = worn and ctx("safeMethod")(worn, "getItem")
        if item then
            totalWorn = totalWorn + 1
            local scriptItem = ctx("safeMethod")(item, "getScriptItem")
            local discomfort = getItemOrScriptNumber(item, scriptItem, "getDiscomfortModifier")
            if discomfort > 0.0001 then
                local wornLocation = ctx("safeMethod")(worn, "getLocation")
                local wearable = ctx("isWearableItem")(item, wornLocation)
                if wearable then
                    nonZeroWearable = nonZeroWearable + 1
                end
                local isArmorLike = false
                local classifier = ctx("Classifier")
                if classifier and type(classifier.evaluateArmorLike) == "function" then
                    local eval = classifier.evaluateArmorLike(item, scriptItem, wornLocation)
                    isArmorLike = eval and ctx("toBoolean")(eval.isArmorLike) or false
                else
                    isArmorLike = ctx("itemToBurdenSignal")(item, wornLocation) ~= nil
                end
                if isArmorLike then
                    nonZeroArmorLike = nonZeroArmorLike + 1
                end
                labels[#labels + 1] = string.format(
                    "%s(%.3f,%s,%s)",
                    tostring(ctx("safeMethod")(item, "getFullType") or ctx("safeMethod")(item, "getType") or "unknown"),
                    discomfort,
                    wearable and "wearable" or "non-wearable",
                    isArmorLike and "armor" or "non-armor"
                )
            end
        end
    end

    table.sort(labels)
    local classifier = ctx("Classifier")
    ctx("log")(string.format(
        "[DISCOMFORT_AUDIT] worn=%d nonZeroWearable=%d nonZeroArmorLike=%d classifier=%s",
        totalWorn,
        nonZeroWearable,
        nonZeroArmorLike,
        tostring(classifier and type(classifier.evaluateArmorLike) == "function")
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
                        "%s item=%s loc=%s phy=%.3f airflow=%.3f thermal=%.3f",
                        logTag or "[UI_PROBE]",
                        fullType,
                        wornLocation ~= "" and wornLocation or "none",
                        tonumber(signal.physicalLoad) or 0,
                        tonumber(signal.airflowResistance) or 0,
                        tonumber(signal.thermalResistance) or 0
                    ))
                end
            end
        end
    end

    local state = ctx("ensureState")(player)
    local runtime = type(state) == "table" and state.uiRuntimeSnapshot or nil
    if type(runtime) ~= "table" then
        ctx("logError")("ui probe failed: no production runtime snapshot yet")
        return nil
    end

    return {
        pieces = itemCount,
        phy = tonumber(runtime.physicalLoad),
        airflow = tonumber(runtime.airflowResistance),
        thermal = tonumber(runtime.thermalResistance),
        effective = tonumber(runtime.effectiveLoad),
        norm = tonumber(runtime.loadNorm),
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
        "[UI_PROBE] total pieces=%d phy=%s airflow=%s thermal=%s effective=%s norm=%s hot_pressure=%s cold_suitability=%s updated_minute=%s source=production_runtime",
        summary.pieces,
        tostring(summary.phy or "na"),
        tostring(summary.airflow or "na"),
        tostring(summary.thermal or "na"),
        tostring(summary.effective or "na"),
        tostring(summary.norm or "na"),
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

function Commands.benchStatus()
    local BenchRunner = getBenchRunner()
    if not BenchRunner or type(BenchRunner.status) ~= "function" then
        ctx("logError")("bench status failed: bench runner unavailable")
        return false
    end
    return BenchRunner.status()
end

function Commands.benchStop()
    local BenchRunner = getBenchRunner()
    if not BenchRunner or type(BenchRunner.stop) ~= "function" then
        ctx("logError")("bench stop failed: bench runner unavailable")
        return false
    end
    return BenchRunner.stop()
end

function Commands.benchSetList(presetId)
    local BenchRunner = getBenchRunner()
    if not BenchRunner or type(BenchRunner.setList) ~= "function" then
        ctx("logError")("bench set list failed: bench runner unavailable")
        return false
    end
    return BenchRunner.setList(presetId)
end

function Commands.benchScenarioList(presetId)
    local BenchRunner = getBenchRunner()
    if not BenchRunner or type(BenchRunner.scenarioList) ~= "function" then
        ctx("logError")("bench scenario list failed: bench runner unavailable")
        return false
    end
    return BenchRunner.scenarioList(presetId)
end

function Commands.benchWearSet(presetId, setId)
    local BenchRunner = getBenchRunner()
    if not BenchRunner or type(BenchRunner.wearSet) ~= "function" then
        ctx("logError")("bench wear set failed: bench runner unavailable")
        return false
    end
    return BenchRunner.wearSet(presetId, setId)
end

return Commands
