ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Core = ArmorMakesSense.Core or {}

-- Turns worn-gear analysis and a runtime snapshot into what the Burden tab
-- shows. No UI calls, so wording and decisions are testable offline.
local View = {}
ArmorMakesSense.Core.BurdenView = View

local LoadModel = require "ArmorMakesSense_LoadModelShared"
local Policy = require "ArmorMakesSense_PresentationPolicy"
local SpeedRebalance = require "ArmorMakesSense_SpeedRebalance"
local Strain = require "ArmorMakesSense_StrainShared"

View.MAX_ITEMS = 6

-- BodyPartType indices. BloodBodyPartType uses the same order plus Back (17),
-- which the body map folds into the upper torso.
View.PART = {
    Hand_L = 0, Hand_R = 1, ForeArm_L = 2, ForeArm_R = 3, UpperArm_L = 4, UpperArm_R = 5,
    Torso_Upper = 6, Torso_Lower = 7, Head = 8, Neck = 9, Groin = 10,
    UpperLeg_L = 11, UpperLeg_R = 12, LowerLeg_L = 13, LowerLeg_R = 14, Foot_L = 15, Foot_R = 16,
}
View.PART_COUNT = 17
local BACK = 17

-- `%1`, `%2` placeholders. B42 loads translations as Java format strings:
-- arguments must go through getText itself (calling it bare on a template logs
-- a formatter warning), and a literal percent sign is `%%`.
function View.tr(key, fallback, ...)
    local args = { ... }
    if type(getText) == "function" then
        local value = getText(key, ...)
        if value and value ~= key then
            return value
        end
    end
    if #args == 0 then
        return fallback
    end
    return (string.gsub(fallback, "%%(%d)", function(n)
        local value = args[tonumber(n)]
        return value ~= nil and tostring(value) or ""
    end))
end
local tr = View.tr

local function kg(value)
    return string.format("%.1f", tonumber(value) or 0)
end

local function pct(scale)
    return string.format("%+d%%", Policy.percentChange(scale))
end

-- 0 pips reads as inactive; 3 and 4 escalate to warning colors.
local function tone(pips, base)
    if pips >= 4 then return "bad" end
    if pips >= 3 then return "warn" end
    if pips <= 0 then return "dim" end
    return base
end

local function magnitudeTone(scale)
    local m = math.abs(Policy.percentChange(scale))
    if m >= 40 then return "bad" end
    if m >= 15 then return "warn" end
    return "text"
end

local TIERS = {
    [0] = { "UI_AMS_Tier_Negligible", "Negligible" },
    { "UI_AMS_Tier_Light", "Light" },
    { "UI_AMS_Tier_Moderate", "Moderate" },
    { "UI_AMS_Tier_Heavy", "Heavy" },
    { "UI_AMS_Tier_Extreme", "Extreme" },
}

function View.tierText(pips)
    local t = TIERS[pips] or TIERS[0]
    return tr(t[1], t[2])
end

local function stateText(states, pips)
    local s = states[pips] or states[0]
    return tr(s[1], s[2])
end

-- -----------------------------------------------------------------------------
-- Body parts
-- -----------------------------------------------------------------------------

-- Fallback when an item reports no covered parts. First match wins; full
-- suits come first because "torso1legs1" also contains "legs".
local LOCATION_PARTS = {
    { { "fullsuit", "boilersuit", "torso1legs1" }, { "Torso_Upper", "Torso_Lower", "Groin", "UpperLeg", "LowerLeg" } },
    { { "shoe", "sock", "foot", "ankle" }, { "Foot" } },
    { { "calf", "shin", "knee", "gaiter" }, { "LowerLeg" } },
    { { "thigh" }, { "UpperLeg" } },
    { { "pants", "legs", "skirt", "shorts" }, { "Groin", "UpperLeg" } },
    { { "forearm", "elbow" }, { "ForeArm" } },
    { { "hand", "finger", "wrist", "glove" }, { "Hand" } },
    { { "shoulder", "arm" }, { "UpperArm" } },
    { { "mask", "eye", "ear", "nose", "hat", "head" }, { "Head" } },
    { { "neck", "gorget", "scarf" }, { "Neck" } },
}
local DEFAULT_PARTS = { "Torso_Upper", "Torso_Lower" }

local function has(text, fragment)
    return string.find(text, fragment, 1, true) ~= nil
end

local function expand(names, location)
    local left, right = has(location, "left"), has(location, "right")
    local out = {}
    for _, name in ipairs(names) do
        if View.PART[name] then
            out[#out + 1] = View.PART[name]
        else
            if left or not right then out[#out + 1] = View.PART[name .. "_L"] end
            if right or not left then out[#out + 1] = View.PART[name .. "_R"] end
        end
    end
    return out
end

function View.partsForLocation(location)
    local loc = string.lower(tostring(location or ""))
    for _, entry in ipairs(LOCATION_PARTS) do
        for _, fragment in ipairs(entry[1]) do
            if has(loc, fragment) then
                return expand(entry[2], loc)
            end
        end
    end
    return expand(DEFAULT_PARTS, loc)
end

-- Covered part indices (BloodBodyPartType order) or the location fallback.
function View.itemParts(row, covered)
    local out, seen = {}, {}
    for _, index in ipairs(covered or {}) do
        local part = index == BACK and View.PART.Torso_Upper or index
        if part >= 0 and part < View.PART_COUNT and not seen[part] then
            seen[part] = true
            out[#out + 1] = part
        end
    end
    if #out == 0 then
        return View.partsForLocation(row and row.bodyLocation)
    end
    return out
end

local function spread(target, parts, value)
    if #parts == 0 then
        return
    end
    local share = value / #parts
    for _, part in ipairs(parts) do
        target[part] = (target[part] or 0) + share
    end
end

-- -----------------------------------------------------------------------------
-- Rows
-- -----------------------------------------------------------------------------

local function buildLoad(r, options)
    local lf = tonumber(r.loadFraction) or 0
    local pips = Policy.loadPips(lf)
    local burden = tonumber(r.burdenKg) or 0
    local allowance = tonumber(options.BurdenClothingAllowanceKg) or 3.5
    local detail
    if burden <= allowance then
        detail = tr("UI_AMS_Load_UnderAllowance", "Within the %1 kg that everyday clothing gets for free.", kg(allowance))
    else
        detail = tr("UI_AMS_Load_Carrier", "Your build: %1 kg, Strength %2.",
            string.format("%.0f", tonumber(r.bodyKg) or 80), tostring(r.strength or 5))
    end
    return {
        label = tr("UI_AMS_Row_Load", "Load"),
        pips = pips,
        fill = Policy.fill(lf, Policy.LOAD_BANDS),
        state = View.tierText(pips),
        value = kg(burden) .. " kg",
        tone = tone(pips, "burden"),
        color = "burden",
        detail = detail,
    }
end

local function buildEndurance(r)
    local stand = tonumber(r.standRegenScale) or 1
    local walk = tonumber(r.walkRegenScale) or 1
    local run = tonumber(r.runDrainScale) or 1
    local sprint = tonumber(r.sprintDrainScale) or 1
    local normal = tr("UI_AMS_Pace_Normal", "normal")

    local function recovery(scale)
        if scale < 0 then
            return tr("UI_AMS_Pace_Drains", "drains"), "bad"
        elseif scale < 0.995 then
            return pct(scale), magnitudeTone(scale)
        end
        return normal, "dim"
    end
    local function use(scale)
        if scale > 1.005 then
            return pct(scale), magnitudeTone(scale)
        end
        return normal, "dim"
    end

    local function pace(key, fallback, value, valueTone)
        return { label = tr(key, fallback), value = value, tone = valueTone }
    end
    local groups = {
        {
            label = tr("UI_AMS_Endurance_Recovery", "Recovery"),
            paces = {
                pace("UI_AMS_Pace_Stand", "Standing", recovery(stand)),
                pace("UI_AMS_Pace_Walk", "Walking", recovery(walk)),
            },
        },
        {
            label = tr("UI_AMS_Endurance_Exertion", "Exertion"),
            paces = {
                pace("UI_AMS_Pace_Run", "Running", use(run)),
                pace("UI_AMS_Pace_Sprint", "Sprinting", use(sprint)),
            },
        },
    }

    local affected = stand < 0.995 or walk < 0.995 or run > 1.005 or sprint > 1.005
    local state, stateTone
    if walk < 0 then
        state, stateTone = tr("UI_AMS_Endurance_DrainsWalking", "Drains even walking"), "bad"
    elseif affected then
        state, stateTone = tr("UI_AMS_Endurance_Taxed", "Taxed"), magnitudeTone(sprint)
    else
        state, stateTone = tr("UI_AMS_Endurance_Unaffected", "Unaffected"), "dim"
    end
    return {
        label = tr("UI_AMS_Row_Endurance", "Endurance"),
        state = state,
        tone = stateTone,
        groups = groups,
    }
end

local HEAT_STATES = {
    [0] = { "UI_AMS_Heat_None", "No heat build-up" },
    { "UI_AMS_Heat_Warm", "Warm" },
    { "UI_AMS_Heat_Hot", "Hot" },
    { "UI_AMS_Heat_Overheating", "Overheating" },
    { "UI_AMS_Heat_Stress", "Heat stress" },
}

local function buildHeat(r, heatPending)
    local heat = tonumber(r.heat) or 0
    local pips = Policy.heatPips(heat)
    local row = {
        label = tr("UI_AMS_Row_Heat", "Heat"),
        pips = pips,
        fill = Policy.fill(heat, Policy.HEAT_BANDS),
        color = "heat",
    }
    if heatPending then
        row.state, row.tone, row.fill = tr("UI_AMS_WaitingSnapshot", "Waiting for server..."), "dim", 0
    elseif pips > 0 then
        row.state, row.tone = stateText(HEAT_STATES, pips), tone(pips, "heat")
        local rest = tonumber(r.restRegenScale) or 1
        if rest < 0.995 then
            row.detail = tr("UI_AMS_Heat_Trapping", "Trapping heat: recovery %1 even at rest. Slow down or shed layers.", pct(rest))
        else
            row.detail = tr("UI_AMS_Heat_Building", "Trapping heat. Slow down or shed layers.")
        end
    elseif (tonumber(r.coldSuitability) or 0) >= 0.25 then
        row.state, row.tone = tr("UI_AMS_Heat_KeepingWarm", "Keeping you warm"), "good"
        row.detail = tr("UI_AMS_Heat_Insulating", "Your layers are holding in heat against the cold.")
    else
        row.state, row.tone = stateText(HEAT_STATES, 0), "dim"
        if (tonumber(r.thermalResistance) or 0) >= 0.5 then
            row.detail = tr("UI_AMS_Heat_WellInsulated", "Well insulated: traps heat in warm weather.")
        end
    end
    return row
end

local BREATHING_STATES = {
    [0] = { "UI_AMS_Breathing_Clear", "Clear" },
    { "UI_AMS_Breathing_Slight", "Slightly restricted" },
    { "UI_AMS_Breathing_Restricted", "Restricted" },
    { "UI_AMS_Breathing_Heavy", "Heavily restricted" },
    { "UI_AMS_Breathing_Sealed", "Sealed" },
}

local function buildBreathing(r)
    local severity = tonumber(r.breathingSeverity) or 0
    local pips = Policy.breathingPips(severity)
    return {
        label = tr("UI_AMS_Label_Breathing", "Breathing"),
        pips = pips,
        fill = Policy.fill(severity, Policy.BREATHING_BANDS),
        state = stateText(BREATHING_STATES, pips),
        tone = tone(pips, "breathing"),
        color = "breathing",
        detail = pips > 0 and tr("UI_AMS_Breathing_Detail", "Hard work costs extra endurance. Walking and resting are free.") or nil,
    }
end

local MELEE_STATES = {
    [0] = { "UI_AMS_Melee_Free", "Free" },
    { "UI_AMS_Melee_Light", "Light" },
    { "UI_AMS_Melee_Noticeable", "Noticeable" },
    { "UI_AMS_Melee_Heavy", "Heavy" },
    { "UI_AMS_Melee_VeryHeavy", "Very heavy" },
}

local function swingSlowdown(rows)
    local total = 0
    for _, row in ipairs(rows) do
        if row.included then
            total = total + (1 - SpeedRebalance.combatSpeedModifier(row.bodyLocation, row.burdenKg))
        end
    end
    return total
end

local function buildMelee(r, rows, options)
    local armKg = tonumber(r.armKg) or 0
    local pips = Policy.armPips(armKg)
    local slow = swingSlowdown(rows)
    local strain = Strain.computeArmorStrainExtra(options, { armKg = armKg })
    local detail
    if slow >= 0.005 and strain > 0 then
        detail = tr("UI_AMS_Melee_SlowStrain", "Swings %1 slower and your arms tire faster.", string.format("%.0f%%", slow * 100))
    elseif slow >= 0.005 then
        detail = tr("UI_AMS_Melee_Slow", "Swings %1 slower.", string.format("%.0f%%", slow * 100))
    elseif strain > 0 then
        detail = tr("UI_AMS_Melee_Strain", "Your arms tire faster when swinging.")
    end
    return {
        label = tr("UI_AMS_Row_Melee", "Melee"),
        pips = pips,
        fill = Policy.fill(armKg, Policy.ARM_BANDS_KG),
        state = stateText(MELEE_STATES, pips),
        tone = tone(pips, "swing"),
        color = "swing",
        detail = detail,
    }
end

local SLEEP_STATES = {
    [0] = { "UI_AMS_Sleep_Undisturbed", "Undisturbed" },
    { "UI_AMS_Sleep_Slight", "Slightly restless" },
    { "UI_AMS_Sleep_Restless", "Restless" },
    { "UI_AMS_Sleep_Poor", "Poor" },
    { "UI_AMS_Sleep_VeryPoor", "Very poor" },
}

local function buildSleep(r)
    local fraction = tonumber(r.sleepPenaltyFraction) or 0
    local pips = Policy.sleepPips(fraction)
    return {
        label = tr("UI_AMS_Row_Sleep", "Sleep"),
        pips = pips,
        fill = Policy.fill(fraction, Policy.SLEEP_BANDS),
        state = stateText(SLEEP_STATES, pips),
        tone = tone(pips, "sleep"),
        color = "sleep",
        detail = pips > 0 and tr("UI_AMS_Sleep_Detail", "Recovery %1. Take stiff gear off for bed.",
            pct(1 - fraction)) or nil,
    }
end

-- -----------------------------------------------------------------------------
-- Gear, tip and verdict
-- -----------------------------------------------------------------------------

-- What each gear row feeds, with the amount shown on the body map when that
-- channel row is hovered.
local function channelShares(row, burden)
    local out = {}
    if LoadModel.isSwingChainLocation(row.bodyLocation) then
        out.melee = burden
    end
    if (tonumber(row.rigidKg) or 0) > 0 then
        out.sleep = tonumber(row.rigidKg)
    end
    if (tonumber(row.airflow) or 0) > 0 or (tonumber(row.sealedRestriction) or 0) > 0 then
        out.breathing = math.max(burden, 1.0)
    end
    return out
end

-- Identical pieces (left and right shin guards) share one row.
local function buildGear(rows, covered)
    local items, parts, byKey = {}, {}, {}
    local channelParts = { load = parts, melee = {}, sleep = {}, breathing = {} }
    local lighterCount, lighterKg, totalCount = 0, 0, 0
    for _, row in ipairs(rows) do
        local burden = tonumber(row.burdenKg) or 0
        if row.included and burden > 0 then
            totalCount = totalCount + 1
            local itemParts = View.itemParts(row, covered and covered(row) or nil)
            spread(parts, itemParts, burden)
            local shares = channelShares(row, burden)
            for channel, amount in pairs(shares) do
                spread(channelParts[channel], itemParts, amount)
            end
            -- Left and right pieces are separate item types with one display name.
            local key = tostring(row.displayName or row.fullType) .. "|" .. string.format("%.2f", burden)
            local group = byKey[key]
            if group then
                group.count = group.count + 1
                group.kg = group.kg + burden
                spread(group.parts, itemParts, burden)
            elseif burden >= LoadModel.COST_DRIVER_THRESHOLD_KG and #items < View.MAX_ITEMS then
                group = {
                    label = tostring(row.displayName or row.fullType or ""),
                    count = 1,
                    unitKg = burden,
                    kg = burden,
                    channels = shares,
                    parts = {},
                    row = row,
                }
                spread(group.parts, itemParts, burden)
                byKey[key] = group
                items[#items + 1] = group
            else
                lighterCount = lighterCount + 1
                lighterKg = lighterKg + burden
            end
        end
    end
    for _, item in ipairs(items) do
        item.countText = item.count > 1 and ("x" .. item.count) or nil
        item.value = kg(item.kg) .. " kg"
        item.fill = Policy.fill(item.unitKg, Policy.ITEM_BANDS_KG)
        item.tone = tone(Policy.itemPips(item.unitKg), "burden")
    end
    table.sort(items, function(a, b) return a.kg > b.kg end)
    local summary
    if #items == 0 then
        summary = totalCount > 0 and tr("UI_AMS_Gear_AllLight", "Nothing you wear is heavy enough to stand out.") or nil
    elseif lighterCount == 1 then
        summary = tr("UI_AMS_Gear_LighterOne", "+ 1 lighter item, %1 kg", kg(lighterKg))
    elseif lighterCount > 1 then
        summary = tr("UI_AMS_Gear_Lighter", "+ %1 lighter items, %2 kg together", tostring(lighterCount), kg(lighterKg))
    end
    return items, parts, summary, channelParts
end

local function buildTip(r, options, items, loadPips)
    if loadPips < 2 then
        return nil
    end
    local carrier = { bodyKg = tonumber(r.bodyKg) or 80, strength = tonumber(r.strength) or 5 }
    local burden = tonumber(r.burdenKg) or 0
    local best, bestPips = nil, loadPips
    for _, item in ipairs(items) do
        local after = Policy.loadPips(LoadModel.loadFraction(options, burden - item.unitKg, carrier))
        if after < bestPips then
            best, bestPips = item, after
        end
    end
    if not best then
        return nil
    end
    return tr("UI_AMS_Tip_Remove", "Without the %1: %2 load.", best.label, string.lower(View.tierText(bestPips)))
end

local function buildVerdict(v, r)
    local load, heat = v.load.pips, v.channels.heat and v.channels.heat.pips or 0
    local breathing = v.channels.breathing and v.channels.breathing.pips or 0
    local sleep = v.channels.sleep and v.channels.sleep.pips or 0
    if (tonumber(r.walkRegenScale) or 1) < 0 then
        return tr("UI_AMS_Verdict_DrainsWalking", "Too heavy to recover endurance even at a walk."), "bad"
    end
    if heat >= 3 then
        return tr("UI_AMS_Verdict_Overheating", "You are overheating in this gear."), "bad"
    end
    if load >= 4 then
        return tr("UI_AMS_Verdict_Extreme", "Extreme load. Every run costs you dearly."), "bad"
    end
    if load >= 3 then
        return tr("UI_AMS_Verdict_Heavy", "Heavy load. Expect to stop and catch your breath."), "warn"
    end
    if breathing >= 3 then
        return tr("UI_AMS_Verdict_Breathing", "Your mask makes hard work exhausting."), "warn"
    end
    if heat >= 1 then
        return tr("UI_AMS_Verdict_Warm", "Your gear is holding in heat."), "warn"
    end
    if load >= 2 then
        return tr("UI_AMS_Verdict_Moderate", "Noticeable load. You tire faster on the move and in fights."), "text"
    end
    if load >= 1 then
        return tr("UI_AMS_Verdict_Light", "Light load. You will barely notice it."), "text"
    end
    if sleep >= 2 then
        return tr("UI_AMS_Verdict_Sleep", "Easy to move in, but not to sleep in."), "text"
    end
    if v.channels.heat and v.channels.heat.tone == "good" then
        return tr("UI_AMS_Verdict_Warm_Good", "Your clothes are keeping you warm."), "good"
    end
    return tr("UI_AMS_Verdict_Free", "Your gear costs you nothing extra."), "good"
end

-- input: runtime, analysis, options, heatPending, covered(row) -> part indices
function View.build(input)
    local r = input.runtime or {}
    local options = input.options or {}
    local rows = input.analysis and input.analysis.rows or {}

    local v = { channels = {} }
    v.load = buildLoad(r, options)
    v.endurance = buildEndurance(r)

    local order = {}
    if options.EnableThermalModel ~= false then
        v.channels.heat = buildHeat(r, input.heatPending)
        order[#order + 1] = v.channels.heat
    end
    if options.EnableBreathingModel ~= false then
        v.channels.breathing = buildBreathing(r)
        order[#order + 1] = v.channels.breathing
    end
    v.channels.melee = buildMelee(r, rows, options)
    order[#order + 1] = v.channels.melee
    if options.EnableSleepPenaltyModel ~= false then
        v.channels.sleep = buildSleep(r)
        order[#order + 1] = v.channels.sleep
    end
    v.channelOrder = order

    v.items, v.parts, v.gearSummary, v.channelParts = buildGear(rows, input.covered)
    v.load.key = "load"
    v.endurance.key = "endurance"
    for key, channel in pairs(v.channels) do
        channel.key = key
    end
    v.tip = buildTip(r, options, v.items, v.load.pips)
    v.verdict, v.verdictTone = buildVerdict(v, r)
    return v
end

-- Plain-language explanations behind each row's "?" marker. One line per
-- "\n": the first is the summary, "# " starts a heading, "- " a point, and
-- any other line is a closing note. Percent figures are arguments: a
-- literal percent in a Java format string needs escaping.
local INFO = {
    load = { "UI_AMS_Info_Load", "How heavy your worn gear is for your body.\n- Each item counts its weight.\n- Legs, feet and arms count up to twice as much: you lift them with every step and swing.\n- Stiff or bulky gear adds extra.\n- The first 3.5 kg, about a set of everyday clothes, is free.\n- A heavier or stronger character carries the same kit more easily.\nEvery other row grows with Load." },
    endurance = { "UI_AMS_Info_Endurance", "What your gear does to endurance, compared with wearing nothing.\n# Recovery\n- Sitting: always normal.\n- Standing: a little slower.\n- Walking: much slower. Very heavy loads drain even at a walk.\n# Exertion\n- Running, sprinting and fighting drain faster the heavier you are.\nValues preview each pace with your current gear, heat and breathing." },
    heat = { "UI_AMS_Info_Heat", "Insulating gear traps body heat.\n- It only counts once you are actually running hot.\n- Then recovery slows by up to half, even sitting down.\n- Exertion costs more too.\n- Cool off or shed a layer and it fades within minutes.\nIn the cold the same gear just keeps you warm, with no penalty." },
    breathing = { "UI_AMS_Info_Breathing", "Masks, respirators and sealed suits restrict airflow.\n- Resting and walking are free.\n- The harder you work, the more extra endurance it costs.\n- The full rating applies at a sprint.\nA filtered gas mask is the worst. Take it off when the air is clean." },
    melee = { "UI_AMS_Info_Melee", "Gear on your shoulders, arms and hands moves with every attack.\n- Swings are %1 slower per kilo, up to %2.\n- Heavy arm gear makes your arms stiffen faster in a long fight.\n- Chest and leg armor do not slow your swing, but a heavy Load makes fighting cost more endurance.", "1%", "5%" },
    sleep = { "UI_AMS_Info_Sleep", "Stiff gear makes sleep clear fatigue more slowly.\n- About %1 slower per kilo, up to half.\n- Torso armor counts fully, limb armor partly, headgear not at all.\n- Soft clothes are fine.\nTake Off Armor before bed, Wear Armor when you wake up.", "2.5%" },
    gear = { "UI_AMS_Info_Gear", "The worn items that add the most load, heaviest first.\n- Cells rate a single piece.\n- Hover a row to see where it sits on your body.\n- When one piece makes the difference, the line below says what taking it off would change." },
}

-- Lines of { kind = "summary" | "heading" | "point" | "note", text }.
-- Translations may carry real newlines or a literal backslash-n.
function View.info(key)
    local entry = INFO[key]
    if not entry then
        return nil
    end
    local text
    if entry[4] then
        text = tr(entry[1], entry[2], entry[3], entry[4])
    elseif entry[3] then
        text = tr(entry[1], entry[2], entry[3])
    else
        text = tr(entry[1], entry[2])
    end
    text = string.gsub(text, "\\n", "\n")
    local lines = {}
    for raw in string.gmatch(text .. "\n", "([^\n]*)\n") do
        local line = string.match(raw, "^%s*(.-)%s*$")
        if line ~= "" then
            local kind, rest = "note", line
            if #lines == 0 then
                kind = "summary"
            elseif string.sub(line, 1, 2) == "# " then
                kind, rest = "heading", string.sub(line, 3)
            elseif string.sub(line, 1, 2) == "- " then
                kind, rest = "point", string.sub(line, 3)
            end
            lines[#lines + 1] = { kind = kind, text = rest }
        end
    end
    return lines
end

return View
