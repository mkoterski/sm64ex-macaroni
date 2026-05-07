#!/bin/zsh
# sm64-macaroni-bundle.sh
# sm64 Macaroni — Intel Mac / macOS Tahoe app bundle creator
#
# Two bundling strategies based on what the upstream Makefile produces:
#
#   1. Build-from-scratch (sm64ex, render96ex):
#      Upstream produces a bare binary at build/us_pc/<name>. We construct
#      a .app bundle around it: cwd-wrapper, our Info.plist, our icon,
#      dylibbundler-bundled Homebrew dylibs, ad-hoc codesign.
#
#   2. Adopt-upstream-app (coopdx):
#      Upstream's Makefile already produces a complete, self-contained
#      .app at build/us_pc/<name>.app — binary, sibling dylibs, and its
#      own Info.plist all in place. We copy that .app to dist/, dedupe
#      any duplicate LC_RPATH entries the linker accumulated, rewrite
#      CFBundleIdentifier to our namespace (com.mkoterski.sm64-macaroni.*)
#      so multiple Macaroni-bundled coopdx variants don't collide in
#      Launch Services, and re-sign ad-hoc.
#
# Auto-detects the upstream from the most-recently-built artifact, or use
# --upstream <preset> to force a specific tree.
#
# Usage:
#     ./sm64-macaroni-bundle.sh                      # auto-detect
#     ./sm64-macaroni-bundle.sh --upstream sm64ex
#     ./sm64-macaroni-bundle.sh --upstream coopdx
#     ./sm64-macaroni-bundle.sh --upstream render96ex   # ❌ broken upstream
#
# Output:
#     dist/<App>.app               ← drag-to-Applications ready
#         dist/sm64ex.app          (sm64ex preset, build-from-scratch)
#         dist/sm64coopdx.app      (coopdx preset, adopt-upstream-app)
#     logs/bundle-<preset>-<timestamp>.log
#
# Icon source (build-from-scratch path only):
#     src/icon.icns           ← preferred: use as-is
#     src/icon.png            ← fallback: convert via sips + iconutil
#     (placeholder)           ← final fallback: Mario-red stub
# (coopdx adopt-upstream-app path keeps upstream's icon intact.)
#
# CHANGELOG
#   v0.14 (2026-05-06) - Added adopt-upstream-app strategy for coopdx, where
#                        the upstream Makefile (OSX_APP_BUILD path) already
#                        produces a complete .app at build/us_pc/sm64coopdx
#                        .app. Copying + sanitizing that .app is meaningfully
#                        cleaner than the build-from-scratch approach used
#                        for sm64ex — upstream knows its own dylib layout
#                        better than we do, so we don't run dylibbundler or
#                        author our own Info.plist for it. Strategy is
#                        keyed off a per-preset UPSTREAM_PROVIDES_APP flag.
#                        sm64ex / render96ex retain the original build-
#                        from-scratch path. Both strategies share the
#                        LC_RPATH dedup + ad-hoc codesign tail.
#                        Bundle ID rewrite for coopdx: upstream sets its
#                        own CFBundleIdentifier, but we want a stable
#                        com.mkoterski.sm64-macaroni.* namespace so that
#                        any future Macaroni-bundled variants live
#                        peacefully alongside any direct upstream install.
#   v0.13 (2026-05-05) - Repo renamed sm64ex-macaroni → sm64-macaroni,
#                        bundle ID prefix migrated.
#   v0.12 (2026-05-05) - Log filename includes upstream preset.
#   v0.11 (2026-05-05) - Step 7.5 LC_RPATH dedup fix for dyld SIGABRT.
#   v0.10 (2026-05-05) - Initial version; adapted from spmc-bundle.sh v0.10.

set -eo pipefail

VERSION="0.14"
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
        *) echo "Usage: $0 [--upstream <sm64ex|coopdx|render96ex>]" >&2; exit 1 ;;
    esac
done

# ── Auto-detect upstream if not specified ─────────────────────────────────────
typeset -A PRESET_DIR
PRESET_DIR=(sm64ex "sm64ex" coopdx "sm64coopdx" render96ex "Render96ex")

if [[ -z "$UPSTREAM" ]]; then
    LATEST_MTIME=0
    for p in sm64ex coopdx render96ex; do
        for bin in "$SCRIPT_DIR/${PRESET_DIR[$p]}/build/us_pc/sm64.us.f3dex2e" \
                   "$SCRIPT_DIR/${PRESET_DIR[$p]}/build/us_pc/sm64coopdx.app/Contents/MacOS/sm64coopdx" \
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
# UPSTREAM_PROVIDES_APP toggles the bundling strategy:
#   0: build-from-scratch — we author Info.plist, dylibbundler, etc.
#   1: adopt-upstream-app — copy upstream's .app, sanitize, re-sign
case "$UPSTREAM" in
    sm64ex)
        REPO_NAME="sm64ex"
        BIN_NAME_PRIMARY="sm64.us.f3dex2e"
        APP_NAME="sm64ex"
        DISPLAY_NAME="Super Mario 64 (sm64 Macaroni)"
        BUNDLE_ID="com.mkoterski.sm64-macaroni.sm64ex"
        ICON_BASENAME="sm64ex"
        UPSTREAM_PROVIDES_APP=0
        UPSTREAM_APP_PATH=""  # built by us
        ;;
    render96ex)
        REPO_NAME="Render96ex"
        BIN_NAME_PRIMARY="sm64.us.f3dex2e"
        APP_NAME="Render96"
        DISPLAY_NAME="Super Mario 64 Render96 (sm64 Macaroni)"
        BUNDLE_ID="com.mkoterski.sm64-macaroni.render96ex"
        ICON_BASENAME="render96"
        UPSTREAM_PROVIDES_APP=0
        UPSTREAM_APP_PATH=""
        ;;
    coopdx)
        REPO_NAME="sm64coopdx"
        BIN_NAME_PRIMARY="sm64coopdx"
        APP_NAME="sm64coopdx"
        DISPLAY_NAME="Super Mario 64 Coop Deluxe (sm64 Macaroni)"
        BUNDLE_ID="com.mkoterski.sm64-macaroni.coopdx"
        ICON_BASENAME="sm64coopdx"
        UPSTREAM_PROVIDES_APP=1
        UPSTREAM_APP_PATH="$SCRIPT_DIR/sm64coopdx/build/us_pc/sm64coopdx.app"
        ;;
    *)
        echo "❌ Unknown --upstream preset: $UPSTREAM" >&2
        echo "   Valid: sm64ex, coopdx, render96ex" >&2
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
echo "    Strategy:    $([[ $UPSTREAM_PROVIDES_APP -eq 1 ]] && echo "adopt-upstream-app" || echo "build-from-scratch")" | tee -a "$LOGFILE"
echo "    Log:         $LOGFILE" | tee -a "$LOGFILE"

# ────────────────────────────────────────────────────────────────────────────
# Shared helper: dedupe LC_RPATH entries.
#
# Used by both bundling strategies, but for different reasons:
#   - build-from-scratch: sm64ex's link-time rpath + dylibbundler's rpath
#     produce duplicates that dyld 14+ rejects (SIGABRT before any code runs).
#   - adopt-upstream-app: upstream's linker may emit duplicates from multiple
#     LDFLAGS slots (we saw 4× in the build script log for sm64coopdx).
#     Same dyld behavior, same fix.
# ────────────────────────────────────────────────────────────────────────────
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

dedupe_rpaths() {
    local bin="$1"
    local orig_rpaths
    orig_rpaths=("${(@f)$(get_rpaths "$bin")}")
    orig_rpaths=("${(@)orig_rpaths:#}")
    local unique_rpaths
    unique_rpaths=("${(@u)orig_rpaths}")

    while true; do
        local next
        next="$(get_rpaths "$bin" | head -1)"
        [[ -z "$next" ]] && break
        install_name_tool -delete_rpath "$next" "$bin" 2>&1 | tee -a "$LOGFILE" || break
    done
    for rpath in "${unique_rpaths[@]}"; do
        [[ -z "$rpath" ]] && continue
        install_name_tool -add_rpath "$rpath" "$bin" 2>&1 | tee -a "$LOGFILE"
    done
    echo "    ✅ ${#orig_rpaths[@]} rpath(s) → ${#unique_rpaths[@]} unique" | tee -a "$LOGFILE"
    echo "       Final rpaths in binary:" | tee -a "$LOGFILE"
    get_rpaths "$bin" | sed 's/^/         · /' | tee -a "$LOGFILE"
}

# ════════════════════════════════════════════════════════════════════════════
# Strategy A: adopt-upstream-app (coopdx)
# ════════════════════════════════════════════════════════════════════════════
if (( UPSTREAM_PROVIDES_APP )); then
    echo "" | tee -a "$LOGFILE"
    echo "🔍 Preflight checks" | tee -a "$LOGFILE"
    if [[ ! -d "$UPSTREAM_APP_PATH" ]]; then
        echo "    ❌ Upstream .app not found at:" | tee -a "$LOGFILE"
        echo "       $UPSTREAM_APP_PATH" | tee -a "$LOGFILE"
        echo "       Run: ./sm64-macaroni-build.sh --upstream $UPSTREAM" | tee -a "$LOGFILE"
        exit 1
    fi
    UPSTREAM_BIN="$UPSTREAM_APP_PATH/Contents/MacOS/$BIN_NAME_PRIMARY"
    if [[ ! -f "$UPSTREAM_BIN" ]]; then
        echo "    ❌ Upstream .app is malformed — missing binary at:" | tee -a "$LOGFILE"
        echo "       Contents/MacOS/$BIN_NAME_PRIMARY" | tee -a "$LOGFILE"
        exit 1
    fi
    echo "    ✅ Upstream .app: $(du -sh "$UPSTREAM_APP_PATH" | cut -f1)" | tee -a "$LOGFILE"
    echo "    ✅ Binary:        ${BIN_NAME_PRIMARY} ($(du -h "$UPSTREAM_BIN" | cut -f1))" | tee -a "$LOGFILE"

    # Step 1: copy the upstream .app verbatim.
    echo "" | tee -a "$LOGFILE"
    echo "📋 Step 1: Copy upstream .app → dist/" | tee -a "$LOGFILE"
    rm -rf "$BUNDLE"
    cp -R "$UPSTREAM_APP_PATH" "$BUNDLE"
    echo "    ✅ $BUNDLE ($(du -sh "$BUNDLE" | cut -f1))" | tee -a "$LOGFILE"

    # Step 2: rewrite CFBundleIdentifier to our namespace.
    # We use PlistBuddy (ships with macOS) for a robust XML edit. defaults(1)
    # would also work but rewrites the whole plist in binary format, which
    # is harder to inspect during debugging.
    echo "" | tee -a "$LOGFILE"
    echo "🪪 Step 2: Rewrite CFBundleIdentifier → $BUNDLE_ID" | tee -a "$LOGFILE"
    PLIST="$BUNDLE/Contents/Info.plist"
    OLD_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$PLIST" 2>/dev/null || echo "<unset>")"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$PLIST" 2>&1 | tee -a "$LOGFILE" || \
        /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $BUNDLE_ID" "$PLIST" 2>&1 | tee -a "$LOGFILE"
    echo "    ✅ Was: $OLD_BUNDLE_ID" | tee -a "$LOGFILE"
    echo "    ✅ Now: $BUNDLE_ID" | tee -a "$LOGFILE"

    # Step 3: dedupe LC_RPATH entries on the binary.
    echo "" | tee -a "$LOGFILE"
    echo "🧹 Step 3: Dedupe LC_RPATH entries" | tee -a "$LOGFILE"
    BIN="$BUNDLE/Contents/MacOS/$BIN_NAME_PRIMARY"
    dedupe_rpaths "$BIN"

    # Step 4: quarantine attrs + ad-hoc codesign.
    echo "" | tee -a "$LOGFILE"
    echo "🛡  Step 4: Quarantine attrs + ad-hoc codesign" | tee -a "$LOGFILE"
    xattr -cr "$BUNDLE" 2>&1 | tee -a "$LOGFILE" || true
    codesign --sign - --force --deep "$BUNDLE" 2>&1 | tee -a "$LOGFILE"
    echo "    ✅ ad-hoc signed" | tee -a "$LOGFILE"

    # Step 5: verify.
    echo "" | tee -a "$LOGFILE"
    echo "🔍 Step 5: Verify bundle" | tee -a "$LOGFILE"
    echo "    Binary:    $(file "$BIN" | grep -o 'Mach-O.*')" | tee -a "$LOGFILE"
    echo "    Bundle:    $(du -sh "$BUNDLE" | cut -f1) total" | tee -a "$LOGFILE"
    echo "    Bundle ID: $(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$PLIST" 2>/dev/null)" | tee -a "$LOGFILE"
    echo "    Signature: $(codesign -dv "$BUNDLE" 2>&1 | grep -i 'signature' | head -1)" | tee -a "$LOGFILE"

    echo "" | tee -a "$LOGFILE"
    echo "════════════════════════════════════════════════════════════════" | tee -a "$LOGFILE"
    echo "✅ sm64-macaroni-bundle.sh v$VERSION complete!" | tee -a "$LOGFILE"
    echo "    🎯 Upstream: $UPSTREAM ($REPO_NAME) — adopt-upstream-app" | tee -a "$LOGFILE"
    echo "    📍 $BUNDLE" | tee -a "$LOGFILE"
    echo "    📄 $LOGFILE" | tee -a "$LOGFILE"
    echo "    👉 Test:    open \"$BUNDLE\"" | tee -a "$LOGFILE"
    echo "════════════════════════════════════════════════════════════════" | tee -a "$LOGFILE"
    exit 0
fi

# ════════════════════════════════════════════════════════════════════════════
# Strategy B: build-from-scratch (sm64ex, render96ex)
# ════════════════════════════════════════════════════════════════════════════

# ── Locate binary ─────────────────────────────────────────────────────────────
BINARY=""
for candidate in "$BUILD_DIR/$BIN_NAME_PRIMARY" \
                 "$BUILD_DIR/sm64.us.f3dex2e" \
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
echo "" | tee -a "$LOGFILE"
echo "🧹 Step 7.5: Dedupe LC_RPATH entries" | tee -a "$LOGFILE"
dedupe_rpaths "$BUNDLE/Contents/MacOS/${APP_NAME}Bin"

# ── Step 8: Quarantine attrs + ad-hoc codesign ────────────────────────────────
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
echo "    🎯 Upstream: $UPSTREAM ($REPO_NAME) — build-from-scratch" | tee -a "$LOGFILE"
echo "    📍 $BUNDLE" | tee -a "$LOGFILE"
echo "    📄 $LOGFILE" | tee -a "$LOGFILE"
echo "    👉 Test:    open \"$BUNDLE\"" | tee -a "$LOGFILE"
echo "    👉 Package: ./sm64-macaroni-package.sh --upstream $UPSTREAM" | tee -a "$LOGFILE"
echo "════════════════════════════════════════════════════════════════" | tee -a "$LOGFILE"
