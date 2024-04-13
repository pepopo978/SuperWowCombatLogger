import re


def replace_instances(player_name, filename):
    player_name = player_name.strip().capitalize()
    # Define the instances to replace and their replacements
    replacements = {
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
        r"'s Fireball\.": "'s FireballDot.",  # make fireball dot appear as a separate spell
        r'.*You fail to cast.*\n': '',
        r'.*You fail to perform.*\n': '',
    }

    # Read the contents of the file
    with open(filename, 'r') as file:
        text = file.read()

    # Perform replacements
    for pattern, replacement in replacements.items():
        text = re.sub(pattern, replacement, text)

    # Write the modified text back to the file
    with open(filename, 'w') as file:
        file.write(text)


# Example usage
player_name = input("Enter player name: ")
filename = input("Enter filename (defaults to WowCombatLog.txt if left empty): ")
if not filename.strip():
    filename = 'WowCombatLog.txt'

replace_instances(player_name, filename)
print(f"Messages with You/Your have been converted to {player_name}.")
