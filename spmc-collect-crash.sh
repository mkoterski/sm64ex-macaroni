#!/bin/zsh
# spmc-collect-crash.sh
# SpaghettiKart MacCheese — macOS crash report collector
#
# Collects the most recent SpaghettiKart / Spaghettify crash reports from
# macOS DiagnosticReports and copies them into logs/crash-<timestamp>/
# alongside a system snapshot. Attach the output folder when filing bug
# reports on the HarbourMasters/SpaghettiKart issue tracker.
#
# Usage:
#   ./spmc-collect-crash.sh               # collect last 5
#   ./spmc-collect-crash.sh -n 10         # collect last N reports
#   ./spmc-collect-crash.sh --list        # list only, no copy
#
# CHANGELOG
# v0.10 (2026-03-14) - Initial version; adapted from pdmv-collect-crash.sh v0.10;
#                      searches Spaghettify.* and SpaghettiKart.*

set -eo pipefail
VERSION="0.10"
SCRIPT_DIR="${0:A:h}"
TIMESTAMP="$(date '+%Y%m%d-%H%M')"
MAX_REPORTS=5
LIST_ONLY=0

# ── Parse arguments ───────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n)     MAX_REPORTS="$2"; shift 2 ;;
    --list) LIST_ONLY=1;      shift ;;
    *) echo "Usage: $0 [-n <count>] [--list]" >&2; exit 1 ;;
  esac
done

LOG_DIR="$SCRIPT_DIR/logs"
OUT_DIR="$LOG_DIR/crash-$TIMESTAMP"
LOGFILE="$OUT_DIR/collect-crash-$TIMESTAMP.log"

mkdir -p "$OUT_DIR"
echo "💥 spmc-collect-crash.sh v$VERSION — $(date)" | tee -a "$LOGFILE"
echo "   Output: $OUT_DIR" | tee -a "$LOGFILE"

# ── Search paths ──────────────────────────────────────────────────────────────

# macOS writes crash reports in two locations:
#   User:   ~/Library/Logs/DiagnosticReports/
#   System: /Library/Logs/DiagnosticReports/
# Both .ips (modern JSON-based) and .crash (legacy) formats are collected.
# (N) suppresses errors on no match (zsh nullglob).

USER_DIAG="$HOME/Library/Logs/DiagnosticReports"
SYS_DIAG="/Library/Logs/DiagnosticReports"

echo "" | tee -a "$LOGFILE"
echo "🔍 Searching for SpaghettiKart crash reports..." | tee -a "$LOGFILE"

ALL_CRASHES=()
for dir in "$USER_DIAG" "$SYS_DIAG"; do
  if [[ -d "$dir" ]]; then
    for f in "$dir"/Spaghettify*.ips(N) "$dir"/Spaghettify*.crash(N) \
             "$dir"/spaghettify*.ips(N) "$dir"/spaghettify*.crash(N) \
             "$dir"/SpaghettiKart*.ips(N) "$dir"/SpaghettiKart*.crash(N); do
      ALL_CRASHES+=("$f")
    done
  fi
done

# Sort by mtime descending
if (( ${#ALL_CRASHES[@]} > 0 )); then
  ALL_CRASHES=(${(f)"$(for f in "${ALL_CRASHES[@]}"; do
    echo "$(stat -f '%m' "$f") $f"
  done | sort -rn | awk '{print $2}')"})
fi

TOTAL=${#ALL_CRASHES[@]}

if (( TOTAL == 0 )); then
  echo "   ℹ️  No SpaghettiKart crash reports found." | tee -a "$LOGFILE"
  echo "      Crashes appear in Console.app → Crash Reports" | tee -a "$LOGFILE"
  exit 0
fi

echo "   Found $TOTAL crash report(s) — collecting up to $MAX_REPORTS" | tee -a "$LOGFILE"

# ── List or copy ──────────────────────────────────────────────────────────────

COPIED=0
for f in "${ALL_CRASHES[@]}"; do
  (( COPIED >= MAX_REPORTS )) && break
  MTIME="$(stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "$f")"
  SIZE="$(du -h "$f" | cut -f1)"
  FNAME="${f:t}"
  echo "   📄 $MTIME  $SIZE  $FNAME" | tee -a "$LOGFILE"
  if (( LIST_ONLY == 0 )); then
    cp "$f" "$OUT_DIR/"
    (( COPIED++ ))
  fi
done

if (( LIST_ONLY )); then
  echo "" | tee -a "$LOGFILE"
  echo "   (--list mode: no files copied)" | tee -a "$LOGFILE"
  exit 0
fi

# ── Attach sysinfo ────────────────────────────────────────────────────────────

if [[ -f "$SCRIPT_DIR/spmc-sysinfo.sh" ]]; then
  echo "" | tee -a "$LOGFILE"
  echo "📋 Running spmc-sysinfo.sh..." | tee -a "$LOGFILE"
  "$SCRIPT_DIR/spmc-sysinfo.sh" --out "$OUT_DIR" 2>&1 | tee -a "$LOGFILE" || \
    echo "   ⚠️  sysinfo failed (non-fatal)" | tee -a "$LOGFILE"
fi

# ── Summary ───────────────────────────────────────────────────────────────────

echo "" | tee -a "$LOGFILE"
echo "✅ spmc-collect-crash.sh v$VERSION complete!" | tee -a "$LOGFILE"
echo "   📁 $OUT_DIR" | tee -a "$LOGFILE"
echo "   Copied $COPIED of $TOTAL crash report(s)" | tee -a "$LOGFILE"
echo "   👉 Attach this folder when filing a bug report at:" | tee -a "$LOGFILE"
echo "      https://github.com/HarbourMasters/SpaghettiKart/issues" | tee -a "$LOGFILE"