ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Core = ArmorMakesSense.Core or {}

-- The Burden tab: a verdict, a body map of where the weight sits, one row per
-- cost channel, and the worn gear that drives it. Content comes from BurdenView.
local BurdenPanel = ArmorMakesSense.Core.BurdenPanel or {}
ArmorMakesSense.Core.BurdenPanel = BurdenPanel

local ClientRuntime = require "core/ArmorMakesSense_ClientRuntime"
local LoadModel = require "ArmorMakesSense_LoadModelShared"
local MP = require "ArmorMakesSense_MPCompat"
local Options = require "ArmorMakesSense_Options"
local Physiology = require "ArmorMakesSense_PhysiologyShared"
local PresentationPolicy = require "ArmorMakesSense_PresentationPolicy"
local SupportReport = require "core/ArmorMakesSense_SupportReport"
local View = require "core/ArmorMakesSense_BurdenView"
local Draw = require "core/ArmorMakesSense_Draw"
local Utils = require "ArmorMakesSense_UtilsShared"

local tr = View.tr
local C = Draw.C

local MAP_W, MAP_H = 123, 302
local MAP_MAX_KG = 3.0
local BUTTON_H = 20
local BUTTON_GAP = 6
local BUTTON_PAD = 16
local COLUMN_MAX = 380
local ITEM_CELLS_W = 52

-- Set by UI: opens the help window.
BurdenPanel.onHelp = BurdenPanel.onHelp or nil

local function color(key)
    return C[key] or C.text
end

local function font()
    return UIFont and UIFont.Small or nil
end

local function tw(text)
    return Draw.textWidth(font(), text)
end

local function truncate(label, maxW)
    if maxW <= 0 then
        return ""
    end
    if tw(label) <= maxW then
        return label
    end
    local len = #label
    while len > 1 and tw(string.sub(label, 1, len) .. "...") > maxW do
        len = len - 1
    end
    return string.sub(label, 1, len) .. "..."
end

-- Covered body parts come from script data, so they are cached per type.
local coveredCache = {}
local function coveredParts(row)
    local key = tostring(row.fullType) .. "|" .. tostring(row.bodyLocation)
    local cached = coveredCache[key]
    if cached then
        return cached
    end
    local out = {}
    local item = row.item
    local isClothing = item and (type(instanceof) ~= "function" or instanceof(item, "Clothing"))
    local list = isClothing and ClientRuntime.safeMethod(item, "getCoveredParts") or nil
    local count = tonumber(list and ClientRuntime.safeMethod(list, "size")) or 0
    for i = 0, count - 1 do
        local part = ClientRuntime.safeMethod(list, "get", i)
        local index = tonumber(part and ClientRuntime.safeMethod(part, "index"))
        if index then
            out[#out + 1] = index
        end
    end
    coveredCache[key] = out
    return out
end

local function currentOptions()
    local UI = ArmorMakesSense.Core.UI
    return (UI and UI._lastOptions) or Options.get()
end

local function showExportResultModal(playerNum, ok, detail)
    if not ISModalDialog then
        return
    end
    local label = ok and tr("UI_AMS_Help_ExportSaved", "Saved") or tr("UI_AMS_Help_ExportFailed", "Export failed")
    local modal = ISModalDialog:new(0, 0, 360, 120, label .. ":\n" .. tostring(detail or ""), false, nil, nil, playerNum)
    modal:initialise()
    modal:addToUIManager()
end

local Panel = nil

local function defineClass()
    Panel = ISPanel:derive("AMSBurdenPanel")

    function Panel:new(x, y, width, height, playerNum)
        local o = ISPanel:new(x, y, width, height)
        setmetatable(o, self)
        self.__index = self
        o.playerNum = tonumber(playerNum) or 0
        o.lastRefreshMinute = -1
        o.view = nil
        o.needsRefresh = true
        o.noBackground = true
        o.isStandalone = false
        o.hoverPart = nil
        return o
    end

    local function makeButton(self, label, onClick)
        local btn = ISButton:new(0, 0, tw(label) + BUTTON_PAD, BUTTON_H, label, self, onClick)
        btn:initialise()
        btn:instantiate()
        btn.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 0.7 }
        btn.backgroundColor = { r = 0.15, g = 0.15, b = 0.15, a = 0.8 }
        self:addChild(btn)
        return btn
    end

    function Panel:createChildren()
        ISPanel.createChildren(self)
        self.helpBtn = makeButton(self, tr("UI_AMS_Help_Button", "? Help"), Panel.onHelpClick)
        self.exportBtn = makeButton(self, tr("UI_AMS_Help_ExportShort", "Save Report"), Panel.onExportClick)
        self.exportBtn:setTooltip(tr(
            "UI_AMS_Help_ExportTooltip",
            "Save a support report with your loadout, burden calculations, mod list and game state."
        ))
    end

    function Panel:onHelpClick()
        if type(BurdenPanel.onHelp) == "function" then
            BurdenPanel.onHelp()
        end
    end

    function Panel:onExportClick()
        local exportFn = SupportReport.writeCurrentPlayerReport
        if type(exportFn) ~= "function" then
            return
        end
        local ok, pathOrNil, err = exportFn(self:resolvePlayer())
        if ok then
            showExportResultModal(self.playerNum, true, tostring(pathOrNil or "Lua/ams_reports/"))
        else
            showExportResultModal(self.playerNum, false, tostring(err or "unknown"))
        end
    end

    function Panel:onJoypadDown(button, joypadData)
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

    function Panel:markDirty()
        self.needsRefresh = true
    end

    function Panel:resolvePlayer()
        local player = type(getSpecificPlayer) == "function" and getSpecificPlayer(self.playerNum) or nil
        if not player and type(getPlayer) == "function" then
            player = getPlayer()
        end
        return player
    end

    function Panel:collectSnapshot(force)
        local player = self:resolvePlayer()
        if not player then
            self.view = nil
            return
        end
        local nowMinute = tonumber(Utils.getWorldAgeMinutes()) or 0
        if not (force or self.needsRefresh or self.view == nil or self.lastRefreshMinute < 0
            or (nowMinute - self.lastRefreshMinute) >= 0.5) then
            return
        end
        self.lastRefreshMinute = nowMinute
        self.needsRefresh = false

        local state = ClientRuntime.ensureState(player)
        local options = currentOptions()
        local analysis = LoadModel.analyzeWornGear(player, options)
        local runtime, heatPending
        if Utils.isMultiplayer() then
            local mpRuntime = ArmorMakesSense.MPClientRuntime
            if mpRuntime and type(mpRuntime.requestSnapshot) == "function" then
                mpRuntime.requestSnapshot(player, tonumber(MP.SNAPSHOT_UI_REFRESH_SECONDS) or 30)
            end
            -- Local gear keeps clothing changes instant; heat comes from the server.
            local server = Physiology.getUiRuntimeSnapshot(state)
            runtime = Physiology.projectWithServerThermal(player, options, analysis.profile, server)
            heatPending = server == nil
        else
            runtime = Physiology.project(player, state, options, analysis.profile)
        end
        self.view = View.build({
            runtime = runtime,
            analysis = analysis,
            options = options,
            heatPending = heatPending,
            covered = coveredParts,
        })
        self:ensureBodyMap(player)
    end

    function Panel:onBodyPartSelected(bp)
        self.hoverPart = bp and bp.bodyPartType and BodyPartType.ToIndex(bp.bodyPartType) or nil
    end

    function Panel:ensureBodyMap(player)
        if self.bodyMap and self.bodyMapPlayer == player then
            return
        end
        if self.bodyMap then
            self:removeChild(self.bodyMap)
        end
        require "ISUI/BodyParts/ISBodyPartPanel"
        local map = ISBodyPartPanel:new(player, 0, 0, self, Panel.onBodyPartSelected)
        map.maxValue = MAP_MAX_KG
        map.canSelect = true
        map:initialise()
        map:setColorScheme({
            { val = 0, color = Color.new(0.20, 0.20, 0.20, 1) },
            { val = 0.4, color = Color.new(0.55, 0.45, 0.28, 1) },
            { val = 1.5, color = Color.new(C.burden.r, C.burden.g, C.burden.b, 1) },
            { val = MAP_MAX_KG, color = Color.new(C.bad.r, C.bad.g, C.bad.b, 1) },
        })
        self:addChild(map)
        self.bodyMap = map
        self.bodyMapPlayer = player
        self.hoverPart = nil
    end

    function Panel:prerender()
        self:collectSnapshot(false)
    end

    function Panel:buttonsWidth()
        return self.exportBtn.width + BUTTON_GAP + self.helpBtn.width
    end

    -- Vanilla character-info views set their exact size every frame, even
    -- when unchanged: other tabs resize the shared window while hidden.
    function Panel:fitTo(width, height)
        local w, h = math.floor(width), math.floor(height)
        if self.isStandalone then
            self:setWidth(w)
            self:setHeight(h)
            local parent = self:getParent()
            if parent then
                parent:setWidth(w + 16)
                parent:setHeight(h + 32)
            end
            return
        end
        self:setWidthAndParentWidth(w)
        self:setHeightAndParentHeight(h)
    end

    local MAP_CAPTIONS = {
        load = { "UI_AMS_Map_Load", "All worn gear" },
        melee = { "UI_AMS_Map_Melee", "Arm and hand gear" },
        sleep = { "UI_AMS_Map_Sleep", "Stiff gear" },
        breathing = { "UI_AMS_Map_Breathing", "Masks and sealed gear" },
    }

    -- Endurance: a row label, then two paces of name and value.
    local function paceMetrics(v)
        local labelW, nameW, valueW = 0, 0, 0
        for _, group in ipairs(v.endurance.groups) do
            labelW = math.max(labelW, tw(group.label))
            for _, pace in ipairs(group.paces) do
                nameW = math.max(nameW, tw(pace.label))
                valueW = math.max(valueW, tw(pace.value))
            end
        end
        return labelW + 12, nameW + 6, valueW + 14
    end

    function Panel:measure(v, fh)
        local need = math.max(260, fh * 18)
        local function row(label, state, value)
            need = math.max(need, tw(label) + 16 + tw(state) + (value and (tw(value) + 10) or 0))
        end
        row(v.load.label, v.load.state, v.load.value)
        row(v.endurance.label, v.endurance.state)
        local labelW, nameW, valueW = paceMetrics(v)
        need = math.max(need, labelW + (nameW + valueW) * 2)
        for _, channel in ipairs(v.channelOrder) do
            row(channel.label, channel.state)
        end
        return math.min(COLUMN_MAX, need)
    end

    -- The tab strip must fit without scroll arrows.
    function Panel:tabStripWidth()
        local host = self.parent
        if self.isStandalone or not (host and type(host.getWidthOfAllTabs) == "function") then
            return 0
        end
        return host:getWidthOfAllTabs() + 2
    end

    local function hit(rects, mx, my)
        for _, rect in ipairs(rects or {}) do
            if my >= rect.y1 and my < rect.y2 and mx >= rect.x1 and mx < rect.x2 then
                return rect
            end
        end
        return nil
    end

    function Panel:resolveHover()
        if not self:isMouseOver() then
            return nil, nil
        end
        local mx, my = self:getMouseX(), self:getMouseY()
        return hit(self.itemRects, mx, my), hit(self.channelRects, mx, my)
    end

    function Panel:render()
        local v = self.view
        local f = font()
        local fh = Draw.fontHeight(f)
        local pad = math.max(10, math.floor(fh * 0.7))
        local sink = Draw.elementSink(self)
        local cellH = math.max(5, math.floor(fh * 0.4))
        local colX = pad + MAP_W + math.floor(pad * 1.5)

        if not v then
            local width = math.max(colX + 260 + pad, self:tabStripWidth())
            self:placeButtons(pad, width)
            self:fitTo(width, pad * 2 + BUTTON_H)
            return
        end

        local width = math.max(colX + self:measure(v, fh) + pad, self:tabStripWidth())
        local colW = width - pad - colX
        local colRight = colX + colW
        local fullW = width - pad * 2
        local y = pad
        -- Hover resolves against last frame's rects; the view is rebuilt
        -- periodically, so match by key.
        local itemRect, channelRect = self:resolveHover()
        local hoveredItem = itemRect and v.items[itemRect.key] or nil
        local hoveredChannel = nil
        if channelRect then
            hoveredChannel = channelRect.key == "load" and v.load or v.channels[channelRect.key]
        end

        local function text(value, x, ty, c)
            self:drawText(tostring(value), x, ty, c.r, c.g, c.b, 1.0, f)
        end
        local function textRight(value, right, ty, c)
            local str = tostring(value)
            self:drawText(str, right - tw(str), ty, c.r, c.g, c.b, 1.0, f)
        end
        local function wrapped(value, x, w, c)
            for _, line in ipairs(Draw.wrap(f, value, w)) do
                text(line, x, y, c)
                y = y + fh
            end
        end
        local function separator(gap)
            y = y + gap
            self:drawRect(pad, y, fullW, 1, 0.18, 1, 1, 1)
            y = y + gap + 1
        end

        -- Verdict: the one thing worth knowing right now.
        wrapped(v.verdict, pad, fullW, color(v.verdictTone))
        separator(math.floor(pad * 0.6))

        -- Channel column beside the body map. Rows with a cause on the map
        -- are hoverable.
        local topY = y
        local rowGap = math.floor(pad * 0.9)
        self.channelRects = {}
        local function header(rowData)
            text(rowData.label, colX, y, (hoveredChannel == rowData) and C.text or C.label)
            textRight(rowData.state, colRight, y, color(rowData.tone))
            if rowData.value then
                textRight(rowData.value, colRight - tw(rowData.state) - 10, y, C.dim)
            end
            y = y + fh + 3
        end
        local function cells(rowData)
            if (rowData.fill or 0) <= 0 then
                y = y - 1
                return
            end
            local tone = rowData.tone
            local c = (tone == "warn" or tone == "bad") and color(tone) or color(rowData.color)
            Draw.cells(sink, colX, y, colW, cellH, PresentationPolicy.PIP_COUNT, rowData.fill, c)
            y = y + cellH + 4
        end
        local function channelRow(rowData)
            local y1 = y
            local hoverable = rowData.key and v.channelParts[rowData.key] ~= nil
            if hoverable and hoveredChannel == rowData then
                self:drawRect(colX - 6, channelRect.y1, colW + 12, channelRect.y2 - channelRect.y1, 0.06, 1, 1, 1)
            end
            header(rowData)
            cells(rowData)
            if rowData.detail then
                wrapped(rowData.detail, colX, colW, C.dim)
            end
            if hoverable then
                self.channelRects[#self.channelRects + 1] = {
                    key = rowData.key, x1 = colX - 6, x2 = colRight + 6, y1 = y1 - 3, y2 = y + 3,
                }
            end
        end

        channelRow(v.load)
        y = y + rowGap

        header(v.endurance)
        local labelW, nameW, valueW = paceMetrics(v)
        for _, group in ipairs(v.endurance.groups) do
            text(group.label, colX, y, C.dim)
            local px = colX + labelW
            for _, pace in ipairs(group.paces) do
                text(pace.label, px, y, C.label)
                text(pace.value, px + nameW, y, color(pace.tone))
                px = px + nameW + valueW
            end
            y = y + fh + 2
        end

        for _, channel in ipairs(v.channelOrder) do
            y = y + rowGap
            channelRow(channel)
        end
        local columnBottom = y

        -- Body map: a hovered gear row or channel row narrows it to its cause;
        -- a hovered body part names its load and lights the gear on it.
        local caption, captionColor = tr("UI_AMS_Map_Caption", "Weight by area"), C.dim
        local values = v.parts
        if hoveredItem then
            values, caption, captionColor = hoveredItem.parts, hoveredItem.label, C.text
        elseif hoveredChannel and v.channelParts[hoveredChannel.key] then
            local cap = MAP_CAPTIONS[hoveredChannel.key]
            values, caption, captionColor = v.channelParts[hoveredChannel.key], tr(cap[1], cap[2]), C.text
        elseif self.hoverPart ~= nil then
            caption = tr("UI_AMS_Map_Part", "%1: %2 kg",
                BodyPartType.getDisplayName(BodyPartType.FromIndex(self.hoverPart)),
                string.format("%.1f", v.parts[self.hoverPart] or 0))
            captionColor = C.text
        end
        if self.bodyMap then
            self.bodyMap:setX(pad)
            self.bodyMap:setY(topY)
            for i = 0, View.PART_COUNT - 1 do
                self.bodyMap:setValue(BodyPartType.FromIndex(i), values[i] or 0)
            end
        end
        local captionY = topY + MAP_H + 4
        for _, line in ipairs(Draw.wrap(f, caption, MAP_W)) do
            line = truncate(line, MAP_W)
            text(line, pad + math.floor((MAP_W - tw(line)) / 2), captionY, captionColor)
            captionY = captionY + fh
        end
        if self.bodyMap then
            captionY = self:drawMapLegend(pad, captionY + 6, cellH, f, fh)
        end

        y = math.max(columnBottom, captionY)
        separator(math.floor(pad * 0.6))

        -- Worn gear.
        text(tr("UI_AMS_Row_Gear", "Heaviest gear"), pad, y, C.label)
        y = y + fh + 4
        local iconSize = fh + 2
        local rowH = iconSize + 4
        local kgW = tw("00.0 kg")
        local cellsX = width - pad - kgW - 10 - ITEM_CELLS_W
        local nameX = pad + iconSize + 6
        local nameW = cellsX - 10 - nameX
        self.itemRects = {}
        for index, item in ipairs(v.items) do
            local lit = hoveredItem == item
                or (self.hoverPart ~= nil and (item.parts[self.hoverPart] or 0) > 0)
                or (hoveredChannel ~= nil and (hoveredChannel.key == "load" or item.channels[hoveredChannel.key] ~= nil))
            if lit then
                self:drawRect(pad - 4, y - 2, fullW + 8, rowH, 0.08, 1, 1, 1)
            end
            local tex = ClientRuntime.safeMethod(item.row.item, "getTex")
            if tex then
                self:drawTextureScaledAspect(tex, pad, y, iconSize, iconSize, 1, 1, 1, 1)
            end
            local textY = y + math.floor((iconSize - fh) / 2)
            local countW = item.countText and (tw(item.countText) + 6) or 0
            local name = truncate(item.label, nameW - countW)
            text(name, nameX, textY, lit and C.text or C.label)
            if item.countText then
                text(item.countText, nameX + tw(name) + 6, textY, C.dim)
            end
            Draw.cells(sink, cellsX, textY + math.floor((fh - cellH) / 2) + 1, ITEM_CELLS_W, cellH,
                PresentationPolicy.PIP_COUNT, item.fill, color(item.tone == "dim" and "burden" or item.tone), 2)
            textRight(item.value, width - pad, textY, lit and C.text or C.dim)
            self.itemRects[#self.itemRects + 1] = { key = index, x1 = 0, x2 = width, y1 = y - 2, y2 = y - 2 + rowH }
            y = y + rowH
        end
        if v.gearSummary then
            wrapped(v.gearSummary, pad, fullW, C.dim)
        end
        if v.tip then
            y = y + 4
            wrapped(v.tip, pad, fullW, C.good)
        end

        separator(math.floor(pad * 0.6))
        self:placeButtons(y, width)
        self:fitTo(width, y + BUTTON_H + pad)
    end

    -- Scale for the body map colors: 0 to MAP_MAX_KG per part.
    function Panel:drawMapLegend(x, y, h, f, fh)
        local left, w = x + 4, MAP_W - 8
        for px = 0, w - 1, 2 do
            local r, g, b = self.bodyMap:getRgbForValue((px + 1) / w * MAP_MAX_KG)
            self:drawRect(left + px, y, 2, h, 1, r, g, b)
        end
        y = y + h + 2
        self:drawText("0", left, y, C.dim.r, C.dim.g, C.dim.b, 1, f)
        local maxLabel = tr("UI_AMS_Map_Max", "%1+ kg", string.format("%.0f", MAP_MAX_KG))
        self:drawText(maxLabel, left + w - tw(maxLabel), y, C.dim.r, C.dim.g, C.dim.b, 1, f)
        return y + fh
    end

    function Panel:placeButtons(y, width)
        local right = width - math.max(10, math.floor(Draw.fontHeight(font()) * 0.7))
        self.helpBtn:setX(right - self.helpBtn.width)
        self.helpBtn:setY(y)
        self.exportBtn:setX(self.helpBtn.x - BUTTON_GAP - self.exportBtn.width)
        self.exportBtn:setY(y)
    end
end

function BurdenPanel.new(x, y, width, height, playerNum)
    if not Panel then
        defineClass()
    end
    return Panel:new(x, y, width, height, playerNum)
end

return BurdenPanel
