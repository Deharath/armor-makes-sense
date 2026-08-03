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

function Policy.queueSnapshotRequest(mpState)
    if type(mpState) ~= "table" then
        return false
    end
    mpState.pendingSnapshotRequest = true
    return true
end

function Policy.canFlushSnapshot(mpState, snapshot)
    if type(mpState) ~= "table"
        or mpState.pendingSnapshotRequest ~= true
        or type(snapshot) ~= "table" then
        return false
    end
    return true
end

function Policy.completeSnapshotRequest(mpState)
    if type(mpState) ~= "table" then
        return false
    end
    mpState.pendingSnapshotRequest = false
    return true
end

return Policy
