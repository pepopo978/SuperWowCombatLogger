if not SetAutoloot then

	StaticPopupDialogs["NO_SUPERWOW_RPLL"] = {
		text = "|cffffff00SuperWowCombatLogger|r requires SuperWoW to operate.",
		button1 = TEXT(OKAY),
		timeout = 0,
		whileDead = 1,
		hideOnEscape = 1,
		showAlert = 1,
	}

	StaticPopup_Show("NO_SUPERWOW_RPLL")
	return
end

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
RPLL:RegisterEvent("CHAT_MSG_SYSTEM")

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

-- won't this fire too much?
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
	[20572] = "Blood Fury",
	[45511] = "Bloodlust",
	[29602] = "Jom Gabbar",
	[28200] = "Ascendance",
	[24658] = "Unstable Power",
	[11129] = "Combustion",
	[20549] = "War Stomp",
	[1044] = "Blessing of Freedom",
	[1022] = "Blessing of Protection", -- rank 1
	[5599] = "Blessing of Protection", -- rank 2
	[10278] = "Blessing of Protection", -- rank 3
	[6940] = "Blessing of Sacrifice", -- rank 1
	[20729] = "Blessing of Sacrifice", -- rank 2
	[9907] = "Faerie Fire",
	[17392] = "Faerie Fire (Feral)",
	[11597] = "Sunder Armor",
	[1161] = "Challenging Shout",
	[5209] = "Challenging Roar",

	[11722] = "Curse of the Elements", -- lock
	[11717] = "Curse of Recklessness",
	[17937] = "Curse of Shadow",
	[11708] = "Curse of Weakness",
	[11719] = "Curse of Tongues",
	[25311] = "Corruption",
	[11713] = "Curse of Agony",

	[1038] = "Blessing of Salvation", -- pally
	[10278] = "Blessing of Protection",
	[20217] = "Blessing of Kings",
	[19979] = "Blessing of Light",
	[20914] = "Blessing of Sanctuary",
	[20729] = "Blessing of Sacrifice",
	[25291] = "Blessing of Might",
	[25290] = "Blessing of Wisdom",
	[25895] = "Greater Blessing of Salvation",
	[25898] = "Greater Blessing of Kings",
	[25890] = "Greater Blessing of Light",
	[25916] = "Greater Blessing of Might",
	[25918] = "Greater Blessing of Wisdom",
	[25899] = "Greater Blessing of Sanctuary",
	[45801] = "Greater Blessing of Sacrifice",

	[10060] = "Power Infusion", -- priest
	[10938] = "Power Word: Fortitude",
	[23948] = "Power Word: Fortitude",
	[10901] = "Power Word: Shield",
	[27607] = "Power Word: Shield",
	[23948] = "Power Word: Fortitude",
	[21564] = "Prayer of Fortitude",
	[45551] = "Prayer of Spirit",

	[10157] = "Arcane Intellect", -- mage
	[23028] = "Arcane Brilliance",

	[45511] = "Bloodlust", --shaman

	[16878] = "Mark of the Wild", --druid
	[24752] = "Mark of the Wild",
	[21850] = "Gift of the Wild",
	[57108] = "Emerald Blessing",
	[24977] = "Insect Swarm",

	[11198] = "Expose Armor",
	--only tracking max rank for above spells

	[774] = "Improved Rejuvenation", --r1
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
} --only tracking max rank
local trackedConsumes = {
	-- elixirs:
	[11390] = "Arcane Elixir",
	[17539] = "Greater Arcane Elixir",
	[7844] = "Elixir of Firepower",
	[26276] = "Elixir of Greater Firepower",
	[11474] = "Elixir of Shadow Power",
	[45988] = "Elixir of Greater Nature Power",
	[21920] = "Elixir of Frost Power",
	[45427] = "Dreamshard Elixir",
	[45489] = "Dreamtonic",
	[24363] = "Mageblood Potion",

	[11328] = "Elixir of Agility",
	[11334] = "Elixir of Greater Agility",
	[17538] = "Elixir of the Mongoose",
	[11405] = "Elixir of Giants",
	[17535] = "Elixir of the Sages", -- laugh
	[17537] = "Elixir of Brute Force", -- laugh
	[11349] = "Elixir of Greater Defense", -- laugh
	[11348] = "Elixir of Superior Defense",
	[24361] = "Major Troll's Blood Potion", -- laugh

	[3593] = "Elixir of Fortitude",
	[17038] = "Winterfall Firewater",
	[11371] = "Gift of Arthas",

	-- food:
	[18194] = "Nightfin Soup",
	-- [24800] = "Smoked Desert Dumplings", -- same  as power mush
	[18124] = "Blessed Sunfruit",
	[18140] = "Blessed Sunfruit Juice",
	[18230] = "Grilled Squid",

	[57043] = "Danonzo's Tel'Abim Delight",
	[57045] = "Danonzo's Tel'Abim Medley",
	[57055] = "Danonzo's Tel'Abim Surprise",

	[24800] = "Power Mushroom",
	[25660] = "Hardened Mushroom",
	-- [25660] = "Dirge's Kickin' Chimaerok Chops", -- same as hardened mush
	[45624] = "Le Fishe Au Chocolat",
	[46084] = "Gurubashi Gumbo",
	-- drinks
	[22789] = "Gordok Green Grog",
	[20875] = "Rumsey Rum",
	[25804] = "Rumsey Rum Black Label",
	[57106] = "Medivh's Merlot",
	[57107] = "Medivh's Merlot Blue Label",
	[22790] = "Kreeg's Stout Beatdown",

	-- flasks
	[17626] = "Flask of the Titans",
	[17627] = "Flask of Distilled Wisdom",
	[17628] = "Flask of Supreme Power",
	[17629] = "Flask of Chromatic Resistance",
	-- zanzas
	[24382] = "Spirit of Zanza",
	[24383] = "Swiftness of Zanza",
	[24417] = "Sheen of Zanza",
	-- blasted
	[10692] = "Cerebral Cortex Compound",
	[10667] = "R.O.I.D.S.",
	[10668] = "Lung Juice Cocktail",
	[10669] = "Ground Scorpok Assay",
	[10693] = "Gizzard Gum",
	-- potions
	[3169] = "Limited Invulnerability Potion",
	[3680] = "Lesser Invisibility Potion",
	[11392] = "Invisibility Potion",
	[45425] = "Potion of Quickness",
	[16589] = "Noggenfogger Elixir",
	[6615] = "Free Action Potion",
	[24364] = "Living Action Potion",
	[4941] = "Lesser Stoneshield Potion",
	[17540] = "Greater Stoneshield Potion",
	[8212] = "Elixir of Giant Growth",
	[6613] = "Great Rage Potion",
	[17528] = "Mighty Rage Potion",
	[2379] = "Swiftness Potion",
	-- restoratives
	[9512] = "Thistle Tea",
	[17534] = "Major Healing Potion",
	[17531] = "Major Mana Potion",
	[22729] = "Major Rejuvenation Potion",
	[19199] = "Tea With Sugar",
	[16666] = "Demonic Rune",
	[27869] = "Dark Rune",
	[10850] = "Powerful Smelling Salts",
	-- bandages
	[18610] = "Heavy Runecloth Bandage",
	[18608] = "Runecloth Bandage",
	-- scrolls
	[12178] = "Scroll of Stamina IV",
	[12179] = "Scroll of Strength IV",
	[12174] = "Scroll of Agility IV",
	[12176] = "Scroll of Intellect IV",
	[12177] = "Scroll of Spirit IV",
	[12175] = "Scroll of Protection IV",
	-- protections
	[7233] = "Fire Protection Potion",
	[17543] = "Greater Fire Protection Potion",
	[7239] = "Frost Protection Potion",
	[17544] = "Greater Frost Protection Potion",
	[7254] = "Nature Protection Potion",
	[17546] = "Greater Nature Protection Potion",
	[7242] = "Shadow Protection Potion",
	[17548] = "Greater Shadow Protection Potion",
	[7245] = "Holy Protection Potion",
	[17545] = "Greater Holy Protection Potion",
	[17549] = "Greater Arcane Protection Potion",
	-- cleanse
	[26677] = "Elixir of Poison Resistance",
	[7932] = "Anti-Venom",
	[7933] = "Strong Anti-Venom",
	[23786] = "Powerful Anti-Vendom",
	[3592] = "Jungle Remedy",
	[11359] = "Restorative Potion",
	[17550] = "Purification Potion",
	[45426] = "Lucidity Potion",

	-- juju
	[16321] = "Juju Escape",
	[16322] = "Juju Flurry",
	[16323] = "Juju Power",
	[16325] = "Juju Chill",
	[16326] = "Juju Ember",
	[16327] = "Juju Guile",
	[16329] = "Juju Might",
	-- misc
	[15231] = "Crystal Force",
	[15279] = "Crystal Spire",
	[29332] = "Fire-toasted Bun",
	[5665] = "Bogling Root",
	[23645] = "Hourglass Sand",
	[6727] = "Poisonous Mushroom",
	[15852] = "Dragonbreath Chili",
	[11350] = "Oil of Immolation",

	-- misc 2
	[23133] = "Gnomish Battle Chicken",
	[23074] = "Arcanite Dragonling",
	[18307] = "Barov Peasant Caller", -- horde
	[18308] = "Barov Peasant Caller", -- alliance
	[8892] = "Goblin Rocket Boots",
	[17490] = "Ancient Cornerstone Grimoire",
	[26066] = "Defender of the Timbermaw",

	-- misc 3
	[46002] = "Goblin Brainwashing Device",
	-- [21358] = "Rune of the Firelord", "has doused a", nil, "ff1eff00", "raid" },
	-- [45304] = { "Rune of the Firelord", "has doused a", nil, "ff1eff00", "raid" },
	[46001] = "MOLL-E, Remote Mail Terminal",
	-- [27571] = { "Cascade of Red Roses", "has showered a", "on", "ffff86e0", "any" },
	-- [45407] = { "Oranges", "is summoning", nil, "ff1eff00", "zone" }, -- special
	-- dynamite
	[15239] = "Crystal Charge",
	[4068] = "Iron Grenade",
	[23063] = "Dense Dynamite",
	[12419] = "Solid Dynamite",
	[19769] = "Thorium Grenade",
	[13241] = "Goblin Sapper Charge",
	[17291] = "Stratholme Holy Water",

	-- weapons
	[20747] = "Lesser Mana Oil",
	[25123] = "Brilliant Mana Oil",
	[25121] = "Wizard Oil",
	[25122] = "Brilliant Wizard Oil",
	[28898] = "Blessed Wizard Oil",
	[28891] = "Consecrated Sharpening Stone",
	[3829] = "Frost Oil",
	[3594] = "Shadow Oil",
	[22756] = "Elemental Sharpening Stone",
	[16138] = "Dense Sharpening Stone",
	[16622] = "Dense Weightstone",
	[46070] = "Cleaning Cloth",
}

RPLL.UNIT_CASTEVENT = function(caster, target, event, spellID, castDuration)
	if not (trackedSpells[spellID] or trackedConsumes[spellID]) then
		return
	end

	if event ~= "CAST" then
		return
	end

	local spell = trackedSpells[spellID] or trackedConsumes[spellID]
	if not spell then
		return
	end

	local casterName = UnitName(caster) --get name from GUID
	local targetName = UnitName(target)
	-- -- seems like on razorgore either caster or target can be null here
	-- -- probably related to MC
	if not casterName then
		casterName = "Unknown"
	end
	local verb = trackedConsumes[spellID] and " uses " or " casts "
	if targetName then
		CombatLogAdd(casterName .. verb .. spell .. " on " .. targetName .. ".")
	else
		CombatLogAdd(casterName .. verb .. spell .. ".")
	end
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

local rcount = 0
RPLL.RAID_ROSTER_UPDATE = function()
	local rnow = GetNumRaidMembers()
	if rnow == rcount then
		return
	end
	for i = 1, rnow do
		if UnitName("raid" .. i) then
			this:grab_unit_information("raid" .. i)
		end
	end
	rcount = rnow
end

local pcount = 0
RPLL.PARTY_MEMBERS_CHANGED = function()
	local pnow = GetNumPartyMembers()
	for i = 1, pnow do
		if UnitName("party" .. i) then
			this:grab_unit_information("party" .. i)
		end
	end
	pcount = pnow
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

RPLL.CHAT_MSG_SYSTEM = function(msg)
	-- "Iseut trades item Libram of the Faithful to Milkpress."
	local trade = string.find(msg, "^%w+ trades item")
	if trade then
		CombatLogAdd("LOOT_TRADE: " .. date("%d.%m.%y %H:%M:%S") .. "&" .. msg)
	end
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
