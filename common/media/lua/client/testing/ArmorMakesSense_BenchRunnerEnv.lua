ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Testing = ArmorMakesSense.Testing or {}

local Testing = ArmorMakesSense.Testing
Testing.BenchRunnerEnv = Testing.BenchRunnerEnv or {}

local BenchRunnerEnv = Testing.BenchRunnerEnv
local BenchUtils = Testing.BenchUtils
local C = {}

local BenchCatalog = Testing.BenchCatalog

-- -----------------------------------------------------------------------------
-- Context wiring and shared utility imports
-- -----------------------------------------------------------------------------

local safeMethod = BenchUtils.safeMethod
local clamp = BenchUtils.clamp
local toBoolArg = BenchUtils.toBoolArg

local function ctx(name)
    return C[name]
end

function BenchRunnerEnv.setContext(context)
    C = context or {}
end

-- -----------------------------------------------------------------------------
-- Player readers and coordinate helpers
-- -----------------------------------------------------------------------------

function BenchRunnerEnv.distance2D(ax, ay, bx, by)
    local dx = (tonumber(ax) or 0) - (tonumber(bx) or 0)
    local dy = (tonumber(ay) or 0) - (tonumber(by) or 0)
    return math.sqrt((dx * dx) + (dy * dy))
end

function BenchRunnerEnv.readPlayerCoords(player)
    return
        tonumber(safeMethod(player, "getX")) or 0,
        tonumber(safeMethod(player, "getY")) or 0,
        tonumber(safeMethod(player, "getZ")) or 0
end

function BenchRunnerEnv.snapPlayerToCoords(player, x, y, z)
    if not player then
        return false
    end
    local tx = tonumber(x) or 0
    local ty = tonumber(y) or 0
    local tz = tonumber(z) or 0

    safeMethod(player, "setPath2", nil)
    safeMethod(player, "setMoving", false)
    safeMethod(player, "setJustMoved", false)
    safeMethod(player, "setRunning", false)
    safeMethod(player, "setSprinting", false)
    local behavior = safeMethod(player, "getPathFindBehavior2")
    if behavior then
        safeMethod(behavior, "reset")
    end

    safeMethod(player, "setX", tx)
    safeMethod(player, "setY", ty)
    safeMethod(player, "setZ", tz)
    safeMethod(player, "setLx", tx)
    safeMethod(player, "setLy", ty)
    safeMethod(player, "setLz", tz)
    safeMethod(player, "setNx", tx)
    safeMethod(player, "setNy", ty)

    local cell = type(getCell) == "function" and getCell() or nil
    local square = cell and safeMethod(cell, "getGridSquare", math.floor(tx), math.floor(ty), math.floor(tz))
    if square then
        safeMethod(player, "setCurrentSquare", square)
        safeMethod(player, "setCurrent", square)
    end

    local rx, ry, rz = BenchRunnerEnv.readPlayerCoords(player)
    if BenchRunnerEnv.distance2D(rx, ry, tx, ty) <= 0.25 and math.abs((tonumber(rz) or 0) - tz) <= 0.55 then
        return true
    end
    return false
end

function BenchRunnerEnv.isPlayerOutdoors(player)
    local square = safeMethod(player, "getCurrentSquare")
    local outside = square and safeMethod(square, "isOutside")
    if outside ~= nil then
        return outside == true
    end
    local room = square and safeMethod(square, "getRoom")
    if room ~= nil then
        return room == nil
    end
    local playerOutside = safeMethod(player, "isOutside")
    if playerOutside ~= nil then
        return playerOutside == true
    end
    return nil
end

function BenchRunnerEnv.readClimateSnapshot(player)
    local gameTime = type(getGameTime) == "function" and getGameTime() or nil
    local climate = type(getClimateManager) == "function" and getClimateManager() or nil
    local x, y, z = BenchRunnerEnv.readPlayerCoords(player)

    local ambient = tonumber(gameTime and safeMethod(gameTime, "getAmbient"))
    local timeOfDay = tonumber(gameTime and safeMethod(gameTime, "getTimeOfDay"))
    local gameHour = timeOfDay
    local airTemp = tonumber(climate and safeMethod(climate, "getAirTemperatureForCharacter", player, false))
    local airWindTemp = tonumber(climate and safeMethod(climate, "getAirTemperatureForCharacter", player, true))
    local wind = tonumber(climate and (safeMethod(climate, "getWindSpeedMovement") or safeMethod(climate, "getWindIntensity")))
    local windSpeed = tonumber(climate and (safeMethod(climate, "getWindspeedKph") or safeMethod(climate, "getWindSpeedMovement")))
    local windIntensity = tonumber(climate and safeMethod(climate, "getWindIntensity"))
    local cloud = tonumber(climate and safeMethod(climate, "getCloudIntensity"))
    local rainIntensity = tonumber(climate and (safeMethod(climate, "getRainIntensity") or safeMethod(climate, "getPrecipitationIntensity")))
    local raining = climate and safeMethod(climate, "isRaining") or nil
    local outdoors = BenchRunnerEnv.isPlayerOutdoors(player)
    local inVehicle = safeMethod(player, "getVehicle") ~= nil
    local climbing = safeMethod(player, "isClimbing")

    return {
        x = x,
        y = y,
        z = z,
        outdoors = outdoors,
        inVehicle = inVehicle,
        climbing = climbing,
        ambient = ambient,
        timeOfDay = timeOfDay,
        gameHour = gameHour,
        airTemp = airTemp,
        airWindTemp = airWindTemp,
        wind = wind,
        windSpeed = windSpeed,
        windIntensity = windIntensity,
        cloud = cloud,
        rainIntensity = rainIntensity,
        raining = raining,
    }
end

-- -----------------------------------------------------------------------------
-- Thermoregulator and clothing condition readers
-- -----------------------------------------------------------------------------

function BenchRunnerEnv.getThermoregulator(player)
    local body = safeMethod(player, "getBodyDamage")
    return body and safeMethod(body, "getThermoregulator") or nil
end

function BenchRunnerEnv.readSkinTemperature(player, thermoregulator)
    thermoregulator = thermoregulator or BenchRunnerEnv.getThermoregulator(player)
    if not thermoregulator then
        return nil
    end

    local nodeCount = math.max(0, math.floor(tonumber(safeMethod(thermoregulator, "getNodeSize")) or 0))
    local total = 0.0
    local samples = 0
    for i = 0, nodeCount - 1 do
        local node = safeMethod(thermoregulator, "getNode", i)
        local skin = tonumber(node and safeMethod(node, "getSkinCelcius"))
        if skin ~= nil then
            total = total + skin
            samples = samples + 1
        end
    end

    if samples > 0 then
        return total / samples
    end

    return tonumber(safeMethod(thermoregulator, "getSkinCelcius"))
end

function BenchRunnerEnv.readThermoregulatorMetrics(player)
    local thermoregulator = BenchRunnerEnv.getThermoregulator(player)
    if not thermoregulator then
        return {
            thermoregulator = nil,
            externalAirTemp = nil,
            airAndWindTemp = nil,
            thermalChevronUp = nil,
            energyMultiplier = nil,
            fatigueMultiplier = nil,
            setPoint = nil,
        }
    end

    return {
        thermoregulator = thermoregulator,
        externalAirTemp = tonumber(safeMethod(thermoregulator, "getExternalAirTemperature")),
        airAndWindTemp = tonumber(safeMethod(thermoregulator, "getTemperatureAirAndWind")),
        thermalChevronUp = safeMethod(thermoregulator, "thermalChevronUp"),
        energyMultiplier = tonumber(safeMethod(thermoregulator, "getEnergyMultiplier")),
        fatigueMultiplier = tonumber(safeMethod(thermoregulator, "getFatigueMultiplier")),
        setPoint = tonumber(safeMethod(thermoregulator, "getSetPoint")),
    }
end

function BenchRunnerEnv.readClothingCondition(player)
    local wornItems = safeMethod(player, "getWornItems")
    local count = tonumber(wornItems and safeMethod(wornItems, "size")) or 0
    if count <= 0 then
        return nil, nil, 0
    end

    local total = 0.0
    local samples = 0
    local minRatio = nil
    for i = 0, count - 1 do
        local worn = safeMethod(wornItems, "get", i)
        local item = worn and safeMethod(worn, "getItem") or nil
        if item then
            local condition = tonumber(safeMethod(item, "getCondition"))
            local conditionMax = tonumber(safeMethod(item, "getConditionMax"))
            if condition ~= nil and conditionMax ~= nil and conditionMax > 0 then
                local ratio = clamp(condition / conditionMax, 0, 1)
                total = total + ratio
                samples = samples + 1
                if minRatio == nil or ratio < minRatio then
                    minRatio = ratio
                end
            end
        end
    end

    if samples <= 0 then
        return nil, nil, 0
    end

    return total / samples, minRatio, samples
end

function BenchRunnerEnv.applyNativeActivityMode(player, activity)
    local mode = tostring(activity or "walk")
    if mode == "sprint" then
        safeMethod(player, "setForceSprint", true)
        safeMethod(player, "setForceRun", true)
        safeMethod(player, "setRunning", false)
        safeMethod(player, "setSprinting", true)
    elseif mode == "run" then
        safeMethod(player, "setForceSprint", false)
        safeMethod(player, "setForceRun", true)
        safeMethod(player, "setSprinting", false)
        safeMethod(player, "setRunning", true)
    else
        safeMethod(player, "setForceSprint", false)
        safeMethod(player, "setForceRun", false)
        safeMethod(player, "setSprinting", false)
        safeMethod(player, "setRunning", false)
    end
end

-- -----------------------------------------------------------------------------
-- Native movement/combat helpers
-- -----------------------------------------------------------------------------

function BenchRunnerEnv.stabilizeNativeCombatStance(player, clearPath)
    if not player then
        return
    end

    safeMethod(player, "setForceSprint", false)
    safeMethod(player, "setForceRun", false)
    safeMethod(player, "setSprinting", false)
    safeMethod(player, "setRunning", false)
    safeMethod(player, "setJustMoved", false)
    safeMethod(player, "setMoving", false)
    if clearPath ~= false then
        safeMethod(player, "setPath2", nil)
    end
end

function BenchRunnerEnv.clearNativeMovementState(player, driver)
    if not player then
        return
    end

    safeMethod(player, "setIsAiming", false)
    safeMethod(player, "setAimAtFloor", false)
    safeMethod(player, "setIgnoreAimingInput", false)
    safeMethod(player, "setAttackTargetSquare", nil)
    local clearWeapon = safeMethod(player, "getUseHandWeapon") or safeMethod(player, "getPrimaryHandItem")
    if clearWeapon then
        safeMethod(clearWeapon, "setAttackTargetSquare", nil)
    end
    BenchRunnerEnv.stabilizeNativeCombatStance(player, true)
    safeMethod(player, "setDefaultState")

    if driver and driver.behavior then
        safeMethod(driver.behavior, "reset")
    end
end

function BenchRunnerEnv.setNativeTimeOfDay(timeOfDay)
    if timeOfDay == nil then
        return true, nil
    end
    local gameTime = type(getGameTime) == "function" and getGameTime() or nil
    local hasFunction = ctx("hasFunction")
    if not gameTime or type(hasFunction) ~= "function" or not hasFunction(gameTime, "setTimeOfDay") then
        return false, "native_hard_missing_time_api"
    end
    safeMethod(gameTime, "setTimeOfDay", tonumber(timeOfDay) or 12.0)
    return true, nil
end

local WEATHER_OVERRIDE_PROFILES = {
    neutral = {
        temperature = 21.0,
        wind_intensity = 0.10,
        cloud_intensity = 0.10,
        precipitation_intensity = 0.0,
        humidity = 0.35,
        is_snow = false,
    },
    baseline_neutral = {
        temperature = 21.0,
        wind_intensity = 0.10,
        cloud_intensity = 0.10,
        precipitation_intensity = 0.0,
        humidity = 0.35,
        is_snow = false,
    },
    hot = {
        temperature = 33.0,
        wind_intensity = 0.15,
        cloud_intensity = 0.20,
        precipitation_intensity = 0.0,
        is_snow = false,
    },
    thermal_hot = {
        temperature = 33.0,
        wind_intensity = 0.15,
        cloud_intensity = 0.20,
        precipitation_intensity = 0.0,
        is_snow = false,
    },
    cold = {
        temperature = -12.0,
        wind_intensity = 0.55,
        cloud_intensity = 0.85,
        precipitation_intensity = 0.35,
        is_snow = true,
    },
    thermal_cold = {
        temperature = -12.0,
        wind_intensity = 0.55,
        cloud_intensity = 0.85,
        precipitation_intensity = 0.35,
        is_snow = true,
    },
}

local function setClimateFloatOverride(channel, value)
    if not channel then
        return
    end
    local numeric = tonumber(value) or 0
    safeMethod(channel, "setEnableOverride", true)
    safeMethod(channel, "setOverride", numeric, 0.0)
    safeMethod(channel, "setEnableAdmin", true)
    safeMethod(channel, "setAdminValue", numeric)
    safeMethod(channel, "setEnableModded", true)
    safeMethod(channel, "setModdedValue", numeric)
end

local function setClimateBoolOverride(climate, channel, value)
    if not channel then
        return
    end
    local boolValue = toBoolArg(value)
    safeMethod(channel, "setEnableOverride", true)
    safeMethod(channel, "setOverride", boolValue)
    safeMethod(channel, "setEnableAdmin", true)
    safeMethod(channel, "setAdminValue", boolValue)
    safeMethod(channel, "setEnableModded", true)
    safeMethod(channel, "setModdedValue", boolValue)
    if climate then
        safeMethod(climate, "setPrecipitationIsSnow", boolValue)
    end
end

-- -----------------------------------------------------------------------------
-- Weather override profiles and climate override application
-- -----------------------------------------------------------------------------

function BenchRunnerEnv.cloneTableShallow(source)
    local out = {}
    for key, value in pairs(source or {}) do
        out[key] = value
    end
    return out
end

function BenchRunnerEnv.readWeatherSpec(block)
    if type(block) ~= "table" then
        return nil, nil
    end

    local profileName = string.lower(tostring(block.weather_profile or block.climate_profile or ""))
    local spec = {}
    if profileName ~= "" then
        local profile = WEATHER_OVERRIDE_PROFILES[profileName]
        if type(profile) ~= "table" then
            return nil, "native_hard_unknown_weather_profile"
        end
        spec = BenchRunnerEnv.cloneTableShallow(profile)
        spec.profile = profileName
    end

    local function parseNumber(key, fieldName)
        local raw = block[key]
        if raw == nil then
            return true, nil
        end
        local parsed = tonumber(raw)
        if parsed == nil then
            return false, "native_hard_invalid_" .. tostring(key)
        end
        spec[fieldName] = parsed
        return true, nil
    end

    local ok, err = parseNumber("weather_temp_c", "temperature")
    if not ok then return nil, err end
    ok, err = parseNumber("weather_wind_intensity", "wind_intensity")
    if not ok then return nil, err end
    ok, err = parseNumber("weather_cloud_intensity", "cloud_intensity")
    if not ok then return nil, err end
    ok, err = parseNumber("weather_precip_intensity", "precipitation_intensity")
    if not ok then return nil, err end
    ok, err = parseNumber("weather_fog_intensity", "fog_intensity")
    if not ok then return nil, err end
    ok, err = parseNumber("weather_humidity", "humidity")
    if not ok then return nil, err end
    ok, err = parseNumber("weather_ambient", "ambient")
    if not ok then return nil, err end

    if block.weather_is_snow ~= nil then
        spec.is_snow = toBoolArg(block.weather_is_snow)
    end

    local hasValue = false
    for key, _ in pairs(spec) do
        if key ~= "profile" then
            hasValue = true
            break
        end
    end
    if not hasValue then
        return nil, nil
    end

    spec.profile = spec.profile or "custom"
    return spec, nil
end

function BenchRunnerEnv.applyWeatherOverrides(spec)
    if type(spec) ~= "table" then
        return nil, nil
    end

    local climate = type(getClimateManager) == "function" and getClimateManager() or nil
    if not climate then
        return nil, "native_hard_missing_climate_manager"
    end

    local climateClass = type(rawget) == "function" and rawget(_G, "ClimateManager") or (_G and _G.ClimateManager)
    if not climateClass then
        return nil, "native_hard_missing_climate_class"
    end

    local token = {
        profile = tostring(spec.profile or "custom"),
        spec = BenchRunnerEnv.cloneTableShallow(spec),
        floatIds = {},
        boolIds = {},
        floatValues = {},
        boolValues = {},
    }

    local function applyFloat(specKey, constName)
        local value = spec[specKey]
        if value == nil then
            return true, nil
        end
        local constId = climateClass[constName]
        if constId == nil then
            return false, "native_hard_missing_" .. string.lower(tostring(constName))
        end
        local channel = safeMethod(climate, "getClimateFloat", constId)
        if not channel then
            return false, "native_hard_missing_climate_float_" .. tostring(specKey)
        end
        setClimateFloatOverride(channel, value)
        token.floatIds[#token.floatIds + 1] = constId
        token.floatValues[constId] = tonumber(value) or 0
        return true, nil
    end

    local ok, err = applyFloat("temperature", "FLOAT_TEMPERATURE")
    if not ok then return nil, err end
    ok, err = applyFloat("wind_intensity", "FLOAT_WIND_INTENSITY")
    if not ok then return nil, err end
    ok, err = applyFloat("cloud_intensity", "FLOAT_CLOUD_INTENSITY")
    if not ok then return nil, err end
    ok, err = applyFloat("precipitation_intensity", "FLOAT_PRECIPITATION_INTENSITY")
    if not ok then return nil, err end
    ok, err = applyFloat("fog_intensity", "FLOAT_FOG_INTENSITY")
    if not ok then return nil, err end
    ok, err = applyFloat("humidity", "FLOAT_HUMIDITY")
    if not ok then return nil, err end
    ok, err = applyFloat("ambient", "FLOAT_AMBIENT")
    if not ok then return nil, err end

    if spec.is_snow ~= nil then
        local boolId = climateClass.BOOL_IS_SNOW
        if boolId == nil then
            return nil, "native_hard_missing_bool_is_snow"
        end
        local boolChannel = safeMethod(climate, "getClimateBool", boolId)
        if not boolChannel then
            return nil, "native_hard_missing_climate_bool_is_snow"
        end
        setClimateBoolOverride(climate, boolChannel, spec.is_snow)
        token.boolIds[#token.boolIds + 1] = boolId
        token.boolValues[boolId] = toBoolArg(spec.is_snow)
    end

    safeMethod(climate, "forceDayInfoUpdate")
    safeMethod(climate, "update")

    return token, nil
end

function BenchRunnerEnv.refreshWeatherOverrides(token)
    if type(token) ~= "table" then
        return
    end

    local climate = type(getClimateManager) == "function" and getClimateManager() or nil
    if not climate then
        return
    end

    for _, floatId in ipairs(token.floatIds or {}) do
        local channel = safeMethod(climate, "getClimateFloat", floatId)
        if channel then
            local value = token.floatValues and token.floatValues[floatId] or nil
            if value ~= nil then
                setClimateFloatOverride(channel, value)
            end
        end
    end

    for _, boolId in ipairs(token.boolIds or {}) do
        local channel = safeMethod(climate, "getClimateBool", boolId)
        if channel then
            local value = token.boolValues and token.boolValues[boolId] or nil
            if value ~= nil then
                local boolValue = toBoolArg(value)
                setClimateBoolOverride(climate, channel, boolValue)
            end
        end
    end
end

-- -----------------------------------------------------------------------------
-- Outfit management and movement-route utilities
-- -----------------------------------------------------------------------------

function BenchRunnerEnv.clearWeatherOverrides(token)
    if type(token) ~= "table" then
        return
    end
    local climate = type(getClimateManager) == "function" and getClimateManager() or nil
    if not climate then
        return
    end

    for _, floatId in ipairs(token.floatIds or {}) do
        local channel = safeMethod(climate, "getClimateFloat", floatId)
        if channel then
            safeMethod(channel, "setEnableOverride", false)
            safeMethod(channel, "setEnableAdmin", false)
            safeMethod(channel, "setEnableModded", false)
        end
    end
    for _, boolId in ipairs(token.boolIds or {}) do
        local channel = safeMethod(climate, "getClimateBool", boolId)
        if channel then
            safeMethod(channel, "setEnableOverride", false)
            safeMethod(channel, "setEnableAdmin", false)
            safeMethod(channel, "setEnableModded", false)
        end
    end
    safeMethod(climate, "forceDayInfoUpdate")
    safeMethod(climate, "update")
end

function BenchRunnerEnv.clearExecWeatherOverride(exec)
    if not exec then
        return
    end
    if exec.weatherOverride then
        BenchRunnerEnv.clearWeatherOverrides(exec.weatherOverride)
        exec.weatherOverride = nil
    end
end

function BenchRunnerEnv.buildPatrolWaypoints(x, y, z, radius, shape, axis, rectLongTiles, rectShortTiles)
    local r = math.max(1.5, tonumber(radius) or 4.0)
    local mode = string.lower(tostring(shape or "line"))
    local lane = string.lower(tostring(axis or "x"))

    if mode == "line" or mode == "treadmill" or mode == "back_and_forth" then
        if lane == "y" or lane == "vertical" then
            return {
                { x = x, y = y + r, z = z },
                { x = x, y = y - r, z = z },
            }
        end
        return {
            { x = x + r, y = y, z = z },
            { x = x - r, y = y, z = z },
        }
    end

    if mode == "rectangle" or mode == "rect" then
        local longTiles = math.max(4.0, tonumber(rectLongTiles) or (r * 4.0))
        local shortTiles = math.max(3.0, tonumber(rectShortTiles) or (r * 2.0))
        local halfLong = longTiles * 0.5
        local halfShort = shortTiles * 0.5
        return {
            { x = x + halfLong, y = y + halfShort, z = z },
            { x = x - halfLong, y = y + halfShort, z = z },
            { x = x - halfLong, y = y - halfShort, z = z },
            { x = x + halfLong, y = y - halfShort, z = z },
        }
    end

    return {
        { x = x + r, y = y, z = z },
        { x = x + r, y = y + r, z = z },
        { x = x, y = y + r, z = z },
        { x = x - r, y = y + r, z = z },
        { x = x - r, y = y, z = z },
        { x = x - r, y = y - r, z = z },
        { x = x, y = y - r, z = z },
        { x = x + r, y = y - r, z = z },
    }
end

function BenchRunnerEnv.setEnv(player, tempC, wetness)
    if type(ctx("setBodyTemperature")) == "function" then
        ctx("setBodyTemperature")(player, tempC)
    end
    if type(ctx("setWetness")) == "function" then
        ctx("setWetness")(player, wetness)
    end
end

function BenchRunnerEnv.restoreOutfit(player, entries)
    local wearProfile = ctx("wearProfile")
    if type(wearProfile) ~= "function" then
        return false
    end
    safeMethod(player, "clearWornItems")
    if type(entries) ~= "table" or #entries == 0 then
        return true
    end
    wearProfile(player, entries, "virtual")
    return true
end

function BenchRunnerEnv.equipSet(player, setDef)
    if setDef and setDef.current then
        return 0, 0
    end
    safeMethod(player, "clearWornItems")
    if setDef and setDef.naked then
        return 0, 0
    end
    local entries = BenchCatalog and BenchCatalog.buildWearEntries(setDef) or {}
    local wearProfile = ctx("wearProfile")
    if type(wearProfile) ~= "function" then
        return 0, #entries
    end
    local worn, missing = wearProfile(player, entries, "virtual")
    return tonumber(worn) or 0, tonumber(missing) or 0
end

local function nowMinutes()
    return BenchUtils.nowMinutes(ctx)
end

function BenchRunnerEnv.normalizeLoad(profile)
    profile = profile or {}
    local phy = tonumber(profile.physicalLoad) or 0
    local upperBodyLoad = tonumber(profile.upperBodyLoad) or 0
    local swingChainLoad = tonumber(profile.swingChainLoad) or 0
    local thm = tonumber(profile.thermalLoad) or 0
    local br = tonumber(profile.breathingLoad) or 0
    local pieces = tonumber(profile.armorCount) or 0
    local weightUsedTotal = tonumber(profile.weightUsedTotal) or 0
    local equippedWeightTotal = tonumber(profile.equippedWeightTotal) or 0
    local actualWeightTotal = tonumber(profile.actualWeightTotal) or 0
    local fallbackWeightTotal = tonumber(profile.fallbackWeightTotal) or 0
    local fallbackWeightCount = tonumber(profile.fallbackWeightCount) or 0
    local sourceActualCount = tonumber(profile.sourceActualCount) or 0
    local sourceFallbackCount = tonumber(profile.sourceFallbackCount) or 0

    local options = type(ctx("getOptions")) == "function" and ctx("getOptions")() or {}
    local loadMin = math.max(0, tonumber(options and options.ArmorLoadMin) or 7)
    local comp = phy + (thm * 0.45) + (br * 0.90)
    local compAdj = math.max(0, comp - loadMin)

    return {
        pieces = pieces,
        phy = phy,
        upperBodyLoad = upperBodyLoad,
        swingChainLoad = swingChainLoad,
        thm = thm,
        br = br,
        weightUsedTotal = weightUsedTotal,
        equippedWeightTotal = equippedWeightTotal,
        actualWeightTotal = actualWeightTotal,
        fallbackWeightTotal = fallbackWeightTotal,
        fallbackWeightCount = fallbackWeightCount,
        sourceActualCount = sourceActualCount,
        sourceFallbackCount = sourceFallbackCount,
        compAdj = compAdj,
        norm = nil,
        tier = 0,
    }
end

-- -----------------------------------------------------------------------------
-- Metrics capture
-- -----------------------------------------------------------------------------

function BenchRunnerEnv.readMuscleStrainMetrics(player)
    local body = safeMethod(player, "getBodyDamage")
    local function partStiff(partType)
        if not body or not partType then
            return 0
        end
        local part = safeMethod(body, "getBodyPart", partType)
        return tonumber(part and safeMethod(part, "getStiffness")) or 0
    end

    local handR = partStiff(BodyPartType and BodyPartType.Hand_R)
    local foreArmR = partStiff(BodyPartType and BodyPartType.ForeArm_R)
    local upperArmR = partStiff(BodyPartType and BodyPartType.UpperArm_R)
    local handL = partStiff(BodyPartType and BodyPartType.Hand_L)
    local foreArmL = partStiff(BodyPartType and BodyPartType.ForeArm_L)
    local upperArmL = partStiff(BodyPartType and BodyPartType.UpperArm_L)
    local torsoUpper = partStiff(BodyPartType and BodyPartType.Torso_Upper)
    local torsoLower = partStiff(BodyPartType and BodyPartType.Torso_Lower)
    local upperLegR = partStiff(BodyPartType and BodyPartType.UpperLeg_R)
    local lowerLegR = partStiff(BodyPartType and BodyPartType.LowerLeg_R)
    local footR = partStiff(BodyPartType and BodyPartType.Foot_R)
    local neck = partStiff(BodyPartType and BodyPartType.Neck)

    local rightArm = handR + foreArmR + upperArmR
    local leftArm = handL + foreArmL + upperArmL
    local torso = torsoUpper + torsoLower
    local rightLeg = upperLegR + lowerLegR + footR
    local total = rightArm + leftArm + torso + rightLeg + neck
    local peak = math.max(
        handR, foreArmR, upperArmR, handL, foreArmL, upperArmL,
        torsoUpper, torsoLower, upperLegR, lowerLegR, footR, neck
    )

    return {
        total = total, peak = peak,
        rightArm = rightArm, leftArm = leftArm, torso = torso, rightLeg = rightLeg,
        handR = handR, foreArmR = foreArmR, upperArmR = upperArmR,
        handL = handL, foreArmL = foreArmL, upperArmL = upperArmL,
        torsoUpper = torsoUpper, torsoLower = torsoLower,
        upperLegR = upperLegR, lowerLegR = lowerLegR, footR = footR, neck = neck,
    }
end

function BenchRunnerEnv.collectMetrics(player)
    local getEndurance = ctx("getEndurance")
    local getThirst = ctx("getThirst")
    local getFatigue = ctx("getFatigue")
    local getBodyTemperature = ctx("getBodyTemperature")
    local getWetness = ctx("getWetness")
    local computeArmorProfile = ctx("computeArmorProfile")
    local getOptions = ctx("getOptions")
    local options = type(getOptions) == "function" and getOptions() or {}

    local profile = type(computeArmorProfile) == "function" and computeArmorProfile(player) or {}
    local load = BenchRunnerEnv.normalizeLoad(profile)
    local climate = BenchRunnerEnv.readClimateSnapshot(player)
    local thermoreg = BenchRunnerEnv.readThermoregulatorMetrics(player)
    local skinTemp = BenchRunnerEnv.readSkinTemperature(player, thermoreg.thermoregulator)
    local strain = BenchRunnerEnv.readMuscleStrainMetrics(player)
    local clothingCondAvg, clothingCondMin, clothingCondItems = BenchRunnerEnv.readClothingCondition(player)
    local ambientAirTemp = tonumber(climate.airTemp) or tonumber(climate.ambient)
    local modData = safeMethod(player, "getModData")
    local state = modData and modData["ArmorMakesSenseState"] or nil
    local runtime = type(state) == "table" and type(state.uiRuntimeSnapshot) == "table" and state.uiRuntimeSnapshot or nil
    local runtimeLoadNorm = tonumber(runtime and runtime.loadNorm)
    if runtimeLoadNorm == nil then
        local getUiRuntimeSnapshot = ctx("getUiRuntimeSnapshot")
        if type(getUiRuntimeSnapshot) == "function" then
            local runtimeSnapshot = getUiRuntimeSnapshot(player, state, options)
            runtimeLoadNorm = tonumber(runtimeSnapshot and runtimeSnapshot.loadNorm)
        end
    end
    local runtimeTier = 0
    if runtimeLoadNorm and runtimeLoadNorm >= 0.80 then
        runtimeTier = 4
    elseif runtimeLoadNorm and runtimeLoadNorm >= 0.60 then
        runtimeTier = 3
    elseif runtimeLoadNorm and runtimeLoadNorm >= 0.40 then
        runtimeTier = 2
    elseif runtimeLoadNorm and runtimeLoadNorm >= 0.25 then
        runtimeTier = 1
    end
    local enduranceBeforeAms = tonumber(runtime and runtime.enduranceBeforeAms)
    local enduranceAfterAms = tonumber(runtime and runtime.enduranceAfterAms)
    local enduranceNaturalDelta = tonumber(runtime and runtime.enduranceNaturalDelta)
    local enduranceAppliedDelta = tonumber(runtime and runtime.enduranceAppliedDelta)

    return {
        t = nowMinutes(),
        endurance = tonumber(type(getEndurance) == "function" and getEndurance(player) or nil),
        thirst = tonumber(type(getThirst) == "function" and getThirst(player) or nil),
        fatigue = tonumber(type(getFatigue) == "function" and getFatigue(player) or nil),
        temp = tonumber(type(getBodyTemperature) == "function" and getBodyTemperature(player) or nil),
        wetness = tonumber(type(getWetness) == "function" and getWetness(player) or nil),
        strainTotal = tonumber(strain.total) or 0, strainPeak = tonumber(strain.peak) or 0,
        armStiffness = (tonumber(strain.rightArm) or 0) + (tonumber(strain.leftArm) or 0),
        strainRightArm = tonumber(strain.rightArm) or 0, strainLeftArm = tonumber(strain.leftArm) or 0,
        strainTorso = tonumber(strain.torso) or 0, strainRightLeg = tonumber(strain.rightLeg) or 0,
        strainHandR = tonumber(strain.handR) or 0, strainForeArmR = tonumber(strain.foreArmR) or 0,
        strainUpperArmR = tonumber(strain.upperArmR) or 0,
        strainHandL = tonumber(strain.handL) or 0, strainForeArmL = tonumber(strain.foreArmL) or 0,
        strainUpperArmL = tonumber(strain.upperArmL) or 0,
        strainTorsoUpper = tonumber(strain.torsoUpper) or 0, strainTorsoLower = tonumber(strain.torsoLower) or 0,
        strainUpperLegR = tonumber(strain.upperLegR) or 0, strainLowerLegR = tonumber(strain.lowerLegR) or 0,
        strainFootR = tonumber(strain.footR) or 0, strainNeck = tonumber(strain.neck) or 0,
        pieces = load.pieces, phy = load.phy, upperBodyLoad = load.upperBodyLoad, swingChainLoad = load.swingChainLoad, thm = load.thm, br = load.br,
        compAdj = load.compAdj, norm = runtimeLoadNorm or 0, tier = runtimeTier,
        effectiveLoad = tonumber(runtime and runtime.effectiveLoad),
        loadNormRuntime = runtimeLoadNorm,
        massLoadRuntime = tonumber(runtime and runtime.massLoad),
        thermalLoadRuntime = tonumber(runtime and runtime.thermalLoad),
        breathingLoadRuntime = tonumber(runtime and runtime.breathingLoad),
        thermalPressureScale = tonumber(runtime and runtime.thermalPressureScale),
        hotStrain = tonumber(runtime and runtime.hotStrain),
        bodyTempRuntime = tonumber(runtime and runtime.bodyTemp),
        thermalContribution = tonumber(runtime and runtime.thermalContribution),
        breathingContribution = tonumber(runtime and runtime.breathingContribution),
        muscleContribution = tonumber(runtime and runtime.muscleContribution),
        recoveryContribution = tonumber(runtime and runtime.recoveryContribution),
        enduranceBeforeAms = enduranceBeforeAms,
        enduranceAfterAms = enduranceAfterAms,
        enduranceNaturalDelta = enduranceNaturalDelta,
        enduranceAppliedDelta = enduranceAppliedDelta,
        enduranceBeforeVanilla = nil,
        enduranceAfterVanilla = enduranceBeforeAms,
        weightUsedTotal = load.weightUsedTotal,
        equippedWeightTotal = load.equippedWeightTotal,
        actualWeightTotal = load.actualWeightTotal,
        fallbackWeightTotal = load.fallbackWeightTotal,
        fallbackWeightCount = load.fallbackWeightCount,
        sourceActualCount = load.sourceActualCount,
        sourceFallbackCount = load.sourceFallbackCount,
        x = climate.x, y = climate.y, z = climate.z,
        outdoors = climate.outdoors, inVehicle = climate.inVehicle, climbing = climate.climbing,
        ambient = climate.ambient, ambientAirTemp = ambientAirTemp,
        externalAirTemp = thermoreg.externalAirTemp, airAndWindTemp = thermoreg.airAndWindTemp,
        thermalChevronUp = thermoreg.thermalChevronUp,
        energyMultiplier = thermoreg.energyMultiplier, fatigueMultiplier = thermoreg.fatigueMultiplier,
        setPoint = thermoreg.setPoint,
        timeOfDay = climate.timeOfDay, gameHour = climate.gameHour,
        airTemp = climate.airTemp, airWindTemp = climate.airWindTemp,
        wind = climate.wind, windSpeed = climate.windSpeed, windIntensity = climate.windIntensity,
        cloud = climate.cloud, rainIntensity = climate.rainIntensity, raining = climate.raining,
        skinTemp = skinTemp,
        clothingCondAvg = clothingCondAvg, clothingCondMin = clothingCondMin,
        clothingCondItems = clothingCondItems,
    }
end

return BenchRunnerEnv
