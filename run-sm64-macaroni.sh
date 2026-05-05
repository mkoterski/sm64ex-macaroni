#!/bin/zsh
# run-sm64-macaroni.sh
# sm64ex Macaroni — Intel Mac / macOS Tahoe launcher
#
# Locates the most-recently-built sm64ex-family binary, backs up sm64config.txt,
# runs preflight checks, exports DYLD fallbacks, and launches the game from its
# build directory (so the binary finds gfx/, sound/, levels/ etc. relative to
# cwd). Captures stdout+stderr to a timestamped log.
#
# Auto-detection walks the three preset upstream dirs in order:
#     sm64ex/  →  Render96ex/  →  sm64coopdx/
# If multiple are present, the most-recently-built binary wins.
# Use --upstream <preset> to force a specific tree.
#
# Usage:
#     ./run-sm64-macaroni.sh                       # auto-detect upstream
#     ./run-sm64-macaroni.sh --upstream sm64ex     # force specific build
#     ./run-sm64-macaroni.sh --upstream render96ex
#     ./run-sm64-macaroni.sh --upstream coopdx
#     ./run-sm64-macaroni.sh --restore-cfg         # restore latest cfg backup
#
# Config & saves (portable build, NON_PORTABLE not set):
#     <upstream>/build/us_pc/sm64config.txt    keybindings + window prefs
#     <upstream>/build/us_pc/sm64_save_file.bin    save data
#
# Log output:
#     logs/run-<timestamp>.log         ← last $LOG_KEEP runs kept
#     logs/sm64config.txt.backup-<timestamp>
#
# CHANGELOG
#   v0.10 (2026-05-05) - Initial version; adapted from run-spmc-macos.sh v0.15;
#                        no JSON config patching (sm64ex uses plain-text config);
#                        no --metal/--opengl flags (renderer is compile-time);
#                        multi-upstream binary discovery across sm64ex /
#                        Render96ex / sm64coopdx directories;
#                        portable-mode config path (next to binary, not $HOME)

set -eo pipefail

VERSION="0.10"
SCRIPT_DIR="${0:A:h}"
LOG_KEEP=5

# ── Parse arguments ───────────────────────────────────────────────────────────
UPSTREAM=""           # empty = auto-detect
RESTORE_CFG=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --upstream)         UPSTREAM="$2"; shift 2 ;;
        --restore-cfg)      RESTORE_CFG=1; shift ;;
        -h|--help)
            sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
            exit 0 ;;
        *) echo "Usage: $0 [--upstream <sm64ex|render96ex|coopdx>] [--restore-cfg]" >&2; exit 1 ;;
    esac
done

# ── Locate binary (preset table + auto-detect) ────────────────────────────────
# Each preset maps to (repo dir, primary binary name). The discovery loop
# checks each candidate's mtime; most recent build wins when --upstream is
# unset. Setting --upstream restricts the search to one dir.
typeset -A PRESET_DIR
typeset -A PRESET_BIN_PRIMARY
PRESET_DIR=(
    sm64ex      "sm64ex"
    render96ex  "Render96ex"
    coopdx      "sm64coopdx"
)
PRESET_BIN_PRIMARY=(
    sm64ex      "sm64.us.f3dex2e"
    render96ex  "sm64.us.f3dex2e"
    coopdx      "sm64coopdx"
)

# Build candidate list. Each candidate is "preset|repodir|binary" so we can
# trace which preset was selected without re-deriving it.
CANDIDATES=()
SEARCH_PRESETS=()
if [[ -n "$UPSTREAM" ]]; then
    if [[ -z "${PRESET_DIR[$UPSTREAM]}" ]]; then
        echo "❌ Unknown --upstream preset: $UPSTREAM" >&2
        echo "   Valid: sm64ex, render96ex, coopdx" >&2
        exit 1
    fi
    SEARCH_PRESETS=("$UPSTREAM")
else
    SEARCH_PRESETS=(sm64ex render96ex coopdx)
fi

for preset in "${SEARCH_PRESETS[@]}"; do
    repo_dir="$SCRIPT_DIR/${PRESET_DIR[$preset]}"
    primary="$repo_dir/build/us_pc/${PRESET_BIN_PRIMARY[$preset]}"
    # Cover the canonical path plus common alternatives (binary rename across
    # forks, region/microcode variants).
    for bin in "$primary" \
               "$repo_dir/build/us_pc/sm64.us.f3dex2e" \
               "$repo_dir/build/us_pc/sm64coopdx" \
               "$repo_dir/build/us_pc/sm64ex"; do
        [[ -f "$bin" ]] && CANDIDATES+=("$preset|$repo_dir|$bin")
    done
done

# Pick most-recently-built across all matches.
BINARY=""
SELECTED_PRESET=""
SELECTED_REPO=""
LATEST_MTIME=0
for entry in "${CANDIDATES[@]}"; do
    p="${entry%%|*}"
    rest="${entry#*|}"
    r="${rest%%|*}"
    b="${rest#*|}"
    mtime="$(stat -f '%m' "$b" 2>/dev/null || echo 0)"
    if (( mtime > LATEST_MTIME )); then
        BINARY="$b"
        SELECTED_PRESET="$p"
        SELECTED_REPO="$r"
        LATEST_MTIME=$mtime
    fi
done

BUILD_DIR="$(dirname "$BINARY" 2>/dev/null || true)"
CFG_FILE="$BUILD_DIR/sm64config.txt"

TIMESTAMP="$(date '+%Y%m%d-%H%M')"
LOG_DIR="$SCRIPT_DIR/logs"
LOGFILE="$LOG_DIR/run-$TIMESTAMP.log"
CFG_BACKUP="$LOG_DIR/sm64config.txt.backup-$TIMESTAMP"
mkdir -p "$LOG_DIR"

# ── Restore mode ──────────────────────────────────────────────────────────────
if (( RESTORE_CFG )); then
    LATEST_BAK="$(ls -t "$LOG_DIR"/sm64config.txt.backup-* 2>/dev/null | head -1 || true)"
    if [[ -z "$LATEST_BAK" ]]; then
        echo "⚠️  No config backup found in $LOG_DIR/" >&2
        exit 1
    fi
    if [[ -z "$BINARY" ]]; then
        echo "⚠️  No build found — cannot determine where to restore the config." >&2
        echo "    Run ./sm64-macaroni-build.sh first." >&2
        exit 1
    fi
    cp "$LATEST_BAK" "$CFG_FILE"
    echo "✅ Restored: $CFG_FILE"
    echo "   From:    $LATEST_BAK"
    exit 0
fi

# ── Preflight ─────────────────────────────────────────────────────────────────
echo "🎮 run-sm64-macaroni-macos.sh v$VERSION — $(date)" | tee -a "$LOGFILE"
if [[ -z "$BINARY" ]]; then
    echo "    ❌ No sm64ex-family binary found." | tee -a "$LOGFILE"
    echo "       Run: ./sm64-macaroni-build.sh" | tee -a "$LOGFILE"
    exit 1
fi
echo "    Upstream: $SELECTED_PRESET ($(basename "$SELECTED_REPO"))" | tee -a "$LOGFILE"
echo "    Binary:   $BINARY" | tee -a "$LOGFILE"
echo "    Built:    $(stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "$BINARY")" | tee -a "$LOGFILE"
echo "    Log:      $LOGFILE" | tee -a "$LOGFILE"

# Asset extraction marker — same one the build script uses. If this is missing,
# the binary will likely segfault on first frame trying to load missing assets.
if [[ ! -f "$SELECTED_REPO/sound/sound_data.ctl.inc.c" ]]; then
    echo "    ⚠️  sound_data.ctl.inc.c missing — assets may not be extracted." | tee -a "$LOGFILE"
    echo "       Run: ./sm64-macaroni-build.sh" | tee -a "$LOGFILE"
fi

# ── Config backup ─────────────────────────────────────────────────────────────
# sm64config.txt is plain-text key=value. We back it up before each run as a
# safety net; the game will recreate it on first launch if it doesn't exist
# (with all default keybindings).
if [[ -f "$CFG_FILE" ]]; then
    cp "$CFG_FILE" "$CFG_BACKUP"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [info] Config backup → ${CFG_BACKUP##$SCRIPT_DIR/}" | tee -a "$LOGFILE"
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') [info] No sm64config.txt yet — game will seed defaults on first launch" | tee -a "$LOGFILE"
fi

# ── DYLD paths ────────────────────────────────────────────────────────────────
# Same fallback as spmc — covers cases where the binary was linked against
# a Homebrew dylib path that isn't in the runtime search list.
export DYLD_LIBRARY_PATH="/usr/local/lib:${DYLD_LIBRARY_PATH:-}"
export DYLD_FALLBACK_LIBRARY_PATH="/usr/local/lib:${DYLD_FALLBACK_LIBRARY_PATH:-}"

# ── Launch ────────────────────────────────────────────────────────────────────
# sm64ex expects to run from build/us_pc/ — it loads gfx/, sound/, etc. from
# the working directory. Always cd to BUILD_DIR before exec.
echo "" | tee -a "$LOGFILE"
echo "$(date '+%Y-%m-%d %H:%M:%S') [info] Launching $SELECTED_PRESET..." | tee -a "$LOGFILE"
cd "$BUILD_DIR"
./"${BINARY:t}" 2>&1 | tee -a "$LOGFILE"
EXIT_CODE=${pipestatus[1]}

echo "" | tee -a "$LOGFILE"
if [[ $EXIT_CODE -eq 0 ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') [info] $SELECTED_PRESET exited cleanly (code 0)" | tee -a "$LOGFILE"
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') [warn] $SELECTED_PRESET exited with code $EXIT_CODE" | tee -a "$LOGFILE"
    echo "       Crash logs: ./sm64-macaroni-collect-crash.sh" | tee -a "$LOGFILE"
fi

# ── Log rotation ──────────────────────────────────────────────────────────────
RUN_LOGS=("${(@f)$(ls -t "$LOG_DIR"/run-*.log 2>/dev/null)}")
if (( ${#RUN_LOGS[@]} > LOG_KEEP )); then
    TO_DELETE=("${RUN_LOGS[@]:$LOG_KEEP}")
    for old in "${TO_DELETE[@]}"; do
        rm -f "$old"
        echo "$(date '+%Y-%m-%d %H:%M:%S') [info] Log rotated: ${old:t}" | tee -a "$LOGFILE"
    done
fi

echo "" | tee -a "$LOGFILE"
echo "════════════════════════════════════════════════════════════════" | tee -a "$LOGFILE"
echo "✅ run-sm64-macaroni-macos.sh v$VERSION complete!" | tee -a "$LOGFILE"
echo "    📄 $LOGFILE" | tee -a "$LOGFILE"
echo "    💾 Keeping last $LOG_KEEP run logs" | tee -a "$LOGFILE"
echo "════════════════════════════════════════════════════════════════" | tee -a "$LOGFILE"
