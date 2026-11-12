#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [ -z "${JAVA_HOME:-}" ]; then
  if [ -x /opt/homebrew/opt/openjdk@17/bin/java ]; then
    JAVA_HOME=/opt/homebrew/opt/openjdk@17
  else
    JAVA_HOME=$(/usr/libexec/java_home -v 17 2>/dev/null || true)
  fi
fi
[ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ] || { echo "Set JAVA_HOME to an existing JDK 17; nothing will be installed" >&2; exit 1; }
ANDROID_HOME=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}
[ -f "$ANDROID_HOME/platforms/android-34/android.jar" ] && [ -d "$ANDROID_HOME/build-tools/34.0.0" ] || {
  echo "Set ANDROID_HOME to your existing SDK with Android 34 and build-tools 34.0.0" >&2; exit 1;
}
export JAVA_HOME ANDROID_HOME
GRADLE_DIST_ROOT="${GRADLE_USER_HOME:-$HOME/.gradle}/wrapper/dists/gradle-8.9-bin"
[ -d "$GRADLE_DIST_ROOT" ] || { echo "Gradle 8.9 is not cached; no distribution will be downloaded" >&2; exit 1; }
GRADLE_BIN=$(find "$GRADLE_DIST_ROOT" -path "*/gradle-8.9/bin/gradle" -type f -print -quit)
[ -x "$GRADLE_BIN" ] || { echo "The existing Gradle 8.9 distribution is incomplete" >&2; exit 1; }
cd "$ROOT/apps/tv-android"
# Offline is intentional: no SDK, Gradle or Maven downloads.
"$GRADLE_BIN" --offline :app:assembleDebug :app:testDebugUnitTest :app:lintDebug "$@"
mkdir -p "$ROOT/dist"
cp app/build/outputs/apk/debug/app-debug.apk "$ROOT/dist/tianzige-tv-debug.apk"
