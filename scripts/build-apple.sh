#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
xcodebuild -version
command -v xcodegen >/dev/null || { echo "Use the existing XcodeGen installation" >&2; exit 1; }
mkdir -p "$ROOT/dist"
# CI tags override product versions; local builds retain project.yml values.
set --
if [ -n "${TIANZIGE_VERSION:-}" ]; then
  set -- "$@" "MARKETING_VERSION=$TIANZIGE_VERSION"
fi
if [ -n "${TIANZIGE_BUILD:-}" ]; then
  set -- "$@" "CURRENT_PROJECT_VERSION=$TIANZIGE_BUILD"
fi
cd "$ROOT/apps/upload-mac"
xcodegen generate
xcodebuild -project TianzigeMac.xcodeproj -scheme TianzigeMac -configuration Release -derivedDataPath build CODE_SIGN_IDENTITY=- "$@" build
ditto -c -k --sequesterRsrc --keepParent build/Build/Products/Release/TianzigeMac.app "$ROOT/dist/TianzigeMac.zip"
cd "$ROOT/apps/upload-ios"
xcodegen generate
# Compiles against the installed device SDK; no simulator runtime or provisioning is downloaded.
xcodebuild -project Tianzige.xcodeproj -scheme Tianzige -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO "$@" build
ditto -c -k --keepParent build/Build/Products/Release-iphoneos/Tianzige.app "$ROOT/dist/Tianzige-iOS-unsigned.zip"
sh "$ROOT/scripts/package-ios.sh"
