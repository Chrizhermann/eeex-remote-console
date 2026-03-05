#!/usr/bin/env bash
# eeex-remote.sh — Send Lua commands to a running BG:EE game via EEex Remote Console
#
# Usage: eeex-remote.sh <game-override-dir> <lua-command> [timeout]
#   lua-command: inline Lua string, or @path/to/file.lua to send file contents
#   timeout: seconds to wait for result (default: 10)
#
# Examples:
#   eeex-remote.sh <game-dir>/override 'print("hello")'
#   eeex-remote.sh <game-dir>/override @scripts/diagnostic.lua
#   eeex-remote.sh <game-dir>/override 'return 2+2' 5

set -euo pipefail

if [ $# -lt 2 ]; then
    echo "Usage: eeex-remote.sh <game-override-dir> <lua-command> [timeout]" >&2
    exit 2
fi

OVERRIDE="$1"
CMD="$2"
TIMEOUT=${3:-10}

CMD_FILE="$OVERRIDE/eeex_remote_cmd.lua"
RESULT_FILE="$OVERRIDE/eeex_remote_result.json"

# Clean up any stale result
rm -f "$RESULT_FILE"

# Write command (@ prefix = send file contents)
if [[ "$CMD" == @* ]]; then
    cp "${CMD:1}" "$CMD_FILE"
else
    printf '%s' "$CMD" > "$CMD_FILE"
fi

# Poll for result (0.2s intervals, TIMEOUT is in seconds)
max_iterations=$((TIMEOUT * 5))
elapsed=0
while [ ! -f "$RESULT_FILE" ] && [ "$elapsed" -lt "$max_iterations" ]; do
    sleep 0.2
    elapsed=$((elapsed + 1))
done

if [ -f "$RESULT_FILE" ]; then
    cat "$RESULT_FILE"
    rm -f "$RESULT_FILE"
    exit 0
else
    echo '{"status":"timeout","error":"No response after '"${TIMEOUT}"'s (is the game running and on the world screen?)"}'
    exit 1
fi
