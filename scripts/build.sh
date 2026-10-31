#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'Native build requires macOS with Xcode Command Line Tools.' >&2
  exit 1
fi
xcrun --find swiftc >/dev/null
BUILD_ROOT="$PWD/build/0.4.0"
APP="$BUILD_ROOT/FolderTerm.app"
HELPER="$APP/Contents/Helpers/FolderTermToolbar.app"
mkdir -p "$BUILD_ROOT"
# Only replace the generated candidate, never the user's installed app.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" \
  "$HELPER/Contents/MacOS" "$HELPER/Contents/Resources" "$BUILD_ROOT/FolderTerm.iconset"
MODULE_CACHE="$PWD/build/module-cache"
mkdir -p "$MODULE_CACHE"
ARCH="$(uname -m)"
case "$ARCH" in arm64|x86_64) ;; *) echo "Unsupported architecture: $ARCH" >&2; exit 1;; esac
xcrun clang -target "$ARCH-apple-macosx12.0" -c Sources/ToolbarAliasBridge.c -o "$BUILD_ROOT/ToolbarAliasBridge.o"
xcrun swiftc -swift-version 5 -O -module-cache-path "$MODULE_CACHE" -target "$ARCH-apple-macosx12.0" \
  -import-objc-header Sources/ToolbarAliasBridge.h "$BUILD_ROOT/ToolbarAliasBridge.o" \
  -framework AppKit Sources/Core.swift Sources/Settings.swift Sources/ConfigurationLifecycle.swift \
  Sources/ToolbarPreferencesModel.swift Sources/ToolbarReference.swift Sources/ToolbarTransaction.swift \
  Sources/FinderToolbarStore.swift Sources/ToolbarInstaller.swift Sources/main.swift \
  -o "$APP/Contents/MacOS/FolderTerm"
xcrun swiftc -swift-version 5 -O -module-cache-path "$MODULE_CACHE" -target "$ARCH-apple-macosx12.0" \
  -framework AppKit -framework Carbon Sources/Core.swift Sources/Settings.swift Sources/ToolbarAction.swift \
  Sources/Automation.swift Sources/Toolbar/main.swift -o "$HELPER/Contents/MacOS/FolderTermToolbar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Toolbar-Info.plist "$HELPER/Contents/Info.plist"
cp Resources/*.applescript "$HELPER/Contents/Resources/"
xcrun swift -module-cache-path "$MODULE_CACHE" scripts/make-icon.swift "$BUILD_ROOT/FolderTerm.iconset"
iconutil -c icns "$BUILD_ROOT/FolderTerm.iconset" -o "$APP/Contents/Resources/FolderTerm.icns"
cp "$APP/Contents/Resources/FolderTerm.icns" "$HELPER/Contents/Resources/FolderTerm.icns"
# Ad-hoc local build, not a notarized public distribution. Pass a Developer ID
# identity explicitly only when you own that identity and intend to sign.
codesign --force --options runtime --entitlements Resources/Toolbar.entitlements \
  --sign "${SIGN_IDENTITY:--}" "$HELPER"
codesign --force --options runtime --sign "${SIGN_IDENTITY:--}" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
for source in Resources/Finder.applescript Resources/Terminal.applescript; do
  # Compilation only: never execute the scripts as part of the build.
  osacompile -o "$BUILD_ROOT/$(basename "$source" .applescript).scpt" "$source"
done
if [[ "${VALIDATE_ITERM:-0}" == 1 ]]; then
  osacompile -o "$BUILD_ROOT/iTerm2.scpt" Resources/iTerm2.applescript
fi
printf '\nBuilt configuration app: %s\nToolbar entry: %s\nArchitecture: %s\nNot installed or launched.\n' "$APP" "$HELPER" "$ARCH"
