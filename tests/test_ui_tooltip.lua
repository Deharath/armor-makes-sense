local source = debug.getinfo(1, "S").source
local scriptPath = string.sub(source, 2)
local testsDir = string.match(scriptPath, "(.*/)") or "./"
local rootDir = testsDir .. ".."

package.path = table.concat({
    rootDir .. "/common/media/lua/client/?.lua",
    rootDir .. "/common/media/lua/client/?/?.lua",
    rootDir .. "/common/media/lua/shared/?.lua",
    testsDir .. "?.lua",
    package.path,
}, ";")

local Support = dofile((os.getenv("AMS_ROOT") or rootDir) .. "/tests/support.lua")
local UITooltip = require "core/ArmorMakesSense_UITooltip"

ISToolTipInv = nil
UITooltip.install()

local originalRender = function()
    return "original"
end
ISToolTipInv = { render = originalRender }

UITooltip.install()

Support.assertTrue(
    ISToolTipInv.render ~= originalRender,
    "tooltip installation retries after the vanilla class becomes available"
)

local installedRender = ISToolTipInv.render
UITooltip.install()
Support.assertEqual(
    ISToolTipInv.render,
    installedRender,
    "tooltip installation remains idempotent"
)

local LoadModel = require "ArmorMakesSense_LoadModelShared"
local originalSignalResolver = LoadModel.itemToBurdenSignal
LoadModel.itemToBurdenSignal = function()
    return { physicalLoad = 14, airflowResistance = 2.2, sealedRestriction = 0 }
end

local originalTooltipCalls = 0
local embeddedTooltipCalls = 0
local completedLayouts = {}
local tooltipKey = "Tooltip_item_NoBackpack"
local tooltipSuppressedDuringRender = 0
local itemMethods = {
    getBodyLocation = function() return "ams:shoulderpad_left" end,
    getFullType = function() return "Base.Shoulderpad_Articulated_L_Metal" end,
    getTooltip = function() return tooltipKey end,
    setTooltip = function(_, value)
        tooltipKey = value
    end,
    DoTooltip = function(self, targetTooltip)
        originalTooltipCalls = originalTooltipCalls + 1
        targetTooltip:setWidth(170)
        targetTooltip:setHeight(100)
        if self:getTooltip() == nil then
            tooltipSuppressedDuringRender = tooltipSuppressedDuringRender + 1
        end
    end,
    DoTooltipEmbedded = function(self, _, layout)
        embeddedTooltipCalls = embeddedTooltipCalls + 1
        if self:getTooltip() == nil then
            tooltipSuppressedDuringRender = tooltipSuppressedDuringRender + 1
        end
        layout.offsetY = 30
        local encumbrance = layout:addItem()
        encumbrance:setLabel("Encumbrance:", 1, 1, 0.8, 1)
        encumbrance:setValue("2.0 (0.6 equipped)", 1, 1, 1, 1)
        local defense = layout:addItem()
        defense:setLabel("Bite Defense:", 1, 1, 0.8, 1)
        defense:setValue("100 (+100)", 0, 1, 0, 1)
        local combatSpeed = layout:addItem()
        combatSpeed:setLabel("Combat speed modifier:", 1, 1, 0.8, 1)
        combatSpeed:setProgress(0.5, 0.5, 0.5, 0.5, 1)
    end,
}
local item = setmetatable({}, { __index = itemMethods })
local tooltipHeight = 100
local tooltipWidth = 170
local function newLayout()
    local layout = {
        rows = {},
        minLabelWidth = 0,
        minValueWidth = 0,
        offsetY = 0,
    }
    function layout:setMinLabelWidth(width)
        self.minLabelWidth = width
    end
    function layout:setMinValueWidth(width)
        self.minValueWidth = width
    end
    function layout:addItem()
        local row = {}
        function row:setLabel(text)
            self.label = text
        end
        function row:setProgress(fraction)
            self.progress = fraction
        end
        function row:setValue(value)
            self.value = value
        end
        self.rows[#self.rows + 1] = row
        return row
    end
    function layout:render(x, y, targetTooltip)
        self.renderX = x
        self.renderY = y
        local labelWidth = self.minLabelWidth
        local valueWidth = self.minValueWidth
        for _, row in ipairs(self.rows) do
            if row.label == "Combat speed modifier:" then
                labelWidth = math.max(labelWidth, 200)
            end
            if row.value == "100 (+100)" then
                valueWidth = math.max(valueWidth, 157)
            end
        end
        targetTooltip:setWidth(x + labelWidth + 8 + valueWidth + targetTooltip.padRight)
        return y + (#self.rows * 14)
    end
    return layout
end
local tooltipMethods = {
    beginLayout = function()
        local layout = newLayout()
        completedLayouts[#completedLayouts + 1] = layout
        return layout
    end,
    endLayout = function() end,
    getFont = function() return "TooltipFont" end,
    getLineSpacing = function() return 20 end,
    getHeight = function() return tooltipHeight end,
    getWidth = function() return tooltipWidth end,
    setHeight = function(_, value) tooltipHeight = value end,
    setWidth = function(_, value) tooltipWidth = value end,
}
local tooltip = setmetatable({
    padRight = 10,
}, { __index = tooltipMethods })
getTextManager = function()
    return {
        MeasureStringX = function(_, font, text)
            Support.assertEqual(font, "TooltipFont", "tooltip geometry uses the active tooltip font")
            Support.assertEqual(text, "0", "tooltip geometry mirrors vanilla padding measurement")
            return 10
        end,
    }
end
local reflectionCalls = 0
getNumClassFields = function()
    reflectionCalls = reflectionCalls + 1
    error("Not in debug")
end
getClassField = getNumClassFields
getClassFieldVal = getNumClassFields
local panel = { item = item, tooltip = tooltip }
originalRender = function(self)
    self.item:DoTooltip(self.tooltip)
    self.item:DoTooltip(self.tooltip)
end
ISToolTipInv._amsTooltipRenderWrapper = nil
ISToolTipInv.render = originalRender
UITooltip.install()
ISToolTipInv.render(panel)
Support.assertEqual(itemMethods.DoTooltip, getmetatable(item).__index.DoTooltip, "AMS restores item DoTooltip after owner render")
Support.assertEqual(originalTooltipCalls, 0, "standalone AMS owns the eligible item's embedded tooltip path")
Support.assertEqual(embeddedTooltipCalls, 2, "AMS preserves both owner passes through DoTooltipEmbedded")
Support.assertEqual(#completedLayouts, 2, "AMS creates one combined layout per owner pass")
for _, layout in ipairs(completedLayouts) do
    Support.assertEqual(layout.minLabelWidth, 80, "combined layout preserves vanilla's minimum label width")
    Support.assertEqual(layout.minValueWidth, 80, "combined layout preserves vanilla's minimum value width")
    Support.assertEqual(#layout.rows, 5, "vanilla and AMS rows share one combined layout")
    Support.assertEqual(layout.rows[4].label, "Burden:", "burden follows the vanilla rows")
    Support.assertClose(layout.rows[4].progress, 0.5, 1e-9, "combined layout preserves the burden fraction")
    Support.assertEqual(layout.rows[5].label, "Breathing:", "breathing follows burden in the combined layout")
    Support.assertEqual(layout.rows[5].value, "Restricted", "combined layout preserves breathing text")
    Support.assertEqual(layout.renderX, 10, "combined layout derives vanilla left padding from font metrics")
    Support.assertEqual(layout.renderY, 30, "combined layout renders at vanilla's embedded content offset")
end
Support.assertEqual(tooltipWidth, 385, "widest vanilla label and value determine the shared tooltip width")
Support.assertEqual(tooltipHeight, 105, "combined layout owns the final tooltip height")
Support.assertEqual(tooltipSuppressedDuringRender, 2, "misleading shoulder warning is suppressed for both owner passes")
Support.assertEqual(tooltipKey, "Tooltip_item_NoBackpack", "shoulder tooltip state is restored after owner render")
Support.assertEqual(reflectionCalls, 0, "release tooltip rendering never calls debug-only reflection helpers")

local wrappedByAnotherMod = ISToolTipInv.render
ISToolTipInv.render = function(self)
    return wrappedByAnotherMod(self)
end
UITooltip.install()
ISToolTipInv.render(panel)
Support.assertEqual(embeddedTooltipCalls, 4, "rewrapping a competing owner preserves both combined-layout passes")
Support.assertEqual(#completedLayouts, 4, "nested AMS wrappers create one combined layout per owner pass")

EuryTooltipController = {
    installed = true,
    providers = {},
    registerProvider = function(self, id, provider)
        self.providers[id] = provider
    end,
}
UITooltip.install()
Support.assertEqual(
    EuryTooltipController.providers.ArmorMakesSense,
    UITooltip._provider,
    "AMS registers with an available shared tooltip controller"
)
ISToolTipInv.render(panel)
Support.assertEqual(#completedLayouts, 4, "provider ownership suppresses standalone duplicate layouts")
Support.assertEqual(originalTooltipCalls, 2, "provider ownership preserves the vanilla owner render")
Support.assertEqual(tooltipSuppressedDuringRender, 6, "provider path still suppresses the misleading shoulder warning")
Support.assertEqual(#UITooltip._provider:getRows({ item = item }), 2, "provider exposes both AMS rows")

LoadModel.itemToBurdenSignal = originalSignalResolver
EuryTooltipController = nil

print("ams tooltip lifecycle checks passed")
