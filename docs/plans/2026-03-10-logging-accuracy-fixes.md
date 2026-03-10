# Logging Accuracy Fixes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix the approved logging-accuracy issues in the wrapper and bundled SWCL without changing the three accepted non-fixes.

**Architecture:** Split the work into wrapper-session correctness, SWCL metadata correctness, ambiguity-safe consume output, and documentation/test coverage. Preserve existing log prefixes where practical, but prefer truthful ambiguity or omission over false precision.

**Tech Stack:** Lua 5.x addon code, WoW 1.12 API stubs, local Lua regression harnesses in `scripts/`

---

### Task 1: Lock the wrapper behavior with failing tests

**Files:**
- Modify: `scripts/test_captainslog.lua`
- Test: `scripts/test_captainslog.lua`

**Step 1: Write the failing tests**

Add regression cases for:

- area-level auto-stop when moving from a tracked raid session into an untracked zone
- no auto-stop on `ZONE_CHANGED` / `ZONE_CHANGED_INDOORS` while the observed raid identity is unchanged
- delayed `COMBAT_END` after the player leaves combat before the rest of the raid
- `ENCOUNTER_END: WIPE` emitted from resolved combat end, not from `BigWigs_RebootModule`
- no fake `ZONE_TRANSITION` when only the canonical alias changes
- `RAID_LEADER` refresh on mid-session leader change

Example harness shape:

```lua
local pendingCombat = { raid2 = true }

local ctx = newHarness(function()
    return "Zul'Gurub"
end, {
    getNumRaidMembers = function() return 3 end,
    unitAffectingCombat = function(unit)
        return pendingCombat[unit] and 1 or nil
    end,
})

dispatch(ctx, "ZONE_CHANGED_NEW_AREA")
dispatch(ctx, "PLAYER_REGEN_ENABLED")
assertTrue(not containsPrefix(ctx.combatLogLines, "COMBAT_END: "), "combat should stay pending")

pendingCombat.raid2 = nil
tick(ctx)
assertTrue(containsPrefix(ctx.combatLogLines, "COMBAT_END: "), "combat should resolve on retry")
```

**Step 2: Run test to verify it fails**

Run: `lua scripts/test_captainslog.lua`

Expected: FAIL on the newly added lifecycle and encounter-resolution assertions.

**Step 3: Record helper needs**

Add any minimal test harness helpers needed for timer polling, roster updates, and alternate zone-event simulation. Keep them in the same file unless reuse becomes awkward.

**Step 4: Re-run the wrapper test file**

Run: `lua scripts/test_captainslog.lua`

Expected: Still FAIL, but only on the new coverage you added.

**Step 5: Commit**

```bash
git add scripts/test_captainslog.lua
git commit -m "test: add wrapper logging accuracy regressions"
```

### Task 2: Implement wrapper-side session and encounter fixes

**Files:**
- Modify: `CaptainsLog.lua`
- Test: `scripts/test_captainslog.lua`

**Step 1: Add explicit wrapper state**

Introduce state for:

- canonical vs observed zone
- pending combat resolution
- last emitted raid leader
- encounter kill/wipe resolution guard

Suggested shape:

```lua
local sessionCanonicalZone = nil
local sessionObservedZone = nil
local pendingCombatResolution = false
local lastRaidLeader = nil
local pendingCombatCheckAt = nil
```

**Step 2: Split lifecycle evaluation from fine-grained zone updates**

Refactor `SyncZoneLogging()` to accept event context, for example:

```lua
local function SyncZoneLogging(eventName)
    local isAreaTransition =
        eventName == "ZONE_CHANGED_NEW_AREA" or
        eventName == "PLAYER_ENTERING_WORLD" or
        eventName == "UPDATE_INSTANCE_INFO"
    -- update observed zone every time
    -- only evaluate auto start/stop on area transitions
end
```

Required behavior:

- auto-start on tracked raid zones at area transitions
- keep one auto session across tracked raid-to-tracked raid moves
- stop auto sessions on area transitions into untracked zones
- do not stop on `ZONE_CHANGED` / `ZONE_CHANGED_INDOORS` alone
- suppress alias-only fake `ZONE_TRANSITION` records

**Step 3: Replace one-shot combat-end logic with pending resolution**

Implement:

- set `pendingCombatResolution = true` on `PLAYER_REGEN_ENABLED` during an active session
- clear it on `PLAYER_REGEN_DISABLED`
- on `OnUpdate`, poll until all raid members are out of combat
- emit `COMBAT_END` once at resolution time
- preserve the existing session-level wipe heuristic unchanged

**Step 4: Move encounter wipe resolution out of `BigWigs_RebootModule`**

Implement:

- `BossDeath` still emits `ENCOUNTER_END: KILL` and clears `engagedBoss`
- resolved combat end emits `ENCOUNTER_END: WIPE <boss>` if `engagedBoss` is still set
- `BigWigs_RebootModule` becomes cleanup-only or a no-op for encounter-end logging

**Step 5: Refresh `RAID_LEADER` when leadership changes**

Register `RAID_ROSTER_UPDATE` in the wrapper and emit a leader marker only when:

- the first valid leader appears after session start
- the raid leader actually changes during an active session

**Step 6: Run tests**

Run: `lua scripts/test_captainslog.lua`

Expected: PASS

**Step 7: Commit**

```bash
git add CaptainsLog.lua scripts/test_captainslog.lua
git commit -m "fix: improve wrapper session and encounter accuracy"
```

### Task 3: Add a dedicated SWCL regression harness

**Files:**
- Create: `scripts/test_superwowcombatlogger.lua`
- Test: `scripts/test_superwowcombatlogger.lua`

**Step 1: Write the failing test harness**

Create a Lua harness that:

- stubs `CreateFrame`, `CombatLogAdd`, `SpellInfo`, `UnitName`, `UnitExists`, `GetInventoryItemLink`, `GetNumRaidMembers`, `GetSavedInstanceInfo`, and other RPLL dependencies
- loads `RPLLCollector.lua` and then `SuperWowCombatLogger.lua`
- captures emitted log lines and allows synthetic event dispatch

Skeleton:

```lua
local combatLogLines = {}

_G.CombatLogAdd = function(msg)
    table.insert(combatLogLines, msg)
end

dofile("RPLLCollector.lua")
dofile("SuperWowCombatLogger.lua")
```

**Step 2: Add failing tests for the approved SWCL fixes**

Cover:

- same-count roster swaps re-scan combatants
- all-nil gear does not poison the retry throttle
- duplicate V1+V2 cast emission is removed
- ambiguous consume spell IDs emit safe generic labels
- `specials` initializes by zone and enriches target only in matching zones
- `ZONE_INFO` preserves display casing and matches normalized aliases
- trade detection accepts accented names / non-`%w` names
- `UNIT_DIED` uses cached GUID-to-name data
- `strsplit` returns the proper tail token

**Step 3: Run test to verify it fails**

Run: `lua scripts/test_superwowcombatlogger.lua`

Expected: FAIL across the newly added accuracy regressions.

**Step 4: Commit**

```bash
git add scripts/test_superwowcombatlogger.lua
git commit -m "test: add bundled swcl accuracy regressions"
```

### Task 4: Fix SWCL combatant, zone, trade, death, and helper accuracy

**Files:**
- Modify: `SuperWowCombatLogger.lua`
- Test: `scripts/test_superwowcombatlogger.lua`

**Step 1: Replace roster-count short-circuit with a roster signature**

Implement a cheap signature based on visible raid member names or GUIDs:

```lua
local lastRaidRosterSignature = nil

local function BuildRaidRosterSignature()
    local parts = {}
    for i = 1, GetNumRaidMembers() do
        parts[#parts + 1] = UnitName("raid" .. i) or "nil"
    end
    return table.concat(parts, "|")
end
```

Only skip `RAID_ROSTER_UPDATE` work when the full signature is unchanged.

**Step 2: Make combatant throttling depend on successful scans**

Required behavior:

- do not stamp `PlayerInformation[unit_name]` before the scan proves usable
- treat all-nil gear as incomplete and retryable
- keep `LoggedCombatantInfo` dedupe unchanged

**Step 3: Add a GUID/name cache**

Populate a shared cache during successful unit scans:

```lua
RPLL.GuidToName = RPLL.GuidToName or {}
RPLL.GuidToName[guid] = unit_name
```

Use it in `UNIT_DIED` before falling back to `Unknown`.

**Step 4: Fix zone and formatting helpers**

Implement:

- correct `strsplit()` tail extraction
- normalized zone matching in `QueueRaidIds()`
- original-case fallback zone output
- broader English trade detection using a plain-text contains check

Example direction:

```lua
local function HasTradePhrase(msg)
    return string.find(msg, " trades item ", 1, true) ~= nil
end
```

**Step 5: Run tests**

Run: `lua scripts/test_superwowcombatlogger.lua`

Expected: PASS for the helper, roster, zone, trade, death, and combatant cases not related to consumes/cast duplication.

**Step 6: Commit**

```bash
git add SuperWowCombatLogger.lua scripts/test_superwowcombatlogger.lua
git commit -m "fix: improve bundled swcl metadata accuracy"
```

### Task 5: Make consume and cast output truthful

**Files:**
- Modify: `SuperWowCombatLogger.lua`
- Test: `scripts/test_superwowcombatlogger.lua`

**Step 1: Split consume metadata into exact and ambiguous groups**

Replace the current single-string assumption with explicit ambiguity handling.

Suggested shape:

```lua
local exactConsumes = {
    [17545] = "Greater Holy Protection Potion",
}

local ambiguousConsumes = {
    [24800] = { "Smoked Desert Dumplings", "Spicy Beef Burrito", "Power Mushroom" },
}
```

**Step 2: Introduce an ambiguity-safe label helper**

Implement a formatter such as:

```lua
local function GetConsumeLabel(spellID)
    if exactConsumes[spellID] then
        return exactConsumes[spellID]
    end
    if ambiguousConsumes[spellID] then
        return "Ambiguous Consumable"
    end
    return nil
end
```

Keep the spell ID in the emitted line so ambiguity remains inspectable.

**Step 3: Make V2 authoritative and V1 fallback-only**

Refactor `LogCastEventV2()` to return whether it emitted a line. Then change `UNIT_CASTEVENT` to:

```lua
local emitted = LogCastEventV2(caster, target, event, spellID, castDuration)
if not emitted then
    LogCastEventV1(caster, target, event, spellID, castDuration)
end
```

This preserves a narrow compatibility path without duplicating successful V2 output.

**Step 4: Initialize `specials` from `specials_data`**

On area-level zone updates, set `specials` to the current zone-specific table or `nil` if none exists.

**Step 5: Run tests**

Run: `lua scripts/test_superwowcombatlogger.lua`

Expected: PASS for ambiguous consume labeling, special-target setup, and one-line-per-cast behavior.

**Step 6: Commit**

```bash
git add SuperWowCombatLogger.lua scripts/test_superwowcombatlogger.lua
git commit -m "fix: remove false consume precision and duplicate cast lines"
```

### Task 6: Document supported behavior and verify everything

**Files:**
- Modify: `README.md`
- Test: `scripts/test_captainslog.lua`
- Test: `scripts/test_superwowcombatlogger.lua`

**Step 1: Update README**

Document:

- the three accepted non-fixes
- that ambiguous consume IDs now emit truthful generic labels instead of guessed item names
- that encounter wipe markers come from resolved combat end, not BigWigs reboot
- that standalone `SuperWowCombatLogger` alongside the bundled copy is unsupported if pinned/tested behavior matters

**Step 2: Run both regression suites**

Run: `lua scripts/test_captainslog.lua`

Expected: PASS

Run: `lua scripts/test_superwowcombatlogger.lua`

Expected: PASS

**Step 3: Spot-check for duplicate cast output**

Run:

```bash
rg -n "LogCastEventV1|LogCastEventV2|UNIT_CASTEVENT|Ambiguous Consumable|BigWigs_RebootModule|RAID_LEADER" CaptainsLog.lua SuperWowCombatLogger.lua README.md
```

Expected:

- one authoritative `UNIT_CASTEVENT` emission path
- no wipe logging tied directly to `BigWigs_RebootModule`
- README language aligned with implemented behavior

**Step 4: Commit**

```bash
git add README.md CaptainsLog.lua SuperWowCombatLogger.lua scripts/test_captainslog.lua scripts/test_superwowcombatlogger.lua
git commit -m "docs: align logging accuracy behavior and coverage"
```

## Handoff Notes

- Do not "fix" the intentional session-level wipe heuristic.
- Do not add party-only combat counting behavior unless requirements change.
- Do not block BigWigs idle auto-starts in unknown zones as part of this plan.
- If compatibility requirements outside this repo depend on legacy V1 cast lines always being present, stop and re-evaluate before Task 5; the default plan assumes accuracy wins and no in-repo parser requires duplicated output.
