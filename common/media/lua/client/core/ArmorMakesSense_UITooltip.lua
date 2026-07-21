ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Core = ArmorMakesSense.Core or {}

local Core = ArmorMakesSense.Core
Core.UITooltip = Core.UITooltip or {}

local ClientRuntime = require "core/ArmorMakesSense_ClientRuntime"
local LoadModel = require "ArmorMakesSense_LoadModelShared"
local Utils = require "ArmorMakesSense_UtilsShared"

local UITooltip = Core.UITooltip

local hookInstalled = false
local renderPatched = false
local originalISToolTipInvRender = nil

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
    local value = tonumber(resistance) or 0
    if value < 0.80 then
        return nil
    end
    if (tonumber(sealedRestriction) or 0) > 0 then
        return tr("UI_AMS_Label_BreathingHeavyRestricted", "Heavily Restricted")
    end
    if value < 2.00 then
        return tr("UI_AMS_Label_BreathingMild", "Mild")
    end
    return tr("UI_AMS_Label_BreathingRestricted", "Restricted")
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

local function isShoulderpadFamilyItem(item, location)
    local loc = Utils.lower(location or getBodyLocation(item))
    if string.find(loc, "shoulderpad", 1, true) then
        return true
    end
    local fullType = tostring(ClientRuntime.safeMethod(item, "getFullType") or "")
    return string.find(Utils.lower(fullType), "shoulderpad", 1, true) ~= nil
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

local function getTooltipPadding(tooltip)
    local padLeft = tonumber(tooltip and tooltip.padLeft)
    local padRight = tonumber(tooltip and tooltip.padRight)
    local padTop = tonumber(tooltip and tooltip.padTop)
    local padBottom = tonumber(tooltip and tooltip.padBottom)
    if padLeft and padRight and padTop and padBottom then
        return padLeft, padRight, padTop, padBottom
    end

    local font = tooltip and ClientRuntime.safeMethod(tooltip, "getFont") or nil
    local tm = _G.TextManager and _G.TextManager.instance or nil
    local charWidth = tonumber(tm and font and ClientRuntime.safeMethod(tm, "MeasureStringX", font, "1")) or 5
    if charWidth < 1 then
        charWidth = 5
    end
    charWidth = charWidth + 2
    local verticalPad = math.floor(charWidth / 2)
    if verticalPad < 1 then
        verticalPad = 2
    end
    return charWidth + 1, charWidth, verticalPad, verticalPad
end

local function injectTooltipRowsWithLayout(layout, item)
    if not layout or not item or not isTooltipWearable(item) then
        return
    end
    local signal = LoadModel.itemToBurdenSignal(item, getBodyLocation(item))
    if not signal then
        return
    end
    local hasPhysical = (tonumber(signal.physicalLoad) or 0) >= TOOLTIP_DISPLAY_THRESHOLD
    local hasBreathing = (tonumber(signal.airflowResistance) or 0) >= 0.80
    if not hasPhysical and not hasBreathing then
        return
    end

    if hasPhysical then
        addLayoutRow(layout, {
            label = stripAmsPrefix(tr("UI_AMS_Label_Burden", "Burden")) .. ":",
            labelColor = TT_LABEL_ACCENT,
            progress = burdenBarFraction(signal.physicalLoad),
            barColor = TT_BAR_BURDEN,
        })
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
    end
end

local function renderTooltipLayoutForItem(item, tooltip)
    if not item or not tooltip then
        return false
    end

    local layout = ClientRuntime.safeMethod(tooltip, "beginLayout")
    if not layout then
        return false
    end

    local ok = pcall(function()
        ClientRuntime.safeMethod(layout, "setMinLabelWidth", 80)
        ClientRuntime.safeMethod(layout, "setMinValueWidth", 80)
        item:DoTooltipEmbedded(tooltip, layout, 0)
        injectTooltipRowsWithLayout(layout, item)

        local padLeft, padRight, padTop, padBottom = getTooltipPadding(tooltip)
        local lineSpacing = tonumber(ClientRuntime.safeMethod(tooltip, "getLineSpacing")) or 14
        local top = padTop + lineSpacing + 5
        local height = tonumber(ClientRuntime.safeMethod(layout, "render", padLeft, top, tooltip)) or top
        ClientRuntime.safeMethod(tooltip, "endLayout", layout)

        local width = tonumber(ClientRuntime.safeMethod(tooltip, "getWidth")) or 0
        if width < 150 then
            width = 150
        end

        if instanceof(item, "InventoryContainer") then
            if width < 160 then
                width = 160
            end
            local container = ClientRuntime.safeMethod(item, "getItemContainer")
            local items = container and ClientRuntime.safeMethod(container, "getItems")
            local maxX = width - padRight
            if items and not ClientRuntime.safeMethod(items, "isEmpty") then
                local seenItems = {}
                local xOffset = padLeft
                height = height + 4
                local itemCount = tonumber(ClientRuntime.safeMethod(items, "size")) or 0
                for i = itemCount - 1, 0, -1 do
                    local containerItem = ClientRuntime.safeMethod(items, "get", i)
                    local name = containerItem and tostring(ClientRuntime.safeMethod(containerItem, "getName") or "")
                    if not seenItems[name] then
                        seenItems[name] = true
                        local tex = containerItem and ClientRuntime.safeMethod(containerItem, "getTex")
                        if tex then
                            ClientRuntime.safeMethod(tooltip, "DrawTextureScaledAspect", tex, xOffset, height, 16, 16, 1, 1, 1, 1)
                        end
                        xOffset = xOffset + 17
                        if xOffset + 16 > maxX then
                            break
                        end
                    end
                end
                height = height + 16
            end
        end

        ClientRuntime.safeMethod(tooltip, "setHeight", math.floor(height + padBottom))
        ClientRuntime.safeMethod(tooltip, "setWidth", math.floor(width))
    end)

    if not ok then
        pcall(function()
            ClientRuntime.safeMethod(tooltip, "endLayout", layout)
        end)
        return false
    end

    return true
end

local function installRenderPatch()
    if renderPatched then
        return true
    end
    if not ISToolTipInv or type(ISToolTipInv.render) ~= "function" then
        return false
    end

    originalISToolTipInvRender = originalISToolTipInvRender or ISToolTipInv.render
    ISToolTipInv.render = function(self)
        local item = self and self.item
        if not item or instanceof(item, "FluidContainer") or not isTooltipWearable(item) then
            return originalISToolTipInvRender(self)
        end

        local itemMt = nil
        local mtOk, mtValue = pcall(getmetatable, item)
        if mtOk and type(mtValue) == "table" then
            itemMt = mtValue
        end
        local itemIndex = itemMt and type(itemMt.__index) == "table" and itemMt.__index or nil
        local originalDoTooltip = itemIndex and itemIndex.DoTooltip or nil
        if type(originalDoTooltip) ~= "function" then
            return originalISToolTipInvRender(self)
        end

        local restoreTooltip = nil
        if isShoulderpadFamilyItem(item) then
            local tooltipKey = tostring(ClientRuntime.safeMethod(item, "getTooltip") or "")
            if tooltipKey ~= "" then
                restoreTooltip = tooltipKey
                pcall(function()
                    item:setTooltip(nil)
                end)
            end
        end

        itemIndex.DoTooltip = function(overriddenItem, tooltip)
            if not renderTooltipLayoutForItem(overriddenItem, tooltip) then
                return originalDoTooltip(overriddenItem, tooltip)
            end
        end

        local ok, result = pcall(originalISToolTipInvRender, self)
        itemIndex.DoTooltip = originalDoTooltip
        if restoreTooltip ~= nil then
            pcall(function()
                item:setTooltip(restoreTooltip)
            end)
        end
        if not ok then
            error(result)
        end
        return result
    end

    renderPatched = true
    ClientRuntime.logOnce("ui_tooltip_patch_installed", "[UI] AMS tooltip rows registered via pre-render ISToolTipInv patch.")
    return true
end

function UITooltip.install()
    if hookInstalled then
        return
    end
    if not installRenderPatch() then
        ClientRuntime.logOnce("ui_tooltip_patch_deferred", "[UI] ISToolTipInv not ready; AMS tooltip installation deferred.")
        return
    end
    hookInstalled = true
end

return UITooltip
