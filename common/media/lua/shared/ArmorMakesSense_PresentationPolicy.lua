ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.PresentationPolicy = ArmorMakesSense.PresentationPolicy or {}

local Policy = ArmorMakesSense.PresentationPolicy

-- Every AMS readout is a strip of PIP_COUNT pips. Each table lists the
-- value at which pip 1..PIP_COUNT lights up.
Policy.PIP_COUNT = 4
Policy.TIERS = { "negligible", "light", "moderate", "heavy", "extreme" }

Policy.LOAD_BANDS = { 0.02, 0.07, 0.13, 0.25 }     -- load fraction of body mass
-- Starts above 1.0 kg: vanilla leaves most shoes and trousers at the default
-- script weight, which lands every pair of shoes at exactly 1.0 kg.
Policy.ITEM_BANDS_KG = { 1.5, 3.0, 4.5, 6.0 }      -- one item's effective kg
Policy.HEAT_BANDS = { 0.05, 0.20, 0.40, 0.65 }     -- insulation x heat strain
Policy.BREATHING_BANDS = { 0.10, 0.35, 0.60, 0.90 } -- respiratory severity
Policy.SLEEP_BANDS = { 0.03, 0.10, 0.20, 0.30 }    -- fatigue recovery lost
Policy.ARM_BANDS_KG = { 1.5, 3.0, 5.0, 8.0 }       -- swing-chain effective kg

Policy.ITEM_TOOLTIP_MIN_KG = Policy.ITEM_BANDS_KG[1]

function Policy.pips(value, bands)
    local v = tonumber(value) or 0
    local count = 0
    for i = 1, #bands do
        if v >= bands[i] then
            count = i
        end
    end
    return count
end

-- Continuous 0..#bands: whole cells for passed bands, a partial cell for
-- progress toward the next one. floor(fill) always equals pips().
function Policy.fill(value, bands)
    local v = tonumber(value) or 0
    local lower = 0
    for i = 1, #bands do
        if v < bands[i] then
            return (i - 1) + math.max(0, (v - lower) / (bands[i] - lower))
        end
        lower = bands[i]
    end
    return #bands
end

function Policy.tier(pips)
    return Policy.TIERS[(tonumber(pips) or 0) + 1] or Policy.TIERS[1]
end

function Policy.loadPips(loadFraction)
    return Policy.pips(loadFraction, Policy.LOAD_BANDS)
end

function Policy.itemPips(burdenKg)
    return Policy.pips(burdenKg, Policy.ITEM_BANDS_KG)
end

function Policy.heatPips(heat)
    return Policy.pips(heat, Policy.HEAT_BANDS)
end

function Policy.breathingPips(severity)
    return Policy.pips(severity, Policy.BREATHING_BANDS)
end

function Policy.sleepPips(penaltyFraction)
    return Policy.pips(penaltyFraction, Policy.SLEEP_BANDS)
end

function Policy.armPips(armKg)
    return Policy.pips(armKg, Policy.ARM_BANDS_KG)
end

-- Signed whole-percent change against vanilla for a regen or drain scale.
function Policy.percentChange(scale)
    return math.floor(((tonumber(scale) or 1) - 1) * 100 + 0.5)
end

return Policy
