#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
sdk="$(xcrun --sdk macosx --show-sdk-path)"
minimum_os="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Info.plist)"
work="$(mktemp -d "${TMPDIR:-/tmp}/calendarlens.XXXXXX")"
trap 'rm -rf "$work"' EXIT

xcrun swiftc -sdk "$sdk" -target "arm64-apple-macos${minimum_os}" \
    -swift-version 5 -parse-as-library -O \
    -module-name calendarLens -module-cache-path "$work/ModuleCache" \
    -file-prefix-map "$PWD=." -debug-prefix-map "$PWD=." \
    ./*.swift -framework SwiftUI -framework AppKit -framework EventKit -framework Combine \
    -o "$work/calendarLens"

app="$work/calendarLens.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
mv "$work/calendarLens" "$app/Contents/MacOS/calendarLens"
cp Info.plist "$app/Contents/Info.plist"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $version" "$app/Contents/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $version" "$app/Contents/Info.plist"
cp AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp Credits.rtf "$app/Contents/Resources/Credits.rtf"
xattr -cr "$app"
codesign --force --sign - --identifier com.calendarlens.app \
    --options runtime --entitlements calendarLens.entitlements "$app"
codesign --verify --strict "$app"
xcrun lipo "$app/Contents/MacOS/calendarLens" -verify_arch arm64

rm -rf calendarLens.app
mv "$app" calendarLens.app
echo "Built calendarLens.app"