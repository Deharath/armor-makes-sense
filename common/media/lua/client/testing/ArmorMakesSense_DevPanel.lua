ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Testing = ArmorMakesSense.Testing or {}

local Testing = ArmorMakesSense.Testing
Testing.DevPanel = Testing.DevPanel or {}

local DevPanel = Testing.DevPanel
local C = {}
local panelInstance = nil
local initialized = false

pcall(require, "ISUI/ISPanel")
pcall(require, "ISUI/ISButton")
pcall(require, "ISUI/ISComboBox")

local PANEL_W = 780
local PANEL_H = 540
local PAD = 14
local DIVIDER_X = 382
local TOOLS_X = 398
local TOOLS_W = PANEL_W - TOOLS_X - PAD
local ROW_H = 18
local BUTTON_H = 22

local FONT_MEDIUM = UIFont and UIFont.Medium or "Medium"
local FONT_SMALL = UIFont and UIFont.Small or "Small"

local COLOR = {
    bg = { r = 0.07, g = 0.07, b = 0.08, a = 0.96 },
    border = { r = 0.42, g = 0.48, b = 0.50, a = 0.78 },
    header = { r = 0.92, g = 0.92, b = 0.88, a = 1.00 },
    section = { r = 0.76, g = 0.65, b = 0.37, a = 1.00 },
    label = { r = 0.62, g = 0.65, b = 0.66, a = 1.00 },
    value = { r = 0.92, g = 0.94, b = 0.94, a = 1.00 },
    good = { r = 0.48, g = 0.78, b = 0.50, a = 1.00 },
    warn = { r = 0.91, g = 0.66, b = 0.28, a = 1.00 },
    bad = { r = 0.88, g = 0.38, b = 0.31, a = 1.00 },
    dim = { r = 0.43, g = 0.46, b = 0.47, a = 0.85 },
    line = { r = 0.30, g = 0.32, b = 0.33, a = 0.70 },
}

local function ctx(name)
    return C[name]
end

local function safeInvoke(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, a, b, c = pcall(fn, ...)
    if not ok then
        return nil, tostring(a)
    end
    return a, b, c
end

local function safeValue(fn, ...)
    local value = safeInvoke(fn, ...)
    return value
end

local function copySortedDrivers(drivers)
    local out = {}
    for i = 1, #(drivers or {}) do
        out[#out + 1] = drivers[i]
    end
    table.sort(out, function(a, b)
        return (tonumber(a and a.physical) or 0) > (tonumber(b and b.physical) or 0)
    end)
    return out
end

function DevPanel.setContext(context)
    C = context or {}
end

function DevPanel.buildSnapshot()
    local player = safeInvoke(ctx("getLocalPlayer"))
    if not player then
        return nil
    end

    local multiplayer = safeInvoke(ctx("isMultiplayer")) == true
    local state = safeInvoke(ctx("getRuntimeState"), player) or {}
    local hasAuthoritativeSnapshot = multiplayer and type(state.mpServerSnapshot) == "table"
    local options = safeInvoke(ctx("getOptions")) or {}
    local runtime = safeInvoke(ctx("getUiRuntimeSnapshot"), player, state, options) or {}
    local analysis = safeInvoke(ctx("analyzeWornGear"), player) or {}
    local localProfile = analysis.profile or safeInvoke(ctx("computeWornProfile"), player) or {}
    local profile = localProfile
    if hasAuthoritativeSnapshot and next(runtime) ~= nil then
        profile = {
            physicalLoad = runtime.physicalLoad,
            thermalResistance = runtime.thermalResistance,
            airflowResistance = runtime.airflowResistance,
            sealedRestriction = runtime.sealedRestriction,
            rigidityLoad = runtime.rigidityLoad,
            driverCount = runtime.driverCount,
        }
    end
    local rawRuntime = multiplayer and state.mpServerSnapshot or state.uiRuntimeSnapshot
    rawRuntime = type(rawRuntime) == "table" and rawRuntime or runtime
    local nowMinute = tonumber(safeValue(ctx("getWorldAgeMinutes"))) or 0
    local updatedMinute = tonumber(runtime.updatedMinute)

    return {
        player = player,
        multiplayer = multiplayer,
        source = hasAuthoritativeSnapshot and "MP SERVER" or (multiplayer and "MP WAIT" or "SP LOCAL"),
        hasAuthoritativeSnapshot = hasAuthoritativeSnapshot,
        state = state,
        runtime = runtime,
        rawRuntime = rawRuntime,
        profile = profile,
        localProfile = localProfile,
        drivers = copySortedDrivers(hasAuthoritativeSnapshot and runtime.drivers or analysis.costDrivers),
        endurance = tonumber(safeValue(ctx("getEndurance"), player)),
        fatigue = tonumber(safeValue(ctx("getFatigue"), player)),
        bodyTemp = tonumber(safeValue(ctx("getBodyTemperature"), player)),
        wetness = tonumber(safeValue(ctx("getWetness"), player)),
        snapshotAgeMinutes = updatedMinute and math.max(0, nowMinute - updatedMinute) or nil,
        testLock = state.testLock,
        bench = state.benchRunner,
    }
end

local function shortText(value, maxLength)
    local text = tostring(value or "--")
    local limit = tonumber(maxLength) or 28
    if #text <= limit then
        return text
    end
    return string.sub(text, 1, math.max(1, limit - 3)) .. "..."
end

local function formatNumber(value, decimals)
    local number = tonumber(value)
    if number == nil then
        return "--"
    end
    return string.format("%." .. tostring(decimals or 3) .. "f", number)
end

local function formatPercent(value)
    local number = tonumber(value)
    if number == nil then
        return "--"
    end
    return string.format("%.1f%%", number * 100)
end

local function screenWidth()
    local core = type(getCore) == "function" and getCore() or nil
    return tonumber(core and safeValue(core.getScreenWidth, core)) or 1024
end

local function screenHeight()
    local core = type(getCore) == "function" and getCore() or nil
    return tonumber(core and safeValue(core.getScreenHeight, core)) or 768
end

local AMSDevOverlay = (ISPanel and type(ISPanel.derive) == "function")
    and ISPanel:derive("AMSDevOverlay")
    or {}

function AMSDevOverlay:new(x, y)
    local panel = ISPanel:new(x, y, PANEL_W, PANEL_H)
    setmetatable(panel, self)
    self.__index = self
    panel.backgroundColor = COLOR.bg
    panel.borderColor = COLOR.border
    panel.statusText = "Live values update continuously."
    panel.statusColor = COLOR.dim
    panel.spOnlyControls = {}
    panel.snapshotCache = nil
    panel.snapshotFrames = 0
    return panel
end

function AMSDevOverlay:initialise()
    ISPanel.initialise(self)
end

local function addButton(panel, x, y, width, title, callback, internal, tooltip)
    local button = ISButton:new(x, y, width, BUTTON_H, title, panel, callback)
    button:initialise()
    button.internal = internal
    if tooltip and type(button.setTooltip) == "function" then
        button:setTooltip(tooltip)
    end
    panel:addChild(button)
    return button
end

local function addCombo(panel, x, y, width, options)
    local combo = ISComboBox:new(x, y, width, BUTTON_H, panel, AMSDevOverlay.onComboChanged)
    combo:initialise()
    panel:addChild(combo)
    for i = 1, #(options or {}) do
        local value = tostring(options[i])
        combo:addOptionWithData(value, value)
    end
    if #(options or {}) > 0 then
        combo.selected = 1
    end
    return combo
end

function AMSDevOverlay:createChildren()
    ISPanel.createChildren(self)

    self.closeButton = addButton(self, PANEL_W - 29, 5, 23, "X", AMSDevOverlay.onClose)

    local buttonGap = 6
    local fourButtonW = math.floor((TOOLS_W - buttonGap * 3) / 4)
    local y = 88
    local environments = {
        { title = "Neutral", args = nil },
        { title = "Hot", args = { 39.0, 0, 120 } },
        { title = "Cold", args = { 35.0, 0, 120 } },
        { title = "Wet", args = { 37.0, 100, 120 } },
    }
    for i = 1, #environments do
        local spec = environments[i]
        local button = addButton(
            self,
            TOOLS_X + (i - 1) * (fourButtonW + buttonGap),
            y,
            fourButtonW,
            spec.title,
            AMSDevOverlay.onEnvironment,
            spec.args
        )
        self.spOnlyControls[#self.spOnlyControls + 1] = button
    end

    y = 151
    local twoButtonW = math.floor((TOOLS_W - buttonGap) / 2)
    local reset = addButton(self, TOOLS_X, y, twoButtonW, "Reset equilibrium", AMSDevOverlay.onReset)
    self.spOnlyControls[#self.spOnlyControls + 1] = reset
    addButton(self, TOOLS_X + twoButtonW + buttonGap, y, twoButtonW, "Write mark", AMSDevOverlay.onMark)
    y = y + BUTTON_H + buttonGap
    addButton(self, TOOLS_X, y, twoButtonW, "Probe current gear", AMSDevOverlay.onProbe)
    addButton(self, TOOLS_X + twoButtonW + buttonGap, y, twoButtonW, "Export report", AMSDevOverlay.onReport)

    local profiles = safeInvoke(ctx("listBuiltInGearProfiles")) or {}
    self.gearCombo = addCombo(self, TOOLS_X, 247, TOOLS_W, profiles)
    local gearWear = addButton(self, TOOLS_X, 275, 112, "Wear virtual", AMSDevOverlay.onWearGear)
    local gearClear = addButton(self, TOOLS_X + 118, 275, 94, "Clear", AMSDevOverlay.onClearGear)
    local gearSave = addButton(self, TOOLS_X + 218, 275, TOOLS_W - 218, "Save current", AMSDevOverlay.onSaveGear)
    self.spOnlyControls[#self.spOnlyControls + 1] = gearWear
    self.spOnlyControls[#self.spOnlyControls + 1] = gearClear
    self.spOnlyControls[#self.spOnlyControls + 1] = gearSave

    local presets = safeInvoke(ctx("listBenchPresetIds")) or {}
    self.benchCombo = addCombo(self, TOOLS_X, 337, TOOLS_W, presets)
    local benchRun = addButton(self, TOOLS_X, 365, twoButtonW, "Run benchmark", AMSDevOverlay.onRunBench)
    local benchStop = addButton(self, TOOLS_X + twoButtonW + buttonGap, 365, twoButtonW, "Stop benchmark", AMSDevOverlay.onStopBench)
    self.spOnlyControls[#self.spOnlyControls + 1] = benchRun
    self.spOnlyControls[#self.spOnlyControls + 1] = benchStop
end

function AMSDevOverlay:onComboChanged()
end

function AMSDevOverlay:setStatus(text, color)
    self.statusText = tostring(text or "")
    self.statusColor = color or COLOR.dim
end

function AMSDevOverlay:runCommand(label, methodName, ...)
    local commands = ctx("Commands")
    local method = commands and commands[methodName]
    if type(method) ~= "function" then
        self:setStatus(label .. " unavailable", COLOR.bad)
        return false
    end
    local ok, result = pcall(method, ...)
    if not ok or result == false then
        self:setStatus(label .. " failed", COLOR.bad)
        return false
    end
    self:setStatus(label .. " complete", COLOR.good)
    self.snapshotCache = nil
    self.snapshotFrames = 0
    return true
end

function AMSDevOverlay:onEnvironment(button)
    local args = button and button.internal
    if args == nil then
        self:runCommand("Environment unlock", "testUnlock")
        return
    end
    self:runCommand(button.title or "Environment lock", "lockEnv", args[1], args[2], args[3])
end

function AMSDevOverlay:onReset()
    self:runCommand("Equilibrium reset", "resetEquilibrium")
end

function AMSDevOverlay:onMark()
    self:runCommand("Debug mark", "mark", "dev-panel")
end

function AMSDevOverlay:onProbe()
    self:runCommand("Gear probe", "uiProbeCurrentGear")
end

function AMSDevOverlay:onReport()
    local player = safeValue(ctx("getLocalPlayer"))
    local ok, path, err = safeInvoke(ctx("writeSupportReport"), player)
    if ok == true then
        self:setStatus("Report: " .. shortText(path, 42), COLOR.good)
    else
        self:setStatus(tostring(err or "Report export failed"), COLOR.bad)
    end
end

local function selectedData(combo)
    if not combo or not combo.selected or type(combo.getOptionData) ~= "function" then
        return nil
    end
    return combo:getOptionData(combo.selected)
end

function AMSDevOverlay:onWearGear()
    local profile = selectedData(self.gearCombo)
    if not profile then
        self:setStatus("No gear profile selected", COLOR.warn)
        return
    end
    self:runCommand("Wore " .. tostring(profile), "gearWear", profile, "virtual")
end

function AMSDevOverlay:onClearGear()
    self:runCommand("Gear clear", "gearClear")
end

function AMSDevOverlay:onSaveGear()
    self:runCommand("Saved current gear", "gearSave", "dev_panel")
end

function AMSDevOverlay:onRunBench()
    local preset = selectedData(self.benchCombo)
    if not preset then
        self:setStatus("No benchmark selected", COLOR.warn)
        return
    end
    self:runCommand("Started " .. tostring(preset), "benchRun", preset, nil)
end

function AMSDevOverlay:onStopBench()
    self:runCommand("Benchmark stop", "benchStop")
end

function AMSDevOverlay:onClose()
    DevPanel.hide()
end

local function drawSection(self, x, y, width, title)
    self:drawText(title, x, y, COLOR.section.r, COLOR.section.g, COLOR.section.b, COLOR.section.a, FONT_SMALL)
    self:drawRect(x, y + 16, width, 1, COLOR.line.a, COLOR.line.r, COLOR.line.g, COLOR.line.b)
    return y + 22
end

local function drawPair(self, x, y, width, leftLabel, leftValue, rightLabel, rightValue, valueColor)
    local half = math.floor(width / 2)
    local vc = valueColor or COLOR.value
    self:drawText(leftLabel, x, y, COLOR.label.r, COLOR.label.g, COLOR.label.b, COLOR.label.a, FONT_SMALL)
    self:drawTextRight(tostring(leftValue), x + half - 8, y, vc.r, vc.g, vc.b, vc.a, FONT_SMALL)
    self:drawText(rightLabel, x + half + 4, y, COLOR.label.r, COLOR.label.g, COLOR.label.b, COLOR.label.a, FONT_SMALL)
    self:drawTextRight(tostring(rightValue), x + width, y, vc.r, vc.g, vc.b, vc.a, FONT_SMALL)
    return y + ROW_H
end

local function drawLiveData(self, snapshot)
    local x = PAD
    local width = DIVIDER_X - PAD * 2
    local y = 42
    if not snapshot then
        self:drawText("Waiting for local player...", x, y, COLOR.dim.r, COLOR.dim.g, COLOR.dim.b, COLOR.dim.a, FONT_SMALL)
        return
    end

    local runtime = snapshot.runtime or {}
    local raw = snapshot.rawRuntime or {}
    local profile = snapshot.profile or {}
    local age = snapshot.snapshotAgeMinutes
    local ageColor = age == nil and COLOR.warn or (age > 5 and COLOR.warn or COLOR.good)
    local thermalState = runtime.thermalUiState or raw.thermalUiState
    if not thermalState then
        thermalState = (tonumber(runtime.hotPressure) or 0) > 0.24 and "hot"
            or ((tonumber(runtime.coldSuitability) or 0) > 0.45 and "cold" or "neutral")
    end

    y = drawSection(self, x, y, width, "Runtime")
    y = drawPair(self, x, y, width, "Source", snapshot.source, "Age", age and formatNumber(age, 1) .. "m" or "--", ageColor)
    y = drawPair(self, x, y, width, "Activity", shortText(runtime.activityLabel, 12), "Heat scale", formatNumber(runtime.thermalStrainScale, 3))
    y = drawPair(self, x, y, width, "Thermal", shortText(thermalState, 10), "Updated", formatNumber(runtime.updatedMinute, 1))

    y = drawSection(self, x, y + 3, width, "Player")
    y = drawPair(self, x, y, width, "Endurance", formatPercent(snapshot.endurance), "Fatigue", formatPercent(snapshot.fatigue))
    y = drawPair(self, x, y, width, "Body temp", formatNumber(snapshot.bodyTemp, 2) .. " C", "Wetness", formatNumber(snapshot.wetness, 1))

    y = drawSection(self, x, y + 3, width, snapshot.hasAuthoritativeSnapshot and "Burden (server)" or "Burden (local)")
    y = drawPair(self, x, y, width, "Physical", formatNumber(profile.physicalLoad, 3), "Resistance", formatNumber(runtime.thermalResistance, 3))
    y = drawPair(self, x, y, width, "Airflow", formatNumber(profile.airflowResistance, 3), "Sealed", formatNumber(profile.sealedRestriction, 3))
    y = drawPair(self, x, y, width, "Rigidity", formatNumber(profile.rigidityLoad, 3), "Drivers", tostring(profile.driverCount or 0))
    y = drawPair(self, x, y, width, "Effective", formatNumber(runtime.effectiveLoad, 3), "Normalized", formatNumber(runtime.loadNorm, 3))
    y = drawSection(self, x, y + 3, width, "Applied effects")
    y = drawPair(self, x, y, width, "Thermal add", formatNumber(raw.thermalContribution, 4), "Breathing", formatNumber(raw.breathingContribution, 4))
    y = drawPair(self, x, y, width, "MET rate", formatNumber(raw.metabolicRate, 3), "MET demand", formatNumber(raw.metabolicDemand, 3))
    y = drawPair(self, x, y, width, "Effort norm", formatNumber(raw.metabolicNorm, 3), "Effort ramp", formatNumber(raw.breathingEffortRamp, 3))
    y = drawPair(self, x, y, width, "Open load", formatNumber(raw.breathingDynamicLoad, 3), "Sealed load", formatNumber(raw.breathingSealedLoad, 3))
    y = drawPair(self, x, y, width, "Hot pressure", formatNumber(runtime.hotPressure, 3), "Cold fit", formatNumber(runtime.coldSuitability, 3))
    y = drawPair(self, x, y, width, "Natural dE", formatNumber(raw.enduranceNaturalDelta, 5), "AMS dE", formatNumber(raw.enduranceAppliedDelta, 5))
    y = drawPair(self, x, y, width, "Regen scale", formatNumber(raw.composedEnduranceRegenScale, 3), "AMS drain", formatNumber(raw.amsEnduranceDrainApplied, 5))
    y = drawPair(self, x, y, width, "Sleep loss", formatNumber(snapshot.state.lastSleepPenaltyFraction, 3), "Wake adj", formatNumber(snapshot.state.lastSleepWakeAdjustment, 4))

    y = drawSection(self, x, y + 3, width, "Top physical drivers")
    if #snapshot.drivers == 0 then
        self:drawText("None", x, y, COLOR.dim.r, COLOR.dim.g, COLOR.dim.b, COLOR.dim.a, FONT_SMALL)
    else
        for i = 1, math.min(4, #snapshot.drivers) do
            local driver = snapshot.drivers[i]
            self:drawText(tostring(i) .. ". " .. shortText(driver.label or driver.fullType, 31), x, y, COLOR.label.r, COLOR.label.g, COLOR.label.b, COLOR.label.a, FONT_SMALL)
            self:drawTextRight(formatNumber(driver.physical, 3), x + width, y, COLOR.value.r, COLOR.value.g, COLOR.value.b, COLOR.value.a, FONT_SMALL)
            y = y + ROW_H
        end
    end
end

local function lockSummary(snapshot)
    local lock = snapshot and snapshot.testLock
    if type(lock) ~= "table" or not lock.mode then
        return "Environment lock: off"
    end
    return string.format(
        "Environment lock: %.2f C / %.0f wet",
        tonumber(lock.bodyTemp) or 37,
        tonumber(lock.wetness) or 0
    )
end

local function benchSummary(snapshot)
    local bench = snapshot and snapshot.bench
    if type(bench) ~= "table" or bench.active ~= true then
        return "Benchmark: idle"
    end
    return string.format(
        "Benchmark: %s  %d/%d",
        shortText(bench.preset or bench.id, 24),
        tonumber(bench.index) or 0,
        tonumber(bench.total) or 0
    )
end

function AMSDevOverlay:render()
    ISPanel.render(self)
    self.snapshotFrames = (tonumber(self.snapshotFrames) or 0) + 1
    if not self.snapshotCache or self.snapshotFrames >= 10 then
        self.snapshotCache = DevPanel.buildSnapshot()
        self.snapshotFrames = 0
    end
    local snapshot = self.snapshotCache
    local multiplayer = snapshot and snapshot.multiplayer == true

    self:drawText("Armor Makes Sense", PAD, 8, COLOR.header.r, COLOR.header.g, COLOR.header.b, COLOR.header.a, FONT_MEDIUM)
    self:drawText("developer", 153, 11, COLOR.dim.r, COLOR.dim.g, COLOR.dim.b, COLOR.dim.a, FONT_SMALL)
    self:drawRect(DIVIDER_X, 36, 1, PANEL_H - 48, COLOR.line.a, COLOR.line.r, COLOR.line.g, COLOR.line.b)
    drawLiveData(self, snapshot)

    self:drawText(shortText(self.statusText, 46), TOOLS_X, 42, self.statusColor.r, self.statusColor.g, self.statusColor.b, self.statusColor.a, FONT_SMALL)
    drawSection(self, TOOLS_X, 66, TOOLS_W, "Environment presets")
    drawSection(self, TOOLS_X, 129, TOOLS_W, "Character and inspection")
    drawSection(self, TOOLS_X, 225, TOOLS_W, "Gear profiles")
    drawSection(self, TOOLS_X, 315, TOOLS_W, "Benchmarks")
    drawSection(self, TOOLS_X, 405, TOOLS_W, "Development state")
    self:drawText(lockSummary(snapshot), TOOLS_X, 429, COLOR.label.r, COLOR.label.g, COLOR.label.b, COLOR.label.a, FONT_SMALL)
    self:drawText(benchSummary(snapshot), TOOLS_X, 449, COLOR.label.r, COLOR.label.g, COLOR.label.b, COLOR.label.a, FONT_SMALL)
    local modeText = multiplayer and "MP telemetry only; state-changing tools disabled" or "Singleplayer tools enabled"
    local modeColor = multiplayer and COLOR.warn or COLOR.good
    self:drawText(modeText, TOOLS_X, 469, modeColor.r, modeColor.g, modeColor.b, modeColor.a, FONT_SMALL)

    for i = 1, #self.spOnlyControls do
        local control = self.spOnlyControls[i]
        if type(control.setEnable) == "function" then
            control:setEnable(not multiplayer)
        else
            control.enable = not multiplayer
        end
    end
end

function AMSDevOverlay:onMouseDown(x, y)
    if y <= 32 then
        self.moving = true
        self.moveOffsetX = x
        self.moveOffsetY = y
    end
    return true
end

function AMSDevOverlay:onMouseUp()
    self.moving = false
    return true
end

function AMSDevOverlay:onMouseMove(dx, dy)
    if self.moving then
        self:setX(self:getX() + dx)
        self:setY(self:getY() + dy)
    end
    return true
end

function AMSDevOverlay:onMouseMoveOutside(dx, dy)
    return self:onMouseMove(dx, dy)
end

function DevPanel.show()
    if panelInstance and panelInstance:isVisible() then
        return true
    end
    if not AMSDevOverlay.__index and ISPanel and type(ISPanel.derive) == "function" then
        local methods = {}
        for key, value in pairs(AMSDevOverlay) do
            methods[key] = value
        end
        AMSDevOverlay = ISPanel:derive("AMSDevOverlay")
        for key, value in pairs(methods) do
            AMSDevOverlay[key] = value
        end
    end
    if not ISPanel or not ISButton or not ISComboBox or type(AMSDevOverlay.new) ~= "function" then
        print("[ArmorMakesSense][DEV][ERROR] developer panel requires ISPanel, ISButton, and ISComboBox")
        return false
    end

    local x = math.max(20, screenWidth() - PANEL_W - 30)
    local y = math.max(30, math.min(70, screenHeight() - PANEL_H - 20))
    panelInstance = AMSDevOverlay:new(x, y)
    panelInstance:initialise()
    panelInstance:addToUIManager()
    panelInstance:setVisible(true)
    return true
end

function DevPanel.hide()
    if not panelInstance then
        return false
    end
    panelInstance:setVisible(false)
    panelInstance:removeFromUIManager()
    panelInstance = nil
    return true
end

function DevPanel.toggle()
    if panelInstance and panelInstance:isVisible() then
        return DevPanel.hide()
    end
    return DevPanel.show()
end

function DevPanel.isVisible()
    return panelInstance ~= nil and panelInstance:isVisible()
end

local function onFillWorldObjectContextMenu(_, context, _, test)
    if test then
        return true
    end
    if context and type(context.addDebugOption) == "function" then
        context:addDebugOption("AMS Developer", nil, DevPanel.toggle)
    elseif context and type(context.addOption) == "function" then
        context:addOption("AMS Developer", nil, DevPanel.toggle)
    end
end

function DevPanel.initialize()
    if initialized then
        return true
    end
    _G.AMS_DevPanel = function()
        return DevPanel.toggle()
    end
    if Events and Events.OnFillWorldObjectContextMenu
        and type(Events.OnFillWorldObjectContextMenu.Add) == "function" then
        Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
    end
    initialized = true
    return true
end

return DevPanel
