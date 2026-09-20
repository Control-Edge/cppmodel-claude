# Template: copy this into a CppModel project (e.g. as scripts\install-cppmodel.ps1) and commit
# it - it's meant to be run by that project's own developers and CI, not invoked from the plugin.
# Windows only; use install-cppmodel.sh on Linux/macOS.
[CmdletBinding()]
param(
    [string]$DepsDir,
    [string]$BaseUrl = "https://download.cppmodel.com/",
    [string]$Version = "latest",
    [ValidateSet("UCRT64", "CLANG64", "MSVC")]
    [string]$Platform
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
if (-not $DepsDir) { $DepsDir = Join-Path $ProjectRoot "dependencies" }

if (-not $Platform) {
    $found = @()
    foreach ($exe in "g++", "clang++") {
        $cmd = Get-Command $exe -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Source -match "(?i)ucrt64") { $found += "UCRT64" }
        elseif ($cmd -and $cmd.Source -match "(?i)clang64") { $found += "CLANG64" }
    }
    if (Get-Command cl -ErrorAction SilentlyContinue) { $found += "MSVC" }
    $found = @($found | Select-Object -Unique)

    if ($found.Count -eq 1) { $Platform = $found[0] }
    elseif ($found.Count -eq 0) { throw "Could not detect Windows toolchain. Pass -Platform UCRT64|CLANG64|MSVC." }
    else { throw "Multiple toolchains detected ($($found -join ', ')). Pass -Platform to disambiguate." }
}

$archiveName = "CppModel-$Version-Windows-$Platform.zip"
Write-Host "Target platform: Windows-$Platform (version: $Version)"

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "cppmodel-install-$(Get-Date -Format yyyyMMdd-HHmmss)"
New-Item -ItemType Directory -Path $tempDir | Out-Null
$archivePath = Join-Path $tempDir $archiveName
Write-Host "Downloading $archiveName ..."
Invoke-WebRequest -Uri ($BaseUrl + $archiveName) -OutFile $archivePath -UseBasicParsing

$stagingRoot = Join-Path $tempDir "staging"
Write-Host "Extracting..."
Expand-Archive -Path $archivePath -DestinationPath $stagingRoot -Force

# Archive layout has changed across releases (some ship a single top-level version folder,
# older ones ship flat) - handle both rather than assuming one.
$topEntries = @(Get-ChildItem $stagingRoot)
$contentDir = $stagingRoot
if ($topEntries.Count -eq 1 -and $topEntries[0].PSIsContainer) { $contentDir = $topEntries[0].FullName }

if (Test-Path $DepsDir) { Remove-Item $DepsDir -Recurse -Force }
New-Item -ItemType Directory -Path $DepsDir | Out-Null
Copy-Item -Path (Join-Path $contentDir '*') -Destination $DepsDir -Recurse -Force

Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Installed CppModel $Version into $DepsDir"
