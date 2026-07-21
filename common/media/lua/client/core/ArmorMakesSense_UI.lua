ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Core = ArmorMakesSense.Core or {}

local Core = ArmorMakesSense.Core
Core.UI = Core.UI or {}

local ClientRuntime = require "core/ArmorMakesSense_ClientRuntime"
local LoadModel = require "ArmorMakesSense_LoadModelShared"
local Options = require "ArmorMakesSense_Options"
local Physiology = require "ArmorMakesSense_PhysiologyShared"
local SupportReport = require "core/ArmorMakesSense_SupportReport"
local UITooltip = require "core/ArmorMakesSense_UITooltip"
local Utils = require "ArmorMakesSense_UtilsShared"

local UI = Core.UI

local clothingUpdateHookInstalled = false
local tabHookInstalled = false
local tabHookFailed = false
local fallbackWindow = nil
local helpWindow = nil
local pendingUiRefresh = true

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

local function wrapTextLines(text, wrapW, font, tm)
    local words = {}
    for w in string.gmatch(text or "", "%S+") do
        words[#words + 1] = w
    end
    local lines = {}
    local line = ""
    for wi = 1, #words do
        local testLine = (line == "") and words[wi] or (line .. " " .. words[wi])
        local testW = (tm and font) and (tonumber(ClientRuntime.safeMethod(tm, "MeasureStringX", font, testLine)) or (#testLine * 8)) or (#testLine * 8)
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

local function clamp01(value)
    return Utils.clamp(tonumber(value) or 0, 0, 1)
end

local BURDEN_BAR_MAX = 100
local TOOLTIP_BAR_MAX = 28

local function burdenBarFraction(physicalLoad, maxLoad)
    local v = tonumber(physicalLoad) or 0
    if v <= 0 then return 0 end
    return math.min(1.0, v / (maxLoad or BURDEN_BAR_MAX))
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

local function showExportResultModal(playerNum, ok, detail)
    if not ISModalDialog then
        return false
    end
    local label = ok
        and tr("UI_AMS_Help_ExportSaved", "Saved")
        or tr("UI_AMS_Help_ExportFailed", "Export failed")
    local body = label .. ":\n" .. tostring(detail or "")
    local modal = ISModalDialog:new(0, 0, 360, 120, body, false, nil, nil, tonumber(playerNum) or 0)
    modal:initialise()
    modal:addToUIManager()
    return true
end
-- -----------------------------------------------------------------------------
-- Burden refresh hook
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

local function resolveDriverLabelsForClient(analysis, drivers)
    local displayNames = {}
    for i = 1, #(analysis and analysis.rows or {}) do
        local row = analysis.rows[i]
        local fullType = tostring(row and row.fullType or "")
        local displayName = tostring(row and row.displayName or "")
        if fullType ~= "" and displayName ~= "" then
            displayNames[fullType] = displayName
        end
    end

    local resolved = {}
    for i = 1, #(drivers or {}) do
        local row = drivers[i]
        if type(row) == "table" then
            local fullType = tostring(row.fullType or "")
            local fallbackLabel = tostring(row.label or "")
            if fallbackLabel == "" then
                fallbackLabel = fullType ~= "" and fullType or "Unknown Item"
            end
            resolved[#resolved + 1] = {
                label = displayNames[fullType] or fallbackLabel,
                fullType = fullType,
                physical = tonumber(row.physical) or 0,
            }
        end
    end
    return resolved
end

local function resolveThermalEffect(runtimeSnapshot)
    local thermalScale = tonumber(runtimeSnapshot and runtimeSnapshot.thermalStrainScale) or 0
    local coldSuitability = tonumber(runtimeSnapshot and runtimeSnapshot.coldSuitability) or 0
    if thermalScale >= 0.50 then
        return tr("UI_AMS_Label_ThermalOppressive", "Oppressive"), { 1.0, 0.45, 0.25, 1.0 }, true,
            tr("UI_AMS_Annotation_HeatOppressive", "Overheating in heavy gear"),
            { 0.95, 0.40, 0.25, 0.90 }
    end
    if thermalScale >= 0.15 then
        return tr("UI_AMS_Label_ThermalBurdensome", "Burdensome"), { 1.0, 0.74, 0.35, 1.0 }, true,
            tr("UI_AMS_Annotation_HeatBurdensome", "Heat increasing exertion cost"),
            { 0.90, 0.65, 0.35, 0.90 }
    end
    if thermalScale > 0.01 then
        return tr("UI_AMS_Label_ThermalWarm", "Warm"), { 1.0, 0.88, 0.55, 1.0 }, false,
            tr("UI_AMS_Annotation_HeatWarm", "Armor retaining body heat"),
            { 0.85, 0.78, 0.50, 0.90 }
    end
    if coldSuitability > 0.45 then
        return tr("UI_AMS_Label_ThermalHelpful", "Helpful"), { 0.65, 0.95, 0.65, 1.0 }, false,
            tr("UI_AMS_Annotation_ColdHelping", "Insulation suited to the cold"),
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
local HELP_BUTTON_HEIGHT = 22

toggleHelpWindow = function()
    if helpWindow then
        helpWindow:setVisible(not helpWindow:isVisible())
        return
    end
    if not AMSHelpWindow then
        return
    end
    local core = type(getCore) == "function" and getCore() or nil
    local sw = core and ClientRuntime.safeMethod(core, "getScreenWidth") or 800
    local sh = core and ClientRuntime.safeMethod(core, "getScreenHeight") or 600
    local font = UIFont and UIFont.Small or nil
    local tm = type(getTextManager) == "function" and getTextManager() or nil
    local w = math.min(math.floor(sw * 0.40), 540)
    w = math.max(w, 360)
    local titleBarH = 24
    local contentH = measureHelpText(w - 28, font, tm)
    local h = contentH + titleBarH + 8
    h = math.min(h, math.floor(sh * 0.75))
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
            local gap = 6
            local helpW = 52
            local exportW = 110
            local btnH = 20
            local rightEdge = self.width - gap

            self.helpBtn = ISButton:new(rightEdge - helpW, 4, helpW, btnH, "? Help", self, AMSBurdenPanel.onHelpClick)
            self.helpBtn:initialise()
            self.helpBtn:instantiate()
            self.helpBtn.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 0.7 }
            self.helpBtn.backgroundColor = { r = 0.15, g = 0.15, b = 0.15, a = 0.8 }
            self:addChild(self.helpBtn)

            self.exportBtn = ISButton:new(rightEdge - helpW - gap - exportW, 4, exportW, btnH,
                tr("UI_AMS_Help_ExportShort", "Export"),
                self, AMSBurdenPanel.onExportClick)
            self.exportBtn:initialise()
            self.exportBtn:instantiate()
            self.exportBtn.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 0.7 }
            self.exportBtn.backgroundColor = { r = 0.15, g = 0.15, b = 0.15, a = 0.8 }
            self.exportBtn:setTooltip(tr(
                "UI_AMS_Help_ExportTitleDesc",
                "Save a support report with your current loadout, burden calculations, mod list, and game state."
            ))
            self:addChild(self.exportBtn)
        end
    end

    function AMSBurdenPanel:onHelpClick()
        toggleHelpWindow()
    end

    function AMSBurdenPanel:onExportClick()
        local exportFn = SupportReport.writeCurrentPlayerReport
        if type(exportFn) ~= "function" then
            return
        end
        local ok, pathOrNil, err = exportFn()
        if ok then
            local savedPath = tostring(pathOrNil or "Lua/ams_reports/")
            showExportResultModal(self.playerNum, true, savedPath)
        else
            local failure = tostring(err or "unknown")
            showExportResultModal(self.playerNum, false, failure)
        end
    end

    function AMSBurdenPanel:onJoypadDown(button, joypadData)
        if not Joypad then
            return
        end

        local playerInfo = type(getPlayerInfoPanel) == "function" and getPlayerInfoPanel(self.playerNum) or nil
        if button == Joypad.LBumper or button == Joypad.RBumper then
            if playerInfo and type(playerInfo.onJoypadDown) == "function" then
                playerInfo:onJoypadDown(button, joypadData)
            end
            return
        end

        if button == Joypad.BButton then
            if playerInfo and type(playerInfo.toggleView) == "function" then
                playerInfo:toggleView(tr("UI_AMS_Tab_Burden", "Burden"))
            elseif self.isStandalone then
                local parent = self:getParent()
                if parent and type(parent.setVisible) == "function" then
                    parent:setVisible(false)
                end
            end
            if type(setJoypadFocus) == "function" then
                setJoypadFocus(self.playerNum, nil)
            end
        end
    end

    function AMSBurdenPanel:prerender()
        self:collectSnapshot(false)
        if self.helpBtn then
            local gap = 6
            local helpW = 52
            local exportW = 110
            local rightEdge = self.width - gap
            self.helpBtn:setX(rightEdge - helpW)
            if self.exportBtn then
                self.exportBtn:setX(rightEdge - helpW - gap - exportW)
            end
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

    local function shouldShowThermalBlock(thermalBurdensome, thermalAnnotation, showBurden, showBreathing, showSleep)
        return thermalBurdensome or thermalAnnotation ~= nil or showBurden or showBreathing or showSleep
    end

    local function buildProfileFromRuntime(runtime)
        local loadNorm = tonumber(runtime and runtime.loadNorm) or 0
        local physicalLoad = tonumber(runtime and runtime.physicalLoad)
        if physicalLoad == nil then
            physicalLoad = Utils.clamp(loadNorm / 2.8 * 100.0, 0, 100)
        end
        return {
            physicalLoad = physicalLoad,
            airflowResistance = tonumber(runtime and runtime.airflowResistance) or 0,
            sealedRestriction = tonumber(runtime and runtime.sealedRestriction) or 0,
            rigidityLoad = tonumber(runtime and runtime.rigidityLoad) or 0,
            driverCount = tonumber(runtime and runtime.driverCount) or (physicalLoad > 1 and 1 or 0),
        }
    end

    local function buildBreathingDescription(airflowResistance, sealedRestriction)
        local resistance = tonumber(airflowResistance) or 0
        if (tonumber(sealedRestriction) or 0) > 0 then
            return tr("UI_AMS_BreathingDesc_HeavyRestricted", "Severe breathing penalty")
        elseif resistance >= 2.00 then
            return tr("UI_AMS_BreathingDesc_Restricted", "Restricts airflow during exertion")
        end
        return tr("UI_AMS_BreathingDesc_Mild", "Slightly restricts airflow")
    end

    local function buildSleepWord(rigidityLoad)
        local rigidity = tonumber(rigidityLoad) or 0
        if rigidity < 10 then
            return nil
        end

        local rigidityNorm = rigidity / (rigidity + 80.0) * 2.0
        local sleepPct = math.floor(rigidityNorm * 6.75 + 0.5)
        if sleepPct < 1 then
            return nil
        end

        return string.format("~%d%% %s", sleepPct, tr("UI_AMS_Label_SleepLonger", "longer recovery"))
    end

    local function buildBurdenWords(profile)
        local burdenTier, burdenTierKey = burdenTierFromTotal(tonumber(profile and profile.physicalLoad) or 0)
        local breathingWord = breathingTierFromResistance(
            profile and profile.airflowResistance,
            profile and profile.sealedRestriction
        )
        local breathingDesc = nil
        if breathingWord then
            breathingDesc = buildBreathingDescription(
                profile and profile.airflowResistance,
                profile and profile.sealedRestriction
            )
        end
        local sleepWord = buildSleepWord(profile and profile.rigidityLoad)
        return burdenTier, burdenTierKey, breathingWord, breathingDesc, sleepWord
    end

    local function hasRenderableContent(data)
        return (type(data.summaryLines) == "table" and #data.summaryLines > 0)
            or data.showBurden
            or data.showThermal
            or data.showBreathing
            or data.showSleep
            or data.showDrivers
    end

    function AMSBurdenPanel:collectSnapshot(force)
        local player = self:resolvePlayer()
        if not player then
            self.snapshot = nil
            return
        end

        local nowMinute = tonumber(Utils.getWorldAgeMinutes()) or 0

        local refreshRuntime = force
            or self.needsRefresh
            or self.snapshot == nil
            or self.lastRuntimeRefreshMinute < 0
            or (nowMinute - self.lastRuntimeRefreshMinute) >= 0.5

        if not refreshRuntime then
            return
        end

        local state = ClientRuntime.ensureState(player)
        local options = UI._lastOptions or Options.get()
        local runtime = Physiology.getUiRuntimeSnapshot(player, state, options)
        local isMp = Utils.isMultiplayer()

        if isMp and type(runtime) ~= "table" then
            self.snapshot = {
                pendingSnapshot = true,
                profile = {
                    physicalLoad = 0,
                    airflowResistance = 0,
                    sealedRestriction = 0,
                    rigidityLoad = 0,
                    driverCount = 0,
                },
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
                summaryLines = {},
                showBurden = false,
                showThermal = false,
                showBreathing = false,
                showSleep = false,
                showDrivers = false,
                drivers = {},
            }
            self.lastRefreshMinute = nowMinute
            self.lastRuntimeRefreshMinute = nowMinute
            self.needsRefresh = false
            return
        end

        local profile = nil
        local burdenTier, burdenTierKey, breathingWord, breathingDesc, sleepWord = nil, nil, nil, nil, nil
        local costDrivers = {}
        local analysis = LoadModel.analyzeWornGear(player)
        if isMp then
            profile = buildProfileFromRuntime(runtime)
            costDrivers = resolveDriverLabelsForClient(analysis, runtime and runtime.drivers)
        else
            profile = analysis.profile
            costDrivers = analysis.costDrivers
        end
        burdenTier, burdenTierKey, breathingWord, breathingDesc, sleepWord = buildBurdenWords(profile)

        local thermalWord, thermalColor, thermalBurdensome, thermalAnnotation, thermalAnnotationColor = resolveThermalEffect(runtime)
        local physical = tonumber(profile.physicalLoad) or 0
        local driverCount = tonumber(profile.driverCount) or 0
        local noBurden = driverCount <= 0
        local compact = (not noBurden)
            and physical < 15
            and (not thermalBurdensome)
            and (not breathingWord)
        local heatSensitive = (not noBurden) and physical < 15 and thermalBurdensome
        local showBreathing = breathingWord ~= nil
        local showSleep = sleepWord ~= nil
        local showDrivers = #costDrivers > 0
        local showBurden = (not noBurden)
        local showThermal = shouldShowThermalBlock(thermalBurdensome, thermalAnnotation, showBurden, showBreathing, showSleep)
        local summaryLines = {}

        if noBurden then
            summaryLines[#summaryLines + 1] = {
                text = tr("UI_AMS_NoBurden", "No armor burden."),
                tone = "default",
            }
        elseif compact then
            summaryLines[#summaryLines + 1] = {
                text = tr("UI_AMS_LightMinimal", "Light clothing -- minimal burden."),
                tone = "default",
            }
        elseif heatSensitive then
            summaryLines[#summaryLines + 1] = {
                text = tr("UI_AMS_HeatSensitive", "Low weight, but heat-sensitive outfit."),
                tone = "warm",
            }
        end

        if not showBurden and not showBreathing and not showSleep and not thermalBurdensome and not thermalAnnotation then
            showThermal = false
        end

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
            summaryLines = summaryLines,
            showBurden = showBurden,
            showThermal = showThermal,
            showBreathing = showBreathing,
            showSleep = showSleep,
            showDrivers = showDrivers,
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
        local fontH = (tm and font) and (tonumber(ClientRuntime.safeMethod(tm, "getFontHeight", font)) or 18) or 18
        local lineH = fontH + 6
        local sectionGap = math.max(12, math.floor(lineH * 0.65))
        local x = 14
        local y = 14
        local measure = tm

        local labelCol = 0
        if measure then
            local labels = { "Burden:", "Thermal:", "Breathing:", "Sleep:" }
            for li = 1, #labels do
                local lw = tonumber(ClientRuntime.safeMethod(measure, "MeasureStringX", font, labels[li])) or 60
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

        if not hasRenderableContent(data) then
            self:drawText(tr("UI_AMS_LightMinimal", "Light clothing -- minimal burden."), x, y, cValue[1], cValue[2], cValue[3], 1.0, font)
            self:syncSizeToScreen(self.canonicalW or 480, y + lineH)
            return
        end

        local summaryLines = data.summaryLines or {}
        for i = 1, #summaryLines do
            local row = summaryLines[i]
            local color = cValue
            if row.tone == "warm" then
                color = { 1.0, 0.85, 0.55 }
            end
            self:drawText(tostring(row.text or ""), x, y, color[1], color[2], color[3], 1.0, font)
            y = y + lineH
        end

        local contentW = self.width - x - 14

        if #summaryLines > 0 then
            y = y + 4
        end

        local renderedPrimary = false

        if data.showBurden then
            drawLabelValue(self, font, x, y, tr("UI_AMS_Panel_Burden", "Burden") .. ":", cLabel, data.burdenTier, cValue, labelCol)
            y = y + lineH
            local profilePhysical = tonumber(data.profile and data.profile.physicalLoad) or 0
            local barH = math.max(8, math.floor(fontH * 0.6))
            drawBar(self, x, y, contentW, burdenBarFraction(profilePhysical), { 0.95, 0.70, 0.25 }, barH)
            y = y + barH + 8
            renderedPrimary = true
        end

        if data.showThermal then
            drawLabelValue(self, font, x, y, tr("UI_AMS_Panel_Thermal", "Thermal") .. ":", cLabel, data.thermalWord, data.thermalColor, labelCol)
            y = y + lineH
            if data.thermalAnnotation then
                local ac = data.thermalAnnotationColor or { cAnnotation[1], cAnnotation[2], cAnnotation[3], 0.90 }
                self:drawText(data.thermalAnnotation, x, y, ac[1], ac[2], ac[3], ac[4], font)
                y = y + lineH
            end
            renderedPrimary = true
        end

        if data.showBreathing then
            drawLabelValue(self, font, x, y, tr("UI_AMS_Panel_Breathing", "Breathing") .. ":", cLabel, data.breathingWord, { 1.0, 0.80, 0.40 }, labelCol)
            y = y + lineH
            if data.breathingDesc then
                self:drawText(data.breathingDesc, x, y, cAnnotation[1], cAnnotation[2], cAnnotation[3], 0.90, font)
                y = y + lineH
            end
            renderedPrimary = true
        end

        if data.showSleep then
            drawLabelValue(self, font, x, y, tr("UI_AMS_Panel_Sleep", "Sleep") .. ":", cLabel, data.sleepWord, cValue, labelCol)
            y = y + lineH
            renderedPrimary = true
        end

        local drivers = data.drivers or {}
        local maxRows = data.showDrivers and #drivers or 0
        if maxRows <= 0 then
            self:syncSizeToScreen(self.canonicalW or 480, y + lineH)
            return
        end

        -- Separator
        if renderedPrimary then
            y = y + sectionGap
        end
        self:drawRect(x, y, contentW, 1, 0.18, cSep[1], cSep[2], cSep[3])
        y = y + sectionGap

        -- Section: Cost Drivers
        self:drawText(tr("UI_AMS_Section_CostDrivers", "Cost Drivers"), x, y, cHeader[1], cHeader[2], cHeader[3], 1.0, font)
        y = y + lineH + 4
        local topPhysical = maxRows > 0 and (tonumber(drivers[1].physical) or 0) or 1

        local maxNameW = 0
        for i = 1, maxRows do
            local tw = measure and tonumber(ClientRuntime.safeMethod(measure, "MeasureStringX", font, drivers[i].label))
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
                local tw = tonumber(ClientRuntime.safeMethod(measure, "MeasureStringX", font, displayLabel)) or 0
                if tw > nameW then
                    local base = row.label
                    local len = string.len(base)
                    while len > 1 do
                        len = len - 1
                        displayLabel = string.sub(base, 1, len) .. "..."
                        tw = tonumber(ClientRuntime.safeMethod(measure, "MeasureStringX", font, displayLabel)) or 0
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
        { key = "UI_AMS_Help_Overview",        fallback = "Overview: Armor costs scale with activity. Standing still or walking costs almost nothing. Running, sprinting, and fighting is where heavy armor makes itself felt. The heavier your outfit, the faster you tire during exertion and the slower you recover afterward." },
        { key = "UI_AMS_Help_Burden",          fallback = "Burden: The total physical weight and bulk of your worn armor. The bar shows your current load on a fixed scale. Heavier loadouts drain endurance faster during running, sprinting, and melee combat. In heavy armor, your arms also tire faster per swing." },
        { key = "UI_AMS_Help_Thermal",         fallback = "Thermal: Insulating gear adds exertion cost only after your body remains hot long enough. Short temperature spikes fade without a penalty. In cold conditions, Helpful means the insulation suits the weather; AMS does not add a cold bonus. Vanilla clothing condition and wetness are included in the reading." },
        { key = "UI_AMS_Help_Breathing",       fallback = "Breathing: Respirators, gas masks, and other sealed headgear restrict airflow. This adds to your exertion cost during physical activity. The severity is shown as Mildly Restricted, Restricted, or Heavily Restricted depending on the gear." },
        { key = "UI_AMS_Help_Sleep",           fallback = "Sleep: Sleeping in rigid armor slows recovery. The percentage shows the estimated extra time needed to fully rest. Take off heavy gear before bed." },
        { key = "UI_AMS_Help_CostDrivers",     fallback = "Cost Drivers: Shows which worn items contribute most to your total burden, sorted by impact. If one item dominates the list, swapping it out will make the biggest difference." },
        { key = "UI_AMS_Help_ExportTitleDesc",  fallback = "Support Reports: If something feels wrong, use this to save a snapshot of your current loadout, burden calculations, mod list, and game state to a text file. Attach it when reporting a problem." },
    }

    local HELP_SECTION_GAP = 10
    local HELP_DIVIDER_GAP = 6
    local HELP_CONTENT_LEFT_PAD = 14
    local HELP_CONTENT_RIGHT_PAD = 20

    local function getHelpContentWidth(panelWidth)
        local scrollBarW = tonumber(_G.SCROLL_BAR_WIDTH) or 13
        return math.max(120, (tonumber(panelWidth) or 0) - HELP_CONTENT_LEFT_PAD - HELP_CONTENT_RIGHT_PAD - scrollBarW)
    end

    measureHelpText = function(wrapW, font, tm)
        local fontH = (tm and font) and (tonumber(ClientRuntime.safeMethod(tm, "getFontHeight", font)) or 18) or 18
        local lineH = fontH + 4
        local y = 10
        for i = 1, #helpSections do
            if i > 1 then
                y = y + HELP_DIVIDER_GAP + 1 + HELP_DIVIDER_GAP
            end
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
            y = y + HELP_SECTION_GAP
        end
        return y + 10
    end

    function AMSHelpPanel:createChildren()
        ISPanel.createChildren(self)
        self:addScrollBars()
        self:setScrollChildren(true)
    end

    function AMSHelpPanel:prerender()
        self:setStencilRect(0, 0, self.width, self.height)
        ISPanel.prerender(self)
        local font = UIFont and UIFont.Small or nil
        local tm = type(getTextManager) == "function" and getTextManager() or nil
        local wrapW = getHelpContentWidth(self.width)
        local textH = measureHelpText(wrapW, font, tm)
        self:setScrollHeight(textH)
    end

    function AMSHelpPanel:render()
        local font = UIFont and UIFont.Small or nil
        local tm = type(getTextManager) == "function" and getTextManager() or nil
        local fontH = (tm and font) and (tonumber(ClientRuntime.safeMethod(tm, "getFontHeight", font)) or 18) or 18
        local lineH = fontH + 4
        local wrapW = getHelpContentWidth(self.width)
        local x = HELP_CONTENT_LEFT_PAD
        local y = 10

        local cHeader = { 1.0, 0.90, 0.65 }
        local cBody = { 0.88, 0.85, 0.80 }
        local cDivider = { 0.30, 0.30, 0.30 }

        for i = 1, #helpSections do
            if i > 1 then
                y = y + HELP_DIVIDER_GAP
                self:drawRect(x, y, wrapW, 1, 0.25, cDivider[1], cDivider[2], cDivider[3])
                y = y + 1 + HELP_DIVIDER_GAP
            end
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
            y = y + HELP_SECTION_GAP
        end

        ISPanel.render(self)
        self:clearStencilRect()
    end

    if ISCollapsableWindow then
        AMSHelpWindow = ISCollapsableWindow:derive("AMSHelpWindow")

        function AMSHelpWindow:new(x, y, width, height)
            local window = ISCollapsableWindow:new(x, y, width, height)
            setmetatable(window, self)
            self.__index = self
            window.resizable = false
            local version = ClientRuntime.getLoadedModVersion()
            local versionTag = version and (" v" .. tostring(version)) or ""
            window.title = tr("UI_AMS_Help_Title", "Armor Makes Sense") .. versionTag
            return window
        end

        function AMSHelpWindow:createChildren()
            ISCollapsableWindow.createChildren(self)
            local titleBarH = 24
            pcall(function() titleBarH = self:titleBarHeight() end)
            self.helpPanel = AMSHelpPanel:new(0, titleBarH + 1, self.width, self.height - titleBarH - 1)
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
                ClientRuntime.logOnce("ui_burden_tab_fallback", "[UI] Burden tab injection failed; enabling standalone fallback window.")
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
    ClientRuntime.logOnce("ui_burden_tab_hook_installed", "[UI] Character info Burden tab hook installed.")

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

    UITooltip.install()
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
