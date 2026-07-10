#!/usr/bin/env bash
# eeex-remote.sh — Send Lua to a running BG:EE/BG2:EE game via EEex Remote Console
#
# Usage: eeex-remote.sh <game-override-dir> <lua-command | @script.lua | - | --api PATTERN> [timeout-sec]
#   @file.lua : send file contents (whole scripts are one chunk: locals shared)
#   -         : read the script from stdin
#   --api P   : list live globals matching Lua pattern P (e.g. '^EEex_Sprite_')
# Exit codes: 0 ok | 1 lua error/parse_error | 2 timeout | 3 usage

set -euo pipefail

if [ $# -lt 2 ]; then
    echo "Usage: eeex-remote.sh <game-override-dir> <lua|@file|-|--api PATTERN> [timeout]" >&2
    exit 3
fi

OVERRIDE="$1"; shift
CMD="$1"; shift
if [ "$CMD" = "--api" ]; then
    [ $# -ge 1 ] || { echo "--api needs a Lua pattern" >&2; exit 3; }
    CMD="return EEexRemote.ListGlobals(\"$1\")"; shift
fi
TIMEOUT="${1:-10}"

CMD_FILE="$OVERRIDE/eeex_remote_cmd.lua"
RESULT_FILE="$OVERRIDE/eeex_remote_result.json"
TMP_FILE="$OVERRIDE/eeex_remote_cmd.tmp.$$"

ID="$(date +%s%N)-$$-$RANDOM"

{
    printf -- '--@id=%s\n' "$ID"
    if [ "$CMD" = "-" ]; then cat
    elif [ "${CMD#@}" != "$CMD" ]; then cat "${CMD#@}"
    else printf '%s' "$CMD"; fi
} > "$TMP_FILE"

rm -f "$RESULT_FILE"
mv -f "$TMP_FILE" "$CMD_FILE"   # atomic: the game never reads a partial file

deadline=$(( $(date +%s) + TIMEOUT ))
while :; do
    if [ -f "$RESULT_FILE" ]; then
        body="$(cat "$RESULT_FILE" 2>/dev/null || true)"
        if [ -n "$body" ]; then
            rid="$(printf '%s' "$body" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4 || true)"
            if [ -z "$rid" ] || [ "$rid" = "$ID" ]; then
                rm -f "$RESULT_FILE"
                printf '%s\n' "$body"
                printf '%s' "$body" | grep -q '"status":"ok"' && exit 0 || exit 1
            fi
            rm -f "$RESULT_FILE"   # stale result from another run — discard
        fi
    fi
    [ "$(date +%s)" -ge "$deadline" ] && break
    sleep 0.2
done

echo '{"status":"timeout","error":"No response after '"$TIMEOUT"'s (game running on world screen or main menu? mod installed?)"}'
exit 2
