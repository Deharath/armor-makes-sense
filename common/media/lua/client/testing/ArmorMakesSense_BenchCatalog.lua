ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Testing = ArmorMakesSense.Testing or {}

local Testing = ArmorMakesSense.Testing
Testing.BenchCatalog = Testing.BenchCatalog or {}

local BenchCatalog = Testing.BenchCatalog
local C = {}

local VALID_CLASSES = {
    civilian = true,
    mask = true,
    armor = true,
    custom = true,
}

-- -----------------------------------------------------------------------------
-- Context wiring and normalization helpers
-- -----------------------------------------------------------------------------

local function ctx(name)
    return C[name]
end

function BenchCatalog.setContext(context)
    C = context or {}
end

local function splitCsv(value)
    local out = {}
    local text = tostring(value or "")
    for token in string.gmatch(text, "([^,]+)") do
        local trimmed = string.gsub(token, "^%s+", "")
        trimmed = string.gsub(trimmed, "%s+$", "")
        if trimmed ~= "" then
            out[#out + 1] = trimmed
        end
    end
    return out
end

local function normalizeList(value)
    if type(value) == "table" then
        local out = {}
        for _, v in ipairs(value) do
            local token = tostring(v or "")
            if token ~= "" then
                out[#out + 1] = token
            end
        end
        return out
    end
    if type(value) == "string" then
        return splitCsv(value)
    end
    return {}
end

local function lowerText(value)
    return string.lower(tostring(value or ""))
end

local function boolOpt(value)
    if value == nil then
        return false
    end
    if type(value) == "boolean" then
        return value
    end
    if type(value) == "number" then
        return value ~= 0
    end
    local text = lowerText(value)
    return text == "1" or text == "true" or text == "yes" or text == "on"
end

local function isCurrentSetAlias(value)
    local text = lowerText(value)
    return text == "current" or text == "equipped" or text == "current_equipped"
end

local function buildBaselineEntries(overrides)
    local entries = {
        { fullType = "Base.Shirt_Denim", location = "base:shirt" },
        { fullType = "Base.Trousers_Denim", location = "base:pants" },
        { fullType = "Base.Shoes_TrainerTINT", location = "base:shoes" },
    }
    if type(overrides) ~= "table" then
        return entries
    end
    local overrideMap = {}
    for _, fullType in ipairs(overrides) do
        overrideMap[tostring(fullType)] = true
    end
    for _, item in ipairs(entries) do
        if overrideMap[item.fullType] then
            item.omit = true
        end
    end
    local filtered = {}
    for _, item in ipairs(entries) do
        if not item.omit then
            filtered[#filtered + 1] = item
        end
    end
    return filtered
end

local function makeCatalog()

    -- -------------------------------------------------------------------------
    -- Canonical benchmark set definitions
    -- -------------------------------------------------------------------------
    local sets = {
        { id = "naked", class = "civilian", naked = true, baseline = false, items = {} },
        {
            id = "civilian_baseline",
            class = "civilian",
            baseline = false,
            items = {
                "Base.Tshirt_DefaultTEXTURE_TINT",
                "Base.Trousers_DefaultTEXTURE_TINT",
                "Base.Shoes_TrainerTINT",
            },
        },
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
            id = "civilian_leather",
            class = "civilian",
            baseline = false,
            items = {
                "Base.Tshirt_DefaultTEXTURE_TINT",
                "Base.Jacket_LeatherBrown",
                "Base.Trousers_Denim",
                "Base.Shoes_WorkBoots",
                "Base.Socks_Ankle",
            },
        },
        { id = "mask_respirator", class = "mask", baseline = false, items = { "Base.Hat_BuildersRespirator" } },
        { id = "mask_respirator_nofilter", class = "mask", baseline = false, items = { "Base.Hat_BuildersRespirator_nofilter" } },
        { id = "mask_gas", class = "mask", baseline = false, items = { "Base.Hat_GasMask" } },
        { id = "mask_gas_nofilter", class = "mask", baseline = false, items = { "Base.Hat_GasMask_nofilter" } },
        { id = "military_surplus", class = "armor", gearProfile = "military_surplus", items = {} },
        { id = "light", class = "armor", gearProfile = "light", items = {} },
        { id = "heavy", class = "armor", gearProfile = "heavy", items = {} },
    }

    local seenSetIds = {}
    for _, setDef in ipairs(sets) do
        seenSetIds[tostring(setDef.id)] = true
    end
    local gear = Testing and Testing.Gear
    local listProfiles = gear and gear.listBuiltInProfileNames
    if type(listProfiles) == "function" then
        for _, profileName in ipairs(listProfiles()) do
            local id = tostring(profileName or "")
            if id ~= "" and not seenSetIds[id] then
                seenSetIds[id] = true
                sets[#sets + 1] = {
                    id = id,
                    class = "armor",
                    gearProfile = id,
                    baseline = false,
                    items = {},
                }
            end
        end
    end

    local presets = {
        benchmark_core_v1 = {
            id = "benchmark_core_v1",
            sets = {
                "naked",
                "civilian_baseline",
                "civilian_leather",
                "military_surplus",
                "light",
                "heavy",
            },
            scenarios = {
                "native_treadmill_walk",
                "native_treadmill_run",
                "native_treadmill_sprint",
                "native_standing_combat_air",
            },
            repeats = 3,
            speed = 8.0,
            mode = "sim",
        },
        benchmark_thermal_v1 = {
            id = "benchmark_thermal_v1",
            sets = {
                "naked",
                "civilian_winter_layer",
                "heavy",
            },
            scenarios = {
                "native_treadmill_walk_hot",
                "native_treadmill_run_hot",
                "native_treadmill_walk_cold",
                "native_treadmill_run_cold",
            },
            repeats = 2,
            speed = 8.0,
            mode = "sim",
        },
        benchmark_thermal_cold_windy_v1 = {
            id = "benchmark_thermal_cold_windy_v1",
            sets = {
                "naked",
                "civilian_winter_layer",
                "heavy",
            },
            scenarios = {
                "native_treadmill_walk_cold",
                "native_treadmill_run_cold",
            },
            repeats = 2,
            speed = 8.0,
            mode = "sim",
        },
        benchmark_thermal_cold_nowind_v1 = {
            id = "benchmark_thermal_cold_nowind_v1",
            sets = {
                "naked",
                "civilian_winter_layer",
                "heavy",
            },
            scenarios = {
                "native_treadmill_walk_cold_nowind",
                "native_treadmill_run_cold_nowind",
            },
            repeats = 2,
            speed = 8.0,
            mode = "sim",
        },
        benchmark_breathing_v1 = {
            id = "benchmark_breathing_v1",
            sets = {
                "naked",
                "mask_respirator",
                "mask_respirator_nofilter",
                "mask_gas",
                "mask_gas_nofilter",
            },
            scenarios = {
                "native_treadmill_walk",
                "native_treadmill_run",
                "native_treadmill_sprint",
            },
            repeats = 3,
            speed = 8.0,
            mode = "sim",
        },
        benchmark_breathing_quick = {
            id = "benchmark_breathing_quick",
            sets = {
                "naked",
                "mask_respirator",
                "mask_respirator_nofilter",
                "mask_gas",
                "mask_gas_nofilter",
            },
            scenarios = {
                "native_treadmill_run",
            },
            repeats = 1,
            speed = 8.0,
            mode = "sim",
        },
        benchmark_smoke = {
            id = "benchmark_smoke",
            sets = {
                "naked",
                "heavy",
            },
            scenarios = {
                "native_treadmill_walk",
                "native_treadmill_run",
                "native_standing_combat_air",
            },
            repeats = 1,
            speed = 8.0,
            mode = "sim",
        },
        benchmark_sleep_v1 = {
            id = "benchmark_sleep_v1",
            sets = {
                "naked",
                "civilian_baseline",
                "civilian_leather",
                "military_surplus",
                "light",
                "heavy",
            },
            scenarios = {
                "sleep_real_neutral_v1",
            },
            repeats = 3,
            speed = 8.0,
            mode = "sim",
        },
    }

    local byId = {}
    for _, setDef in ipairs(sets) do
        byId[tostring(setDef.id)] = setDef
    end

    return {
        sets = sets,
        setById = byId,
        presets = presets,
    }
end

local CATALOG = makeCatalog()

function BenchCatalog.validate()
    local seen = {}
    for _, setDef in ipairs(CATALOG.sets) do
        local id = tostring(setDef.id or "")
        if id == "" then
            if ctx("logError") then ctx("logError")("[AMS_BENCH_CATALOG_ERROR] set missing id") end
            return false
        end
        if seen[id] then
            if ctx("logError") then ctx("logError")("[AMS_BENCH_CATALOG_ERROR] duplicate set id=" .. id) end
            return false
        end
        seen[id] = true
        local cls = tostring(setDef.class or "")
        if not VALID_CLASSES[cls] then
            if ctx("logError") then ctx("logError")("[AMS_BENCH_CATALOG_ERROR] invalid class id=" .. id .. " class=" .. cls) end
            return false
        end
        if type(setDef.items) ~= "table" then
            if ctx("logError") then ctx("logError")("[AMS_BENCH_CATALOG_ERROR] malformed items id=" .. id) end
            return false
        end
    end
    return true
end

function BenchCatalog.getPreset(presetId)
    local id = tostring(presetId or "benchmark_core_v1")
    if id == "" then
        id = "benchmark_core_v1"
    end
    return CATALOG.presets[id], id
end

function BenchCatalog.getSet(setId)
    return CATALOG.setById[tostring(setId or "")]
end

function BenchCatalog.listSetIds(presetId)
    local preset = BenchCatalog.getPreset(presetId)
    if not preset then
        return {}
    end
    local out = {}
    for _, setId in ipairs(preset.sets or {}) do
        out[#out + 1] = tostring(setId)
    end
    return out
end

function BenchCatalog.listScenarioIds(presetId)
    local preset = BenchCatalog.getPreset(presetId)
    if not preset then
        return {}
    end
    local out = {}
    for _, scenarioId in ipairs(preset.scenarios or {}) do
        out[#out + 1] = tostring(scenarioId)
    end
    return out
end

local function normalizeStatProfile(raw)
    if type(raw) ~= "table" then
        return nil
    end
    local function clampLevel(value)
        return math.max(0, math.min(10, math.floor(tonumber(value) or 0)))
    end
    local strengthRaw = raw.strength
    if strengthRaw == nil then
        strengthRaw = raw.str
    end
    local fitnessRaw = raw.fitness
    if fitnessRaw == nil then
        fitnessRaw = raw.fit
    end
    local weaponSkillRaw = raw.weapon_skill
    if weaponSkillRaw == nil then
        weaponSkillRaw = raw.weaponSkill
    end
    if weaponSkillRaw == nil then
        weaponSkillRaw = raw.wpn
    end
    local hasStrength = strengthRaw ~= nil
    local hasFitness = fitnessRaw ~= nil
    local hasWeaponSkill = weaponSkillRaw ~= nil
    local weaponPerk = tostring(raw.weapon_perk or raw.weaponPerk or raw.perk or "all")
    if weaponPerk == "" then
        weaponPerk = "all"
    end
    if (not hasStrength) and (not hasFitness) and (not hasWeaponSkill) then
        return nil
    end
    return {
        strength = hasStrength and clampLevel(strengthRaw) or nil,
        fitness = hasFitness and clampLevel(fitnessRaw) or nil,
        weaponSkill = hasWeaponSkill and clampLevel(weaponSkillRaw) or nil,
        weaponPerk = string.lower(weaponPerk),
    }
end

function BenchCatalog.resolveRunPlan(presetId, opts)
    local preset, resolvedId = BenchCatalog.getPreset(presetId)
    if not preset then
        return nil, "unknown preset '" .. tostring(resolvedId) .. "'"
    end

    local setsFilter = normalizeList(opts and opts.sets)
    local scenariosFilter = normalizeList(opts and opts.scenarios)
    local classesFilter = normalizeList(opts and opts.classes)

    local classMap = {}
    for _, cls in ipairs(classesFilter) do
        classMap[tostring(cls)] = true
    end
    local hasClassFilter = #classesFilter > 0

    local setMap = {}
    for _, id in ipairs(setsFilter) do
        setMap[id] = true
    end
    local hasSetFilter = #setsFilter > 0

    local scenarioMap = {}
    for _, id in ipairs(scenariosFilter) do
        scenarioMap[id] = true
    end
    local hasScenarioFilter = #scenariosFilter > 0
    local runCurrentSet = boolOpt(opts and (opts.current_set or opts.use_current_set or opts.current))
    if not runCurrentSet and hasSetFilter then
        for _, setId in ipairs(setsFilter) do
            if isCurrentSetAlias(setId) then
                runCurrentSet = true
                break
            end
        end
    end

    local presetSetMap = {}
    for _, setId in ipairs(preset.sets or {}) do
        presetSetMap[tostring(setId)] = true
    end

    local requestedOutsidePreset = false
    if hasSetFilter then
        for _, requestedId in ipairs(setsFilter) do
            if not presetSetMap[tostring(requestedId)] then
                requestedOutsidePreset = true
                break
            end
        end
    end

    local selectedSets = {}
    if runCurrentSet then
        if hasSetFilter then
            for _, setId in ipairs(setsFilter) do
                if not isCurrentSetAlias(setId) then
                    return nil, "current_set cannot be combined with explicit set ids"
                end
            end
        end
        selectedSets[1] = {
            id = "current_equipped",
            class = "custom",
            current = true,
            baseline = false,
            items = {},
        }
    elseif hasSetFilter and requestedOutsidePreset then
        local seen = {}
        local unknown = {}
        for _, requestedId in ipairs(setsFilter) do
            local id = tostring(requestedId)
            if not seen[id] then
                seen[id] = true
                local setDef = BenchCatalog.getSet(id)
                if setDef then
                    if (not hasClassFilter) or classMap[tostring(setDef.class)] then
                        selectedSets[#selectedSets + 1] = setDef
                    end
                else
                    unknown[#unknown + 1] = id
                end
            end
        end
        if #unknown > 0 then
            return nil, "unknown set ids: " .. table.concat(unknown, ",")
        end
    else
        for _, setId in ipairs(preset.sets or {}) do
            local setDef = BenchCatalog.getSet(setId)
            if setDef then
                local include = true
                if hasSetFilter and not setMap[tostring(setDef.id)] then
                    include = false
                end
                if include and hasClassFilter and not classMap[tostring(setDef.class)] then
                    include = false
                end
                if include then
                    selectedSets[#selectedSets + 1] = setDef
                end
            end
        end
    end

    local selectedScenarios = {}
    for _, scenarioId in ipairs(preset.scenarios or {}) do
        if (not hasScenarioFilter) or scenarioMap[tostring(scenarioId)] then
            selectedScenarios[#selectedScenarios + 1] = tostring(scenarioId)
        end
    end

    if #selectedSets == 0 then
        return nil, "no sets selected"
    end
    if #selectedScenarios == 0 then
        return nil, "no scenarios selected"
    end

    local repeats = math.max(1, math.floor(tonumber(opts and opts.repeats) or tonumber(preset.repeats) or 1))

    return {
        presetId = resolvedId,
        speed = tonumber(opts and opts.speed) or tonumber(preset.speed) or 10.0,
        mode = tostring((opts and opts.mode) or preset.mode or "lab"),
        label = tostring((opts and opts.label) or ""),
        statProfile = normalizeStatProfile((opts and (opts.stat_profile or opts.statProfile)) or preset.statProfile),
        thresholds = type(opts and opts.thresholds) == "table" and opts.thresholds or (type(preset.thresholds) == "table" and preset.thresholds or {}),
        repeats = repeats,
        sets = selectedSets,
        scenarios = selectedScenarios,
    }, nil
end

function BenchCatalog.buildWearEntries(setDef)
    if not setDef then
        return {}
    end
    if setDef.naked or setDef.current then
        return {}
    end

    if setDef.gearProfile then
        local getProfile = ctx("getBuiltInGearProfile")
        if type(getProfile) == "function" then
            local profile = getProfile(tostring(setDef.gearProfile))
            if type(profile) == "table" then
                local out = {}
                for _, entry in ipairs(profile) do
                    out[#out + 1] = {
                        fullType = tostring(entry.fullType or ""),
                        location = tostring(entry.location or ""),
                    }
                end
                return out
            end
        end
        return {}
    end

    local entries = {}
    local includeBaseline = setDef.baseline ~= false
    if includeBaseline then
        local base = buildBaselineEntries(setDef.items)
        for _, item in ipairs(base) do
            entries[#entries + 1] = { fullType = item.fullType, location = item.location }
        end
    end
    for _, fullType in ipairs(setDef.items or {}) do
        entries[#entries + 1] = { fullType = fullType, location = "" }
    end
    return entries
end

return BenchCatalog
