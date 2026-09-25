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

local function makeCatalog()

    -- -------------------------------------------------------------------------
    -- Canonical benchmark set definitions
    -- -------------------------------------------------------------------------
    local sets = {
        { id = "naked", class = "civilian", naked = true, items = {} },
        {
            id = "civilian_baseline",
            class = "civilian",
            items = {
                "Base.Tshirt_DefaultTEXTURE_TINT",
                "Base.Trousers_DefaultTEXTURE_TINT",
                "Base.Shoes_TrainerTINT",
            },
        },
        {
            id = "civilian_winter_layer",
            class = "civilian",
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
            items = {
                "Base.Tshirt_DefaultTEXTURE_TINT",
                "Base.Jacket_LeatherBrown",
                "Base.Trousers_Denim",
                "Base.Shoes_WorkBoots",
                "Base.Socks_Ankle",
            },
        },
        { id = "mask_respirator", class = "mask", items = { "Base.Hat_BuildersRespirator" } },
        { id = "mask_respirator_nofilter", class = "mask", items = { "Base.Hat_BuildersRespirator_nofilter" } },
        { id = "mask_gas", class = "mask", items = { "Base.Hat_GasMask" } },
        { id = "mask_gas_nofilter", class = "mask", items = { "Base.Hat_GasMask_nofilter" } },
        { id = "military_surplus", class = "armor", gearProfile = "military_surplus", items = {} },
        { id = "bulletproof_vest", class = "armor", gearProfile = "light", items = {} },
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
                            items = {},
                }
            end
        end
    end

    local coreSets = { "naked", "civilian_baseline", "civilian_leather", "military_surplus", "bulletproof_vest", "heavy" }
    local thermalSets = { "naked", "civilian_winter_layer", "heavy" }
    local maskSets = { "naked", "mask_respirator", "mask_respirator_nofilter", "mask_gas", "mask_gas_nofilter" }

    local presets = {
        core = {
            sets = coreSets,
            scenarios = { "treadmill_run", "treadmill_sprint", "combat_air" },
            repeats = 1,
        },
        recovery = {
            sets = coreSets,
            scenarios = { "recovery_stand", "recovery_walk" },
            repeats = 1,
        },
        thermal = {
            sets = thermalSets,
            scenarios = { "treadmill_walk_hot", "treadmill_run_hot", "treadmill_walk_cold", "treadmill_run_cold" },
            repeats = 1,
        },
        thermal_nowind = {
            sets = thermalSets,
            scenarios = { "treadmill_walk_cold_nowind", "treadmill_run_cold_nowind" },
            repeats = 1,
        },
        thermal_transient = {
            sets = { "naked", "civilian_baseline", "heavy" },
            scenarios = { "thermal_transient_run_60s", "thermal_transient_run_180s", "thermal_transient_run_360s" },
            repeats = 2,
        },
        breathing = {
            sets = maskSets,
            scenarios = { "breathing_walk", "breathing_run", "breathing_sprint" },
            repeats = 1,
        },
        breathing_quick = {
            sets = maskSets,
            scenarios = { "breathing_run" },
            repeats = 1,
        },
        sleep = {
            sets = coreSets,
            scenarios = { "sleep_neutral" },
            repeats = 3,
        },
        smoke = {
            sets = { "naked", "heavy" },
            scenarios = { "treadmill_run", "recovery_stand" },
            repeats = 1,
        },
    }
    -- Endurance is measured as a per-tick ratio and strain as per-frame gain,
    -- so game speed only sets how much game time passes per frame. Sleep keeps
    -- the older 8x until it has been validated faster.
    for id, preset in pairs(presets) do
        preset.id = id
        preset.speed = id == "sleep" and 8.0 or 16.0
    end

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

function BenchCatalog.validate(scenarioExists)
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

    for presetId, preset in pairs(CATALOG.presets) do
        if tostring(preset.id or "") ~= tostring(presetId) then
            if ctx("logError") then ctx("logError")("[AMS_BENCH_CATALOG_ERROR] preset id mismatch=" .. tostring(presetId)) end
            return false
        end
        if type(preset.sets) ~= "table" or #preset.sets == 0 or type(preset.scenarios) ~= "table" or #preset.scenarios == 0 then
            if ctx("logError") then ctx("logError")("[AMS_BENCH_CATALOG_ERROR] empty preset=" .. tostring(presetId)) end
            return false
        end
        for _, setId in ipairs(preset.sets) do
            if not CATALOG.setById[tostring(setId)] then
                if ctx("logError") then ctx("logError")("[AMS_BENCH_CATALOG_ERROR] unknown set=" .. tostring(setId) .. " preset=" .. tostring(presetId)) end
                return false
            end
        end
        if type(scenarioExists) == "function" then
            for _, scenarioId in ipairs(preset.scenarios) do
                if not scenarioExists(scenarioId) then
                    if ctx("logError") then ctx("logError")("[AMS_BENCH_CATALOG_ERROR] unknown scenario=" .. tostring(scenarioId) .. " preset=" .. tostring(presetId)) end
                    return false
                end
            end
        end
    end
    return true
end

function BenchCatalog.getPreset(presetId)
    local id = tostring(presetId or "core")
    if id == "" then
        id = "core"
    end
    return CATALOG.presets[id], id
end

function BenchCatalog.listPresetIds()
    local out = {}
    for id in pairs(CATALOG.presets) do
        out[#out + 1] = id
    end
    table.sort(out)
    return out
end

function BenchCatalog.getSet(setId)
    return CATALOG.setById[tostring(setId or "")]
end

local function toSet(list)
    local out = {}
    for _, value in ipairs(list) do
        out[tostring(value)] = true
    end
    return out
end

function BenchCatalog.resolveRunPlan(presetId, opts)
    opts = opts or {}
    local preset, resolvedId = BenchCatalog.getPreset(presetId)
    if not preset then
        return nil, "unknown preset '" .. tostring(resolvedId) .. "'"
    end

    local setsFilter = normalizeList(opts.sets)
    local scenariosFilter = normalizeList(opts.scenarios)
    local classesFilter = normalizeList(opts.classes)
    local classMap = toSet(classesFilter)
    local scenarioMap = toSet(scenariosFilter)

    local selectedSets = {}
    if opts.current_set == true then
        if #setsFilter > 0 then
            return nil, "current_set cannot be combined with explicit set ids"
        end
        selectedSets[1] = { id = "current_equipped", class = "custom", current = true, items = {} }
    else
        -- Explicit set ids may come from anywhere in the catalog, not just the preset.
        local sourceIds = #setsFilter > 0 and setsFilter or preset.sets
        local seen, unknown = {}, {}
        for _, rawId in ipairs(sourceIds) do
            local id = tostring(rawId)
            if not seen[id] then
                seen[id] = true
                local setDef = BenchCatalog.getSet(id)
                if not setDef then
                    unknown[#unknown + 1] = id
                elseif #classesFilter == 0 or classMap[tostring(setDef.class)] then
                    selectedSets[#selectedSets + 1] = setDef
                end
            end
        end
        if #unknown > 0 then
            return nil, "unknown set ids: " .. table.concat(unknown, ",")
        end
    end

    local selectedScenarios = {}
    for _, scenarioId in ipairs(preset.scenarios) do
        if #scenariosFilter == 0 or scenarioMap[tostring(scenarioId)] then
            selectedScenarios[#selectedScenarios + 1] = tostring(scenarioId)
        end
    end

    if #selectedSets == 0 then
        return nil, "no sets selected"
    end
    if #selectedScenarios == 0 then
        return nil, "no scenarios selected"
    end

    return {
        presetId = resolvedId,
        speed = tonumber(opts.speed) or preset.speed,
        label = tostring(opts.label or ""),
        thresholds = type(opts.thresholds) == "table" and opts.thresholds or {},
        repeats = math.max(1, math.floor(tonumber(opts.repeats) or preset.repeats)),
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
    for _, fullType in ipairs(setDef.items or {}) do
        entries[#entries + 1] = { fullType = fullType, location = "" }
    end
    return entries
end

return BenchCatalog
