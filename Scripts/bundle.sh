#!/bin/bash
# Builds MemWatch.app, signs it ad-hoc and copies it to ~/Applications.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="$ROOT/build/MemWatch.app"
DEST="$HOME/Applications/MemWatch.app"

echo "==> swift build -c release"
swift build -c release

echo "==> Building $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/MemWatch" "$APP/Contents/MacOS/MemWatch"

cat > "$APP/Contents/Info.plist" <<'PLIST'
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
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
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
