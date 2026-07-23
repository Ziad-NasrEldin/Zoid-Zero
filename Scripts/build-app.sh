#!/bin/zsh

set -euo pipefail

ROOT="${0:A:h:h}"
CONFIGURATION="${1:-release}"
APP="$ROOT/.build/Zoid 0.app"
EXTENSION_PROJECT="$ROOT/SafariExtension/HostProject/Zoid 0/Zoid 0.xcodeproj"
EXTENSION_BUILD_DIR="$ROOT/.build/safari-extension"
EXTENSION_PRODUCT="$EXTENSION_BUILD_DIR/Zoid 0 Extension.appex"
SIGNING_IDENTITY="${ZOID_ZERO_SIGNING_IDENTITY:-$(security find-identity -v -p codesigning | awk -F '"' '/Apple Development/{print $2; exit}')}"

if [[ -z "$SIGNING_IDENTITY" ]]; then
  echo "No code-signing identity is available. Set ZOID_ZERO_SIGNING_IDENTITY." >&2
  exit 1
fi

swift build --package-path "$ROOT" -c "$CONFIGURATION" --product ZoidZero
BIN_DIR="$(swift build --package-path "$ROOT" -c "$CONFIGURATION" --show-bin-path)"
xcodebuild \
  -project "$EXTENSION_PROJECT" \
  -target "Zoid 0 Extension" \
  -configuration Release \
  CODE_SIGNING_ALLOWED=NO \
  ENABLE_APPINTENTS_METADATA_PROCESSING=NO \
  CONFIGURATION_BUILD_DIR="$EXTENSION_BUILD_DIR" \
  build

if [[ ! -d "$EXTENSION_PRODUCT" ]]; then
  echo "Safari extension build product is missing." >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/PlugIns"
cp "$BIN_DIR/ZoidZero" "$APP/Contents/MacOS/ZoidZero"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp -R "$EXTENSION_PRODUCT" "$APP/Contents/PlugIns/Zoid 0 Extension.appex"
codesign \
  --force \
  --options runtime \
  --timestamp=none \
  --entitlements "$ROOT/SafariExtension/ZoidSafariExtension.entitlements" \
  --sign "$SIGNING_IDENTITY" \
  "$APP/Contents/PlugIns/Zoid 0 Extension.appex"
codesign \
  --force \
  --options runtime \
  --timestamp=none \
  --entitlements "$ROOT/Resources/ZoidZero.entitlements" \
  --sign "$SIGNING_IDENTITY" \
  "$APP"

if ! codesign -d --entitlements :- "$APP" 2>/dev/null \
  | grep -q "com.apple.security.personal-information.calendars"; then
  echo "Calendar entitlement is missing from the signed app." >&2
  exit 1
fi

if ! codesign -d --entitlements :- "$APP" 2>/dev/null \
  | grep -q "com.apple.security.app-sandbox"; then
  echo "App Sandbox entitlement is missing from the signed app." >&2
  exit 1
fi

if ! codesign -d --entitlements :- "$APP" 2>/dev/null \
  | grep -q "group.com.ziadnasreldin.zoidzero"; then
  echo "Shared app group entitlement is missing from the signed app." >&2
  exit 1
fi

echo "$APP"
