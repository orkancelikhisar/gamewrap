#!/bin/zsh
# Builds GameWrap.app (release, Apple Silicon) and installs it into the given folder.
# Usage: scripts/package-app.sh [destination folder, default ~/Applications]
set -euo pipefail

HERE="${0:A:h:h}"
DEST="${1:-$HOME/Applications}"
# Keep build products outside iCloud-synced folders: File Provider attributes break codesign.
BUILD="${TMPDIR:-/tmp/}gamewrap-build"
cd "$HERE"

swift build -c release --arch arm64 --product GameWrap --scratch-path "$BUILD"
BIN="$(swift build -c release --arch arm64 --scratch-path "$BUILD" --show-bin-path)/GameWrap"

WORK="$(mktemp -d /tmp/gamewrap-app.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/GameWrap.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/GameWrap"
cp "$HERE/assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$HERE/LICENSE" "$APP/Contents/Resources/LICENSE.txt"
cp "$HERE/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>GameWrap</string>
	<key>CFBundleDisplayName</key><string>GameWrap</string>
	<key>CFBundleIdentifier</key><string>io.github.gamewrap</string>
	<key>CFBundleExecutable</key><string>GameWrap</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>CFBundleShortVersionString</key><string>0.1.0</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
	<key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

xattr -cr "$APP"
codesign --force -s - "$APP"
codesign --verify "$APP"

mkdir -p "$DEST"
rm -rf "$DEST/GameWrap.app"
ditto "$APP" "$DEST/GameWrap.app"
echo "Installed $DEST/GameWrap.app"
