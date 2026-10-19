# Read-only probe used by the cppmodel:setup-environment skill: reports the Windows version,
# architecture, installed toolchains (MSVC and clang-cl; MSYS2's MinGW UCRT64/CLANG64/MINGW64, which
# use the same x64 DLL), build tools, plus which SDK builds download.cppmodel.com currently
# publishes. From SDK 0.8 the SDK is one self-contained DLL per architecture (OpenSSL and zlib
# linked in), so no libraries are probed. Installs nothing. Windows only; use
# detect-environment.sh on Linux/macOS.
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
kv arch $(switch ($arch) { "AMD64" { "x64" } "ARM64" { "ARM64" } default { $arch } })

$pms = @("winget", "choco", "scoop") | Where-Object { Get-Command $_ }
kv pkg_manager $(if ($pms) { $pms -join "," } else { "none" })

function Get-FirstVersion([string]$text) {
    if ($text -match '(\d+\.\d+(\.\d+)?)') { return $Matches[1] }
    return "unknown"
}

# --- MSYS2 / MinGW (supported on x64 with the same Windows-x64 archive) ------------------------
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
        foreach ($llvmArch in "x64", "ARM64") {
            $clangCl = Join-Path $i.installationPath "VC\Tools\Llvm\$llvmArch\bin\clang-cl.exe"
            if (Test-Path $clangCl) {
                $v = Get-FirstVersion ((& $clangCl --version) | Select-Object -First 1)
                kv toolchain "CLANGCL clang $v $clangCl"
            }
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
