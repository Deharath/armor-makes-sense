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

ISButton = {}
ISButton.__index = ISButton
function ISButton:new(x, y, width, height, title)
    return setmetatable({ x = x, y = y, width = width, height = height, title = title }, ISButton)
end
function ISButton:initialise() end
function ISButton:instantiate() end
function ISButton:setTooltip() end
function ISButton:setX(x) self.x = x end
function ISButton:setY(y) self.y = y end

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
Support.assertTrue(panel.helpBtn ~= nil and panel.exportBtn ~= nil, "buttons created")
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
    Support.assertTrue(panel.exportBtn.x >= 0, label .. ": export button inside")
    Support.assertTrue(panel.exportBtn.x + panel.exportBtn.width <= panel.helpBtn.x, label .. ": buttons do not overlap")
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

-- Help button routes to the UI help window.
local helped = false
local BurdenPanel = require "core/ArmorMakesSense_BurdenPanel"
local originalHelp = BurdenPanel.onHelp
BurdenPanel.onHelp = function() helped = true end
panel:onHelpClick()
Support.assertTrue(helped, "help routed")
BurdenPanel.onHelp = originalHelp

print("ams burden panel checks passed")
