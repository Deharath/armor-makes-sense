ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Core = ArmorMakesSense.Core or {}

local Core = ArmorMakesSense.Core
Core.UI = Core.UI or {}

local UI = Core.UI
local C = {}

local tooltipHookInstalled = false
local clothingUpdateHookInstalled = false
local tabHookInstalled = false
local tabHookFailed = false
local fallbackWindow = nil
local helpWindow = nil
local pendingUiRefresh = true
local TOOLTIP_DISPLAY_THRESHOLD = 1.5

-- -----------------------------------------------------------------------------
-- Context / setup
-- -----------------------------------------------------------------------------

local function ctx(name)
    return C[name]
end

function UI.setContext(context)
    C = context or {}
end

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
    return (ctx("clamp") and ctx("clamp")(tonumber(value) or 0, 0, 1)) or 0
end

local BURDEN_BAR_MAX = 100
local TOOLTIP_BAR_MAX = 28

local function burdenBarFraction(physicalLoad, maxLoad)
    local v = tonumber(physicalLoad) or 0
    if v <= 0 then return 0 end
    return math.min(1.0, v / (maxLoad or BURDEN_BAR_MAX))
end

local function breathingTierFromLoad(load)
    local value = tonumber(load) or 0
    if value < 1.2 then
        return nil
    end
    if value < 3.45 then
        return tr("UI_AMS_Label_BreathingRestricted", "Restricted")
    end
    return tr("UI_AMS_Label_BreathingHeavyRestricted", "Heavily Restricted")
end

local function burdenTierFromTotal(physicalLoad)
    local value = tonumber(physicalLoad) or 0
    if value < 7 then
        return tr("UI_AMS_Tier_Negligible", "Negligible"), "negligible"
    end
    if value < 20 then
        return tr("UI_AMS_Tier_Light", "Light"), "light"
    end
    if value < 45 then
        return tr("UI_AMS_Tier_Moderate", "Moderate"), "moderate"
    end
    if value < 75 then
        return tr("UI_AMS_Tier_Heavy", "Heavy"), "heavy"
    end
    return tr("UI_AMS_Tier_Extreme", "Extreme"), "extreme"
end

-- -----------------------------------------------------------------------------
-- Tooltip rendering (ISToolTipInv rows)
-- -----------------------------------------------------------------------------

local TT_LABEL_DEFAULT = { 1.0, 1.0, 0.8, 1.0 }
local TT_LABEL_ACCENT = { 1.0, 0.85, 0.55, 1.0 }
local TT_VALUE_DEFAULT = { 1.0, 1.0, 1.0, 1.0 }
local TT_VALUE_BREATHING = { 1.0, 0.80, 0.40, 1.0 }
local TT_VALUE_BREATHING_HEAVY = { 1.0, 0.45, 0.35, 1.0 }
local TT_BAR_BURDEN = { 0.95, 0.70, 0.25, 1.0 }
local TT_SEPARATOR = { 0.60, 0.60, 0.60, 1.0 }

local function addLayoutRow(layout, payload)
    local row = ctx("safeMethod")(layout, "addItem")
    if not row then
        return nil
    end

    local labelColor = payload.labelColor or TT_LABEL_DEFAULT
    ctx("safeMethod")(row, "setLabel", payload.label or "", labelColor[1], labelColor[2], labelColor[3], labelColor[4])

    if payload.progress ~= nil then
        local barColor = payload.barColor or TT_BAR_BURDEN
        ctx("safeMethod")(row, "setProgress", clamp01(payload.progress), barColor[1], barColor[2], barColor[3], barColor[4])
    end
    if payload.value ~= nil then
        local valueColor = payload.valueColor or TT_VALUE_DEFAULT
        ctx("safeMethod")(row, "setValue", tostring(payload.value), valueColor[1], valueColor[2], valueColor[3], valueColor[4])
    end

    return row
end

local function getBodyLocation(item)
    return tostring(ctx("safeMethod")(item, "getBodyLocation") or "")
end

local function isShoulderpadFamilyItem(item, location)
    local loc = ctx("lower")(location or getBodyLocation(item))
    if string.find(loc, "shoulderpad", 1, true) then
        return true
    end
    local fullType = tostring(ctx("safeMethod")(item, "getFullType") or "")
    local loweredFullType = ctx("lower")(fullType)
    return string.find(loweredFullType, "shoulderpad", 1, true) ~= nil
end

local function pruneBackpackTooltipRow(layout, item, starlitUI)
    if not layout or not item then
        return
    end
    if not isShoulderpadFamilyItem(item) then
        return
    end

    local rows = layout.items
    if not rows then
        return
    end

    local noBackpackText = getText and getText("Tooltip_item_NoBackpack") or "Can't wear with a backpack."
    local noBackpackTextLower = ctx("lower")(tostring(noBackpackText or ""))
    local itemTooltip = tostring(ctx("safeMethod")(item, "getTooltip") or "")
    local count = tonumber(ctx("safeMethod")(rows, "size")) or 0
    local toRemove = {}
    for i = count - 1, 0, -1 do
        local row = ctx("safeMethod")(rows, "get", i)
        local label = tostring((row and row.label) or ctx("safeMethod")(row, "getLabel") or "")
        local value = tostring((row and row.value) or ctx("safeMethod")(row, "getValue") or "")
        local normalized = string.gsub(label, "^%s+", "")
        normalized = string.gsub(normalized, "%s+$", "")
        local normalizedLower = ctx("lower")(normalized)
        local normalizedValue = string.gsub(value, "^%s+", "")
        normalizedValue = string.gsub(normalizedValue, "%s+$", "")
        local normalizedValueLower = ctx("lower")(normalizedValue)

        local isNoBackpack = (
            normalized == tostring(noBackpackText or "")
            or normalizedValue == tostring(noBackpackText or "")
            or (noBackpackTextLower ~= "" and (
                string.find(normalizedLower, noBackpackTextLower, 1, true) ~= nil
                or string.find(normalizedValueLower, noBackpackTextLower, 1, true) ~= nil
            ))
        )
        local isEmptyPlaceholder = (
            normalized == "\"\"" or normalizedValue == "\"\""
            or (normalized == "" and normalizedValue == "")
        )
        local isItemTooltipBlank = (itemTooltip == "" or itemTooltip == "\"\"")

        if isNoBackpack or (isItemTooltipBlank and isEmptyPlaceholder) then
            toRemove[#toRemove + 1] = row
        end
    end

    for i = 1, #toRemove do
        local row = toRemove[i]
        local removed = false
        if type(starlitUI) == "table" and type(starlitUI.removeTooltipElement) == "function" then
            local ok = pcall(starlitUI.removeTooltipElement, layout, row)
            if ok then
                removed = true
            end
        end
        if not removed and row then
            pcall(function()
                rows:remove(row)
                removed = true
            end)
        end
        if not removed and row then
            row.label = ""
            row.value = ""
            row.hasValue = false
            row.couldHaveValue = false
            row.progressFraction = 0
            row.height = 0
        end
    end
end

local function stripAmsPrefix(text)
    local value = tostring(text or "")
    value = string.gsub(value, "^%s*AMS%s+", "")
    return value
end

local function isTooltipWearable(item)
    if not item then
        return false
    end
    local location = getBodyLocation(item)
    local wearableCheck = ctx("isWearableItem")
    if type(wearableCheck) == "function" then
        local ok, result = pcall(wearableCheck, item, location)
        if ok and result then
            return true
        end
    end
    local scriptItem = ctx("safeMethod")(item, "getScriptItem")
    local bodyLocation = tostring(ctx("safeMethod")(scriptItem, "getBodyLocation") or "")
    return location ~= "" or bodyLocation ~= ""
end

local function injectTooltipRowsWithLayout(layout, item)
    if not layout or not item then
        return
    end
    if not isTooltipWearable(item) then
        return
    end
    local signal = ctx("itemToArmorSignal")(item, getBodyLocation(item))
    if not signal then
        return
    end
    local hasPhysical = (tonumber(signal.physicalLoad) or 0) >= TOOLTIP_DISPLAY_THRESHOLD
    local hasBreathing = (tonumber(signal.breathingLoad) or 0) >= 1.2
    if not hasPhysical and not hasBreathing then
        return
    end

    local rows = {}

    if hasPhysical then
        rows[#rows + 1] = {
            label = stripAmsPrefix(tr("UI_AMS_Label_Burden", "Burden")) .. ":",
            labelColor = TT_LABEL_ACCENT,
            progress = burdenBarFraction(signal.physicalLoad, TOOLTIP_BAR_MAX),
            barColor = TT_BAR_BURDEN,
        }
    end

    local breathingTier = breathingTierFromLoad(signal.breathingLoad)
    if breathingTier then
        local isHeavy = (tonumber(signal.breathingLoad) or 0) >= 3.45
        rows[#rows + 1] = {
            label = stripAmsPrefix(tr("UI_AMS_Label_Breathing", "Breathing")) .. ":",
            labelColor = TT_LABEL_ACCENT,
            value = breathingTier,
            valueColor = isHeavy and TT_VALUE_BREATHING_HEAVY or TT_VALUE_BREATHING,
        }
    end

    if #rows <= 0 then
        return
    end

    if #rows >= 2 then
        addLayoutRow(layout, {
            label = "----------------",
            labelColor = TT_SEPARATOR,
            value = "",
        })
    end

    for i = 1, #rows do
        addLayoutRow(layout, rows[i])
    end
end

local starlitHookInstalled = false

local function installStarlitHook()
    if starlitHookInstalled then
        return true
    end

    local ok, starlitUI = pcall(require, "Starlit/client/ui/InventoryUI")
    if not ok or type(starlitUI) ~= "table" then
        return false
    end
    if not starlitUI.onFillItemTooltip or type(starlitUI.onFillItemTooltip.addListener) ~= "function" then
        return false
    end

    starlitUI.onFillItemTooltip:addListener(function(tooltip, layout, item)
        pcall(pruneBackpackTooltipRow, layout, item, starlitUI)
        pcall(injectTooltipRowsWithLayout, layout, item)
    end)
    starlitHookInstalled = true
    ctx("logOnce")("ui_tooltip_starlit", "[UI] AMS tooltip rows registered via Starlit onFillItemTooltip event.")
    return true
end

local function installTooltipHook()
    if tooltipHookInstalled then
        return
    end

    if installStarlitHook() then
        tooltipHookInstalled = true
        return
    end

    ctx("logErrorOnce")("ui_tooltip_starlit_missing", "[UI] Starlit Library missing: AMS tooltip rows unavailable.")
    tooltipHookInstalled = true
end

-- -----------------------------------------------------------------------------
-- Hook installation (tooltip + clothing updates)
-- -----------------------------------------------------------------------------

local function markUiDirty()
    pendingUiRefresh = true
    if fallbackWindow and fallbackWindow.panel and type(fallbackWindow.panel.markDirty) == "function" then
        fallbackWindow.panel:markDirty()
    end
    local screenClass = _G.ISCharacterInfoWindow
    local existing = screenClass and screenClass.instance or nil
    if existing and existing._amsBurdenPanel and type(existing._amsBurdenPanel.markDirty) == "function" then
        existing._amsBurdenPanel:markDirty()
    end
end

local function installClothingUpdateHook()
    if clothingUpdateHookInstalled then
        return
    end
    if not (Events and Events.OnClothingUpdated and type(Events.OnClothingUpdated.Add) == "function") then
        return
    end

    Events.OnClothingUpdated.Add(function()
        markUiDirty()
    end)
    clothingUpdateHookInstalled = true
end

-- -----------------------------------------------------------------------------
-- Panel / tab data model
-- -----------------------------------------------------------------------------

local function getItemFullType(item)
    local fullType = tostring(ctx("safeMethod")(item, "getFullType") or "")
    if fullType ~= "" then
        return fullType
    end

    local script = ctx("safeMethod")(item, "getScriptItem")
    fullType = tostring(ctx("safeMethod")(script, "getFullName") or "")
    if fullType ~= "" then
        return fullType
    end

    local moduleName = tostring(ctx("safeMethod")(script, "getModuleName") or "")
    local typeName = tostring(ctx("safeMethod")(script, "getName") or "")
    if moduleName ~= "" and typeName ~= "" then
        return moduleName .. "." .. typeName
    end

    return tostring(item)
end

local function collectCostDrivers(player)
    local wornItems = ctx("safeMethod")(player, "getWornItems")
    if not wornItems then
        return {}
    end

    local rows = {}
    local count = tonumber(ctx("safeMethod")(wornItems, "size")) or 0
    for i = 0, count - 1 do
        local worn = ctx("safeMethod")(wornItems, "get", i)
        local item = worn and ctx("safeMethod")(worn, "getItem")
        if item then
            local locationName = tostring(ctx("safeMethod")(worn, "getLocation") or getBodyLocation(item))
            local signal = ctx("itemToArmorSignal")(item, locationName)
            if signal and (tonumber(signal.physicalLoad) or 0) >= TOOLTIP_DISPLAY_THRESHOLD then
                local displayName = tostring(ctx("safeMethod")(item, "getDisplayName") or ctx("safeMethod")(item, "getName") or getItemFullType(item))
                rows[#rows + 1] = {
                    label = displayName,
                    physical = tonumber(signal.physicalLoad) or 0,
                }
            end
        end
    end

    table.sort(rows, function(a, b)
        return a.physical > b.physical
    end)

    return rows
end

local function resolveThermalEffect(runtimeSnapshot)
    local hotStrain = tonumber(runtimeSnapshot and runtimeSnapshot.hotStrain) or 0
    local coldAppropriateness = tonumber(runtimeSnapshot and runtimeSnapshot.coldAppropriateness) or 0
    if hotStrain > 0.15 then
        return tr("UI_AMS_Label_ThermalBurdensome", "Burdensome"), { 1.0, 0.74, 0.35, 1.0 }, true,
            tr("UI_AMS_Annotation_HeatAmplifying", "Heat amplifying armor costs"),
            { 0.90, 0.65, 0.35, 0.90 }
    end
    if coldAppropriateness > 0.30 then
        return tr("UI_AMS_Label_ThermalHelpful", "Helpful"), { 0.65, 0.95, 0.65, 1.0 }, false,
            tr("UI_AMS_Annotation_ColdHelping", "Cold weather -- insulation reducing burden"),
            { 0.55, 0.80, 0.55, 0.90 }
    end
    return tr("UI_AMS_Label_ThermalNeutral", "Neutral"), { 0.82, 0.82, 0.82, 1.0 }, false, nil, nil
end

-- -----------------------------------------------------------------------------
-- Panel / tab rendering + help window
-- -----------------------------------------------------------------------------

local measureHelpText = nil
local toggleHelpWindow = nil
local AMSHelpPanel = nil
local AMSHelpWindow = nil
local AMSBurdenPanel = nil
local AMSBurdenWindow = nil

toggleHelpWindow = function()
    if helpWindow then
        helpWindow:setVisible(not helpWindow:isVisible())
        return
    end
    if not AMSHelpWindow then
        return
    end
    local core = type(getCore) == "function" and getCore() or nil
    local sw = core and ctx("safeMethod")(core, "getScreenWidth") or 800
    local sh = core and ctx("safeMethod")(core, "getScreenHeight") or 600
    local font = UIFont and UIFont.Small or nil
    local tm = type(getTextManager) == "function" and getTextManager() or nil
    local w = math.min(math.floor(sw * 0.35), 480)
    w = math.max(w, 320)
    local titleBarH = 24
    local contentH = measureHelpText(w - 28, font, tm)
    local h = contentH + titleBarH + 8
    h = math.min(h, math.floor(sh * 0.8))
    local wx = math.floor((sw - w) / 2)
    local wy = math.floor((sh - h) / 2)
    helpWindow = AMSHelpWindow:new(wx, wy, w, h)
    helpWindow:initialise()
    helpWindow:instantiate()
    helpWindow:addToUIManager()
    helpWindow:setVisible(true)
end

local function ensurePanelClasses()
    if AMSBurdenPanel or not ISPanel then
        return
    end

    AMSBurdenPanel = ISPanel:derive("AMSBurdenPanel")

    function AMSBurdenPanel:new(x, y, width, height, playerNum)
        local panel = ISPanel:new(x, y, width, height)
        setmetatable(panel, self)
        self.__index = self
        panel.playerNum = tonumber(playerNum) or 0
        panel.lastRefreshMinute = -1
        panel.lastRuntimeRefreshMinute = -1
        panel.snapshot = nil
        panel.needsRefresh = true
        panel.noBackground = true
        panel.isStandalone = false
        return panel
    end

    function AMSBurdenPanel:createChildren()
        ISPanel.createChildren(self)
        if ISButton then
            local btnW = 52
            local btnH = 20
            self.helpBtn = ISButton:new(self.width - btnW - 6, 4, btnW, btnH, "? Help", self, AMSBurdenPanel.onHelpClick)
            self.helpBtn:initialise()
            self.helpBtn:instantiate()
            self.helpBtn.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 0.7 }
            self.helpBtn.backgroundColor = { r = 0.15, g = 0.15, b = 0.15, a = 0.8 }
            self:addChild(self.helpBtn)
        end
    end

    function AMSBurdenPanel:onHelpClick()
        toggleHelpWindow()
    end

    function AMSBurdenPanel:prerender()
        self:collectSnapshot(false)
        if self.helpBtn then
            local btnW = 52
            self.helpBtn:setX(self.width - btnW - 6)
        end
    end

    function AMSBurdenPanel:markDirty()
        self.needsRefresh = true
    end

    function AMSBurdenPanel:resolvePlayer()
        local player = nil
        if type(getSpecificPlayer) == "function" then
            player = getSpecificPlayer(self.playerNum)
        end
        if not player and type(getPlayer) == "function" then
            player = getPlayer()
        end
        return player
    end

    function AMSBurdenPanel:collectSnapshot(force)
        local player = self:resolvePlayer()
        if not player then
            self.snapshot = nil
            return
        end

        local nowMinute = 0
        if type(ctx("getWorldAgeMinutes")) == "function" then
            nowMinute = tonumber(ctx("getWorldAgeMinutes")()) or 0
        end

        local refreshRuntime = force
            or self.needsRefresh
            or self.snapshot == nil
            or self.lastRuntimeRefreshMinute < 0
            or (nowMinute - self.lastRuntimeRefreshMinute) >= 0.5

        if not refreshRuntime then
            return
        end

        local state = ctx("ensureState") and ctx("ensureState")(player) or nil
        local options = UI._lastOptions or (ctx("getOptions") and ctx("getOptions")()) or {}
        local runtime = ctx("getUiRuntimeSnapshot") and ctx("getUiRuntimeSnapshot")(player, state, options) or nil
        local isMp = type(ctx("isMultiplayer")) == "function" and ctx("isMultiplayer")()

        if isMp and type(runtime) ~= "table" then
            self.snapshot = {
                pendingSnapshot = true,
                profile = { physicalLoad = 0, breathingLoad = 0, rigidityLoad = 0, armorCount = 0 },
                runtime = nil,
                burdenTier = tr("UI_AMS_Tier_Negligible", "Negligible"),
                burdenTierKey = "negligible",
                thermalWord = tr("UI_AMS_Label_ThermalNeutral", "Neutral"),
                thermalColor = { 0.82, 0.82, 0.82, 1.0 },
                thermalAnnotation = nil,
                thermalAnnotationColor = nil,
                breathingWord = nil,
                breathingDesc = nil,
                sleepWord = nil,
                noBurden = false,
                compact = false,
                heatSensitive = false,
                drivers = {},
            }
            self.lastRefreshMinute = nowMinute
            self.lastRuntimeRefreshMinute = nowMinute
            self.needsRefresh = false
            return
        end

        local profile = nil
        local burdenTier, burdenTierKey = nil, nil
        local breathingWord = nil
        local breathingDesc = nil
        local sleepWord = nil
        local costDrivers = {}
        if isMp then
            local loadNorm = tonumber(runtime and runtime.loadNorm) or 0
            local physicalLoad = tonumber(runtime and runtime.physicalLoad)
            if physicalLoad == nil then
                physicalLoad = ctx("clamp")(loadNorm / 2.8 * 100.0, 0, 100)
            end
            local breathingLoad = tonumber(runtime and runtime.breathingLoad) or 0
            local rigidityLoad = tonumber(runtime and runtime.rigidityLoad) or 0
            local armorCount = tonumber(runtime and runtime.armorCount) or (physicalLoad > 1 and 1 or 0)
            profile = {
                physicalLoad = physicalLoad,
                breathingLoad = breathingLoad,
                rigidityLoad = rigidityLoad,
                armorCount = armorCount,
            }
            burdenTier, burdenTierKey = burdenTierFromTotal(tonumber(profile.physicalLoad) or 0)
            breathingWord = breathingTierFromLoad(profile.breathingLoad)
            if breathingWord then
                local bLoad = tonumber(profile.breathingLoad) or 0
                if bLoad >= 3.45 then
                    breathingDesc = tr("UI_AMS_BreathingDesc_HeavyRestricted", "Severe breathing penalty")
                else
                    breathingDesc = tr("UI_AMS_BreathingDesc_Restricted", "Restricts airflow during exertion")
                end
            end
            local rigidity = tonumber(profile.rigidityLoad) or 0
            if rigidity >= 10 then
                local rigidityNorm = rigidity / (rigidity + 80.0) * 2.0
                local sleepPct = math.floor(rigidityNorm * 6.75 + 0.5)
                if sleepPct >= 1 then
                    sleepWord = string.format("~%d%% %s", sleepPct, tr("UI_AMS_Label_SleepLonger", "longer recovery"))
                end
            end
            costDrivers = type(runtime and runtime.drivers) == "table" and runtime.drivers or {}
        else
            profile = ctx("computeArmorProfile")(player) or {}
            burdenTier, burdenTierKey = burdenTierFromTotal(tonumber(profile.physicalLoad) or 0)
            breathingWord = breathingTierFromLoad(profile.breathingLoad)
            if breathingWord then
                local bLoad = tonumber(profile.breathingLoad) or 0
                if bLoad >= 3.45 then
                    breathingDesc = tr("UI_AMS_BreathingDesc_HeavyRestricted", "Severe breathing penalty")
                else
                    breathingDesc = tr("UI_AMS_BreathingDesc_Restricted", "Restricts airflow during exertion")
                end
            end

            local rigidity = tonumber(profile.rigidityLoad) or 0
            if rigidity >= 10 then
                local rigidityNorm = rigidity / (rigidity + 80.0) * 2.0
                local sleepPct = math.floor(rigidityNorm * 6.75 + 0.5)
                if sleepPct >= 1 then
                    sleepWord = string.format("~%d%% %s", sleepPct, tr("UI_AMS_Label_SleepLonger", "longer recovery"))
                end
            end
            costDrivers = collectCostDrivers(player)
        end

        local thermalWord, thermalColor, thermalBurdensome, thermalAnnotation, thermalAnnotationColor = resolveThermalEffect(runtime)
        local physical = tonumber(profile.physicalLoad) or 0
        local armorCount = tonumber(profile.armorCount) or 0
        local noBurden = armorCount <= 0
        local compact = (not noBurden)
            and physical < 15
            and (not thermalBurdensome)
            and (not breathingWord)
        local heatSensitive = (not noBurden) and physical < 15 and thermalBurdensome

        self.snapshot = {
            pendingSnapshot = false,
            profile = profile,
            runtime = runtime,
            burdenTier = burdenTier,
            burdenTierKey = burdenTierKey,
            thermalWord = thermalWord,
            thermalColor = thermalColor,
            thermalAnnotation = thermalAnnotation,
            thermalAnnotationColor = thermalAnnotationColor,
            breathingWord = breathingWord,
            breathingDesc = breathingDesc,
            sleepWord = sleepWord,
            noBurden = noBurden,
            compact = compact,
            heatSensitive = heatSensitive,
            drivers = costDrivers,
        }

        self.lastRefreshMinute = nowMinute
        self.lastRuntimeRefreshMinute = nowMinute
        self.needsRefresh = false
    end

    local function drawBar(self, x, y, width, value, color, barH)
        local h = barH or 10
        local fill = clamp01(value)
        self:drawRect(x, y, width, h, 0.50, 0.12, 0.12, 0.12)
        self:drawRect(x, y, math.floor(width * fill), h, 0.85, color[1], color[2], color[3])
        self:drawRectBorder(x, y, width, h, 0.55, 0.40, 0.40, 0.40)
    end

    local function drawLabelValue(self, font, x, y, label, labelColor, value, valueColor, labelCol)
        self:drawText(label, x, y, labelColor[1], labelColor[2], labelColor[3], 1.0, font)
        self:drawText(value, x + labelCol, y, valueColor[1], valueColor[2], valueColor[3], 1.0, font)
    end

    function AMSBurdenPanel:syncSizeToScreen(contentW, contentH)
        if not self.screenRef or self.isStandalone then
            if self.isStandalone then
                local targetH = contentH + 8
                self:setHeight(targetH)
                local parent = self:getParent()
                if parent and type(parent.setHeight) == "function" and parent.resizable then
                    parent:setHeight(targetH + 32)
                end
            end
            return
        end
        local screen = self.screenRef
        local tabPanel = self:getParent()
        if not tabPanel then return end
        local tabH = tonumber(tabPanel.tabHeight) or 24
        local th = 0
        pcall(function() th = screen:titleBarHeight() end)
        local rh = 0
        pcall(function() rh = screen:resizeWidgetHeight() end)
        local targetW = contentW
        local targetH = th + tabH + contentH + rh + 8
        pcall(function() screen:setWidth(targetW) end)
        pcall(function() screen:setHeight(targetH) end)
        pcall(function() tabPanel:setWidth(targetW) end)
        pcall(function() tabPanel:setHeight(targetH - th - rh) end)
        self:setWidth(targetW)
        self:setHeight(targetH - th - tabH - rh)
    end

    function AMSBurdenPanel:render()
        local data = self.snapshot
        if not data then
            self:syncSizeToScreen(self.canonicalW or 480, 30)
            return
        end

        local font = UIFont and UIFont.Small or nil
        local tm = type(getTextManager) == "function" and getTextManager() or nil
        local fontH = (tm and font) and (tonumber(ctx("safeMethod")(tm, "getFontHeight", font)) or 18) or 18
        local lineH = fontH + 6
        local sectionGap = math.max(12, math.floor(lineH * 0.65))
        local x = 14
        local y = 14
        local measure = tm

        local labelCol = 0
        if measure then
            local labels = { "Burden:", "Thermal:", "Breathing:", "Sleep:" }
            for li = 1, #labels do
                local lw = tonumber(ctx("safeMethod")(measure, "MeasureStringX", font, labels[li])) or 60
                if lw > labelCol then labelCol = lw end
            end
            labelCol = labelCol + 12
        else
            labelCol = 90
        end

        -- Unified color palette
        local cLabel = { 0.85, 0.82, 0.75 }
        local cValue = { 0.95, 0.92, 0.85 }
        local cHeader = { 0.72, 0.68, 0.58 }
        local cItem = { 0.88, 0.85, 0.78 }
        local cAnnotation = { 0.72, 0.70, 0.64 }
        local cSep = { 0.35, 0.35, 0.35 }

        if data.pendingSnapshot then
            self:drawText("Waiting for server snapshot...", x, y, cValue[1], cValue[2], cValue[3], 1.0, font)
            self:syncSizeToScreen(self.canonicalW or 480, y + lineH)
            return
        end

        if data.noBurden then
            self:drawText(tr("UI_AMS_NoBurden", "No armor burden."), x, y, cValue[1], cValue[2], cValue[3], 1.0, font)
            self:syncSizeToScreen(self.canonicalW or 480, y + lineH)
            return
        end

        if data.compact then
            self:drawText(tr("UI_AMS_LightMinimal", "Light clothing -- minimal burden."), x, y, cValue[1], cValue[2], cValue[3], 1.0, font)
            self:syncSizeToScreen(self.canonicalW or 480, y + lineH)
            return
        end

        local contentW = self.width - x - 14

        if data.heatSensitive then
            self:drawText(tr("UI_AMS_HeatSensitive", "Low weight, but heat-sensitive outfit."), x, y, 1.0, 0.85, 0.55, 1.0, font)
            y = y + lineH + 4
            drawLabelValue(self, font, x, y, tr("UI_AMS_Panel_Thermal", "Thermal") .. ":", cLabel, data.thermalWord, data.thermalColor, labelCol)
            if data.thermalAnnotation then
                local ac = data.thermalAnnotationColor or { cAnnotation[1], cAnnotation[2], cAnnotation[3], 0.90 }
                y = y + lineH
                self:drawText(data.thermalAnnotation, x, y, ac[1], ac[2], ac[3], ac[4], font)
            end
            self:syncSizeToScreen(self.canonicalW or 480, y + lineH)
            return
        end

        -- Section: Load Channels
        drawLabelValue(self, font, x, y, tr("UI_AMS_Panel_Burden", "Burden") .. ":", cLabel, data.burdenTier, cValue, labelCol)
        y = y + lineH
        local profilePhysical = tonumber(data.profile and data.profile.physicalLoad) or 0
        local barH = math.max(8, math.floor(fontH * 0.6))
        drawBar(self, x, y, contentW, burdenBarFraction(profilePhysical), { 0.95, 0.70, 0.25 }, barH)
        y = y + barH + 8

        drawLabelValue(self, font, x, y, tr("UI_AMS_Panel_Thermal", "Thermal") .. ":", cLabel, data.thermalWord, data.thermalColor, labelCol)
        y = y + lineH
        if data.thermalAnnotation then
            local ac = data.thermalAnnotationColor or { cAnnotation[1], cAnnotation[2], cAnnotation[3], 0.90 }
            self:drawText(data.thermalAnnotation, x, y, ac[1], ac[2], ac[3], ac[4], font)
            y = y + lineH
        end

        if data.breathingWord then
            drawLabelValue(self, font, x, y, tr("UI_AMS_Panel_Breathing", "Breathing") .. ":", cLabel, data.breathingWord, { 1.0, 0.80, 0.40 }, labelCol)
            y = y + lineH
            if data.breathingDesc then
                self:drawText(data.breathingDesc, x, y, cAnnotation[1], cAnnotation[2], cAnnotation[3], 0.90, font)
                y = y + lineH
            end
        end

        if data.sleepWord then
            drawLabelValue(self, font, x, y, tr("UI_AMS_Panel_Sleep", "Sleep") .. ":", cLabel, data.sleepWord, cValue, labelCol)
            y = y + lineH
        end

        local drivers = data.drivers or {}
        local maxRows = #drivers
        if maxRows <= 0 then
            self:syncSizeToScreen(self.canonicalW or 480, y + lineH)
            return
        end

        -- Separator
        y = y + sectionGap
        self:drawRect(x, y, contentW, 1, 0.18, cSep[1], cSep[2], cSep[3])
        y = y + sectionGap

        -- Section: Cost Drivers
        self:drawText(tr("UI_AMS_Section_CostDrivers", "Cost Drivers"), x, y, cHeader[1], cHeader[2], cHeader[3], 1.0, font)
        y = y + lineH + 4
        local topPhysical = maxRows > 0 and (tonumber(drivers[1].physical) or 0) or 1

        local maxNameW = 0
        for i = 1, maxRows do
            local tw = measure and tonumber(ctx("safeMethod")(measure, "MeasureStringX", font, drivers[i].label))
                or (string.len(drivers[i].label) * 7)
            if tw > maxNameW then maxNameW = tw end
        end
        local nameGap = 12
        local barX = x + 4 + math.min(maxNameW, contentW * 0.55) + nameGap
        local barW = math.max(60, self.width - barX - 14)

        for i = 1, maxRows do
            local row = drivers[i]
            local nameW = barX - nameGap - x - 4
            local displayLabel = row.label
            if measure then
                local tw = tonumber(ctx("safeMethod")(measure, "MeasureStringX", font, displayLabel)) or 0
                if tw > nameW then
                    local base = row.label
                    local len = string.len(base)
                    while len > 1 do
                        len = len - 1
                        displayLabel = string.sub(base, 1, len) .. "..."
                        tw = tonumber(ctx("safeMethod")(measure, "MeasureStringX", font, displayLabel)) or 0
                        if tw <= nameW then break end
                    end
                end
            end
            self:drawText(displayLabel, x + 6, y, cItem[1], cItem[2], cItem[3], 1.0, font)
            local ratio = (tonumber(row.physical) or 0) / math.max(1, topPhysical)
            local driverBarH = math.max(6, math.floor(fontH * 0.5))
            local barY = y + math.floor((fontH - driverBarH) / 2) + 1
            drawBar(self, barX, barY, barW, ratio, { 0.82, 0.72, 0.48 }, driverBarH)
            y = y + lineH
        end

        self:syncSizeToScreen(self.canonicalW or 480, y)
    end

    -- Help panel: renders help text sections using drawText
    AMSHelpPanel = ISPanel:derive("AMSHelpPanel")

    function AMSHelpPanel:new(x, y, width, height)
        local panel = ISPanel:new(x, y, width, height)
        setmetatable(panel, self)
        self.__index = self
        panel.backgroundColor = { r = 0.10, g = 0.10, b = 0.10, a = 0.95 }
        return panel
    end

    local helpSections = {
        { key = "UI_AMS_Help_Burden",      fallback = "Burden: Your armor's physical weight and bulk. Heavier armor drains more endurance during physical activity and slows recovery between efforts. Melee combat in heavy armor also increases muscle strain per swing. The bar shows total burden as a fraction of the heaviest possible loadout." },
        { key = "UI_AMS_Help_Thermal",      fallback = "Thermal: In hot weather, armor amplifies endurance drain. In cold weather, insulating armor reduces burden. Wet armor provides less insulation. Burdensome = heat is costing you. Helpful = insulation is working for you." },
        { key = "UI_AMS_Help_Breathing",    fallback = "Breathing: Face coverings and sealed headgear restrict airflow, increasing exertion cost during physical activity." },
        { key = "UI_AMS_Help_Sleep",        fallback = "Sleep: Sleeping in rigid armor slows recovery. The percentage shows the estimated extra time needed to fully rest." },
        { key = "UI_AMS_Help_CostDrivers",  fallback = "Cost Drivers: Shows which of your worn items contribute most to your total burden, sorted by impact." },
    }

    local function wrapTextLines(text, wrapW, font, tm)
        local words = {}
        for w in string.gmatch(text or "", "%S+") do
            words[#words + 1] = w
        end
        local lines = {}
        local line = ""
        for wi = 1, #words do
            local testLine = (line == "") and words[wi] or (line .. " " .. words[wi])
            local testW = (tm and font) and (tonumber(ctx("safeMethod")(tm, "MeasureStringX", font, testLine)) or (#testLine * 8)) or (#testLine * 8)
            if testW > wrapW and line ~= "" then
                lines[#lines + 1] = line
                line = words[wi]
            else
                line = testLine
            end
        end
        if line ~= "" then
            lines[#lines + 1] = line
        end
        return lines
    end

    measureHelpText = function(wrapW, font, tm)
        local fontH = (tm and font) and (tonumber(ctx("safeMethod")(tm, "getFontHeight", font)) or 18) or 18
        local lineH = fontH + 4
        local y = 10
        for i = 1, #helpSections do
            local text = tr(helpSections[i].key, helpSections[i].fallback)
            local colonPos = string.find(text, ": ", 1, true)
            if colonPos then
                y = y + lineH
                local body = string.sub(text, colonPos + 2)
                local lines = wrapTextLines(body, wrapW, font, tm)
                y = y + (#lines * lineH)
            else
                y = y + lineH
            end
            y = y + 4
        end
        return y + 10
    end

    function AMSHelpPanel:render()
        local font = UIFont and UIFont.Small or nil
        local tm = type(getTextManager) == "function" and getTextManager() or nil
        local fontH = (tm and font) and (tonumber(ctx("safeMethod")(tm, "getFontHeight", font)) or 18) or 18
        local lineH = fontH + 4
        local wrapW = self.width - 28
        local x = 14
        local y = 10

        local cHeader = { 1.0, 0.90, 0.65 }
        local cBody = { 0.88, 0.85, 0.80 }

        for i = 1, #helpSections do
            local text = tr(helpSections[i].key, helpSections[i].fallback)
            local colonPos = string.find(text, ": ", 1, true)
            if colonPos then
                local header = string.sub(text, 1, colonPos - 1)
                local body = string.sub(text, colonPos + 2)
                self:drawText(header, x, y, cHeader[1], cHeader[2], cHeader[3], 1.0, font)
                y = y + lineH
                local lines = wrapTextLines(body, wrapW, font, tm)
                for li = 1, #lines do
                    self:drawText(lines[li], x + 4, y, cBody[1], cBody[2], cBody[3], 1.0, font)
                    y = y + lineH
                end
            else
                self:drawText(text, x, y, cBody[1], cBody[2], cBody[3], 1.0, font)
                y = y + lineH
            end
            y = y + 4
        end
    end

    if ISCollapsableWindow then
        AMSHelpWindow = ISCollapsableWindow:derive("AMSHelpWindow")

        function AMSHelpWindow:new(x, y, width, height)
            local window = ISCollapsableWindow:new(x, y, width, height)
            setmetatable(window, self)
            self.__index = self
            window.resizable = false
            window.title = tr("UI_AMS_Help_Title", "Armor Makes Sense -- How It Works")
            return window
        end

        function AMSHelpWindow:createChildren()
            ISCollapsableWindow.createChildren(self)
            self.helpPanel = AMSHelpPanel:new(0, 24, self.width, self.height - 24)
            self.helpPanel:initialise()
            self.helpPanel:instantiate()
            self.helpPanel:setAnchorRight(true)
            self.helpPanel:setAnchorBottom(true)
            self:addChild(self.helpPanel)
        end

        function AMSHelpWindow:close()
            self:setVisible(false)
        end
    end

    if ISCollapsableWindow then
        AMSBurdenWindow = ISCollapsableWindow:derive("AMSBurdenWindow")

        function AMSBurdenWindow:new(x, y, width, height, playerNum)
            local window = ISCollapsableWindow:new(x, y, width, height)
            setmetatable(window, self)
            self.__index = self
            window.playerNum = tonumber(playerNum) or 0
            window.resizable = true
            window.title = tr("UI_AMS_Tab_Burden", "Burden")
            window.panel = nil
            return window
        end

        function AMSBurdenWindow:createChildren()
            ISCollapsableWindow.createChildren(self)
            self.panel = AMSBurdenPanel:new(8, 24, self.width - 16, self.height - 32, self.playerNum)
            self.panel.isStandalone = true
            self.panel:initialise()
            self.panel:instantiate()
            self.panel:setAnchorRight(true)
            self.panel:setAnchorBottom(false)
            self:addChild(self.panel)
        end
    end
end

-- -----------------------------------------------------------------------------
-- Panel / tab hook installation
-- -----------------------------------------------------------------------------

local function ensureFallbackWindow(showNow)
    ensurePanelClasses()
    if not AMSBurdenWindow then
        return
    end

    if not fallbackWindow then
        fallbackWindow = AMSBurdenWindow:new(120, 80, 420, 300, 0)
        fallbackWindow:initialise()
        fallbackWindow:instantiate()
        fallbackWindow:addToUIManager()
        fallbackWindow:setVisible(false)
    end

    if showNow then
        fallbackWindow:setVisible(true)
        if fallbackWindow.panel and type(fallbackWindow.panel.markDirty) == "function" then
            fallbackWindow.panel:markDirty()
        end
    end
end

local function attachBurdenTabToScreen(screen)
    ensurePanelClasses()
    if not AMSBurdenPanel then
        return false, "ISPanel unavailable"
    end

    if screen._amsBurdenAttached then
        return true
    end

    local candidates = { screen.panel, screen.tabs, screen.tabPanel, screen.characterTabs }

    for i = 1, #candidates do
        local host = candidates[i]
        if host then
            local hostW = tonumber(host.width) or (tonumber(screen.width) or 600) - 24
            local hostH = tonumber(host.height) or (tonumber(screen.height) or 420) - 64
            local panel = AMSBurdenPanel:new(0, 0, hostW, hostH, screen.playerNum or 0)
            panel:initialise()
            panel:instantiate()
            panel:setAnchorRight(true)

            local title = tr("UI_AMS_Tab_Burden", "Burden")
            local added = false
            if type(host.addView) == "function" then
                local ok = pcall(host.addView, host, title, panel)
                added = ok
            elseif type(host.addTab) == "function" then
                local ok = pcall(host.addTab, host, title, panel)
                added = ok
            elseif type(host.addPanel) == "function" then
                local ok = pcall(host.addPanel, host, title, panel)
                added = ok
            end

            if added then
                screen._amsBurdenPanel = panel
                screen._amsBurdenAttached = true
                panel.screenRef = screen
                screen._amsBurdenTabHost = host

                local tabStripW = 0
                pcall(function()
                    tabStripW = tonumber(host:getWidthOfAllTabs()) or 0
                end)
                if tabStripW <= 0 then tabStripW = 480 end
                panel.canonicalW = tabStripW

                local tabSafetyPad = 2
                local minWindowW = math.max(tabStripW + tabSafetyPad, tonumber(screen.width) or 0)
                screen._amsMinCharacterInfoWidth = minWindowW
                host._amsMinTabHostWidth = minWindowW

                if not screen._amsOriginalSetWidth and type(screen.setWidth) == "function" then
                    screen._amsOriginalSetWidth = screen.setWidth
                    screen.setWidth = function(self, width, ...)
                        local clamped = math.max(tonumber(width) or 0, tonumber(self._amsMinCharacterInfoWidth) or 0)
                        return self:_amsOriginalSetWidth(clamped, ...)
                    end
                end
                if not host._amsOriginalSetWidth and type(host.setWidth) == "function" then
                    host._amsOriginalSetWidth = host.setWidth
                    host.setWidth = function(self, width, ...)
                        local clamped = math.max(tonumber(width) or 0, tonumber(self._amsMinTabHostWidth) or 0)
                        return self:_amsOriginalSetWidth(clamped, ...)
                    end
                end

                pcall(function() host:setWidth(minWindowW) end)
                pcall(function() screen:setWidth(minWindowW) end)
                host.scrollX = 0
                host.smoothScrollX = 0
                host.smoothScrollTargetX = nil

                return true
            end
        end
    end

    return false, "character info tabs container unavailable"
end

local function installCharacterTabHook()
    if tabHookInstalled then
        return
    end

    pcall(require, "XpSystem/ISUI/ISCharacterInfoWindow")
    local screenClass = _G.ISCharacterInfoWindow
    if not (screenClass and type(screenClass.createChildren) == "function") then
        return
    end
    if screenClass._amsBurdenTabPatched then
        tabHookInstalled = true
        return
    end

    local originalCreateChildren = screenClass.createChildren
    screenClass.createChildren = function(self, ...)
        local result = originalCreateChildren(self, ...)
        if not tabHookFailed then
            local ok, attached = pcall(function()
                local attachedOk, attachReason = attachBurdenTabToScreen(self)
                return attachedOk, attachReason
            end)
            if not ok or not attached then
                tabHookFailed = true
                ctx("logOnce")("ui_burden_tab_fallback", "[UI] Burden tab injection failed; enabling standalone fallback window.")
                ensureFallbackWindow(true)
            elseif self._amsBurdenPanel and type(self._amsBurdenPanel.markDirty) == "function" then
                self._amsBurdenPanel:markDirty()
            end
        end
        return result
    end

    screenClass._amsBurdenTabPatched = true
    screenClass._amsBurdenTabOriginalCreateChildren = originalCreateChildren
    tabHookInstalled = true
    ctx("logOnce")("ui_burden_tab_hook_installed", "[UI] Character info Burden tab hook installed.")

    -- Retroactively attach to any already-created instance
    pcall(function()
        local existing = screenClass.instance
        if existing and not existing._amsBurdenAttached and existing.panel and type(existing.panel.addView) == "function" then
            attachBurdenTabToScreen(existing)
        end
    end)
end

-- -----------------------------------------------------------------------------
-- Public API
-- -----------------------------------------------------------------------------

function UI.markDirty()
    markUiDirty()
end

function UI.update(player, profile, options)
    UI._lastOptions = options or UI._lastOptions or {}

    installTooltipHook()
    installClothingUpdateHook()
    installCharacterTabHook()

    if tabHookFailed then
        ensureFallbackWindow(true)
    end

    if pendingUiRefresh then
        pendingUiRefresh = false
        if fallbackWindow and fallbackWindow.panel and type(fallbackWindow.panel.markDirty) == "function" then
            fallbackWindow.panel:markDirty()
        end
    end
end

return UI
