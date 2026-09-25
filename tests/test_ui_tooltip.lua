local Support = dofile((os.getenv("AMS_ROOT") or ".") .. "/tests/support.lua")
package.path = (Support.ROOT .. "/common/media/lua/client/?/?.lua;") .. package.path

local UITooltip = require "core/ArmorMakesSense_UITooltip"
local LoadModel = require "ArmorMakesSense_LoadModelShared"

-- Installation waits for the vanilla class and stays idempotent.
ISToolTipInv = nil
Support.assertFalse(UITooltip.install(), "install defers without ISToolTipInv")
local ownerPasses = 2
local originalRender = function(self)
    for _ = 1, ownerPasses do
        self.item:DoTooltip(self.tooltip)
    end
end
ISToolTipInv = { render = originalRender }
Support.assertTrue(UITooltip.install(), "install succeeds once the class exists")
local installed = ISToolTipInv.render
Support.assertTrue(installed ~= originalRender, "render is wrapped")
UITooltip.install()
Support.assertEqual(ISToolTipInv.render, installed, "install is idempotent")

getTextManager = function()
    return { MeasureStringX = function(_, _, text) return #text * 7 end }
end

local signal = { burdenKg = 4.6, airflowResistance = 3.75, sealedRestriction = 1 }
LoadModel.itemToBurdenSignal = function() return signal end

local tooltipKey = "Tooltip_item_NoBackpack"
local keyDuringRender = {}
local calls = { original = 0, embedded = 0 }
local itemMethods = {
    getBodyLocation = function() return "ams:shoulderpad_left" end,
    getFullType = function() return "Base.Shoulderpad_Articulated_L_Metal" end,
    getTooltip = function() return tooltipKey end,
    setTooltip = function(_, value) tooltipKey = value end,
    DoTooltip = function()
        calls.original = calls.original + 1
        keyDuringRender[#keyDuringRender + 1] = tostring(tooltipKey)
    end,
    DoTooltipEmbedded = function(_, _, layout)
        calls.embedded = calls.embedded + 1
        keyDuringRender[#keyDuringRender + 1] = tostring(tooltipKey)
        layout.rows = 2
    end,
}
local originalDoTooltip = itemMethods.DoTooltip
local item = setmetatable({}, { __index = itemMethods })

local measureOnly = false
local texts, rects = {}, {}
local tooltip = { width = 100, height = 0 }
function tooltip:beginLayout()
    local layout = { rows = 0 }
    function layout:setMinLabelWidth(w) self.minLabel = w end
    function layout:setMinValueWidth(w) self.minValue = w end
    function layout:render(x, y) self.x, self.y = x, y; return y + self.rows * 14 end
    self.layout = layout
    return layout
end
function tooltip:endLayout() end
function tooltip:getFont() return "TooltipFont" end
function tooltip:getLineSpacing() return 20 end
function tooltip:isMeasureOnly() return measureOnly end
function tooltip:getWidth() return self.width end
function tooltip:setWidth(v) self.width = v end
function tooltip:setHeight(v) self.height = v end
function tooltip:DrawText(_, text, x, y) texts[#texts + 1] = { text = text, x = x, y = y } end
function tooltip:DrawTextureScaledColor(_, x, y, w, h, r, g, b, a) rects[#rects + 1] = { x = x, y = y, w = w, a = a } end

local rows = UITooltip.buildRows(item)
Support.assertEqual(#rows, 2, "burden and breathing rows")
Support.assertEqual(rows[1].label, "Burden", "burden row first")
Support.assertEqual(rows[1].pips, 3, "4.6 kg is three pips")
Support.assertEqual(rows[2].label, "Breathing", "breathing row second")
Support.assertEqual(rows[2].pips, 4, "sealed mask is four pips")

local panel = { item = item, tooltip = tooltip }
ISToolTipInv.render(panel)
Support.assertTrue(itemMethods.DoTooltip ~= originalDoTooltip, "persistent class wrapper installed")
Support.assertEqual(calls.original, 0, "AMS owns eligible DoTooltip passes")
Support.assertEqual(calls.embedded, 2, "both owner passes reuse vanilla's embedded rows")
Support.assertEqual(tooltip.layout.minLabel, 80, "label column minimum")
Support.assertEqual(tooltip.layout.x, 7, "left pad from digit width")
Support.assertEqual(tooltip.layout.y, 28, "content starts below the title line")
Support.assertEqual(tooltip.height, 102, "pip block extends tooltip height")
Support.assertEqual(tooltip.width, 154, "pip strip widens a narrow tooltip")
Support.assertEqual(#texts, 4, "two labels per pass")
Support.assertEqual(texts[1].text, "Burden:", "burden label drawn")
Support.assertEqual(texts[1].y, 59, "pip block sits under vanilla rows")
Support.assertEqual(#rects, 16, "four pips per row per pass")
Support.assertEqual(rects[1].x, 95, "pips align to the value column")
Support.assertEqual(rects[1].y, 64, "pips are vertically centred")
local lit = 0
for i = 1, 8 do
    if rects[i].a == 1 then lit = lit + 1 end
end
Support.assertEqual(lit, 7, "3 + 4 pips lit")
Support.assertEqual(table.concat(keyDuringRender, ","), "nil,nil", "no-backpack note hidden during render")
Support.assertEqual(tooltipKey, "Tooltip_item_NoBackpack", "no-backpack note restored after render")
Support.assertEqual(UITooltip._active, nil, "active render cleared")

-- Measure-only passes size the tooltip without drawing.
texts, rects, measureOnly = {}, {}, true
ISToolTipInv.render(panel)
Support.assertEqual(#texts + #rects, 0, "measure-only pass draws nothing")
Support.assertEqual(tooltip.height, 102, "measure-only pass still sizes the tooltip")
measureOnly = false

-- Outside an AMS render (or for a different tooltip) the wrapper is inert.
item:DoTooltip(tooltip)
Support.assertEqual(calls.original, 1, "DoTooltip outside render uses vanilla")
UITooltip._active = { item = item, tooltip = {}, rows = rows }
item:DoTooltip(tooltip)
Support.assertEqual(calls.original, 2, "mismatched tooltip uses vanilla")
UITooltip._active = nil

-- Errors in the owner render still restore item state.
ISToolTipInv._amsTooltipRenderWrapper = nil
ISToolTipInv.render = function() error("owner boom") end
UITooltip.install()
local ok, err = pcall(ISToolTipInv.render, panel)
Support.assertFalse(ok, "owner errors propagate")
Support.assertTrue(string.find(tostring(err), "owner boom", 1, true) ~= nil, "owner error message preserved")
Support.assertEqual(tooltipKey, "Tooltip_item_NoBackpack", "tooltip key restored after owner error")
Support.assertEqual(UITooltip._active, nil, "active render cleared after owner error")
ISToolTipInv._amsTooltipRenderWrapper = nil
ISToolTipInv.render = originalRender
UITooltip.install()

-- Nothing to show: vanilla renders untouched.
signal = { burdenKg = 0.4, airflowResistance = 0, sealedRestriction = 0 }
Support.assertEqual(#UITooltip.buildRows(item), 0, "light item has no rows")
ISToolTipInv.render(panel)
Support.assertEqual(calls.original, 4, "rowless items keep vanilla DoTooltip")

-- Breathing toggle hides the breathing row.
signal = { burdenKg = 4.6, airflowResistance = 3.75, sealedRestriction = 1 }
SandboxVars = { ArmorMakesSense = { EnableBreathingModel = false } }
rows = UITooltip.buildRows(item)
Support.assertEqual(#rows, 1, "breathing disabled leaves burden only")
SandboxVars = nil

itemMethods.IsInventoryContainer = function() return true end
Support.assertEqual(#UITooltip.buildRows(item), 0, "containers get no AMS rows")
itemMethods.IsInventoryContainer = nil

-- A shared tooltip controller takes over row display.
EuryTooltipController = {
    installed = true,
    providers = {},
    registerProvider = function(self, id, provider) self.providers[id] = provider end,
}
UITooltip.install()
Support.assertEqual(EuryTooltipController.providers.ArmorMakesSense, UITooltip._provider, "provider registered")
local before = calls.original
ISToolTipInv.render(panel)
Support.assertEqual(calls.original, before + 2, "provider ownership leaves vanilla DoTooltip")
local providerRows = UITooltip._provider:getRows({ item = item })
Support.assertEqual(#providerRows, 2, "provider exposes both rows")
Support.assertEqual(providerRows[1].value, "3/4", "provider pip text")
EuryTooltipController = nil

print("ams tooltip lifecycle checks passed")
