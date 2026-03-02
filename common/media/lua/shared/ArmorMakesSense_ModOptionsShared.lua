ArmorMakesSense = ArmorMakesSense or {}

-- Module load guard.
if ArmorMakesSense._modOptionsSharedLoaded then
    return
end
ArmorMakesSense._modOptionsSharedLoaded = true

local MOD_ID = "ArmorMakesSense"

-- Optional dependency: keep loading even when ModOptions is unavailable.
local okModOptionsRequire, modOptionsRequireErr = pcall(require, "PZAPI/ModOptions")
if not okModOptionsRequire then
    print(
        "[ArmorMakesSense][WARN] optional require failed: PZAPI/ModOptions :: "
            .. tostring(modOptionsRequireErr)
    )
end
local registered = false

local function safeCall(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, result = pcall(fn, ...)
    if not ok then
        return nil
    end
    return result
end

local function textOrFallback(key, fallback)
    if not getText then
        return fallback
    end
    local value = getText(key)
    if not value or value == key then
        return fallback
    end
    return value
end

local function registerOptions()
    if registered then
        return
    end

    if not (PZAPI and PZAPI.ModOptions and PZAPI.ModOptions.create) then
        return
    end

    local options = PZAPI.ModOptions:getOptions(MOD_ID)
    if not options then
        options = PZAPI.ModOptions:create(MOD_ID, textOrFallback("UI_AMS_ModName", "Armor Makes Sense"))
    end
    if not options then
        return
    end

    if not safeCall(options.getOption, options, "EnableMuscleStrainModel") then
        options:addTickBox(
            "EnableMuscleStrainModel",
            textOrFallback("UI_AMS_EnableMuscleStrainModel", "Enable Armor Muscle Strain"),
            true,
            textOrFallback("UI_AMS_EnableMuscleStrainModel_tooltip", "Adds a small armor-load multiplier to vanilla combat muscle strain. Combat-only; no recovery override.")
        )
    end

    if not safeCall(options.getOption, options, "EnableSleepPenaltyModel") then
        options:addTickBox(
            "EnableSleepPenaltyModel",
            textOrFallback("UI_AMS_EnableSleepPenaltyModel", "Enable Sleep Recovery Penalty"),
            true,
            textOrFallback("UI_AMS_EnableSleepPenaltyModel_tooltip", "Sleeping in restrictive armor reduces overnight endurance recovery and increases next-day fatigue.")
        )
    end

    registered = true
    print("[ArmorMakesSense] ModOptions registered (shared)")
end

registerOptions()
if Events and Events.OnGameBoot and type(Events.OnGameBoot.Add) == "function" then
    Events.OnGameBoot.Add(registerOptions)
end
if Events and Events.OnMainMenuEnter and type(Events.OnMainMenuEnter.Add) == "function" then
    Events.OnMainMenuEnter.Add(registerOptions)
end
