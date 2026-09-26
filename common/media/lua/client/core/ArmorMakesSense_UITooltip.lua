ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Core = ArmorMakesSense.Core or {}

local Core = ArmorMakesSense.Core
Core.UITooltip = Core.UITooltip or {}

local BreathingModel = require "ArmorMakesSense_BreathingModel"
local ClientRuntime = require "core/ArmorMakesSense_ClientRuntime"
local Draw = require "core/ArmorMakesSense_Draw"
local LoadModel = require "ArmorMakesSense_LoadModelShared"
local Options = require "ArmorMakesSense_Options"
local Policy = require "ArmorMakesSense_PresentationPolicy"
local Utils = require "ArmorMakesSense_UtilsShared"

local UITooltip = Core.UITooltip
local safeCall = ClientRuntime.safeMethod

local TOOLTIP_MIN_LABEL_WIDTH = 80
local TOOLTIP_MIN_VALUE_WIDTH = 80
local TOOLTIP_MIN_WIDTH = 150
local TOOLTIP_TITLE_GAP = 5
local PIP_BLOCK_GAP = 3

-- Labels vanilla clothing tooltips can emit; the pip column clears all of them
-- so AMS pips line up with vanilla values.
local VANILLA_LABEL_KEYS = {
    "Tooltip_item_Weight", "Tooltip_item_Insulation", "Tooltip_item_Windresist",
    "Tooltip_item_Waterresist", "Tooltip_BiteDefense", "Tooltip_ScratchDefense",
    "Tooltip_BulletDefense", "Tooltip_CombatSpeedModifier", "Tooltip_RunSpeedModifier",
    "Tooltip_weapon_Condition",
}

local function tr(key, fallback)
    if not getText then
        return fallback
    end
    local value = getText(key)
    if not value or value == key then
        return fallback
    end
    return value
end

local function bodyLocation(item)
    local location = tostring(safeCall(item, "getBodyLocation") or "")
    if location ~= "" then
        return location
    end
    return tostring(safeCall(safeCall(item, "getScriptItem"), "getBodyLocation") or "")
end

local function isShoulderpad(item)
    return string.find(Utils.lower(bodyLocation(item)), "shoulderpad", 1, true) ~= nil
        or string.find(Utils.lower(safeCall(item, "getFullType")), "shoulderpad", 1, true) ~= nil
end

function UITooltip.buildRows(item)
    if not item or bodyLocation(item) == "" or Utils.toBoolean(safeCall(item, "IsInventoryContainer")) then
        return {}
    end
    local options = Options.get()
    local signal = LoadModel.itemToBurdenSignal(item, bodyLocation(item), options)
    if not signal then
        return {}
    end
    local rows = {}
    local burdenPips = Policy.itemPips(signal.burdenKg)
    if burdenPips > 0 then
        rows[#rows + 1] = {
            label = tr("UI_AMS_Label_Burden", "Burden"),
            pips = burdenPips,
            color = Draw.C.burden,
        }
    end
    if Utils.toBoolean(options.EnableBreathingModel) then
        local breathingPips = Policy.breathingPips(
            BreathingModel.severity(signal.airflowResistance, signal.sealedRestriction)
        )
        if breathingPips > 0 then
            rows[#rows + 1] = {
                label = tr("UI_AMS_Label_Breathing", "Breathing"),
                pips = breathingPips,
                color = Draw.C.breathing,
            }
        end
    end
    return rows
end

local function tooltipLayoutGeometry(tooltip)
    local lineSpacing = tonumber(safeCall(tooltip, "getLineSpacing")) or 14
    local digitWidth = math.max(1, Draw.textWidth(safeCall(tooltip, "getFont"), "0"))
    local horizontalPad = math.floor(digitWidth)
    local verticalPad = math.floor(digitWidth / 2)
    return horizontalPad, verticalPad + lineSpacing + TOOLTIP_TITLE_GAP, verticalPad
end

local function labelColumnWidth(font, rows)
    local width = TOOLTIP_MIN_LABEL_WIDTH
    for _, key in ipairs(VANILLA_LABEL_KEYS) do
        local text = getText and getText(key) or nil
        if text and text ~= key then
            width = math.max(width, Draw.textWidth(font, text .. ":"))
        end
    end
    for _, row in ipairs(rows) do
        width = math.max(width, Draw.textWidth(font, row.label .. ":"))
    end
    return width
end

local function renderPipBlock(tooltip, rows, padLeft, top, labelColumn)
    local font = safeCall(tooltip, "getFont")
    local lineSpacing = tonumber(safeCall(tooltip, "getLineSpacing")) or 14
    local measureOnly = safeCall(tooltip, "isMeasureOnly") == true
    local valueX = padLeft + labelColumn + math.max(Draw.textWidth(font, "W"), 8)
    local size, gap = Draw.pipGeometry(lineSpacing)
    local sink = (not measureOnly) and Draw.tooltipSink(tooltip) or nil
    local label = Draw.C.tooltipLabel
    local y = top + PIP_BLOCK_GAP
    for _, row in ipairs(rows) do
        if sink then
            tooltip:DrawText(font, row.label .. ":", padLeft, y, label.r, label.g, label.b, 1)
            Draw.pips(sink, valueX, y + math.floor((lineSpacing - size) / 2), Policy.PIP_COUNT, row.pips, size, gap, row.color)
        end
        y = y + lineSpacing
    end
    return y, valueX + Draw.pipStripWidth(Policy.PIP_COUNT, size, gap)
end

local function renderCombinedTooltip(tooltip, item, rows)
    local layout = tooltip:beginLayout()
    local labelColumn = labelColumnWidth(safeCall(tooltip, "getFont"), rows)
    layout:setMinLabelWidth(labelColumn)
    layout:setMinValueWidth(TOOLTIP_MIN_VALUE_WIDTH)
    item:DoTooltipEmbedded(tooltip, layout, 0)
    local padLeft, contentY, padBottom = tooltipLayoutGeometry(tooltip)
    local height = tonumber(layout:render(padLeft, contentY, tooltip)) or contentY
    tooltip:endLayout(layout)
    local right
    height, right = renderPipBlock(tooltip, rows, padLeft, height, labelColumn)
    tooltip:setHeight(math.floor(height + padBottom))
    local needed = math.max(TOOLTIP_MIN_WIDTH, right + padLeft)
    if (tonumber(tooltip:getWidth()) or 0) < needed then
        tooltip:setWidth(needed)
    end
end

UITooltip._renderCombined = renderCombinedTooltip

-- One persistent DoTooltip wrapper per item class. It only takes over while
-- ISToolTipInv.render has published a matching item/tooltip pair.
UITooltip._wrappedMethods = UITooltip._wrappedMethods or {}

local function ensureDoTooltipWrapped(item)
    local ok, metatable = pcall(getmetatable, item)
    local methods = ok and type(metatable) == "table" and metatable.__index or nil
    if type(methods) ~= "table" or UITooltip._wrappedMethods[methods] then
        return
    end
    local original = methods.DoTooltip
    if type(original) ~= "function" then
        return
    end
    UITooltip._wrappedMethods[methods] = original
    methods.DoTooltip = function(target, tooltip, ...)
        local active = UITooltip._active
        if active and active.item == target and active.tooltip == tooltip then
            return UITooltip._renderCombined(tooltip, target, active.rows)
        end
        return original(target, tooltip, ...)
    end
end

local function providerOwnsRows()
    local controller = rawget(_G, "EuryTooltipController")
    return controller ~= nil
        and controller.installed == true
        and UITooltip._registeredController == controller
        and type(controller.providers) == "table"
        and controller.providers.ArmorMakesSense == UITooltip._provider
end

local function registerProvider()
    local controller = rawget(_G, "EuryTooltipController")
    if type(controller) ~= "table" or type(controller.registerProvider) ~= "function" then
        return false
    end
    UITooltip._provider = UITooltip._provider or {
        priority = 90,
        getRows = function(_, ctx)
            local rows = {}
            for _, row in ipairs(UITooltip.buildRows(ctx and ctx.item)) do
                rows[#rows + 1] = {
                    label = row.label,
                    value = string.format("%d/%d", row.pips, Policy.PIP_COUNT),
                    labelR = Draw.C.tooltipLabel.r,
                    labelG = Draw.C.tooltipLabel.g,
                    labelB = Draw.C.tooltipLabel.b,
                }
            end
            return #rows > 0 and rows or nil
        end,
    }
    local ok = pcall(controller.registerProvider, controller, "ArmorMakesSense", UITooltip._provider)
    if ok then
        UITooltip._registeredController = controller
        ClientRuntime.logOnce("ui_tooltip_provider_installed", "[UI] AMS tooltip rows registered with the shared tooltip controller.")
    end
    return ok
end

local function installRenderPatch()
    if not ISToolTipInv or type(ISToolTipInv.render) ~= "function" then
        return false
    end
    -- Install once per class. Re-wrapping whenever another mod sits on top grows the render chain
    -- every UI update (a tooltip stack overflow after ~30 minutes in 2.0.0).
    if ISToolTipInv._amsTooltipRenderWrapper then
        return true
    end
    local originalRender = ISToolTipInv.render
    local wrapper = function(self)
        local item = self and self.item
        -- Vanilla's "no backpack" note is wrong once AMS reslots shoulderpads;
        -- hide it for this render only.
        local hiddenTooltipKey = nil
        if item and isShoulderpad(item) then
            local key = safeCall(item, "getTooltip")
            if key == nil or key == "" or key == "Tooltip_item_NoBackpack" then
                hiddenTooltipKey = key or ""
                safeCall(item, "setTooltip", nil)
            end
        end
        UITooltip._active = nil
        if item and self.tooltip and not providerOwnsRows() then
            local rows = UITooltip.buildRows(item)
            if #rows > 0 then
                ensureDoTooltipWrapped(item)
                UITooltip._active = { item = item, tooltip = self.tooltip, rows = rows }
            end
        end
        local ok, err = pcall(originalRender, self)
        UITooltip._active = nil
        if hiddenTooltipKey ~= nil and hiddenTooltipKey ~= "" then
            safeCall(item, "setTooltip", hiddenTooltipKey)
        end
        if not ok then
            error(err, 0)
        end
    end
    ISToolTipInv._amsTooltipRenderWrapper = wrapper
    ISToolTipInv.render = wrapper
    ClientRuntime.logOnce("ui_tooltip_patch_installed", "[UI] AMS tooltip rows registered around the inventory tooltip owner.")
    return true
end

function UITooltip.install()
    registerProvider()
    if not installRenderPatch() then
        ClientRuntime.logOnce("ui_tooltip_patch_deferred", "[UI] ISToolTipInv not ready; AMS tooltip installation deferred.")
        return false
    end
    return true
end

return UITooltip
