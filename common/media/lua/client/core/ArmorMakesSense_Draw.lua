ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.Core = ArmorMakesSense.Core or {}

-- Shared drawing vocabulary for the Burden tab and item tooltips.
local Draw = ArmorMakesSense.Core.Draw or {}
ArmorMakesSense.Core.Draw = Draw

local function rgb(r, g, b)
    return { r = r, g = g, b = b }
end

Draw.C = {
    text = rgb(0.95, 0.92, 0.85),
    label = rgb(0.85, 0.82, 0.75),
    header = rgb(0.72, 0.68, 0.58),
    dim = rgb(0.55, 0.54, 0.50),
    sep = rgb(0.35, 0.35, 0.35),
    track = rgb(1, 1, 1),
    burden = rgb(0.95, 0.70, 0.25),
    heat = rgb(0.95, 0.52, 0.30),
    breathing = rgb(0.55, 0.75, 0.95),
    sleep = rgb(0.70, 0.62, 0.90),
    warn = rgb(1.0, 0.78, 0.36),
    bad = rgb(0.95, 0.38, 0.30),
    tooltipLabel = rgb(1.0, 1.0, 0.8),
    good = rgb(0.55, 0.82, 0.50),
    swing = rgb(0.85, 0.72, 0.55),
}

Draw.TRACK_ALPHA = 0.13

function Draw.fontHeight(font)
    local tm = type(getTextManager) == "function" and getTextManager() or nil
    return tm and tm:getFontHeight(font) or 14
end

function Draw.textWidth(font, text)
    local tm = type(getTextManager) == "function" and getTextManager() or nil
    return tm and tm:MeasureStringX(font, tostring(text or "")) or (#tostring(text or "") * 7)
end

function Draw.wrap(font, text, width)
    local lines, line = {}, ""
    for word in string.gmatch(tostring(text or ""), "%S+") do
        local candidate = line == "" and word or (line .. " " .. word)
        if line ~= "" and Draw.textWidth(font, candidate) > width then
            lines[#lines + 1] = line
            line = word
        else
            line = candidate
        end
    end
    if line ~= "" then
        lines[#lines + 1] = line
    end
    return lines
end

-- Rect sinks: fn(x, y, w, h, color, alpha).
function Draw.elementSink(el)
    return function(x, y, w, h, c, a)
        el:drawRect(x, y, w, h, a, c.r, c.g, c.b)
    end
end

function Draw.tooltipSink(tooltip)
    return function(x, y, w, h, c, a)
        tooltip:DrawTextureScaledColor(nil, x, y, w, h, c.r, c.g, c.b, a)
    end
end

function Draw.pipGeometry(lineHeight)
    local size = math.max(5, math.floor(lineHeight * 0.5))
    local gap = math.max(2, math.floor(size * 0.45))
    return size, gap
end

function Draw.pipStripWidth(count, size, gap)
    return count * size + (count - 1) * gap
end

-- `filled` whole pips out of `count`; returns the strip width.
function Draw.pips(sink, x, y, count, filled, size, gap, color, alpha)
    local lit = math.max(0, math.min(count, math.floor(tonumber(filled) or 0)))
    for i = 1, count do
        local px = x + (i - 1) * (size + gap)
        if i <= lit then
            sink(px, y, size, size, color, alpha or 1)
        else
            sink(px, y, size, size, Draw.C.track, Draw.TRACK_ALPHA)
        end
    end
    return Draw.pipStripWidth(count, size, gap)
end

-- Segmented bar: `count` cells across `w`, filled to a fractional `fill`.
function Draw.cells(sink, x, y, w, h, count, fill, color, gap)
    local g = gap or 3
    local cellW = math.floor((w - g * (count - 1)) / count)
    local f = math.max(0, math.min(count, tonumber(fill) or 0))
    for i = 1, count do
        local cx = x + (i - 1) * (cellW + g)
        sink(cx, y, cellW, h, Draw.C.track, Draw.TRACK_ALPHA)
        local part = math.max(0, math.min(1, f - (i - 1)))
        if part > 0 then
            sink(cx, y, math.max(1, math.floor(cellW * part + 0.5)), h, color, 0.95)
        end
    end
end

return Draw
