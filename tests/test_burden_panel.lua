local Support = dofile((os.getenv("AMS_ROOT") or ".") .. "/tests/support.lua")

ArmorMakesSense = {}
require "ArmorMakesSense_Config"
UIFont = { Small = "Small" }
getText = function(key) return key end
getTextManager = function()
    return {
        MeasureStringX = function(_, _, text) return #tostring(text) * 7 end,
        getFontHeight = function() return 14 end,
    }
end

-- Mirrors vanilla ISUIElement instance fields so a method name that shadows
-- one (minimumWidth is a number) fails here, not in game.
local function newElement(x, y, width, height)
    return {
        x = x, y = y, width = width, height = height, children = {}, drawn = {}, rects = {},
        minimumWidth = 0, minimumHeight = 0, anchorLeft = true, anchorTop = true,
    }
end

local function setWidthChain(el, w)
    el.width = w
    local child, parent = el, el.parent
    while parent do
        parent.width = child.x + child.width
        child, parent = parent, parent.parent
    end
end

local mouse = { over = false, x = 0, y = 0 }

ISPanel = {}
ISPanel.__index = ISPanel
function ISPanel:derive(_)
    local class = setmetatable({}, { __index = self })
    class.__index = class
    return class
end
function ISPanel:new(x, y, width, height)
    return setmetatable(newElement(x, y, width, height), ISPanel)
end
function ISPanel:initialise() end
function ISPanel:instantiate()
    if self.createChildren then
        self:createChildren()
    end
end
function ISPanel:createChildren() end
function ISPanel:addChild(child) child.parent = self; self.children[#self.children + 1] = child end
function ISPanel:removeChild(child) child.parent = nil end
function ISPanel:getParent() return self.parent end
function ISPanel:setX(x) self.x = x end
function ISPanel:setY(y) self.y = y end
function ISPanel:setWidth(w) self.width = w end
function ISPanel:setHeight(h) self.height = h end
function ISPanel:setAnchorBottom() end
function ISPanel:setWidthAndParentWidth(w) setWidthChain(self, w) end
function ISPanel:setHeightAndParentHeight(h) self.height = h end
function ISPanel:isMouseOver() return mouse.over end
function ISPanel:getMouseY() return mouse.y end
function ISPanel:getMouseX() return mouse.x end
function ISPanel:drawRect(x, y, w, h, a) self.rects[#self.rects + 1] = { x = x, y = y, w = w, h = h, a = a } end
function ISPanel:drawTextureScaledAspect(tex, x, y, w, h) self.icons = (self.icons or 0) + 1 end
function ISPanel:drawText(text, x, y, r, g, b) self.drawn[#self.drawn + 1] = { text = text, x = x, y = y, r = r, g = g, b = b } end
function ISPanel:drawRectBorder(x, y, w, h) self.borders = self.borders or {}; self.borders[#self.borders + 1] = { x = x, y = y, w = w, h = h } end

local tips = {}
ISToolTip = {}
ISToolTip.__index = ISToolTip
function ISToolTip:new() local t = setmetatable({ visible = false }, ISToolTip); tips[#tips + 1] = t; return t end
function ISToolTip:setOwner(o) self.owner = o end
function ISToolTip:setVisible(v) self.visible = v end
function ISToolTip:getIsVisible() return self.visible end
function ISToolTip:setAlwaysOnTop() end
function ISToolTip:addToUIManager() self.managed = true end
function ISToolTip:removeFromUIManager() self.managed = false end
function ISToolTip:setDesiredPosition(x, y) self.px, self.py = x, y end
getMouseX = function() return 0 end
getMouseY = function() return 0 end

ISButton = {}
ISButton.__index = ISButton
function ISButton:new(x, y, width, height, title)
    return setmetatable({ x = x, y = y, width = width, height = height, title = title }, ISButton)
end
function ISButton:initialise() end
function ISButton:instantiate() end
function ISButton:setTooltip(t) self.tooltip = t end
function ISButton:setX(x) self.x = x end
function ISButton:setY(y) self.y = y end
function ISButton:setWidth(w) self.width = w end
function ISButton:setTitle(t) self.title = t end
function ISButton:setVisible(v) self.visible = v end
function ISButton:isVisible() return self.visible ~= false end
function ISButton:setEnable(v) self.enable = v end

Color = { new = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end }
BodyPartType = {
    FromIndex = function(i) return { index = i } end,
    ToIndex = function(bpt) return bpt.index end,
    getDisplayName = function(bpt) return "Part" .. bpt.index end,
}
package.loaded["ISUI/BodyParts/ISBodyPartPanel"] = true
ISBodyPartPanel = setmetatable({}, { __index = ISPanel })
ISBodyPartPanel.__index = ISBodyPartPanel
function ISBodyPartPanel:new(player, x, y, target, onPartSelected)
    local o = setmetatable(newElement(x, y, 123, 302), ISBodyPartPanel)
    o.values = {}
    o.target, o.onPartSelected = target, onPartSelected
    return o
end
function ISBodyPartPanel:setColorScheme(scheme) self.colorScheme = scheme end
function ISBodyPartPanel:setValue(bpt, value) self.values[bpt.index] = value end
function ISBodyPartPanel:getRgbForValue(v) return v / 3, 0.5, 0.2 end

local vanillaView = { width = 380, tabtotalwidth = 380 }
function vanillaView:setWidth(w) self.width = w end
local host = { x = 0, width = 560, height = 400, viewList = { { view = vanillaView } }, scrollX = -40 }
function host:addView(_, view)
    view.parent = self
    self.view = view
    self.viewList[#self.viewList + 1] = { view = view }
end
function host:getWidthOfAllTabs() return 470 end
local screen = { panel = host, playerNum = 0 }
ISCharacterInfoWindow = { createChildren = function() end }
getPlayerData = function() return { characterInfo = screen } end

local UI = require "core/ArmorMakesSense_UI"
local View = require "core/ArmorMakesSense_BurdenView"
local player = { getPlayerNum = function() return 0 end }
UI.update(player, {}, {})

local panel = screen._amsBurdenPanel
Support.assertTrue(panel ~= nil, "burden tab attached")
Support.assertTrue(panel.helpBtn ~= nil, "help button created")
Support.assertEqual(panel.exportBtn, nil, "Save Report lives in the help window")
panel:ensureBodyMap(player)
Support.assertTrue(panel.bodyMap ~= nil and panel.bodyMap.parent == panel, "body map attached")
Support.assertEqual(panel.bodyMap.maxValue, 3.0, "body map scale")

-- The added tab must not push the strip into scroll arrows on vanilla views.
Support.assertEqual(vanillaView.width, 472, "vanilla view widened to the tab strip")
Support.assertEqual(vanillaView.tabtotalwidth, 461, "health-style floor raised")
Support.assertEqual(host.scrollX, 0, "tab strip scroll reset")

local function options()
    local out = {}
    for k, v in pairs(ArmorMakesSense.DEFAULTS) do out[k] = v end
    return out
end

local texture = {}
local function row(name, location, kg)
    return {
        included = true, displayName = name, fullType = "Base." .. name, bodyLocation = location, burdenKg = kg,
        item = { getTex = function() return texture end },
    }
end

local function renderWith(r, rows)
    local base = {
        burdenKg = 0, loadFraction = 0, bodyKg = 80, strength = 5, armKg = 0, heat = 0,
        restRegenScale = 1, standRegenScale = 1, walkRegenScale = 1, runDrainScale = 1, sprintDrainScale = 1,
    }
    for k, v in pairs(r) do base[k] = v end
    panel.view = View.build({ runtime = base, analysis = { rows = rows }, options = options() })
    panel.drawn, panel.rects, panel.icons = {}, {}, 0
    panel:render()
end

local function assertInside(label)
    for _, d in ipairs(panel.drawn) do
        Support.assertTrue(d.x >= 0 and d.x + #d.text * 7 <= panel.width,
            label .. ": text inside panel: " .. d.text)
        Support.assertTrue(d.y >= 0 and d.y + 14 <= panel.height, label .. ": text above the bottom: " .. d.text)
    end
    Support.assertTrue(panel.helpBtn.x + panel.helpBtn.width <= panel.width, label .. ": help button inside")
    Support.assertTrue(panel.helpBtn.y + panel.helpBtn.height <= panel.height, label .. ": buttons above the bottom")
end

local function drawn(text)
    for _, d in ipairs(panel.drawn) do
        if d.text == text then return d end
    end
    return nil
end

-- Civilian.
renderWith({ burdenKg = 1 }, { row("Shoes", "Shoes", 1.0) })
local civWidth = panel.width
Support.assertTrue(panel.width >= 472, "burden tab is at least as wide as the tab strip")
Support.assertEqual(host.width, panel.width, "window follows the panel width")
assertInside("civilian")
Support.assertTrue(drawn("Your gear costs you nothing extra.") ~= nil, "verdict drawn")
Support.assertTrue(drawn("Weight by area") ~= nil, "map caption drawn")
Support.assertTrue(drawn("3+ kg") == nil, "no map legend")
Support.assertTrue(drawn("Heat") == nil and drawn("Breathing") == nil and drawn("Sleep") == nil, "idle rows hidden")
Support.assertTrue(drawn("Melee") ~= nil, "melee always shown")
Support.assertClose(panel.bodyMap.values[15], 0.5, 1e-9, "map shows feet load")
Support.assertEqual(panel.bodyMap.values[6], 0, "map clears unloaded parts")

-- Heavy loadout with a long modded name.
local longName = string.rep("Very Long Modded Armor Name ", 4)
renderWith({
    burdenKg = 30, loadFraction = 0.3, walkRegenScale = -0.1, restRegenScale = 0.9, standRegenScale = 0.8,
    runDrainScale = 1.5, sprintDrainScale = 1.7, heat = 0.5, breathingSeverity = 1,
    sleepPenaltyFraction = 0.25, armKg = 6,
}, { row(longName, "TorsoExtraVest", 12), row("Greaves", "Calf_Left", 3), row("Vambraces", "Forearm_Right", 2) })
assertInside("heavy")
Support.assertTrue(panel.width >= civWidth, "heavy panel is not narrower")
Support.assertEqual(panel.icons, 3, "one icon per gear row")
Support.assertTrue(drawn("Greaves") ~= nil, "gear row drawn")
local walkLabel, fightLabel = drawn("Walking"), drawn("Fighting")
Support.assertTrue(walkLabel ~= nil and fightLabel ~= nil and walkLabel.y == fightLabel.y, "endurance paces on one line")
Support.assertTrue(drawn("Standing") == nil and drawn("Sprinting") == nil, "standing and sprinting left to the ? text")
Support.assertTrue(drawn(longName) == nil, "long name truncated")
Support.assertClose(panel.bodyMap.values[13], 3, 1e-9, "greaves on the left calf")

-- Hovering a gear row shows only that item on the map.
local rect = panel.itemRects[2]
mouse.over, mouse.x, mouse.y = true, 20, rect.y1 + 1
panel.drawn, panel.rects = {}, {}
panel:render()
Support.assertClose(panel.bodyMap.values[13], 3, 1e-9, "hovered item parts shown")
Support.assertEqual(panel.bodyMap.values[6], 0, "other items hidden while hovering")

-- Hovering the Melee row narrows the map to swing-chain gear.
local meleeRect
for _, r in ipairs(panel.channelRects) do
    if r.key == "melee" then meleeRect = r end
end
Support.assertTrue(meleeRect ~= nil, "melee row is hoverable")
mouse.x, mouse.y = meleeRect.x1 + 5, meleeRect.y1 + 5
panel.drawn, panel.rects = {}, {}
panel:render()
Support.assertTrue(drawn("Arm and hand gear") ~= nil, "melee caption")
Support.assertTrue((panel.bodyMap.values[3] or 0) > 0, "vambraces on the right forearm")
Support.assertEqual(panel.bodyMap.values[13], 0, "greaves hidden under melee hover")
mouse.over = false

-- Hovering a body part names it and its load.
panel.bodyMap.onPartSelected(panel.bodyMap.target, { bodyPartType = BodyPartType.FromIndex(13) })
panel.drawn, panel.rects = {}, {}
panel:render()
Support.assertTrue(drawn("Part13: 3.0 kg") ~= nil, "part caption")
panel.bodyMap.onPartSelected(panel.bodyMap.target, nil)
Support.assertEqual(panel.hoverPart, nil, "part hover clears")

-- Another tab narrowed the shared window while Burden was hidden.
host.width = 300
panel.drawn, panel.rects = {}, {}
panel:render()
Support.assertEqual(host.width, panel.width, "window regrows to the panel on return")

-- Shrinks back when the loadout gets lighter.
renderWith({ burdenKg = 1 }, { row("Shoes", "Shoes", 1.0) })
Support.assertEqual(panel.width, civWidth, "panel shrinks back")
assertInside("light again")

-- Armor buttons: hidden without armor; shown left of the utility buttons,
-- wrapping onto their own row when they do not fit.
Support.assertFalse(panel.takeOffBtn:isVisible(), "take off hidden without armor")
Support.assertFalse(panel.wearBtn:isVisible(), "wear hidden without a saved set")
local function piece(label) return { label = label } end
panel.armor = {
    worn = { piece("Helmet"), piece("Vest") },
    ready = { { piece = piece("Greaves") } },
    missing = { piece("Cuirass") },
}
panel.drawn, panel.rects = {}, {}
panel:render()
Support.assertTrue(panel.takeOffBtn:isVisible() and panel.dropBtn:isVisible(), "take off and drop shown")
Support.assertTrue(panel.wearBtn:isVisible(), "wear shown")
Support.assertEqual(panel.wearBtn.title, "Wear Armor (1)", "wear counts ready pieces")
Support.assertTrue(panel.wearBtn.tooltip:find("Greaves", 1, true) ~= nil, "wear tooltip lists pieces")
Support.assertTrue(panel.wearBtn.tooltip:find("Not nearby: Cuirass", 1, true) ~= nil, "wear tooltip names missing")
Support.assertTrue(panel.takeOffBtn.tooltip:find("Helmet, Vest", 1, true) ~= nil, "take off tooltip lists worn")
local lastArmor = panel.dropBtn
Support.assertTrue(panel.wearBtn.x < panel.takeOffBtn.x and panel.takeOffBtn.x < panel.dropBtn.x, "armor buttons in order")
if lastArmor.y == panel.helpBtn.y then
    Support.assertTrue(lastArmor.x + lastArmor.width < panel.helpBtn.x, "armor buttons clear the help button")
else
    Support.assertTrue(panel.helpBtn.y > lastArmor.y, "help button wraps below armor")
end
assertInside("armor buttons")
panel.armor = nil

local BurdenPanel = require "core/ArmorMakesSense_BurdenPanel"

-- "?" markers: one per row, inside the panel, clear of the state text;
-- hovering one shows its explanation, leaving hides it.
renderWith({ burdenKg = 14, loadFraction = 0.4, armKg = 3, heat = 0.2, breathingSeverity = 0.5, sleepPenaltyFraction = 0.2 },
    { row("Vest", "TorsoExtraVest", 8.0), row("Gloves", "Hands", 3.0) })
local keys = {}
for _, rect in ipairs(panel.infoRects) do
    keys[rect.key] = rect
    Support.assertTrue(rect.x1 >= 0 and rect.x2 <= panel.width and rect.y2 <= panel.height, "info marker inside: " .. rect.key)
    Support.assertTrue(View.info(rect.key) ~= nil, "info text exists: " .. rect.key)
end
for _, key in ipairs({ "load", "endurance", "heat", "breathing", "melee", "sleep", "gear" }) do
    Support.assertTrue(keys[key] ~= nil, "info marker for " .. key)
end
for _, d in ipairs(panel.drawn) do
    if d.text ~= "?" then
        for _, rect in pairs(keys) do
            local overlaps = d.y < rect.y2 and d.y + 14 > rect.y1 and d.x < rect.x2 and d.x + #d.text * 7 > rect.x1
            Support.assertFalse(overlaps, "info marker clear of text: " .. rect.key .. " / " .. d.text)
        end
    end
end
mouse.over, mouse.x, mouse.y = true, keys.sleep.x1 + 3, keys.sleep.y1 + 3
panel.drawn, panel.rects = {}, {}
panel:render()
panel.drawn, panel.rects = {}, {}
panel:render()
Support.assertEqual(panel.hoveredInfo, "sleep", "sleep marker hovered")
Support.assertTrue(panel.infoTip ~= nil and panel.infoTip.visible, "info tip shown")
local desc = panel.infoTip.description
Support.assertEqual(desc, BurdenPanel.infoRichText(View.info("sleep")), "info tip text")
Support.assertTrue(desc:find("2.5% slower per kilo", 1, true) ~= nil, "percent argument substituted")
Support.assertTrue(desc:find(" <BR> ", 1, true) ~= nil and desc:find(" <LINE> ", 1, true) ~= nil, "info tip broken into lines")
Support.assertTrue(desc:find("<SETX:16>", 1, true) ~= nil, "points get a hanging indent")
for _, key in ipairs({ "load", "endurance", "heat", "breathing", "melee", "sleep", "gear" }) do
    local rich = BurdenPanel.infoRichText(View.info(key))
    Support.assertTrue(rich:match(">%s*$") == nil, "info text ends with text, not a tag: " .. key)
end
local endurance = View.info("endurance")
local kinds = {}
for _, line in ipairs(endurance) do kinds[#kinds + 1] = line.kind end
Support.assertEqual(table.concat(kinds, ","), "summary,heading,point,point,point,heading,point,heading,point,note", "endurance info structure")
getText = function(key) return key == "UI_AMS_Info_Gear" and "Top line\\n- one\\nlast" or key end
local literal = View.info("gear")
Support.assertEqual(#literal, 3, "literal backslash-n splits")
Support.assertEqual(literal[2].kind, "point", "literal point kind")
getText = function(key) return key end
mouse.over = false
panel.drawn, panel.rects = {}, {}
panel:render()
Support.assertFalse(panel.infoTip.visible, "info tip hidden on leave")
Support.assertEqual(#tips, 1, "info tip reused")

-- Help button routes to the UI help window.
local helped = false
local originalHelp = BurdenPanel.onHelp
BurdenPanel.onHelp = function(playerNum) helped = playerNum end
panel:onHelpClick()
Support.assertEqual(helped, 0, "help routed with the player number")
BurdenPanel.onHelp = originalHelp

print("ams burden panel checks passed")
