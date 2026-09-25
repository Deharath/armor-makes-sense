ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Testing = ArmorMakesSense.Testing or {}

local Testing = ArmorMakesSense.Testing
Testing.BenchCurtain = Testing.BenchCurtain or {}

local BenchCurtain = Testing.BenchCurtain

pcall(require, "ISUI/ISPanel")
pcall(require, "ISUI/ISButton")

-- Full-screen panel raised over the HUD while a benchmark runs. Being "over UI"
-- keeps world hover, clicks, context menus and zoom away from the character.
-- Java still reads the aim key and the keyboard, so right-clicks and key
-- presses are reported as disturbances and the runner re-runs the step. It is
-- not always-on-top so the pause menu stays usable.

local STRIP_H = 46
local STOP_W = 84
local FONT_MEDIUM = UIFont and UIFont.Medium or "Medium"
local FONT_SMALL = UIFont and UIFont.Small or "Small"

local COLOR = {
    veil = { r = 0.0, g = 0.0, b = 0.0, a = 0.14 },
    strip = { r = 0.06, g = 0.06, b = 0.07, a = 0.88 },
    line = { r = 0.76, g = 0.65, b = 0.37, a = 0.90 },
    title = { r = 0.92, g = 0.92, b = 0.88, a = 1.00 },
    label = { r = 0.62, g = 0.65, b = 0.66, a = 1.00 },
    warn = { r = 0.91, g = 0.66, b = 0.28, a = 1.00 },
}

local curtain = nil
local keyHandler = nil

local function screenSize()
    local core = type(getCore) == "function" and getCore() or nil
    if not core then
        return 1024, 768
    end
    return tonumber(core:getScreenWidth()) or 1024, tonumber(core:getScreenHeight()) or 768
end

local function nowMs()
    return type(getTimestampMs) == "function" and tonumber(getTimestampMs()) or 0
end

local function formatDuration(ms)
    local total = math.max(0, math.floor((tonumber(ms) or 0) / 1000))
    local hours = math.floor(total / 3600)
    local minutes = math.floor((total % 3600) / 60)
    local seconds = total % 60
    if hours > 0 then
        return string.format("%d:%02d:%02d", hours, minutes, seconds)
    end
    return string.format("%d:%02d", minutes, seconds)
end

function BenchCurtain.describe(status, elapsedMs)
    if type(status) ~= "table" then
        return "Benchmark starting", nil
    end
    local completed = tonumber(status.completed) or 0
    local total = tonumber(status.total) or 0
    local title = string.format(
        "Benchmark %s  -  step %d/%d  -  %s / %s",
        tostring(status.preset or "?"),
        math.min(total, completed + 1),
        total,
        tostring(status.setId or "-"),
        tostring(status.scenarioId or "-")
    )
    if (tonumber(status.attempt) or 1) > 1 then
        title = title .. string.format("  (attempt %d)", tonumber(status.attempt))
    end
    local eta = nil
    if completed > 0 and total > completed and (tonumber(elapsedMs) or 0) > 0 then
        eta = (elapsedMs / completed) * (total - completed)
    end
    return title, eta
end

local AMSBenchCurtain = (ISPanel and type(ISPanel.derive) == "function")
    and ISPanel:derive("AMSBenchCurtain")
    or {}

function AMSBenchCurtain:new(hooks)
    local width, height = screenSize()
    local panel = ISPanel:new(0, 0, width, height)
    setmetatable(panel, self)
    self.__index = self
    panel.hooks = hooks or {}
    panel.backgroundColor = COLOR.veil
    panel.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    panel.moveWithMouse = false
    panel.startedMs = nowMs()
    return panel
end

function AMSBenchCurtain:createChildren()
    ISPanel.createChildren(self)
    self.stopButton = ISButton:new(self.width - STOP_W - 12, 12, STOP_W, 22, "Stop", self, AMSBenchCurtain.onStop)
    self.stopButton:initialise()
    self:addChild(self.stopButton)
end

function AMSBenchCurtain:onStop()
    if type(self.hooks.onStop) == "function" then
        self.hooks.onStop()
    end
end

function AMSBenchCurtain:render()
    ISPanel.render(self)
    self:drawRect(0, 0, self.width, STRIP_H, COLOR.strip.a, COLOR.strip.r, COLOR.strip.g, COLOR.strip.b)
    self:drawRect(0, STRIP_H, self.width, 1, COLOR.line.a, COLOR.line.r, COLOR.line.g, COLOR.line.b)

    local status = type(self.hooks.status) == "function" and self.hooks.status() or nil
    local elapsed = nowMs() - (tonumber(self.startedMs) or 0)
    local title, eta = BenchCurtain.describe(status, elapsed)
    self:drawText(title, 14, 5, COLOR.title.r, COLOR.title.g, COLOR.title.b, COLOR.title.a, FONT_MEDIUM)

    local timing = "elapsed " .. formatDuration(elapsed)
    if eta then
        timing = timing .. "   eta " .. formatDuration(eta)
    end
    self:drawTextRight(timing, self.width - STOP_W - 24, 16, COLOR.label.r, COLOR.label.g, COLOR.label.b, COLOR.label.a, FONT_SMALL)

    local disturbed = type(status) == "table" and status.disturbed or nil
    if disturbed then
        self:drawText("Input detected (" .. tostring(disturbed) .. "): this step will restart.", 14, 27, COLOR.warn.r, COLOR.warn.g, COLOR.warn.b, COLOR.warn.a, FONT_SMALL)
    else
        self:drawText("Hands off: the mouse is locked; key presses and right-clicks restart the current step.", 14, 27, COLOR.label.r, COLOR.label.g, COLOR.label.b, COLOR.label.a, FONT_SMALL)
    end
end

function AMSBenchCurtain:disturb(reason)
    if type(self.hooks.onDisturb) == "function" then
        self.hooks.onDisturb(reason)
    end
end

function AMSBenchCurtain:onMouseDown()
    return true
end

function AMSBenchCurtain:onMouseUp()
    return true
end

function AMSBenchCurtain:onRightMouseDown()
    self:disturb("right_click")
    return true
end

function AMSBenchCurtain:onRightMouseUp()
    return true
end

function AMSBenchCurtain:onMouseWheel()
    return true
end

function AMSBenchCurtain:onMouseMove()
    return true
end

function BenchCurtain.show(hooks)
    if curtain then
        curtain.hooks = hooks or {}
        return true
    end
    if AMSBenchCurtain.Type == nil and ISPanel and type(ISPanel.derive) == "function" then
        local methods = AMSBenchCurtain
        AMSBenchCurtain = ISPanel:derive("AMSBenchCurtain")
        for key, value in pairs(methods) do
            AMSBenchCurtain[key] = value
        end
    end
    if not ISPanel or not ISButton or type(AMSBenchCurtain.new) ~= "function" then
        print("[ArmorMakesSense][DEV][ERROR] bench curtain requires ISPanel and ISButton")
        return false
    end
    curtain = AMSBenchCurtain:new(hooks)
    curtain:initialise()
    curtain:addToUIManager()
    curtain:bringToTop()
    keyHandler = function(key)
        if curtain then
            curtain:disturb("key_" .. tostring(key))
        end
    end
    Events.OnKeyPressed.Add(keyHandler)
    return true
end

function BenchCurtain.hide()
    if keyHandler then
        Events.OnKeyPressed.Remove(keyHandler)
        keyHandler = nil
    end
    if not curtain then
        return false
    end
    curtain:setVisible(false)
    curtain:removeFromUIManager()
    curtain = nil
    return true
end

function BenchCurtain.isVisible()
    return curtain ~= nil
end

return BenchCurtain
