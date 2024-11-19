import os
import re
import shutil
import time
import zipfile


def handle_replacements(line, replacements):
    for pattern, replacement in replacements.items():
        try:
            new_text, num_subs = re.subn(pattern, replacement, line)
        except Exception as e:
            print(f"Error replacing pattern: {pattern} with replacement: {replacement}")
            print(f"Line: {line}")
            raise e
        if num_subs:
            return new_text

    return line


def replace_instances(player_name, filename):
    player_name = player_name.strip().capitalize()

    # Mob names with apostrophes have top priority
    # only the first match will be replaced
    mob_names_with_apostrophe = {
        "Onyxia's Elite Guard": "Onyxias Elite Guard",
        "Sartura's Royal Guard": "Sarturas Royal Guard",
        "Medivh's Merlot Blue Label": "Medivhs Merlot Blue Label",
    }

    # Pet replacements have next priority
    # only the first match will be replaced
    pet_replacements = {
        r"  ([a-zzA-Z][ a-zzA-Z]+[a-zzA-Z]) \(([a-zzA-Z]+)\) (hits|crits|misses)": r"  \g<2>'s Pet Summoned \g<3>",
        # convert pet hits/crits/misses to spell 'Pet Summoned' on the hunter
        r"  ([a-zzA-Z][ a-zzA-Z]+[a-zzA-Z]) \(([a-zzA-Z]+)\)'s": r"  \g<2>'s",  # pet ability
    }

    # You replacements have next priority
    # Only the first two matches will be replaced
    you_replacements = {
        r'.*You fail to cast.*\n': '',
        r'.*You fail to perform.*\n': '',
        r"You suffer (.*?) from your": rf"{player_name} suffers \g<1> from {player_name} (self damage) 's",
        # handle self damage
        r"Your (.*?) hits you for": rf"{player_name} (self damage) 's \g<1> hits {player_name} for",
        # handle self damage
        # handle self parry, legacy expects 'was' instead of 'is'
        r"Your (.*?) is parried by": rf"{player_name} 's \g<1> was parried by",
        r"Your (.*?) failed": rf"{player_name} 's \g<1> fails",
        r" failed. You are immune": rf" fails. {player_name} is immune",
        r" [Yy]our ": f" {player_name} 's ",
        r"You gain (.*?) from (.*?)'s": rf"{player_name} gains \g<1> from \g<2> 's",
        # handle gains from other players spells
        r"You gain (.*?) from ": rf"{player_name} gains \g<1> from {player_name} 's ",
        # handle gains from your own spells
        "You gain": f"{player_name} gains",  # handle buff gains
        "You hit": f"{player_name} hits",
        "You crit": f"{player_name} crits",
        "You are": f"{player_name} is",
        "You suffer": f"{player_name} suffers",
        "You lose": f"{player_name} loses",
        "You die": f"{player_name} dies",
        "You cast": f"{player_name} casts",
        "You create": f"{player_name} creates",
        "You perform": f"{player_name} performs",
        "You interrupt": f"{player_name} interrupts",
        "You miss": f"{player_name} misses",
        "You attack": f"{player_name} attacks",
        "You block": f"{player_name} blocks",
        "You parry": f"{player_name} parries",
        "You dodge": f"{player_name} dodges",
        "You resist": f"{player_name} resists",
        "You absorb": f"{player_name} absorbs",
        "You reflect": f"{player_name} reflects",
        "You receive": f"{player_name} receives",
        "You deflect": f"{player_name} deflects",
        r"was dodged\.": f"was dodged by {player_name}.",  # SPELLDODGEDOTHERSELF=%s's %s was dodged.  No 'You'
        "causes you": f"causes {player_name}",
        "heals you": f"heals {player_name}",
        "hits you for": f"hits {player_name} for",
        "crits you for": f"crits {player_name} for",
        r"You have slain (.*?)!": rf"\g<1> is slain by {player_name}.",
        r"(\S)\syou\.": rf"\g<1> {player_name}.",  # non whitespace character followed by whitespace followed by you
        "You fall and lose": f"{player_name} falls and loses",
    }

    # Generic replacements have 2nd priority
    # Only the first match will be replaced
    generic_replacements = {
        r" fades from .*\.": r"\g<0>",  # some buffs/debuffs have 's in them, need to ignore these lines
        r" gains .*\)\.": r"\g<0>",  # some buffs/debuffs have 's in them, need to ignore these lines
        r" is afflicted by .*\)\.": r"\g<0>",  # some buffs/debuffs have 's in them, need to ignore these lines

        # handle 's at beginning of line by looking for [double space] [playername] [Capital letter]
        r"  ([a-zA-Z' ]*?\S)'s ([A-Z])": r"  \g<1> 's \g<2>",
        r"from ([a-zA-Z' ]*?\S)'s ([A-Z])": r"from \g<1> 's \g<2>",  # handle 's in middle of line by looking for 'from'
        r"is immune to ([a-zA-Z' ]*?\S)'s ([A-Z])": r"is immune to \g<1> 's \g<2>",  # handle 's in middle of line by looking for 'is immune to'
        r"\)'s ([A-Z])": r") 's \g<1>",  # handle 's for pets
    }

    # Renames occur last
    # Only the first match will be replaced
    renames = {
        r"'s Fireball\.": "'s Improved Fireball.",  # make Fireball dot appear as a separate spell
        r"'s Flamestrike\.": "'s Improved Flamestrike.",  # make Flamestrike dot appear as a separate spell
        r"'s Pyroblast\.": "'s Pyroclast Barrage.",  # make Pyroblast dot appear as a separate spell
        r"'s Immolate\.": "'s Improved Immolate.",  # make Immolate dot appear as a separate spell
        r"'s Moonfire\.": "'s Improved Moonfire.",  # make Moonfire dot appear as a separate spell
        r"'s Holy Fire\.": "'s Cleansing Flames.",  # make Holy Fire dot appear as a separate spell
        r"'s Flame Shock\.": "'s Improved Flame Shock.",  # make Flame Shock dot appear as a separate spell

        # convert totem spells to appear as though the shaman cast them so that player gets credit
        r"  [A-Z][a-zA-Z ]* Totem [IVX]+ \((.*?)\) 's": r"  \g<1> 's",
        r" from [A-Z][a-zA-Z ]* Totem [IVX]+ \((.*?)\) 's": r" from \g<1> 's",

        "Onyxias Elite Guard": "Onyxia's Elite Guard",  # readd apostrophes
        "Sarturas Royal Guard": "Sartura's Royal Guard",
    }

    # check for players hitting themselves
    self_damage = {
        r"  ([a-zA-Z' ]*?) suffers (.*) (damage) from ([a-zA-Z' ]*?) 's": r"  \g<1> suffers \g<2> damage from \g<4> (self damage) 's",
        r"  ([a-zA-Z' ]*?) 's (.*) (hits|crits) ([a-zA-Z' ]*?) for": r"  \g<1> (self damage) 's \g<2> \g<3> \g<4> for",
    }

    # add quantity 1 to loot messages without quantity
    loot_replacements = {
        r"\|h\|r\.$": "|h|rx1.",
    }

    # create backup of original file
    backup_filename = filename.replace(".txt", "") + f".original.{int(time.time())}.txt"
    shutil.copyfile(filename, backup_filename)

    # Read the contents of the file
    with open(filename, 'r', encoding='utf-8') as file:
        lines = file.readlines()

    # collect pet names and change LOOT messages
    # 4/14 20:51:43.354  COMBATANT_INFO: 14.04.24 20:51:43&Hunter&HUNTER&Dwarf&2&PetName <- pet name
    pet_names = set()
    owner_names = set()

    ignored_pet_names = {"Razorgore the Untamed", "Deathknight Understudy", "Naxxramas Worshipper"}

    # associate common summoned pets with their owners as well
    summoned_pet_names = {"Greater Feral Spirit", "Battle Chicken", "Arcanite Dragonling"}
    summoned_pet_owner_regex = r"([a-zzA-Z][ a-zzA-Z]+[a-zzA-Z]) \(([a-zzA-Z]+)\)"
    for i, _ in enumerate(lines):
        # DPSMate logs have " 's" already which will break some of our parsing, remove the space
        lines[i] = lines[i].replace(" 's", "'s")
        if "COMBATANT_INFO" in lines[i]:
            try:
                line_parts = lines[i].split("&")
                pet_name = line_parts[5]
                if pet_name != "nil" and pet_name not in ignored_pet_names:
                    pet_names.add(f"{pet_name}")
                    owner_names.add(f"({line_parts[1]})")
                # remove pet name from uploaded combatant info, can cause player to not appear in logs if pet name
                # is a player name or ability name.  Don't even think legacy displays pet info anyways.
                line_parts[5] = "nil"

                # remove turtle items that won't exist
                for j, line_part in enumerate(line_parts):
                    if ":" in line_part:
                        item_parts = line_part.split(":")
                        if len(item_parts) == 4:
                            # definitely an item, remove any itemid > 25818 or enchantid > 3000 as they won't exist
                            if int(item_parts[0]) > 25818 or int(item_parts[1]) >= 3000:
                                line_parts[j] = "nil"

                lines[i] = "&".join(line_parts)

            except Exception as e:
                print(f"Error parsing pet name from line: {lines[i]}")
                print(e)
        elif "LOOT:" in lines[i]:
            lines[i] = handle_replacements(lines[i], loot_replacements)
        else:
            for summoned_pet_name in summoned_pet_names:
                if summoned_pet_name in lines[i]:
                    match = re.search(summoned_pet_owner_regex, lines[i])
                    if match:
                        pet_names.add(summoned_pet_name)
                        owner_names.add(f"({match.group(2)})")

    print(f"The following pet owners will have their pet hits/crits/misses/spells associated with them: {owner_names}")

    # Perform replacements
    # enumerate over lines to be able to modify the list in place
    for i, _ in enumerate(lines):
        # mob names with apostrophe
        lines[i] = handle_replacements(lines[i], mob_names_with_apostrophe)

        # handle pets
        for owner_name in owner_names:
            if owner_name in lines[i]:
                lines[i] = handle_replacements(lines[i], pet_replacements)

        # if line contains you/You
        if "you" in lines[i] or "You" in lines[i] or "dodged." in lines[i]:
            lines[i] = handle_replacements(lines[i], you_replacements)
            lines[i] = handle_replacements(lines[i],
                                           you_replacements)  # when casting ability on yourself need to do two replacements

        # generic replacements
        lines[i] = handle_replacements(lines[i], generic_replacements)

        # renames
        lines[i] = handle_replacements(lines[i], renames)

        # self damage
        for pattern, replacement in self_damage.items():
            match = re.search(pattern, lines[i])
            # check that group 1 and 4 are equal meaning the player is hitting themselves
            if match and match.group(1).strip() == match.group(4).strip():
                lines[i] = handle_replacements(lines[i], {pattern: replacement})
                break

    # Write the modified text back to the file
    with open(filename, 'w', encoding='utf-8') as file:
        file.writelines(lines)


def create_zip_file(source_file, zip_filename):
    with zipfile.ZipFile(zip_filename, 'w', zipfile.ZIP_DEFLATED) as zipf:
        zipf.write(source_file, arcname=os.path.basename(source_file))


player_name = input("Enter player name: ")
filename = input("Enter filename (defaults to WoWCombatLog.txt if left empty): ")
if not filename.strip():
    filename = 'WoWCombatLog.txt'

create_zip = input("Create zip file (default y): ")

replace_instances(player_name, filename)
if not create_zip.strip() or create_zip.lower().startswith('y'):
    create_zip_file(filename, filename + ".zip")
print(
    f"Messages with You/Your have been converted to {player_name}.  A backup of the original file has also been created.")
