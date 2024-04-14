# Installation
Remove `AdvancedVanillaCombatLog` directory from your addons folder but leave AdvancedVanillaCombatLog_Helper.   
Place `SuperWowCombatLogger` in Interface/Addons.

# Preparing for upload
In order to upload your logs to monkeylogs/legacy logs you need to run `format_log_for_upload.py` on your WowCombatLog.txt.  

Copy this file to the same directory as your WowCombatLog.txt and run `python format_log_for_upload.py`.  

Fill in your player name and the name of your log file when prompted, then zip the new WowCombatLog.txt and upload it to monkeylogs/legacy logs.

# Changes from AdvancedVanillaCombatLog
- No longer need to spam failure messages to write to the log
- No longer overwrites all of the combat event format strings to change you -> playername.  This would break addons like bigwigs that looked for messages like "You have been afflicted by Poison Charge".
It does still overwrite the initial debuff/buff events to add a (1) because I deemed it unlikely to break other addons and is convenient compared to editing those messages after the fact.
```
    AURAADDEDOTHERHELPFUL = "%s gains %s (1)."
    AURAADDEDOTHERHARMFUL = "%s is afflicted by %s (1)."
    AURAADDEDSELFHARMFUL = "You are afflicted by %s (1)."
    AURAADDEDSELFHELPFUL = "You gain %s (1)."
```
- In order to upload to monkeylogs/legacy logs need to run `convert_you.py` on your WowCombatLog.txt
- The dot component of the following spells have been renamed to allow viewing casts of those spells independently from ticks:
    - Fireball Dot  -> Improved Fireball
    - Pyroblast Dot -> Pyroclast Barrage
    - Immolate Dot  -> Improved Immolate
    - Moonfire Dot  -> Improved Moonfire
- Tracks Sunder Armor and Faerie Fire casts.
