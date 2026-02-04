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

RPLL.NUM_PLAYERS_IN_COMBAT = 0

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

RPLL:RegisterEvent("PLAYER_REGEN_DISABLED")
RPLL:RegisterEvent("PLAYER_REGEN_ENABLED")

RPLL:RegisterEvent("UNIT_DIED")
RPLL:RegisterEvent("PLAYER_LOGOUT")

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

-- cache what we've seen, SpellInfo (while fairly speedy) is _5x_ slower than keeping a table
local spellCache = {}

-- some mobs have a 'target' but their spell cast doesn't mention one, we add them ourselves
local specials = nil
local specials_data = {
	["Blackwing Lair"] = {
		[22539] = "Shadow Flame", -- firemaw/ebonroc/flamegor/nefarian
		[23308] = "Incinerate", -- chromag
		[23310] = "Time Lapse", -- chromag
		[23313] = "Corrosive Acid", -- chromag
		[23315] = "Ignite Flesh", -- chromag
		[23187] = "Frost Burn", -- chromag
		[22334] = "Bomb" -- techies
		-- [23461] = "Flame Breath", -- vael
	},
	["Onyxia's Lair"] = {
		[18435] = "Flame Breath", -- onyxia
	}
	-- ["Tower of Karazhan"] = {
		-- gnarlmoon lunar shift
	-- }
}

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
	[51012] = "Jewel of Wild Magics",
	--[51143] = "Remains of Overwhelming Power", already gets logged
	[57667] = "Elunes Guardian",

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

	[56546] = "Highborne Insight",

	[45511] = "Bloodlust", --shaman

	[14280] = "Viper Sting", -- hunter

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
	-- elixirs
	-- flasks
	-- zanzas
	-- blasted
	-- protections

	-- food:
	[18194] = "Nightfin Soup",

	-- drinks
	[20875] = "Rumsey Rum",
	[25804] = "Rumsey Rum Black Label",
	[25722] = "Rumsey Rum Dark",

	-- potions
	[16589] = "Noggenfogger Elixir",
	-- restoratives
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
	-- cleanse
	[7932] = "Anti-Venom",
	[7933] = "Strong Anti-Venom",
	[23786] = "Powerful Anti-Venom",
	[3592] = "Jungle Remedy",

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
	[23645] = "Hourglass Sand",
	[27664] = "Stormwind Gift of Friendship",
	[27665] = "Ironforge Gift of Friendship",
	[27666] = "Darnassus Gift of Friendship",
	[27669] = "Orgrimmar Gift of Friendship",
	[27670] = "Thunder Bluff Gift of Friendship",
	[27671] = "Undercity Gift of Friendship",

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


	-- manually pick an alternative
	--[24800] = "Smoked Desert Dumplings",
	--[24800] = "Spicy Beef Burrito",
	[24800] = "Power Mushroom",

	--[19199] = "Nordanaar Herbal Tea",
	[19199] = "Tea with Sugar",

	--[25660] = "Dirge's Kickin' Chimaerok Chops",
	--[25660] = "Gnome Stew",
	--[25660] = "Roasted Tauren",
	[25660] = "Hardened Mushroom",  -- also avoids 's

	--[18230] = "Sweet Mountain Berry",
	--[18230] = "Jarl's Juicy Jumbly",
	--[18230] = "Icepaw Cookie",
	[18230] = "Grilled Squid",  -- also avoids 's

	--[17534] = "The McWeaksauce Classic",
	[17534] = "Major Healing Potion",

	--[24869] = "Bobbing Apple",
	--[24869] = "Plump Country Pumpkin",
	[24869] = "Winter Veil Cookie",  -- avoids ambiguous consumable: pumpkin

	--[5004] = "Spiced Wolf Meat",
	--[5004] = "Beer Basted Boar Ribs",
	--[5004] = "Kaldorei Spider Kabob",
	--[5004] = "Herb Baked Egg",
	--[5004] = "Lollipop",
	--[5004] = "Candy Bar",
	--[5004] = "Chocolate Square",
	--[5004] = "Cactus Apple Surprise",
	--[5004] = "Crispy Bat Wing",
	--[5004] = "Gingerbread Cookie",
	--[5004] = "Bad Egg Nog",
	--[5004] = "Sprat’s Crunchy Vulture Surprise",
	--[5004] = "Maritime Gumbo",
	[5004] = "Roasted Kodo Meat",  -- also avoids 's

	--[25990] = "Lovely Apple",
	--[25990] = "Delicious Birthday Cake",
	[25990] = "Graccus Mince Meat Fruitcake",  -- also avoids 's

	[1127] = "Graccus Homemade Meat Pie",  -- also avoids 's, low level

	--[435] = "Clam Chowder",
	--[435] = "Tigule and Foror's Strawberry Ice Cream",
	[435] = "Dig Rat Stew",  -- also avoids 's, low level

	--[434] = "Styleen's Sour Suckerpop",
	[434] = "Spiced Beef Jerky",  -- also avoids 's, low level

	--[1129] = "Bellara's Nutterbar",
	[1129] = "Crunchy Frog",  -- also avoids 's, low level


	-- renames to remove 's and other special syntax
	[10667] = "Rage of Ages",
	[57106] = "Medivhs Merlot",
	[57107] = "Medivhs Merlot Blue Label",
	[22790] = "Kreegs Stout Beatdown",
	[57043] = "Danonzos Tel'Abim Delight",
	[57045] = "Danonzos Tel'Abim Medley",
	[57055] = "Danonzos Tel'Abim Surprise",
}

-- auto generated, manually add stuff in trackedConsumes instead
local dbConsumes = {
	-- all potions in the database
	[437] = "Minor Mana Potion",
	[438] = "Lesser Mana Potion",
	[438] = "Full Moonshine",
	[439] = "Minor Healing Potion",
	[440] = "Lesser Healing Potion",
	[440] = "Discolored Healing Potion",
	[441] = "Healing Potion",
	[673] = "Oil of Olaf",
	[673] = "Elixir of Minor Defense",
	[2023] = "Mana Potion",
	[2024] = "Greater Healing Potion",
	[2367] = "Elixir of Lions Strength",
	[2370] = "Minor Rejuvenation Potion",
	[2374] = "Elixir of Minor Agility",
	[2378] = "Elixir of Minor Fortitude",
	[2379] = "Swiftness Potion",
	[2380] = "Minor Magic Resistance Potion",
	[3160] = "Elixir of Lesser Agility",
	[3164] = "Elixir of Ogres Strength",
	[3166] = "Elixir of Wisdom",
	[3169] = "Limited Invulnerability Potion",
	[3219] = "Weak Trolls Blood Potion",
	[3220] = "Elixir of Defense",
	[3222] = "Strong Trolls Blood Potion",
	[3223] = "Mighty Trolls Blood Potion",
	[3593] = "Elixir of Fortitude",
	[3680] = "Lesser Invisibility Potion",
	[4042] = "Superior Healing Potion",
	[4042] = "Combat Healing Potion",
	[4941] = "Lesser Stoneshield Potion",
	[6512] = "Elixir of Detect Lesser Invisibility",
	[6612] = "Rage Potion",
	[6613] = "Great Rage Potion",
	[6615] = "Free Action Potion",
	[7178] = "Elixir of Water Breathing",
	[7233] = "Fire Protection Potion",
	[7239] = "Frost Protection Potion",
	[7242] = "Shadow Protection Potion",
	[7245] = "Holy Protection Potion",
	[7254] = "Nature Protection Potion",
	[7396] = "Fishliver Oil",
	[7840] = "Swim Speed Potion",
	[7844] = "Elixir of Firepower",
	[8212] = "Elixir of Giant Growth",
	[9512] = "Thistle Tea",
	[11319] = "Elixir of Water Walking",
	[11328] = "Elixir of Agility",
	[11334] = "Elixir of Greater Agility",
	[11348] = "Elixir of Superior Defense",
	[11349] = "Elixir of Greater Defense",
	[11359] = "Restorative Potion",
	[11364] = "Magic Resistance Potion",
	[11387] = "Wildvine Potion",
	[11389] = "Elixir of Detect Undead",
	[11390] = "Arcane Elixir",
	[11392] = "Invisibility Potion",
	[11396] = "Elixir of Greater Intellect",
	[11405] = "Elixir of Giants",
	[11406] = "Elixir of Demonslaying",
	[11407] = "Elixir of Detect Demon",
	[11474] = "Elixir of Shadow Power",
	[11903] = "Greater Mana Potion",
	[12608] = "Catseye Elixir",
	[15822] = "Dreamless Sleep Potion",
	[17038] = "Winterfall Firewater",
	[17528] = "Mighty Rage Potion",
	[17530] = "Superior Mana Potion",
	[17530] = "Combat Mana Potion",
	[17531] = "Diet McWeaksauce",
	[17531] = "Major Mana Potion",
	[17534] = "Major Healing Potion",
	[17534] = "The McWeaksauce Classic",
	[17535] = "Elixir of the Sages",
	[17537] = "Elixir of Brute Force",
	[17538] = "Elixir of the Mongoose",
	[17539] = "Greater Arcane Elixir",
	[17540] = "Greater Stoneshield Potion",
	[17543] = "Greater Fire Protection Potion",
	[17544] = "Greater Frost Protection Potion",
	[17545] = "Greater Holy Protection Potion",
	[17546] = "Greater Nature Protection Potion",
	[17548] = "Greater Shadow Protection Potion",
	[17549] = "Greater Arcane Protection Potion",
	[17550] = "Purification Potion",
	[17619] = "Alchemists Stone",
	[17624] = "Flask of Petrification",
	[17626] = "Flask of the Titans",
	[17627] = "Flask of Distilled Wisdom",
	[17628] = "Flask of Supreme Power",
	[17629] = "Flask of Chromatic Resistance",
	[18832] = "Lily Root",
	[19199] = "Tea with Sugar",
	[19199] = "Nordanaar Herbal Tea",
	[21393] = "Major Healing Draught",
	[21394] = "Superior Healing Draught",
	[21395] = "Major Mana Draught",
	[21396] = "Superior Mana Draught",
	[21920] = "Elixir of Frost Power",
	[22729] = "Major Rejuvenation Potion",
	[22807] = "Elixir of Greater Water Breathing",
	[24360] = "Greater Dreamless Sleep Potion",
	[24361] = "Major Trolls Blood Potion",
	[24363] = "Mageblood Potion",
	[24364] = "Living Action Potion",
	[24382] = "Spirit of Zanza",
	[24383] = "Swiftness of Zanza",
	[24417] = "Sheen of Zanza",
	[26276] = "Elixir of Greater Firepower",
	[26677] = "Elixir of Poison Resistance",
	[27538] = "Low Energy Regulator",
	[27540] = "Shimmering Moonstone Tablet",
	[27652] = "Bloodkelp Elixir of Resistance",
	[27653] = "Bloodkelp Elixir of Dodging",
	[28766] = "Coldhowls Necklace",
	[28769] = "The Black Pendant",
	[29236] = "Mug of Shimmer Stout",
	[29432] = "Frozen Rune",
	[30331] = "Permanent Sheen of Zanza",
	[30336] = "Permanent Spirit of Zanza",
	[30338] = "Permanent Swiftness of Zanza",
	[36928] = "Concoction of the Emerald Mongoose",
	[36931] = "Concoction of the Arcane Giant",
	[36934] = "Concoction of the Dreamwater",

	[45427] = "Dreamshard Elixir",
	[45489] = "Dreamtonic",
	[45988] = "Elixir of Greater Nature Power",

	-- the spellid for all items that match this query
	-- class=0 and subclass=0 and spellid_1 is not null and stackable > 1 and spellid_1 in (select entry from spell_template where effect1=6)
	[430] = "Refreshing Spring Water",
	[430] = "Conjured Water",
	[430] = "Kaja'Cola",
	[430] = "Sun-Parched Waterskin",
	[431] = "Ice Cold Milk",
	[431] = "Conjured Fresh Water",
	[431] = "Blended Bean Brew",
	[432] = "Melon Juice",
	[432] = "Conjured Purified Water",
	[432] = "Bubbling Water",
	[432] = "Fizzy Faire Drink",
	[433] = "Tough Jerky",
	[433] = "Slitherskin Mackerel",
	[433] = "Healing Herb",
	[433] = "Darnassian Bleu",
	[433] = "Charred Wolf Meat",
	[433] = "Roasted Boar Meat",
	[433] = "Shiny Red Apple",
	[433] = "Tough Hunk of Bread",
	[433] = "Forest Mushroom Cap",
	[433] = "Small Pumpkin",
	[433] = "Ripe Watermelon",
	[433] = "Conjured Muffin",
	[433] = "Raw Longjaw Mud Snapper",
	[433] = "Brilliant Smallfish",
	[433] = "Raw Loch Frenzy",
	[433] = "Raw Rainbow Fin Albacore",
	[433] = "Oil Covered Fish",
	[433] = "Leg Meat",
	[433] = "Candy Cane",
	[433] = "Darkmoon Dog",
	[433] = "Bean Soup",
	[433] = "Crunchy Murloc Fin",
	[433] = "Crusty Flatbread",
	[434] = "Dalaran Sharp",
	[434] = "Conjured Bread",
	[434] = "Sauteed Sunfish",
	[434] = "Haunch of Meat",
	[434] = "Tel'Abim Banana",
	[434] = "Freshly Baked Bread",
	[434] = "Longjaw Mud Snapper",
	[434] = "Red-speckled Mushroom",
	[434] = "Fissure Plant",
	[434] = "Rainbow Fin Albacore",
	[434] = "Raw Bristle Whisker Catfish",
	[434] = "Loch Frenzy Delight",
	[434] = "Smoked Bear Meat",
	[434] = "Versicolor Treat",
	[434] = "Deeprun Rat Kabob",
	[434] = "Holiday Cheesewheel",
	[434] = "Styleen's Sour Suckerpop",
	[434] = "Spiced Beef Jerky",
	[434] = "Darkshore Grouper",
	[435] = "Dwarven Mild",
	[435] = "Westfall Stew",
	[435] = "Conjured Rye",
	[435] = "Succulent Pork Ribs",
	[435] = "Mutton Chop",
	[435] = "Snapvine Watermelon",
	[435] = "Moist Cornbread",
	[435] = "Bristle Whisker Catfish",
	[435] = "Spongy Morel",
	[435] = "Dig Rat Stew",
	[435] = "Clam Chowder",
	[435] = "Tigule and Foror's Strawberry Ice Cream",
	[435] = "Raw Mithril Head Trout",
	[435] = "Steamed Mandu",
	[435] = "Pickled Kodo Foot",
	[435] = "Bottled Spirits",
	[435] = "Flank of Meat",
	[673] = "Oil of Olaf",
	[700] = "Slumber Sand",
	[774] = "Highpeak Thistle",
	[806] = "Potion of Fervor",
	[1090] = "Magic Dust",
	[1127] = "Conjured Pumpernickel",
	[1127] = "Stormwind Brie",
	[1127] = "Wild Hog Shank",
	[1127] = "Goldenbark Apple",
	[1127] = "Mulgore Spice Bread",
	[1127] = "Raw Spotted Yellowtail",
	[1127] = "Delicious Cave Mold",
	[1127] = "Frog Leg Stew",
	[1127] = "Mithril Head Trout",
	[1127] = "Raw Glossy Mightfish",
	[1127] = "Winter Squid",
	[1127] = "Raw Summer Bass",
	[1127] = "Raw Redgill",
	[1127] = "Raw Nightfin Snapper",
	[1127] = "Wild Ricecake",
	[1127] = "Graccu's Homemade Meat Pie",
	[1127] = "Moonbrook Riot Taffy",
	[1127] = "Red Hot Wings",
	[1127] = "Underwater Mushroom Cap",
	[1127] = "Mysterious Floater",
	[1127] = "Amberglaze Donut",
	[1129] = "Fine Aged Cheddar",
	[1129] = "Cured Ham Steak",
	[1129] = "Soft Banana Bread",
	[1129] = "Moon Harvest Pumpkin",
	[1129] = "Raw Black Truffle",
	[1129] = "Spotted Yellowtail",
	[1129] = "Conjured Sourdough",
	[1129] = "Raw Spinefin Halibut",
	[1129] = "Grilled King Crawler Legs",
	[1129] = "Bloodbelly Fish",
	[1129] = "Darkclaw Lobster",
	[1129] = "Large Raw Mightfish",
	[1129] = "Filet of Redgill",
	[1129] = "Heaven Peach",
	[1129] = "Undermine Clam Chowder",
	[1129] = "Spicy Beefstick",
	[1129] = "Runn Tum Tuber",
	[1129] = "Bellara's Nutterbar",
	[1129] = "Crunchy Frog",
	[1129] = "Darnassus Kimchi Pie",
	[1129] = "Striped Yellowtail",
	[1131] = "Conjured Sweet Roll",
	[1131] = "Alterac Swiss",
	[1131] = "Dried King Bolete",
	[1131] = "Homemade Cherry Pie",
	[1131] = "Roasted Quail",
	[1131] = "Deep Fried Plantains",
	[1131] = "Spinefin Halibut",
	[1131] = "Mixed Berries",
	[1131] = "Grim Guzzler Boar",
	[1131] = "Shinsollo",
	[1131] = "Deep Fried Candybar",
	[1131] = "Cabbage Kimchi",
	[1131] = "Radish Kimchi",
	[1131] = "Winter Kimchi",
	[1131] = "Un'Goro Etherfruit",
	[1131] = "Ripe Tel'Abim Banana",
	[1133] = "Sweet Nectar",
	[1133] = "Conjured Spring Water",
	[1133] = "Enchanted Water",
	[1133] = "Goldthorn Tea",
	[1133] = "Green Garden Tea",
	[1135] = "Moonberry Juice",
	[1135] = "Conjured Mineral Water",
	[1135] = "Bottled Winterspring Water",
	[1137] = "Conjured Sparkling Water",
	[1137] = "Morning Glory Dew",
	[1138] = "Crystal Basilisk Spine",
	[2639] = "Cooked Crab Claw",
	[2639] = "Senggin Root",
	[5004] = "Spiced Wolf Meat",
	[5004] = "Beer Basted Boar Ribs",
	[5004] = "Kaldorei Spider Kabob",
	[5004] = "Roasted Kodo Meat",
	[5004] = "Herb Baked Egg",
	[5004] = "Lollipop",
	[5004] = "Candy Bar",
	[5004] = "Chocolate Square",
	[5004] = "Cactus Apple Surprise",
	[5004] = "Crispy Bat Wing",
	[5004] = "Gingerbread Cookie",
	[5004] = "Bad Egg Nog",
	[5004] = "Sprat’s Crunchy Vulture Surprise",
	[5004] = "Maritime Gumbo",
	[5005] = "Goretusk Liver Pie",
	[5005] = "Crab Cake",
	[5005] = "Coyote Steak",
	[5005] = "Dry Pork Ribs",
	[5005] = "Blood Sausage",
	[5005] = "Crocolisk Steak",
	[5005] = "Fillet of Frenzy",
	[5005] = "Strider Stew",
	[5005] = "Boiled Clams",
	[5006] = "Seasoned Wolf Kabob",
	[5006] = "Redridge Goulash",
	[5006] = "Murloc Fin Soup",
	[5006] = "Crocolisk Gumbo",
	[5006] = "Curiously Tasty Omelet",
	[5006] = "Gooey Spider Cake",
	[5006] = "Big Bear Steak",
	[5006] = "Hot Lion Chops",
	[5006] = "Crispy Lizard Tail",
	[5006] = "Lean Venison",
	[5006] = "Goblin Deviled Clams",
	[5006] = "Lean Wolf Steak",
	[5006] = "Plump Country Pumpkin",
	[5007] = "Tasty Lion Steak",
	[5007] = "Soothing Turtle Bisque",
	[5007] = "Barbecued Buzzard Wing",
	[5007] = "Giant Clam Scorcho",
	[5007] = "Jungle Stew",
	[5007] = "Carrion Surprise",
	[5007] = "Mystery Stew",
	[5007] = "Hot Wolf Ribs",
	[5007] = "Heavy Crocolisk Stew",
	[5007] = "Spiced Wolf Ribs",
	[5007] = "Roast Raptor",
	[5020] = "Stormstout",
	[5665] = "Bogling Root",
	[5909] = "Watered-down Beer",
	[6114] = "Raptor Punch",
	[6410] = "Scorpid Surprise",
	[6614] = "Cowardly Flight Potion",
	[6727] = "Poisonous Mushroom",
	[6758] = "Party Grenade",
	[6902] = "Super Snuff",
	[7396] = "Fishliver Oil",
	[7737] = "Raw Brilliant Smallfish",
	[7737] = "Sickly Looking Fish",
	[7737] = "Raw Slitherskin Mackerel",
	[8070] = "Restoring Balm",
	[8277] = "Severed Voodoo Claw",
	[8312] = "Really Sticky Glue",
	[10256] = "Heavy Kodo Stew",
	[10256] = "Spiced Chili Crab",
	[10256] = "Clamlette Surprise",
	[10256] = "Spider Sausage",
	[10256] = "Tender Wolf Steak",
	[10256] = "Monster Omelet",
	[10256] = "Juicy Striped Melon",
	[10257] = "Lobster Stew",
	[10257] = "Baked Salmon",
	[10618] = "Scroll of Magic Warding",
	[10667] = "R.O.I.D.S.",
	[10668] = "Lung Juice Cocktail",
	[10669] = "Ground Scorpok Assay",
	[10692] = "Cerebral Cortex Compound",
	[10693] = "Gizzard Gum",
	[11319] = "Elixir of Water Walking",
	[11350] = "Oil of Immolation",
	[11371] = "Gift of Arthas",
	[15852] = "Dragonbreath Chili",
	[17038] = "Winterfall Firewater",
	[17545] = "Greater Holy Protection Potion",
	[18124] = "Blessed Sunfruit",
	[18140] = "Blessed Sunfruit Juice",
	[18229] = "Cooked Glossy Mightfish",
	[18229] = "Sweet Mountain Berry",
	[18230] = "Grilled Squid",
	[18230] = "Sweet Mountain Berry",
	[18230] = "Jarl's Juicy Jumbly",
	[18230] = "Icepaw Cookie",
	[18231] = "Hot Smoked Bass",
	[18233] = "Nightfin Soup",
	[18234] = "Mightfish Steak",
	[21149] = "Egg Nog",
	[21335] = "Scroll of Thorns",
	[21955] = "Razorlash Root",
	[21956] = "Scroll of Empowered Protection",
	[22731] = "Runn Tum Tuber Surprise",
	[22731] = "Juicy Striped Melon",
	[22734] = "Conjured Crystal Water",
	[22789] = "Gordok Green Grog",
	[22790] = "Kreeg's Stout Beatdown",
	[23698] = "Bottled Alterac Spring Water",
	[24005] = "Harvest Bread",
	[24005] = "Harvest Fruit",
	[24005] = "Harvest Boar",
	[24005] = "Harvest Fish",
	[24005] = "Winter Veil Roast",
	[24005] = "Winter Veil Loaf",
	[24005] = "Winter Veil Candy",
	[24355] = "Harvest Nectar",
	[24355] = "Winter Veil Eggnog",
	[24382] = "Spirit of Zanza",
	[24383] = "Swiftness of Zanza",
	[24417] = "Sheen of Zanza",
	[24707] = "Lollipop",
	[24707] = "Candy Corn",
	[24707] = "Candy Bar",
	[24707] = "Conjured Mana Orange",
	[24800] = "Smoked Desert Dumplings",
	[24800] = "Spicy Beef Burrito",
	[24800] = "Power Mushroom",
	[24869] = "Bobbing Apple",
	[24869] = "Winter Veil Cookie",
	[24869] = "Plump Country Pumpkin",
	[25660] = "Dirge's Kickin' Chimaerok Chops",
	[25660] = "Hardened Mushroom",
	[25660] = "Gnome Stew",
	[25660] = "Roasted Tauren",
	[25990] = "Graccu's Mince Meat Fruitcake",
	[25990] = "Lovely Apple",
	[25990] = "Delicious Birthday Cake",
	[26030] = "Windblossom Berries",
	[26263] = "Festival Dumplings",
	[27571] = "Handful of Rose Petals",
	[27720] = "Buttermilk Delight",
	[27721] = "Very Berry Cream",
	[27722] = "Sweet Surprise",
	[27723] = "Dark Desire",
	[29006] = "Bubbly Beverage",
	[29007] = "Freshly-Squeezed Lemonade",
	[29008] = "Friendship Bread",
	[29008] = "Deepsea Lobster",
	[29041] = "Tasty Summer Treat",
	[29055] = "Refreshing Red Apple",
	[29073] = "Conjured Cinnamon Roll",
	[29073] = "Gargantuan Tel'Abim Banana",
	[29332] = "Fire-toasted Bun",
	[29333] = "Midsummer Sausage",
	[29334] = "Toasted Smorc",
	[29335] = "Elderberry Pie",
	[29388] = "Fiery Festival Brew",
	[30020] = "Crystal Infused Bandage",
	[30088] = "Lesser Mark of the Dawn",
	[30089] = "Mark of the Dawn",
	[30090] = "Greater Mark of the Dawn",
	[45024] = "Delicious Pizza",
	[45024] = "Delicious Pizza",
	[45060] = "Volatile Concoction",
	[45425] = "Potion of Quickness",
	[45426] = "Lucidity Potion",
	[45427] = "Dreamshard Elixir",
	[45489] = "Dreamtonic",
	[45624] = "Le Fishe Au Chocolat",
	[45626] = "Gilneas Hot Stew",
	[46084] = "Gurubashi Gumbo",
	[49552] = "Empowering Herbal Salad",
	[57043] = "Danonzo's Tel'Abim Delight",
	[57045] = "Danonzo's Tel'Abim Medley",
	[57055] = "Danonzo's Tel'Abim Surprise",
	[57106] = "Medivh's Merlot",
	[57107] = "Medivh's Merlot Blue",
}


-- add if it doesn't already exist
for key, val in pairs(dbConsumes) do
  if trackedConsumes[key] == nil then
    trackedConsumes[key] = val
  end
end

local function logPlayersInCombat()
	local currentPlayersInCombat = 0
	local totalPlayers = 0

	if UnitInRaid("player") then
		totalPlayers = GetNumRaidMembers()
		for i = 1, totalPlayers do
			if UnitAffectingCombat("raid" .. i) then
				currentPlayersInCombat = currentPlayersInCombat + 1
			end
		end
	elseif UnitInParty("player") then
		totalPlayers = GetNumRaidMembers()
		for i = 1, totalPlayers do
			if UnitAffectingCombat("party" .. i) then
				currentPlayersInCombat = currentPlayersInCombat + 1
			end
		end
	end

	if currentPlayersInCombat ~= RPLL.NUM_PLAYERS_IN_COMBAT then
		RPLL.NUM_PLAYERS_IN_COMBAT = currentPlayersInCombat
		CombatLogAdd("PLAYERS_IN_COMBAT: " .. tostring(currentPlayersInCombat) .. "/" .. tostring(totalPlayers))
	end
end

-- Shutdown flag to prevent processing during logout
RPLL.isShuttingDown = false

RPLL:SetScript("OnUpdate", function()
	-- Stop processing during shutdown to prevent crash 132
	if RPLL.isShuttingDown then return end

	if (this.limit or 1) > GetTime() then
		return
	else
		this.limit = GetTime() + 15 -- update combat state every 15 seconds in case logger isn't involved in the fight
	end
	logPlayersInCombat()
end)

-- Handle PLAYER_LOGOUT to prevent crash 132 during shutdown
RPLL.PLAYER_LOGOUT = function()
	-- Set shutdown flag immediately to stop OnUpdate processing
	RPLL.isShuttingDown = true

	-- Unregister all events first
	this:UnregisterAllEvents()

	-- Clear scripts
	this:SetScript("OnUpdate", nil)
	this:SetScript("OnEvent", nil)

	-- Clear caches to prevent stale data
	for k in pairs(spellCache) do spellCache[k] = nil end
	if this.PlayerInformation then
		for k in pairs(this.PlayerInformation) do this.PlayerInformation[k] = nil end
	end
	if RPLL.LoggedCombatantInfo then
		for k in pairs(RPLL.LoggedCombatantInfo) do RPLL.LoggedCombatantInfo[k] = nil end
	end
end

RPLL.PLAYER_REGEN_DISABLED = function()
	CombatLogAdd("PLAYER_REGEN_DISABLED")
	logPlayersInCombat()
end

RPLL.PLAYER_REGEN_ENABLED = function()
	CombatLogAdd("PLAYER_REGEN_ENABLED")
	logPlayersInCombat()
end

RPLL.UNIT_DIED = function(guid)
	local name = UnitName(guid) or "Unknown"
	CombatLogAdd("UNIT_DIED:" .. name .. ":" .. guid)
end

-- this is verbose but prevents allocating runtime strings each call
local fmt_with_rank_target = "CAST: %s %s %s(%s)(%s) on %s."
local fmt_with_rank = "CAST: %s %s %s(%s)(%s)."
local fmt_with_target = "CAST: %s %s %s(%s) on %s."
local fmt_simple = "CAST: %s %s %s(%s)."

local function LogCastEventV2(caster, target, event, spellID, castDuration)
	if not (caster and spellID) then return end
	if event == "MAINHAND" or event == "OFFHAND" then return end

	-- cache lookup
	local cachedSpell = spellCache[spellID]
	local spell = cachedSpell and cachedSpell[1]
	local rank = cachedSpell and cachedSpell[2]

	if not spell then
		-- Spell not cached yet? Call SpellInfo and cache the result.
		spell,rank = SpellInfo(spellID)
		if spell then
			-- only cache Rank for things that have one. Some items have joke ranks!
			rank = string.find(rank, "^Rank") and rank or ""
			spellCache[spellID] = { spell, rank }
		end
	end

	if not spell then return end

	local targetName -- = UnitName(target) or "Unknown"
	local casterName = UnitName(caster) or "Unknown"
	if specials and specials[spellID] then
		targetName = UnitName(caster.."target")
	elseif target and target ~= "" then
		targetName = UnitName(target) or "Unknown"
	-- else
		-- local t = UnitName(caster.."target")
		-- targetName = t and (t.."(via targeting)")
	end

	local verb
	if event == "START" then
		verb = "begins to cast"
	elseif event == "FAIL" then
		verb = "fails casting"
	elseif event == "CHANNEL" then
		verb = "channels"
	else -- event == "CAST"
		verb = "casts"
	end

	if targetName then
		if rank ~= "" then
			CombatLogAdd(format(fmt_with_rank_target, casterName, verb, spell, spellID, rank, targetName))
		else
			CombatLogAdd(format(fmt_with_target, casterName, verb, spell, spellID, targetName))
		end
	else
		if rank ~= "" then
			CombatLogAdd(format(fmt_with_rank, casterName, verb, spell, spellID, rank))
		else
			CombatLogAdd(format(fmt_simple, casterName, verb, spell, spellID))
		end
	end
end

-- kept for backwards compatibility with existing tools
local function LogCastEventV1(caster, target, event, spellID, castDuration)
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

RPLL.UNIT_CASTEVENT = function(caster, target, event, spellID, castDuration)
	LogCastEventV1(caster, target, event, spellID, castDuration) -- for backwards compatibility
	LogCastEventV2(caster, target, event, spellID, castDuration)
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

  -- Rate limiting cache for player info scanning (timestamps only, session-only)
  this.PlayerInformation = {}

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
	-- don't log zone change if the player is a ghost (presumably released and is running back to the instance)
	-- zone change causes legacyplayers to wipe all unit information and can cause issues
	if UnitIsGhost("player") then
		return
	end

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
    -- Check rate limiting using simple timestamp cache
    local last_update = this.PlayerInformation[unit_name]
    if last_update ~= nil and time() - last_update <= 30 then
			return
		end

    -- Gather all info into local table
    local info = {}
		info["last_update_date"] = date("%d.%m.%y %H:%M:%S")
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
			local pet_guid = nil
			if unit == "player" then
				pet_name = UnitName("pet")
				_, pet_guid = UnitExists("pet")
			elseif strfind(unit, "raid") then
				local str = "raidpet" .. strsub(unit, 5)
				pet_name = UnitName(str)
				_, pet_guid = UnitExists(str)
			elseif strfind(unit, "party") then
				local str = "partypet" .. strsub(unit, 6)
				pet_name = UnitName(str)
				_, pet_guid = UnitExists(str)
			end

			if pet_name ~= nil and pet_name ~= Unknown then
				info["pet"] = pet_name
			end
			if pet_guid then
				info["pet_guid"] = pet_guid
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

    info["gear"] = {}
		if any_item then
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

		info["guid"] = "0x0"
		local exists, guid = UnitExists(unit)
		if exists and guid then
			info["guid"] = guid
		end

    -- Update timestamp cache
    this.PlayerInformation[unit_name] = time()

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

		local result = prep_value(character["name"]) .. "&"
				.. prep_value(character["hero_class"]) .. "&"
				.. prep_value(character["race"]) .. "&"
				.. prep_value(character["sex"]) .. "&"
				.. prep_value(character["pet"]) .. "&"
				.. prep_value(character["guild_name"]) .. "&"
				.. prep_value(character["guild_rank_name"]) .. "&"
				.. prep_value(character["guild_rank_index"]) .. "&"
				.. gear_str .. "&"
				.. prep_value(character["talents"]) .. "&"
				.. prep_value(character["guid"]) .. "&"
				.. prep_value(character["pet_guid"])

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
