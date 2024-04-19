import re
import shutil
import time


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

    # Pet replacements have top priority
    # only the first match will be replaced
    pet_replacements = {
        r"  ([a-zzA-Z]+) \(([a-zzA-Z]+)\) (hits|crits|misses)": r"  \g<2>'s Pet Summoned \g<3>",
        # convert pet hits/crits/misses to spell 'Pet Summoned' on the hunter
        r"  ([a-zzA-Z]+) \(([a-zzA-Z]+)\)'s": r"  \g<2>'s",  # pet ability
        r"([a-zzA-Z]+) \(([a-zzA-Z]+)\)": r"\g<1>(\g<2>)",
        # other pet logs, need to remove space otherwise not parsed correctly
    }

    # You replacements have next highest priority
    # Only the first match will be replaced
    you_replacements = {
        r'.*You fail to cast.*\n': '',
        r'.*You fail to perform.*\n': '',
        r"You suffer (.*?) from your": rf"{player_name} suffers \g<1> from {player_name}(selfdamage) 's",
        # handle self damage
        r"Your (.*?) hits you for": rf"{player_name}(selfdamage) 's \g<1> hits {player_name} for",  # handle self damage

        r" [Yy]our ": f" {player_name} 's ",
        "You gain": f"{player_name} gains",
        "You hit": f"{player_name} hits",
        "You crit": f"{player_name} crits",
        "You are": f"{player_name} is",
        "You suffer": f"{player_name} suffers",
        "You lose": f"{player_name} loses",
        "You die": f"{player_name} dies",
        "You cast": f"{player_name} casts",
        "You create": f"{player_name} creates",
        "You have slain": f"{player_name} has slain",
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
        "heals you": f"heals {player_name}",
        "hits you for": f"hits {player_name} for",
        "crits you for": f"crits {player_name} for",
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
        r"  ([a-zA-Z ]*?\S)'s ([A-Z])": r"  \g<1> 's \g<2>",
        r"from ([a-zA-Z ]*?\S)'s ([A-Z])": r"from \g<1> 's \g<2>",  # handle 's in middle of line by looking for 'from'
        r"\)'s ([A-Z])": r") 's \g<1>",  # handle 's for pets
    }

    # Renames occur last
    # Only the first match will be replaced
    renames = {
        r"'s Fireball\.": "'s Improved Fireball.",  # make fireball dot appear as a separate spell
        r"'s Pyroblast\.": "'s Pyroclast Barrage.",  # make Pyroblast dot appear as a separate spell
        r"'s Immolate\.": "'s Improved Immolate.",  # make Immolate dot appear as a separate spell
        r"'s Moonfire\.": "'s Improved Moonfire.",  # make Immolate dot appear as a separate spell

        " Burning Hatred": " Burning Flesh",
        # Burning Hatred custom twow spell not in logging database so it doesn't show up
        " Fire Rune": " Fire Storm",  # Fire rune is proc from flarecore 6 set
        " Spirit Link": " Spirit Bond",  # Shaman spell
        " Pain Spike": " Intense Pain",  # Spriest spell
        " Potent Venom": " Creeper Venom",  # lower kara trinket

        # convert totem spells to appear as though the shaman cast them so that player gets credit
        r"  [A-Z][a-zA-Z ]* Totem [IVX]+ \((.*?)\) 's": r"  \g<1> 's",
        r" from [A-Z][a-zA-Z ]* Totem [IVX]+ \((.*?)\) 's": r" from \g<1> 's",
    }

    # create backup of original file
    backup_filename = filename.replace(".txt", "") + f".original.{int(time.time())}.txt"
    shutil.copyfile(filename, backup_filename)

    # Read the contents of the file
    with open(filename, 'r', encoding='utf-8') as file:
        lines = file.readlines()

    # collect pet names
    # 4/14 20:51:43.354  COMBATANT_INFO: 14.04.24 20:51:43&Hunter&HUNTER&Dwarf&2&PetName <- pet name
    pet_names = set()
    for line in lines:
        if "COMBATANT_INFO" in line:
            try:
                line_parts = line.split("&")
                pet_name = line_parts[5]
                if pet_name != "nil" and pet_name != "Razorgore the Untamed":
                    pet_names.add(pet_name)
            except Exception as e:
                print(f"Error parsing pet name from line: {line}")
                print(e)

    print(f"The follow pet hits/crits/misses/spells will be associated with their owner: {pet_names}")

    # Perform replacements
    # enumerate over lines to be able to modify the list in place
    for i, _ in enumerate(lines):
        # handle hunter pets first, then process other rules
        for pet_name in pet_names:
            if pet_name in lines[i]:
                lines[i] = handle_replacements(lines[i], pet_replacements)

        # if line contains you/You
        if "you" in lines[i] or "You" in lines[i]:
            lines[i] = handle_replacements(lines[i], you_replacements)

        # generic replacements
        lines[i] = handle_replacements(lines[i], generic_replacements)

        # renames
        lines[i] = handle_replacements(lines[i], renames)

    # Write the modified text back to the file
    with open(filename, 'w', encoding='utf-8') as file:
        file.writelines(lines)


player_name = input("Enter player name: ")
filename = input("Enter filename (defaults to WowCombatLog.txt if left empty): ")
if not filename.strip():
    filename = 'WowCombatLog.txt'

replace_instances(player_name, filename)
print(
    f"Messages with You/Your have been converted to {player_name}.  A backup of the original file has also been created.")
