# Installation
This requires https://github.com/balakethelock/SuperWoW to work.

Remove `AdvancedVanillaCombatLog` and `AdvancedVanillaCombatLog_Helper` directories from your addons folder if they existed.

Place `SuperWowCombatLogger` in Interface/Addons.

# Preparing for upload
In order to upload your logs to monkeylogs/turtlogs you need to run `format_log_for_upload.py` on your WowCombatLog.txt.  

Copy `format_log_for_upload.py` and `run_format_log.bat`(windows) or `run_format_log.sh`(mac/linux) to the same directory as your WowCombatLog.txt and double click the appropriate `run_format_log` file.
You can also run the python script directly in a terminal in that directory with `python format_log_for_upload.py`. 

Fill in your player name and the name of your log file when prompted, update a zip containing the formatted log to monkey/turtlogs.

# Changes from AdvancedVanillaCombatLog
- No longer requires any raiders to run the AdvancedVanillaCombatLog_Helper addon.
- No longer need to spam failure messages to write to the log
- No longer overwrites all of the combat event format strings to change you -> playername.  This would break addons like bigwigs that looked for messages like "You have been afflicted by Poison Charge".
It does still overwrite the initial debuff/buff events to add a (1) because I deemed it unlikely to break other addons and is convenient compared to editing those messages after the fact.
```
    AURAADDEDOTHERHELPFUL = "%s gains %s (1)."
    AURAADDEDOTHERHARMFUL = "%s is afflicted by %s (1)."
    AURAADDEDSELFHARMFUL = "You are afflicted by %s (1)."
    AURAADDEDSELFHELPFUL = "You gain %s (1)."
```
- Self damage is now separated as Playername (self damage)
- Shaman totem spells are edited to appear as though the shaman cast them so they get credit for the spell.
- Pet autoattacks will now appear under "Auto Attack (pet)" on their owners and their spells will appear as though the owner cast them.
- Greater Feral Spirit, Battle Chicken, Arcanite Dragonling are similarly edited to associate with their owners.
- Tracks the caster and target for the following max level spells that were missing from the combat log:
    - Faerie Fire
    - Sunder Armor
    - Curse of the Elements
    - Curse of Recklessness
    - Curse of Shadow
    - Curse of Weakness
    - Curse of Tongues
    - Expose Armor
    - Heal over Time casts (ticks have the original spell name)
        - Rejuvenation Cast -> Improved Rejuvenation
        - Regrowth Cast -> Improved Regrowth
        - Renew Cast -> Improved Renew
