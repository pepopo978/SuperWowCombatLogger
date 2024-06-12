local RPLL = RPLL
RPLL.VERSION = 14
RPLL.MAX_MESSAGE_LENGTH = 500
RPLL.CONSOLIDATE_CHARACTER = "{"
RPLL.MESSAGE_PREFIX = "RPLL_HELPER_"

RPLL.PlayerInformation = {}
RPLL.LoggedCombatantInfo = {}

RPLL:RegisterEvent("RAID_ROSTER_UPDATE")
RPLL:RegisterEvent("PARTY_MEMBERS_CHANGED")

RPLL:RegisterEvent("ZONE_CHANGED_NEW_AREA")
RPLL:RegisterEvent("UPDATE_INSTANCE_INFO")

RPLL:RegisterEvent("PLAYER_ENTERING_WORLD")

RPLL:RegisterEvent("UNIT_PET")
RPLL:RegisterEvent("PLAYER_PET_CHANGED")
RPLL:RegisterEvent("PET_STABLE_CLOSED")

RPLL:RegisterEvent("CHAT_MSG_LOOT")

RPLL:RegisterEvent("UNIT_INVENTORY_CHANGED")

RPLL:RegisterEvent("UNIT_CASTEVENT")

local tinsert = table.insert
local UnitName = UnitName
local strsub = string.sub
local GetNumSavedInstances = GetNumSavedInstances
local GetSavedInstanceInfo = GetSavedInstanceInfo
local IsInInstance = IsInInstance
local pairs = pairs
local GetNumPartyMembers = GetNumPartyMembers
local GetNumRaidMembers = GetNumRaidMembers
local UnitIsPlayer = UnitIsPlayer
local UnitSex = UnitSex
local strlower = strlower
local GetGuildInfo = GetGuildInfo
local GetInventoryItemLink = GetInventoryItemLink
local strfind = string.find
local Unknown = UNKNOWN
local LoggingCombat = LoggingCombat
local time = time
local GetRealZoneText = GetRealZoneText
local date = date
local strjoin = string.join or function(delim, ...)
	if type(arg) == 'table' then
		return table.concat(arg, delim)
	else
		return delim
	end
end

local function strsplit(pString, pPattern)
	local Table = {}
	local fpat = "(.-)" .. pPattern
	local last_end = 1
	local s, e, cap = strfind(pString, fpat, 1)
	while s do
		if s ~= 1 or cap ~= "" then
			table.insert(Table, cap)
		end
		last_end = e + 1
		s, e, cap = strfind(pString, fpat, last_end)
	end
	if last_end <= strlen(pString) then
		cap = strfind(pString, last_end)
		table.insert(Table, cap)
	end
	return Table
end

RPLL.UNIT_INVENTORY_CHANGED = function(unit)
	this:grab_unit_information(unit)
end

local trackedSpells = {
	[9907] = "Faerie Fire",
	[17392] = "Faerie Fire (Feral)",
	[11597] = "Sunder Armor",
	[11722] = "Curse of the Elements",
	[11717] = "Curse of Recklessness",
	[17937] = "Curse of Shadow",
	[11708] = "Curse of Weakness",
	[11719] = "Curse of Tongues",
	[11198] = "Expose Armor", --only tracking max rank for above spells
	[774] = "Improved Rejuvenation", --r1
	[8070] = "Improved Rejuvenation", --r1 again?
	[1058] = "Improved Rejuvenation", --r2
	[1430] = "Improved Rejuvenation", --r3
	[2090] = "Improved Rejuvenation", --r4
	[2091] = "Improved Rejuvenation", --r5
	[3627] = "Improved Rejuvenation", --r6
	[8910] = "Improved Rejuvenation", --r7
	[9839] = "Improved Rejuvenation", --r8
	[9840] = "Improved Rejuvenation", --r9
	[9841] = "Improved Rejuvenation", --r10
	[25299] = "Improved Rejuvenation", --r11
	[8936] = "Improved Regrowth", --r1
	[8938] = "Improved Regrowth", --r2
	[8939] = "Improved Regrowth", --r3
	[8940] = "Improved Regrowth", --r4
	[8941] = "Improved Regrowth", --r5
	[9750] = "Improved Regrowth", --r6
	[9856] = "Improved Regrowth", --r7
	[9857] = "Improved Regrowth", --r8
	[9858] = "Improved Regrowth", --r9
	[139] = "Improved Renew", --r1
	[6074] = "Improved Renew", --r2
	[6075] = "Improved Renew", --r3
	[6076] = "Improved Renew", --r4
	[6077] = "Improved Renew", --r5
	[6078] = "Improved Renew", --r6
	[10927] = "Improved Renew", --r7
	[10928] = "Improved Renew", --r8
	[27606] = "Improved Renew", --r9
	[10929] = "Improved Renew", --r9 again?
	[25315] = "Improved Renew", --r10
} 

RPLL.UNIT_CASTEVENT = function(caster, target, event, spellID, castDuration)
	if not trackedSpells[spellID] then
		return
	end

	local spellName = trackedSpells[spellID]
	local targetName = UnitName(target) --get name from GUID
	local casterName = UnitName(caster)

	-- seems like on razorgore either caster or target can be null here
	-- probably related to MC
	CombatLogAdd(tostring(casterName) .. " casts " .. spellName .. " on " .. tostring(targetName) .. ".")
end

RPLL.ZONE_CHANGED_NEW_AREA = function()
	LoggingCombat(IsInInstance("player"))
	this:grab_unit_information("player")
	this:RAID_ROSTER_UPDATE()
	this:PARTY_MEMBERS_CHANGED()
	this:QueueRaidIds()
	RPLL.LoggedCombatantInfo = {}
end

RPLL.UPDATE_INSTANCE_INFO = function()
	LoggingCombat(IsInInstance("player"))
	this:grab_unit_information("player")
	this:RAID_ROSTER_UPDATE()
	this:PARTY_MEMBERS_CHANGED()
	this:QueueRaidIds()
end

local initialized = false
RPLL.PLAYER_ENTERING_WORLD = function()
	if initialized then
		return
	end
	initialized = true

	-- add (1) for first stack of buffs/debuffs
	AURAADDEDOTHERHELPFUL = "%s gains %s (1)."
	AURAADDEDOTHERHARMFUL = "%s is afflicted by %s (1)."
	AURAADDEDSELFHARMFUL = "You are afflicted by %s (1)."
	AURAADDEDSELFHELPFUL = "You gain %s (1)."

	if RPLL_PlayerInformation == nil then
		RPLL_PlayerInformation = {}
	end
	this.PlayerInformation = RPLL_PlayerInformation
	this:grab_unit_information("player")
	this:RAID_ROSTER_UPDATE()
	this:PARTY_MEMBERS_CHANGED()
end

RPLL.RAID_ROSTER_UPDATE = function()
	for i = 1, GetNumRaidMembers() do
		if UnitName("raid" .. i) then
			this:grab_unit_information("raid" .. i)
		end
	end
end

RPLL.PARTY_MEMBERS_CHANGED = function()
	for i = 1, GetNumPartyMembers() do
		if UnitName("party" .. i) then
			this:grab_unit_information("party" .. i)
		end
	end
end

RPLL.UNIT_PET = function(unit)
	if unit then
		this:grab_unit_information(unit)
	end
end

RPLL.PLAYER_PET_CHANGED = function()
	this:grab_unit_information("player")
end

RPLL.PET_STABLE_CLOSED = function()
	this:grab_unit_information("player")
end

RPLL.CHAT_MSG_LOOT = function(msg)
	CombatLogAdd("LOOT: " .. date("%d.%m.%y %H:%M:%S") .. "&" .. msg)
end

function RPLL:DeepSubString(str1, str2)
	if str1 == nil or str2 == nil then
		return false
	end

	str1 = strlower(str1)
	str2 = strlower(str2)
	if (strfind(str1, str2) or strfind(str2, str1)) then
		return true;
	end
	for cat, val in pairs(strsplit(str1, " ")) do
		if val ~= "the" then
			if (strfind(val, str2) or strfind(str2, val)) then
				return true;
			end
		end
	end
	return false;
end

function RPLL:QueueRaidIds()
	local zone = strlower(GetRealZoneText())
	local found = false
	for i = 1, GetNumSavedInstances() do
		local instance_name, instance_id = GetSavedInstanceInfo(i)
		if zone == strlower(instance_name) then
			CombatLogAdd("ZONE_INFO: " .. date("%d.%m.%y %H:%M:%S") .. "&" .. instance_name .. "&" .. instance_id)
			found = true
			break
		end
	end

	if found == false then
		CombatLogAdd("ZONE_INFO: " .. date("%d.%m.%y %H:%M:%S") .. "&" .. zone .. "&0")
	end
end

function RPLL:grab_unit_information(unit)
	local unit_name = UnitName(unit)
	if UnitIsPlayer(unit) and unit_name ~= nil and unit_name ~= Unknown then
		if this.PlayerInformation[unit_name] == nil then
			this.PlayerInformation[unit_name] = {}
		end
		local info = this.PlayerInformation[unit_name]
		if info["last_update"] ~= nil and time() - info["last_update"] <= 30 then
			return
		end
		info["last_update_date"] = date("%d.%m.%y %H:%M:%S")
		info["last_update"] = time()
		info["name"] = unit_name

		-- Guild info
		local guildName, guildRankName, guildRankIndex = GetGuildInfo(unit)
		if guildName ~= nil then
			info["guild_name"] = guildName
			info["guild_rank_name"] = guildRankName
			info["guild_rank_index"] = guildRankIndex
		end

		-- Pet name
		if strfind(unit, "pet") == nil then
			local pet_name = nil
			if unit == "player" then
				pet_name = UnitName("pet")
			elseif strfind(unit, "raid") then
				pet_name = UnitName("raidpet" .. strsub(unit, 5))
			elseif strfind(unit, "party") then
				pet_name = UnitName("partypet" .. strsub(unit, 6))
			end

			if pet_name ~= nil and pet_name ~= Unknown and pet ~= "" then
				info["pet"] = pet_name
			end
		end

		-- Hero Class, race, sex
		if UnitClass(unit) ~= nil then
			local _, english_class = UnitClass(unit)
			info["hero_class"] = english_class
		end
		if UnitRace(unit) ~= nil then
			local _, en_race = UnitRace(unit)
			info["race"] = en_race
		end
		if UnitSex(unit) ~= nil then
			info["sex"] = UnitSex(unit)
		end

		-- Gear
		local any_item = false
		for i = 1, 19 do
			if GetInventoryItemLink(unit, i) ~= nil then
				any_item = true
				break
			end
		end

		if info["gear"] == nil then
			info["gear"] = {}
		end

		if any_item then
			info["gear"] = {}
			for i = 1, 19 do
				local inv_link = GetInventoryItemLink(unit, i)
				if inv_link == nil then
					info["gear"][i] = nil
				else
					local found, _, itemString = strfind(inv_link, "Hitem:(.+)\124h%[")
					if found == nil then
						info["gear"][i] = nil
					else
						info["gear"][i] = itemString
					end
				end
			end
		end

		-- Talents
		if unit == "player" then
			local talents = { "", "", "" };
			for t = 1, 3 do
				local numTalents = GetNumTalents(t);
				-- Last one is missing?
				for i = 1, numTalents do
					local _, _, _, _, currRank = GetTalentInfo(t, i);
					talents[t] = talents[t] .. currRank
				end
			end
			talents = strjoin("}", talents[1], talents[2], talents[3])
			if strlen(talents) <= 10 then
				talents = nil
			end

			if talents ~= nil then
				info["talents"] = talents
			end
		end

		log_combatant_info(info)
	end
end

function log_combatant_info(character)
	if character ~= nil then
		local num_nil_gear = 0
		if character["gear"][1] == nil then
			num_nil_gear = num_nil_gear + 1
		end

		local gear_str = prep_value(character["gear"][1])
		for i = 2, 19 do
			if character["gear"][i] == nil then
				num_nil_gear = num_nil_gear + 1
			end

			gear_str = gear_str .. "&" .. prep_value(character["gear"][i])
		end

		-- If all gear is nil, don't log
		if num_nil_gear == 19 then
			return
		end

		local result = prep_value(character["name"]) .. "&" .. prep_value(character["hero_class"]) .. "&" .. prep_value(character["race"]) .. "&" .. prep_value(character["sex"]) .. "&" .. prep_value(character["pet"]) .. "&" .. prep_value(character["guild_name"]) .. "&" .. prep_value(character["guild_rank_name"]) .. "&" .. prep_value(character["guild_rank_index"]) .. "&" .. gear_str .. "&" .. prep_value(character["talents"])

		if not RPLL.LoggedCombatantInfo[result] then
			local result_prefix = "COMBATANT_INFO: " .. prep_value(character["last_update_date"]) .. "&"
			CombatLogAdd(result_prefix .. result)
			RPLL.LoggedCombatantInfo[result] = true
		end

	end
end

function prep_value(val)
	if val == nil then
		return "nil"
	end
	return val
end

function RPLL:SendMessage(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cFFFF8080LegacyPlayers|r: " .. msg)
end
