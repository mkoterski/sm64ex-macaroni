#!/bin/zsh
# spmc-sysinfo.sh
# SpaghettiKart MacCheese — system snapshot for bug reports
#
# Captures hardware, GPU, macOS version, Homebrew deps, and SpaghettiKart
# build info into a single text file. Called automatically by
# spmc-collect-crash.sh.
#
# Usage:
#   ./spmc-sysinfo.sh                   # write to logs/
#   ./spmc-sysinfo.sh --out /some/dir   # write to specified directory
#   ./spmc-sysinfo.sh --print           # also print to stdout
#
# CHANGELOG
# v0.10 (2026-03-14) - Initial version; adapted from pdmv-systeminfo.sh v0.10;
#                      Spaghettify binary; spaghettify.cfg.json config read;
#                      o2r file status; Homebrew SpaghettiKart deps

set -eo pipefail
VERSION="0.10"
SCRIPT_DIR="${0:A:h}"
TIMESTAMP="$(date '+%Y%m%d-%H%M')"
PRINT_STDOUT=0

# ── Parse arguments ───────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)   OUT_DIR="$2";   shift 2 ;;
    --print) PRINT_STDOUT=1; shift ;;
    *) echo "Usage: $0 [--out <dir>] [--print]" >&2; exit 1 ;;
  esac
done

REPO_DIR="$SCRIPT_DIR/SpaghettiKart"
BUILD_DIR="$REPO_DIR/build-cmake"
OUT_DIR="${OUT_DIR:-$SCRIPT_DIR/logs}"
mkdir -p "$OUT_DIR"
OUTFILE="$OUT_DIR/sysinfo-$TIMESTAMP.txt"

# Helper — write to file, optionally stdout
w() {
  echo "$@" >> "$OUTFILE"
  (( PRINT_STDOUT )) && echo "$@" || true
}

# ── Header ────────────────────────────────────────────────────────────────────

w "════════════════════════════════════════════════════════════════"
w " SpaghettiKart MacCheese — System Snapshot"
w " spmc-sysinfo.sh v$VERSION — $(date)"
w "════════════════════════════════════════════════════════════════"
w ""

# ── macOS & Hardware ──────────────────────────────────────────────────────────

w "── macOS ────────────────────────────────────────────────────────"
sw_vers >> "$OUTFILE" 2>&1
w "Kernel: $(uname -r)"
w "Architecture: $(uname -m)"
w ""

w "── Hardware ─────────────────────────────────────────────────────"
system_profiler SPHardwareDataType 2>/dev/null \
  | grep -E 'Model Name|Model Identifier|Processor|Cores|Memory|Serial' \
  | sed 's/^[[:space:]]*/  /' >> "$OUTFILE"
w ""

# ── GPU & Graphics ────────────────────────────────────────────────────────────

w "── GPU / Graphics ───────────────────────────────────────────────"
system_profiler SPDisplaysDataType 2>/dev/null \
  | grep -E 'Chipset|VRAM|Metal|Vendor|Device|Resolution|Pixel' \
  | sed 's/^[[:space:]]*/  /' >> "$OUTFILE"
system_profiler SPDisplaysDataType 2>/dev/null \
  | grep -iE 'OpenGL|GLSL' \
  | sed 's/^[[:space:]]*/  /' >> "$OUTFILE" || true
w "  Note: GL/Metal renderer string requires active context (launch game to capture)"
w ""

# ── Homebrew dependencies ─────────────────────────────────────────────────────

w "── Homebrew dependencies ────────────────────────────────────────"
if command -v brew &>/dev/null; then
  BREW_PKGS=(
    cmake ninja git python3
    sdl2 sdl2_net libpng glew
    nlohmann-json libzip tinyxml2
    spdlog boost libogg libvorbis vorbis-tools
  )
  for pkg in "${BREW_PKGS[@]}"; do
    VER="$(brew list --versions "$pkg" 2>/dev/null || echo 'not installed')"
    w "  $pkg: $VER"
  done
else
  w "  brew not found"
fi
w ""

# ── SpaghettiKart binary ──────────────────────────────────────────────────────

w "── SpaghettiKart binary ─────────────────────────────────────────"
BINARY=""
for candidate in "$BUILD_DIR/Spaghettify" "$BUILD_DIR/spaghettify"; do
  [[ -f "$candidate" ]] && BINARY="$candidate" && break
done

if [[ -n "$BINARY" ]]; then
  w "  Path:   $BINARY"
  w "  Size:   $(du -h "$BINARY" | cut -f1)"
  w "  Arch:   $(file "$BINARY" | cut -d: -f2 | xargs)"
  w "  Built:  $(stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "$BINARY")"
  w "  Linked libs (otool -L):"
  otool -L "$BINARY" 2>/dev/null | sed 's/^/    /' >> "$OUTFILE" || true
else
  w "  Binary not found in $BUILD_DIR/"
  w "  Run: ./spmc-build.sh"
fi
w ""

# ── O2R files ─────────────────────────────────────────────────────────────────

w "── O2R asset files ──────────────────────────────────────────────"
for o2r_name in mk64.o2r spaghetti.o2r; do
  O2R_PATH="$BUILD_DIR/$o2r_name"
  if [[ -f "$O2R_PATH" ]]; then
    w "  $o2r_name: $(du -h "$O2R_PATH" | cut -f1)  $(stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$O2R_PATH")"
  else
    w "  $o2r_name: not found"
  fi
done
w ""

# ── spaghettify.cfg.json ─────────────────────────────────────────────────────

w "── spaghettify.cfg.json ─────────────────────────────────────────"
CFG="$HOME/spaghettify.cfg.json"
if [[ -f "$CFG" ]]; then
  w "  Path: $CFG"
  head -40 "$CFG" >> "$OUTFILE" 2>/dev/null || true
else
  # Fallback: check build dir (NON_PORTABLE=ON builds)
  CFG="$BUILD_DIR/spaghettify.cfg.json"
  if [[ -f "$CFG" ]]; then
    w "  Path: $CFG"
    head -40 "$CFG" >> "$OUTFILE" 2>/dev/null || true
  else
    w "  Config not found at ~/spaghettify.cfg.json or $BUILD_DIR/"
    w "  (created automatically on first launch)"
  fi
fi
w ""

# ── Disk & Memory ─────────────────────────────────────────────────────────────

w "── Disk & Memory ────────────────────────────────────────────────"
w "  Disk (project): $(du -sh "$SCRIPT_DIR" 2>/dev/null | cut -f1)"
w "  Disk (build):   $(du -sh "$BUILD_DIR" 2>/dev/null | cut -f1)"
df -h "$SCRIPT_DIR" 2>/dev/null | tail -1 \
  | awk '{print "  Free on volume: " $4}' >> "$OUTFILE"
vm_stat 2>/dev/null \
  | grep -E 'Pages (free|active|wired)' \
  | awk '{printf "  vm_stat: %s\n", $0}' >> "$OUTFILE" || true
w ""

# ── Footer ────────────────────────────────────────────────────────────────────

w "════════════════════════════════════════════════════════════════"
w " End of snapshot — $(date)"
w "════════════════════════════════════════════════════════════════"

echo "✅ spmc-sysinfo.sh v$VERSION → $OUTFILE"