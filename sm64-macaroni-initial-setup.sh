#!/bin/zsh
# sm64-macaroni-initial-setup.sh
# sm64 Macaroni — first-run setup for macOS Tahoe / Intel Mac
#
# Installs Xcode CLT, Homebrew, and the common build dependencies shared by
# all supported upstream presets across both build families:
#
#   sm64ex family       (gmake-based: sm64pc/sm64ex, Render96ex, sm64coopdx)
#   libultraship family (CMake-based: HarbourMasters/Ghostship)
#
# Common base packages:
#     gcc, make, cmake, audiofile, sdl2, glew, glfw, pkg-config,
#     dylibbundler, python3, git
#
# Validates any ROM already present in the central roms/ directory.
# Safe to re-run: all steps are idempotent.
#
# Upstream-specific extras (Lua, discord-rpc, libultraship runtime libs,
# etc.) are installed on first build by sm64-macaroni-build.sh based on the
# --upstream flag.
#
# Usage:
#     ./sm64-macaroni-initial-setup.sh
#
# Output:
#     sm64-macaroni/logs/initial-setup-<timestamp>.log
#
# ROM layout (place file here before building — shared across all upstreams):
#     roms/sm64.us.z64    🇺🇸  Super Mario 64 US
#                              SHA-1: 9BEF1128717F958171A4AFAC3ED78EE2BB4E86CE
#
# CHANGELOG
#   v0.12 (2026-05-05) - Repo renamed from sm64ex-macaroni → sm64-macaroni to
#                        reflect dual-family scope (sm64ex no longer the only
#                        target). Header branding updated; no behavior change.
#   v0.11 (2026-05-05) - Added `cmake` to common base deps in support of the
#                        libultraship build family (Ghostship preset). CMake
#                        is needed by the build script regardless of which
#                        gmake/cmake family is selected, so installing it
#                        upfront avoids a re-prompt on first Ghostship build.
#                        Updated header docs to reflect dual-family scope.
#   v0.10 (2026-05-05) - Initial version; adapted from spmc-initial-setup.sh v0.10

set -eo pipefail

VERSION="0.12"
SCRIPT_DIR="${0:A:h}"
TIMESTAMP="$(date '+%Y%m%d-%H%M')"
LOG_DIR="$SCRIPT_DIR/logs"
LOGFILE="$LOG_DIR/initial-setup-$TIMESTAMP.log"
ROM_SHA1="9BEF1128717F958171A4AFAC3ED78EE2BB4E86CE"

mkdir -p "$LOG_DIR"

echo "🛠  sm64-macaroni-initial-setup.sh v$VERSION — $(date)" | tee -a "$LOGFILE"
echo "    macOS:  $(sw_vers -productName) $(sw_vers -productVersion)" | tee -a "$LOGFILE"
echo "    Arch:   $(uname -m)" | tee -a "$LOGFILE"

# ── Architecture guard ────────────────────────────────────────────────────────
if [[ "$(uname -m)" != "x86_64" ]]; then
    echo "⚠️  Non-Intel architecture detected ($(uname -m))." | tee -a "$LOGFILE"
    echo "    This project targets Intel x86_64 Macs." | tee -a "$LOGFILE"
    echo "    On Apple Silicon, use Rosetta 2 or build a native arm64 variant." | tee -a "$LOGFILE"
fi

# ── Step 1: Xcode Command Line Tools ─────────────────────────────────────────
echo "" | tee -a "$LOGFILE"
echo "🔧 Step 1: Xcode Command Line Tools" | tee -a "$LOGFILE"
if ! xcode-select -p &>/dev/null; then
    echo "    Not found — launching installer." | tee -a "$LOGFILE"
    echo "    Complete the GUI prompt, then re-run this script." | tee -a "$LOGFILE"
    xcode-select --install
    exit 0
fi
echo "    ✅ $(xcode-select -p)" | tee -a "$LOGFILE"

# ── Step 2: Homebrew ──────────────────────────────────────────────────────────
echo "" | tee -a "$LOGFILE"
echo "🍺 Step 2: Homebrew" | tee -a "$LOGFILE"
if ! command -v brew &>/dev/null; then
    echo "    Installing Homebrew..." | tee -a "$LOGFILE"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" 2>&1 | tee -a "$LOGFILE"
    # Intel Mac: Homebrew prefix is /usr/local on all macOS versions including Tahoe
    eval "$(/usr/local/bin/brew shellenv)"
fi
echo "    ✅ $(brew --version | head -1)" | tee -a "$LOGFILE"

# ── Step 3: Homebrew packages ─────────────────────────────────────────────────
# Common base deps span both build families:
#     sm64ex family (gmake):       gcc make audiofile sdl2 glew glfw
#                                  pkg-config dylibbundler python3 git
#     libultraship family (cmake): + cmake (asset processing happens at
#                                  runtime in Ghostship, so no extra
#                                  build-time deps beyond the CMake toolchain)
#
# Upstream-specific extras (e.g. discord-rpc + lua for sm64coopdx) are added
# by sm64-macaroni-build.sh after the --upstream flag is resolved.
echo "" | tee -a "$LOGFILE"
echo "📦 Step 3: Homebrew packages" | tee -a "$LOGFILE"
BREW_PKGS=(
    gcc make cmake audiofile
    sdl2 glew glfw
    pkg-config dylibbundler
    python3 git
)
for pkg in "${BREW_PKGS[@]}"; do
    if ! brew list --versions "$pkg" &>/dev/null; then
        echo "    Installing $pkg..." | tee -a "$LOGFILE"
        brew install "$pkg" 2>&1 | tee -a "$LOGFILE"
    else
        echo "    ✅ $(brew list --versions "$pkg")" | tee -a "$LOGFILE"
    fi
done

# ── Step 4: ROM status ────────────────────────────────────────────────────────
# All supported upstreams across both families consume the same US ROM.
# sm64ex-family Makefiles read it from the upstream repo's baserom.us.z64
# at build time; Ghostship reads it from the runtime working directory at
# first launch and generates sm64.o2r from it.
echo "" | tee -a "$LOGFILE"
echo "🎮 Step 4: ROM status" | tee -a "$LOGFILE"
echo "    Checking roms/ directory: $SCRIPT_DIR/roms/" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

ROM_PATH="$SCRIPT_DIR/roms/sm64.us.z64"
if [[ -f "$ROM_PATH" ]]; then
    ACTUAL_SHA1="$(shasum -a 1 "$ROM_PATH" | awk '{print toupper($1)}')"
    if [[ "$ACTUAL_SHA1" == "$ROM_SHA1" ]]; then
        echo "    ✅ 🇺🇸  Super Mario 64 US — $(du -h "$ROM_PATH" | cut -f1)  SHA-1 OK" | tee -a "$LOGFILE"
    else
        echo "    ⚠️  🇺🇸  Super Mario 64 US — SHA-1 MISMATCH" | tee -a "$LOGFILE"
        echo "        got:      $ACTUAL_SHA1" | tee -a "$LOGFILE"
        echo "        expected: $ROM_SHA1" | tee -a "$LOGFILE"
        echo "        ROM must be US version in .z64 (big-endian) format" | tee -a "$LOGFILE"
    fi
else
    echo "    ·  🇺🇸  Super Mario 64 US — not present → roms/sm64.us.z64" | tee -a "$LOGFILE"
    echo "       SHA-1: $ROM_SHA1" | tee -a "$LOGFILE"
    echo "       Must be US version in .z64 format (convert .n64 with byteswap if needed)" | tee -a "$LOGFILE"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo "" | tee -a "$LOGFILE"
echo "════════════════════════════════════════════════════════════════" | tee -a "$LOGFILE"
echo "✅ sm64-macaroni-initial-setup.sh v$VERSION complete!" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"
echo "    Next steps:" | tee -a "$LOGFILE"
echo "      1. Place ROM in roms/sm64.us.z64 (US, .z64 format)" | tee -a "$LOGFILE"
echo "      2. ./sm64-macaroni-build.sh                       # default: sm64pc/sm64ex" | tee -a "$LOGFILE"
echo "         ./sm64-macaroni-build.sh --upstream render96ex # HD textures fork" | tee -a "$LOGFILE"
echo "         ./sm64-macaroni-build.sh --upstream coopdx     # online co-op fork" | tee -a "$LOGFILE"
echo "         ./sm64-macaroni-build.sh --upstream ghostship  # HarbourMasters port (in flight)" | tee -a "$LOGFILE"
echo "      3. ./run-sm64-macaroni.sh                         # launch latest build" | tee -a "$LOGFILE"
echo "════════════════════════════════════════════════════════════════" | tee -a "$LOGFILE"
