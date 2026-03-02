ArmorMakesSense = ArmorMakesSense or {}

-- Module load guard.
if ArmorMakesSense._slotCompatLoaded then
    return
end
ArmorMakesSense._slotCompatLoaded = true

local function log(msg)
    print('[ArmorMakesSense] ' .. tostring(msg))
end

local function hasFunction(target, methodName)
    return target and type(target[methodName]) == "function"
end

local function resolveLocation(id)
    if not ItemBodyLocation or not ResourceLocation then
        return nil
    end
    if type(ResourceLocation.of) ~= "function" or type(ItemBodyLocation.get) ~= "function" then
        return nil
    end
    local ok, loc = pcall(ItemBodyLocation.get, ResourceLocation.of(id))
    if not ok then
        return nil
    end
    return loc
end

local function safeSetExclusive(group, a, b)
    if a and b and hasFunction(group, "setExclusive") then
        pcall(group.setExclusive, group, a, b)
    end
end

local function safeSetHideModel(group, a, b)
    if a and b and hasFunction(group, "setHideModel") then
        pcall(group.setHideModel, group, a, b)
    end
end

local function safeMoveToIndex(group, loc, index)
    if not loc or not hasFunction(group, "moveLocationToIndex") then
        return
    end
    pcall(group.moveLocationToIndex, group, loc, index)
end

local function registerCustomLocations()
    if not BodyLocations or not ItemBodyLocation or not ResourceLocation then
        log("SlotCompat skipped: BodyLocations/ItemBodyLocation/ResourceLocation unavailable")
        return
    end

    local group = BodyLocations.getGroup and BodyLocations.getGroup("Human")
    if not group then
        log("SlotCompat skipped: Human BodyLocationGroup unavailable")
        return
    end

    -- Stable id map for AMS custom body locations.
    local ids = {
        shoulderpad_left = "ams:shoulderpad_left",
        shoulderpad_right = "ams:shoulderpad_right",
        sport_shoulderpad = "ams:sport_shoulderpad",
        sport_shoulderpad_on_top = "ams:sport_shoulderpad_on_top",
        forearm_left = "ams:forearm_left",
        forearm_right = "ams:forearm_right",
        cuirass = "ams:cuirass",
        torso_extra_vest_bullet = "ams:torso_extra_vest_bullet",
    }

    local custom = {}
    local registeredCount = 0
    for key, id in pairs(ids) do
        local okRegister = pcall(ItemBodyLocation.register, id)
        if okRegister then
            registeredCount = registeredCount + 1
        end
        local loc = resolveLocation(id)
        custom[key] = loc
        if loc and hasFunction(group, "getOrCreateLocation") then
            pcall(group.getOrCreateLocation, group, loc)
        end
    end

    local function ex(a, b)
        safeSetExclusive(group, a, b)
    end

    -- Exclusivity rules.

    -- ams:shoulderpad_left (drop BACK/WEBBING/SHOULDER_HOLSTER)
    ex(custom.shoulderpad_left, ItemBodyLocation.FULL_SUIT_HEAD)
    ex(custom.shoulderpad_left, ItemBodyLocation.FULL_SUIT)
    ex(custom.shoulderpad_left, ItemBodyLocation.FULL_TOP)
    ex(custom.shoulderpad_left, ItemBodyLocation.TORSO_EXTRA_VEST_BULLET)
    ex(custom.shoulderpad_left, custom.torso_extra_vest_bullet)
    ex(custom.shoulderpad_left, ItemBodyLocation.SPORT_SHOULDERPAD)
    ex(custom.shoulderpad_left, custom.sport_shoulderpad)
    ex(custom.shoulderpad_left, ItemBodyLocation.SPORT_SHOULDERPAD_ON_TOP)
    ex(custom.shoulderpad_left, custom.sport_shoulderpad_on_top)
    ex(custom.shoulderpad_left, ItemBodyLocation.SCBA)
    ex(custom.shoulderpad_left, ItemBodyLocation.SCBANOTANK)

    -- ams:shoulderpad_right (drop BACK/WEBBING/SHOULDER_HOLSTER)
    ex(custom.shoulderpad_right, ItemBodyLocation.FULL_SUIT_HEAD)
    ex(custom.shoulderpad_right, ItemBodyLocation.FULL_SUIT)
    ex(custom.shoulderpad_right, ItemBodyLocation.FULL_TOP)
    ex(custom.shoulderpad_right, ItemBodyLocation.TORSO_EXTRA_VEST_BULLET)
    ex(custom.shoulderpad_right, custom.torso_extra_vest_bullet)
    ex(custom.shoulderpad_right, ItemBodyLocation.SPORT_SHOULDERPAD)
    ex(custom.shoulderpad_right, custom.sport_shoulderpad)
    ex(custom.shoulderpad_right, ItemBodyLocation.SPORT_SHOULDERPAD_ON_TOP)
    ex(custom.shoulderpad_right, custom.sport_shoulderpad_on_top)
    ex(custom.shoulderpad_right, ItemBodyLocation.SCBA)
    ex(custom.shoulderpad_right, ItemBodyLocation.SCBANOTANK)

    -- ams:sport_shoulderpad (clone all vanilla exclusions minus BACK/WEBBING/SHOULDER_HOLSTER)
    local sportShoulderpadKeeps = {
        ItemBodyLocation.FULL_SUIT_HEAD,
        ItemBodyLocation.FULL_SUIT,
        ItemBodyLocation.FULL_TOP,
        ItemBodyLocation.BOILERSUIT,
        ItemBodyLocation.BATH_ROBE,
        ItemBodyLocation.FULL_ROBE,
        ItemBodyLocation.JACKET_HAT,
        ItemBodyLocation.JACKET_HAT_BULKY,
        ItemBodyLocation.JACKET,
        ItemBodyLocation.JACKET_BULKY,
        ItemBodyLocation.JACKET_DOWN,
        ItemBodyLocation.SWEATER,
        ItemBodyLocation.SWEATER_HAT,
        ItemBodyLocation.TORSO_EXTRA,
        ItemBodyLocation.TORSO_EXTRA_VEST,
        ItemBodyLocation.TORSO_EXTRA_VEST_BULLET,
        ItemBodyLocation.CUIRASS,
        ItemBodyLocation.SPORT_SHOULDERPAD_ON_TOP,
        ItemBodyLocation.SCBA,
        ItemBodyLocation.SCBANOTANK,
        ItemBodyLocation.SHOULDERPAD_RIGHT,
        ItemBodyLocation.SHOULDERPAD_LEFT,
    }
    for _, loc in ipairs(sportShoulderpadKeeps) do
        ex(custom.sport_shoulderpad, loc)
    end
    ex(custom.sport_shoulderpad, custom.sport_shoulderpad_on_top)
    ex(custom.sport_shoulderpad, custom.shoulderpad_right)
    ex(custom.sport_shoulderpad, custom.shoulderpad_left)
    ex(custom.sport_shoulderpad, custom.cuirass)
    ex(custom.sport_shoulderpad, custom.torso_extra_vest_bullet)

    -- ams:sport_shoulderpad_on_top (clone all vanilla exclusions minus BACK/WEBBING/SHOULDER_HOLSTER)
    local sportShoulderpadOnTopKeeps = {
        ItemBodyLocation.TORSO_EXTRA_VEST,
        ItemBodyLocation.TORSO_EXTRA_VEST_BULLET,
        ItemBodyLocation.SCBA,
        ItemBodyLocation.SCBANOTANK,
        ItemBodyLocation.SHOULDERPAD_RIGHT,
        ItemBodyLocation.SHOULDERPAD_LEFT,
        ItemBodyLocation.SPORT_SHOULDERPAD,
    }
    for _, loc in ipairs(sportShoulderpadOnTopKeeps) do
        ex(custom.sport_shoulderpad_on_top, loc)
    end
    ex(custom.sport_shoulderpad_on_top, custom.torso_extra_vest_bullet)
    ex(custom.sport_shoulderpad_on_top, custom.shoulderpad_right)
    ex(custom.sport_shoulderpad_on_top, custom.shoulderpad_left)
    ex(custom.sport_shoulderpad_on_top, custom.sport_shoulderpad)

    -- ams:forearm_left / ams:forearm_right drop wrist exclusions entirely

    -- ams:cuirass (drop SHOULDER_HOLSTER)
    ex(custom.cuirass, ItemBodyLocation.TORSO_EXTRA)
    ex(custom.cuirass, ItemBodyLocation.TORSO_EXTRA_VEST)
    ex(custom.cuirass, ItemBodyLocation.TORSO_EXTRA_VEST_BULLET)
    ex(custom.cuirass, custom.torso_extra_vest_bullet)
    ex(custom.cuirass, ItemBodyLocation.SCBA)
    ex(custom.cuirass, ItemBodyLocation.SCBANOTANK)

    -- ams:torso_extra_vest_bullet (drop SHOULDERPAD_LEFT / SHOULDERPAD_RIGHT)
    ex(custom.torso_extra_vest_bullet, ItemBodyLocation.TORSO_EXTRA)
    ex(custom.torso_extra_vest_bullet, ItemBodyLocation.TORSO_EXTRA_VEST)
    ex(custom.torso_extra_vest_bullet, ItemBodyLocation.SHOULDER_HOLSTER)
    ex(custom.torso_extra_vest_bullet, custom.cuirass)

    -- Explicit cross-exclusions between custom shoulderpad variants
    ex(custom.shoulderpad_left, custom.sport_shoulderpad)
    ex(custom.shoulderpad_left, custom.sport_shoulderpad_on_top)
    ex(custom.shoulderpad_right, custom.sport_shoulderpad)
    ex(custom.shoulderpad_right, custom.sport_shoulderpad_on_top)

    -- hideModel parity for affected slots.
    safeSetHideModel(group, custom.torso_extra_vest_bullet, ItemBodyLocation.FANNY_PACK_FRONT)
    safeSetHideModel(group, custom.cuirass, ItemBodyLocation.FANNY_PACK_FRONT)
    safeSetHideModel(group, custom.torso_extra_vest_bullet, ItemBodyLocation.FANNY_PACK_BACK)
    safeSetHideModel(group, custom.cuirass, ItemBodyLocation.FANNY_PACK_BACK)
    safeSetHideModel(group, custom.cuirass, ItemBodyLocation.NECKLACE)
    safeSetHideModel(group, custom.cuirass, ItemBodyLocation.NECKLACE_LONG)
    safeSetHideModel(group, custom.torso_extra_vest_bullet, ItemBodyLocation.NECKLACE)
    safeSetHideModel(group, custom.torso_extra_vest_bullet, ItemBodyLocation.NECKLACE_LONG)
    safeSetHideModel(group, custom.torso_extra_vest_bullet, ItemBodyLocation.NECK)
    safeSetHideModel(group, ItemBodyLocation.JACKET_HAT, custom.torso_extra_vest_bullet)
    safeSetHideModel(group, ItemBodyLocation.JACKET_DOWN, custom.torso_extra_vest_bullet)
    safeSetHideModel(group, ItemBodyLocation.JACKET_HAT, custom.cuirass)
    safeSetHideModel(group, ItemBodyLocation.JACKET_DOWN, custom.cuirass)
    safeSetHideModel(group, ItemBodyLocation.FULL_ROBE, custom.torso_extra_vest_bullet)
    safeSetHideModel(group, ItemBodyLocation.FULL_ROBE, custom.cuirass)
    safeSetHideModel(group, ItemBodyLocation.FULL_ROBE, custom.forearm_left)
    safeSetHideModel(group, ItemBodyLocation.FULL_ROBE, custom.forearm_right)
    safeSetHideModel(group, ItemBodyLocation.FULL_ROBE, custom.shoulderpad_left)
    safeSetHideModel(group, ItemBodyLocation.FULL_ROBE, custom.shoulderpad_right)
    safeSetHideModel(group, ItemBodyLocation.JERSEY, custom.sport_shoulderpad)

    -- Keep custom locations near vanilla render indices.
    local function moveNear(vanillaLoc, customLoc)
        if not vanillaLoc or not customLoc or not hasFunction(group, "indexOf") then
            return
        end
        local ok, index = pcall(group.indexOf, group, vanillaLoc)
        if ok and type(index) == "number" and index >= 0 then
            safeMoveToIndex(group, customLoc, index)
        end
    end

    moveNear(ItemBodyLocation.SHOULDERPAD_LEFT, custom.shoulderpad_left)
    moveNear(ItemBodyLocation.SHOULDERPAD_RIGHT, custom.shoulderpad_right)
    moveNear(ItemBodyLocation.SPORT_SHOULDERPAD, custom.sport_shoulderpad)
    moveNear(ItemBodyLocation.SPORT_SHOULDERPAD_ON_TOP, custom.sport_shoulderpad_on_top)
    moveNear(ItemBodyLocation.FORE_ARM_LEFT, custom.forearm_left)
    moveNear(ItemBodyLocation.FORE_ARM_RIGHT, custom.forearm_right)
    moveNear(ItemBodyLocation.CUIRASS, custom.cuirass)
    moveNear(ItemBodyLocation.TORSO_EXTRA_VEST_BULLET, custom.torso_extra_vest_bullet)

    local resolvedCount = 0
    for _, loc in pairs(custom) do
        if loc then
            resolvedCount = resolvedCount + 1
        end
    end
    log(string.format("SlotCompat initialized: register attempts=%d, resolved locations=%d", registeredCount, resolvedCount))
end

registerCustomLocations()
