# Runs one CppModel simulation repeatedly with different inputs/parameters (a sweep), used by the
# cppmodel:parameter-sweep skill. Every API call goes through cppmodel-fetch.ps1. Same plan format,
# checks, and output layout as cppmodel-sweep.sh - see that script's header.
#
#   cppmodel-sweep.ps1 <plan.json> <out-dir> [-DryRun] [-TimeoutSeconds <s>] [-Workspace <id>]
#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)][string]$Plan,
    [Parameter(Mandatory, Position = 1)][string]$Out,
    [switch]$DryRun,
    [int]$TimeoutSeconds = 0,
    [string]$Workspace
)
$ErrorActionPreference = "Stop"

$Fetch = Join-Path $PSScriptRoot "cppmodel-fetch.ps1"
$WsArgs = @(); if ($Workspace) { $WsArgs = @("--workspace", $Workspace) }
function Invoke-Fetch {
    $output = & $Fetch @WsArgs @args
    if ($LASTEXITCODE) { throw "cppmodel-fetch.ps1 $($args -join ' ') failed" }
    return ($output | Out-String)
}
function Read-Json([string]$Path) { Get-Content -Raw -Encoding UTF8 $Path | ConvertFrom-Json }
function Write-Text([string]$Text, [string]$Path) {
    # UTF-8 without BOM - Windows PowerShell 5.1's -Encoding UTF8 would add one.
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding $false))
}
function Write-Json($Object, [string]$Path) { Write-Text (ConvertTo-Json -InputObject $Object -Depth 20) $Path }
function Copy-Deep($Object) { ConvertTo-Json -InputObject $Object -Depth 20 | ConvertFrom-Json }
function Get-Props($Object) { if ($Object) { @($Object.PSObject.Properties) } else { @() } }

$RepoRoot = (& git rev-parse --show-toplevel).Trim()
$PlanData = Read-Json $Plan
$Simulation = $PlanData.simulation
if (-not $Simulation) { throw 'Plan has no "simulation"' }
$Binary = $PlanData.binary
if ($Binary -and -not [System.IO.Path]::IsPathRooted($Binary)) { $Binary = Join-Path $RepoRoot $Binary }
if (-not $DryRun -and -not (Test-Path $Binary)) { throw "Simulation binary not found: $Binary (build it first)" }
$BaseKind = if ($null -eq $PlanData.base) { "defaults" } elseif ($PlanData.base -is [string]) { $PlanData.base } else { "inline" }
if (@("defaults", "current", "inline") -notcontains $BaseKind) { throw "Unknown base `"$BaseKind`" - use `"defaults`", `"current`", or an inline document." }

New-Item -ItemType Directory -Force -Path (Join-Path $Out "runs"), (Join-Path $Out "results") | Out-Null
$Out = (Resolve-Path $Out).Path
$RunsDir = Join-Path $Out "runs"; $ResultsDir = Join-Path $Out "results"
$PendingFile = Join-Path $Out "pending-before.json"
Remove-Item (Join-Path $RunsDir "*"), (Join-Path $ResultsDir "*"), (Join-Path $Out "summary.json"), $PendingFile -ErrorAction SilentlyContinue

# A document someone already posted for the next execution. GET returns 404 ("No input data
# found") when there is none, which is the normal case.
$HavePending = $false
if (-not $DryRun -or $BaseKind -eq "current") {
    try {
        Write-Text (Invoke-Fetch inputs $Simulation) $PendingFile
        $HavePending = $true
        Write-Host "Note: '$Simulation' already had inputs pending; they'll be re-posted after the sweep."
    } catch {
        if ("$_" -notmatch "NOT_FOUND|404|No input data") { throw }
    }
}
$Base = switch ($BaseKind) {
    "defaults" { [pscustomobject]@{} }
    "inline" { $PlanData.base }
    "current" {
        if ($HavePending) { Read-Json $PendingFile }
        else {
            try { Invoke-Fetch $Simulation | ConvertFrom-Json; Write-Host "Base: the latest execution's recorded inputs/parameters." }
            catch { Write-Host "Base: defaults (no pending document and no previous execution)."; [pscustomobject]@{} }
        }
    }
}
$Base = [pscustomobject]@{
    inputs = @(if ($Base.inputs) { $Base.inputs })
    parameters = $(if ($Base.parameters) { $Base.parameters } else { [pscustomobject]@{} })
}

# --- Expand the plan into one full inputs document per run ---------------------------------------
$GridParams = Get-Props $PlanData.parameters
$GridInputs = Get-Props $PlanData.inputs
if ($PlanData.runs -and ($GridParams.Count -or $GridInputs.Count)) {
    throw 'Plan uses both "runs" and grid keys ("parameters"/"inputs") - use one or the other.'
}

$Runs = @()
if ($PlanData.runs) {
    $i = 0
    foreach ($r in $PlanData.runs) {
        $i++
        $inputs = @{}; foreach ($p in (Get-Props $r.inputs)) { $inputs[$p.Name] = $p.Value }
        $params = [ordered]@{}; foreach ($p in (Get-Props $r.parameters)) { $params[$p.Name] = $p.Value }
        $Runs += @{ name = $(if ($r.name) { $r.name } else { "run $i" }); parameters = $params; inputs = $inputs; variants = $null }
    }
} else {
    # Cartesian product: start with one empty combination, multiply by each axis in turn.
    $combos = @(@{ parameters = [ordered]@{}; inputs = @{}; variants = [ordered]@{}; names = @() })
    foreach ($axis in $GridParams) {
        $combos = @(foreach ($c in $combos) { foreach ($v in $axis.Value) {
            $p = [ordered]@{}; foreach ($k in $c.parameters.Keys) { $p[$k] = $c.parameters[$k] }; $p[$axis.Name] = $v
            @{ parameters = $p; inputs = $c.inputs.Clone(); variants = $c.variants; names = $c.names + "$($axis.Name)=$v" }
        } })
    }
    foreach ($axis in $GridInputs) {
        $combos = @(foreach ($c in $combos) { foreach ($variant in (Get-Props $axis.Value)) {
            $in = $c.inputs.Clone(); $in[$axis.Name] = $variant.Value
            $va = [ordered]@{}; foreach ($k in $c.variants.Keys) { $va[$k] = $c.variants[$k] }; $va[$axis.Name] = $variant.Name
            @{ parameters = $c.parameters; inputs = $in; variants = $va; names = $c.names + "$($axis.Name)=$($variant.Name)" }
        } })
    }
    foreach ($c in $combos) {
        $Runs += @{ name = $(if ($c.names) { $c.names -join ", " } else { "base" }); parameters = $c.parameters; inputs = $c.inputs; variants = $c.variants }
    }
}

# The server stores whatever it's given without validating it, so validate here.
function Test-Series([string]$Where, [string]$Label, $S) {
    $x = @($S.x); $y = @($S.y)
    # Test for $null explicitly: -not @(0) is $true, so x = [0] would look missing.
    if ($null -eq $S.x -or $null -eq $S.y -or $x.Count -eq 0) { throw "${Where}: input `"$Label`" needs non-empty `"x`" and `"y`" lists" }
    if ($x.Count -ne $y.Count) { throw "${Where}: input `"$Label`" has $($x.Count) x values but $($y.Count) y values" }
    for ($k = 1; $k -lt $x.Count; $k++) { if ($x[$k] -lt $x[$k - 1]) { throw "${Where}: input `"$Label`" has x values out of order" } }
}

$Now = Get-Date -Format "dd-MM-yyyy HH:mm:ss"
for ($i = 1; $i -le $Runs.Count; $i++) {
    $r = $Runs[$i - 1]; $n = "{0:D3}" -f $i
    $body = Copy-Deep $Base
    $body | Add-Member -Force NoteProperty executionTime $Now
    foreach ($k in $r.parameters.Keys) { $body.parameters | Add-Member -Force NoteProperty $k $r.parameters[$k] }
    foreach ($label in $r.inputs.Keys) {
        $s = $r.inputs[$label]
        Test-Series $r.name $label $s
        $body.inputs = @(@($body.inputs | Where-Object { $_.label -ne $label }) + [pscustomobject]@{ label = $label; x = @($s.x); y = @($s.y) })
    }
    Write-Json $body (Join-Path $RunsDir "$n.json")
    $inputsMeta = if ($r.variants -and $r.variants.Count) { $r.variants } else { @($r.inputs.Keys | Sort-Object) }
    Write-Json ([ordered]@{ run = $i; name = $r.name; parameters = $r.parameters; inputs = $inputsMeta }) (Join-Path $RunsDir "$n.meta.json")
}
Write-Host "$($Runs.Count) run(s) prepared in $RunsDir"

# A posted name the code never reads is accepted and even recorded, so a typo only shows up as the
# fallback being used. Warn about names the latest execution didn't read before anything is posted.
try {
    $latest = Invoke-Fetch $Simulation | ConvertFrom-Json
    $knownParams = @((Get-Props $latest.parameters) | ForEach-Object { $_.Name })
    $knownInputs = @(@($latest.inputs) | Where-Object { $_ } | ForEach-Object { $_.label })
    $unknown = @()
    $unknown += @($Runs | ForEach-Object { $_.parameters.Keys } | Sort-Object -Unique | Where-Object { $knownParams -notcontains $_ } | ForEach-Object { "parameter `"$_`"" })
    $unknown += @($Runs | ForEach-Object { $_.inputs.Keys } | Sort-Object -Unique | Where-Object { $knownInputs -notcontains $_ } | ForEach-Object { "input `"$_`"" })
    if ($unknown.Count) { Write-Warning ("not read by the latest execution of this simulation - check for typos:`n  " + ($unknown -join "`n  ")) }
} catch {
    Write-Host "note: no previous execution to check names against - verify them against the source."
}

$RunFiles = @(Get-ChildItem $RunsDir -Filter "???.json" | Sort-Object Name)
if ($DryRun) {
    foreach ($f in $RunFiles) { $m = Read-Json ($f.FullName -replace '\.json$', '.meta.json'); Write-Host ("{0:D3}  {1}" -f $m.run, $m.name) }
    Write-Host "Dry run - nothing posted or executed."
    exit 0
}

# --- Execute -------------------------------------------------------------------------------------
function Get-TopExecutionId {
    try { $list = Invoke-Fetch executions $Simulation | ConvertFrom-Json } catch { return "" }
    if ($list.items) { return @($list.items)[0].id } else { return "" }
}
function Test-Same($a, $b) { [math]::Abs([double]$a - [double]$b) -le 1e-6 * [math]::Max(1.0, [math]::Abs([double]$a)) }
function Get-Held($Series, [double]$t) {
    # Zero-order hold: the y of the latest x <= t.
    $x = @($Series.x); $y = @($Series.y); $v = $null
    for ($k = 0; $k -lt $x.Count -and $x[$k] -le $t; $k++) { $v = $y[$k] }
    return $v
}
# Compares the posted document with what the execution recorded. Posted values take precedence
# over fallbacks, so every posted name should appear with exactly the posted value.
function Compare-Applied($Posted, $Recorded) {
    $mismatches = @()
    $recParams = @{}; foreach ($p in (Get-Props $Recorded.parameters)) { $recParams[$p.Name] = $p.Value }
    foreach ($p in (Get-Props $Posted.parameters)) {
        if ($p.Name -like "CppModel.*") { continue }
        if (-not $recParams.ContainsKey($p.Name)) { $mismatches += "parameter `"$($p.Name)`": posted $($p.Value), missing from the execution record" }
        elseif (-not (Test-Same $p.Value $recParams[$p.Name])) { $mismatches += "parameter `"$($p.Name)`": posted $($p.Value), simulation read $($recParams[$p.Name])" }
    }
    $recInputs = @{}; foreach ($s in @($Recorded.inputs)) { if ($s) { $recInputs[$s.label] = $s } }
    foreach ($s in @($Posted.inputs)) {
        if (-not $s) { continue }
        $rs = $recInputs[$s.label]
        if (-not $rs) { $mismatches += "input `"$($s.label)`": posted, missing from the execution record"; continue }
        $rx = @($rs.x); $ry = @($rs.y)
        for ($k = 0; $k -lt $rx.Count; $k++) {
            $want = Get-Held $s $rx[$k]
            if ($null -ne $want -and -not (Test-Same $want $ry[$k])) {
                $mismatches += "input `"$($s.label)`" at $($rx[$k]) ms: posted $want, simulation read $($ry[$k])"; break
            }
        }
    }
    return @{ mismatches = $mismatches }
}

$EnvVars = @{}
Get-Content (Join-Path $RepoRoot ".env") | ForEach-Object {
    if ($_ -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') { $EnvVars[$Matches[1]] = $Matches[2] }
}

$Summary = @()
$exitStatus = 0
try {
    $prevId = Get-TopExecutionId
    foreach ($f in $RunFiles) {
        $n = $f.BaseName
        $meta = Read-Json (Join-Path $RunsDir "$n.meta.json")
        Write-Host "=== Run ${n}: $($meta.name)"
        Invoke-Fetch set-inputs $Simulation $f.FullName | Out-Null

        # Give the binary the .env credentials (and never offline mode), then put the session back.
        $saved = @{}
        foreach ($k in @($EnvVars.Keys) + "CPPMODEL_OFFLINE") { $saved[$k] = [Environment]::GetEnvironmentVariable($k, "Process") }
        try {
            foreach ($k in $EnvVars.Keys) { [Environment]::SetEnvironmentVariable($k, $EnvVars[$k], "Process") }
            [Environment]::SetEnvironmentVariable("CPPMODEL_OFFLINE", $null, "Process")
            $log = Join-Path $RunsDir "$n.log"; $err = "$log.stderr"
            $proc = Start-Process -FilePath $Binary -WorkingDirectory $RepoRoot -NoNewWindow -PassThru `
                -RedirectStandardOutput $log -RedirectStandardError $err
            $null = $proc.Handle  # cache the handle so ExitCode is available after exit
            if ($TimeoutSeconds -gt 0) {
                if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) { $proc.Kill(); $proc.WaitForExit() }
            } else { $proc.WaitForExit() }
            $code = $proc.ExitCode
            Get-Content $err | Add-Content $log; Remove-Item $err
        } finally {
            foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k], "Process") }
        }

        # An offline run never read the posted inputs, so none of its numbers mean anything.
        if (Select-String -Path $log -Pattern "Running offline" -SimpleMatch -Quiet) {
            throw "Run $n ran OFFLINE (API unreachable) - posted inputs were not used. Aborting sweep."
        }
        $execId = Get-TopExecutionId
        if (-not $execId -or $execId -eq $prevId) { throw "Run $n produced no new execution on the server (see runs/$n.log). Aborting sweep." }
        $prevId = $execId
        $resultFile = Join-Path $ResultsDir "$n.json"
        Write-Text (Invoke-Fetch execution $Simulation $execId) $resultFile

        # Did the simulation read what was posted? The execution records every input and parameter
        # it actually read - fallback values included - so compare those with the posted document.
        $check = Compare-Applied (Read-Json $f.FullName) (Read-Json $resultFile)
        $meta | Add-Member NoteProperty exitCode $code
        $meta | Add-Member NoteProperty passed ($code -eq 0)
        $meta | Add-Member NoteProperty executionId $execId
        $meta | Add-Member NoteProperty applied ($check.mismatches.Count -eq 0)
        $meta | Add-Member NoteProperty results "results/$n.json"
        $meta | Add-Member NoteProperty log "runs/$n.log"
        $Summary += $meta
        if ($check.mismatches.Count) {
            throw ("Run ${n}: the simulation did NOT use the posted values:`n  " + ($check.mismatches -join "`n  ") +
                "`nIts results describe the default run, not this scenario (SDKs before 0.6.1 don't apply posted inputs - check dependencies\). Aborting sweep.")
        }
        Write-Host "    exit $code, execution $execId"
    }
    Write-Json @($Summary) (Join-Path $Out "summary.json")
    Write-Host "$(@($Summary | Where-Object passed).Count)/$($Summary.Count) runs passed. Summary: $(Join-Path $Out 'summary.json')"
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    $exitStatus = 1
} finally {
    if ($HavePending) {
        Write-Host "Re-posting the inputs that were pending before the sweep ..."
        try { Invoke-Fetch set-inputs $Simulation $PendingFile | Out-Null }
        catch { Write-Warning "Re-post failed - post $PendingFile manually." }
    }
}
exit $exitStatus
