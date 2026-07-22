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
local appendedRows = 0
local itemMethods = {
    getBodyLocation = function() return "TorsoExtra" end,
    DoTooltip = function()
        originalTooltipCalls = originalTooltipCalls + 1
    end,
}
local item = setmetatable({}, { __index = itemMethods })
local layout = {
    setMinLabelWidth = function() end,
    setMinValueWidth = function() end,
    addItem = function()
        appendedRows = appendedRows + 1
        return {
            setLabel = function() end,
            setProgress = function() end,
            setValue = function() end,
        }
    end,
}
local completedLayouts = 0
local tooltipMethods = {
    endLayout = function() end,
}
tooltipMethods.endLayout = function()
    completedLayouts = completedLayouts + 1
end
local tooltip = setmetatable({}, { __index = tooltipMethods })
local panel = { item = item, tooltip = tooltip }
originalRender = function(self)
    self.item:DoTooltip(self.tooltip)
    self.tooltip:endLayout(layout)
    self.item:DoTooltip(self.tooltip)
    self.tooltip:endLayout(layout)
end
ISToolTipInv._amsTooltipRenderWrapper = nil
ISToolTipInv.render = originalRender
UITooltip.install()
ISToolTipInv.render(panel)
Support.assertEqual(itemMethods.DoTooltip, getmetatable(item).__index.DoTooltip, "AMS never replaces item DoTooltip")
Support.assertEqual(originalTooltipCalls, 2, "AMS preserves both owner render passes")
Support.assertEqual(appendedRows, 4, "AMS contributes two rows to both tooltip layout passes")
Support.assertEqual(completedLayouts, 2, "AMS preserves vanilla layout completion")

local wrappedByAnotherMod = ISToolTipInv.render
ISToolTipInv.render = function(self)
    return wrappedByAnotherMod(self)
end
UITooltip.install()
ISToolTipInv.render(panel)
Support.assertEqual(originalTooltipCalls, 4, "rewrapping a competing renderer preserves both owner calls")
Support.assertEqual(appendedRows, 8, "nested AMS wrappers contribute rows only once per layout")

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
Support.assertEqual(appendedRows, 8, "provider ownership suppresses layout-extension duplicate rows")
Support.assertEqual(#UITooltip._provider:getRows({ item = item }), 2, "provider exposes both AMS rows")

LoadModel.itemToBurdenSignal = originalSignalResolver
EuryTooltipController = nil

print("ams tooltip lifecycle checks passed")
