#!/bin/zsh
# sm64-macaroni-bundle.sh
# sm64 Macaroni — Intel Mac / macOS Tahoe app bundle creator
#
# Wraps the compiled sm64ex-family binary into a proper .app bundle. The real
# binary is placed at Contents/MacOS/<Name>Bin behind a zsh wrapper that sets
# cwd to Contents/Resources/ so res/ (runtime assets baked by EXTERNAL_DATA=1)
# resolves correctly. Bundles all Homebrew dylibs into Contents/libs/ via
# dylibbundler so the .app runs without Homebrew installed. Ad-hoc codesigns
# the bundle for Tahoe Gatekeeper.
#
# Auto-detects the upstream from the most-recently-built binary, or use
# --upstream <preset> to force a specific tree.
#
# Usage:
#     ./sm64-macaroni-bundle.sh                      # auto-detect
#     ./sm64-macaroni-bundle.sh --upstream sm64ex
#     ./sm64-macaroni-bundle.sh --upstream render96ex
#     ./sm64-macaroni-bundle.sh --upstream coopdx
#
# Output:
#     dist/<App>.app               ← drag-to-Applications ready
#         dist/sm64ex.app          (sm64ex preset)
#         dist/Render96.app        (render96ex preset)
#         dist/sm64coopdx.app      (coopdx preset)
#     logs/bundle-<preset>-<timestamp>.log
#         e.g. bundle-sm64ex-20260505-1115.log
#              bundle-render96ex-20260505-1142.log
#
# Icon source (in priority order):
#     src/icon.icns           ← preferred: use as-is
#     src/icon.png            ← fallback: convert via sips + iconutil
#     (placeholder)           ← final fallback: Mario-red stub
#
# CHANGELOG
#   v0.13 (2026-05-05) - Repo renamed from sm64ex-macaroni → sm64-macaroni to
#                        reflect dual-family scope (sm64ex no longer the only
#                        target). Bundle ID prefix migrated accordingly:
#                            old:  com.mkoterski.sm64ex-macaroni.<preset>
#                            new:  com.mkoterski.sm64-macaroni.<preset>
#                        Users with previously-bundled .app installs may see
#                        macOS treat the new build as a separate app on first
#                        launch — delete the old one from /Applications to
#                        keep things tidy.
#                        Header branding updated.
#   v0.12 (2026-05-05) - Log filename now includes upstream preset
#                        (bundle-<preset>-<ts>.log) so multiple presets can be
#                        bundled in succession without their logs colliding;
#                        success summary now explicitly states upstream
#   v0.11 (2026-05-05) - Fix: SIGABRT at launch on Tahoe due to duplicate
#                        LC_RPATH '@executable_path/../libs/' in the bundled
#                        binary. sm64ex's Makefile (OSX_BUILD=1 path) adds this
#                        rpath at link time for haframjolk-style bundling, AND
#                        dylibbundler adds the same rpath again when patching
#                        load commands. dyld on macOS 14+ refuses to load a
#                        binary with duplicate LC_RPATH entries and aborts
#                        before any code runs ("Namespace DYLD, Code 0,
#                        duplicate LC_RPATH ..."). Added Step 7.5 to enumerate
#                        and dedupe rpaths via otool + install_name_tool
#                        between dylibbundler and codesign.
#   v0.10 (2026-05-05) - Initial version; adapted from spmc-bundle.sh v0.10;
#                        multi-upstream preset table (sm64ex / render96ex /
#                        coopdx); cwd wrapper pattern for res/ resolution;
#                        dylibbundler step (haframjolk-style bundling);
#                        ad-hoc codesign for Tahoe Gatekeeper;
#                        output to dist/ at wrapper repo root (not nested in
#                        upstream tree)

set -eo pipefail

VERSION="0.13"
SCRIPT_DIR="${0:A:h}"
DIST_DIR="$SCRIPT_DIR/dist"

# ── Parse arguments ───────────────────────────────────────────────────────────
UPSTREAM=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --upstream)         UPSTREAM="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
            exit 0 ;;
        *) echo "Usage: $0 [--upstream <sm64ex|render96ex|coopdx>]" >&2; exit 1 ;;
    esac
done

# ── Auto-detect upstream if not specified ─────────────────────────────────────
# Walk the same preset dirs as the run script and pick the most-recently-built
# binary. We need the upstream identity to resolve bundle name, bundle ID,
# and display name from the preset table below.
typeset -A PRESET_DIR
PRESET_DIR=(sm64ex "sm64ex" render96ex "Render96ex" coopdx "sm64coopdx")

if [[ -z "$UPSTREAM" ]]; then
    LATEST_MTIME=0
    for p in sm64ex render96ex coopdx; do
        for bin in "$SCRIPT_DIR/${PRESET_DIR[$p]}/build/us_pc/sm64.us.f3dex2e" \
                   "$SCRIPT_DIR/${PRESET_DIR[$p]}/build/us_pc/sm64coopdx" \
                   "$SCRIPT_DIR/${PRESET_DIR[$p]}/build/us_pc/sm64ex"; do
            if [[ -f "$bin" ]]; then
                m="$(stat -f '%m' "$bin" 2>/dev/null || echo 0)"
                if (( m > LATEST_MTIME )); then
                    LATEST_MTIME=$m
                    UPSTREAM="$p"
                fi
            fi
        done
    done
    if [[ -z "$UPSTREAM" ]]; then
        echo "❌ No sm64ex-family binary found. Run ./sm64-macaroni-build.sh first." >&2
        exit 1
    fi
fi

# ── Resolve --upstream preset → bundle metadata tuple ─────────────────────────
case "$UPSTREAM" in
    sm64ex)
        REPO_NAME="sm64ex"
        BIN_NAME_PRIMARY="sm64.us.f3dex2e"
        APP_NAME="sm64ex"
        DISPLAY_NAME="Super Mario 64 (sm64 Macaroni)"
        BUNDLE_ID="com.mkoterski.sm64-macaroni.sm64ex"
        ICON_BASENAME="sm64ex"
        ;;
    render96ex)
        REPO_NAME="Render96ex"
        BIN_NAME_PRIMARY="sm64.us.f3dex2e"
        APP_NAME="Render96"
        DISPLAY_NAME="Super Mario 64 Render96 (sm64 Macaroni)"
        BUNDLE_ID="com.mkoterski.sm64-macaroni.render96ex"
        ICON_BASENAME="render96"
        ;;
    coopdx)
        REPO_NAME="sm64coopdx"
        BIN_NAME_PRIMARY="sm64coopdx"
        APP_NAME="sm64coopdx"
        DISPLAY_NAME="Super Mario 64 Coop Deluxe (sm64 Macaroni)"
        BUNDLE_ID="com.mkoterski.sm64-macaroni.coopdx"
        ICON_BASENAME="sm64coopdx"
        ;;
    *)
        echo "❌ Unknown --upstream preset: $UPSTREAM" >&2
        echo "   Valid: sm64ex, render96ex, coopdx" >&2
        exit 1 ;;
esac

REPO_DIR="$SCRIPT_DIR/$REPO_NAME"
BUILD_DIR="$REPO_DIR/build/us_pc"
RES_SOURCE="$BUILD_DIR/res"
BUNDLE="$DIST_DIR/$APP_NAME.app"
ICNS_SRC="$SCRIPT_DIR/src/icon.icns"
ICNS_PNG="$SCRIPT_DIR/src/icon.png"
ICNS_DEST="$BUNDLE/Contents/Resources/$ICON_BASENAME.icns"

TIMESTAMP="$(date '+%Y%m%d-%H%M')"
LOG_DIR="$SCRIPT_DIR/logs"
LOGFILE="$LOG_DIR/bundle-$UPSTREAM-$TIMESTAMP.log"
mkdir -p "$LOG_DIR" "$DIST_DIR"

echo "🎁 sm64-macaroni-bundle.sh v$VERSION — $(date)" | tee -a "$LOGFILE"
echo "    Upstream:    $UPSTREAM ($REPO_NAME)" | tee -a "$LOGFILE"
echo "    App:         $APP_NAME.app" | tee -a "$LOGFILE"
echo "    Bundle ID:   $BUNDLE_ID" | tee -a "$LOGFILE"
echo "    Output:      $BUNDLE" | tee -a "$LOGFILE"
echo "    Log:         $LOGFILE" | tee -a "$LOGFILE"

# ── Locate binary ─────────────────────────────────────────────────────────────
BINARY=""
for candidate in "$BUILD_DIR/$BIN_NAME_PRIMARY" \
                 "$BUILD_DIR/sm64.us.f3dex2e" \
                 "$BUILD_DIR/sm64coopdx" \
                 "$BUILD_DIR/sm64ex"; do
    [[ -f "$candidate" ]] && BINARY="$candidate" && break
done

# ── Preflight ─────────────────────────────────────────────────────────────────
echo "" | tee -a "$LOGFILE"
echo "🔍 Preflight checks" | tee -a "$LOGFILE"
if [[ -z "$BINARY" ]]; then
    echo "    ❌ Binary not found in $BUILD_DIR" | tee -a "$LOGFILE"
    echo "       Run: ./sm64-macaroni-build.sh --upstream $UPSTREAM" | tee -a "$LOGFILE"
    exit 1
fi
echo "    ✅ Binary: ${BINARY:t} ($(du -h "$BINARY" | cut -f1))" | tee -a "$LOGFILE"

if [[ ! -d "$RES_SOURCE" ]]; then
    echo "    ⚠️  res/ directory not found at $RES_SOURCE" | tee -a "$LOGFILE"
    echo "       sm64ex was built without EXTERNAL_DATA=1, or build is incomplete." | tee -a "$LOGFILE"
    echo "       Bundle will continue but may fail to find runtime assets." | tee -a "$LOGFILE"
    RES_FOUND=0
else
    echo "    ✅ res/ ($(du -sh "$RES_SOURCE" | cut -f1))" | tee -a "$LOGFILE"
    RES_FOUND=1
fi

if ! command -v dylibbundler &>/dev/null; then
    echo "    ❌ dylibbundler not found. Run: brew install dylibbundler" | tee -a "$LOGFILE"
    exit 1
fi
echo "    ✅ $(dylibbundler --version 2>&1 | head -1)" | tee -a "$LOGFILE"

# ── Step 1: Resolve icon ──────────────────────────────────────────────────────
# Priority: src/icon.icns → src/icon.png (convert) → generated placeholder.
# The generated placeholder uses Mario-red (#E60012, the iconic hat color).
echo "" | tee -a "$LOGFILE"
echo "🖼  Step 1: Icon" | tee -a "$LOGFILE"
ICNS_BUILT="$LOG_DIR/$ICON_BASENAME.icns"
if [[ -f "$ICNS_SRC" ]]; then
    cp "$ICNS_SRC" "$ICNS_BUILT"
    echo "    ✅ Using src/icon.icns directly ($(du -h "$ICNS_SRC" | cut -f1))" | tee -a "$LOGFILE"
elif [[ -f "$ICNS_PNG" ]]; then
    echo "    Converting src/icon.png → .icns via sips + iconutil..." | tee -a "$LOGFILE"
    ICONSET_TMP="$(mktemp -d)/sm64macaroni.iconset"
    mkdir -p "$ICONSET_TMP"
    for SIZE in 16 32 64 128 256 512; do
        sips -z $SIZE $SIZE "$ICNS_PNG" --out "$ICONSET_TMP/icon_${SIZE}x${SIZE}.png" &>/dev/null
        if (( SIZE >= 32 )); then
            HALF=$(( SIZE / 2 ))
            cp "$ICONSET_TMP/icon_${SIZE}x${SIZE}.png" "$ICONSET_TMP/icon_${HALF}x${HALF}@2x.png"
        fi
    done
    iconutil -c icns "$ICONSET_TMP" -o "$ICNS_BUILT" 2>&1 | tee -a "$LOGFILE"
    rm -rf "$(dirname "$ICONSET_TMP")"
    echo "    ✅ Generated $ICON_BASENAME.icns from src/icon.png" | tee -a "$LOGFILE"
else
    echo "    ⚠️  No src/icon.icns or src/icon.png — generating Mario-red placeholder..." | tee -a "$LOGFILE"
    ICONSET_TMP="$(mktemp -d)/sm64macaroni.iconset"
    mkdir -p "$ICONSET_TMP"
    python3 - "$ICONSET_TMP" << 'PYEOF'
import struct, zlib, sys
def mkpng(w, h):
    rows = bytearray()
    for y in range(h):
        rows += b'\x00'
        for x in range(w):
            rows += bytes([0xE6, 0x00, 0x12, 255])  # Mario red
    compressed = zlib.compress(bytes(rows), 9)
    def chunk(name, data):
        c = zlib.crc32(name + data) & 0xffffffff
        return struct.pack('>I', len(data)) + name + data + struct.pack('>I', c)
    return (b'\x89PNG\r\n\x1a\n' +
            chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)) +
            chunk(b'IDAT', compressed) +
            chunk(b'IEND', b''))
iconset = sys.argv[1]
for s in [16, 32, 64, 128, 256, 512]:
    open(f'{iconset}/icon_{s}x{s}.png',     'wb').write(mkpng(s, s))
    open(f'{iconset}/icon_{s}x{s}@2x.png',  'wb').write(mkpng(s*2, s*2))
PYEOF
    iconutil -c icns "$ICONSET_TMP" -o "$ICNS_BUILT" 2>&1 | tee -a "$LOGFILE"
    rm -rf "$(dirname "$ICONSET_TMP")"
    echo "    ✅ Generated placeholder $ICON_BASENAME.icns" | tee -a "$LOGFILE"
fi

# ── Step 2: Bundle structure ──────────────────────────────────────────────────
echo "" | tee -a "$LOGFILE"
echo "📁 Step 2: Creating bundle structure..." | tee -a "$LOGFILE"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"
mkdir -p "$BUNDLE/Contents/libs"
echo "    ✅ $BUNDLE" | tee -a "$LOGFILE"

# ── Step 3: Binary + cwd wrapper ──────────────────────────────────────────────
# The wrapper sets DYLD fallback paths and cds to Contents/Resources/ so the
# binary's cwd-relative res/ lookup resolves. The real binary is renamed
# *Bin so the user-visible bundle launcher matches CFBundleExecutable.
echo "" | tee -a "$LOGFILE"
echo "📦 Step 3: Binary + wrapper..." | tee -a "$LOGFILE"
cp "$BINARY" "$BUNDLE/Contents/MacOS/${APP_NAME}Bin"
chmod +x "$BUNDLE/Contents/MacOS/${APP_NAME}Bin"

cat > "$BUNDLE/Contents/MacOS/$APP_NAME" << WRAPPER
#!/bin/zsh
# sm64-macaroni cwd wrapper — auto-generated by sm64-macaroni-bundle.sh v$VERSION
export DYLD_LIBRARY_PATH="\${0:A:h}/../libs:/usr/local/lib:\${DYLD_LIBRARY_PATH:-}"
export DYLD_FALLBACK_LIBRARY_PATH="\${0:A:h}/../libs:/usr/local/lib:\${DYLD_FALLBACK_LIBRARY_PATH:-}"
cd "\${0:A:h}/../Resources"
exec "\${0:A:h}/${APP_NAME}Bin" "\$@"
WRAPPER
chmod +x "$BUNDLE/Contents/MacOS/$APP_NAME"
echo "    ✅ ${APP_NAME}Bin (real binary) + $APP_NAME (wrapper, cwd → Resources/)" | tee -a "$LOGFILE"

# ── Step 4: Icon ──────────────────────────────────────────────────────────────
echo "" | tee -a "$LOGFILE"
echo "🖼  Step 4: Icon → Resources/" | tee -a "$LOGFILE"
cp "$ICNS_BUILT" "$ICNS_DEST"
echo "    ✅ ${ICON_BASENAME}.icns" | tee -a "$LOGFILE"

# ── Step 5: Runtime assets ────────────────────────────────────────────────────
# With EXTERNAL_DATA=1, sm64ex looks for res/ next to the binary at runtime
# (or cwd-relative). The wrapper cds to Resources/ so res/ goes there.
echo "" | tee -a "$LOGFILE"
echo "📦 Step 5: Runtime assets" | tee -a "$LOGFILE"
if (( RES_FOUND )); then
    cp -R "$RES_SOURCE" "$BUNDLE/Contents/Resources/res"
    echo "    ✅ res/ → Resources/res/ ($(du -sh "$BUNDLE/Contents/Resources/res" | cut -f1))" | tee -a "$LOGFILE"
else
    echo "    · res/ skipped (not present in build)" | tee -a "$LOGFILE"
fi

# ── Step 6: Info.plist ────────────────────────────────────────────────────────
echo "" | tee -a "$LOGFILE"
echo "📄 Step 6: Info.plist" | tee -a "$LOGFILE"
cat > "$BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>             <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>      <string>$DISPLAY_NAME</string>
    <key>CFBundleIdentifier</key>       <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>          <string>$VERSION</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleExecutable</key>       <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>         <string>$ICON_BASENAME</string>
    <key>CFBundlePackageType</key>      <string>APPL</string>
    <key>LSMinimumSystemVersion</key>   <string>10.9</string>
    <key>NSHighResolutionCapable</key>  <true/>
    <key>NSHumanReadableCopyright</key> <string>mkoterski / sm64ex-family upstream maintainers</string>
</dict>
</plist>
PLIST
echo "    ✅ CFBundleIdentifier: $BUNDLE_ID" | tee -a "$LOGFILE"
echo "    ✅ LSMinimumSystemVersion: 10.9" | tee -a "$LOGFILE"

# ── Step 7: Bundle dylibs (haframjolk pattern) ────────────────────────────────
# dylibbundler walks the binary's @rpath/@executable_path/@loader_path load
# commands, copies referenced dylibs into Contents/libs/, and rewrites the
# binary to use @executable_path/../libs/<dylib>. Result: the .app runs on
# any Intel Mac without Homebrew installed.
echo "" | tee -a "$LOGFILE"
echo "🔗 Step 7: Bundle dylibs via dylibbundler" | tee -a "$LOGFILE"
dylibbundler -b -cd -of \
    -x "$BUNDLE/Contents/MacOS/${APP_NAME}Bin" \
    -d "$BUNDLE/Contents/libs/" \
    -p "@executable_path/../libs/" \
    2>&1 | tee -a "$LOGFILE"
LIB_COUNT=$(ls -1 "$BUNDLE/Contents/libs/" 2>/dev/null | wc -l | tr -d ' ')
echo "    ✅ $LIB_COUNT dylib(s) bundled, $(du -sh "$BUNDLE/Contents/libs" | cut -f1) total" | tee -a "$LOGFILE"

# ── Step 7.5: Dedupe LC_RPATH entries ─────────────────────────────────────────
# sm64ex's Makefile (OSX_BUILD=1 path) adds @executable_path/../libs/ as an
# LC_RPATH at link time, intended for haframjolk-style bundling. dylibbundler
# adds the same rpath again when it patches load commands. Result: the Mach-O
# has two identical LC_RPATH entries.
#
# dyld on macOS 14+ became strict about duplicate rpaths and aborts process
# launch with SIGABRT before any code runs:
#     "Termination Reason: Namespace DYLD, Code 0,
#      duplicate LC_RPATH '@executable_path/../libs/'"
#
# Fix: enumerate all LC_RPATH paths via otool, delete every occurrence
# (install_name_tool -delete_rpath only removes one match per call, hence the
# loop), then re-add only the unique set. Has to run before codesign because
# load-command edits invalidate the existing signature.
echo "" | tee -a "$LOGFILE"
echo "🧹 Step 7.5: Dedupe LC_RPATH entries" | tee -a "$LOGFILE"
BIN="$BUNDLE/Contents/MacOS/${APP_NAME}Bin"

get_rpaths() {
    otool -l "$1" | awk '
        /cmd LC_RPATH/ { in_lc=1; next }
        in_lc && /^[[:space:]]*path / {
            sub(/^[[:space:]]*path /, "")
            sub(/ \(offset.*$/, "")
            print
            in_lc=0
        }'
}

# Snapshot the original list (preserving duplicates) and the unique set.
ORIG_RPATHS=("${(@f)$(get_rpaths "$BIN")}")
ORIG_RPATHS=("${(@)ORIG_RPATHS:#}")          # drop empty entries
UNIQUE_RPATHS=("${(@u)ORIG_RPATHS}")          # zsh (u) flag: deduplicate

# Delete every rpath in load order. install_name_tool removes only the first
# occurrence per call, so we re-query the head of the list each iteration.
while true; do
    NEXT="$(get_rpaths "$BIN" | head -1)"
    [[ -z "$NEXT" ]] && break
    install_name_tool -delete_rpath "$NEXT" "$BIN" 2>&1 | tee -a "$LOGFILE" || break
done

# Re-add the unique rpaths in their original first-seen order.
for rpath in "${UNIQUE_RPATHS[@]}"; do
    [[ -z "$rpath" ]] && continue
    install_name_tool -add_rpath "$rpath" "$BIN" 2>&1 | tee -a "$LOGFILE"
done

echo "    ✅ ${#ORIG_RPATHS[@]} rpath(s) → ${#UNIQUE_RPATHS[@]} unique" | tee -a "$LOGFILE"
echo "       Final rpaths in binary:" | tee -a "$LOGFILE"
get_rpaths "$BIN" | sed 's/^/         · /' | tee -a "$LOGFILE"

# ── Step 8: Quarantine attrs + ad-hoc codesign ────────────────────────────────
# xattr -cr alone is not sufficient on Tahoe (per spaghettikart-maccheese
# notes) — Gatekeeper additionally requires the bundle to be signed. Ad-hoc
# signing (-) skips the developer cert requirement and works for personal
# use; users still get the right-click → Open prompt on first launch but
# the binary itself doesn't get killed. Must run AFTER Step 7.5 because
# load-command edits invalidate any existing signature.
echo "" | tee -a "$LOGFILE"
echo "🛡  Step 8: Quarantine attrs + ad-hoc codesign" | tee -a "$LOGFILE"
xattr -cr "$BUNDLE" 2>&1 | tee -a "$LOGFILE" || true
codesign --sign - --force --deep "$BUNDLE" 2>&1 | tee -a "$LOGFILE"
echo "    ✅ ad-hoc signed" | tee -a "$LOGFILE"

# ── Step 9: Verify bundle ─────────────────────────────────────────────────────
echo "" | tee -a "$LOGFILE"
echo "🔍 Step 9: Verify bundle" | tee -a "$LOGFILE"
echo "    Binary:    $(file "$BUNDLE/Contents/MacOS/${APP_NAME}Bin" | grep -o 'Mach-O.*')" | tee -a "$LOGFILE"
echo "    Wrapper:   $(file "$BUNDLE/Contents/MacOS/${APP_NAME}" | head -1 | sed 's|.*: ||')" | tee -a "$LOGFILE"
echo "    Icon:      $(du -h "$ICNS_DEST" | cut -f1)" | tee -a "$LOGFILE"
[[ -d "$BUNDLE/Contents/Resources/res" ]] && \
    echo "    res/:      $(du -sh "$BUNDLE/Contents/Resources/res" | cut -f1)" | tee -a "$LOGFILE"
echo "    libs/:     $LIB_COUNT dylib(s)" | tee -a "$LOGFILE"
echo "    Bundle:    $(du -sh "$BUNDLE" | cut -f1) total" | tee -a "$LOGFILE"
echo "    Signature: $(codesign -dv "$BUNDLE" 2>&1 | grep -i 'signature' | head -1)" | tee -a "$LOGFILE"

# ── Summary ───────────────────────────────────────────────────────────────────
echo "" | tee -a "$LOGFILE"
echo "════════════════════════════════════════════════════════════════" | tee -a "$LOGFILE"
echo "✅ sm64-macaroni-bundle.sh v$VERSION complete!" | tee -a "$LOGFILE"
echo "    🎯 Upstream: $UPSTREAM ($REPO_NAME)" | tee -a "$LOGFILE"
echo "    📍 $BUNDLE" | tee -a "$LOGFILE"
echo "    📄 $LOGFILE" | tee -a "$LOGFILE"
echo "    👉 Test:    open \"$BUNDLE\"" | tee -a "$LOGFILE"
echo "    👉 Package: ./sm64-macaroni-package.sh --upstream $UPSTREAM" | tee -a "$LOGFILE"
echo "════════════════════════════════════════════════════════════════" | tee -a "$LOGFILE"
