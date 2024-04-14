import re
import shutil


def replace_instances(player_name, filename):
    player_name = player_name.strip().capitalize()
    # Define the instances to replace and their replacements
    replacements = {
        "'s": " 's",  # add space after playernames before possessive
        "Your": f"{player_name} 's",
        "You gain": f"{player_name} gains",
        "You hit": f"{player_name} hits",
        "You crit": f"{player_name} crits",
        "You are": f"{player_name} is",
        "You suffer": f"{player_name} suffers",
        "You die": f"{player_name} dies",
        "You cast": f"{player_name} casts",
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
        "you.": f"{player_name}.",
        "You fall and lose": f"{player_name} falls and loses",
        r"'s Fireball\.": "'s Improved Fireball.",  # make fireball dot appear as a separate spell
        r"'s Pyroblast\.": "'s Pyroclast Barrage.",  # make Pyroblast dot appear as a separate spell
        r"'s Immolate\.": "'s Improved Immolate.",  # make Immolate dot appear as a separate spell
        r"'s Moonfire\.": "'s Improved Moonfire.",  # make Immolate dot appear as a separate spell
        r'.*You fail to cast.*\n': '',
        r'.*You fail to perform.*\n': '',
    }

    # create backup of original file
    backup_filename = filename.replace(".txt", "") + ".original.txt"
    shutil.copyfile(filename, backup_filename)

    # Read the contents of the file
    with open(filename, 'r', encoding='utf-8') as file:
        text = file.read()

    # Perform replacements
    for pattern, replacement in replacements.items():
        text = re.sub(pattern, replacement, text, flags=re.IGNORECASE)

    # Write the modified text back to the file
    with open(filename, 'w', encoding='utf-8') as file:
        file.write(text)


# Example usage
player_name = input("Enter player name: ")
filename = input("Enter filename (defaults to WowCombatLog.txt if left empty): ")
if not filename.strip():
    filename = 'WowCombatLog.txt'

replace_instances(player_name, filename)
print(f"Messages with You/Your have been converted to {player_name}.  A backup of the original file has also been created.")
