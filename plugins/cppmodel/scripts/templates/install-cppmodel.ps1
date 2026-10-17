# Template: copy this into a CppModel project (e.g. as scripts\install-cppmodel.ps1) and commit
# it - it's meant to be run by that project's own developers and CI, not invoked from the plugin.
# Windows only; use install-cppmodel.sh on Linux/macOS.
#
# Installs CppModel SDK 0.8 or later: one archive per architecture (CppModel-<version>-Windows-x64.zip,
# -Windows-ARM64.zip), used with MSVC or clang-cl. MinGW (MSYS2 UCRT64/CLANG64) isn't supported from
# 0.8 on. The project finds it with find_package(cppmodel) (CMAKE_PREFIX_PATH).
[CmdletBinding()]
param(
    [string]$DepsDir,
    [string]$BaseUrl = "https://download.cppmodel.com/",
    [string]$Version = "latest",
    [ValidateSet("x64", "ARM64")]
    [string]$Arch,
    # Accepted so scripts written for SDKs before 0.8 keep running; ignored.
    [string]$Platform
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
if (-not $DepsDir) { $DepsDir = Join-Path $ProjectRoot "dependencies" }

if ($Platform) {
    if ($Platform -in "UCRT64", "CLANG64", "MINGW64") {
        throw "-Platform ${Platform}: MinGW isn't supported from SDK 0.8 on. Build with MSVC or clang-cl."
    }
    Write-Warning "-Platform is ignored - from SDK 0.8 one archive serves MSVC and clang-cl."
}

if ($Version -ne "latest") {
    $v = [version]($Version + $(if ($Version.Split('.').Count -lt 2) { ".0" } else { "" }))
    if ($v -lt [version]"0.8") { throw "-Version ${Version}: this script installs SDK 0.8 or later; older SDKs were packaged per compiler." }
}

if (-not $Arch) {
    # PROCESSOR_ARCHITEW6432 is set when a 32-bit shell runs on a 64-bit OS - prefer it.
    $hostArch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    switch ($hostArch) {
        "AMD64" { $Arch = "x64" }
        "ARM64" { $Arch = "ARM64" }
        default { throw "No CppModel SDK for Windows on '$hostArch' (published: x64, ARM64). Pass -Arch to override." }
    }
}

# Resolve "latest" to the newest version listed for this platform, so the install reports a real
# version; fall back to the CppModel-latest-* alias if the listing can't be read.
if ($Version -eq "latest") {
    try {
        $listing = (Invoke-WebRequest -Uri $BaseUrl -UseBasicParsing -TimeoutSec 20).Content
        $resolved = [regex]::Matches($listing, "CppModel-(\d+\.\d+\.\d+)-Windows-$Arch\.zip") |
            ForEach-Object { [version]$_.Groups[1].Value } | Sort-Object -Descending | Select-Object -First 1
        if ($resolved) { $Version = "$resolved" }
    } catch { }
}

$archiveName = "CppModel-$Version-Windows-$Arch.zip"
Write-Host "Target platform: Windows-$Arch (version: $Version)"

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "cppmodel-install-$(Get-Date -Format yyyyMMdd-HHmmss)"
New-Item -ItemType Directory -Path $tempDir | Out-Null
$archivePath = Join-Path $tempDir $archiveName
Write-Host "Downloading $archiveName ..."
Invoke-WebRequest -Uri ($BaseUrl + $archiveName) -OutFile $archivePath -UseBasicParsing

$stagingRoot = Join-Path $tempDir "staging"
Write-Host "Extracting..."
Expand-Archive -Path $archivePath -DestinationPath $stagingRoot -Force

# The archive holds a single top-level CppModel-<version>-<platform> folder; install its contents.
$topEntries = @(Get-ChildItem $stagingRoot)
$contentDir = $stagingRoot
if ($topEntries.Count -eq 1 -and $topEntries[0].PSIsContainer) { $contentDir = $topEntries[0].FullName }

if (Test-Path $DepsDir) { Remove-Item $DepsDir -Recurse -Force }
New-Item -ItemType Directory -Path $DepsDir | Out-Null
Copy-Item -Path (Join-Path $contentDir '*') -Destination $DepsDir -Recurse -Force

Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue

$installed = $Version
$versionFile = Join-Path $DepsDir "lib\cmake\cppmodel\cppmodelConfigVersion.cmake"
if (Test-Path $versionFile) {
    $m = Select-String -Path $versionFile -Pattern '^set\(PACKAGE_VERSION "([^"]+)"\)$' | Select-Object -First 1
    if ($m) { $installed = $m.Matches[0].Groups[1].Value }
}
Write-Host "Installed CppModel $installed into $DepsDir"
