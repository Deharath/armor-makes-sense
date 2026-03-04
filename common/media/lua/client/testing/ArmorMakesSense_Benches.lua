ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Testing = ArmorMakesSense.Testing or {}

local Testing = ArmorMakesSense.Testing
Testing.Benches = Testing.Benches or {}

local Benches = Testing.Benches
local C = {}

-- -----------------------------------------------------------------------------
-- Context wiring and bench helpers
-- -----------------------------------------------------------------------------

local function ctx(name)
    return C[name]
end

function Benches.setContext(context)
    C = context or {}
end

function Benches.getVanillaMuscleStrainFactor()
    local resolver = ctx("getVanillaMuscleStrainFactor")
    if type(resolver) ~= "function" then
        return nil
    end
    return resolver()
end

function Benches.getArmStiffnessSnapshot(player)
    local body = ctx("safeMethod")(player, "getBodyDamage")
    if not body then
        return nil
    end
    local function partStiff(partType)
        if not partType then
            return 0
        end
        local part = ctx("safeMethod")(body, "getBodyPart", partType)
        return tonumber(part and ctx("safeMethod")(part, "getStiffness")) or 0
    end
    local hR = partStiff(BodyPartType and BodyPartType.Hand_R)
    local fR = partStiff(BodyPartType and BodyPartType.ForeArm_R)
    local uR = partStiff(BodyPartType and BodyPartType.UpperArm_R)
    local hL = partStiff(BodyPartType and BodyPartType.Hand_L)
    local fL = partStiff(BodyPartType and BodyPartType.ForeArm_L)
    local uL = partStiff(BodyPartType and BodyPartType.UpperArm_L)
    local avg = (hR + fR + uR + hL + fL + uL) / 6.0
    return {
        avg = avg,
        right = hR + fR + uR,
        left = hL + fL + uL,
    }
end

function Benches.getPerkLevelSafe(player, perk)
    if not player or not perk then
        return -1
    end
    return tonumber(ctx("safeMethod")(player, "getPerkLevel", perk)) or -1
end

function Benches.getStaticCombatSnapshot(player)
    local strength = Benches.getPerkLevelSafe(player, PerkFactory and PerkFactory.Perks and PerkFactory.Perks.Strength)
    local fitness = Benches.getPerkLevelSafe(player, PerkFactory and PerkFactory.Perks and PerkFactory.Perks.Fitness)
    local weapon = ctx("safeMethod")(player, "getUseHandWeapon") or ctx("safeMethod")(player, "getPrimaryHandItem")
    local weaponName = tostring(ctx("safeMethod")(weapon, "getDisplayName") or ctx("safeMethod")(weapon, "getType") or "none")
    local weaponSkill = tonumber(weapon and ctx("safeMethod")(weapon, "getWeaponSkill", player)) or -1
    return {
        strength = strength,
        fitness = fitness,
        weaponName = weaponName,
        weaponSkill = weaponSkill,
    }
end

function Benches.fitnessProbe()
    local player = ctx("getLocalPlayer") and ctx("getLocalPlayer")()
    if not player then
        ctx("logError")("fitness probe failed: no local player")
        return false
    end
    local fitness = ctx("safeMethod")(player, "getFitness")
    if not fitness then
        ctx("logError")("fitness probe failed: fitness object unavailable")
        return false
    end

    local groups = {"arms", "chest", "abs", "legs"}
    local bits = {}
    for i = 1, #groups do
        local g = groups[i]
        local timer = tonumber(ctx("safeMethod")(fitness, "getCurrentExeStiffnessTimer", g)) or 0
        local inc = tonumber(ctx("safeMethod")(fitness, "getCurrentExeStiffnessInc", g)) or 0
        bits[#bits + 1] = string.format("%s(timer=%d,inc=%.2f)", g, timer, inc)
    end

    local arm = Benches.getArmStiffnessSnapshot(player)
    local armAvg = tonumber(arm and arm.avg) or 0
    local armL = tonumber(arm and arm.left) or 0
    local armR = tonumber(arm and arm.right) or 0
    local heavyLoad = -1
    local moodles = ctx("safeMethod")(player, "getMoodles")
    if moodles and MoodleType and MoodleType.HEAVY_LOAD then
        heavyLoad = tonumber(ctx("safeMethod")(moodles, "getMoodleLevel", MoodleType.HEAVY_LOAD)) or -1
    end
    local factor = Benches.getVanillaMuscleStrainFactor()

    ctx("log")(string.format(
        "[FITNESS_PROBE] %s arm(avg=%.2f,l=%.2f,r=%.2f) heavyLoad=%d vanillaFactor=%s",
        table.concat(bits, " "),
        armAvg,
        armL,
        armR,
        heavyLoad,
        tostring(factor)
    ))
    return true
end

-- -----------------------------------------------------------------------------
-- Sleep bench routines
-- -----------------------------------------------------------------------------

local function runSleepBenchPhase(setName, sleepHours, temp, wetness)
    local player = ctx("getLocalPlayer") and ctx("getLocalPlayer")()
    if not ctx("gearWearVirtual")(setName) then
        return nil, "gear profile unavailable: " .. tostring(setName)
    end

    local options = ctx("getOptions")()
    ctx("setEndurance")(player, 0.5)
    ctx("setFatigue")(player, 0.3)
    ctx("setThirst")(player, 0.1)
    ctx("setBodyTemperature")(player, temp)
    ctx("setWetness")(player, wetness)

    local profile = ctx("computeArmorProfile")(player)
    local heatFactor = ctx("getHeatFactor")(player, options)
    local wetFactor = ctx("getWetFactor")(player, options)
    local beforeEnd = tonumber(ctx("getEndurance")(player)) or 0
    local beforeFat = tonumber(ctx("getFatigue")(player)) or 0
    local snapshot = {
        massLoad = profile.massLoad or profile.physicalLoad,
        wearabilityLoad = profile.wearabilityLoad or profile.thermalLoad,
        breathingLoad = profile.breathingLoad,
        heatFactor = heatFactor,
        wetFactor = wetFactor,
    }

    local sleepHoursMin = tonumber(options.SleepPenaltyMinHours) or 2.0
    local sleepComposite = (tonumber(snapshot.massLoad) or 0) * 0.45
        + ((tonumber(snapshot.wearabilityLoad) or 0) * (tonumber(options.SleepPenaltyThermalWeight) or 0.45))
        + ((tonumber(snapshot.breathingLoad) or 0) * (tonumber(options.SleepPenaltyBreathingWeight) or 0.65))
    local loadMin = math.max(0, tonumber(options.ArmorLoadMin) or 7)
    local applied = nil
    if sleepHours >= sleepHoursMin and sleepComposite > loadMin then
        local loadScale = ctx("softNorm")(sleepComposite - loadMin, 100.0, 2.4)
        local heatScale = ctx("clamp")(tonumber(snapshot.heatFactor) or 1.0, 1.0, 1.8)
        local wetScale = ctx("clamp")(tonumber(snapshot.wetFactor) or 1.0, 1.0, 1.6)
        local durationScale = ctx("clamp")(1 + ((sleepHours - sleepHoursMin) * 0.10), 1.0, 1.7)
        local penaltyScale = loadScale * heatScale * wetScale * durationScale
        local neutral = (heatScale <= 1.02 and wetScale <= 1.02)
        local endCap = neutral and 0.10 or 0.22
        local fatigueCap = neutral and 0.15 or 0.20
        local endLoss = ctx("clamp")((options.SleepPenaltyEnduranceLoss or 0.03) * penaltyScale, 0, endCap)
        local fatigueGain = ctx("clamp")((options.SleepPenaltyFatigueGain or 0.025) * penaltyScale, 0, fatigueCap)
        ctx("setEndurance")(player, beforeEnd - endLoss)
        ctx("setFatigue")(player, beforeFat + fatigueGain)
        applied = {
            sleepComposite = sleepComposite,
            endLoss = endLoss,
            fatigueGain = fatigueGain,
            sleptHours = sleepHours,
        }
    end

    local afterEnd = tonumber(ctx("getEndurance")(player)) or beforeEnd
    local afterFat = tonumber(ctx("getFatigue")(player)) or beforeFat

    return {
        setName = setName,
        physicalLoad = tonumber(profile.physicalLoad) or 0,
        massLoad = tonumber(profile.massLoad) or tonumber(profile.physicalLoad) or 0,
        wearabilityLoad = tonumber(profile.wearabilityLoad) or tonumber(profile.thermalLoad) or 0,
        breathingLoad = tonumber(profile.breathingLoad) or 0,
        heatFactor = heatFactor,
        wetFactor = wetFactor,
        beforeEnd = beforeEnd,
        afterEnd = afterEnd,
        beforeFat = beforeFat,
        afterFat = afterFat,
        endDelta = afterEnd - beforeEnd,
        fatDelta = afterFat - beforeFat,
        applied = applied,
    }, nil
end

function Benches.sleepBench(hours, tempC, wetnessPct)
    local player = ctx("getLocalPlayer") and ctx("getLocalPlayer")()
    if not player then
        ctx("logError")("sleep bench failed: no local player")
        return false
    end
    local options = ctx("getOptions")()
    if not options.EnableSleepPenaltyModel then
        ctx("logError")("sleep bench failed: EnableSleepPenaltyModel=false")
        return false
    end

    local state = ctx("ensureState")(player)
    local stopAutoRunner = ctx("stopAutoRunner")
    if type(stopAutoRunner) == "function" then
        stopAutoRunner(player, state, "sleep bench")
    end
    state.testLock = {
        mode = nil,
        wetness = nil,
        bodyTemp = nil,
        untilMinute = 0,
    }

    local sleepHours = ctx("clamp")(tonumber(hours) or 8.0, 0.5, 24.0)
    local temp = ctx("clamp")(tonumber(tempC) or 37.0, 34.0, 41.0)
    local wet = ctx("clamp")(tonumber(wetnessPct) or 0.0, 0.0, 100.0)

    ctx("resetCharacterToEquilibrium")(player)
    local light, errLight = runSleepBenchPhase("bulletproof_vest", sleepHours, temp, wet)
    if not light then
        ctx("logError")("sleep bench failed (light): " .. tostring(errLight))
        return false
    end

    ctx("resetCharacterToEquilibrium")(player)
    local heavy, errHeavy = runSleepBenchPhase("heavy", sleepHours, temp, wet)
    if not heavy then
        ctx("logError")("sleep bench failed (heavy): " .. tostring(errHeavy))
        return false
    end

    ctx("log")(string.format(
        "[SLEEP_BENCH_PHASE] set=%s hours=%.2f phy=%.2f mass=%.2f wear=%.2f br=%.2f heat=%.2f wetF=%.2f end=%.4f->%.4f d=%.4f fatigue=%.4f->%.4f d=%.4f",
        light.setName,
        sleepHours,
        light.physicalLoad,
        light.massLoad,
        light.wearabilityLoad,
        light.breathingLoad,
        light.heatFactor,
        light.wetFactor,
        light.beforeEnd,
        light.afterEnd,
        light.endDelta,
        light.beforeFat,
        light.afterFat,
        light.fatDelta
    ))
    ctx("log")(string.format(
        "[SLEEP_BENCH_PHASE] set=%s hours=%.2f phy=%.2f mass=%.2f wear=%.2f br=%.2f heat=%.2f wetF=%.2f end=%.4f->%.4f d=%.4f fatigue=%.4f->%.4f d=%.4f",
        heavy.setName,
        sleepHours,
        heavy.physicalLoad,
        heavy.massLoad,
        heavy.wearabilityLoad,
        heavy.breathingLoad,
        heavy.heatFactor,
        heavy.wetFactor,
        heavy.beforeEnd,
        heavy.afterEnd,
        heavy.endDelta,
        heavy.beforeFat,
        heavy.afterFat,
        heavy.fatDelta
    ))

    local lightEndLoss = math.max(0, -light.endDelta)
    local heavyEndLoss = math.max(0, -heavy.endDelta)
    local lightFatGain = math.max(0, light.fatDelta)
    local heavyFatGain = math.max(0, heavy.fatDelta)
    local endRatio = (lightEndLoss > 0) and (heavyEndLoss / lightEndLoss) or 0
    local fatRatio = (lightFatGain > 0) and (heavyFatGain / lightFatGain) or 0

    ctx("log")(string.format(
        "[SLEEP_BENCH_DONE] hours=%.2f temp=%.2f wet=%.1f lightEndLoss=%.4f heavyEndLoss=%.4f endRatio=%.3f lightFatGain=%.4f heavyFatGain=%.4f fatRatio=%.3f",
        sleepHours,
        temp,
        wet,
        lightEndLoss,
        heavyEndLoss,
        endRatio,
        lightFatGain,
        heavyFatGain,
        fatRatio
    ))
    return true
end

return Benches
