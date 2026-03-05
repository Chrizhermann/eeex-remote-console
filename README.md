# EEex Remote Console

A lightweight bridge that lets external tools execute Lua commands inside a running BG:EE/BG2:EE game with EEex, and read structured JSON results back. File-based IPC — no sockets, no FFI, no external dependencies.

## Requirements

- BG:EE, BG2:EE, or EET
- [EEex](https://github.com/Bubb13/EEex) installed

## Installation

1. Copy the `eeexremote` folder and `setup-eeexremote.tp2` into your game directory
2. Run `setup-eeexremote.exe` (or use WeiDU directly)

## Usage

### Bash CLI

```bash
# Simple expression
tools/eeex-remote.sh /c/Games/BG2EE/override 'print("hello")'

# Inspect game state
tools/eeex-remote.sh /c/Games/BG2EE/override 'print(EEex_Sprite_GetInPortrait(0):getName())'

# Send a multi-line script file
tools/eeex-remote.sh /c/Games/BG2EE/override @tools/diagnostic.lua

# Custom timeout (5 seconds)
tools/eeex-remote.sh /c/Games/BG2EE/override 'return 2+2' 5
```

### From any tool (protocol)

The protocol is two files in the game's override directory:

1. **Write** your Lua code to `override/eeex_remote_cmd.lua`
2. **Poll** for `override/eeex_remote_result.json`
3. **Read** the JSON result, then **delete** the result file

Result JSON schema:

```json
{
    "status": "ok | error | parse_error",
    "error": "message (only on error/parse_error)",
    "returnValue": "tostring of return value (only if non-nil)",
    "output": ["captured print() lines"]
}
```

## Limitations

- Game must be running and on the **world screen** (polling uses a menu element that only renders on the world screen)
- One command at a time (serial: write → execute → result → next)
- Text output only (no screenshots or binary data)
- Round-trip latency: ~200ms typical
