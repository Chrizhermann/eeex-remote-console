# EEex Remote Console

A lightweight bridge that lets external tools execute Lua commands inside a running BG:EE/BG2:EE game with [EEex](https://github.com/Bubb13/EEex), and read structured JSON results back.

File-based IPC — no sockets, no FFI, no external dependencies.

## Use Cases

- **AI-assisted modding** — Let Claude Code or other coding agents inspect and manipulate live game state
- **Automated testing** — Run test suites against a live game from CI scripts or the command line
- **Live debugging** — Query sprites, spells, effects, and variables without alt-tabbing to the console
- **Scripted diagnostics** — Send multi-line Lua scripts to diagnose mod conflicts or state issues

## Requirements

- BG:EE, BG2:EE, or EET
- [EEex](https://github.com/Bubb13/EEex) installed

## Installation

1. Copy the `eeexremote` folder and `setup-eeexremote.tp2` into your game directory
2. Run `setup-eeexremote.exe` (or use WeiDU directly)
3. Restart the game and load a save

## How It Works

```
External Tool                           BG:EE Game Process
─────────────                           ──────────────────
                                        EEex Lua Runtime
Write eeex_remote_cmd.lua ────────────> Poll() detects file
                                        loadstring() + pcall()
Read eeex_remote_result.json <────────── Write JSON result + delete cmd
```

An invisible 1x1 menu element calls `EEexRemote.Poll()` every render frame. When it finds a command file, it reads the Lua code, deletes the file, executes via `loadstring()` + `pcall()`, captures any `print()` output, and writes a JSON result file. The external tool polls for the result, reads it, and deletes it.

## Usage

### Bash CLI

```bash
# Simple expression
tools/eeex-remote.sh <game-dir>/override 'print("hello")'

# Inspect game state
tools/eeex-remote.sh <game-dir>/override 'print(EEex_Sprite_GetInPortrait(0):getName())'

# Send a multi-line script file
tools/eeex-remote.sh <game-dir>/override @scripts/diagnostic.lua

# Custom timeout (5 seconds)
tools/eeex-remote.sh <game-dir>/override 'return 2+2' 5
```

### From Claude Code

```bash
# Write a command directly
printf '%s' 'print("hello")' > "<game-dir>/override/eeex_remote_cmd.lua"

# Poll for result
cat "<game-dir>/override/eeex_remote_result.json"
# {"status":"ok","output":["hello"]}
```

### From Any Tool (Protocol)

The protocol is two files in the game's override directory:

1. Delete any stale `eeex_remote_result.json`
2. **Write** your Lua code to `eeex_remote_cmd.lua`
3. **Poll** for `eeex_remote_result.json`
4. **Read** the JSON result, then **delete** the result file

### Result JSON Schema

```json
{
    "status": "ok | error | parse_error",
    "error": "message (only on error/parse_error)",
    "returnValue": "tostring of return value (only if non-nil)",
    "output": ["captured print() lines"]
}
```

## Security Warning

This tool executes **arbitrary Lua code** inside the game process. Any code written to the command file will run with full access to the EEex Lua environment — game state, file I/O, everything the game engine can do.

This is **by design** for development and testing. Do not install this mod in a game directory that untrusted users or processes can write to.

## Limitations

- Game must be running and on the **world screen** (polling uses a menu element that only renders when the world screen is active)
- One command at a time (serial: write command, wait for result, then next)
- Text output only (no screenshots or binary data)
- Round-trip latency: ~200ms typical

## Writing Your Own Client

The bash CLI is a reference implementation. The protocol is just file I/O:

| Step | File | Action |
|------|------|--------|
| 1 | `override/eeex_remote_result.json` | Delete (clear stale) |
| 2 | `override/eeex_remote_cmd.lua` | Write Lua code |
| 3 | `override/eeex_remote_result.json` | Poll until exists |
| 4 | `override/eeex_remote_result.json` | Read JSON, then delete |

Any language that can read/write files can be a client. Timeout after ~10 seconds if no result appears.

## License

[MIT](LICENSE)
