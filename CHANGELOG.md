# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- The single-player start menu (`START_SP`) could stay on the menu stack for the rest of the session and be drawn under the game's own screens. When `START` reopened in single-player state (back from character creation, the load screen or the options), its own `onOpen` replaced it with `START_SP`, and the console menu was then pushed on top. `START_SP`'s buttons close it with a no-argument `Infinity_PopMenu()`, so New Game, Load Game and the other buttons popped the console menu instead. The console menu now opens before the host's `onOpen` and never covers a menu that `onOpen` opened; after such a redirect the console waits for the next host screen. The first-boot behavior is unchanged: when EET's campaign set-up closes `START` without opening another menu, the console stays available until `START` reopens on the first mouse event.
- The smoke suite's ready-file timestamp check failed under PowerShell 7, whose `ConvertFrom-Json` turns ISO 8601 strings into `[datetime]` values. It now checks the timestamp on the raw JSON text, so PowerShell 5.1 and 7 agree.

### Changed

- Prerequisite and failure guidance for EEex v1.2.x and v1.3.x: install component 1 (Main) and component 8 (LuaJIT), then install EEex Remote Console after EEex. The installer still verifies capabilities through `override/M___EEex.lua` and the anchored `LuaPatchMode=REPLACE_INTERNAL_WITH_EXTERNAL` loader setting instead of hardcoding component-log entries.
- The smoke suite's `Info()` and ready-file checks also require LuaJIT, `io`, no disabled reason and both host screens (`WORLD_ACTIONBAR` and `START`).
- Live evidence: the first full 22-case smoke run was BG2:EE 2.6.6.0 with EEex v1.2.0. EET over BG2:EE 2.7.3.0 answered the ready handshake and a fresh `pong` with EEex v1.2.0; with EEex v1.3.1 it passed the whole README checklist: the 22-case suite with the watchdog on the main menu and on the world screen, and a fresh `pong` from the same game process afterwards.

## [0.2.0] - 2026-07-11

### Added

- **EEex 0.10.x–1.0.x compatibility** via capability probing (EEex exposes no version global). Verification status: EEex v0.11.0-alpha is runtime-tested on BG2:EE (full 22-case in-game suite passed); EEex v1.0.0 is source-verified only — every EEex API this mod calls was confirmed present in the v1.0.0 source, but no game has been run on v1.0.0 yet. EEex 0.9.x is refused by the installer (no LuaJIT component exists for that line).
- **Main-menu polling** — commands now execute on the main menu (`START`) as well as the world screen, and polling continues while the game is paused (it is render-driven, independent of simulation pause).
- **Protocol 1.1** (additive — v0.1.0 clients keep working unchanged):
  - Command directives: `--@id=<token>` (echoed back for stale-result rejection), `--@watchdog=<N>`, `--@nowatchdog`
  - New result fields: `protocol`, `id`, `traceback` (runtime errors), `durationMs`, and `returnValues` — every return value as structured JSON (tables serialized as real JSON structures; cycle-safe, depth-limited to 6, capped at 256 KB per value). The legacy `returnValue` field is kept.
  - `eeex_remote_ready.json` handshake file written on load and after every F5 UI reload (`protocol`, `luajit`, `screens`, `disabled`, `timestamp`) — diagnostics only, goes stale after the game quits.
- **Watchdog** — runaway scripts abort after a Lua-instruction budget (default `200000000`, roughly 1–2 s) instead of hanging the game; tune with `--@watchdog=<N>` or disable with `--@nowatchdog`.
- **API discoverability** — `EEexRemote.ListGlobals(pattern)` lists live globals with type and, for Lua functions, `source:line` (ground truth for the installed EEex version); `EEexRemote.Info()` returns a capability report; canned scripts `tools/scripts/ping.lua`, `list-api.lua`, `party.lua`; CLI shortcuts `--api '<pattern>'` (bash) and `-Api '<pattern>'` (PowerShell).
- **PowerShell client** `tools/eeex-remote.ps1` — Windows-native, feature parity with the bash client (`@file`, stdin, `--api`/`-Api`, timeouts, exit codes). Works in Windows PowerShell 5.1 and pwsh 7+.
- **Stdin input** (`-`) in both clients, alongside inline Lua and `@file.lua`.
- In-game smoke-test harness `tools/smoke-test.ps1`.
- IWD:EE installs are allowed (untested).

### Changed

- **Exit codes — breaking for scripts that check them.** Both clients now return 0 = ok, 1 = Lua runtime or parse error, 2 = timeout, 3 = usage. The v0.1.0 bash client exited 0 for any delivered result — including Lua errors — 1 on timeout, and 2 on usage; scripts will now see failures they previously missed.
- **Version-independent installer.** EEex is detected by the physical presence of `override/M___EEex.lua` (EEex's bootstrap file in every version — robust against v1.0.0's WeiDU component renumbering), and the LuaJIT requirement is verified against `InfinityLoader.ini` (`LuaPatchMode=REPLACE_INTERNAL_WITH_EXTERNAL`), failing with per-version remedies when absent.
- **Atomic file handling end to end.** Clients write commands via temp file + rename and reject stale results via request ids; the module claims the command file by rename before executing (no partial reads, no double execution) and publishes results via temp file + rename.
- Missing LuaJIT now self-disables the module with a one-time in-game notice instead of producing per-frame errors.

### Fixed

- Runtime errors now include a full Lua stack traceback; parse errors and tracebacks reference the chunk as `eeex_remote_cmd.lua:<line>`.
- The module never leaves `print()` captured or a stale command claim behind after an internal error; stale claims from a crash are cleared at UI load.
- Client polish: temp-file cleanup on exit, timeout argument validation, and override-path resolution.

## [0.1.0] - 2026-03-06

Initial release.

### Added

- File-based IPC bridge: `eeex_remote_cmd.lua` in, `eeex_remote_result.json` out, in the game's override directory.
- World-screen polling via an invisible 1x1 menu element (`EEexRC.menu`) hooked to `WORLD_ACTIONBAR`.
- Bash client `tools/eeex-remote.sh` (inline Lua, `@file.lua`, timeout).
- WeiDU installer `setup-eeexremote.tp2`.
