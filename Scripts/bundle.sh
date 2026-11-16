#!/bin/bash
# Builds MemWatch.app (universal: arm64 + x86_64), signs it ad-hoc and copies it
# to ~/Applications.
#
# Options:
#   --no-install            only build build/MemWatch.app; do not quit or replace
#                           the installed app (same as MEMWATCH_NO_INSTALL=1)
# Environment:
#   MEMWATCH_VERSION=1.2.3  version written to Info.plist (default 0.1.0)
#   MEMWATCH_NO_INSTALL=1   same as --no-install
set -euo pipefail

NO_INSTALL="${MEMWATCH_NO_INSTALL:-0}"
for arg in "$@"; do
    case "$arg" in
        --no-install) NO_INSTALL=1 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done
VERSION="${MEMWATCH_VERSION:-0.1.0}"
# CFBundleVersion must be numbers and dots only: drop "-beta.1" or "+abc123".
BUILD_NUMBER="${VERSION%%[-+]*}"

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="$ROOT/build/MemWatch.app"
DEST="$HOME/Applications/MemWatch.app"
BUILD_ARGS=(-c release --arch arm64 --arch x86_64)

echo "==> swift build ${BUILD_ARGS[*]}"
swift build "${BUILD_ARGS[@]}"
BIN="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)/MemWatch"
lipo -info "$BIN"

echo "==> Building $APP (version $VERSION)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MemWatch"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MemWatch</string>
    <key>CFBundleIdentifier</key>
    <string>local.memwatch</string>
    <key>CFBundleName</key>
    <string>MemWatch</string>
    <key>CFBundleDisplayName</key>
    <string>MemWatch</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "==> codesign (ad-hoc)"
codesign --force --deep -s - "$APP"
codesign --verify --verbose=1 "$APP"

if [ "$NO_INSTALL" = "1" ]; then
    echo "Done. Built $APP (not installed)."
    exit 0
fi

# If an older copy is running, ask it to quit (a normal quit, not a kill).
if pgrep -x MemWatch >/dev/null 2>&1; then
    echo "==> Asking the running MemWatch to quit"
    osascript -e 'tell application id "local.memwatch" to quit' || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -x MemWatch >/dev/null 2>&1 || break
        sleep 0.5
    done
fi

echo "==> Copying to $DEST"
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
ditto "$APP" "$DEST"

echo "Done. Start it with: open \"$DEST\""
