# 1701 Captain's Log

`1701-CaptainsLog` is a WoW 1.12.1 (Turtle WoW) guild logging addon that bundles:

- **SuperWowCombatLogger (SWCL)** for enriched combat metadata
- **Captain's Log wrapper logic** for session lifecycle, markers, and raid workflow quality-of-life

It is intended for guild raid logging with consistent data collection and simpler install/operations.

## Attribution

- **SuperWowCombatLogger** by Shino/Pepopo: <https://github.com/Pepopo/SuperWowCombatLogger>
- **SuperWoW** by balakethelock: <https://github.com/balakethelock/SuperWoW>
- **Captain's Log wrapper/session layer** by USS Enterprise Guild

## Why We Package SWCL

We bundle SWCL in this addon on purpose:

1. Single install for raiders (`1701-CaptainsLog` only).
2. Pinned, tested behavior for guild log pipelines.
3. Fewer support issues from mixed addon versions.
4. Wrapper features can integrate directly with SWCL output/flow.

If standalone `SuperWowCombatLogger` is installed, the bundled copy exits early to avoid double-loading.
That mixed setup is not supported if you need the pinned/tested behavior in this repo, because the standalone addon can bypass the packaged fixes documented below.

## What Our Wrapper Adds (Beyond SWCL)

Captain's Log adds session-aware control and metadata around SWCL logging:

- Auto mode starts in configured raid zones.
- Auto mode stops when leaving raid context (out of instance), while avoiding mid-raid stops on intra-instance/subzone transitions.
- Manual mode toggle with `/captainslog`.
- Status command with `/captainslog status`.
- Session/transition markers:
  - `SESSION_START`, `SESSION_END`
  - `SESSION_TRANSITION` with reason metadata
  - `ZONE_TRANSITION`
  - `RAID_LEADER`
  - `COMBAT_END`, `WIPE`
  - `ENCOUNTER_START`, `ENCOUNTER_END: KILL`, `ENCOUNTER_END: WIPE` (via BigWigs engage/death signals plus resolved combat end)
- Time metadata improvements:
  - timezone offset (`%z`) appended when client runtime supports it
  - `server_time=HH:MM` tag on zone enter/exit transitions and encounter start/end markers
- Compatibility hook so Captain's Log can preserve managed session behavior when standalone SWCL handlers run.
- Upload helper scripts for post-raid archive/rotation workflow.

## SWCL Changes In This Packaged Version

This repo keeps SWCL behavior largely intact, but includes practical integration/maintenance updates:

- Packaging/load safety:
  - guard for missing SuperWoW
  - guard to skip bundled SWCL if standalone SWCL is already loaded
- Runtime/hot-path cleanup with no intentional loss of cast detail:
  - reduced redundant global/API lookups in hot paths
  - simplified `OnUpdate` time checks
  - reduced redundant player-info API calls
  - one-pass gear extraction in combatant info collection
- Timestamp metadata updates in SWCL-emitted records (where applicable) to include timezone offset when supported.
- Accuracy fixes for packaged logging:
  - raid roster rescans follow roster identity, not just headcount
  - combatant info retries if the first scan lands before gear data is available
  - `UNIT_DIED` uses cached GUID-to-name resolution when direct lookup is unavailable
  - `ZONE_INFO` normalizes known raid aliases while preserving display casing in fallback output
  - tracked consume spell IDs with multiple valid items now emit an ambiguity-safe generic label instead of a guessed item name
  - cast logging uses one authoritative emission path, with the legacy fallback only when the richer path cannot emit

Notes:

- Upstream SWCL logic findings are documented in `docs/superwow-findings/`.
- `legacy/` contains original/legacy tooling retained for compatibility workflows.

## Intentional Non-Fixes

The following behaviors are still intentional in this packaged build:

- Party-only `PLAYERS_IN_COMBAT` accuracy outside raids is not a target; this addon is operated for raid logging.
- Idle BigWigs boss engages can still auto-start a session in the player's current zone; we prefer capturing unknown encounters over dropping those edge-case pulls.
- The session-level wipe heuristic still treats near-total deaths as wipes even if a few players survive via effects like Feign Death, Divine Intervention, or Vanish.

## Requirements

- Turtle WoW (WoW client 1.12.1)
- [SuperWoW](https://github.com/balakethelock/SuperWoW) client patch
- [BigWigs](https://github.com/pepopo978/BigWigs) (optional, for encounter tracking markers)

## Install

1. Copy this folder to:
   `Interface/AddOns/1701-CaptainsLog/`
2. Start game and ensure **1701 Addons - Captains Log** is enabled.

If present, remove old addons:

- `AdvancedVanillaCombatLog`
- `AdvancedVanillaCombatLog_Helper`

## Load Order

`1701-CaptainsLog.toc` loads:

1. `RPLLCollector.lua`
2. `SuperWowCombatLogger.lua`
3. `CaptainsLog.lua`

## Behavior In Game

### Automatic mode

- Enter configured raid zone: logging starts.
- Leave raid context (outside instance): logging stops.
- Intra-instance zone/subzone switches do not force auto stop.

Configured raid zones:

- Molten Core
- Blackwing Lair
- Onyxia's Lair
- Temple of Ahn'Qiraj
- Ruins of Ahn'Qiraj
- Zul'Gurub
- Naxxramas
- Emerald Sanctum
- Lower Karazhan Halls
- Tower of Karazhan

### Manual mode

- `/captainslog` toggles mode/logging.
- `/captainslog status` prints mode, zone, and logging state.

## Upload Workflow

Use scripts in `scripts/` after raid:

- `upload.bat` (recommended launcher on Windows)
- `upload.ps1` (core implementation)

The upload flow:

1. Locates Turtle WoW path.
2. Reads `Logs/WoWCombatLog.txt`.
3. Creates `Logs/uploads/CaptainsLog-YYYY-MM-DD-HHmm.zip`.
4. Rotates original log to `WoWCombatLog-YYYY-MM-DD-HHmm.bak`.
5. Opens Explorer with the zip selected.

## Troubleshooting

- **"SuperWoW required" message**:
  SuperWoW is missing or inactive.
- **No combat log file**:
  start logging (`/captainslog`) and verify `Logs/WoWCombatLog.txt` exists.
- **Upload path prompts unexpectedly**:
  verify addon path is under `.../TurtleWoW/Interface/AddOns/1701-CaptainsLog/`.
