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

print("ams tooltip lifecycle checks passed")
