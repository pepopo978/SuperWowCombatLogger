local function containsPrefix(lines, prefix)
    for _, line in ipairs(lines) do
        if string.sub(line, 1, string.len(prefix)) == prefix then
            return true
        end
    end
    return false
end

local function containsText(lines, expected)
    for _, line in ipairs(lines) do
        if string.find(line, expected, 1, true) then
            return true
        end
    end
    return false
end

local function countPrefix(lines, prefix)
    local count = 0
    for _, line in ipairs(lines) do
        if string.sub(line, 1, string.len(prefix)) == prefix then
            count = count + 1
        end
    end
    return count
end

local function assertTrue(condition, message)
    if not condition then
        error(message)
    end
end

local function makeItemLink(itemId, label)
    return "|cff1eff00|Hitem:" .. tostring(itemId) .. ":0:0:0|h[" .. label .. "]|h|r"
end

local function newHarness(opts)
    opts = opts or {}

    package.loaded["RPLLCollector"] = nil
    package.loaded["SuperWowCombatLogger"] = nil

    local registered = {}
    local onUpdate = nil
    local logLines = {}
    local loggingCalls = {}
    local loggingEnabled = false
    local zone = opts.zone or "Zul'Gurub"
    local savedInstances = opts.savedInstances or {}
    local inventory = opts.inventory or {}
    local unitNames = opts.unitNames or {}
    local unitExists = opts.unitExists or {}
    local spellInfo = opts.spellInfo or {}

    _G.SetAutoloot = true
    _G.RPLL = nil
    _G.UNKNOWN = "Unknown"
    _G.UNKNOWNOBJECT = "Unknown"
    _G.strlower = string.lower
    _G.strlen = string.len
    _G.StaticPopupDialogs = {}
    _G.StaticPopup_Show = function() end
    _G.TEXT = function(text) return text end
    _G.OKAY = "OKAY"
    _G.arg = nil

    _G.CombatLogAdd = function(message)
        table.insert(logLines, message)
    end
    _G.LoggingCombat = function(enabled)
        if enabled ~= nil then
            loggingEnabled = not (enabled == 0 or enabled == false or enabled == nil)
            table.insert(loggingCalls, enabled)
        end
        if loggingEnabled then
            return 1
        end
        return nil
    end
    _G.GetTime = opts.getTime or function()
        return 0
    end
    _G.time = opts.time or function()
        return 0
    end
    _G.date = function(fmt)
        if fmt == "%z" then
            return "+0000"
        end
        if fmt == "%d.%m.%y %H:%M:%S %z" then
            return "01.01.26 00:00:00 +0000"
        end
        return "01.01.26 00:00:00"
    end
    _G.GetRealZoneText = function()
        return zone
    end
    _G.IsInInstance = opts.isInInstance or function()
        return nil
    end
    _G.GetNumSavedInstances = function()
        return #savedInstances
    end
    _G.GetSavedInstanceInfo = function(index)
        local entry = savedInstances[index]
        if not entry then
            return nil
        end
        return entry.name, entry.id
    end
    _G.GetNumRaidMembers = opts.getNumRaidMembers or function()
        return 0
    end
    _G.GetNumPartyMembers = opts.getNumPartyMembers or function()
        return 0
    end
    _G.UnitInRaid = opts.unitInRaid or function()
        return nil
    end
    _G.UnitInParty = opts.unitInParty or function()
        return nil
    end
    _G.UnitAffectingCombat = opts.unitAffectingCombat or function()
        return nil
    end
    _G.UnitIsGhost = opts.unitIsGhost or function()
        return false
    end
    _G.UnitIsPlayer = opts.unitIsPlayer or function(unit)
        return string.find(unit, "player", 1, true) == 1
            or string.find(unit, "raid", 1, true) == 1
            or string.find(unit, "party", 1, true) == 1
    end
    _G.UnitName = opts.unitName or function(unit)
        return unitNames[unit]
    end
    _G.UnitExists = opts.unitExistsFn or function(unit)
        local entry = unitExists[unit]
        if entry == nil then
            return nil, nil
        end
        if type(entry) == "table" then
            return entry[1], entry[2]
        end
        return entry, nil
    end
    _G.GetGuildInfo = opts.getGuildInfo or function()
        return nil
    end
    _G.UnitClass = opts.unitClass or function()
        return "Warrior", "WARRIOR"
    end
    _G.UnitRace = opts.unitRace or function()
        return "Human", "Human"
    end
    _G.UnitSex = opts.unitSex or function()
        return 2
    end
    _G.GetInventoryItemLink = opts.getInventoryItemLink or function(unit, slot)
        return inventory[unit] and inventory[unit][slot] or nil
    end
    _G.GetNumTalents = opts.getNumTalents or function()
        return 0
    end
    _G.GetTalentInfo = opts.getTalentInfo or function()
        return nil, nil, nil, nil, 0
    end
    _G.SpellInfo = opts.spellInfoFn or function(spellId)
        local entry = spellInfo[spellId]
        if type(entry) == "table" then
            return entry[1], entry[2]
        end
        return entry
    end

    _G.CreateFrame = function(_, name)
        local frame = {}
        function frame:RegisterEvent(eventName)
            registered[eventName] = true
        end
        function frame:SetScript(scriptName, fn)
            if scriptName == "OnUpdate" then
                onUpdate = fn
            elseif scriptName == "OnEvent" then
                frame.onEvent = fn
            end
        end
        return frame
    end

    dofile("RPLLCollector.lua")
    dofile("SuperWowCombatLogger.lua")

    return {
        logLines = logLines,
        loggingCalls = loggingCalls,
        registered = registered,
        onUpdate = onUpdate,
        rpll = _G.RPLL,
        setZone = function(value)
            zone = value
        end,
        setUnitName = function(unit, value)
            unitNames[unit] = value
        end,
        setUnitExists = function(unit, exists, guid)
            unitExists[unit] = { exists, guid }
        end,
        setInventory = function(unit, slot, value)
            inventory[unit] = inventory[unit] or {}
            inventory[unit][slot] = value
        end,
    }
end

local function dispatchHandler(ctx, name, ...)
    _G.this = ctx.rpll
    local handler = ctx.rpll[name]
    return handler(...)
end

local function dispatchMethod(ctx, name, ...)
    _G.this = ctx.rpll
    return ctx.rpll[name](ctx.rpll, ...)
end

local function tick(ctx, elapsed)
    if ctx.onUpdate then
        _G.this = ctx.rpll
        ctx.onUpdate(elapsed or 0)
    end
end

local function testRescansRaidRosterWhenHeadcountStaysFlat()
    local ctx = newHarness({
        getNumRaidMembers = function()
            return 2
        end,
        unitNames = {
            raid1 = "Alpha",
            raid2 = "Bravo",
        },
        unitExists = {
            raid1 = { true, "0xA" },
            raid2 = { true, "0xB" },
        },
        inventory = {
            raid1 = { [1] = makeItemLink(1001, "Helm A") },
            raid2 = { [1] = makeItemLink(1002, "Helm B") },
        },
    })

    dispatchHandler(ctx, "RAID_ROSTER_UPDATE")
    ctx.setUnitName("raid2", "Charlie")
    ctx.setUnitExists("raid2", true, "0xC")
    ctx.setInventory("raid2", 1, makeItemLink(1003, "Helm C"))
    dispatchHandler(ctx, "RAID_ROSTER_UPDATE")

    assertTrue(containsText(ctx.logLines, "&Charlie&"), "expected same-count raid roster swap to log Charlie combatant info")
end

local function testRetriesCombatantInfoWhenFirstScanHasNoGear()
    local now = 100
    local ctx = newHarness({
        time = function()
            return now
        end,
        unitNames = {
            raid1 = "Alpha",
        },
        unitExists = {
            raid1 = { true, "0xA" },
        },
    })

    dispatchMethod(ctx, "grab_unit_information", "raid1")
    ctx.setInventory("raid1", 1, makeItemLink(1001, "Helm A"))
    dispatchMethod(ctx, "grab_unit_information", "raid1")

    assertTrue(containsText(ctx.logLines, "&Alpha&"), "expected second combatant scan to succeed after gear loads")
end

local function testEmitsOneAuthoritativeCastLinePerTrackedCast()
    local ctx = newHarness({
        unitNames = {
            casterguid = "Warrior",
            targetguid = "Target",
        },
        spellInfo = {
            [11597] = { "Sunder Armor", "Rank 5" },
        },
    })

    local before = #ctx.logLines
    dispatchHandler(ctx, "UNIT_CASTEVENT", "casterguid", "targetguid", "CAST", 11597, 0)
    local emitted = #ctx.logLines - before

    assertTrue(emitted == 1, "expected one cast line for a tracked cast event")
end

local function testUsesAmbiguitySafeConsumeLabels()
    local ctx = newHarness({
        unitNames = {
            casterguid = "Chef",
        },
    })

    dispatchHandler(ctx, "UNIT_CASTEVENT", "casterguid", nil, "CAST", 24800, 0)

    assertTrue(containsText(ctx.logLines, "Ambiguous"), "expected an ambiguity-safe consume label")
    assertTrue(not containsText(ctx.logLines, "Power Mushroom"), "did not expect a guessed specific item label")
end

local function testPreservesExactUnambiguousConsumeLabels()
    local ctx = newHarness({
        unitNames = {
            casterguid = "Chef",
        },
    })

    dispatchHandler(ctx, "UNIT_CASTEVENT", "casterguid", nil, "CAST", 10667, 0)

    assertTrue(containsText(ctx.logLines, "R.O.I.D.S."), "expected exact punctuation for unambiguous consume labels")
    assertTrue(not containsText(ctx.logLines, "Rage of Ages"), "did not expect the old sanitized consume label")
end

local function testInitializesSpecialTargetsByZone()
    local ctx = newHarness({
        zone = "Blackwing Lair",
        unitNames = {
            bossguid = "Firemaw",
            bossguidtarget = "Tank",
        },
        spellInfo = {
            [22539] = { "Shadow Flame", "" },
        },
    })

    dispatchHandler(ctx, "ZONE_CHANGED_NEW_AREA")
    dispatchHandler(ctx, "UNIT_CASTEVENT", "bossguid", nil, "CAST", 22539, 0)

    assertTrue(containsText(ctx.logLines, "on Tank"), "expected specials target enrichment to use the caster target in configured zones")
end

local function testNormalizesZoneInfoAliasesAndPreservesFallbackCase()
    local ctx = newHarness({
        zone = "Ahn'Qiraj Temple",
        savedInstances = {
            { name = "Temple of Ahn'Qiraj", id = 123 },
        },
    })

    dispatchMethod(ctx, "QueueRaidIds")
    assertTrue(containsText(ctx.logLines, "&Temple of Ahn'Qiraj&123"), "expected normalized ZONE_INFO match for AQ alias")

    local fallbackCtx = newHarness({
        zone = "Blackrock Spire",
    })
    dispatchMethod(fallbackCtx, "QueueRaidIds")
    assertTrue(containsText(fallbackCtx.logLines, "&Blackrock Spire&0"), "expected fallback ZONE_INFO to preserve original case")
end

local function testBroadensTradeDetectionBeyondAsciiWordNames()
    local ctx = newHarness()

    dispatchHandler(ctx, "CHAT_MSG_SYSTEM", "René trades item Libram of the Faithful to Milkpress.")

    assertTrue(containsPrefix(ctx.logLines, "LOOT_TRADE: "), "expected LOOT_TRADE for accented player names")
end

local function testUsesGuidCacheForUnitDied()
    local ctx = newHarness({
        unitNames = {
            raid1 = "Alpha",
        },
        unitExists = {
            raid1 = { true, "0xA" },
        },
        inventory = {
            raid1 = { [1] = makeItemLink(1001, "Helm A") },
        },
        unitName = function(unit)
            if unit == "raid1" then
                return "Alpha"
            end
            return nil
        end,
    })

    dispatchMethod(ctx, "grab_unit_information", "raid1")
    dispatchHandler(ctx, "UNIT_DIED", "0xA")

    assertTrue(containsText(ctx.logLines, "UNIT_DIED:Alpha:0xA"), "expected UNIT_DIED to resolve cached GUID names")
end

local function testDeepSubstringHandlesTailTokensCorrectly()
    local ctx = newHarness()

    local ok, result = pcall(function()
        return dispatchMethod(ctx, "DeepSubString", "alpha beta", "betamax")
    end)

    assertTrue(ok, "expected DeepSubString tail-token matching not to error")
    assertTrue(result == true, "expected DeepSubString to match against the final token")
end

testRescansRaidRosterWhenHeadcountStaysFlat()
testRetriesCombatantInfoWhenFirstScanHasNoGear()
testEmitsOneAuthoritativeCastLinePerTrackedCast()
testUsesAmbiguitySafeConsumeLabels()
testPreservesExactUnambiguousConsumeLabels()
testInitializesSpecialTargetsByZone()
testNormalizesZoneInfoAliasesAndPreservesFallbackCase()
testBroadensTradeDetectionBeyondAsciiWordNames()
testUsesGuidCacheForUnitDied()
testDeepSubstringHandlesTailTokensCorrectly()
print("ok - SuperWowCombatLogger regression tests passed")
