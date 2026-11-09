#!/bin/bash
# Baut die iPhone-App (IPA, ad hoc signiert – zum Neu-Signieren mit Signulous). Aufruf: scripts/baue.sh [Version]
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:-$(cat VERSION)}"
NUMMER="$(echo "$VERSION" | awk -F. '{ printf "%d%02d%02d", $1, $2, $3 }')"
rm -rf build && mkdir -p build
swift scripts/symbol.swift ressourcen/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
command -v xcodegen >/dev/null || brew install xcodegen
xcodegen generate --spec project.yml --quiet
xcodebuild -project GutenMorgen.xcodeproj -scheme GutenMorgen -configuration Release -derivedDataPath build/dd -sdk iphoneos -destination generic/platform=iOS \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$NUMMER" CODE_SIGNING_ALLOWED=NO -skipPackagePluginValidation build 2>&1 | tee build/ios.log \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true
grep -q "BUILD SUCCEEDED" build/ios.log || { grep -B2 -A6 "error:" build/ios.log | head -100; exit 1; }
mkdir -p build/ipa/Payload
cp -R build/dd/Build/Products/Release-iphoneos/GutenMorgen.app build/ipa/Payload/
APP=build/ipa/Payload/GutenMorgen.app
codesign -f -s - --entitlements ressourcen/Widget.entitlements "$APP/PlugIns/GutenMorgenWidget.appex"
codesign -f -s - --entitlements ressourcen/App.entitlements "$APP"
plutil -p "$APP/Info.plist" | grep -A4 CFBundleIcons || { echo "FEHLER: kein App-Symbol"; exit 1; }
mkdir -p bilder-ci && cp ressourcen/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png bilder-ci/
(cd build/ipa && zip -qry "../GutenMorgen-iOS-$VERSION.ipa" Payload)
echo "Fertig: build/GutenMorgen-iOS-$VERSION.ipa"
