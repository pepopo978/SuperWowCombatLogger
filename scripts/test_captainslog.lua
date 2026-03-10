local function containsPrefix(lines, prefix)
    for _, line in ipairs(lines) do
        if string.sub(line, 1, string.len(prefix)) == prefix then
            return true
        end
    end
    return false
end

local function containsValue(lines, expected)
    for _, line in ipairs(lines) do
        if line == expected then
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

local function lastValue(lines)
    return lines[#lines]
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

local function newHarness(zoneProvider, opts)
    opts = opts or {}

    local registered = {}
    local onEvent = nil
    local onUpdate = nil
    local loggingCalls = {}
    local combatLogLines = {}
    local chatLines = {}
    local loggingEnabled = false

    _G.CombatLogAdd = function(message)
        table.insert(combatLogLines, message)
    end
    _G.LoggingCombat = function(enabled)
        if enabled ~= nil then
            if enabled == 0 or enabled == false then
                loggingEnabled = false
            else
                loggingEnabled = true
            end
            table.insert(loggingCalls, enabled)
        end
        if loggingEnabled then
            return 1
        end
        return nil
    end
    _G.GetRealZoneText = zoneProvider
    _G.date = function()
        return "2026-02-25 20:00:00"
    end
    _G.GetGameTime = opts.getGameTime or function()
        return 20, 0
    end
    _G.GetTime = opts.getTime or function()
        return 0
    end
    _G.IsInInstance = opts.isInInstance or function()
        return nil
    end
    _G.DEFAULT_CHAT_FRAME = {
        AddMessage = function(_, msg)
            table.insert(chatLines, msg)
        end
    }
    _G.GetNumRaidMembers = opts.getNumRaidMembers or function()
        return 0
    end
    _G.GetRaidRosterInfo = opts.getRaidRosterInfo or function()
        return nil
    end
    _G.UnitIsDeadOrGhost = opts.unitIsDeadOrGhost or function()
        return false
    end
    _G.UnitAffectingCombat = opts.unitAffectingCombat or function()
        return false
    end
    _G.UnitName = opts.unitName or function(unit)
        return unit
    end
    _G.AceLibrary = opts.aceLibrary
    _G.SlashCmdList = {}
    _G.IsAddOnLoaded = opts.isAddOnLoaded or function()
        return false
    end
    _G.RPLL = opts.rpll

    _G.CreateFrame = function()
        local frame = {}
        function frame:RegisterEvent(name)
            registered[name] = true
        end
        function frame:SetScript(name, fn)
            if name == "OnEvent" then
                onEvent = fn
            elseif name == "OnUpdate" then
                onUpdate = fn
            end
        end
        return frame
    end

    dofile("CaptainsLog.lua")

    return {
        registered = registered,
        onEvent = onEvent,
        onUpdate = onUpdate,
        loggingCalls = loggingCalls,
        combatLogLines = combatLogLines,
        chatLines = chatLines,
        getLoggingEnabled = function()
            return loggingEnabled
        end,
    }
end

local function dispatch(ctx, eventName, arg1Value)
    _G.event = eventName
    _G.arg1 = arg1Value
    ctx.onEvent()
    _G.arg1 = nil
end

local function tick(ctx, elapsed)
    if ctx.onUpdate then
        ctx.onUpdate(elapsed or 0)
    end
end

local function assertTrue(condition, message)
    if not condition then
        error(message)
    end
end

local function testRecoversWhenInitialZoneIsEmpty()
    local zone = ""
    local ctx = newHarness(function()
        return zone
    end)

    assertTrue(ctx.registered["PLAYER_REGEN_DISABLED"], "expected PLAYER_REGEN_DISABLED to be registered")

    dispatch(ctx, "PLAYER_ENTERING_WORLD")
    zone = "Zul'Gurub"
    dispatch(ctx, "PLAYER_REGEN_ENABLED")

    assertTrue(containsValue(ctx.loggingCalls, 1), "expected LoggingCombat(1) after zone becomes available")
    assertTrue(containsPrefix(ctx.combatLogLines, "SESSION_START: Zul'Gurub "), "expected SESSION_START marker for Zul'Gurub")
end

local function testNormalizesWhitespaceAndApostrophes()
    local zone = "\194\160Onyxia\226\128\153s Lair  "
    local ctx = newHarness(function()
        return zone
    end)

    dispatch(ctx, "ZONE_CHANGED_NEW_AREA")

    assertTrue(containsValue(ctx.loggingCalls, 1), "expected LoggingCombat(1) for normalized Onyxia zone")
    assertTrue(containsPrefix(ctx.combatLogLines, "SESSION_START: Onyxia's Lair "), "expected normalized SESSION_START marker")
end

local function testRecognizesAq40AliasZoneName()
    local zone = "Ahn'Qiraj Temple"
    local ctx = newHarness(function()
        return zone
    end)

    dispatch(ctx, "ZONE_CHANGED_NEW_AREA")

    assertTrue(containsValue(ctx.loggingCalls, 1), "expected LoggingCombat(1) for AQ40 alias zone")
    assertTrue(containsPrefix(ctx.combatLogLines, "SESSION_START: Temple of Ahn'Qiraj "), "expected SESSION_START marker for AQ40 alias")
end

local function testRecognizesAhnQirajZoneName()
    local zone = "Ahn'Qiraj"
    local ctx = newHarness(function()
        return zone
    end)

    dispatch(ctx, "ZONE_CHANGED_NEW_AREA")

    assertTrue(containsValue(ctx.loggingCalls, 1), "expected LoggingCombat(1) for Ahn'Qiraj zone name")
    assertTrue(containsPrefix(ctx.combatLogLines, "SESSION_START: Temple of Ahn'Qiraj "), "expected SESSION_START marker for Ahn'Qiraj zone name")
end

local function testManualLockPreventsAutoStopOnUnknownZone()
    local zone = "Localized Raid Name"
    local ctx = newHarness(function()
        return zone
    end)

    _G.SlashCmdList["CAPTAINSLOG"]()
    dispatch(ctx, "ZONE_CHANGED_NEW_AREA")

    assertTrue(containsValue(ctx.loggingCalls, 1), "expected LoggingCombat(1) from manual start")
    assertTrue(not containsValue(ctx.loggingCalls, 0), "did not expect auto stop while manual lock is active")
    assertTrue(not containsPrefix(ctx.combatLogLines, "SESSION_END: "), "did not expect SESSION_END during manual lock")
end

local function testManagedSessionReenablesLoggingIfTurnedOffExternally()
    local zone = "Zul'Gurub"
    local ctx = newHarness(function()
        return zone
    end)

    dispatch(ctx, "ZONE_CHANGED_NEW_AREA")
    _G.LoggingCombat(0)
    dispatch(ctx, "ZONE_CHANGED")

    assertTrue(containsValue(ctx.loggingCalls, 0), "expected external LoggingCombat(0) toggle to be recorded")
    assertTrue(lastValue(ctx.loggingCalls) == 1, "expected addon to re-enable logging for active session")
    assertTrue(ctx.getLoggingEnabled(), "expected combat logging state to end enabled")
end

local function testDoesNotEmitCombatEndWhenRaidMembersStillInCombat()
    local zone = "Zul'Gurub"
    local inCombat = {
        raid2 = true,
    }
    local ctx = newHarness(function()
        return zone
    end, {
        getNumRaidMembers = function()
            return 3
        end,
        unitAffectingCombat = function(unit)
            return inCombat[unit] and 1 or nil
        end,
    })

    dispatch(ctx, "ZONE_CHANGED_NEW_AREA")
    dispatch(ctx, "PLAYER_REGEN_ENABLED")

    assertTrue(not containsPrefix(ctx.combatLogLines, "COMBAT_END: "), "did not expect COMBAT_END while raid members remain in combat")
    assertTrue(not containsPrefix(ctx.combatLogLines, "WIPE: "), "did not expect WIPE while raid members remain in combat")
end

local function testEmitsCombatEndWhenRaidLeavesCombat()
    local zone = "Zul'Gurub"
    local ctx = newHarness(function()
        return zone
    end, {
        getNumRaidMembers = function()
            return 3
        end,
        unitAffectingCombat = function()
            return nil
        end,
    })

    dispatch(ctx, "ZONE_CHANGED_NEW_AREA")
    dispatch(ctx, "PLAYER_REGEN_ENABLED")

    assertTrue(containsPrefix(ctx.combatLogLines, "COMBAT_END: "), "expected COMBAT_END when raid is out of combat")
end

local function testAutoSessionSwitchesWhenRaidZoneChanges()
    local zone = "Zul'Gurub"
    local ctx = newHarness(function()
        return zone
    end)

    dispatch(ctx, "ZONE_CHANGED_NEW_AREA")
    zone = "Onyxia's Lair"
    dispatch(ctx, "ZONE_CHANGED_NEW_AREA")

    local starts = countPrefix(ctx.combatLogLines, "SESSION_START: ")
    local ends = countPrefix(ctx.combatLogLines, "SESSION_END: ")

    assertTrue(starts == 1, "expected single SESSION_START when auto session crosses zones")
    assertTrue(ends == 0, "did not expect auto SESSION_END on raid-zone switch")
    assertTrue(containsPrefix(ctx.combatLogLines, "ZONE_TRANSITION: from=Zul'Gurub to=Onyxia's Lair reason=zone_change "), "expected zone transition marker on raid-zone switch")
end

local function testStatusCommandReportsModeZoneAndLogging()
    local zone = "Zul'Gurub"
    local ctx = newHarness(function()
        return zone
    end)

    _G.SlashCmdList["CAPTAINSLOG"]("status")
    assertTrue(containsPrefix(ctx.chatLines, "|cff00ff00[Captain's Log]|r Status: mode=idle"), "expected idle status output")

    dispatch(ctx, "ZONE_CHANGED_NEW_AREA")
    _G.SlashCmdList["CAPTAINSLOG"]("status")
    assertTrue(containsPrefix(ctx.chatLines, "|cff00ff00[Captain's Log]|r Status: mode=auto zone=Zul'Gurub logging=on"), "expected auto status output")

    _G.SlashCmdList["CAPTAINSLOG"]()
    _G.SlashCmdList["CAPTAINSLOG"]("status")
    assertTrue(containsPrefix(ctx.chatLines, "|cff00ff00[Captain's Log]|r Status: mode=manual zone=Zul'Gurub logging=on"), "expected manual status output")
end

local function testSessionTransitionMarkersIncludeReasons()
    local zone = "Zul'Gurub"
    local ctx = newHarness(function()
        return zone
    end)

    dispatch(ctx, "ZONE_CHANGED_NEW_AREA")
    _G.SlashCmdList["CAPTAINSLOG"]()
    _G.SlashCmdList["CAPTAINSLOG"]()

    assertTrue(containsPrefix(ctx.combatLogLines, "SESSION_TRANSITION: idle->auto reason=zone_enter zone=Zul'Gurub "), "expected auto start transition marker")
    assertTrue(containsPrefix(ctx.combatLogLines, "SESSION_TRANSITION: auto->manual reason=slash_manual_lock zone=Zul'Gurub "), "expected manual lock transition marker")
    assertTrue(containsPrefix(ctx.combatLogLines, "SESSION_TRANSITION: manual->idle reason=slash_stop zone=Zul'Gurub "), "expected manual stop transition marker")
end

local function testZoneEnterTransitionIncludesServerTimeTag()
    local zone = "Zul'Gurub"
    local ctx = newHarness(function()
        return zone
    end, {
        getGameTime = function()
            return 21, 7
        end,
    })

    dispatch(ctx, "ZONE_CHANGED_NEW_AREA")

    assertTrue(
        containsPrefix(ctx.combatLogLines, "SESSION_TRANSITION: idle->auto reason=zone_enter zone=Zul'Gurub server_time=21:07 "),
        "expected zone_enter transition marker to include server_time tag"
    )
end

local function testZoneExitTransitionIncludesServerTimeTag()
    local zone = "Zul'Gurub"
    local ctx = newHarness(function()
        return zone
    end, {
        getGameTime = function()
            return 21, 7
        end,
    })

    dispatch(ctx, "ZONE_CHANGED_NEW_AREA")
    zone = "Stormwind City"
    dispatch(ctx, "ZONE_CHANGED_NEW_AREA")

    assertTrue(containsText(ctx.combatLogLines, "SESSION_TRANSITION: auto->idle reason=zone_exit "), "expected zone_exit transition marker")
    assertTrue(containsText(ctx.combatLogLines, "server_time=21:07"), "expected zone_exit transition marker to include server_time tag")
end

local function testAutoSessionStopsOnAreaTransitionIntoUntrackedInstance()
    local zone = "Zul'Gurub"
    local ctx = newHarness(function()
        return zone
    end, {
        isInInstance = function()
            return 1
        end,
    })

    dispatch(ctx, "ZONE_CHANGED_NEW_AREA")
    zone = "Stratholme"
    dispatch(ctx, "ZONE_CHANGED_NEW_AREA")

    assertTrue(containsValue(ctx.loggingCalls, 0), "expected auto session to stop when entering an untracked instance")
    assertTrue(containsPrefix(ctx.combatLogLines, "SESSION_END: "), "expected SESSION_END after leaving tracked raid content")
end

local function testPlainSubzoneUpdatesDoNotStopAutoSession()
    local zone = "Zul'Gurub"
    local ctx = newHarness(function()
        return zone
    end, {
        isInInstance = function()
            return 1
        end,
    })

    dispatch(ctx, "ZONE_CHANGED_NEW_AREA")
    zone = "Hakkar's Altar"
    dispatch(ctx, "ZONE_CHANGED")

    assertTrue(not containsValue(ctx.loggingCalls, 0), "did not expect auto stop on plain subzone update")
    assertTrue(not containsPrefix(ctx.combatLogLines, "SESSION_END: "), "did not expect SESSION_END on plain subzone update")
end

local function testHooksSwclZoneToggleToPreserveManagedSession()
    local zone = "Zul'Gurub"
    local swclCalled = 0
    local ctx = newHarness(function()
        return zone
    end, {
        rpll = {
            ZONE_CHANGED_NEW_AREA = function()
                swclCalled = swclCalled + 1
                _G.LoggingCombat(0)
            end,
            UPDATE_INSTANCE_INFO = function()
                _G.LoggingCombat(0)
            end,
        },
    })

    dispatch(ctx, "ZONE_CHANGED_NEW_AREA")
    _G.RPLL.ZONE_CHANGED_NEW_AREA()

    assertTrue(swclCalled == 1, "expected original SWCL handler to run once")
    assertTrue(lastValue(ctx.loggingCalls) == 1, "expected compatibility hook to re-enable logging")
    assertTrue(ctx.getLoggingEnabled(), "expected logging to remain enabled after SWCL toggle")
end

local function makeAceLibraryStub(registrations)
    local aceEvent = {}
    aceEvent.embeddedTarget = nil
    aceEvent.embed = function(_, target)
        aceEvent.embeddedTarget = target
        target.RegisterEvent = function(_, eventName)
            registrations[eventName] = true
        end
    end
    local library = setmetatable({
        HasInstance = function(_, name)
            return name == "AceEvent-2.0"
        end,
    }, {
        __call = function(_, name)
            if name == "AceEvent-2.0" then
                return aceEvent
            end
            return nil
        end,
    })
    return library, aceEvent
end

local function testEncounterMarkersIncludeServerTimeTag()
    local zone = "The Rock of Desolation"
    local registrations = {}
    local aceLibrary, aceEvent = makeAceLibraryStub(registrations)
    local ctx = newHarness(function()
        return zone
    end, {
        aceLibrary = aceLibrary,
        getGameTime = function()
            return 21, 7
        end,
    })

    dispatch(ctx, "ADDON_LOADED", "BigWigs")
    assertTrue(aceEvent.embeddedTarget ~= nil, "expected BigWigs handler target to be embedded")

    local handler = aceEvent.embeddedTarget
    handler:BigWigs_RecvSync("BossEngaged", "Echo of Medivh", "Test")
    handler:BigWigs_RecvSync("BossDeath", "Echo of Medivh", "Test")

    assertTrue(
        containsPrefix(ctx.combatLogLines, "ENCOUNTER_START: Echo of Medivh server_time=21:07 "),
        "expected ENCOUNTER_START marker to include server_time tag"
    )
    assertTrue(
        containsPrefix(ctx.combatLogLines, "ENCOUNTER_END: KILL Echo of Medivh server_time=21:07 "),
        "expected ENCOUNTER_END: KILL marker to include server_time tag"
    )
end

local function testEncounterWipeWaitsForResolvedCombatEnd()
    local zone = "Onyxia's Lair"
    local now = 0
    local playerInCombat = false
    local raidInCombat = false
    local registrations = {}
    local aceLibrary, aceEvent = makeAceLibraryStub(registrations)
    local ctx = newHarness(function()
        return zone
    end, {
        aceLibrary = aceLibrary,
        getNumRaidMembers = function()
            return 1
        end,
        getTime = function()
            return now
        end,
        unitAffectingCombat = function(unit)
            if unit == "player" then
                return playerInCombat and 1 or nil
            end
            if unit == "raid1" then
                return raidInCombat and 1 or nil
            end
            return nil
        end,
    })

    dispatch(ctx, "ADDON_LOADED", "BigWigs")
    local handler = aceEvent.embeddedTarget

    handler:BigWigs_RecvSync("BossEngaged", "Onyxia", "Test")
    playerInCombat = true
    raidInCombat = true
    dispatch(ctx, "PLAYER_REGEN_DISABLED")

    now = 60
    handler:BigWigs_RebootModule("Onyxia")
    assertTrue(countPrefix(ctx.combatLogLines, "ENCOUNTER_END: WIPE Onyxia ") == 0, "did not expect wipe marker before combat fully resolves")

    playerInCombat = false
    dispatch(ctx, "PLAYER_REGEN_ENABLED")
    assertTrue(countPrefix(ctx.combatLogLines, "ENCOUNTER_END: WIPE Onyxia ") == 0, "did not expect wipe marker while raid members remain in combat")

    raidInCombat = false
    tick(ctx)

    assertTrue(countPrefix(ctx.combatLogLines, "ENCOUNTER_END: WIPE Onyxia ") == 1, "expected wipe marker after resolved combat end")
end

local function testAliasZoneDoesNotEmitSyntheticZoneTransition()
    local zone = "Ahn'Qiraj Temple"
    local ctx = newHarness(function()
        return zone
    end)

    dispatch(ctx, "ZONE_CHANGED_NEW_AREA")
    dispatch(ctx, "ZONE_CHANGED")

    assertTrue(countPrefix(ctx.combatLogLines, "ZONE_TRANSITION: ") == 0, "did not expect alias-only synthetic zone transition")
end

local function testRefreshesRaidLeaderWhenLeadershipChanges()
    local zone = "Zul'Gurub"
    local leader = "Alpha"
    local ctx = newHarness(function()
        return zone
    end, {
        getNumRaidMembers = function()
            return 2
        end,
        getRaidRosterInfo = function(index)
            if index == 1 then
                return leader, 2
            end
            if index == 2 then
                return "Gamma", 0
            end
            return nil
        end,
    })

    dispatch(ctx, "ZONE_CHANGED_NEW_AREA")

    leader = "Beta"
    assertTrue(ctx.registered["RAID_ROSTER_UPDATE"], "expected RAID_ROSTER_UPDATE to be registered")
    dispatch(ctx, "RAID_ROSTER_UPDATE")

    assertTrue(countPrefix(ctx.combatLogLines, "RAID_LEADER: Alpha ") == 1, "expected initial raid leader marker")
    assertTrue(countPrefix(ctx.combatLogLines, "RAID_LEADER: Beta ") == 1, "expected refreshed raid leader marker after leadership changes")
end

local function testDelaysCombatEndUntilRaidLeavesCombat()
    local zone = "Zul'Gurub"
    local raidTwoInCombat = true
    local ctx = newHarness(function()
        return zone
    end, {
        getNumRaidMembers = function()
            return 3
        end,
        unitAffectingCombat = function(unit)
            if unit == "raid2" and raidTwoInCombat then
                return 1
            end
            return nil
        end,
    })

    dispatch(ctx, "ZONE_CHANGED_NEW_AREA")
    dispatch(ctx, "PLAYER_REGEN_ENABLED")

    assertTrue(not containsPrefix(ctx.combatLogLines, "COMBAT_END: "), "did not expect COMBAT_END before delayed raid resolution")

    raidTwoInCombat = false
    tick(ctx)

    assertTrue(containsPrefix(ctx.combatLogLines, "COMBAT_END: "), "expected delayed COMBAT_END after the rest of the raid leaves combat")
end

local function testEnablesBigWigsTrackingOnAddonLoaded()
    local zone = "Zul'Gurub"
    local registrations = {}
    local ctx = newHarness(function()
        return zone
    end)

    local foundBigWigsMessage = false
    for _, line in ipairs(ctx.chatLines) do
        if string.find(line, "BigWigs detected", 1, true) then
            foundBigWigsMessage = true
            break
        end
    end
    assertTrue(not foundBigWigsMessage, "did not expect BigWigs to be enabled before addon load event")

    local aceLibrary = makeAceLibraryStub(registrations)
    _G.AceLibrary = aceLibrary
    dispatch(ctx, "ADDON_LOADED", "BigWigs")

    assertTrue(registrations["BigWigs_RecvSync"], "expected BigWigs_RecvSync to be registered after addon load")
    assertTrue(registrations["BigWigs_RebootModule"], "expected BigWigs_RebootModule to be registered after addon load")

    local sawBigWigsEnabled = false
    for _, line in ipairs(ctx.chatLines) do
        if string.find(line, "BigWigs detected, encounter tracking enabled", 1, true) then
            sawBigWigsEnabled = true
            break
        end
    end
    assertTrue(sawBigWigsEnabled, "expected BigWigs enable confirmation message")
end

local function testBigWigsEncounterCanStartSessionWhenIdle()
    local zone = "The Rock of Desolation"
    local registrations = {}
    local aceLibrary, aceEvent = makeAceLibraryStub(registrations)
    local ctx = newHarness(function()
        return zone
    end, {
        aceLibrary = aceLibrary,
    })

    dispatch(ctx, "ADDON_LOADED", "BigWigs")
    assertTrue(aceEvent.embeddedTarget ~= nil, "expected BigWigs handler target to be embedded")

    local handler = aceEvent.embeddedTarget
    handler:BigWigs_RecvSync("BossEngaged", "Echo of Medivh", "Test")

    assertTrue(containsPrefix(ctx.combatLogLines, "SESSION_TRANSITION: idle->auto reason=bigwigs_encounter_start zone=The Rock of Desolation "), "expected idle->auto transition from BigWigs encounter")
    assertTrue(containsPrefix(ctx.combatLogLines, "SESSION_START: The Rock of Desolation "), "expected session start from BigWigs encounter")
    assertTrue(containsPrefix(ctx.combatLogLines, "ENCOUNTER_START: Echo of Medivh "), "expected encounter marker from BigWigs")
end

local function testSuppressesBugTrioPrePullWipeNoise()
    local zone = "Temple of Ahn'Qiraj"
    local now = 0
    local playerInCombat = false
    local registrations = {}
    local aceLibrary, aceEvent = makeAceLibraryStub(registrations)
    local ctx = newHarness(function()
        return zone
    end, {
        aceLibrary = aceLibrary,
        getTime = function()
            return now
        end,
        unitAffectingCombat = function(unit)
            if unit == "player" and playerInCombat then
                return 1
            end
            return nil
        end,
    })

    dispatch(ctx, "ADDON_LOADED", "BigWigs")
    local handler = aceEvent.embeddedTarget

    handler:BigWigs_RecvSync("BossEngaged", "The Bug Family", "Test")
    now = 27
    handler:BigWigs_RebootModule("BugTrio")

    now = 77
    handler:BigWigs_RecvSync("BossEngaged", "Princess Yauj", "Test")
    playerInCombat = true
    dispatch(ctx, "PLAYER_REGEN_DISABLED")
    now = 179
    handler:BigWigs_RecvSync("BossDeath", "Vem", "Test")

    assertTrue(countPrefix(ctx.combatLogLines, "ENCOUNTER_START: The Bug Family ") == 1, "expected one Bug Trio start marker")
    assertTrue(countPrefix(ctx.combatLogLines, "ENCOUNTER_END: WIPE The Bug Family ") == 0, "did not expect Bug Trio wipe noise")
    assertTrue(countPrefix(ctx.combatLogLines, "ENCOUNTER_END: KILL The Bug Family ") == 1, "expected one Bug Trio kill marker")
end

local function testSuppressesDuplicateBugTrioKillMarkers()
    local zone = "Temple of Ahn'Qiraj"
    local now = 0
    local playerInCombat = true
    local registrations = {}
    local aceLibrary, aceEvent = makeAceLibraryStub(registrations)
    local ctx = newHarness(function()
        return zone
    end, {
        aceLibrary = aceLibrary,
        getTime = function()
            return now
        end,
        unitAffectingCombat = function(unit)
            if unit == "player" and playerInCombat then
                return 1
            end
            return nil
        end,
    })

    dispatch(ctx, "ADDON_LOADED", "BigWigs")
    local handler = aceEvent.embeddedTarget

    handler:BigWigs_RecvSync("BossEngaged", "The Bug Family", "Test")
    dispatch(ctx, "PLAYER_REGEN_DISABLED")
    now = 90
    handler:BigWigs_RecvSync("BossDeath", "Princess Yauj", "Test")
    now = 95
    handler:BigWigs_RecvSync("BossDeath", "Lord Kri", "Test")

    assertTrue(countPrefix(ctx.combatLogLines, "ENCOUNTER_END: KILL The Bug Family ") == 1, "expected duplicate Bug Trio kills to be ignored")
end

local function testNormalizesBugTrioAliasesToSingleEncounterKey()
    local zone = "Temple of Ahn'Qiraj"
    local now = 0
    local playerInCombat = true
    local registrations = {}
    local aceLibrary, aceEvent = makeAceLibraryStub(registrations)
    local ctx = newHarness(function()
        return zone
    end, {
        aceLibrary = aceLibrary,
        getTime = function()
            return now
        end,
        unitAffectingCombat = function(unit)
            if unit == "player" and playerInCombat then
                return 1
            end
            return nil
        end,
    })

    dispatch(ctx, "ADDON_LOADED", "BigWigs")
    local handler = aceEvent.embeddedTarget

    handler:BigWigs_RecvSync("BossEngaged", "Princess Yauj", "Test")
    now = 5
    handler:BigWigs_RecvSync("BossEngaged", "Lord Kri", "Test")
    dispatch(ctx, "PLAYER_REGEN_DISABLED")
    now = 80
    handler:BigWigs_RecvSync("BossDeath", "Vem", "Test")

    assertTrue(countPrefix(ctx.combatLogLines, "ENCOUNTER_START: The Bug Family ") == 1, "expected Bug Trio aliases to share one start marker")
    assertTrue(countPrefix(ctx.combatLogLines, "ENCOUNTER_END: KILL The Bug Family ") == 1, "expected Bug Trio aliases to share one kill marker")
    assertTrue(countPrefix(ctx.combatLogLines, "ENCOUNTER_START: Princess Yauj ") == 0, "did not expect alias-specific Bug Trio start marker")
    assertTrue(countPrefix(ctx.combatLogLines, "ENCOUNTER_START: Lord Kri ") == 0, "did not expect duplicate alias-specific Bug Trio start marker")
end

local function testNormalizesFourHorsemenAliasesToSingleEncounterKey()
    local zone = "Naxxramas"
    local now = 0
    local playerInCombat = true
    local registrations = {}
    local aceLibrary, aceEvent = makeAceLibraryStub(registrations)
    local ctx = newHarness(function()
        return zone
    end, {
        aceLibrary = aceLibrary,
        getTime = function()
            return now
        end,
        unitAffectingCombat = function(unit)
            if unit == "player" and playerInCombat then
                return 1
            end
            return nil
        end,
    })

    dispatch(ctx, "ADDON_LOADED", "BigWigs")
    local handler = aceEvent.embeddedTarget

    handler:BigWigs_RecvSync("BossEngaged", "Sir Zeliek", "Test")
    now = 5
    handler:BigWigs_RecvSync("BossEngaged", "The Four Horsemen", "Test")
    dispatch(ctx, "PLAYER_REGEN_DISABLED")
    now = 80
    handler:BigWigs_RecvSync("BossDeath", "Baron Rivendare", "Test")

    assertTrue(countPrefix(ctx.combatLogLines, "ENCOUNTER_START: The Four Horsemen ") == 1, "expected Four Horsemen aliases to share one start marker")
    assertTrue(countPrefix(ctx.combatLogLines, "ENCOUNTER_END: KILL The Four Horsemen ") == 1, "expected Four Horsemen aliases to share one kill marker")
    assertTrue(countPrefix(ctx.combatLogLines, "ENCOUNTER_START: Sir Zeliek ") == 0, "did not expect horseman-specific start marker")
end

local function testNormalizesTwinEmperorsAliasesToSingleEncounterKey()
    local zone = "Temple of Ahn'Qiraj"
    local now = 0
    local playerInCombat = true
    local registrations = {}
    local aceLibrary, aceEvent = makeAceLibraryStub(registrations)
    local ctx = newHarness(function()
        return zone
    end, {
        aceLibrary = aceLibrary,
        getTime = function()
            return now
        end,
        unitAffectingCombat = function(unit)
            if unit == "player" and playerInCombat then
                return 1
            end
            return nil
        end,
    })

    dispatch(ctx, "ADDON_LOADED", "BigWigs")
    local handler = aceEvent.embeddedTarget

    handler:BigWigs_RecvSync("BossEngaged", "Emperor Vek'lor", "Test")
    now = 8
    handler:BigWigs_RecvSync("BossEngaged", "Emperor Vek'nilash", "Test")
    dispatch(ctx, "PLAYER_REGEN_DISABLED")
    now = 90
    handler:BigWigs_RecvSync("BossDeath", "Emperor Vek'nilash", "Test")

    assertTrue(countPrefix(ctx.combatLogLines, "ENCOUNTER_START: Twin Emperors ") == 1, "expected Twin Emperors aliases to share one start marker")
    assertTrue(countPrefix(ctx.combatLogLines, "ENCOUNTER_END: KILL Twin Emperors ") == 1, "expected Twin Emperors aliases to share one kill marker")
    assertTrue(countPrefix(ctx.combatLogLines, "ENCOUNTER_START: Emperor Vek'lor ") == 0, "did not expect emperor-specific start marker")
end

local function testStillEmitsWipeForRealNonBugTrioEncounters()
    local zone = "Onyxia's Lair"
    local now = 0
    local playerInCombat = false
    local raidInCombat = false
    local registrations = {}
    local aceLibrary, aceEvent = makeAceLibraryStub(registrations)
    local ctx = newHarness(function()
        return zone
    end, {
        aceLibrary = aceLibrary,
        getTime = function()
            return now
        end,
        getNumRaidMembers = function()
            return 1
        end,
        unitAffectingCombat = function(unit)
            if unit == "player" and playerInCombat then
                return 1
            end
            if unit == "raid1" and raidInCombat then
                return 1
            end
            return nil
        end,
    })

    dispatch(ctx, "ADDON_LOADED", "BigWigs")
    local handler = aceEvent.embeddedTarget

    handler:BigWigs_RecvSync("BossEngaged", "Onyxia", "Test")
    playerInCombat = true
    raidInCombat = true
    dispatch(ctx, "PLAYER_REGEN_DISABLED")
    playerInCombat = false
    now = 60
    handler:BigWigs_RebootModule("Onyxia")
    assertTrue(countPrefix(ctx.combatLogLines, "ENCOUNTER_END: WIPE Onyxia ") == 0, "did not expect wipe marker before combat end resolves")
    dispatch(ctx, "PLAYER_REGEN_ENABLED")
    assertTrue(countPrefix(ctx.combatLogLines, "ENCOUNTER_END: WIPE Onyxia ") == 0, "did not expect wipe marker while raid members remain in combat")
    raidInCombat = false
    tick(ctx)

    assertTrue(countPrefix(ctx.combatLogLines, "ENCOUNTER_END: WIPE Onyxia ") == 1, "expected real non-Bug Trio wipe marker after combat end resolves")
end

local function testModeTransitionMatrix()
    local zone = "Zul'Gurub"
    local ctx = newHarness(function()
        return zone
    end)

    dispatch(ctx, "ZONE_CHANGED_NEW_AREA")
    _G.SlashCmdList["CAPTAINSLOG"]()
    _G.SlashCmdList["CAPTAINSLOG"]()
    dispatch(ctx, "ZONE_CHANGED_NEW_AREA")

    assertTrue(containsPrefix(ctx.combatLogLines, "SESSION_TRANSITION: idle->auto reason=zone_enter zone=Zul'Gurub "), "expected idle->auto transition")
    assertTrue(containsPrefix(ctx.combatLogLines, "SESSION_TRANSITION: auto->manual reason=slash_manual_lock zone=Zul'Gurub "), "expected auto->manual transition")
    assertTrue(containsPrefix(ctx.combatLogLines, "SESSION_TRANSITION: manual->idle reason=slash_stop zone=Zul'Gurub "), "expected manual->idle transition")
    assertTrue(containsPrefix(ctx.combatLogLines, "SESSION_TRANSITION: idle->auto reason=zone_enter zone=Zul'Gurub "), "expected auto restart after returning to zone-driven mode")
end

testRecoversWhenInitialZoneIsEmpty()
testNormalizesWhitespaceAndApostrophes()
testRecognizesAq40AliasZoneName()
testRecognizesAhnQirajZoneName()
testManualLockPreventsAutoStopOnUnknownZone()
testManagedSessionReenablesLoggingIfTurnedOffExternally()
testDoesNotEmitCombatEndWhenRaidMembersStillInCombat()
testEmitsCombatEndWhenRaidLeavesCombat()
testAutoSessionSwitchesWhenRaidZoneChanges()
testStatusCommandReportsModeZoneAndLogging()
testSessionTransitionMarkersIncludeReasons()
testZoneEnterTransitionIncludesServerTimeTag()
testZoneExitTransitionIncludesServerTimeTag()
testAutoSessionStopsOnAreaTransitionIntoUntrackedInstance()
testPlainSubzoneUpdatesDoNotStopAutoSession()
testEncounterMarkersIncludeServerTimeTag()
testEncounterWipeWaitsForResolvedCombatEnd()
testAliasZoneDoesNotEmitSyntheticZoneTransition()
testRefreshesRaidLeaderWhenLeadershipChanges()
testDelaysCombatEndUntilRaidLeavesCombat()
testHooksSwclZoneToggleToPreserveManagedSession()
testEnablesBigWigsTrackingOnAddonLoaded()
testBigWigsEncounterCanStartSessionWhenIdle()
testSuppressesBugTrioPrePullWipeNoise()
testSuppressesDuplicateBugTrioKillMarkers()
testNormalizesBugTrioAliasesToSingleEncounterKey()
testNormalizesFourHorsemenAliasesToSingleEncounterKey()
testNormalizesTwinEmperorsAliasesToSingleEncounterKey()
testStillEmitsWipeForRealNonBugTrioEncounters()
testModeTransitionMatrix()
print("ok - CaptainsLog regression tests passed")
