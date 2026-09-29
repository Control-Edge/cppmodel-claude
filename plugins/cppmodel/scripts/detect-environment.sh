#!/usr/bin/env bash
# Read-only probe used by the cppmodel:setup-environment skill: reports the OS, architecture,
# installed C++ compilers, build tools, and the libraries CppModel links against (OpenSSL, zlib),
# plus which SDK builds download.cppmodel.com currently publishes for this OS/arch.
# Installs nothing. Covers Linux and macOS; use detect-environment.ps1 on Windows.
#
# Output is one "key=value" per line so it's easy to read back. Repeated keys (compiler=,
# published=) list one item each.
#
# Env overrides: BASE_URL (default https://download.cppmodel.com/), OFFLINE=1 to skip the listing.
set -uo pipefail

BASE_URL="${BASE_URL:-https://download.cppmodel.com/}"

kv() { printf '%s=%s\n' "$1" "$2"; }

# --- OS / arch -----------------------------------------------------------------------------------
uname_s="$(uname -s)"
arch="$(uname -m)"
case "$uname_s" in
    Linux)  os="Linux" ;;
    Darwin) os="macOS" ;;
    MINGW*|MSYS*|CYGWIN*)
        kv os "Windows"
        kv note "Running under an MSYS2/Git Bash/Cygwin shell - run detect-environment.ps1 from PowerShell instead for a complete Windows report."
        exit 0
        ;;
    *) os="$uname_s" ;;
esac
[[ "$arch" == "arm64" && "$os" == "Linux" ]] && arch="aarch64"
kv os "$os"
kv arch "$arch"

if [[ "$os" == "Linux" ]]; then
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        kv os_pretty "${PRETTY_NAME:-unknown}"
        kv os_id "${ID:-unknown}"
        kv os_id_like "${ID_LIKE:-}"
        kv os_version "${VERSION_ID:-unknown}"
    fi
    if grep -qi microsoft /proc/version 2>/dev/null; then kv wsl "1"; else kv wsl "0"; fi
elif [[ "$os" == "macOS" ]]; then
    kv os_pretty "macOS $(sw_vers -productVersion 2>/dev/null || echo unknown)"
    kv os_version "$(sw_vers -productVersion 2>/dev/null || echo unknown)"
fi

pm=""
for c in apt-get dnf yum zypper pacman apk brew; do
    if command -v "$c" >/dev/null 2>&1; then pm="$c"; break; fi
done
kv pkg_manager "${pm:-none}"

# --- Compilers -----------------------------------------------------------------------------------
# Every g++/clang++ on PATH, versioned or not (g++-12, clang++-18, ...), deduplicated by resolved path.
declare -A seen=()
compiler_line() {
    local exe="$1" real out family version
    real="$(readlink -f "$(command -v "$exe")" 2>/dev/null || command -v "$exe")"
    [[ -n "${seen[$real]:-}" ]] && return
    seen[$real]=1
    out="$("$exe" --version 2>/dev/null | head -1)" || return
    if [[ "$out" == *"Apple clang"* ]]; then
        family="appleclang"
        version="$(sed -E 's/.*version ([0-9.]+).*/\1/' <<<"$out")"
    elif [[ "$out" == *clang* ]]; then
        family="clang"
        version="$(sed -E 's/.*clang version ([0-9.]+).*/\1/' <<<"$out")"
    else
        family="gcc"
        version="$("$exe" -dumpfullversion -dumpversion 2>/dev/null | head -1)"
    fi
    # family major full-version path
    kv compiler "$family ${version%%.*} $version $(command -v "$exe")"
}
# Glob PATH dirs directly instead of `compgen -c`: under WSL, PATH carries the Windows drives
# (/mnt/c/...), which are slow to list and hold only Windows executables - skip them.
IFS=: read -ra path_dirs <<<"$PATH"
while IFS= read -r exe; do
    compiler_line "$exe"
done < <(
    for d in "${path_dirs[@]}"; do
        [[ "$d" =~ ^/mnt/[a-z]/ || ! -d "$d" ]] && continue
        for f in "$d"/g++ "$d"/g++-* "$d"/clang++ "$d"/clang++-*; do
            [[ -x "$f" ]] && basename "$f"
        done
    done | grep -E '^(g\+\+|clang\+\+)(-[0-9]+(\.[0-9]+)*)?$' | sort -u
)

if command -v c++ >/dev/null 2>&1; then
    kv default_cxx "$(readlink -f "$(command -v c++)" 2>/dev/null || command -v c++)"
fi

# --- Build tools ---------------------------------------------------------------------------------
tool_line() {
    local name="$1" v
    if command -v "$name" >/dev/null 2>&1; then
        local flag="--version"
        [[ "$name" == unzip ]] && flag="-v"
        v="$("$name" "$flag" 2>/dev/null | head -1 | grep -oE '[0-9]+(\.[0-9]+)+' | head -1)"
        kv tool "$name ${v:-unknown}"
    else
        kv tool "$name missing"
    fi
}
for t in cmake ninja make git curl tar unzip; do tool_line "$t"; done

# --- Libraries (OpenSSL + zlib - CppModel's client libraries link against both) ------------------
include_dirs=(/usr/include /usr/local/include)
if [[ "$os" == "macOS" ]] && command -v brew >/dev/null 2>&1; then
    include_dirs+=("$(brew --prefix openssl@3 2>/dev/null)/include" "$(brew --prefix zlib 2>/dev/null)/include" "$(brew --prefix)/include")
fi
if [[ "$os" == "macOS" ]] && command -v xcrun >/dev/null 2>&1; then
    include_dirs+=("$(xcrun --show-sdk-path 2>/dev/null)/usr/include")
fi
lib_line() {
    local name="$1" header="$2" pc="$3" d v
    for d in "${include_dirs[@]}"; do
        if [[ -f "$d/$header" ]]; then
            v=""
            command -v pkg-config >/dev/null 2>&1 && v="$(pkg-config --modversion "$pc" 2>/dev/null)"
            kv lib "$name found ${v:-version-unknown} $d/$header"
            return
        fi
    done
    kv lib "$name missing"
}
lib_line openssl openssl/ssl.h openssl
lib_line zlib zlib.h zlib

# --- What CppModel publishes for this OS/arch ----------------------------------------------------
if [[ "${OFFLINE:-0}" == "1" ]]; then
    kv published_status "skipped (OFFLINE=1)"
    exit 0
fi
listing="$(curl -fsSL --max-time 20 "$BASE_URL" 2>/dev/null)"
if [[ -z "$listing" ]]; then
    kv published_status "unreachable ($BASE_URL)"
    exit 0
fi
files="$(grep -oE 'CppModel-[0-9]+\.[0-9]+\.[0-9]+-[A-Za-z0-9_.-]+\.(tar\.gz|zip)' <<<"$listing" | sort -u)"
latest="$(sed -E 's/^CppModel-([0-9]+\.[0-9]+\.[0-9]+)-.*/\1/' <<<"$files" | sort -uV | tail -1)"
kv published_status "ok"
kv latest_version "$latest"
# Every platform tag published for the latest version, all OSes - the skill filters and explains.
sed -nE "s/^CppModel-${latest//./\\.}-(.+)\.(tar\.gz|zip)$/\1/p" <<<"$files" | while IFS= read -r tag; do
    kv published "$tag"
done
