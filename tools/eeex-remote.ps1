#Requires -Version 5.1
<#
eeex-remote.ps1 — Send Lua to a running BG:EE/BG2:EE game via EEex Remote Console.
Usage:
  .\eeex-remote.ps1 <game-override-dir> <lua-command | '@script.lua' | -> [timeout-sec]
  .\eeex-remote.ps1 <game-override-dir> -Api '<lua-pattern>' [-TimeoutSec <sec>]
Notes:
  -Api is the canonical way to list live globals matching a Lua pattern; it works
  both in-shell and via pwsh -File. The positional '--api PATTERN' form (parity
  with the bash client) works in-shell only — pwsh -File binds leading-dash
  arguments as parameter names. With -Api, pass the timeout as -TimeoutSec.
  Quote @file arguments ('@tools/scripts/ping.lua') — bare @ is PowerShell splatting syntax.
Exit codes: 0 ok | 1 lua error/parse_error | 2 timeout | 3 usage
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)] [string]$OverrideDir,
    [Parameter(Position = 1)] [string]$Command,
    [Parameter(Position = 2)] [string]$Extra,
    [Parameter(Position = 3)] [int]$TimeoutSec = 10,
    [string]$Api
)
$ErrorActionPreference = 'Stop'

if (-not $Api -and -not $Command) { Write-Error 'Usage: eeex-remote.ps1 <override-dir> <lua|@file|-|--api PATTERN> | -Api <pattern> [-TimeoutSec n]' -ErrorAction Continue; exit 3 }
if (-not (Test-Path -LiteralPath $OverrideDir -PathType Container)) {
    Write-Error "Override dir not found: $OverrideDir" -ErrorAction Continue; exit 3
}
if ($Api) {
    $Command = "return EEexRemote.ListGlobals(`"$Api`")"
} elseif ($Command -eq '--api') {
    if (-not $Extra) { Write-Error '--api needs a Lua pattern' -ErrorAction Continue; exit 3 }
    $Command = "return EEexRemote.ListGlobals(`"$Extra`")"
} elseif ($Extra) {
    $TimeoutSec = [int]$Extra
}

$cmdFile    = Join-Path $OverrideDir 'eeex_remote_cmd.lua'
$resultFile = Join-Path $OverrideDir 'eeex_remote_result.json'
$tmpFile    = Join-Path $OverrideDir "eeex_remote_cmd.tmp.$PID"
$id = [guid]::NewGuid().ToString('N')

if ($Command -eq '-') { $body = [Console]::In.ReadToEnd() }
elseif ($Command.StartsWith('@')) { $body = Get-Content -Raw -LiteralPath $Command.Substring(1) }
else { $body = $Command }

Remove-Item -LiteralPath $resultFile -Force -ErrorAction SilentlyContinue
[IO.File]::WriteAllText($tmpFile, "--@id=$id`n$body", [Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $tmpFile -Destination $cmdFile -Force

$deadline = (Get-Date).AddSeconds($TimeoutSec)
while ((Get-Date) -lt $deadline) {
    if (Test-Path -LiteralPath $resultFile) {
        $raw = Get-Content -Raw -LiteralPath $resultFile -Encoding UTF8 -ErrorAction SilentlyContinue
        if ($raw) {
            $json = $null
            try { $json = $raw | ConvertFrom-Json } catch {}
            Remove-Item -LiteralPath $resultFile -Force -ErrorAction SilentlyContinue
            if ($json -and (-not $json.id -or $json.id -eq $id)) {
                Write-Output $raw
                if ($json.status -eq 'ok') { exit 0 } else { exit 1 }
            }
            # invalid or stale — discarded above; keep polling
        }
    }
    Start-Sleep -Milliseconds 200
}
Write-Output ('{"status":"timeout","error":"No response after ' + $TimeoutSec + 's (game running on world screen or main menu? mod installed?)"}')
exit 2
