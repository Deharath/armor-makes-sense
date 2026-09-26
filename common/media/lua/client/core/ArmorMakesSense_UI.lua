ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Core = ArmorMakesSense.Core or {}

local Core = ArmorMakesSense.Core
Core.UI = Core.UI or {}

local BurdenPanel = require "core/ArmorMakesSense_BurdenPanel"
local ClientRuntime = require "core/ArmorMakesSense_ClientRuntime"
local UITooltip = require "core/ArmorMakesSense_UITooltip"
local Draw = require "core/ArmorMakesSense_Draw"
local Utils = require "ArmorMakesSense_UtilsShared"

local UI = Core.UI

local tabHookInstalled = false
local tabHookFailed = false
local fallbackWindow = nil
local helpWindow = nil
local pendingUiRefresh = true
local previousUiHandlers = UI._eventHandlers or {}
UI._eventHandlers = {}

local function removeEventHandler(eventName, handler)
    local event = Events and Events[eventName] or nil
    if event and type(event.Remove) == "function" and type(handler) == "function" then
        pcall(event.Remove, handler)
    end
end

for eventName, handler in pairs(previousUiHandlers) do
    removeEventHandler(eventName, handler)
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

local function getCharacterInfoWindow(playerNum)
    if type(_G.getPlayerData) ~= "function" then
        return nil
    end
    local ok, playerData = pcall(_G.getPlayerData, tonumber(playerNum) or 0)
    if not ok or not playerData then
        return nil
    end
    return playerData.characterInfo
end

-- -----------------------------------------------------------------------------
-- Burden refresh hook
-- -----------------------------------------------------------------------------

local function markUiDirty()
    pendingUiRefresh = true
    if fallbackWindow and fallbackWindow.panel and type(fallbackWindow.panel.markDirty) == "function" then
        fallbackWindow.panel:markDirty()
    end
    for playerNum = 0, 3 do
        local existing = getCharacterInfoWindow(playerNum)
        if existing and existing._amsBurdenPanel and type(existing._amsBurdenPanel.markDirty) == "function" then
            existing._amsBurdenPanel:markDirty()
        end
    end
end

local function installClothingUpdateHook()
    if UI._eventHandlers.OnClothingUpdated then
        return
    end
    if not (Events and Events.OnClothingUpdated and type(Events.OnClothingUpdated.Add) == "function") then
        return
    end

    local handler = function(changedPlayer)
        if changedPlayer
            and Utils.isMultiplayer()
            and not ClientRuntime.isLocalPlayer(changedPlayer) then
            return
        end
        markUiDirty()
    end
    Events.OnClothingUpdated.Add(handler)
    UI._eventHandlers.OnClothingUpdated = handler
end

-- -----------------------------------------------------------------------------
-- Panel / tab rendering + help window
-- -----------------------------------------------------------------------------

local measureHelpText = nil
local toggleHelpWindow = nil
local AMSHelpPanel = nil
local AMSHelpWindow = nil
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
    if AMSHelpPanel or not ISPanel then
        return
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
        { key = "UI_AMS_Help_Overview", fallback = "What it does: Worn gear has a physical cost. Its weight, bulk, trapped heat and restricted breathing change how fast endurance drains and recovers, how fast sleep clears fatigue and how quickly you swing, all compared with wearing nothing. Protection and carry weight stay vanilla, and armor no longer builds discomfort: its bulk counts toward Load instead." },
        { key = "UI_AMS_Help_Reading", fallback = "Reading the tab: The top line is the one thing worth knowing right now. Each row names a cost and its pips show how strong it is. Hover a ? for how that row works, hover a row to see the gear behind it on the body map, and hover a body part to see what sits there." },
        { key = "UI_AMS_Help_Armor", fallback = "Armor buttons: Take Off Armor moves your stiff gear into your inventory and remembers the set. Drop Armor puts it on the floor instead. Wear Armor puts exactly those pieces back on, from your bags or the floor next to you." },
        { key = "UI_AMS_Help_Tips", fallback = "Tips: Sit down to recover, since weight never slows recovery while seated. Shed a layer when you run hot, take masks off when the air is clean, and take armor off before sleeping. Leg and foot armor costs the most for its weight." },
        { key = "UI_AMS_Help_Sandbox", fallback = "Sandbox options: One scale sets how heavy gear feels overall, and the heat, breathing, arm strain and sleep effects can each be turned off." },
        { key = "UI_AMS_Help_Modded", fallback = "Modded gear: Clothing and armor from other mods are rated automatically from their weight, slot and vanilla stats." },
        { key = "UI_AMS_Help_ExportTitleDesc", fallback = "Support reports: If something feels wrong, save a snapshot of your loadout, burden calculations, mod list and game state to a text file, and attach it when reporting a problem." },
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
                local lines = Draw.wrap(font, body, wrapW)
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
                local lines = Draw.wrap(font, body, wrapW)
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
            window.resizable = false
            window.title = tr("UI_AMS_Tab_Burden", "Burden")
            window.panel = nil
            return window
        end

        function AMSBurdenWindow:createChildren()
            ISCollapsableWindow.createChildren(self)
            self.panel = BurdenPanel.new(8, 24, self.width - 16, self.height - 32, self.playerNum)
            self.panel.isStandalone = true
            self.panel:initialise()
            self.panel:instantiate()
            self.panel:setAnchorBottom(false)
            self:addChild(self.panel)
        end
    end
end

BurdenPanel.onHelp = function()
    ensurePanelClasses()
    toggleHelpWindow()
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

local function hideFallbackWindow()
    if fallbackWindow and type(fallbackWindow.setVisible) == "function" then
        fallbackWindow:setVisible(false)
    end
end

-- Vanilla sizes its views to at least the width of its own five tabs. With
-- Burden (or any other mod's tab) added, narrower views would overflow the
-- strip into scroll arrows. Every vanilla view keeps max(self.width, content)
-- (Health keeps tabtotalwidth), so raising the floor once is enough.
local function fitViewsToTabStrip(screen)
    local host = screen._amsBurdenTabHost
    if not (host and type(host.viewList) == "table" and type(host.getWidthOfAllTabs) == "function") then
        return
    end
    local minW = host:getWidthOfAllTabs() + 2
    if screen._amsTabStripWidth == minW then
        return
    end
    screen._amsTabStripWidth = minW
    local spacing = (tonumber(_G.UI_BORDER_SPACING) or 10) + 1
    for _, entry in ipairs(host.viewList) do
        local view = entry.view
        if view and view ~= screen._amsBurdenPanel then
            if tonumber(view.tabtotalwidth) then
                view.tabtotalwidth = math.max(view.tabtotalwidth, minW - spacing)
            end
            if (tonumber(view.width) or 0) < minW and type(view.setWidth) == "function" then
                view:setWidth(minW)
            end
        end
    end
    host.scrollX, host.smoothScrollX, host.smoothScrollTargetX = 0, 0, nil
end

local function attachBurdenTabToScreen(screen)
    ensurePanelClasses()
    if not ISPanel then
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
            local panel = BurdenPanel.new(0, 0, hostW, hostH, screen.playerNum or 0)
            panel:initialise()
            panel:instantiate()

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
                screen._amsBurdenTabHost = host
                fitViewsToTabStrip(screen)
                return true
            end
        end
    end

    return false, "character info tabs container unavailable"
end

local function getLiveCharacterInfoWindow(player)
    local playerNum = tonumber(ClientRuntime.safeMethod(player, "getPlayerNum")) or 0
    return getCharacterInfoWindow(playerNum)
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
    screenClass._amsAttachBurdenTab = function(screen)
        local ok, attached = pcall(function()
            local attachedOk = attachBurdenTabToScreen(screen)
            return attachedOk
        end)
        if not ok or not attached then
            tabHookFailed = true
            ClientRuntime.logWarnOnce(
                "ui_burden_tab_fallback",
                "Burden tab injection failed; using the standalone fallback window"
            )
            ensureFallbackWindow(true)
            return false
        end
        tabHookFailed = false
        hideFallbackWindow()
        if screen._amsBurdenPanel and type(screen._amsBurdenPanel.markDirty) == "function" then
            screen._amsBurdenPanel:markDirty()
        end
        return true
    end

    if screenClass._amsBurdenTabPatched then
        tabHookInstalled = true
        return
    end

    local originalCreateChildren = screenClass.createChildren
    screenClass.createChildren = function(self, ...)
        local result = originalCreateChildren(self, ...)
        local attach = screenClass._amsAttachBurdenTab
        if type(attach) == "function" then
            attach(self)
        end
        return result
    end

    screenClass._amsBurdenTabPatched = true
    screenClass._amsBurdenTabOriginalCreateChildren = originalCreateChildren
    tabHookInstalled = true
    ClientRuntime.logOnce("ui_burden_tab_hook_installed", "[UI] Character info Burden tab hook installed.")
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

    local screenClass = _G.ISCharacterInfoWindow
    local existing = getLiveCharacterInfoWindow(player)
    local attach = screenClass and screenClass._amsAttachBurdenTab or nil
    if existing and not existing._amsBurdenAttached and type(attach) == "function" then
        attach(existing)
    end
    if existing and existing._amsBurdenAttached then
        fitViewsToTabStrip(existing)
    end

    if tabHookFailed then
        if not existing or type(attach) ~= "function" or not attach(existing) then
            ensureFallbackWindow(true)
        end
    end

    if pendingUiRefresh then
        pendingUiRefresh = false
        if fallbackWindow and fallbackWindow.panel and type(fallbackWindow.panel.markDirty) == "function" then
            fallbackWindow.panel:markDirty()
        end
    end
end

return UI
