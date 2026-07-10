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
            $raw = Get-Content -Raw -LiteralPath $resultFile -ErrorAction SilentlyContinue
            if ($raw) {
                Remove-Item -LiteralPath $resultFile -Force -ErrorAction SilentlyContinue
                $json = $raw | ConvertFrom-Json   # throws on invalid JSON = test failure
                if (-not $json.id -or $json.id -eq $id) { return $json }
                # stale result from another client: keep polling
            }
        }
        Start-Sleep -Milliseconds 200
    }
    return $null
}

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if ($Condition) { $script:pass++; Write-Host "  PASS  $Name" -ForegroundColor Green }
    else            { $script:fail++; Write-Host "  FAIL  $Name  $Detail" -ForegroundColor Red }
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
Assert-True 'print capture' ($r.status -eq 'ok' -and $r.output[0] -eq "hello`t42") ($r | ConvertTo-Json -Compress)

$r = Invoke-RC 'return 2+2'
Assert-True 'legacy returnValue' ($r.status -eq 'ok' -and $r.returnValue -eq '4') ($r | ConvertTo-Json -Compress)

$r = Invoke-RC 'error("boom")'
Assert-True 'runtime error' ($r.status -eq 'error' -and $r.error -match 'boom') ($r | ConvertTo-Json -Compress)

$r = Invoke-RC 'this is not lua'
Assert-True 'parse error' ($r.status -eq 'parse_error') ($r | ConvertTo-Json -Compress)

$r = Invoke-RC 'local s = EEex_Sprite_GetInPortrait(0); return s and s:getName() or "no-sprite"'
Assert-True 'EEex API callable' ($r.status -eq 'ok' -and $r.returnValue) ($r | ConvertTo-Json -Compress)

# === APPEND NEW CASES BELOW (Tasks 1-6 add their sections here) ===

Write-Host ''
Write-Host "Result: $script:pass passed, $script:fail failed"
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
