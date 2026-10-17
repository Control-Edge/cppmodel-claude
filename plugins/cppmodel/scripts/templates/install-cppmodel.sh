#!/usr/bin/env bash
# Template: copy this into a CppModel project (e.g. as scripts/install-cppmodel.sh) and commit
# it - it's meant to be run by that project's own developers and CI, not invoked from the plugin.
# Covers Linux and macOS; use install-cppmodel.ps1 on Windows.
#
# Installs CppModel SDK 0.8 or later: one self-contained archive per OS and architecture
# (CppModel-<version>-Linux-x86_64.tar.gz, -Linux-aarch64.tar.gz, -macOS-universal.tar.gz), the
# same for every compiler. The project finds it with find_package(cppmodel) (CMAKE_PREFIX_PATH).
#
# Env overrides: DEPS_DIR, BASE_URL, VERSION (default "latest"), ARCH, OS_NAME.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DEPS_DIR="${DEPS_DIR:-$PROJECT_ROOT/dependencies}"
BASE_URL="${BASE_URL:-https://download.cppmodel.com/}"
VERSION="${VERSION:-latest}"
ARCH="${ARCH:-$(uname -m)}"
OS_NAME="${OS_NAME:-$(uname -s)}"

if [[ -n "${COMPILER:-}" ]]; then
    echo "Note: COMPILER is ignored - from SDK 0.8 one archive serves every compiler." >&2
fi

if [[ "$VERSION" != "latest" ]]; then
    major="${VERSION%%.*}"
    minor="$(cut -d. -f2 <<<"$VERSION")"
    if [[ "$major" == "0" && "$minor" -lt 8 ]]; then
        echo "VERSION=$VERSION: this script installs SDK 0.8 or later; older SDKs were packaged per compiler." >&2
        exit 1
    fi
fi

case "$OS_NAME" in
    Linux)
        [[ "$ARCH" == "arm64" ]] && ARCH="aarch64"
        case "$ARCH" in
            x86_64|aarch64) ;;
            *) echo "No CppModel SDK for Linux on '$ARCH' (published: x86_64, aarch64). Set ARCH to override." >&2; exit 1 ;;
        esac
        PLATFORM_TAG="Linux-${ARCH}"
        ;;
    Darwin)
        # One universal archive (arm64 + x86_64, macOS 11+).
        PLATFORM_TAG="macOS-universal"
        ;;
    *)
        echo "Unsupported OS '$OS_NAME'. This script supports Linux and macOS; use install-cppmodel.ps1 on Windows." >&2
        exit 1
        ;;
esac

# Resolve "latest" to the newest version listed for this platform, so the install reports a real
# version; fall back to the CppModel-latest-* alias if the listing can't be read.
if [[ "$VERSION" == "latest" ]]; then
    listing="$(curl -fsSL --max-time 20 "$BASE_URL" 2>/dev/null || true)"
    resolved="$(grep -oE "CppModel-[0-9]+\.[0-9]+\.[0-9]+-${PLATFORM_TAG}\.tar\.gz" <<<"$listing" |
        sed -E 's/^CppModel-([0-9]+\.[0-9]+\.[0-9]+)-.*/\1/' | sort -uV | tail -1 || true)"
    [[ -n "$resolved" ]] && VERSION="$resolved"
fi

ARCHIVE="CppModel-${VERSION}-${PLATFORM_TAG}.tar.gz"
echo "Target platform: $PLATFORM_TAG (version: $VERSION)"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
echo "Downloading $ARCHIVE ..."
curl -fL -o "$TMP_DIR/$ARCHIVE" "${BASE_URL}${ARCHIVE}"

STAGING_DIR="$TMP_DIR/staging"
mkdir -p "$STAGING_DIR"
tar -xzf "$TMP_DIR/$ARCHIVE" -C "$STAGING_DIR"

# The archive holds a single top-level CppModel-<version>-<platform> folder; install its contents.
CONTENT_DIR="$STAGING_DIR"
TOP_ENTRIES=("$STAGING_DIR"/*)
if [[ ${#TOP_ENTRIES[@]} -eq 1 && -d "${TOP_ENTRIES[0]}" ]]; then
    CONTENT_DIR="${TOP_ENTRIES[0]}"
fi

rm -rf "$DEPS_DIR"
mkdir -p "$DEPS_DIR"
cp -a "$CONTENT_DIR"/. "$DEPS_DIR"/

INSTALLED="$(sed -nE 's/^set\(PACKAGE_VERSION "([^"]+)"\)$/\1/p' "$DEPS_DIR/lib/cmake/cppmodel/cppmodelConfigVersion.cmake" 2>/dev/null | head -1 || true)"
echo "Installed CppModel ${INSTALLED:-$VERSION} into $DEPS_DIR"
