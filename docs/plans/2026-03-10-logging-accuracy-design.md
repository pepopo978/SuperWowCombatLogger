# Logging Accuracy Fixes Design

**Status:** Draft spec for implementation

**Goal:** Improve the accuracy of emitted session, encounter, cast, consume, combatant, zone, trade, and death metadata without changing the three behaviors explicitly accepted as-is.

## Accepted Non-Fixes

The following findings are intentionally out of scope for this work:

- Party-only `PLAYERS_IN_COMBAT` accuracy outside raids. The addon is operated for raid logging.
- BigWigs idle auto-start in unusual zones. We prefer catching unexpected encounters over dropping them.
- The existing session-level wipe heuristic (`alive <= 3` or `< 10%`) remains intentional to catch FD/DI/Vanished edge cases.

These behaviors should be documented clearly so future audits do not reopen them by accident.

## In Scope

- Prevent auto sessions from drifting into unrelated areas or instances.
- Ensure `COMBAT_END` and encounter wipe markers are eventually emitted once raid combat really ends.
- Remove false `ENCOUNTER_END: WIPE` markers caused by BigWigs module reboot behavior.
- Prevent alias-only zone name differences from creating fake `ZONE_TRANSITION` records.
- Keep `RAID_LEADER` metadata current enough to avoid stale or missing leader attribution.
- Fix stale or missing `COMBATANT_INFO` caused by throttle timing and roster-scan shortcuts.
- Repair broken helper logic (`strsplit`) that can corrupt fuzzy matching.
- Improve `ZONE_INFO`, `UNIT_DIED`, and `LOOT_TRADE` attribution so the addon prefers accurate or explicit-unknown output over misleading output.
- Remove duplicate cast/consume lines for a single `UNIT_CASTEVENT`.
- Replace knowingly wrong consumable labels with ambiguity-safe output.
- Re-enable zone-specific special-target enrichment so it works when the data says it should.
- Clarify supported load-state behavior when standalone `SuperWowCombatLogger` is installed.

## Design Principles

- Prefer omission or explicit ambiguity over a confidently wrong label.
- Preserve current log line prefixes where practical.
- Keep manual mode behavior unchanged unless required for correctness.
- Keep raid-to-raid auto sessions continuous unless the user explicitly stops them.
- Add regression coverage before changing behavior.

## Recommended Design

### 1. Session lifecycle must separate display-zone updates from start/stop decisions

Current wrapper logic evaluates lifecycle on every zone-related event, then only stops auto sessions when the player is both outside a tracked raid zone and outside any instance. That preserves intra-instance movement, but it also allows sessions to drift into unrelated instances and can manufacture fake zone transitions when canonical and raw zone names differ.

Recommended changes:

- Track two zone values in the wrapper:
  - `sessionCanonicalZone`: the canonical raid label used for session identity.
  - `sessionObservedZone`: the raw zone text last seen from the client.
- Evaluate auto start/stop only on area-level events:
  - `ZONE_CHANGED_NEW_AREA`
  - `PLAYER_ENTERING_WORLD`
  - `UPDATE_INSTANCE_INFO` via the SWCL compatibility hook
- Continue to emit `ZONE_TRANSITION` on finer-grained zone events, but only when the normalized canonical identity actually changes or when the raw observed zone truly changes within the same session.
- Preserve the current "single auto session across tracked raid-zone changes" behavior.
- Stop auto sessions on area-level transitions into an untracked zone, even if `IsInInstance()` is still true.
- Ignore empty/unknown zone text during loading screens until a stable zone is available.

This is the safest way to fix the unrelated-instance carryover without reintroducing the original mid-raid stop problem.

### 2. Combat-end and encounter-end markers must resolve asynchronously

Current `COMBAT_END` logic only runs once, when the player leaves combat. If any other raid member is still in combat at that instant, the marker is skipped forever. Separately, `ENCOUNTER_END: WIPE` is emitted off `BigWigs_RebootModule`, which is not wipe-specific.

Recommended changes:

- Introduce a wrapper-side `pendingCombatResolution` state when the player gets `PLAYER_REGEN_ENABLED` during an active session.
- Re-check raid combat status on a short timer until the whole raid is out of combat or a new combat start occurs.
- Emit `COMBAT_END` exactly once when raid combat actually resolves.
- Preserve the current session-level wipe heuristic and use it at the resolved combat end, not at the first player regen event.
- Move `ENCOUNTER_END: WIPE` emission to the resolved combat-end path:
  - If `engagedBoss` is still set when combat fully resolves and no `BossDeath` was observed, emit `ENCOUNTER_END: WIPE <boss>`.
- Keep `BigWigs_RebootModule` only as state cleanup or safety fallback, not as the primary wipe signal.

This fixes both missing markers and false wipe markers with one control path.

### 3. Leader and roster metadata must refresh on actual roster changes

Current wrapper leader metadata is a one-time snapshot. Current SWCL roster scanning exits early when raid size is unchanged, so same-count swaps can miss new players entirely.

Recommended changes:

- In `CaptainsLog.lua`, track the last emitted raid leader and listen for `RAID_ROSTER_UPDATE` while a session is active.
- Emit a fresh `RAID_LEADER` marker only when the detected leader actually changes or when the first valid leader becomes available after session start.
- In `SuperWowCombatLogger.lua`, replace the `rcount` short-circuit with a roster signature:
  - Build a cheap snapshot from raid unit names or GUIDs.
  - Re-scan when the snapshot changes, even if member count is identical.

This avoids stale leader attribution and missing `COMBATANT_INFO` for replacements.

### 4. Combatant info must throttle only successful snapshots

Current player-info throttling is keyed by character name and is updated before the code knows whether it can produce a usable `COMBATANT_INFO` line. If all gear slots are temporarily nil, the addon suppresses retries for 30 seconds.

Recommended changes:

- Treat "all gear missing" as an incomplete scan, not a completed one.
- Update the per-character throttle only after `log_combatant_info()` actually emits or confirms a stable duplicate snapshot.
- Preserve content-based deduplication via `RPLL.LoggedCombatantInfo`.
- Keep the 30-second throttle for successful scans to avoid hot-path spam.
- Seed and maintain a GUID-to-name cache during successful unit scans so later events can resolve names more reliably.

### 5. Consume logging must become ambiguity-safe

The current consume table knowingly picks one item name for spell IDs shared by many different consumables. That produces wrong item names by design.

Recommended changes:

- Split consume IDs into two groups:
  - `exactConsumes`: spell IDs with one safe item label.
  - `ambiguousConsumes`: spell IDs with multiple possible items.
- Stop using "pick one alternative" overrides for ambiguous IDs.
- For ambiguous IDs, emit a generic but truthful label that retains the spell ID, for example:
  - `Ambiguous Consumable(24800)`
  - or `Food/Drink Consumable(430)` if a small curated category is worth the maintenance cost.
- Keep exact labels only where the mapping is actually one-to-one.
- Document that the packaged addon now favors truthful ambiguity over false precision.

This is a deliberate accuracy trade: less specificity, but no fabricated item names.

### 6. Cast logging must produce one authoritative line per cast event

`UNIT_CASTEVENT` currently emits both the legacy tracked-event line and the newer `CAST:` line for the same event, which creates downstream double-counting risk.

Recommended changes:

- Make V2 the authoritative cast logger.
- Allow V1 output only as a narrow fallback when V2 cannot resolve a spell name and the old tracked table still has a safe exact label.
- If V1 fallback is retained, it must never run when V2 already emitted a line.
- Add explicit regression coverage to guarantee one emitted cast line per `UNIT_CASTEVENT`.

No in-repo consumer depends on both formats being present, so accuracy should win over redundant compatibility.

### 7. Zone-specific special-target enrichment must actually initialize

`specials_data` is present, but `specials` is never assigned. The feature is effectively disabled.

Recommended changes:

- Initialize `specials` on area-level zone changes using the current real zone text and any canonical raid alias mapping needed by SWCL.
- Clear or replace `specials` whenever the active zone changes.
- Keep the target enrichment limited to the existing curated spell list.

### 8. Helper and formatting fixes must prefer stable, parseable output

Recommended changes:

- Fix `strsplit()` so `DeepSubString()` receives the correct tail token.
- Broaden trade detection from `^%w+ trades item` to a plain-text contains-style check that still targets English client output but does not reject accented names.
- Preserve original zone casing in `ZONE_INFO` fallback output instead of forcing lowercase.
- Normalize zone text before comparing against saved-instance names so alias punctuation and whitespace differences do not silently force `instance_id=0`.
- Use the GUID-to-name cache in `UNIT_DIED` before falling back to `Unknown`.

## Alternatives Considered

### Auto-session stop behavior

Option A: Keep the current `not raidZone and not inInstance` rule.

- Rejected because it is the direct cause of unrelated-instance session drift.

Option B: Stop on any untracked zone event, including `ZONE_CHANGED` and `ZONE_CHANGED_INDOORS`.

- Rejected because it risks reintroducing the original intra-instance/subzone stop bug.

Option C: Stop only on area-level transitions into untracked zones.

- Recommended because it fixes the bad carryover while preserving subzone movement.

### Encounter wipe detection

Option A: Keep `BigWigs_RebootModule` as the wipe trigger.

- Rejected because it is not wipe-specific.

Option B: Emit wipe only from resolved combat end when `engagedBoss` is still active.

- Recommended because it ties encounter-end state to actual combat resolution.

Option C: Combine reboot and combat-end signals with debounce logic.

- Rejected for now as more stateful than needed.

### Ambiguous consume handling

Option A: Keep the existing "pick a representative item" approach.

- Rejected because it knowingly lies.

Option B: Drop ambiguous consume logging entirely.

- Rejected because it throws away useful visibility.

Option C: Emit generic ambiguity-safe labels with the shared spell ID.

- Recommended because it preserves observability without false precision.

## Test Strategy

Add regression coverage in two Lua harnesses:

- Extend `scripts/test_captainslog.lua` for wrapper/session behavior:
  - auto-stop on area-level transitions into untracked zones
  - no auto-stop on plain subzone updates
  - delayed `COMBAT_END` emission after late raid combat resolution
  - `ENCOUNTER_END: WIPE` from resolved combat end, not reboot
  - alias-safe `ZONE_TRANSITION`
  - leader refresh when leadership changes mid-session
- Add `scripts/test_superwowcombatlogger.lua` for SWCL behavior:
  - same-count roster swap triggers new combatant scans
  - all-nil gear scan retries promptly
  - V2-only cast emission by default
  - ambiguous consume labeling
  - `specials` initialization by zone
  - `ZONE_INFO` normalization and casing
  - broader trade detection
  - GUID cache usage for `UNIT_DIED`
  - `strsplit` tail correctness

## Documentation Updates

- Update `README.md` to document:
  - accepted non-fixes
  - ambiguity-safe consume output
  - the supported/unsupported state when standalone `SuperWowCombatLogger` is also installed
  - the new encounter wipe behavior source
- Keep `docs/superwow-findings/` as historical notes; do not duplicate the implementation plan there.
