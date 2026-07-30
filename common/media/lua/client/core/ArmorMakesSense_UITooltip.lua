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
local TOOLTIP_MIN_LABEL_WIDTH = 80
local TOOLTIP_VALUE_WIDTH = 80
local TT_LABEL_DEFAULT = { 1.0, 1.0, 0.8, 1.0 }
local TT_LABEL_ACCENT = { 1.0, 0.85, 0.55, 1.0 }
local TT_VALUE_DEFAULT = { 1.0, 1.0, 1.0, 1.0 }
local TT_VALUE_BREATHING = { 1.0, 0.80, 0.40, 1.0 }
local TT_VALUE_BREATHING_HEAVY = { 1.0, 0.45, 0.35, 1.0 }
local TT_BAR_BURDEN = { 0.95, 0.70, 0.25, 1.0 }
local javaFieldCache = {}

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

local function reflectedFieldValue(target, scope, fieldName)
    if not target
        or type(getNumClassFields) ~= "function"
        or type(getClassField) ~= "function"
        or type(getClassFieldVal) ~= "function"
    then
        return nil
    end

    local key = tostring(scope) .. ":" .. tostring(fieldName)
    local field = javaFieldCache[key]
    if field == false then
        return nil
    end
    if field == nil then
        local count = tonumber(getNumClassFields(target)) or 0
        for index = 0, count - 1 do
            local candidate = getClassField(target, index)
            if candidate and tostring(ClientRuntime.safeMethod(candidate, "getName") or "") == fieldName then
                field = candidate
                javaFieldCache[key] = candidate
                break
            end
        end
        if field == nil then
            javaFieldCache[key] = false
            return nil
        end
    end
    local ok, value = pcall(getClassFieldVal, target, field)
    return ok and value or nil
end

local function numericJavaField(target, scope, fieldName, fallback)
    local reflected = tonumber(reflectedFieldValue(target, scope, fieldName))
    if reflected ~= nil then
        return reflected
    end
    local direct = target and tonumber(target[fieldName]) or nil
    return direct ~= nil and direct or fallback
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

local function isShoulderpadFamilyItem(item)
    local location = Utils.lower(getBodyLocation(item))
    if string.find(location, "shoulderpad", 1, true) then
        return true
    end
    local fullType = Utils.lower(tostring(ClientRuntime.safeMethod(item, "getFullType") or ""))
    return string.find(fullType, "shoulderpad", 1, true) ~= nil
end

local function buildTooltipRows(item)
    if not item or not isTooltipWearable(item) then
        return nil
    end
    local signal = LoadModel.itemToBurdenSignal(item, getBodyLocation(item))
    if not signal then
        return nil
    end
    local hasPhysical = (tonumber(signal.physicalLoad) or 0) >= TOOLTIP_DISPLAY_THRESHOLD
    local hasBreathing = PresentationPolicy.breathingTier(
        signal.airflowResistance,
        signal.sealedRestriction
    ) ~= nil
    if not hasPhysical and not hasBreathing then
        return nil
    end

    local rows = {}
    if hasPhysical then
        rows[#rows + 1] = {
            label = stripAmsPrefix(tr("UI_AMS_Label_Burden", "Burden")) .. ":",
            labelColor = TT_LABEL_ACCENT,
            progress = burdenBarFraction(signal.physicalLoad),
            barColor = TT_BAR_BURDEN,
        }
    end

    local breathingTier = breathingTierFromResistance(signal.airflowResistance, signal.sealedRestriction)
    if breathingTier then
        rows[#rows + 1] = {
            label = stripAmsPrefix(tr("UI_AMS_Label_Breathing", "Breathing")) .. ":",
            labelColor = TT_LABEL_ACCENT,
            value = breathingTier,
            valueColor = (tonumber(signal.sealedRestriction) or 0) > 0
                and TT_VALUE_BREATHING_HEAVY or TT_VALUE_BREATHING,
        }
    end
    return rows
end

local function buildProviderRows(item)
    local sourceRows = buildTooltipRows(item)
    local rows = {}
    for _, source in ipairs(sourceRows or {}) do
        rows[#rows + 1] = {
            label = source.label,
            value = source.progress ~= nil
                and string.format("%.0f%%", clamp01(source.progress) * 100)
                or tostring(source.value or ""),
            labelR = source.labelColor and source.labelColor[1] or nil,
            labelG = source.labelColor and source.labelColor[2] or nil,
            labelB = source.labelColor and source.labelColor[3] or nil,
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

local function addRowsToLayout(layout, item)
    local rows = buildTooltipRows(item)
    if not rows then
        return 0
    end

    for _, row in ipairs(rows) do
        local layoutItem = ClientRuntime.safeMethod(layout, "addItem")
        if not layoutItem then
            return 0
        end
        local labelColor = row.labelColor or TT_LABEL_DEFAULT
        ClientRuntime.safeMethod(
            layoutItem,
            "setLabel",
            row.label or "",
            labelColor[1],
            labelColor[2],
            labelColor[3],
            labelColor[4]
        )

        if row.progress ~= nil then
            local barColor = row.barColor or TT_BAR_BURDEN
            ClientRuntime.safeMethod(
                layoutItem,
                "setProgress",
                clamp01(row.progress),
                barColor[1],
                barColor[2],
                barColor[3],
                barColor[4]
            )
        elseif row.value ~= nil then
            local valueColor = row.valueColor or TT_VALUE_DEFAULT
            ClientRuntime.safeMethod(
                layoutItem,
                "setValue",
                tostring(row.value),
                valueColor[1],
                valueColor[2],
                valueColor[3],
                valueColor[4]
            )
        end
    end
    return #rows
end

local function renderCombinedTooltip(tooltip, item)
    local layout = ClientRuntime.safeMethod(tooltip, "beginLayout")
    if not layout then
        return false
    end

    ClientRuntime.safeMethod(layout, "setMinLabelWidth", TOOLTIP_MIN_LABEL_WIDTH)
    ClientRuntime.safeMethod(layout, "setMinValueWidth", TOOLTIP_VALUE_WIDTH)

    local embedded = item and item.DoTooltipEmbedded
    if type(embedded) ~= "function" then
        ClientRuntime.safeMethod(tooltip, "endLayout", layout)
        error("42.20 tooltip contract missing InventoryItem.DoTooltipEmbedded")
    end
    local ok, failure = pcall(embedded, item, tooltip, layout, 0)
    if not ok then
        ClientRuntime.safeMethod(tooltip, "endLayout", layout)
        error(failure)
    end

    addRowsToLayout(layout, item)
    local y = numericJavaField(layout, "ObjectTooltip.Layout", "offsetY", 0)
    local padLeft = numericJavaField(tooltip, "ObjectTooltip", "padLeft", 5)
    local padBottom = numericJavaField(tooltip, "ObjectTooltip", "padBottom", 5)
    local height = tonumber(ClientRuntime.safeMethod(layout, "render", padLeft, y, tooltip)) or y
    ClientRuntime.safeMethod(tooltip, "endLayout", layout)
    ClientRuntime.safeMethod(tooltip, "setHeight", math.floor(height + padBottom))

    local width = tonumber(ClientRuntime.safeMethod(tooltip, "getWidth")) or 0
    if width < 150 then
        ClientRuntime.safeMethod(tooltip, "setWidth", 150)
    end
    return true
end

local function renderWithItemExtension(panel, originalRender)
    local item = panel and panel.item
    if not item then
        return originalRender(panel)
    end

    local tooltipKey = tostring(ClientRuntime.safeMethod(item, "getTooltip") or "")
    local suppressNoBackpack = isShoulderpadFamilyItem(item)
        and (tooltipKey == "Tooltip_item_NoBackpack" or tooltipKey == "")
        and type(item.setTooltip) == "function"
    if suppressNoBackpack then
        pcall(item.setTooltip, item, nil)
    end

    local tooltip = panel.tooltip
    local extendRows = tooltip
        and isTooltipWearable(item)
        and not Utils.toBoolean(ClientRuntime.safeMethod(item, "IsInventoryContainer"))
        and not providerOwnsRows()
    local okMetatable, metatable = pcall(getmetatable, item)
    local methods = okMetatable and type(metatable) == "table" and metatable.__index or nil
    local originalDoTooltip = type(methods) == "table" and methods.DoTooltip or nil
    if extendRows and type(originalDoTooltip) == "function" then
        methods.DoTooltip = function(target, targetTooltip, ...)
            if target == item and targetTooltip == tooltip then
                return renderCombinedTooltip(targetTooltip, target)
            end
            return originalDoTooltip(target, targetTooltip, ...)
        end
    end

    local ok, result = pcall(originalRender, panel)
    if extendRows and type(originalDoTooltip) == "function" and methods.DoTooltip ~= originalDoTooltip then
        methods.DoTooltip = originalDoTooltip
    end
    if suppressNoBackpack then
        pcall(item.setTooltip, item, tooltipKey)
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
        if nested then
            return originalRender(self)
        end
        self._amsTooltipRenderActive = true
        local ok, result = pcall(renderWithItemExtension, self, originalRender)
        self._amsTooltipRenderActive = nil
        if not ok then
            error(result)
        end
        return result
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
