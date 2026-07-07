#!/usr/bin/env bash
set -euo pipefail

APP_NAME="FastSortClientMac"
BUNDLE_NAME="FastSortClientMac.app"
BUNDLE_ID="cn.xunjian.fast-sort-client.mac"
DISPLAY_NAME="迅拣"
VERSION="0.1.0"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$PROJECT_DIR/dist"
APP_DIR="$DIST_DIR/$BUNDLE_NAME"
EXECUTABLE="$PROJECT_DIR/.build/release/$APP_NAME"
PLIST="$APP_DIR/Contents/Info.plist"
ZIP_PATH="$DIST_DIR/FastSortClientMac-macOS-test.zip"

swift build -c release --package-path "$PROJECT_DIR"

rm -rf "$APP_DIR" "$ZIP_PATH"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

plutil -create xml1 "$PLIST"
plutil -insert CFBundleDevelopmentRegion -string "zh_CN" "$PLIST"
plutil -insert CFBundleDisplayName -string "$DISPLAY_NAME" "$PLIST"
plutil -insert CFBundleExecutable -string "$APP_NAME" "$PLIST"
plutil -insert CFBundleIdentifier -string "$BUNDLE_ID" "$PLIST"
plutil -insert CFBundleInfoDictionaryVersion -string "6.0" "$PLIST"
plutil -insert CFBundleName -string "$DISPLAY_NAME" "$PLIST"
plutil -insert CFBundlePackageType -string "APPL" "$PLIST"
plutil -insert CFBundleShortVersionString -string "$VERSION" "$PLIST"
plutil -insert CFBundleVersion -string "$(date +%Y%m%d%H%M)" "$PLIST"
plutil -insert LSMinimumSystemVersion -string "14.0" "$PLIST"
plutil -insert NSHighResolutionCapable -bool true "$PLIST"
plutil -insert NSQuitAlwaysKeepsWindows -bool false "$PLIST"
plutil -insert ApplePersistenceIgnoreState -bool true "$PLIST"
plutil -insert NSAppTransportSecurity -xml '<dict><key>NSAllowsArbitraryLoads</key><false/><key>NSAllowsLocalNetworking</key><true/></dict>' "$PLIST"

codesign --force --deep --sign - "$APP_DIR"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

printf 'App: %s\nZip: %s\n' "$APP_DIR" "$ZIP_PATH"
