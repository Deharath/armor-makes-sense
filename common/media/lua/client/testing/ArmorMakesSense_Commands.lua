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
    ctx("stopAutoRunner")(player, state)
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
    local profile = ctx("computeArmorProfile")(player)
    local static = ctx("getStaticCombatSnapshot")(player)
    ctx("log")(string.format(
        "[MARK] label=%s t=%.2f phy=%.2f pieces=%d end=%.4f fatigue=%.4f thirst=%.4f temp=%.2f wet=%.1f str=%d fit=%d wpnSkill=%d wpn=%s",
        tag,
        ctx("getWorldAgeMinutes")(),
        tonumber(profile.physicalLoad) or 0,
        tonumber(profile.armorCount) or 0,
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
-- Equilibrium reset and UI probe suite helpers
-- -----------------------------------------------------------------------------

function Commands.resetEquilibrium()
    local player = ctx("getLocalPlayer")()
    if not player then
        ctx("logError")("reset equilibrium failed: no local player")
        return false
    end
    local state = ctx("ensureState")(player)
    ctx("stopAutoRunner")(player, state, "equilibrium reset")
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

local function resolveWearLocation(item)
    local resolver = ctx("resolveItemWearLocation")
    if type(resolver) == "function" then
        local loc = resolver(item)
        if loc ~= nil then
            return loc
        end
    end
    return ctx("safeMethod")(item, "getBodyLocation")
        or ctx("safeMethod")(ctx("safeMethod")(item, "getScriptItem"), "getBodyLocation")
        or ctx("safeMethod")(item, "canBeEquipped")
end

local function createItemByFullType(fullType)
    if not fullType or fullType == "" then
        return nil
    end
    local create = ctx("createItemByFullType")
    if type(create) == "function" then
        return create(fullType)
    end
    if InventoryItemFactory and type(InventoryItemFactory.CreateItem) == "function" then
        local ok, item = pcall(InventoryItemFactory.CreateItem, fullType)
        if ok then
            return item
        end
    end
    return nil
end

local function buildBaselineEntries(overrides)
    local baseline = {
        { fullType = "Base.Shirt_Denim", location = "base:shirt" },
        { fullType = "Base.Trousers_Denim", location = "base:pants" },
        { fullType = "Base.Shoes_TrainerTINT", location = "base:shoes" },
    }
    if type(overrides) ~= "table" then
        return baseline
    end
    local mapped = {}
    for _, entry in ipairs(baseline) do
        mapped[tostring(entry.location)] = entry
    end
    for _, fullType in ipairs(overrides) do
        local item = createItemByFullType(fullType)
        local loc = item and resolveWearLocation(item)
        local locKey = loc and tostring(loc) or ""
        if locKey ~= "" and mapped[locKey] then
            mapped[locKey] = { fullType = fullType, location = locKey }
        end
    end
    local out = {}
    for _, entry in pairs(mapped) do
        out[#out + 1] = entry
    end
    table.sort(out, function(a, b)
        return tostring(a.location) < tostring(b.location)
    end)
    return out
end

local function getUIProbeSuiteDefs()
    return {
        threshold_core_v1 = {
            id = "threshold_core_v1",
            sets = {
                { id = "naked", class = "civilian", naked = true, items = {} },
                { id = "civilian_baseline", class = "civilian", baseline = true, items = {} },
                {
                    id = "civilian_winter_layer",
                    class = "civilian",
                    baseline = false,
                    items = {
                        "Base.Gloves_WhiteTINT",
                        "Base.Scarf_White",
                        "Base.Hat_WinterHat",
                        "Base.Jacket_LeatherBrown",
                        "Base.Jumper_PoloNeck",
                        "Base.Shirt_Denim",
                        "Base.Shoes_WorkBoots",
                        "Base.Socks_Ankle",
                        "Base.Trousers_Denim",
                        "Base.Tshirt_DefaultTEXTURE_TINT",
                    },
                },
                {
                    id = "civilian_rain_layer",
                    class = "civilian",
                    baseline = true,
                    items = {
                        "Base.PonchoTarp",
                        "Base.Shoes_Wellies",
                    },
                },
                {
                    id = "civilian_hazmat",
                    class = "civilian",
                    baseline = true,
                    items = {
                        "Base.HazmatSuit",
                    },
                },
                {
                    id = "mask_mild",
                    class = "mask",
                    baseline = true,
                    items = {
                        "Base.Hat_SurgicalMask",
                    },
                },
                {
                    id = "mask_respirator",
                    class = "mask",
                    baseline = true,
                    items = {
                        "Base.Hat_BuildersRespirator",
                    },
                },
                {
                    id = "mask_gas",
                    class = "mask",
                    baseline = true,
                    items = {
                        "Base.Hat_GasMask",
                    },
                },
                {
                    id = "armor_light_anchor",
                    class = "armor",
                    baseline = true,
                    items = {
                        "Base.Vest_BulletCivilian",
                    },
                },
                {
                    id = "armor_heavy_anchor",
                    class = "armor",
                    baseline = true,
                    items = {
                        "Base.Hat_MetalHelmet",
                        "Base.Gloves_MetalArmour",
                        "Base.Codpiece_Metal",
                        "Base.Vambrace_FullMetal_Left",
                        "Base.Vambrace_FullMetal_Right",
                        "Base.Gorget_Metal",
                        "Base.ShinKneeGuard_L_Metal",
                        "Base.ShinKneeGuard_R_Metal",
                        "Base.Thigh_ArticMetal_L",
                        "Base.Thigh_ArticMetal_R",
                        "Base.Shoulderpad_Articulated_L_Metal",
                        "Base.Shoulderpad_Articulated_R_Metal",
                        "Base.Cuirass_CoatOfPlates",
                        "Base.Shoes_ArmyBoots",
                    },
                },
            },
        },
    }
end

local function resolveUIProbeSuite(suiteId)
    local selectedId = tostring(suiteId or "threshold_core_v1")
    if selectedId == "" then
        selectedId = "threshold_core_v1"
    end
    local suites = getUIProbeSuiteDefs()
    local suite = suites[selectedId]
    if not suite or type(suite.sets) ~= "table" or #suite.sets == 0 then
        return nil, selectedId
    end
    return suite, selectedId
end

local function buildUIProbeSetEntries(setDef)
    local entries = {}
    local baseEnabled = (setDef.naked ~= true) and (setDef.baseline ~= false)
    if baseEnabled then
        local baselineEntries = buildBaselineEntries(setDef.items or {})
        for _, entry in ipairs(baselineEntries) do
            entries[#entries + 1] = entry
        end
    end
    for _, fullType in ipairs(setDef.items or {}) do
        entries[#entries + 1] = { fullType = fullType, location = "" }
    end
    return entries
end

local function findUIProbeSet(suite, setId)
    local wanted = tostring(setId or "")
    if wanted == "" then
        return nil
    end
    for _, setDef in ipairs(suite.sets or {}) do
        if tostring(setDef.id) == wanted then
            return setDef
        end
    end
    return nil
end

local function equipUIProbeSet(player, setDef)
    if not player or not setDef then
        return 0, 0
    end
    ctx("safeMethod")(player, "clearWornItems")
    if setDef.naked == true then
        return 0, 0
    end

    local entries = buildUIProbeSetEntries(setDef)
    local wearProfile = ctx("wearProfile")
    if type(wearProfile) == "function" then
        local worn, missing = wearProfile(player, entries, "virtual")
        return tonumber(worn) or 0, tonumber(missing) or 0
    end
    return 0, #entries
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
                    isArmorLike = ctx("itemToArmorSignal")(item, wornLocation) ~= nil
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

    local options = ctx("getOptions") and ctx("getOptions")() or {}
    local loadMin = math.max(0, tonumber(options and options.ArmorLoadMin) or 7)

    local wornItems = ctx("safeMethod")(player, "getWornItems")
    local count = tonumber(wornItems and ctx("safeMethod")(wornItems, "size")) or 0

    local totalPhysical = 0
    local totalThermal = 0
    local totalBreathing = 0
    local itemCount = 0

    for i = 0, count - 1 do
        local worn = ctx("safeMethod")(wornItems, "get", i)
        local item = worn and ctx("safeMethod")(worn, "getItem")
        if item then
            local wornLocation = tostring(ctx("safeMethod")(worn, "getLocation") or "")
            local signal = ctx("itemToArmorSignal")(item, wornLocation)
            if signal then
                local fullType = tostring(ctx("safeMethod")(item, "getFullType") or ctx("safeMethod")(item, "getType") or "unknown")
                local physical = tonumber(signal.physicalLoad) or 0
                local thermal = tonumber(signal.thermalLoad) or 0
                local breathing = tonumber(signal.breathingLoad) or 0
                local composite = physical + (thermal * 0.45) + (breathing * 0.90)

                totalPhysical = totalPhysical + physical
                totalThermal = totalThermal + thermal
                totalBreathing = totalBreathing + breathing
                itemCount = itemCount + 1

                if logItems then
                    ctx("log")(string.format(
                        "%s item=%s loc=%s phy=%.3f thm=%.3f br=%.3f comp=%.3f",
                        logTag or "[UI_PROBE]",
                        fullType,
                        wornLocation ~= "" and wornLocation or "none",
                        physical,
                        thermal,
                        breathing,
                        composite
                    ))
                end
            end
        end
    end

    local totalComposite = totalPhysical + (totalThermal * 0.45) + (totalBreathing * 0.90)
    local adjustedComposite = math.max(0, totalComposite - loadMin)
    local softNormFn = ctx("softNorm")
    local clampFn = ctx("clamp")
    local burdenNorm = 0
    if type(softNormFn) == "function" and type(clampFn) == "function" then
        burdenNorm = clampFn(softNormFn(adjustedComposite, 100.0, 1.0), 0.0, 1.0)
    end

    local tier = 0
    local label = "hidden"
    if burdenNorm < 0.18 then
        tier = 0
        label = "hidden"
    elseif burdenNorm < 0.38 then
        tier = 1
        label = "slight"
    elseif burdenNorm < 0.62 then
        tier = 2
        label = "moderate"
    else
        tier = 3
        label = "high"
    end

    return {
        pieces = itemCount,
        phy = totalPhysical,
        thm = totalThermal,
        br = totalBreathing,
        comp = totalComposite,
        loadMin = loadMin,
        compAdj = adjustedComposite,
        norm = burdenNorm,
        tier = tier,
        label = label,
    }
end

function Commands.uiProbeCurrentGear()
    local summary = collectUIProbeCurrentGear(true, "[UI_PROBE]")
    if not summary then
        return false
    end
    ctx("log")(string.format(
        "[UI_PROBE] total pieces=%d phy=%.3f thm=%.3f br=%.3f comp=%.3f loadMin=%.3f compAdj=%.3f norm=%.5f tier=%d label=%s",
        summary.pieces,
        summary.phy,
        summary.thm,
        summary.br,
        summary.comp,
        summary.loadMin,
        summary.compAdj,
        summary.norm,
        summary.tier,
        summary.label
    ))
    return true
end

function Commands.uiProbeSuite(suiteId)
    local player = ctx("getLocalPlayer")()
    if not player then
        ctx("logError")("ui probe suite failed: no local player")
        return false
    end

    local suite, selectedId = resolveUIProbeSuite(suiteId)
    if not suite then
        ctx("logError")(string.format("ui probe suite failed: unknown id '%s'", selectedId))
        return false
    end

    local state = ctx("ensureState")(player)
    ctx("stopAutoRunner")(player, state, "ui probe suite")
    ctx("resetCharacterToEquilibrium")(player)
    ctx("safeMethod")(player, "clearWornItems")

    ctx("log")(string.format("[UI_PROBE_SUITE_START] id=%s sets=%d", selectedId, #suite.sets))

    local missingTotal = 0
    for _, setDef in ipairs(suite.sets) do
        local worn, missing = equipUIProbeSet(player, setDef)
        if missing > 0 and setDef.naked ~= true and type(ctx("wearProfile")) ~= "function" then
            ctx("log")(string.format("[UI_PROBE_SUITE_MISS] id=%s set=%s item=* reason=wear_profile_unavailable", selectedId, tostring(setDef.id)))
        end
        missingTotal = missingTotal + missing

        local summary = collectUIProbeCurrentGear(false, "[UI_PROBE]")
        if summary then
            ctx("log")(string.format(
                "[UI_PROBE_SUITE] id=%s set=%s class=%s worn=%d missing=%d pieces=%d phy=%.3f thm=%.3f br=%.3f comp=%.3f loadMin=%.3f compAdj=%.3f norm=%.5f tier=%d label=%s",
                selectedId,
                tostring(setDef.id),
                tostring(setDef.class or "unknown"),
                worn,
                missing,
                summary.pieces,
                summary.phy,
                summary.thm,
                summary.br,
                summary.comp,
                summary.loadMin,
                summary.compAdj,
                summary.norm,
                summary.tier,
                summary.label
            ))
        end
    end

    ctx("safeMethod")(player, "clearWornItems")
    ctx("log")(string.format("[UI_PROBE_SUITE_DONE] id=%s sets=%d missing=%d", selectedId, #suite.sets, missingTotal))
    return true
end

function Commands.uiProbeSetList(suiteId)
    local suite, selectedId = resolveUIProbeSuite(suiteId)
    if not suite then
        ctx("logError")(string.format("ui probe set list failed: unknown id '%s'", selectedId))
        return false
    end
    local names = {}
    for _, setDef in ipairs(suite.sets) do
        names[#names + 1] = tostring(setDef.id)
    end
    ctx("log")(string.format("[UI_PROBE_SET_LIST] id=%s sets=%s", selectedId, table.concat(names, ",")))
    return true
end

function Commands.uiProbeWearSet(suiteId, setId)
    local player = ctx("getLocalPlayer")()
    if not player then
        ctx("logError")("ui probe wear set failed: no local player")
        return false
    end

    local suite, selectedId = resolveUIProbeSuite(suiteId)
    if not suite then
        ctx("logError")(string.format("ui probe wear set failed: unknown id '%s'", selectedId))
        return false
    end
    local target = findUIProbeSet(suite, setId)
    if not target then
        ctx("logError")(string.format("ui probe wear set failed: unknown set '%s'", tostring(setId or "")))
        return false
    end

    local state = ctx("ensureState")(player)
    ctx("stopAutoRunner")(player, state, "ui probe wear set")
    ctx("resetCharacterToEquilibrium")(player)

    local worn, missing = equipUIProbeSet(player, target)
    if missing > 0 and target.naked ~= true and type(ctx("wearProfile")) ~= "function" then
        ctx("log")(string.format("[UI_PROBE_SUITE_MISS] id=%s set=%s item=* reason=wear_profile_unavailable", selectedId, tostring(target.id)))
    end

    ctx("log")(string.format(
        "[UI_PROBE_SET] id=%s set=%s class=%s worn=%d missing=%d",
        selectedId,
        tostring(target.id),
        tostring(target.class or "unknown"),
        worn,
        missing
    ))

    local summary = collectUIProbeCurrentGear(false, "[UI_PROBE]")
    if summary then
        ctx("log")(string.format(
            "[UI_PROBE] total pieces=%d phy=%.3f thm=%.3f br=%.3f comp=%.3f loadMin=%.3f compAdj=%.3f norm=%.5f tier=%d label=%s",
            summary.pieces,
            summary.phy,
            summary.thm,
            summary.br,
            summary.comp,
            summary.loadMin,
            summary.compAdj,
            summary.norm,
            summary.tier,
            summary.label
        ))
    end
    return true
end

function Commands.uiProbeWearSetDefault(setId)
    return Commands.uiProbeWearSet("threshold_core_v1", setId)
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
