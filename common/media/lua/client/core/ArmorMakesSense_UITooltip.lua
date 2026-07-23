ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Core = ArmorMakesSense.Core or {}

local Core = ArmorMakesSense.Core
Core.UITooltip = Core.UITooltip or {}

local ClientRuntime = require "core/ArmorMakesSense_ClientRuntime"
local LoadModel = require "ArmorMakesSense_LoadModelShared"
local PresentationPolicy = require "ArmorMakesSense_PresentationPolicy"
local Utils = require "ArmorMakesSense_UtilsShared"

local UITooltip = Core.UITooltip

local TOOLTIP_DISPLAY_THRESHOLD = 1.5
local TOOLTIP_BAR_MAX = 28
local TT_LABEL_DEFAULT = { 1.0, 1.0, 0.8, 1.0 }
local TT_LABEL_ACCENT = { 1.0, 0.85, 0.55, 1.0 }
local TT_VALUE_DEFAULT = { 1.0, 1.0, 1.0, 1.0 }
local TT_VALUE_BREATHING = { 1.0, 0.80, 0.40, 1.0 }
local TT_VALUE_BREATHING_HEAVY = { 1.0, 0.45, 0.35, 1.0 }
local TT_BAR_BURDEN = { 0.95, 0.70, 0.25, 1.0 }

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

local function clamp01(value)
    return Utils.clamp(tonumber(value) or 0, 0, 1)
end

local function burdenBarFraction(physicalLoad)
    local value = tonumber(physicalLoad) or 0
    if value <= 0 then
        return 0
    end
    return math.min(1.0, value / TOOLTIP_BAR_MAX)
end

local function breathingTierFromResistance(resistance, sealedRestriction)
    local tier = PresentationPolicy.breathingTier(resistance, sealedRestriction)
    local labels = {
        mild = { "UI_AMS_Label_BreathingMild", "Mild" },
        restricted = { "UI_AMS_Label_BreathingRestricted", "Restricted" },
        heavy = { "UI_AMS_Label_BreathingHeavyRestricted", "Heavily Restricted" },
    }
    local label = tier and labels[tier] or nil
    return label and tr(label[1], label[2]) or nil
end

local function addLayoutRow(layout, payload)
    local row = ClientRuntime.safeMethod(layout, "addItem")
    if not row then
        return nil
    end

    local labelColor = payload.labelColor or TT_LABEL_DEFAULT
    ClientRuntime.safeMethod(row, "setLabel", payload.label or "", labelColor[1], labelColor[2], labelColor[3], labelColor[4])

    if payload.progress ~= nil then
        local barColor = payload.barColor or TT_BAR_BURDEN
        ClientRuntime.safeMethod(row, "setProgress", clamp01(payload.progress), barColor[1], barColor[2], barColor[3], barColor[4])
    end
    if payload.value ~= nil then
        local valueColor = payload.valueColor or TT_VALUE_DEFAULT
        ClientRuntime.safeMethod(row, "setValue", tostring(payload.value), valueColor[1], valueColor[2], valueColor[3], valueColor[4])
    end

    return row
end

local function getBodyLocation(item)
    return tostring(ClientRuntime.safeMethod(item, "getBodyLocation") or "")
end

local function stripAmsPrefix(text)
    return string.gsub(tostring(text or ""), "^%s*AMS%s+", "")
end

local function isTooltipWearable(item)
    if not item then
        return false
    end
    if getBodyLocation(item) ~= "" then
        return true
    end
    local scriptItem = ClientRuntime.safeMethod(item, "getScriptItem")
    return tostring(ClientRuntime.safeMethod(scriptItem, "getBodyLocation") or "") ~= ""
end

local function injectTooltipRowsWithLayout(layout, item)
    if not layout or not item or not isTooltipWearable(item) then
        return 0
    end
    local signal = LoadModel.itemToBurdenSignal(item, getBodyLocation(item))
    if not signal then
        return 0
    end
    local hasPhysical = (tonumber(signal.physicalLoad) or 0) >= TOOLTIP_DISPLAY_THRESHOLD
    local hasBreathing = PresentationPolicy.breathingTier(
        signal.airflowResistance,
        signal.sealedRestriction
    ) ~= nil
    if not hasPhysical and not hasBreathing then
        return 0
    end

    local rowCount = 0
    if hasPhysical then
        addLayoutRow(layout, {
            label = stripAmsPrefix(tr("UI_AMS_Label_Burden", "Burden")) .. ":",
            labelColor = TT_LABEL_ACCENT,
            progress = burdenBarFraction(signal.physicalLoad),
            barColor = TT_BAR_BURDEN,
        })
        rowCount = rowCount + 1
    end

    local breathingTier = breathingTierFromResistance(signal.airflowResistance, signal.sealedRestriction)
    if breathingTier then
        addLayoutRow(layout, {
            label = stripAmsPrefix(tr("UI_AMS_Label_Breathing", "Breathing")) .. ":",
            labelColor = TT_LABEL_ACCENT,
            value = breathingTier,
            valueColor = (tonumber(signal.sealedRestriction) or 0) > 0
                and TT_VALUE_BREATHING_HEAVY or TT_VALUE_BREATHING,
        })
        rowCount = rowCount + 1
    end
    return rowCount
end

local function buildProviderRows(item)
    if not isTooltipWearable(item) then
        return nil
    end
    local signal = LoadModel.itemToBurdenSignal(item, getBodyLocation(item))
    if not signal then
        return nil
    end

    local rows = {}
    if (tonumber(signal.physicalLoad) or 0) >= TOOLTIP_DISPLAY_THRESHOLD then
        rows[#rows + 1] = {
            label = stripAmsPrefix(tr("UI_AMS_Label_Burden", "Burden")) .. ":",
            value = string.format("%.0f%%", burdenBarFraction(signal.physicalLoad) * 100),
            labelR = TT_LABEL_ACCENT[1],
            labelG = TT_LABEL_ACCENT[2],
            labelB = TT_LABEL_ACCENT[3],
        }
    end
    local breathingTier = breathingTierFromResistance(signal.airflowResistance, signal.sealedRestriction)
    if breathingTier then
        rows[#rows + 1] = {
            label = stripAmsPrefix(tr("UI_AMS_Label_Breathing", "Breathing")) .. ":",
            value = breathingTier,
        }
    end
    return #rows > 0 and rows or nil
end

local function registerProvider()
    local controller = rawget(_G, "EuryTooltipController")
    if type(controller) ~= "table" or type(controller.registerProvider) ~= "function" then
        return false
    end

    UITooltip._provider = UITooltip._provider or {
        priority = 90,
        getRows = function(_, ctx)
            return buildProviderRows(ctx and ctx.item)
        end,
    }
    local ok = pcall(controller.registerProvider, controller, "ArmorMakesSense", UITooltip._provider)
    if ok then
        UITooltip._registeredController = controller
        ClientRuntime.logOnce("ui_tooltip_provider_installed", "[UI] AMS tooltip rows registered with the shared tooltip controller.")
    end
    return ok
end

local function providerOwnsRows()
    local controller = rawget(_G, "EuryTooltipController")
    return controller ~= nil
        and controller.installed == true
        and UITooltip._registeredController == controller
        and type(controller.providers) == "table"
        and controller.providers.ArmorMakesSense == UITooltip._provider
end

local function renderWithLayoutExtension(panel, originalRender)
    local item = panel and panel.item
    local tooltip = panel and panel.tooltip
    if not item or not tooltip or not isTooltipWearable(item) then
        return originalRender(panel)
    end

    local okMetatable, metatable = pcall(getmetatable, tooltip)
    local methods = okMetatable and type(metatable) == "table" and metatable.__index or nil
    local originalEndLayout = type(methods) == "table" and methods.endLayout or nil
    if type(originalEndLayout) ~= "function" then
        return originalRender(panel)
    end

    local endLayoutExtension = function(target, layout, ...)
        if target == tooltip then
            injectTooltipRowsWithLayout(layout, item)
        end
        return originalEndLayout(target, layout, ...)
    end
    methods.endLayout = endLayoutExtension
    local ok, result = pcall(originalRender, panel)
    if methods.endLayout == endLayoutExtension then
        methods.endLayout = originalEndLayout
    end
    if not ok then
        error(result)
    end
    return result
end

local function installRenderPatch()
    if not ISToolTipInv or type(ISToolTipInv.render) ~= "function" then
        return false
    end
    if ISToolTipInv.render == ISToolTipInv._amsTooltipRenderWrapper then
        return true
    end

    local originalRender = ISToolTipInv.render
    local wrapper = function(self)
        local nested = self and self._amsTooltipRenderActive == true
        if nested or providerOwnsRows() then
            return originalRender(self)
        end
        self._amsTooltipRenderActive = true
        local ok, result = pcall(renderWithLayoutExtension, self, originalRender)
        self._amsTooltipRenderActive = nil
        if not ok then
            error(result)
        end
        return result
    end

    ISToolTipInv._amsTooltipRenderWrapper = wrapper
    ISToolTipInv.render = wrapper
    ClientRuntime.logOnce("ui_tooltip_patch_installed", "[UI] AMS tooltip rows registered as a compositional layout extension.")
    return true
end

function UITooltip.install()
    registerProvider()
    if providerOwnsRows() then
        return true
    end
    if not installRenderPatch() then
        ClientRuntime.logOnce("ui_tooltip_patch_deferred", "[UI] ISToolTipInv not ready; AMS tooltip installation deferred.")
        return false
    end
    return true
end

return UITooltip
