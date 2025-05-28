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
	[9907] = "Faerie Fire",
	[17392] = "Faerie Fire (Feral)",

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
	[24361] = "Major Trolls Blood Potion", -- laugh

	[3593] = "Elixir of Fortitude",
	[17038] = "Winterfall Firewater",
	[11371] = "Gift of Arthas",

	-- food:
	[18194] = "Nightfin Soup",
	-- [24800] = "Smoked Desert Dumplings", -- same  as power mush
	[18124] = "Blessed Sunfruit",
	[18140] = "Blessed Sunfruit Juice",
	[18230] = "Grilled Squid",

	[57043] = "Danonzos Tel'Abim Delight",
	[57045] = "Danonzos Tel'Abim Medley",
	[57055] = "Danonzos Tel'Abim Surprise",

	[24800] = "Power Mushroom",
	[25660] = "Hardened Mushroom",
	-- [25660] = "Dirges Kickin' Chimaerok Chops", -- same as hardened mush
	[45624] = "Le Fishe Au Chocolat",
	[46084] = "Gurubashi Gumbo",
	-- drinks
	[22789] = "Gordok Green Grog",
	[20875] = "Rumsey Rum",
	[25804] = "Rumsey Rum Black Label",
	[57106] = "Medivhs Merlot",
	[57107] = "Medivhs Merlot Blue Label",
	[22790] = "Kreegs Stout Beatdown",

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
	[10667] = "Rage of Ages",
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


	-- remove 's
	[60593] = "Jarls Juicy Jumbly",
	[80104] = "Sprats Crunchy Vulture Surprise",
	[7228] = "Tigule and Forors Strawberry Ice Cream",
	[17407] = "Graccus Homemade Meat Pie",
	[18633] = "Styleens Sour Suckerpop",
	[18635] = "Bellaras Nutterbar",
	[21023] = "Dirges Kickin' Chimaerok Chops",
	[21215] = "Graccus Mince Meat Fruitcake",
}


local dbConsumes = {
	-- all potions in the database
	[436] = "Restore Mana",
	[437] = "Restore Mana",
	[438] = "Restore Mana",
	[439] = "Healing Potion",
	[440] = "Healing Potion",
	[441] = "Healing Potion",
	[673] = "Lesser Armor",
	[834] = "Lesser Armor",
	[2023] = "Restore Mana",
	[2024] = "Healing Potion",
	[2367] = "Lesser Strength",
	[2370] = "Rejuvenation Potion",
	[2374] = "Lesser Agility",
	[2376] = "Lesser Intellect",
	[2378] = "Health",
	[2379] = "Speed",
	[2380] = "Resistance",
	[2599] = "Rejuvenation Potion",
	[2600] = "Rejuvenation Potion",
	[3157] = "Lesser Agility",
	[3158] = "Lesser Agility",
	[3159] = "Agility",
	[3160] = "Agility",
	[3161] = "Lesser Strength",
	[3162] = "Lesser Strength",
	[3163] = "Strength",
	[3164] = "Strength",
	[3165] = "Lesser Intellect",
	[3166] = "Lesser Intellect",
	[3167] = "Intellect",
	[3168] = "Intellect",
	[3169] = "Invulnerability",
	[3219] = "Regeneration",
	[3220] = "Armor",
	[3221] = "Regeneration",
	[3222] = "Regeneration",
	[3223] = "Regeneration",
	[3593] = "Health II",
	[3680] = "Lesser Invisibility",
	[4042] = "Healing Potion",
	[4941] = "Stoneshield",
	[6512] = "Detect Lesser Invisibility",
	[6612] = "Rage",
	[6613] = "Great Rage",
	[6615] = "Free Action",
	[7178] = "Water Breathing",
	[7230] = "Fire Protection",
	[7231] = "Fire Protection",
	[7232] = "Fire Protection",
	[7233] = "Fire Protection",
	[7234] = "Fire Protection",
	[7235] = "Shadow Protection ",
	[7236] = "Frost Protection",
	[7237] = "Frost Protection",
	[7238] = "Frost Protection",
	[7239] = "Frost Protection",
	[7240] = "Frost Protection",
	[7241] = "Shadow Protection ",
	[7242] = "Shadow Protection ",
	[7243] = "Shadow Protection ",
	[7244] = "Shadow Protection ",
	[7245] = "Holy Protection ",
	[7246] = "Holy Protection ",
	[7247] = "Holy Protection ",
	[7248] = "Holy Protection ",
	[7249] = "Holy Protection ",
	[7250] = "Nature Protection ",
	[7251] = "Nature Protection ",
	[7252] = "Nature Protection ",
	[7253] = "Nature Protection ",
	[7254] = "Nature Protection ",
	[7396] = "Fishliver Oil",
	[7840] = "Swim Speed",
	[7844] = "Fire Power",
	[8212] = "Enlarge",
	[9512] = "Restore Energy",
	[11319] = "Water Walking",
	[11328] = "Agility",
	[11330] = "Agility",
	[11331] = "Strength",
	[11332] = "Great Strength",
	[11333] = "Greater Agility",
	[11334] = "Greater Agility",
	[11348] = "Greater Armor",
	[11349] = "Armor",
	[11351] = "Fire Shield",
	[11359] = "Restoration",
	[11363] = "Resistance",
	[11364] = "Resistance",
	[11387] = "Wildvine Potion",
	[11389] = "Detect Undead",
	[11390] = "Arcane Elixir",
	[11392] = "Invisibility",
	[11393] = "Intellect",
	[11394] = "Greater Intellect",
	[11395] = "Greater Intellect",
	[11396] = "Greater Intellect",
	[11404] = "Great Strength",
	[11405] = "Elixir of the Giants",
	[11406] = "Elixir of Demonslaying",
	[11407] = "Detect Demon",
	[11474] = "Shadow Power",
	[11903] = "Restore Mana",
	[12608] = "Stealth Detection",
	[15822] = "Dreamless Sleep",
	[17038] = "Winterfall Firewater",
	[17528] = "Mighty Rage",
	[17530] = "Restore Mana",
	[17531] = "Restore Mana",
	[17534] = "Healing Potion",
	[17535] = "Elixir of the Sages",
	[17537] = "Elixir of Brute Force",
	[17538] = "Elixir of the Mongoose",
	[17539] = "Greater Arcane Elixir",
	[17540] = "Greater Stoneshield",
	[17543] = "Fire Protection",
	[17544] = "Frost Protection",
	[17545] = "Holy Protection ",
	[17546] = "Nature Protection ",
	[17548] = "Shadow Protection ",
	[17549] = "Arcane Protection",
	[17550] = "Purification",
	[17619] = "Alchemists Stone",
	[17624] = "Petrification",
	[17626] = "Flask of the Titans",
	[17627] = "Distilled Wisdom",
	[17628] = "Supreme Power",
	[17629] = "Chromatic Resistance",
	[18191] = "Increased Stamina",
	[18192] = "Increased Agility",
	[18193] = "Increased Spirit",
	[18194] = "Mana Regeneration",
	[18222] = "Health Regeneration",
	[18832] = "Lily Root",
	[18942] = "Fire Protection",
	[19199] = "Tea with Sugar",
	[21393] = "Healing Draught",
	[21394] = "Healing Draught",
	[21395] = "Restore Mana",
	[21396] = "Restore Mana",
	[21920] = "Frost Power",
	[22729] = "Rejuvenation Potion",
	[22730] = "Increased Intellect",
	[22807] = "Greater Water Breathing",
	[23396] = "Restoration",
	[24360] = "Greater Dreamless Sleep",
	[24361] = "Regeneration",
	[24363] = "Mana Regeneration",
	[24364] = "Living Free Action",
	[24382] = "Spirit of Zanza",
	[24383] = "Swiftness of Zanza",
	[24417] = "Sheen of Zanza",
	[25661] = "Increased Stamina",
	[26276] = "Greater Firepower",
	[26677] = "Cure Poison",
	[27533] = "Fire Resistance",
	[27534] = "Frost Resistance",
	[27535] = "Shadow Resistance",
	[27536] = "Holy Resistance",
	[27538] = "Nature Resistance",
	[27540] = "Arcane Resistance",
	[27652] = "Elixir of Resistance",
	[27653] = "Elixir of Dodging",
	[28765] = "Fire Resistance",
	[28766] = "Frost Resistance",
	[28768] = "Nature Resistance",
	[28769] = "Shadow Resistance",
	[28770] = "Arcane Resistance",
	[29236] = "Shimmer Stout",
	[29432] = "Fire Protection",
	[30003] = "Sheen of Zanza",
	[30331] = "Permanent Sheen of Zanza",
	[30336] = "Permanent Spirit of Zanza",
	[30338] = "Permanent Swiftness of Zanza",
	[57139] = "Lucid Action",
	[57140] = "Elixir of the Mongoose",
	[45427] = "Dreamshard Elixir",
	[45489] = "Dreamtonic",
	[45988] = "Elixir of Greater Nature Power",
	[49553] = "Increased Healing Bonus",
	[51228] = "Invulnerability",
	[51267] = "Zandalari Vigil",

	-- all items that match this query
	-- class=0 and subclass=0 and spellid_1 is not null and stackable > 1 and spellid_1 in (select entry from spell_template where effect1=6)
	[117] = "Tough Jerky",
	[159] = "Refreshing Spring Water",
	[414] = "Dalaran Sharp",
	[422] = "Dwarven Mild",
	[724] = "Goretusk Liver Pie",
	[733] = "Westfall Stew",
	[787] = "Slitherskin Mackerel",
	[961] = "Healing Herb",
	[1017] = "Seasoned Wolf Kabob",
	[1082] = "Redridge Goulash",
	[1113] = "Conjured Bread",
	[1114] = "Conjured Rye",
	[1119] = "Bottled Spirits",
	[1177] = "Oil of Olaf",
	[1179] = "Ice Cold Milk",
	[1205] = "Melon Juice",
	[1322] = "Fishliver Oil",
	[1326] = "Sauteed Sunfish",
	[1450] = "Potion of Fervor",
	[1487] = "Conjured Pumpernickel",
	[1645] = "Moonberry Juice",
	[1703] = "Crystal Basilisk Spine",
	[1707] = "Stormwind Brie",
	[1708] = "Sweet Nectar",
	[1970] = "Restoring Balm",
	[2070] = "Darnassian Bleu",
	[2091] = "Magic Dust",
	[2136] = "Conjured Purified Water",
	[2287] = "Haunch of Meat",
	[2288] = "Conjured Fresh Water",
	[2679] = "Charred Wolf Meat",
	[2680] = "Spiced Wolf Meat",
	[2681] = "Roasted Boar Meat",
	[2682] = "Cooked Crab Claw",
	[2683] = "Crab Cake",
	[2684] = "Coyote Steak",
	[2685] = "Succulent Pork Ribs",
	[2687] = "Dry Pork Ribs",
	[2888] = "Beer Basted Boar Ribs",
	[3220] = "Blood Sausage",
	[3434] = "Slumber Sand",
	[3448] = "Senggin Root",
	[3662] = "Crocolisk Steak",
	[3663] = "Murloc Fin Soup",
	[3664] = "Crocolisk Gumbo",
	[3665] = "Curiously Tasty Omelet",
	[3666] = "Gooey Spider Cake",
	[3726] = "Big Bear Steak",
	[3727] = "Hot Lion Chops",
	[3728] = "Tasty Lion Steak",
	[3729] = "Soothing Turtle Bisque",
	[3770] = "Mutton Chop",
	[3771] = "Wild Hog Shank",
	[3772] = "Conjured Spring Water",
	[3927] = "Fine Aged Cheddar",
	[4457] = "Barbecued Buzzard Wing",
	[4536] = "Shiny Red Apple",
	[4537] = "Tel'Abim Banana",
	[4538] = "Snapvine Watermelon",
	[4539] = "Goldenbark Apple",
	[4540] = "Tough Hunk of Bread",
	[4541] = "Freshly Baked Bread",
	[4542] = "Moist Cornbread",
	[4544] = "Mulgore Spice Bread",
	[4592] = "Longjaw Mud Snapper",
	[4593] = "Bristle Whisker Catfish",
	[4599] = "Cured Ham Steak",
	[4601] = "Soft Banana Bread",
	[4602] = "Moon Harvest Pumpkin",
	[4603] = "Raw Spotted Yellowtail",
	[4604] = "Forest Mushroom Cap",
	[4605] = "Red-speckled Mushroom",
	[4606] = "Spongy Morel",
	[4607] = "Delicious Cave Mold",
	[4608] = "Raw Black Truffle",
	[4656] = "Small Pumpkin",
	[4791] = "Enchanted Water",
	[4941] = "Really Sticky Glue",
	[4952] = "Stormstout",
	[5057] = "Ripe Watermelon",
	[5066] = "Fissure Plant",
	[5095] = "Rainbow Fin Albacore",
	[5206] = "Bogling Root",
	[5265] = "Watered-down Beer",
	[5342] = "Raptor Punch",
	[5349] = "Conjured Muffin",
	[5350] = "Conjured Water",
	[5457] = "Severed Voodoo Claw",
	[5472] = "Kaldorei Spider Kabob",
	[5473] = "Scorpid Surprise",
	[5474] = "Roasted Kodo Meat",
	[5476] = "Fillet of Frenzy",
	[5477] = "Strider Stew",
	[5478] = "Dig Rat Stew",
	[5479] = "Crispy Lizard Tail",
	[5480] = "Lean Venison",
	[5525] = "Boiled Clams",
	[5526] = "Clam Chowder",
	[5527] = "Goblin Deviled Clams",
	[5632] = "Cowardly Flight Potion",
	[5823] = "Poisonous Mushroom",
	[5845] = "Flank of Meat",
	[5859] = "Party Grenade",
	[5878] = "Super Snuff",
	[6038] = "Giant Clam Scorcho",
	[6289] = "Raw Longjaw Mud Snapper",
	[6290] = "Brilliant Smallfish",
	[6291] = "Raw Brilliant Smallfish",
	[6299] = "Sickly Looking Fish",
	[6303] = "Raw Slitherskin Mackerel",
	[6308] = "Raw Bristle Whisker Catfish",
	[6316] = "Loch Frenzy Delight",
	[6317] = "Raw Loch Frenzy",
	[6361] = "Raw Rainbow Fin Albacore",
	[6458] = "Oil Covered Fish",
	[6807] = "Frog Leg Stew",
	[6887] = "Spotted Yellowtail",
	[6888] = "Herb Baked Egg",
	[6890] = "Smoked Bear Meat",
	[7097] = "Leg Meat",
	[7228] = "Tigule and Foror's Strawberry Ice Cream",
	[7806] = "Lollipop",
	[7807] = "Candy Bar",
	[7808] = "Chocolate Square",
	[8075] = "Conjured Sourdough",
	[8076] = "Conjured Sweet Roll",
	[8077] = "Conjured Mineral Water",
	[8078] = "Conjured Sparkling Water",
	[8079] = "Conjured Crystal Water",
	[8364] = "Mithril Head Trout",
	[8365] = "Raw Mithril Head Trout",
	[8410] = "R.O.I.D.S.",
	[8411] = "Lung Juice Cocktail",
	[8412] = "Ground Scorpok Assay",
	[8423] = "Cerebral Cortex Compound",
	[8424] = "Gizzard Gum",
	[8543] = "Underwater Mushroom Cap",
	[8766] = "Morning Glory Dew",
	[8827] = "Elixir of Water Walking",
	[8932] = "Alterac Swiss",
	[8948] = "Dried King Bolete",
	[8950] = "Homemade Cherry Pie",
	[8952] = "Roasted Quail",
	[8953] = "Deep Fried Plantains",
	[8956] = "Oil of Immolation",
	[8957] = "Spinefin Halibut",
	[8959] = "Raw Spinefin Halibut",
	[9088] = "Gift of Arthas",
	[9451] = "Bubbling Water",
	[9681] = "Grilled King Crawler Legs",
	[10841] = "Goldthorn Tea",
	[11415] = "Mixed Berries",
	[11444] = "Grim Guzzler Boar",
	[11584] = "Cactus Apple Surprise",
	[11950] = "Windblossom Berries",
	[12209] = "Lean Wolf Steak",
	[12210] = "Roast Raptor",
	[12211] = "Spiced Wolf Ribs",
	[12212] = "Jungle Stew",
	[12213] = "Carrion Surprise",
	[12214] = "Mystery Stew",
	[12215] = "Heavy Kodo Stew",
	[12216] = "Spiced Chili Crab",
	[12217] = "Dragonbreath Chili",
	[12218] = "Monster Omelet",
	[12224] = "Crispy Bat Wing",
	[12238] = "Darkshore Grouper",
	[12763] = "Un'Goro Etherfruit",
	[12820] = "Winterfall Firewater",
	[13460] = "Greater Holy Protection Potion",
	[13546] = "Bloodbelly Fish",
	[13754] = "Raw Glossy Mightfish",
	[13755] = "Winter Squid",
	[13756] = "Raw Summer Bass",
	[13758] = "Raw Redgill",
	[13759] = "Raw Nightfin Snapper",
	[13810] = "Blessed Sunfruit",
	[13813] = "Blessed Sunfruit Juice",
	[13851] = "Hot Wolf Ribs",
	[13888] = "Darkclaw Lobster",
	[13893] = "Large Raw Mightfish",
	[13927] = "Cooked Glossy Mightfish",
	[13928] = "Grilled Squid",
	[13929] = "Hot Smoked Bass",
	[13930] = "Filet of Redgill",
	[13931] = "Nightfin Soup",
	[13933] = "Lobster Stew",
	[13934] = "Mightfish Steak",
	[13935] = "Baked Salmon",
	[16166] = "Bean Soup",
	[16167] = "Versicolor Treat",
	[16168] = "Heaven Peach",
	[16169] = "Wild Ricecake",
	[16170] = "Steamed Mandu",
	[16171] = "Shinsollo",
	[16766] = "Undermine Clam Chowder",
	[16971] = "Clamlette Surprise",
	[17119] = "Deeprun Rat Kabob",
	[17197] = "Gingerbread Cookie",
	[17198] = "Egg Nog",
	[17199] = "Bad Egg Nog",
	[17222] = "Spider Sausage",
	[17344] = "Candy Cane",
	[17404] = "Blended Bean Brew",
	[17405] = "Green Garden Tea",
	[17406] = "Holiday Cheesewheel",
	[17407] = "Graccu's Homemade Meat Pie",
	[17408] = "Spicy Beefstick",
	[17747] = "Razorlash Root",
	[18045] = "Tender Wolf Steak",
	[18254] = "Runn Tum Tuber Surprise",
	[18255] = "Runn Tum Tuber",
	[18269] = "Gordok Green Grog",
	[18284] = "Kreeg's Stout Beatdown",
	[18632] = "Moonbrook Riot Taffy",
	[18633] = "Styleen's Sour Suckerpop",
	[18635] = "Bellara's Nutterbar",
	[19223] = "Darkmoon Dog",
	[19224] = "Red Hot Wings",
	[19225] = "Deep Fried Candybar",
	[19299] = "Fizzy Faire Drink",
	[19300] = "Bottled Winterspring Water",
	[19304] = "Spiced Beef Jerky",
	[19305] = "Pickled Kodo Foot",
	[19306] = "Crunchy Frog",
	[19318] = "Bottled Alterac Spring Water",
	[19696] = "Harvest Bread",
	[19994] = "Harvest Fruit",
	[19995] = "Harvest Boar",
	[19996] = "Harvest Fish",
	[19997] = "Harvest Nectar",
	[20074] = "Heavy Crocolisk Stew",
	[20079] = "Spirit of Zanza",
	[20080] = "Sheen of Zanza",
	[20081] = "Swiftness of Zanza",
	[20388] = "Lollipop",
	[20389] = "Candy Corn",
	[20390] = "Candy Bar",
	[20452] = "Smoked Desert Dumplings",
	[20516] = "Bobbing Apple",
	[21023] = "Dirge's Kickin' Chimaerok Chops",
	[21030] = "Darnassus Kimchi Pie",
	[21031] = "Cabbage Kimchi",
	[21033] = "Radish Kimchi",
	[21215] = "Graccu's Mince Meat Fruitcake",
	[21235] = "Winter Veil Roast",
	[21236] = "Winter Veil Loaf",
	[21240] = "Winter Veil Candy",
	[21241] = "Winter Veil Eggnog",
	[21254] = "Winter Veil Cookie",
	[21537] = "Festival Dumplings",
	[21552] = "Striped Yellowtail",
	[22218] = "Handful of Rose Petals",
	[22236] = "Buttermilk Delight",
	[22237] = "Dark Desire",
	[22238] = "Very Berry Cream",
	[22239] = "Sweet Surprise",
	[22324] = "Winter Kimchi",
	[22895] = "Conjured Cinnamon Roll",
	[23160] = "Friendship Bread",
	[23161] = "Freshly-Squeezed Lemonade",
	[23164] = "Bubbly Beverage",
	[23172] = "Refreshing Red Apple",
	[23175] = "Tasty Summer Treat",
	[23194] = "Lesser Mark of the Dawn",
	[23195] = "Mark of the Dawn",
	[23196] = "Greater Mark of the Dawn",
	[23211] = "Toasted Smorc",
	[23246] = "Fiery Festival Brew",
	[23326] = "Midsummer Sausage",
	[23327] = "Fire-toasted Bun",
	[23435] = "Elderberry Pie",
	[23684] = "Crystal Infused Bandage",
	[30818] = "Maritime Gumbo",
	[40001] = "Delicious Pizza",
	[45001] = "Delicious Pizza",
	[50739] = "Roasted Tauren",
	[50741] = "Gnome Stew",
	[51262] = "Volatile Concoction",
	[51267] = "Spicy Beef Burrito",
	[51710] = "Plump Country Pumpkin",
	[51711] = "Sweet Mountain Berry",
	[51712] = "Juicy Striped Melon",
	[51713] = "Plump Country Pumpkin",
	[51714] = "Sweet Mountain Berry",
	[51717] = "Hardened Mushroom",
	[51718] = "Juicy Striped Melon",
	[51720] = "Power Mushroom",
	[53015] = "Gurubashi Gumbo",
	[55509] = "Deepsea Lobster",
	[60593] = "Jarl's Juicy Jumbly",
	[60954] = "Ripe Tel'Abim Banana",
	[60955] = "Gargantuan Tel'Abim Banana",
	[60976] = "Danonzo's Tel'Abim Surprise",
	[60977] = "Danonzo's Tel'Abim Delight",
	[60978] = "Danonzo's Tel'Abim Medley",
	[60984] = "Icepaw Cookie",
	[61174] = "Medivh's Merlot",
	[61175] = "Medivh's Merlot Blue",
	[61181] = "Potion of Quickness",
	[61224] = "Dreamshard Elixir",
	[61225] = "Lucidity Potion",
	[61423] = "Dreamtonic",
	[65016] = "Scroll of Thorns",
	[65017] = "Scroll of Empowered Protection",
	[65018] = "Scroll of Magic Warding",
	[70241] = "Amberglaze Donut",
	[80104] = "Sprat's Crunchy Vulture Surprise",
	[80156] = "Highpeak Thistle",
	[80167] = "Kaja'Cola",
	[80168] = "Crunchy Murloc Fin",
	[80250] = "Sun-Parched Waterskin",
	[80251] = "Crusty Flatbread",
	[80866] = "Lovely Apple",
	[83004] = "Conjured Mana Orange",
	[83271] = "Delicious Birthday Cake",
	[83309] = "Empowering Herbal Salad",
	[84040] = "Le Fishe Au Chocolat",
	[84041] = "Gilneas Hot Stew",
	[84605] = "Mysterious Floater",
}


-- add if it doesn't already exist
for key, val in pairs(dbConsumes) do
  if trackedConsumes[key] == nil then
    trackedConsumes[key] = val
  end
end


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

	if not casterName then
		casterName = "Unknown" -- can happen before player name is queried from server
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
