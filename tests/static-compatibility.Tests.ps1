#Requires -Version 5.1
<#
Dependency-free regression checks for EEex compatibility documentation and
installer/runtime prerequisite diagnostics.

These checks intentionally verify capability-based detection separately from
the version-specific guidance shown to users.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = New-Object 'System.Collections.Generic.List[string]'
$script:assertions = 0

function Read-RepoFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    return Get-Content -Raw -LiteralPath (Join-Path $repoRoot $Path)
}

function Assert-Matches {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$Pattern
    )
    $script:assertions++
    if ($Content -notmatch $Pattern) {
        $failures.Add("$Name (missing pattern: $Pattern)")
    }
}

function Assert-NotMatches {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$Pattern
    )
    $script:assertions++
    if ($Content -match $Pattern) {
        $failures.Add("$Name (stale pattern still present: $Pattern)")
    }
}

$installer = Read-RepoFile 'setup-eeexremote.tp2'
$module = Read-RepoFile 'eeexremote/M_EEexRC.lua'
$readme = Read-RepoFile 'README.md'
$changelog = Read-RepoFile 'CHANGELOG.md'
$claudeExample = Read-RepoFile 'CLAUDE.md.example'
$smokeTest = Read-RepoFile 'tools/smoke-test.ps1'
$pingScript = Read-RepoFile 'tools/scripts/ping.lua'

$eeexGateMatch = [regex]::Match(
    $installer,
    '(?s)REQUIRE_PREDICATE\s+\(FILE_EXISTS\s+~override/M___EEex\.lua~\)\s+~(?<message>.*?)~'
)
$luaJitGateMatch = [regex]::Match(
    $installer,
    '(?s)ACTION_IF\s+\(eeexrc_luajit\s+=\s+0\)\s+BEGIN\s+FAIL\s+~(?<message>.*?)~\s+END'
)
$installerGuidance = @(
    $eeexGateMatch.Groups['message'].Value,
    $luaJitGateMatch.Groups['message'].Value
) -join "`n"

$runtimeGuidanceMatch = [regex]::Match(
    $module,
    '(?s)if not \(io and os\) then\s+EEexRemote\.Disabled\s*=\s*(?<message>.*?)(?=\s*elseif not register)'
)
$runtimeGuidance = $runtimeGuidanceMatch.Groups['message'].Value
$runtimeMenuGuidanceMatch = [regex]::Match(
    $module,
    '(?s)elseif not register then\s+EEexRemote\.Disabled\s*=\s*(?<message>.*?)(?=\s*end)'
)
$runtimeMenuGuidance = $runtimeMenuGuidanceMatch.Groups['message'].Value

$unreleasedMatch = [regex]::Match(
    $changelog,
    '(?ms)^## \[Unreleased\]\s*(?<body>.*?)(?=^## \[)'
)
$unreleased = $unreleasedMatch.Groups['body'].Value

$acceptanceMatch = [regex]::Match(
    $readme,
    '(?ms)^## Live Verification Status\s*(?<body>.*?)(?=^## )'
)
$acceptance = $acceptanceMatch.Groups['body'].Value

# The installer must keep probing installed capabilities, not hardcoded EEex
# component log entries or version globals.
Assert-Matches 'EEex bootstrap capability gate' $installer `
    'FILE_EXISTS\s+~override/M___EEex\.lua~'
Assert-Matches 'Anchored LuaJIT loader capability gate' $installer `
    'COUNT_REGEXP_INSTANCES\s+~\^LuaPatchMode=REPLACE_INTERNAL_WITH_EXTERNAL~'
Assert-NotMatches 'Installer avoids component-log gating' $installer `
    '(?i)MOD_IS_INSTALLED'
Assert-Matches 'EEex gate has user-facing guidance' $eeexGateMatch.Value `
    'REQUIRE_PREDICATE'
Assert-Matches 'LuaJIT gate has user-facing guidance' $luaJitGateMatch.Value `
    'ACTION_IF'

# v1.2 and later (v1.3) share the component layout. The actionable diagnostics
# must tell users which EEex components to install and that this mod comes
# afterwards.
Assert-Matches 'Installer names EEex v1.2 target' $installerGuidance `
    'EEex v1\.2(?:\.0)?'
Assert-Matches 'Installer covers EEex v1.3' $installerGuidance `
    'EEex v1\.2 or later \(including v1\.3\)'
Assert-Matches 'Installer names EEex main component 1' $installerGuidance `
    'component\s+1\s+\([^\r\n]*Main[^\r\n]*\)'
Assert-Matches 'Installer names EEex LuaJIT component 8' $installerGuidance `
    'component\s+8\s+\([^\r\n]*LuaJIT[^\r\n]*\)'
Assert-Matches 'Installer states install order' $installerGuidance `
    '(?i)install EEex Remote Console after EEex'
Assert-Matches 'Runtime missing-LuaJIT diagnostic exists' $runtimeGuidanceMatch.Value `
    'EEexRemote\.Disabled'
Assert-Matches 'Runtime missing-LuaJIT diagnostic names v1.2' $runtimeGuidance `
    'EEex v1\.2(?:\.0)?'
Assert-Matches 'Runtime missing-LuaJIT diagnostic names components 1 and 8' $runtimeGuidance `
    '(?s)component\s+1.*component\s+8'
Assert-Matches 'Runtime missing-LuaJIT diagnostic states install order' $runtimeGuidance `
    '(?i)install EEex Remote Console after EEex'
Assert-NotMatches 'Runtime guidance no longer stops at v1.0 Experimental' $runtimeGuidance `
    'EEex v1\.0\.0: choose the Experimental tier'
Assert-Matches 'Runtime missing-menu-API diagnostic exists' $runtimeMenuGuidanceMatch.Value `
    'EEexRemote\.Disabled'
Assert-Matches 'Runtime missing-menu-API diagnostic names v1.2' $runtimeMenuGuidance `
    'EEex v1\.2(?:\.0)?'
Assert-Matches 'Runtime missing-menu-API diagnostic names components 1 and 8' $runtimeMenuGuidance `
    '(?s)component\s+1.*component\s+8'
Assert-Matches 'Runtime missing-menu-API diagnostic states install order' $runtimeMenuGuidance `
    '(?i)install EEex Remote Console after EEex'
Assert-NotMatches 'Runtime menu guidance no longer uses the old minimum-only message' $runtimeMenuGuidance `
    'EEex 0\.10\+ required'

# Public/project documentation must distinguish what has already run live from
# the specific acceptance pass that has not run yet.
Assert-Matches 'README requirements cover EEex v1.3' $readme `
    'EEex v1\.2\.x and v1\.3\.x: install \*\*component 1 \(Main\)\*\* and \*\*component 8 \(LuaJIT\)\*\*'
Assert-Matches 'README matrix lists EEex 1.3.x' $readme `
    '(?m)^\| 1\.3\.x \| Supported \|'
Assert-Matches 'README names v1.2 components and install order' $readme `
    '(?s)EEex v1\.2(?:\.0)?.*component\s+1.*component\s+8.*after EEex'
Assert-Matches 'README records prior BG2EE 2.6.6 smoke evidence' $acceptance `
    '(?s)BG2:EE\s+2\.6\.6(?:\.0)?.*EEex v1\.2(?:\.0)?.*22[- ]case'
Assert-Matches 'README records EET 2.7.3 handshake evidence for v1.2' $acceptance `
    '(?s)EET over BG2:EE 2\.7\.3\.0 with EEex v1\.2\.0.*pong'
Assert-Matches 'README marks EEex 1.3.x as source-reviewed until it runs' $readme `
    '\|\s*1\.3\.x\s*\|\s*Supported\s*\|\s*\*\*Source-reviewed\*\*'
Assert-Matches 'README marks EET 2.7.3 live acceptance pending' $acceptance `
    '(?i)(?s)EET.*2\.7\.3.*(?:pending|not yet)'
Assert-Matches 'README future checklist names ready file' $acceptance `
    'eeex_remote_ready\.json'
Assert-Matches 'README future checklist verifies ready protocol' $acceptance `
    'protocol="1\.1"'
Assert-Matches 'README future checklist verifies ready LuaJIT' $acceptance `
    'luajit=true'
Assert-Matches 'README future checklist verifies ready enabled state' $acceptance `
    'disabled=false'
Assert-Matches 'README future checklist verifies both ready screens' $acceptance `
    '(?s)WORLD_ACTIONBAR.*START'
Assert-Matches 'README future checklist verifies pong' $acceptance `
    '(?i)(?s)ping\.lua.*pong'
Assert-Matches 'README future checklist verifies both polling hosts' $acceptance `
    '(?i)(?s)main menu.*world screen'
Assert-Matches 'README future checklist includes watchdog and liveness' $acceptance `
    '(?s)-IncludeWatchdog.*watchdog.*(?:alive|liveness)'
Assert-Matches 'Changelog records the v1.2 target update' $unreleased `
    '(?s)EEex v1\.2(?:\.0)?.*component\s+1.*component\s+8'
Assert-Matches 'Changelog separates old evidence from pending EET acceptance' $unreleased `
    '(?i)(?s)BG2:EE\s+2\.6\.6(?:\.0)?.*EET.*2\.7\.3.*pending'
Assert-Matches 'Claude example reflects v1.2 component requirements' $claudeExample `
    '(?s)EEex v1\.2(?:\.0)?.*component\s+1.*component\s+8'

# Keep the automated 22-case suite aligned with the ready/Info criteria used by
# the future manual host-screen acceptance procedure.
Assert-Matches 'Smoke Info assertion checks LuaJIT and io' $smokeTest `
    '(?s)Info\(\) payload.*?\.luajit\s+-eq\s+\$true.*?\.io\s+-eq\s+\$true'
Assert-Matches 'Smoke Info assertion checks both screens' $smokeTest `
    '(?s)Info\(\) payload.*?WORLD_ACTIONBAR.*?START'
Assert-Matches 'Smoke ready assertion checks enabled state' $smokeTest `
    '(?s)ready file valid.*?\.disabled\s+-eq\s+\$false'
Assert-Matches 'Smoke ready assertion checks both screens' $smokeTest `
    '(?s)ready file valid.*?WORLD_ACTIONBAR.*?START'
Assert-Matches 'Module hosts polling on world and main-menu screens' $module `
    'HOST_MENUS\s*=\s*\{\s*"WORLD_ACTIONBAR"\s*,\s*"START"\s*\}'
Assert-Matches 'Ping script returns pong plus Info' $pingScript `
    'return\s+"pong"\s*,\s*EEexRemote\.Info\(\)'
Assert-Matches 'Smoke watchdog is followed by a liveness case' $smokeTest `
    '(?s)watchdog aborts runaway.*?game alive after watchdog'

if ($failures.Count -gt 0) {
    $summary = 'Static compatibility checks failed: {0} of {1}' -f @(
        $failures.Count,
        $script:assertions
    )
    [Console]::Error.WriteLine($summary)
    foreach ($failure in $failures) {
        [Console]::Error.WriteLine(" - $failure")
    }
    exit 1
}

Write-Host (
    'Static compatibility checks passed: {0}' -f $script:assertions
)
exit 0
