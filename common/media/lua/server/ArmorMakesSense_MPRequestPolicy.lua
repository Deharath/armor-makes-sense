ArmorMakesSense = ArmorMakesSense or {}
ArmorMakesSense.MPRequestPolicy = ArmorMakesSense.MPRequestPolicy or {}

local Policy = ArmorMakesSense.MPRequestPolicy

function Policy.acceptSnapshotRequest(mpState, nowSecond, intervalSeconds)
    if type(mpState) ~= "table" then
        return false
    end

    local now = tonumber(nowSecond) or 0
    local interval = math.max(0, tonumber(intervalSeconds) or 0)
    local last = tonumber(mpState.lastClientSnapshotRequestWallSecond) or 0
    if last > 0 and now >= last and (now - last) < interval then
        return false
    end

    mpState.lastClientSnapshotRequestWallSecond = now
    return true
end

return Policy
