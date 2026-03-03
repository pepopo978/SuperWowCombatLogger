-- Captain's Log
-- Auto-manages combat logging for USS Enterprise Guild raid sessions
-- Part of 1701-CaptainsLog unified addon
-- Requires: SuperWoW (for CombatLogAdd)

-- Guard: SuperWoW must be present for session markers
if not CombatLogAdd then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[Captain's Log]|r SuperWoW required for session management.")
    return
end

local frame = CreateFrame("Frame")
local sessionMode = "idle" -- "idle" | "auto" | "manual"
local sessionZone = nil

local LoggingCombat = LoggingCombat
local GetRealZoneText = GetRealZoneText
local IsInInstance = IsInInstance
local UnitAffectingCombat = UnitAffectingCombat
local GetGameTime = GetGameTime
local unpack = unpack or table.unpack
local date = date
local CHAT_PREFIX = "|cff00ff00[Captain's Log]|r "
local StartLogging

local supportsTimezoneOffset = nil

local function FormatTimestamp()
    if supportsTimezoneOffset == nil then
        local probe = date("%z")
        supportsTimezoneOffset = probe and probe ~= "" and probe ~= "%z"
    end
    if supportsTimezoneOffset then
        return date("%Y-%m-%d %H:%M:%S %z")
    end
    return date("%Y-%m-%d %H:%M:%S")
end

local function FormatServerTimeTag()
    if not GetGameTime then
        return nil
    end
    local hour, minute = GetGameTime()
    if not hour or not minute then
        return nil
    end
    return "server_time=" .. string.format("%02d:%02d", hour, minute)
end

local function Trim(s)
    if not s then
        return ""
    end
    s = string.gsub(s, "^%s+", "")
    s = string.gsub(s, "%s+$", "")
    return s
end

local function SessionActive()
    return sessionMode ~= "idle"
end

local function NormalizeZoneName(name)
    if not name or name == "" then
        return nil, nil
    end

    -- Handle smart quotes and non-breaking spaces from client-provided zone strings.
    name = string.gsub(name, "\226\128\152", "'")
    name = string.gsub(name, "\226\128\153", "'")
    name = string.gsub(name, "\194\160", " ")
    name = string.gsub(name, "^%s+", "")
    name = string.gsub(name, "%s+$", "")
    if name == "" then
        return nil, nil
    end

    return string.lower(name), name
end

local function EmitTransition(fromMode, toMode, reason, zone)
    local ts = FormatTimestamp()
    local message = "SESSION_TRANSITION: " .. fromMode .. "->" .. toMode .. " reason=" .. reason
    if zone and zone ~= "" then
        message = message .. " zone=" .. zone
    end
    if reason == "zone_enter" or reason == "zone_exit" then
        local serverTimeTag = FormatServerTimeTag()
        if serverTimeTag then
            message = message .. " " .. serverTimeTag
        end
    end
    CombatLogAdd(message .. " " .. ts)
end

local function EmitZoneTransition(fromZone, toZone, reason)
    local ts = FormatTimestamp()
    CombatLogAdd("ZONE_TRANSITION: from=" .. fromZone .. " to=" .. toZone .. " reason=" .. reason .. " " .. ts)
end

-- BigWigs encounter tracking (optional - only if BigWigs is loaded)
local engagedBoss = nil
local bwHandler = nil
local bigWigsTrackingEnabled = false

local function EnsureBigWigsTracking()
    if bigWigsTrackingEnabled then
        return true
    end
    if not AceLibrary or not AceLibrary:HasInstance("AceEvent-2.0") then
        return false
    end

    local AceEvent = AceLibrary("AceEvent-2.0")
    if not bwHandler then
        bwHandler = {}
        AceEvent:embed(bwHandler)

        function bwHandler:BigWigs_RecvSync(sync, rest, nick)
            if sync == "BossEngaged" and rest and not SessionActive() then
                local _, zoneText = NormalizeZoneName(GetRealZoneText())
                local zone = zoneText or "Unknown Zone"
                StartLogging(zone, "auto", "bigwigs_encounter_start")
            end
            if not SessionActive() then return end
            if sync == "BossEngaged" and rest then
                local ts = FormatTimestamp()
                local serverTimeTag = FormatServerTimeTag()
                engagedBoss = rest
                local message = "ENCOUNTER_START: " .. rest
                if serverTimeTag then
                    message = message .. " " .. serverTimeTag
                end
                CombatLogAdd(message .. " " .. ts)
            elseif sync == "BossDeath" and rest then
                local ts = FormatTimestamp()
                local serverTimeTag = FormatServerTimeTag()
                engagedBoss = nil
                local message = "ENCOUNTER_END: KILL " .. rest
                if serverTimeTag then
                    message = message .. " " .. serverTimeTag
                end
                CombatLogAdd(message .. " " .. ts)
            end
        end

        function bwHandler:BigWigs_RebootModule(moduleName)
            if not SessionActive() or not engagedBoss then return end
            local ts = FormatTimestamp()
            local serverTimeTag = FormatServerTimeTag()
            local message = "ENCOUNTER_END: WIPE " .. engagedBoss
            if serverTimeTag then
                message = message .. " " .. serverTimeTag
            end
            CombatLogAdd(message .. " " .. ts)
            engagedBoss = nil
        end
    end

    if not bwHandler.__captainslog_registered then
        bwHandler:RegisterEvent("BigWigs_RecvSync")
        bwHandler:RegisterEvent("BigWigs_RebootModule")
        bwHandler.__captainslog_registered = true
    end

    bigWigsTrackingEnabled = true
    DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. "BigWigs detected, encounter tracking enabled")
    return true
end

EnsureBigWigsTracking()

-- Raid zones: vanilla + Turtle WoW custom content
local RAID_ZONE_NAMES = {
    -- Vanilla raids
    "Molten Core",
    "Blackwing Lair",
    "Onyxia's Lair",
    "Temple of Ahn'Qiraj",
    "Ruins of Ahn'Qiraj",
    "Zul'Gurub",
    "Naxxramas",
    -- Turtle WoW custom raids
    "Emerald Sanctum",
    "Lower Karazhan Halls",
    "Tower of Karazhan",
}

local RAID_ZONE_ALIASES = {
    -- AQ names vary by client/build; map known variants to canonical labels.
    ["Ahn'Qiraj Temple"] = "Temple of Ahn'Qiraj",
    ["Ahn Qiraj Temple"] = "Temple of Ahn'Qiraj",
    ["Temple of Ahn Qiraj"] = "Temple of Ahn'Qiraj",
    ["Ahn'Qiraj"] = "Temple of Ahn'Qiraj",
    ["Ahn Qiraj"] = "Temple of Ahn'Qiraj",
    ["Ahn'Qiraj Ruins"] = "Ruins of Ahn'Qiraj",
    ["Ahn Qiraj Ruins"] = "Ruins of Ahn'Qiraj",
    ["Ruins of Ahn Qiraj"] = "Ruins of Ahn'Qiraj",
}

local RAID_ZONES = {}
for _, zoneName in ipairs(RAID_ZONE_NAMES) do
    local zoneKey = NormalizeZoneName(zoneName)
    RAID_ZONES[zoneKey] = zoneName
end
for aliasName, canonicalName in pairs(RAID_ZONE_ALIASES) do
    local aliasKey = NormalizeZoneName(aliasName)
    if aliasKey then
        RAID_ZONES[aliasKey] = canonicalName
    end
end

StartLogging = function(zone, mode, reason)
    if mode ~= "manual" then
        mode = "auto"
    end
    if not reason or reason == "" then
        reason = "start"
    end

    EmitTransition(sessionMode, mode, reason, zone)
    LoggingCombat(1)
    sessionMode = mode
    sessionZone = zone
    local ts = FormatTimestamp()
    CombatLogAdd("SESSION_START: " .. zone .. " " .. ts)
    if GetRaidRosterInfo then
        for i = 1, GetNumRaidMembers() do
            local name, rank = GetRaidRosterInfo(i)
            if rank == 2 and name then
                CombatLogAdd("RAID_LEADER: " .. name .. " " .. ts)
                break
            end
        end
    end
    DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. "Combat logging started for " .. zone)
end

local function StopLogging(reason)
    if not SessionActive() then
        return
    end
    if not reason or reason == "" then
        reason = "stop"
    end

    EmitTransition(sessionMode, "idle", reason, sessionZone)
    CombatLogAdd("SESSION_END: " .. FormatTimestamp())
    LoggingCombat(0)
    sessionMode = "idle"
    sessionZone = nil
    engagedBoss = nil
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[Captain's Log]|r Combat logging stopped")
end

local function EnsureLoggingEnabled()
    if SessionActive() and not LoggingCombat() then
        LoggingCombat(1)
    end
end

local function SyncZoneLogging()
    local zoneKey, zoneText = NormalizeZoneName(GetRealZoneText())
    local observedZone = zoneText or "Unknown Zone"
    local inInstance = IsInInstance and IsInInstance("player")

    if SessionActive() and sessionZone ~= observedZone then
        EmitZoneTransition(sessionZone, observedZone, "zone_change")
        sessionZone = observedZone
    end

    if sessionMode == "manual" then
        EnsureLoggingEnabled()
        return
    end

    if sessionMode == "idle" then
        local raidZone = zoneKey and RAID_ZONES[zoneKey] or nil
        if raidZone then
            StartLogging(raidZone, "auto", "zone_enter")
        end
        return
    end

    if sessionMode == "auto" then
        local raidZone = zoneKey and RAID_ZONES[zoneKey] or nil
        if not raidZone and not inInstance then
            StopLogging("zone_exit")
            return
        end
    end

    EnsureLoggingEnabled()
end

local swclCompatibilityHooked = false
local swclCompatibilityWarned = false

local function EnsureSwclCompatibilityHook()
    if swclCompatibilityHooked or not RPLL then
        return
    end

    local wrapped = false

    local function WrapHandler(name)
        local key = "__captainslog_wrapped_" .. name
        if RPLL[key] then
            wrapped = true
            return
        end

        local original = RPLL[name]
        if type(original) ~= "function" then
            return
        end

        RPLL[name] = function(...)
            if type(arg) == "table" then
                original(unpack(arg))
            else
                original()
            end
            SyncZoneLogging()
        end
        RPLL[key] = true
        wrapped = true
    end

    WrapHandler("ZONE_CHANGED_NEW_AREA")
    WrapHandler("UPDATE_INSTANCE_INFO")

    if wrapped then
        swclCompatibilityHooked = true
        if IsAddOnLoaded and IsAddOnLoaded("SuperWowCombatLogger") and not swclCompatibilityWarned then
            DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[Captain's Log]|r Standalone SuperWowCombatLogger detected; compatibility hook enabled")
            swclCompatibilityWarned = true
        end
    end
end

local function OnCombatEnd()
    if not SessionActive() then
        return
    end

    local total = GetNumRaidMembers()
    if total == 0 then
        return
    end

    if UnitAffectingCombat then
        for i = 1, total do
            if UnitAffectingCombat("raid" .. i) then
                return
            end
        end
    end

    local alive = 0
    local counted = {}
    for i = 1, total do
        local unit = "raid" .. i
        if not UnitIsDeadOrGhost(unit) then
            alive = alive + 1
        end
        counted[UnitName(unit)] = true
    end

    -- Include the player if not already counted via raid iteration
    if not counted[UnitName("player")] then
        total = total + 1
        if not UnitIsDeadOrGhost("player") then
            alive = alive + 1
        end
    end

    local ts = FormatTimestamp()
    CombatLogAdd("COMBAT_END: " .. alive .. "/" .. total .. " " .. ts)

    if alive <= 3 or alive / total < 0.10 then
        CombatLogAdd("WIPE: " .. ts)
    end
end

frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("ZONE_CHANGED")
frame:RegisterEvent("ZONE_CHANGED_INDOORS")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("ADDON_LOADED")

EnsureSwclCompatibilityHook()

frame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" then
        if arg1 == "BigWigs" then
            EnsureBigWigsTracking()
        elseif arg1 == "SuperWowCombatLogger" then
            EnsureSwclCompatibilityHook()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        EnsureSwclCompatibilityHook()
    end

    SyncZoneLogging()

    if event == "PLAYER_REGEN_ENABLED" then
        OnCombatEnd()
    end
end)

-- Slash command: /captainslog — manually toggle combat logging
SLASH_CAPTAINSLOG1 = "/captainslog"
SlashCmdList["CAPTAINSLOG"] = function(msg)
    local command = string.lower(Trim(msg))

    if command == "status" then
        local zone = sessionZone
        if not zone then
            local _, zoneText = NormalizeZoneName(GetRealZoneText())
            zone = zoneText or "Unknown Zone"
        end
        local loggingState = LoggingCombat() and "on" or "off"
        DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. "Status: mode=" .. sessionMode .. " zone=" .. zone .. " logging=" .. loggingState)
        return
    end

    if sessionMode == "manual" then
        StopLogging("slash_stop")
        return
    end

    if sessionMode == "auto" then
        EmitTransition("auto", "manual", "slash_manual_lock", sessionZone)
        sessionMode = "manual"
        EnsureLoggingEnabled()
        DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. "Manual logging lock enabled")
        return
    end

    if sessionMode == "idle" then
        local zoneKey, zoneText = NormalizeZoneName(GetRealZoneText())
        local zone = zoneText
        if zoneKey and RAID_ZONES[zoneKey] then
            zone = RAID_ZONES[zoneKey]
        end
        if not zone then
            zone = "Unknown Zone"
        end
        StartLogging(zone, "manual", "slash_start")
    else
        -- Safety fallback for unexpected mode values.
        if SessionActive() then
            StopLogging("slash_stop")
        end
    end
end
