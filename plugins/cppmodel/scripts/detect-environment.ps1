# Read-only probe used by the cppmodel:setup-environment skill: reports the Windows version,
# architecture, installed toolchains (MSYS2 UCRT64/CLANG64, MSVC, clang-cl), build tools, and the
# libraries CppModel links against (OpenSSL, zlib), plus which SDK builds download.cppmodel.com
# currently publishes. Installs nothing. Windows only; use detect-environment.sh on Linux/macOS.
#
# Output is one "key=value" per line, same shape as detect-environment.sh. Repeated keys
# (toolchain=, published=) list one item each. Works on Windows PowerShell 5.1 and PowerShell 7.
[CmdletBinding()]
param(
    [string]$BaseUrl = "https://download.cppmodel.com/",
    [string]$Msys2Root,
    [switch]$Offline
)

$ErrorActionPreference = "SilentlyContinue"
function kv([string]$k, [string]$v) { Write-Output "$k=$v" }

# --- OS / arch -----------------------------------------------------------------------------------
$osInfo = Get-CimInstance Win32_OperatingSystem
kv os "Windows"
kv os_pretty "$($osInfo.Caption) $($osInfo.Version)".Trim()
kv os_version "$($osInfo.Version)"
# PROCESSOR_ARCHITEW6432 is set when a 32-bit shell runs on a 64-bit OS - prefer it.
$arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
kv arch $(switch ($arch) { "AMD64" { "x86_64" } "ARM64" { "arm64" } default { $arch } })

$pms = @("winget", "choco", "scoop") | Where-Object { Get-Command $_ }
kv pkg_manager $(if ($pms) { $pms -join "," } else { "none" })

# --- MSYS2 (UCRT64 / CLANG64) --------------------------------------------------------------------
function Get-FirstVersion([string]$text) {
    if ($text -match '(\d+\.\d+(\.\d+)?)') { return $Matches[1] }
    return "unknown"
}

$msysCandidates = @($Msys2Root, "C:\msys64", "$env:USERPROFILE\scoop\apps\msys2\current", "C:\tools\msys64") |
    Where-Object { $_ -and (Test-Path (Join-Path $_ "usr\bin\pacman.exe")) }
$msys = $msysCandidates | Select-Object -First 1
kv msys2 $(if ($msys) { $msys } else { "missing" })

if ($msys) {
    foreach ($envName in "ucrt64", "clang64", "mingw64") {
        $bin = Join-Path $msys "$envName\bin"
        foreach ($exe in "g++.exe", "clang++.exe") {
            $path = Join-Path $bin $exe
            if (-not (Test-Path $path)) { continue }
            $v = Get-FirstVersion ((& $path --version) | Select-Object -First 1)
            $family = if ($exe -like "clang*") { "clang" } else { "gcc" }
            # toolchain=<env> <family> <version> <path>
            kv toolchain "$($envName.ToUpper()) $family $v $path"
        }
        # OpenSSL/zlib as MSYS2 packages for this environment.
        $pkgPrefix = switch ($envName) {
            "ucrt64"  { "mingw-w64-ucrt-x86_64" }
            "clang64" { "mingw-w64-clang-x86_64" }
            "mingw64" { "mingw-w64-x86_64" }
        }
        $pacman = Join-Path $msys "usr\bin\pacman.exe"
        foreach ($lib in "openssl", "zlib") {
            $q = & $pacman -Q "$pkgPrefix-$lib" 2>$null
            if ($LASTEXITCODE -eq 0 -and $q) { kv lib "$($envName.ToUpper()) $lib found $(($q -split ' ')[1])" }
            elseif (Test-Path $bin) { kv lib "$($envName.ToUpper()) $lib missing" }
        }
    }
}

# --- Visual Studio: MSVC and clang-cl ------------------------------------------------------------
$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhere) {
    $instances = & $vswhere -all -products * -format json | ConvertFrom-Json
    foreach ($i in $instances) {
        $vc = Join-Path $i.installationPath "VC\Tools\MSVC"
        if (Test-Path $vc) {
            $msvcVer = (Get-ChildItem $vc -Directory | Sort-Object Name -Descending | Select-Object -First 1).Name
            # toolchain=MSVC <product line e.g. 2022> <MSVC toolset version> <VS install path>
            kv toolchain "MSVC $($i.catalog.productLineVersion) $msvcVer $($i.installationPath)"
        }
        $clangCl = Join-Path $i.installationPath "VC\Tools\Llvm\x64\bin\clang-cl.exe"
        if (Test-Path $clangCl) {
            $v = Get-FirstVersion ((& $clangCl --version) | Select-Object -First 1)
            kv toolchain "CLANGCL clang $v $clangCl"
        }
    }
} else {
    kv visual_studio "missing"
}
# A standalone LLVM install also provides clang-cl.
$llvmClangCl = Join-Path $env:ProgramFiles "LLVM\bin\clang-cl.exe"
if (Test-Path $llvmClangCl) {
    $v = Get-FirstVersion ((& $llvmClangCl --version) | Select-Object -First 1)
    kv toolchain "CLANGCL clang $v $llvmClangCl"
}

# OpenSSL/zlib for MSVC/clang-cl builds come from outside MSYS2 - vcpkg or a standalone installer.
if ($env:VCPKG_ROOT -and (Test-Path $env:VCPKG_ROOT)) {
    kv vcpkg $env:VCPKG_ROOT
    $installed = Join-Path $env:VCPKG_ROOT "installed\x64-windows\include"
    kv lib "VCPKG openssl $(if (Test-Path (Join-Path $installed 'openssl\ssl.h')) { 'found' } else { 'missing' })"
    kv lib "VCPKG zlib $(if (Test-Path (Join-Path $installed 'zlib.h')) { 'found' } else { 'missing' })"
} else {
    kv vcpkg "missing"
}
foreach ($d in "$env:ProgramFiles\OpenSSL-Win64", "$env:ProgramFiles\OpenSSL") {
    if (Test-Path (Join-Path $d "include\openssl\ssl.h")) { kv lib "STANDALONE openssl found $d" }
}

# --- Build tools on PATH -------------------------------------------------------------------------
foreach ($t in "cmake", "ninja", "git", "curl", "tar") {
    $cmd = Get-Command "$t.exe"
    if ($cmd) { kv tool "$t $(Get-FirstVersion ((& $cmd.Source --version) | Select-Object -First 1)) $($cmd.Source)" }
    else { kv tool "$t missing" }
}
# Compilers already on the plain PATH (outside an MSYS2 shell) - tells us what a bare `cmake` picks up.
foreach ($exe in "g++.exe", "clang++.exe", "cl.exe", "clang-cl.exe") {
    $cmd = Get-Command $exe
    if ($cmd) { kv path_compiler "$exe $($cmd.Source)" }
}

# --- What CppModel publishes ---------------------------------------------------------------------
if ($Offline) { kv published_status "skipped (-Offline)"; exit 0 }
try {
    $listing = (Invoke-WebRequest -Uri $BaseUrl -UseBasicParsing -TimeoutSec 20).Content
} catch {
    kv published_status "unreachable ($BaseUrl)"; exit 0
}
$files = [regex]::Matches($listing, 'CppModel-(\d+\.\d+\.\d+)-([A-Za-z0-9_.-]+?)\.(tar\.gz|zip)') |
    ForEach-Object { [pscustomobject]@{ Version = [version]$_.Groups[1].Value; Tag = $_.Groups[2].Value } }
$latest = ($files | Sort-Object Version -Descending | Select-Object -First 1).Version
kv published_status "ok"
kv latest_version "$latest"
$files | Where-Object { $_.Version -eq $latest } | Select-Object -ExpandProperty Tag -Unique | Sort-Object |
    ForEach-Object { kv published $_ }
