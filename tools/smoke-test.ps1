#Requires -Version 5.1
<#
smoke-test.ps1 — In-game test suite for EEex Remote Console.
Requires: game running with the mod installed, on the WORLD SCREEN (a loaded save).
Usage:    .\tools\smoke-test.ps1 [-OverrideDir <path>] [-IncludeWatchdog]
Exit:     0 all pass, 1 failures, 2 game unreachable.
#>
[CmdletBinding()]
param(
    [string]$OverrideDir = 'C:\Games\Baldur''s Gate II Enhanced Edition modded\override',
    [switch]$IncludeWatchdog
)
$ErrorActionPreference = 'Stop'

$script:pass = 0
$script:fail = 0

function Invoke-RC {
    param([string]$Lua, [int]$TimeoutSec = 10)
    $cmdFile    = Join-Path $OverrideDir 'eeex_remote_cmd.lua'
    $resultFile = Join-Path $OverrideDir 'eeex_remote_result.json'
    $tmpFile    = Join-Path $OverrideDir "eeex_remote_cmd.tmp.$PID"
    $id = [guid]::NewGuid().ToString('N')
    Remove-Item -LiteralPath $resultFile -Force -ErrorAction SilentlyContinue
    [IO.File]::WriteAllText($tmpFile, "--@id=$id`n$Lua", [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmpFile -Destination $cmdFile -Force
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $resultFile) {
            $raw = Get-Content -Raw -LiteralPath $resultFile -Encoding UTF8 -ErrorAction SilentlyContinue
            if ($raw) {
                Remove-Item -LiteralPath $resultFile -Force -ErrorAction SilentlyContinue
                try {
                    $json = $raw | ConvertFrom-Json
                } catch {
                    Write-Host "  INVALID-JSON payload: $raw" -ForegroundColor Red
                    return $null
                }
                if (-not $json.id -or $json.id -eq $id) { return $json }
                # stale result from another client: keep polling
            }
        }
        Start-Sleep -Milliseconds 200
    }
    return $null
}

function Assert-True {
    param([string]$Name, [object]$Condition, [string]$Detail = '')
    if ([bool]$Condition) { $script:pass++; Write-Host "  PASS  $Name" -ForegroundColor Green }
    else                  { $script:fail++; Write-Host "  FAIL  $Name  $Detail" -ForegroundColor Red }
}

Write-Host "EEex Remote Console smoke suite -> $OverrideDir"

# Reachability probe
$r = Invoke-RC 'return 1' 10
if ($null -eq $r) {
    Write-Host 'Game unreachable (running? world screen? mod installed?)' -ForegroundColor Red
    exit 2
}

# --- Baseline (v0.1.0 behavior) ---
$r = Invoke-RC 'print("hello", 42)'
Assert-True 'print capture' ($null -ne $r -and $r.status -eq 'ok' -and $r.output[0] -eq "hello`t42") ($r | ConvertTo-Json -Compress -Depth 6 -WarningAction SilentlyContinue)

$r = Invoke-RC 'return 2+2'
Assert-True 'legacy returnValue' ($null -ne $r -and $r.status -eq 'ok' -and $r.returnValue -eq '4') ($r | ConvertTo-Json -Compress -Depth 6 -WarningAction SilentlyContinue)

$r = Invoke-RC 'error("boom")'
Assert-True 'runtime error' ($null -ne $r -and $r.status -eq 'error' -and $r.error -match 'boom') ($r | ConvertTo-Json -Compress -Depth 6 -WarningAction SilentlyContinue)

$r = Invoke-RC 'this is not lua'
Assert-True 'parse error' ($null -ne $r -and $r.status -eq 'parse_error') ($r | ConvertTo-Json -Compress -Depth 6 -WarningAction SilentlyContinue)

$r = Invoke-RC 'local s = EEex_Sprite_GetInPortrait(0); return s and s:getName() or "no-sprite"'
Assert-True 'EEex API callable' ($null -ne $r -and $r.status -eq 'ok' -and $r.returnValue) ($r | ConvertTo-Json -Compress -Depth 6 -WarningAction SilentlyContinue)

# === APPEND NEW CASES BELOW (Tasks 1-6 add their sections here) ===

# --- Task 1: compat core ---
$r = Invoke-RC 'return EEexRemote.Info()'
Assert-True 'Info() exists' ($null -ne $r -and $r.status -eq 'ok') ($r | ConvertTo-Json -Compress -Depth 6 -WarningAction SilentlyContinue)

$r = Invoke-RC 'return EEexRemote.PROTOCOL'
Assert-True 'protocol version' ($null -ne $r -and $r.returnValue -eq '1.1') ($r | ConvertTo-Json -Compress -Depth 6 -WarningAction SilentlyContinue)

# --- Task 2: robustness ---
$r = Invoke-RC 'print("a\0b\31c")'   # control chars must not break JSON
Assert-True 'control-char escaping' ($null -ne $r -and $r.status -eq 'ok') ($r | ConvertTo-Json -Compress -Depth 6 -WarningAction SilentlyContinue)

$r = Invoke-RC 'error("boom")'
Assert-True 'traceback field' ($null -ne $r -and $r.traceback -match 'traceback') ($r | ConvertTo-Json -Compress -Depth 6 -WarningAction SilentlyContinue)

$r = Invoke-RC 'local t = {}; t.self = t; return t'
Assert-True 'cycle-safe serializer' ($null -ne $r -and $r.status -eq 'ok') ($r | ConvertTo-Json -Compress -Depth 6 -WarningAction SilentlyContinue)

$r = Invoke-RC 'return 1, "two", true'
Assert-True 'multi-return count' ($null -ne $r -and $r.returnValues.Count -eq 3) ($r | ConvertTo-Json -Compress -Depth 6 -WarningAction SilentlyContinue)
Assert-True 'multi-return values' ($null -ne $r -and $r.returnValues[1] -eq 'two' -and $r.returnValues[2] -eq $true) ($r | ConvertTo-Json -Compress -Depth 6 -WarningAction SilentlyContinue)

if ($IncludeWatchdog) {
    $r = Invoke-RC "--@watchdog=2000000`nwhile true do end" 30
    Assert-True 'watchdog aborts runaway' ($null -ne $r -and $r.status -eq 'error' -and $r.error -match 'watchdog') ($r | ConvertTo-Json -Compress -Depth 6 -WarningAction SilentlyContinue)
    $r = Invoke-RC 'return 42'
    Assert-True 'game alive after watchdog' ($null -ne $r -and $r.returnValue -eq '42') ($r | ConvertTo-Json -Compress -Depth 6 -WarningAction SilentlyContinue)
}

Write-Host ''
Write-Host "Result: $script:pass passed, $script:fail failed"
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
