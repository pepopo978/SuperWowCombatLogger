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
- Fireball dot ticks are renamed so that you can view fireball casts separately from the dot ticks.
