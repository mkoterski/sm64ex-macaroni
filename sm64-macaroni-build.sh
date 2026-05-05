#!/bin/zsh
# sm64-macaroni-build.sh
# sm64 Macaroni — Intel Mac / macOS Tahoe build script
#
# Clones or updates one of three supported sm64ex-family upstreams, copies the
# US ROM into place, runs extract_assets.py, and compiles via gmake OSX_BUILD=1.
# The ROM is sourced from the central roms/ directory.
#
# Supported upstreams (--upstream flag):
#   sm64ex      sm64pc/sm64ex                (default; vanilla + options menu)
#   render96ex  Render96/Render96ex          (HD model/texture pack support)
#   coopdx      coop-deluxe/sm64coopdx       (online co-op + Lua mod API)
#
# Usage:
#     ./sm64-macaroni-build.sh                          # default: sm64ex
#     ./sm64-macaroni-build.sh --upstream render96ex
#     ./sm64-macaroni-build.sh --upstream coopdx
#     ./sm64-macaroni-build.sh --upstream-url <git-url> # arbitrary fork
#     ./sm64-macaroni-build.sh --skip-deps              # skip Homebrew dep check
#
# ROM layout (place file here — shared across all upstream presets):
#     roms/sm64.us.z64    🇺🇸  Super Mario 64 US
#                              SHA-1: 9BEF1128717F958171A4AFAC3ED78EE2BB4E86CE
#                              (copied to <upstream>/baserom.us.z64 by this script)
#
# Log output:
#     logs/build-<preset>-<timestamp>.log
#         e.g. build-sm64ex-20260505-1015.log
#              build-render96ex-20260505-1042.log
#              build-coopdx-20260505-1108.log
#
# CHANGELOG
#   v0.12 (2026-05-05) - Repo renamed from sm64ex-macaroni → sm64-macaroni to
#                        reflect dual-family scope. Header branding updated;
#                        no behavior change. (BUILD_FAMILY rework + Ghostship
#                        preset land in v0.13.)
#   v0.11 (2026-05-05) - Log filename now includes upstream preset
#                        (build-<preset>-<ts>.log) so multiple presets can be
#                        built in succession without their logs colliding;
#                        fixed stale "run-sm64-macaroni-macos.sh" reference in
#                        the success summary (now run-sm64-macaroni.sh)
#   v0.10 (2026-05-05) - Initial version; adapted from spmc-build.sh v0.13;
#                        gmake OSX_BUILD=1 build chain (no cmake);
#                        extract_assets.py us replaces ExtractAssets cmake target;
#                        --upstream preset table for sm64ex / render96ex / coopdx;
#                        --upstream-url escape hatch for arbitrary forks;
#                        Homebrew deps inline; ROM auto-copy

set -eo pipefail

VERSION="0.12"
SCRIPT_DIR="${0:A:h}"
ROM_SHA1="9BEF1128717F958171A4AFAC3ED78EE2BB4E86CE"

# ── Parse arguments ───────────────────────────────────────────────────────────
UPSTREAM="sm64ex"
UPSTREAM_URL_OVERRIDE=""
SKIP_DEPS=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --upstream)         UPSTREAM="$2"; shift 2 ;;
        --upstream-url)     UPSTREAM_URL_OVERRIDE="$2"; shift 2 ;;
        --skip-deps)        SKIP_DEPS=1; shift ;;
        -h|--help)
            sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
            exit 0 ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Usage: $0 [--upstream <sm64ex|render96ex|coopdx>] [--upstream-url <url>] [--skip-deps]" >&2
            exit 1 ;;
    esac
done

# ── Resolve --upstream preset → tuple ─────────────────────────────────────────
# Each preset defines:
#     UPSTREAM_LABEL       human-readable name for logs
#     UPSTREAM_GIT         default git URL (overridable via --upstream-url)
#     REPO_NAME            local clone directory name (under SCRIPT_DIR)
#     BINARY_REL           expected relative path of built binary, or "" to discover
#     EXTRA_BREW_PKGS      preset-specific Homebrew deps on top of the common base
#     EXTRA_MAKE_FLAGS     preset-specific gmake variables on top of OSX_BUILD=1
case "$UPSTREAM" in
    sm64ex)
        UPSTREAM_LABEL="sm64pc/sm64ex"
        UPSTREAM_GIT="https://github.com/sm64pc/sm64ex.git"
        REPO_NAME="sm64ex"
        BINARY_REL="build/us_pc/sm64.us.f3dex2e"
        EXTRA_BREW_PKGS=()
        EXTRA_MAKE_FLAGS=(BETTERCAMERA=1 EXT_OPTIONS_MENU=1 TEXTURE_FIX=1 EXTERNAL_DATA=1)
        ;;
    render96ex)
        UPSTREAM_LABEL="Render96/Render96ex"
        UPSTREAM_GIT="https://github.com/Render96/Render96ex.git"
        REPO_NAME="Render96ex"
        BINARY_REL="build/us_pc/sm64.us.f3dex2e"
        EXTRA_BREW_PKGS=()
        EXTRA_MAKE_FLAGS=(BETTERCAMERA=1 EXT_OPTIONS_MENU=1 TEXTURE_FIX=1 EXTERNAL_DATA=1)
        ;;
    coopdx)
        UPSTREAM_LABEL="coop-deluxe/sm64coopdx"
        UPSTREAM_GIT="https://github.com/coop-deluxe/sm64coopdx.git"
        REPO_NAME="sm64coopdx"
        BINARY_REL=""  # discovered at validation step (name varies by version)
        EXTRA_BREW_PKGS=(curl coreutils)
        EXTRA_MAKE_FLAGS=()
        ;;
    *)
        echo "❌ Unknown --upstream preset: $UPSTREAM" >&2
        echo "   Valid: sm64ex, render96ex, coopdx" >&2
        echo "   For arbitrary forks, also pass --upstream-url <git-url>" >&2
        exit 1 ;;
esac

# --upstream-url overrides only the git URL; preset still determines binary path,
# extra deps, and make flags. Use this for sm64ex-derived forks (e.g. sm64ex-alo,
# sm64ex-coop pre-coopdx) that share the sm64ex Makefile contract.
if [[ -n "$UPSTREAM_URL_OVERRIDE" ]]; then
    UPSTREAM_LABEL="$UPSTREAM (custom URL)"
    UPSTREAM_GIT="$UPSTREAM_URL_OVERRIDE"
fi

REPO_DIR="$SCRIPT_DIR/$REPO_NAME"
BUILD_DIR="$REPO_DIR/build"
ROM_SOURCE="$SCRIPT_DIR/roms/sm64.us.z64"
ROM_DEST="$REPO_DIR/baserom.us.z64"
TIMESTAMP="$(date '+%Y%m%d-%H%M')"

LOG_DIR="$SCRIPT_DIR/logs"
LOGFILE="$LOG_DIR/build-$UPSTREAM-$TIMESTAMP.log"
mkdir -p "$LOG_DIR"

echo "🔨 sm64-macaroni-build.sh v$VERSION — $(date)" | tee -a "$LOGFILE"
echo "    Upstream:    $UPSTREAM_LABEL" | tee -a "$LOGFILE"
echo "    Git URL:     $UPSTREAM_GIT" | tee -a "$LOGFILE"
echo "    Repo dir:    $REPO_DIR" | tee -a "$LOGFILE"
echo "    Make flags:  OSX_BUILD=1 ${EXTRA_MAKE_FLAGS[*]}" | tee -a "$LOGFILE"
echo "    Log:         $LOGFILE" | tee -a "$LOGFILE"

# ── Step 1: Homebrew deps (skippable) ─────────────────────────────────────────
# Common base is installed by sm64-macaroni-initial-setup.sh; this step is a
# safety net plus the slot for preset-specific extras (e.g. curl/coreutils for
# coopdx). Re-running brew install on already-installed packages is cheap.
if (( ! SKIP_DEPS )); then
    echo "" | tee -a "$LOGFILE"
    echo "📦 Step 1: Homebrew dependencies" | tee -a "$LOGFILE"
    if ! command -v brew &>/dev/null; then
        echo "    ❌ Homebrew not found. Run ./sm64-macaroni-initial-setup.sh first." | tee -a "$LOGFILE"
        exit 1
    fi
    BREW_PKGS=(
        gcc make audiofile
        sdl2 glew glfw
        pkg-config dylibbundler
        python3 git
    )
    BREW_PKGS+=("${EXTRA_BREW_PKGS[@]}")
    for pkg in "${BREW_PKGS[@]}"; do
        if ! brew list --versions "$pkg" &>/dev/null; then
            echo "    Installing $pkg..." | tee -a "$LOGFILE"
            brew install "$pkg" 2>&1 | tee -a "$LOGFILE"
        else
            echo "    ✅ $(brew list --versions "$pkg")" | tee -a "$LOGFILE"
        fi
    done
else
    echo "" | tee -a "$LOGFILE"
    echo "📦 Step 1: Skipped (--skip-deps)" | tee -a "$LOGFILE"
fi

# ── Step 2: Xcode CLT ─────────────────────────────────────────────────────────
echo "" | tee -a "$LOGFILE"
echo "🔧 Step 2: Xcode CLT" | tee -a "$LOGFILE"
if ! xcode-select -p &>/dev/null; then
    echo "    ❌ Xcode Command Line Tools not found." | tee -a "$LOGFILE"
    echo "       Run: xcode-select --install  then re-run this script." | tee -a "$LOGFILE"
    exit 1
fi
echo "    ✅ $(xcode-select -p)" | tee -a "$LOGFILE"

# ── Step 3: gmake availability ────────────────────────────────────────────────
# macOS ships GNU make 3.81 as /usr/bin/make — too old for sm64ex (requires
# 4.x). Homebrew's make package provides /usr/local/bin/gmake (GNU make 4.x).
# The Makefile uses 4.x-only constructs (.SECONDEXPANSION recipes, etc.).
echo "" | tee -a "$LOGFILE"
echo "🔧 Step 3: gmake (GNU make 4.x)" | tee -a "$LOGFILE"
if ! command -v gmake &>/dev/null; then
    echo "    ❌ gmake not found. The Homebrew 'make' package provides it." | tee -a "$LOGFILE"
    echo "       Run: brew install make  then re-run this script." | tee -a "$LOGFILE"
    exit 1
fi
echo "    ✅ $(gmake --version | head -1)" | tee -a "$LOGFILE"

# ── Step 4: Clone or update ───────────────────────────────────────────────────
# Check for Makefile — not just the directory — to detect stale/empty clones.
echo "" | tee -a "$LOGFILE"
echo "📥 Step 4: Clone / update $UPSTREAM_LABEL" | tee -a "$LOGFILE"
if [[ ! -f "$REPO_DIR/Makefile" ]]; then
    [[ -d "$REPO_DIR" ]] && echo "    ⚠️  Repo dir exists but Makefile missing — removing and re-cloning..." | tee -a "$LOGFILE"
    rm -rf "$REPO_DIR"
    echo "    Cloning $UPSTREAM_GIT..." | tee -a "$LOGFILE"
    git clone --recursive "$UPSTREAM_GIT" "$REPO_DIR" 2>&1 | tee -a "$LOGFILE"
else
    echo "    Repo exists — pulling latest..." | tee -a "$LOGFILE"
    git -C "$REPO_DIR" pull --recurse-submodules 2>&1 | tee -a "$LOGFILE"
    git -C "$REPO_DIR" submodule update --init --recursive 2>&1 | tee -a "$LOGFILE"
fi
echo "    ✅ $(git -C "$REPO_DIR" rev-parse --short HEAD) on $(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD)" | tee -a "$LOGFILE"

# ── Step 5: ROM ───────────────────────────────────────────────────────────────
# All sm64ex-family Makefiles expect baserom.us.z64 at the upstream repo root.
# The wrapper repo keeps the ROM in roms/ (gitignored, shared across builds).
echo "" | tee -a "$LOGFILE"
echo "🎮 Step 5: ROM" | tee -a "$LOGFILE"
if [[ -f "$ROM_DEST" ]]; then
    echo "    ✅ ROM already in place: $(du -h "$ROM_DEST" | cut -f1)" | tee -a "$LOGFILE"
elif [[ -f "$ROM_SOURCE" ]]; then
    echo "    📋 Copying ROM from roms/ → $REPO_NAME/baserom.us.z64..." | tee -a "$LOGFILE"
    cp "$ROM_SOURCE" "$ROM_DEST"
    echo "    ✅ ROM copied: $(du -h "$ROM_DEST" | cut -f1)" | tee -a "$LOGFILE"
else
    echo "    ❌ ROM not found. Place it at:" | tee -a "$LOGFILE"
    echo "       $ROM_SOURCE  ← recommended (central roms/ dir)" | tee -a "$LOGFILE"
    echo "       SHA-1: $ROM_SHA1 (US, .z64 format only)" | tee -a "$LOGFILE"
    exit 1
fi

# ── Step 6: Extract assets ────────────────────────────────────────────────────
# extract_assets.py reads baserom.us.z64 and writes raw asset files into the
# repo's actors/, levels/, sound/, textures/ trees. Re-running is idempotent
# but slow (~30-60s); we cache by checking for one of the canonical extracted
# files. Some forks may rename or relocate this script — fall back to make
# extract_assets if the .py is missing.
echo "" | tee -a "$LOGFILE"
echo "📦 Step 6: Extract assets from ROM" | tee -a "$LOGFILE"
EXTRACT_MARKER="$REPO_DIR/sound/sound_data.ctl.inc.c"
if [[ -f "$EXTRACT_MARKER" ]]; then
    echo "    ✅ Assets already extracted (sound_data.ctl.inc.c present)" | tee -a "$LOGFILE"
    echo "       (Run gmake distclean inside $REPO_NAME/ to force re-extraction)" | tee -a "$LOGFILE"
elif [[ -x "$REPO_DIR/extract_assets.py" ]]; then
    echo "    Running ./extract_assets.py us..." | tee -a "$LOGFILE"
    (cd "$REPO_DIR" && ./extract_assets.py us) 2>&1 | tee -a "$LOGFILE"
elif [[ -f "$REPO_DIR/extract_assets.py" ]]; then
    echo "    Running python3 extract_assets.py us..." | tee -a "$LOGFILE"
    (cd "$REPO_DIR" && python3 extract_assets.py us) 2>&1 | tee -a "$LOGFILE"
else
    echo "    ⚠️  extract_assets.py not found — relying on Makefile to extract." | tee -a "$LOGFILE"
fi

# ── Step 7: Build ─────────────────────────────────────────────────────────────
# OSX_BUILD=1 enables the macOS-specific paths in the upstream Makefile (links
# against Homebrew SDL2/GLEW/GLFW, uses gcc-from-Homebrew rather than Apple
# clang for the audio code that needs gnu99 dialect, etc.).
echo "" | tee -a "$LOGFILE"
echo "🔨 Step 7: Build  ($(sysctl -n hw.logicalcpu) cores)" | tee -a "$LOGFILE"
echo "    gmake OSX_BUILD=1 ${EXTRA_MAKE_FLAGS[*]} -j$(sysctl -n hw.logicalcpu)" | tee -a "$LOGFILE"
(cd "$REPO_DIR" && gmake OSX_BUILD=1 "${EXTRA_MAKE_FLAGS[@]}" -j"$(sysctl -n hw.logicalcpu)") 2>&1 | tee -a "$LOGFILE"

# ── Step 8: Binary validation ─────────────────────────────────────────────────
# sm64ex / Render96ex name the binary build/us_pc/sm64.us.f3dex2e (region +
# microcode encoded in the filename). sm64coopdx may use sm64coopdx instead.
# Fall back to a discovery loop covering the common candidates.
echo "" | tee -a "$LOGFILE"
echo "🔍 Step 8: Validate binary" | tee -a "$LOGFILE"
BINARY=""
CANDIDATES=()
[[ -n "$BINARY_REL" ]] && CANDIDATES+=("$REPO_DIR/$BINARY_REL")
CANDIDATES+=(
    "$REPO_DIR/build/us_pc/sm64.us.f3dex2e"
    "$REPO_DIR/build/us_pc/sm64coopdx"
    "$REPO_DIR/build/us_pc/sm64ex"
)
for candidate in "${CANDIDATES[@]}"; do
    if [[ -f "$candidate" ]]; then
        BINARY="$candidate"
        break
    fi
done

if [[ -z "$BINARY" ]]; then
    echo "    ❌ Binary not found in $REPO_NAME/build/" | tee -a "$LOGFILE"
    echo "       Build dir contents:" | tee -a "$LOGFILE"
    ls -lh "$BUILD_DIR/us_pc" 2>/dev/null | head -20 | tee -a "$LOGFILE"
    echo "       Check log: $LOGFILE" | tee -a "$LOGFILE"
    exit 1
fi
chmod +x "$BINARY"
echo "    ✅ Binary: $(file "$BINARY" | grep -o 'Mach-O.*')" | tee -a "$LOGFILE"
echo "    ✅ Path:   $BINARY" | tee -a "$LOGFILE"
echo "    ✅ Size:   $(du -h "$BINARY" | cut -f1)" | tee -a "$LOGFILE"
echo "    ✅ Built:  $(stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "$BINARY")" | tee -a "$LOGFILE"

# ── Summary ───────────────────────────────────────────────────────────────────
echo "" | tee -a "$LOGFILE"
echo "════════════════════════════════════════════════════════════════" | tee -a "$LOGFILE"
echo "✅ sm64-macaroni-build.sh v$VERSION complete!" | tee -a "$LOGFILE"
echo "    🎯 Upstream: $UPSTREAM_LABEL" | tee -a "$LOGFILE"
echo "    📍 $BINARY" | tee -a "$LOGFILE"
echo "    📄 $LOGFILE" | tee -a "$LOGFILE"
echo "    👉 ./run-sm64-macaroni.sh                       # launch latest build" | tee -a "$LOGFILE"
echo "    👉 ./sm64-macaroni-bundle.sh --upstream $UPSTREAM   # wrap into .app" | tee -a "$LOGFILE"
echo "════════════════════════════════════════════════════════════════" | tee -a "$LOGFILE"
