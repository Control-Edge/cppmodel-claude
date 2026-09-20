#!/usr/bin/env bash
# Template: copy this into a CppModel project (e.g. as scripts/install-cppmodel.sh) and commit
# it - it's meant to be run by that project's own developers and CI, not invoked from the plugin.
# Covers Linux and macOS; use install-cppmodel.ps1 on Windows.
#
# Env overrides: DEPS_DIR, BASE_URL, VERSION (default "latest"), ARCH, COMPILER (Linux only),
# OS_NAME.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DEPS_DIR="${DEPS_DIR:-$PROJECT_ROOT/dependencies}"
BASE_URL="${BASE_URL:-https://download.cppmodel.com/}"
VERSION="${VERSION:-latest}"
ARCH="${ARCH:-$(uname -m)}"
COMPILER="${COMPILER:-}"
OS_NAME="${OS_NAME:-$(uname -s)}"

case "$OS_NAME" in
    Linux)
        OS_TAG="Linux"
        case "$ARCH" in
            x86_64|aarch64) ;;
            *) echo "Unsupported arch '$ARCH' for Linux. Set ARCH=x86_64|aarch64." >&2; exit 1 ;;
        esac

        if [[ -z "$COMPILER" ]]; then
            cxx="$(command -v c++ || command -v g++ || command -v clang++ || true)"
            if [[ "$cxx" == *clang* ]]; then
                COMPILER="clang21"
            elif [[ -n "$cxx" ]]; then
                ver="$("$cxx" -dumpversion 2>/dev/null | cut -d. -f1)"
                case "$ver" in
                    12) COMPILER="gcc12" ;;
                    16) COMPILER="gcc16" ;;
                    *)
                        echo "Detected gcc major version '$ver', no published archive for it." >&2
                        echo "Set COMPILER=gcc12|gcc16|clang21, or check https://download.cppmodel.com/ for what's currently published." >&2
                        exit 1
                        ;;
                esac
            else
                echo "Could not detect compiler. Set COMPILER=gcc12|gcc16|clang21." >&2
                exit 1
            fi
        fi

        PLATFORM_TAG="${OS_TAG}-${ARCH}-${COMPILER}"
        ;;
    Darwin)
        # macOS archives have no compiler suffix - just OS and arch.
        OS_TAG="macOS"
        case "$ARCH" in
            x86_64|arm64) ;;
            *) echo "Unsupported arch '$ARCH' for macOS. Set ARCH=x86_64|arm64." >&2; exit 1 ;;
        esac

        PLATFORM_TAG="${OS_TAG}-${ARCH}"
        ;;
    *)
        echo "Unsupported OS '$OS_NAME'. This script supports Linux and macOS; use install-cppmodel.ps1 on Windows." >&2
        exit 1
        ;;
esac

ARCHIVE="CppModel-${VERSION}-${PLATFORM_TAG}.tar.gz"
echo "Target platform: $PLATFORM_TAG (version: $VERSION)"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
echo "Downloading $ARCHIVE ..."
curl -fL -o "$TMP_DIR/$ARCHIVE" "${BASE_URL}${ARCHIVE}"

STAGING_DIR="$TMP_DIR/staging"
mkdir -p "$STAGING_DIR"
tar -xzf "$TMP_DIR/$ARCHIVE" -C "$STAGING_DIR"

# Archive layout has changed across releases (some ship a single top-level version folder,
# older ones ship flat) - handle both rather than assuming one.
CONTENT_DIR="$STAGING_DIR"
TOP_ENTRIES=("$STAGING_DIR"/*)
if [[ ${#TOP_ENTRIES[@]} -eq 1 && -d "${TOP_ENTRIES[0]}" ]]; then
    CONTENT_DIR="${TOP_ENTRIES[0]}"
fi

rm -rf "$DEPS_DIR"
mkdir -p "$DEPS_DIR"
cp -a "$CONTENT_DIR"/. "$DEPS_DIR"/

echo "Installed CppModel $VERSION into $DEPS_DIR"
