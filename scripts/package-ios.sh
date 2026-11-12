#!/bin/sh
# Package the existing device build for import into LiveContainer.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP=${1:-$ROOT/apps/upload-ios/build/Build/Products/Release-iphoneos/Tianzige.app}
[ -d "$APP" ] || { echo "Build the iOS device App first" >&2; exit 1; }
PLATFORM=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleSupportedPlatforms:0' "$APP/Info.plist")
[ "$PLATFORM" = iPhoneOS ] || { echo "IPA requires an iPhoneOS build, not a simulator App" >&2; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist")
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/tianzige-ipa.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/Payload" "$ROOT/dist"
ditto --norsrc "$APP" "$STAGE/Payload/Tianzige.app"
OUT="$ROOT/dist/Tianzige-$VERSION-build$BUILD.ipa"
ditto --norsrc -c -k --keepParent "$STAGE/Payload" "$OUT"
printf '%s\n' "$OUT"
