#!/bin/zsh
# sm64-macaroni-build.sh
# sm64 Macaroni — Intel Mac / macOS Tahoe build script
#
# Clones or updates one of the supported sm64ex-family upstreams, copies the
# US ROM into place, runs extract_assets.py, applies preset-specific source
# patches if needed, and compiles via gmake OSX_BUILD=1. The ROM is sourced
# from the central roms/ directory.
#
# Supported upstreams (--upstream flag):
#   sm64ex      sm64pc/sm64ex                (default; vanilla + options menu)
#                                            ✅ builds and runs on Tahoe
#   coopdx      coop-deluxe/sm64coopdx       (online co-op + Lua mod API;
#                                            upstream self-bundles via
#                                            OSX_APP_BUILD)
#                                            ✅ builds; runtime test pending
#   render96ex  Render96/Render96ex          (HD model/texture pack support)
#                                            ❌ broken upstream — see README
#                                            "Known issues". Patches 1–5 in
#                                            this script land cleanly but a
#                                            6th (cpp linemarker mangling)
#                                            blocks the build. Kept in place
#                                            for anyone iterating against a
#                                            different render96 fork via
#                                            --upstream-url.
#
# Usage:
#     ./sm64-macaroni-build.sh                          # default: sm64ex
#     ./sm64-macaroni-build.sh --upstream coopdx
#     ./sm64-macaroni-build.sh --upstream render96ex    # ❌ known broken
#     ./sm64-macaroni-build.sh --upstream-url <git-url> # arbitrary fork
#     ./sm64-macaroni-build.sh --skip-deps              # skip Homebrew dep check
#
# Log output:
#     logs/build-<preset>-<timestamp>.log
#
# CHANGELOG
#   v0.18 (2026-05-06) - Render96ex marked broken upstream. After 5 iterative
#                        fixes (v0.14–v0.17) the next failure surfaced inside
#                        a silenced Makefile rule that emits malformed
#                        generated headers due to cpp-15 linemarker output
#                        differences from cpp-9. The dependency chain of
#                        upstream-specific patches needed to bring render96ex
#                        up on Tahoe makes this wrapper effectively a fork
#                        of a fork — outside the scope of what these scripts
#                        should be doing.
#                        Behavior: a warning block prints before Step 1 when
#                        --upstream render96ex is selected, with workaround
#                        guidance. The build still attempts to run (does not
#                        bail) so anyone iterating against a different
#                        render96 fork via --upstream-url benefits from
#                        Patches 1–5 already in Step 6.5.
#                        sm64ex and coopdx unaffected.
#   v0.17 (2026-05-05) - CPATH=/usr/local/include export for render96ex to
#                        resolve <SDL2/SDL.h> against Homebrew's
#                        -I/usr/local/include/SDL2 cflags layout.
#   v0.16 (2026-05-05) - Detect highest-numbered cpp-N from /usr/local/bin
#                        and pass as `CPP=cpp-N` to override render96ex's
#                        Makefile hardcode of cpp-9.
#   v0.15 (2026-05-05) - Patch 1 rewritten with sm64-macaroni-owned sentinel
#                        comment (false-positive in v0.14's grep).
#   v0.14 (2026-05-05) - Added Step 6.5: render96ex-specific source patches
#                        (3 total) for Tahoe-era clang.
#   v0.13 (2026-05-05) - Extended binary discovery to include upstream-created
#                        .app bundles (coopdx OSX_APP_BUILD pattern).
#   v0.12 (2026-05-05) - Repo renamed sm64ex-macaroni → sm64-macaroni.
#   v0.11 (2026-05-05) - Log filename includes upstream preset.
#   v0.10 (2026-05-05) - Initial version; adapted from spmc-build.sh v0.13.

set -eo pipefail

VERSION="0.18"
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
            echo "Usage: $0 [--upstream <sm64ex|coopdx|render96ex>] [--upstream-url <url>] [--skip-deps]" >&2
            exit 1 ;;
    esac
done

# ── Resolve --upstream preset → tuple ─────────────────────────────────────────
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
        BINARY_REL="build/us_pc/sm64coopdx.app/Contents/MacOS/sm64coopdx"
        EXTRA_BREW_PKGS=(curl coreutils)
        EXTRA_MAKE_FLAGS=()
        ;;
    *)
        echo "❌ Unknown --upstream preset: $UPSTREAM" >&2
        echo "   Valid: sm64ex, coopdx, render96ex" >&2
        echo "   For arbitrary forks, also pass --upstream-url <git-url>" >&2
        exit 1 ;;
esac

if [[ -n "$UPSTREAM_URL_OVERRIDE" ]]; then
    UPSTREAM_LABEL="$UPSTREAM (custom URL)"
    UPSTREAM_GIT="$UPSTREAM_URL_OVERRIDE"
fi

# ── Render96ex CPP detection ─────────────────────────────────────────────────
if [[ "$UPSTREAM" == "render96ex" ]]; then
    DETECTED_CPP="$(ls /usr/local/bin/cpp-* 2>/dev/null | grep -E '/cpp-[0-9]+$' | sort -V | tail -1)"
    if [[ -n "$DETECTED_CPP" ]]; then
        DETECTED_CPP_BASENAME="$(basename "$DETECTED_CPP")"
        EXTRA_MAKE_FLAGS+=("CPP=$DETECTED_CPP_BASENAME")
    fi
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

# ── Render96ex broken-upstream warning ───────────────────────────────────────
# Show this prominently before Step 1 so the user can ctrl-C if they didn't
# realize what they were getting into. Don't bail outright — anyone passing
# --upstream-url to point at a different render96 fork still benefits from
# the Step 6.5 patches.
if [[ "$UPSTREAM" == "render96ex" ]] && [[ -z "$UPSTREAM_URL_OVERRIDE" ]]; then
    echo "" | tee -a "$LOGFILE"
    echo "⚠️  ════════════════════════════════════════════════════════════════" | tee -a "$LOGFILE"
    echo "    Render96/Render96ex is known broken on macOS Tahoe." | tee -a "$LOGFILE"
    echo "    The fork's macOS support is unmaintained; 5 iterative patches" | tee -a "$LOGFILE"
    echo "    (Steps 6.5, CPP=, CPATH=) clear earlier failures but a 6th" | tee -a "$LOGFILE"
    echo "    issue (cpp-15 linemarker output mangling generated headers)" | tee -a "$LOGFILE"
    echo "    blocks the build. See README.md → Known issues." | tee -a "$LOGFILE"
    echo "" | tee -a "$LOGFILE"
    echo "    Workarounds:" | tee -a "$LOGFILE"
    echo "      • For HD textures: use the default sm64ex preset with a" | tee -a "$LOGFILE"
    echo "        Render96 texture pack drop-in. EXTERNAL_DATA=1 is on." | tee -a "$LOGFILE"
    echo "      • For a different render96 fork: re-run this script with" | tee -a "$LOGFILE"
    echo "        --upstream-url <git-url-of-fork>" | tee -a "$LOGFILE"
    echo "" | tee -a "$LOGFILE"
    echo "    Continuing in 5 seconds. Ctrl-C to abort." | tee -a "$LOGFILE"
    echo "    ════════════════════════════════════════════════════════════════" | tee -a "$LOGFILE"
    sleep 5
fi

if [[ "$UPSTREAM" == "render96ex" ]]; then
    if [[ -n "${DETECTED_CPP:-}" ]]; then
        echo "    Detected CPP: $DETECTED_CPP (overriding Makefile's hardcoded cpp-9)" | tee -a "$LOGFILE"
    else
        echo "    ⚠️  No cpp-N found under /usr/local/bin/. Build will likely fail with" | tee -a "$LOGFILE"
        echo "       'cpp-9: command not found' from render96ex's Makefile.split." | tee -a "$LOGFILE"
        echo "       Fix: brew install gcc  (or any cpp-N from Homebrew's gcc package)" | tee -a "$LOGFILE"
    fi
fi

# ── Step 1: Homebrew deps (skippable) ─────────────────────────────────────────
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
echo "" | tee -a "$LOGFILE"
echo "🔧 Step 3: gmake (GNU make 4.x)" | tee -a "$LOGFILE"
if ! command -v gmake &>/dev/null; then
    echo "    ❌ gmake not found. The Homebrew 'make' package provides it." | tee -a "$LOGFILE"
    echo "       Run: brew install make  then re-run this script." | tee -a "$LOGFILE"
    exit 1
fi
echo "    ✅ $(gmake --version | head -1)" | tee -a "$LOGFILE"

# ── Step 4: Clone or update ───────────────────────────────────────────────────
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

# ── Step 6.5: Render96ex source patches (Tahoe-clang compatibility) ──────────
SM64M_SENTINEL_1="/* sm64-macaroni: Tahoe-clang stdio.h fix — v0.15 */"

apply_render96ex_patches() {
    local patched=0

    # Patch 1: aiff_extract_codebook.c needs <stdio.h> BEFORE _XOPEN_SOURCE 500
    local aiff="$REPO_DIR/tools/aiff_extract_codebook.c"
    if [[ -f "$aiff" ]] && ! grep -qF "$SM64M_SENTINEL_1" "$aiff"; then
        echo "    Original head of aiff_extract_codebook.c:" | tee -a "$LOGFILE"
        head -3 "$aiff" | sed 's/^/      ▸ /' | tee -a "$LOGFILE"
        {
            echo "$SM64M_SENTINEL_1"
            echo "#include <stdio.h>"
            cat "$aiff"
        } > "$aiff.tmp" && mv "$aiff.tmp" "$aiff"
        echo "    ✅ Patched: tools/aiff_extract_codebook.c (+#include <stdio.h>)" | tee -a "$LOGFILE"
        patched=$((patched + 1))
    elif [[ -f "$aiff" ]]; then
        echo "    · Skipped (sentinel present): tools/aiff_extract_codebook.c" | tee -a "$LOGFILE"
    fi

    # Patch 2: exoquant.c uses Linux <malloc.h>
    local exoquant="$REPO_DIR/tools/n64graphics_ci_dir/exoquant/exoquant.c"
    if [[ -f "$exoquant" ]] && grep -q '#include <malloc.h>' "$exoquant"; then
        sed -i '' 's|#include <malloc.h>|#include <stdlib.h>|' "$exoquant"
        echo "    ✅ Patched: tools/n64graphics_ci_dir/exoquant/exoquant.c (<malloc.h> → <stdlib.h>)" | tee -a "$LOGFILE"
        patched=$((patched + 1))
    elif [[ -f "$exoquant" ]]; then
        echo "    · Skipped (already patched): tools/n64graphics_ci_dir/exoquant/exoquant.c" | tee -a "$LOGFILE"
    fi

    # Patch 3: tools/Makefile — tabledesign depends on libaudiofile.a
    local toolsmk="$REPO_DIR/tools/Makefile"
    local sentinel3="# sm64-macaroni: tabledesign-audiofile order fix"
    if [[ -f "$toolsmk" ]] && ! grep -qF "$sentinel3" "$toolsmk"; then
        cat >> "$toolsmk" << 'MAKEPATCH'

# sm64-macaroni: tabledesign-audiofile order fix
# Force tabledesign to wait for libaudiofile.a before linking. Without this,
# `gmake -jN` can race the linker against an unbuilt static library on macOS.
tabledesign: audiofile/libaudiofile.a
MAKEPATCH
        echo "    ✅ Patched: tools/Makefile (tabledesign depends on libaudiofile.a)" | tee -a "$LOGFILE"
        patched=$((patched + 1))
    elif [[ -f "$toolsmk" ]]; then
        echo "    · Skipped (already patched): tools/Makefile" | tee -a "$LOGFILE"
    fi

    if (( patched > 0 )); then
        echo "    📝 Applied $patched render96ex patch(es) for Tahoe-clang compatibility" | tee -a "$LOGFILE"
        echo "    🧹 Cleaning tools/ to force rebuild from patched sources..." | tee -a "$LOGFILE"
        (cd "$REPO_DIR/tools" && gmake clean 2>&1 | tee -a "$LOGFILE") || true
    fi
}

if [[ "$UPSTREAM" == "render96ex" ]]; then
    echo "" | tee -a "$LOGFILE"
    echo "🩹 Step 6.5: Render96ex Tahoe-clang patches" | tee -a "$LOGFILE"
    apply_render96ex_patches
fi

# ── Step 7: Build ─────────────────────────────────────────────────────────────
if [[ "$UPSTREAM" == "render96ex" ]]; then
    export CPATH="/usr/local/include:${CPATH:-}"
    echo "" | tee -a "$LOGFILE"
    echo "🔧 Render96ex CPATH override" | tee -a "$LOGFILE"
    echo "    CPATH=$CPATH" | tee -a "$LOGFILE"
    echo "    (resolves <SDL2/SDL.h> against Homebrew's /usr/local/include/SDL2/)" | tee -a "$LOGFILE"
fi

echo "" | tee -a "$LOGFILE"
echo "🔨 Step 7: Build  ($(sysctl -n hw.logicalcpu) cores)" | tee -a "$LOGFILE"
echo "    gmake OSX_BUILD=1 ${EXTRA_MAKE_FLAGS[*]} -j$(sysctl -n hw.logicalcpu)" | tee -a "$LOGFILE"
(cd "$REPO_DIR" && gmake OSX_BUILD=1 "${EXTRA_MAKE_FLAGS[@]}" -j"$(sysctl -n hw.logicalcpu)") 2>&1 | tee -a "$LOGFILE"

# ── Step 8: Binary validation ─────────────────────────────────────────────────
echo "" | tee -a "$LOGFILE"
echo "🔍 Step 8: Validate binary" | tee -a "$LOGFILE"
BINARY=""
CANDIDATES=()
[[ -n "$BINARY_REL" ]] && CANDIDATES+=("$REPO_DIR/$BINARY_REL")
CANDIDATES+=(
    "$REPO_DIR/build/us_pc/sm64.us.f3dex2e"
    "$REPO_DIR/build/us_pc/sm64coopdx"
    "$REPO_DIR/build/us_pc/sm64ex"
    "$REPO_DIR/build/us_pc/sm64coopdx.app/Contents/MacOS/sm64coopdx"
    "$REPO_DIR/build/us_pc/sm64ex.app/Contents/MacOS/sm64ex"
    "$REPO_DIR/build/us_pc/sm64.us.f3dex2e.app/Contents/MacOS/sm64.us.f3dex2e"
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

if [[ "$BINARY" == *".app/Contents/MacOS/"* ]]; then
    APP_DIR="${BINARY%/Contents/MacOS/*}"
    echo "    ℹ️  Binary lives inside upstream .app: $APP_DIR" | tee -a "$LOGFILE"
fi

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
