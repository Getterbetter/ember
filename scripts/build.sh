#!/bin/bash
# Build, test and install Ember on this Mac.
#   scripts/build.sh            generate the project, run unit tests, build Release
#   scripts/build.sh install    ...then copy Ember.app to /Applications and open it
#   scripts/build.sh test       unit tests only
set -euo pipefail
cd "$(dirname "$0")/.."

XCODEGEN="$(command -v xcodegen || echo "$HOME/.local/bin/xcodegen")"
if [ ! -x "$XCODEGEN" ]; then
  echo "XcodeGen not found. Install it: brew install xcodegen (or see README)." >&2
  exit 1
fi

# Team ID: env var, then Config/Local.xcconfig, then an existing project of yours in ~/Developer.
touch Config/Local.xcconfig
if ! grep -q '^DEVELOPMENT_TEAM *= *[A-Z0-9]' Config/Local.xcconfig; then
  TEAM="${DEVELOPMENT_TEAM:-}"
  if [ -z "$TEAM" ]; then
    TEAM="$(grep -ho 'DEVELOPMENT_TEAM = [A-Z0-9]*' "$HOME"/Developer/*/*.xcodeproj/project.pbxproj 2>/dev/null | head -1 | awk '{print $3}' || true)"
  fi
  if [ -z "$TEAM" ]; then
    echo "Set DEVELOPMENT_TEAM=<your team ID> and run again." >&2
    exit 1
  fi
  echo "DEVELOPMENT_TEAM = $TEAM" >> Config/Local.xcconfig
  echo "Added team $TEAM to Config/Local.xcconfig"
fi

"$XCODEGEN" generate --quiet

DERIVED="build/DerivedData"
COMMON=(-project Ember.xcodeproj -scheme Ember -derivedDataPath "$DERIVED" -allowProvisioningUpdates)

echo "== Unit tests"
xcodebuild "${COMMON[@]}" -destination 'platform=macOS' test | tail -25

[ "${1:-}" = "test" ] && exit 0

echo "== Release build"
xcodebuild "${COMMON[@]}" -configuration Release build | tail -5
APP="$DERIVED/Build/Products/Release/Ember.app"

echo "== Bundle check"
test -x "$APP/Contents/MacOS/EmberHelper" && echo "helper embedded"
ls "$APP/Contents/Library/LaunchDaemons/"
codesign --verify --deep --strict "$APP" && echo "signature OK"
codesign -dv "$APP" 2>&1 | grep -E 'Identifier|TeamIdentifier'
codesign -dv "$APP/Contents/MacOS/EmberHelper" 2>&1 | grep -E 'Identifier|TeamIdentifier'
test -d "$APP/Contents/Resources/Metadata.appintents" && echo "App Intents metadata present"

if [ "${1:-}" = "install" ]; then
  echo "== Installing to /Applications"
  osascript -e 'tell application "Ember" to quit' 2>/dev/null || true
  sleep 1
  [ -d /Applications/Ember.app ] && mv /Applications/Ember.app "$HOME/.Trash/Ember-$(date +%s).app"
  ditto "$APP" /Applications/Ember.app
  open /Applications/Ember.app
  echo "Installed. First launch: approve Ember in System Settings > General > Login Items."
fi
