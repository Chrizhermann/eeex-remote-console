# EEex Remote Console

A lightweight bridge that lets external tools execute Lua commands inside a running BG:EE/BG2:EE game with [EEex](https://github.com/Bubb13/EEex), and read structured JSON results back.

File-based IPC — no sockets, no FFI, no external dependencies.

## Use Cases

- **AI-assisted modding** — Let Claude Code or other coding agents inspect and manipulate live game state
- **Automated testing** — Run test suites against a live game from CI scripts or the command line
- **Live debugging** — Query sprites, spells, effects, and variables without alt-tabbing to the console
- **Scripted diagnostics** — Send multi-line Lua scripts to diagnose mod conflicts or state issues

## Requirements

- A supported Infinity Engine EE game (see matrix below)
- [EEex](https://github.com/Bubb13/EEex) 0.10.x through 1.3.x with the **LuaJIT component**, which provides the Lua `io`/`os` libraries this mod depends on
  - EEex v1.2.x and v1.3.x: install **component 1 (Main)** and **component 8 (LuaJIT)**
  - EEex v1.0.0: choose the **Experimental** quick-menu tier
  - EEex v0.10.x / v0.11.x: install the **"Experimental - Use LuaJIT"** component
- Install EEex Remote Console **after EEex** so those runtime capabilities are already present

EEex Remote Console checks the resulting capabilities rather than hardcoding
component numbers, so compatible older EEex installs keep working.

### Compatibility Matrix

| EEex version | Status | Verification |
|--------------|--------|--------------|
| 0.9.x | **Not supported** | No LuaJIT component exists for that line; the installer refuses to install |
| 0.10.x | Supported | Not separately verified |
| 0.11.x | Supported | **Runtime-tested**: v0.11.0-alpha on BG2:EE, full 22-case in-game suite passed |
| 1.0.x | Supported | **Source-verified only**: every EEex API this mod calls was confirmed present in the v1.0.0 source, but no game has been run on v1.0.0 yet |
| 1.2.x | Supported | **Runtime-tested**: v1.2.0 with LuaJIT on BG2:EE 2.6.6.0 (full 22-case in-game suite passed) and on EET over BG2:EE 2.7.3.0 (ready handshake and a fresh `pong`) |
| 1.3.x | Supported | **Runtime-tested**: v1.3.1 with LuaJIT on EET over BG2:EE 2.7.3.0 (ready handshake, fresh `pong`, and the full 22-case suite with the watchdog on the main menu) |

| Game | Status |
|------|--------|
| BG:EE (incl. SoD) | Supported |
| BG2:EE | Supported — this is where the full in-game suite ran |
| EET | Supported — runtime-tested on 2.7.3.0 |
| IWD:EE | Installer allows it; untested |

Game versions: runtime-tested on 2.7.3.0, the current patch, and on 2.6.6.0. Which game builds run at all depends on your EEex version.

WeiDU note: the installer's `bgee` check in `GAME_IS` also matches BG:EE+SoD installs — WeiDU has no separate `sod` keyword there (SoD detection exists only in `GAME_INCLUDES`).

## Installation

1. Install EEex v1.2.0 or later with components **1 (Main)** and **8 (LuaJIT)**
2. Copy the `eeexremote` folder and `setup-eeexremote.tp2` into your game directory
3. Run `setup-eeexremote.exe` (or use WeiDU directly) **after EEex**
4. Restart the game — the console is live from the main menu onward

The installer verifies its prerequisites in a version-independent way:

- **EEex present** — detected via `override/M___EEex.lua`, EEex's engine bootstrap file across the supported compatibility range, including v1.2.x and v1.3.x.
- **LuaJIT enabled** — detected by reading `InfinityLoader.ini` for `LuaPatchMode=REPLACE_INTERNAL_WITH_EXTERNAL` (the line the EEex LuaJIT component sets). If absent, installation fails with per-version instructions for enabling it.

These checks are intentionally capability-based: component numbers describe how
to produce a supported install, but the installer tests the files and loader
mode the running game actually receives.

## Live Verification Status

Live evidence so far:

- **BG2:EE 2.6.6.0 with EEex v1.2.0**: the ready handshake and `pong` probe
  succeeded, and `tools/smoke-test.ps1 -IncludeWatchdog` finished with **22-case
  coverage (22 passed, 0 failed)**, including post-watchdog game liveness.
- **EET over BG2:EE 2.7.3.0 with EEex v1.2.0**: ready handshake and a fresh `pong`.
- **EET over BG2:EE 2.7.3.0 with EEex v1.3.1** (2026-10-18, disposable lab): the
  ready handshake (`protocol="1.1"`, `luajit=true`, `disabled=false`, both
  screens), a fresh `pong` with the expected Info object, and
  `tools/smoke-test.ps1 -IncludeWatchdog` with **22 passed, 0 failed** on the main
  menu, including post-watchdog game liveness. The same lab (EET v14.0) then passed
  the world-screen steps 4–6 below twice: with the v0.2.0 loader from `master`
  (this branch changes only its comments and disabled-reason texts), and with this
  branch's loader plus the `START_SP` fix from [#4](https://github.com/Chrizhermann/eeex-remote-console/pull/4). Both times `ping.lua` answered
  `pong` on the world screen, the suite passed there with **22 passed, 0 failed**,
  and the next `pong` came from the same game and loader processes.

**The full checklist below has passed on EET over BG2:EE 2.7.3.0 with EEex v1.3.1.**
The world-screen runs found one menu-stack bug: when `START` reopened in
single-player state, the console menu covered `START_SP`, and `START_SP` then
stayed on the stack under the game's screens ([#4](https://github.com/Chrizhermann/eeex-remote-console/pull/4) fixes it). Run the checklist on a
disposable test install for each new EEex or game release:

1. With the game and `InfinityLoader.exe` closed, install EEex v1.2.0 or later
   with component 1 (Main) and component 8 (LuaJIT), then install EEex Remote
   Console after EEex. Confirm `override/M___EEex.lua` exists and `InfinityLoader.ini` has the
   active line `LuaPatchMode=REPLACE_INTERNAL_WITH_EXTERNAL`. Use one client at
   a time and clear stale `eeex_remote_cmd.lua`, `eeex_remote_cmd.lua.run`,
   `eeex_remote_result.json`, `eeex_remote_result.json.tmp`, and
   `eeex_remote_ready.json` before launch.
2. Launch once through `InfinityLoader.exe`, record the `Baldur.exe` and loader
   PIDs/start times, and stop at the main menu. The newly written
   `override/eeex_remote_ready.json` handshake must have a fresh timestamp and
   report `protocol="1.1"`,
   `luajit=true`, `disabled=false`, and screens containing both
   `WORLD_ACTIONBAR` and `START`. The ready file is diagnostics, not liveness.
3. At the **main menu**, run
   `.\tools\eeex-remote.ps1 <override> '@tools/scripts/ping.lua'`. Require
   client exit 0, `status="ok"`, protocol `1.1`, and the first return value
   `pong`. The returned Info object must report `luajit=true`, `io=true`,
   `eeexActive=true`, both screen names, and no disabled reason. This proves
   `START` polling.
4. Load an EET save to the **world screen** and repeat the same `ping.lua`
   command. Require a fresh `pong`; this proves `WORLD_ACTIONBAR` polling.
5. From the world screen, run
   `.\tools\smoke-test.ps1 -OverrideDir <override> -IncludeWatchdog`. Require
   client exit 0 and `Result: 22 passed, 0 failed`, including `PASS ready file
   valid`, `PASS watchdog aborts runaway`, and `PASS game alive after watchdog`.
   The runaway loop must end with a watchdog error, and the following `return
   42` probe must prove the game is still alive.
6. Without restarting, run `ping.lua` once more. Require another healthy `pong`
   from the same PIDs/start times; this independently proves post-watchdog
   liveness. Record exact game/EET/EEex/mod versions, ready JSON, both host-screen
   ping results, the full 22/22 transcript, exit codes, and process identity.

## How It Works

```
External Tool                            BG:EE Game Process
─────────────                            ──────────────────
write temp file, rename to               EEexRemote.Poll() every render frame:
eeex_remote_cmd.lua        ────────────> claims the file (atomic rename),
                                         compiles it as ONE chunk, runs it
                                         under xpcall + watchdog, captures print()
poll for
eeex_remote_result.json    <──────────── writes temp file, renames to
read it, then delete it                  eeex_remote_result.json
```

An invisible 1x1 menu element calls `EEexRemote.Poll()` every render frame. The element is pushed on top of both the **world screen** (`WORLD_ACTIONBAR`) and the **main menu** (`START`), so commands work in-game and from the title screen. Polling is render-driven, independent of simulation pause — it keeps working while the game is **paused**.

Both sides use atomic renames: the game claims the command file by renaming it before reading (no partial reads, no double execution) and publishes the result via a temp file + rename (clients never observe a half-written result).

On load — and after every F5 UI reload — the module writes `override/eeex_remote_ready.json`, a diagnostic handshake file (see [Protocol v1.1](#protocol-v11)).

## Usage

Two reference clients ship in `tools/`. Both write commands atomically, tag them with request ids so stale results are rejected, and share the same exit codes:

| Exit code | Meaning |
|-----------|---------|
| 0 | Success (`status` is `ok`) |
| 1 | Lua runtime error or parse error |
| 2 | Timeout — no response from the game |
| 3 | Usage error (bad arguments) |

### Bash — `tools/eeex-remote.sh`

```bash
OVERRIDE="/path/to/Baldur's Gate II Enhanced Edition/override"

# Inline expression
tools/eeex-remote.sh "$OVERRIDE" 'return 2 + 2'

# Inspect game state
tools/eeex-remote.sh "$OVERRIDE" 'print(EEex_Sprite_GetInPortrait(0):getName())'

# Send a script file (executes as one chunk — locals shared across lines)
tools/eeex-remote.sh "$OVERRIDE" @tools/scripts/party.lua

# Read the script from stdin
tools/eeex-remote.sh "$OVERRIDE" - <<'LUA'
local total = 0
for i = 1, 10 do total = total + i end
return total
LUA

# List live API globals matching a Lua pattern
tools/eeex-remote.sh "$OVERRIDE" --api '^EEex_Sprite_'

# Custom timeout (seconds)
tools/eeex-remote.sh "$OVERRIDE" 'return 2 + 2' 5
```

### PowerShell — `tools/eeex-remote.ps1`

Works in Windows PowerShell 5.1 and pwsh 7+.

```powershell
$override = "C:\Games\Baldur's Gate II Enhanced Edition\override"

# Inline expression
.\tools\eeex-remote.ps1 $override 'return 2 + 2'

# Send a script file — quote @paths, bare @ is PowerShell splatting syntax
.\tools\eeex-remote.ps1 $override '@tools/scripts/party.lua'

# List live API globals: -Api is canonical (works in-shell AND via pwsh -File);
# pass the timeout as -TimeoutSec when using it
.\tools\eeex-remote.ps1 $override -Api '^EEex_Sprite_' -TimeoutSec 10

# Positional --api works in-shell only (pwsh -File binds leading-dash
# arguments as parameter names)
.\tools\eeex-remote.ps1 $override --api '^EEex_Sprite_'

# Stdin ('-') is for piped cross-shell / pwsh -File use — in-session
# PowerShell pipelines do not feed [Console]::In
'return 2 + 2' | pwsh -File tools\eeex-remote.ps1 $override -

# Custom timeout (seconds)
.\tools\eeex-remote.ps1 $override 'return 2 + 2' 5
```

Note: `--api` / `-Api` patterns must not contain double quotes (they are interpolated into a Lua string literal).

## Protocol v1.1

The wire protocol is two files in the game's override directory. **v1.1 is additive** — clients written against the v0.1.0 protocol keep working unchanged.

1. Delete any stale `eeex_remote_result.json`
2. **Write** your Lua to `eeex_remote_cmd.lua` — atomically, see [Writing Your Own Client](#writing-your-own-client)
3. **Poll** for `eeex_remote_result.json`
4. **Read** the JSON result, then **delete** the result file

### Command Directives

A command file is raw Lua, optionally prefixed with directive comment lines. Directives must be the very first lines of the file, one per line, before any code. They are ordinary Lua comments, so they never affect execution (a v0.1.0-era server would simply ignore them).

```lua
--@id=req-42
--@watchdog=500000000
return 2 + 2
```

| Directive | Effect |
|-----------|--------|
| `--@id=<token>` | Token is echoed back as `id` in the result — lets clients reject stale results |
| `--@watchdog=<N>` | Sets the runaway-script guard to N Lua instructions (default `200000000`, roughly 1–2 s of a runaway loop) |
| `--@nowatchdog` | Disables the guard for legitimately long scripts |

A tripped watchdog produces a normal `status: "error"` result with the message `watchdog: exceeded <N> Lua instructions (use --@nowatchdog for long scripts)`.

### Result Schema

```json
{
    "protocol": "1.1",
    "status": "ok | error | parse_error",
    "id": "echo of --@id (only if the command sent one)",
    "error": "message (only on error / parse_error)",
    "traceback": "Lua stack traceback (only on runtime error)",
    "durationMs": 3,
    "returnValue": "tostring of the first return value (legacy; only if non-nil)",
    "returnValues": ["every return value, as structured JSON (only on ok)"],
    "output": ["captured print() lines"]
}
```

- `protocol`, `status`, `durationMs`, and `output` are always present.
- `returnValues` serializes Lua tables as real JSON structures — cycle-safe, depth-limited to 6 levels, capped at 256 KB per value. Cyclic, too-deep, or oversized parts are replaced with placeholder strings (`"<cycle>"`, `"<max depth>"`, `"<value too large: N bytes>"`).
- `returnValue` is the legacy v0.1.0 field — the `tostring()` of the first return value — kept so old clients continue to work.
- Parse errors and tracebacks reference the chunk as `eeex_remote_cmd.lua:<line>`.

### Ready File

On load — and after every F5 UI reload — the module writes `override/eeex_remote_ready.json`:

```json
{"protocol":"1.1","luajit":true,"screens":["WORLD_ACTIONBAR","START"],"disabled":false,"timestamp":"2026-07-11T12:00:00Z"}
```

`disabled` is `false` on a healthy install. The file is **diagnostics only**: the game never deletes it, so it goes stale once the game quits. To check liveness, send a ping instead (`tools/scripts/ping.lua`).

## Whole Scripts

A command file executes as **one Lua chunk**:

- **Locals are shared across all lines** of the file — unlike the in-game EEex console, which compiles each entered line as its own chunk (locals vanish between lines).
- **Globals persist across successive commands** — stash intermediate state in a global and come back for it later.

```lua
-- command 1
local sprite = EEex_Sprite_GetInPortrait(0)  -- local: visible on every line below
lastSprite = sprite                          -- global: persists for later commands
return sprite:getName()
```

```lua
-- command 2, sent any time later
return lastSprite:getName()
```

Send whole files with `@path/to/script.lua` or pipe them via stdin (`-`) — see [Usage](#usage).

## Discovering the API

Static EEex documentation may not match the version you actually have installed. The console can introspect the **live** Lua environment instead — ground truth for your install:

```lua
-- every global matching a Lua pattern, with its type and,
-- for Lua functions, the defining source:line
return EEexRemote.ListGlobals("^EEex_Sprite_")

-- capability report: protocol, luajit, io, screens, disabled, eeexActive
return EEexRemote.Info()
```

The CLI shortcuts `--api '<pattern>'` (bash) and `-Api '<pattern>'` (PowerShell) wrap `ListGlobals`.

Canned scripts in `tools/scripts/`:

| Script | Purpose |
|--------|---------|
| `ping.lua` | Liveness check + capability report |
| `list-api.lua` | Overview of the installed EEex API surface, grouped by prefix |
| `party.lua` | Names of the active party in portrait order |

For concepts and reference documentation, see the official EEex docs: https://eeex-docs.readthedocs.io/

## Security Warning

This tool executes **arbitrary Lua code** inside the game process. Any code written to the command file will run with full access to the EEex Lua environment — game state, file I/O, everything the game engine can do.

This is **by design** for development and testing. Do not install this mod in a game directory that untrusted users or processes can write to.

## Known Limitations

- **Forced dialogues suspend polling.** During a forced dialogue the world UI is torn down and stops rendering, so the poll can't tick; commands sent mid-dialogue wait (or time out) and the console recovers automatically when the dialogue ends. The game is modal for the player during dialogue anyway. Pausing is fine — polling is render-driven and continues while the game is paused.
- **Result size.** Only individual return values are capped (256 KB each); aggregate result size and `print()` output volume are unbounded, and serialization happens on the render thread — don't return or print megabyte-scale data.
- One command at a time (serial: write command, wait for result, then next)
- Text output only (no screenshots or binary data)
- Round-trip latency: ~200ms typical

## Troubleshooting

**Game won't launch after the 2.7 update (EEex v1.0.0).** Patch 2.7 — Steam also shipped it as a silently refreshed "2.6" beta — breaks EEex v1.0.0 itself, not this mod. Update EEex to v1.2.0 or later, which runs on 2.7.3.0. If the loader still fails, delete the `[Auto-Generated]` section from `InfinityLoader.ini`. Players who want to stay on 2.6.6.0 need a true 2.6.6.0 build; the refreshed "2.6" beta is not one.

**Commands time out.** Check that the game is running and on the world screen or main menu (not in a dialogue), and that the mod is actually installed (`weidu.log`).

**One-time in-game notice "EEex Remote Console disabled…".** The EEex LuaJIT component is missing, so the Lua `io`/`os` libraries don't exist; the module self-disables with a single notice instead of erroring every frame. For EEex v1.2.0 or later, install component 1 (Main) and component 8 (LuaJIT), then reinstall EEex Remote Console after EEex. A healthy install writes `eeex_remote_ready.json` with `"disabled":false` when the UI loads.

**Generalized Biffing.** Don't let it biff `M_EEexRC.lua` or `EEexRC.menu` — a biffed copy breaks polling. The same hazard applies to EEex's own override files.

## Writing Your Own Client

The bash and PowerShell CLIs are reference implementations. The protocol is just file I/O:

| Step | File | Action |
|------|------|--------|
| 1 | `override/eeex_remote_result.json` | Delete (clear stale) |
| 2 | temp file in `override/` | Write `--@id=<unique>` + your Lua |
| 3 | `override/eeex_remote_cmd.lua` | **Rename** the temp file onto this name |
| 4 | `override/eeex_remote_result.json` | Poll until it exists |
| 5 | `override/eeex_remote_result.json` | Read the JSON; if it has an `id` that isn't yours, delete it and keep polling (stale); otherwise delete it and you're done |

Rules of the road:

- **Write atomically.** Write to a temp file **in the same directory**, then rename it onto `eeex_remote_cmd.lua`. A client that writes the command file directly can be read mid-write. (Renames are only atomic within the same directory/volume.)
- **Send an id** (`--@id=<unique-token>`) and reject results carrying a different one — otherwise a stale result from a previous run can be mistaken for yours.
- Timeout after ~10 seconds if no result appears.
- If your client is a command-line tool, match the reference exit codes: 0 ok / 1 Lua or parse error / 2 timeout / 3 usage.

Any language that can read, write, and rename files can be a client.

## License

[MIT](LICENSE)
