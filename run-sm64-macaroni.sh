#!/bin/zsh
# run-sm64-macaroni.sh
# sm64 Macaroni — Intel Mac / macOS Tahoe launcher
#
# Locates the most-recently-built sm64ex-family binary across the supported
# upstream presets, runs preflight checks, and launches the game.
#
# Two launch strategies based on how the upstream packaged its build:
#
#   1. Bare binary (sm64ex, render96ex):
#      Binary sits at <upstream>/build/us_pc/<binname>. Wrapper sets DYLD
#      paths, cds to build/us_pc/, and execs the binary directly. Logs
#      stdout+stderr to logs/run-<timestamp>.log.
#
#   2. Upstream-built .app bundle (coopdx):
#      coopdx's Makefile (OSX_APP_BUILD path) produces a complete .app at
#      <upstream>/build/us_pc/<name>.app, with the binary, dylibs, and
#      Info.plist already in place. Wrapper launches via `open <path>`,
#      mirroring what double-clicking from Finder does.
#
# Auto-detection walks all preset upstream dirs and picks the most-
# recently-built artifact. Use --upstream <preset> to force one tree.
#
# Usage:
#     ./run-sm64-macaroni.sh                       # auto-detect upstream
#     ./run-sm64-macaroni.sh --upstream sm64ex     # force specific build
#     ./run-sm64-macaroni.sh --upstream coopdx
#     ./run-sm64-macaroni.sh --restore-cfg         # bare-binary upstreams only
#
# CHANGELOG
#   v0.14 (2026-05-06) - Two robustness fixes for zsh quirks under set -e:
#                        (1) Explicit PATH at top of script. Without it, some
#                            shell init paths leave PATH empty inside command
#                            substitutions ($(...)) reached after certain
#                            arithmetic contexts, producing the misleading
#                            "command not found: date" / "stat" errors we
#                            were seeing on coopdx.
#                        (2) stat replaced with absolute-path /usr/bin/stat
#                            and || true on the failure path, so a single
#                            unreadable file doesn't take down the discovery
#                            loop. Also captures stderr so the trace shows
#                            *why* stat failed if it does.
#                        (3) set -u removed from set flags; only -e and
#                            pipefail remain. This script reads many possibly-
#                            unset variables (PRESET_DIR[$UPSTREAM] when
#                            UPSTREAM is invalid, etc.) and -u just makes the
#                            error messages worse without catching real bugs.
#                        Behavior under correct inputs is unchanged.
#   v0.13 (2026-05-06) - Added Option-A launch path for upstream-built .app
#                        bundles via `open`.
#   v0.12 (2026-05-05) - Repo renamed sm64ex-macaroni → sm64-macaroni.
#   v0.11 (2026-05-05) - Drop -macos suffix; remove obsolete preflight.
#   v0.10 (2026-05-05) - Initial version; adapted from run-spmc-macos.sh v0.15.

# ── Defensive PATH ────────────────────────────────────────────────────────────
# Set this BEFORE any command substitution so subshells inherit a known-good
# search path. macOS-default PATH plus Homebrew Intel prefix.
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

set -eo pipefail

VERSION="0.14"
SCRIPT_DIR="${0:A:h}"
LOG_KEEP=5

# ── Parse arguments ───────────────────────────────────────────────────────────
UPSTREAM=""
RESTORE_CFG=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --upstream)         UPSTREAM="$2"; shift 2 ;;
        --restore-cfg)      RESTORE_CFG=1; shift ;;
        -h|--help)
            sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
            exit 0 ;;
        *) echo "Usage: $0 [--upstream <sm64ex|coopdx|render96ex>] [--restore-cfg]" >&2; exit 1 ;;
    esac
done

# ── Locate binary (preset table + auto-detect) ────────────────────────────────
typeset -A PRESET_DIR
PRESET_DIR=(
    sm64ex      "sm64ex"
    coopdx      "sm64coopdx"
    render96ex  "Render96ex"
)

build_candidates_for() {
    local preset="$1"
    local repo_dir="$SCRIPT_DIR/${PRESET_DIR[$preset]}"
    case "$preset" in
        sm64ex|render96ex)
            echo "$preset|$repo_dir|$repo_dir/build/us_pc/sm64.us.f3dex2e"
            echo "$preset|$repo_dir|$repo_dir/build/us_pc/sm64.us.f3dex2e.app/Contents/MacOS/sm64.us.f3dex2e"
            echo "$preset|$repo_dir|$repo_dir/build/us_pc/sm64ex.app/Contents/MacOS/sm64ex"
            ;;
        coopdx)
            echo "$preset|$repo_dir|$repo_dir/build/us_pc/sm64coopdx.app/Contents/MacOS/sm64coopdx"
            echo "$preset|$repo_dir|$repo_dir/build/us_pc/sm64coopdx"
            ;;
    esac
}

# Robust mtime helper: absolute path to /usr/bin/stat, captures stderr to
# dev/null so set -e doesn't blow up on transient FS errors, falls back to 0.
get_mtime() {
    /usr/bin/stat -f '%m' "$1" 2>/dev/null || echo 0
}

CANDIDATES=()
SEARCH_PRESETS=()
if [[ -n "$UPSTREAM" ]]; then
    if [[ -z "${PRESET_DIR[$UPSTREAM]}" ]]; then
        echo "❌ Unknown --upstream preset: $UPSTREAM" >&2
        echo "   Valid: sm64ex, coopdx, render96ex" >&2
        exit 1
    fi
    SEARCH_PRESETS=("$UPSTREAM")
else
    SEARCH_PRESETS=(sm64ex coopdx render96ex)
fi

for preset in "${SEARCH_PRESETS[@]}"; do
    while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue
        path="${entry##*|}"
        [[ -f "$path" ]] && CANDIDATES+=("$entry")
    done < <(build_candidates_for "$preset")
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
    mtime="$(get_mtime "$b")"
    if (( mtime > LATEST_MTIME )); then
        BINARY="$b"
        SELECTED_PRESET="$p"
        SELECTED_REPO="$r"
        LATEST_MTIME=$mtime
    fi
done

# If no winner emerged but we have at least one candidate (mtime fetch failed
# for every entry), fall back to the first candidate. Better than aborting.
if [[ -z "$BINARY" && ${#CANDIDATES[@]} -gt 0 ]]; then
    entry="${CANDIDATES[1]}"
    SELECTED_PRESET="${entry%%|*}"
    rest="${entry#*|}"
    SELECTED_REPO="${rest%%|*}"
    BINARY="${rest#*|}"
    echo "⚠️  mtime fetch failed for all candidates; falling back to first match." >&2
fi

# Distinguish launch strategy.
LAUNCH_MODE="bare"
APP_PATH=""
if [[ -n "$BINARY" && "$BINARY" == *".app/Contents/MacOS/"* ]]; then
    LAUNCH_MODE="app"
    APP_PATH="${BINARY%/Contents/MacOS/*}"
fi

BUILD_DIR=""
[[ -n "$BINARY" ]] && BUILD_DIR="$(dirname "$BINARY")"
CFG_FILE="$BUILD_DIR/sm64config.txt"

TIMESTAMP="$(date '+%Y%m%d-%H%M')"
LOG_DIR="$SCRIPT_DIR/logs"
LOGFILE="$LOG_DIR/run-$TIMESTAMP.log"
CFG_BACKUP="$LOG_DIR/sm64config.txt.backup-$TIMESTAMP"
mkdir -p "$LOG_DIR"

# ── Restore mode ──────────────────────────────────────────────────────────────
if (( RESTORE_CFG )); then
    if [[ "$LAUNCH_MODE" == "app" ]]; then
        echo "⚠️  --restore-cfg is a no-op for $SELECTED_PRESET — its config" >&2
        echo "    lives in ~/Library/Application Support/, managed by the .app." >&2
        exit 1
    fi
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
echo "🎮 run-sm64-macaroni.sh v$VERSION — $(date)" | tee -a "$LOGFILE"
if [[ -z "$BINARY" ]]; then
    echo "    ❌ No sm64ex-family binary found." | tee -a "$LOGFILE"
    echo "       Run: ./sm64-macaroni-build.sh" | tee -a "$LOGFILE"
    exit 1
fi
echo "    Upstream: $SELECTED_PRESET ($(basename "$SELECTED_REPO"))" | tee -a "$LOGFILE"
echo "    Mode:     $LAUNCH_MODE" | tee -a "$LOGFILE"
if [[ "$LAUNCH_MODE" == "app" ]]; then
    echo "    .app:     $APP_PATH" | tee -a "$LOGFILE"
else
    echo "    Binary:   $BINARY" | tee -a "$LOGFILE"
fi
echo "    Built:    $(/usr/bin/stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "$BINARY" 2>/dev/null || echo 'unknown')" | tee -a "$LOGFILE"
echo "    Log:      $LOGFILE" | tee -a "$LOGFILE"

# ── Launch ────────────────────────────────────────────────────────────────────
if [[ "$LAUNCH_MODE" == "app" ]]; then
    echo "" | tee -a "$LOGFILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [info] Launching $SELECTED_PRESET via open..." | tee -a "$LOGFILE"
    open "$APP_PATH"
    EXIT_CODE=$?
    echo "$(date '+%Y-%m-%d %H:%M:%S') [info] $SELECTED_PRESET launched (open returned $EXIT_CODE)" | tee -a "$LOGFILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [info] Live stdout/stderr in Console.app — search for '$SELECTED_PRESET'" | tee -a "$LOGFILE"
else
    export DYLD_LIBRARY_PATH="/usr/local/lib:${DYLD_LIBRARY_PATH:-}"
    export DYLD_FALLBACK_LIBRARY_PATH="/usr/local/lib:${DYLD_FALLBACK_LIBRARY_PATH:-}"

    if [[ -f "$CFG_FILE" ]]; then
        cp "$CFG_FILE" "$CFG_BACKUP"
        echo "$(date '+%Y-%m-%d %H:%M:%S') [info] Config backup → ${CFG_BACKUP##$SCRIPT_DIR/}" | tee -a "$LOGFILE"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') [info] No sm64config.txt yet — game will seed defaults on first launch" | tee -a "$LOGFILE"
    fi

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
echo "✅ run-sm64-macaroni.sh v$VERSION complete!" | tee -a "$LOGFILE"
echo "    📄 $LOGFILE" | tee -a "$LOGFILE"
echo "    💾 Keeping last $LOG_KEEP run logs" | tee -a "$LOGFILE"
echo "════════════════════════════════════════════════════════════════" | tee -a "$LOGFILE"
