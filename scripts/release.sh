#!/bin/bash
# Build a Developer ID signed, notarised Ember release and (optionally) publish it on GitHub.
#
#   scripts/release.sh              build, sign, notarise, staple, zip  -> build/release/
#   scripts/release.sh --publish    ...then create the GitHub release vX.Y.Z with the zip
#   scripts/release.sh --sign-only  build and sign, check signatures, stop before notarising
#
# One-time setup on the Mac that builds releases:
#   1. Signing, either:
#      a. a local "Developer ID Application" certificate (only the team's Account Holder can create
#         one: Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application), or
#      b. cloud-managed Developer ID signing: the Account Holder, or an Admin given access to
#         cloud-managed Developer ID certificates in App Store Connect > Users and Access.
#   2. xcrun notarytool store-credentials ember-notary --apple-id <you> --team-id <TEAM>
# Signing keys and notary credentials stay in the login keychain; nothing secret is in the repo.
set -euo pipefail
cd "$(dirname "$0")/.."

NOTARY_PROFILE="${NOTARY_PROFILE:-ember-notary}"
PUBLISH=0
SIGN_ONLY=0
[ "${1:-}" = "--publish" ] && PUBLISH=1
[ "${1:-}" = "--sign-only" ] && SIGN_ONLY=1

XCODEGEN="$(command -v xcodegen || echo "$HOME/.local/bin/xcodegen")"
GH="$(command -v gh || echo "$HOME/.local/bin/gh")"

VERSION="$(grep -E '^\s*MARKETING_VERSION:' project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')"
[ -n "$VERSION" ] || { echo "Couldn't read MARKETING_VERSION from project.yml" >&2; exit 1; }

IDENTITY_LINE="$(security find-identity -v -p codesigning | grep 'Developer ID Application' | head -1 || true)"
if [ -n "$IDENTITY_LINE" ]; then
  MODE=local
  TEAM="$(echo "$IDENTITY_LINE" | sed -E 's/.*\(([A-Z0-9]{10})\)".*/\1/')"
else
  MODE=cloud
  TEAM="${DEVELOPMENT_TEAM:-$(grep -ho '^DEVELOPMENT_TEAM *= *[A-Z0-9]*' Config/Local.xcconfig 2>/dev/null | awk '{print $3}')}"
  [ -n "$TEAM" ] || { echo "No local Developer ID certificate and no team ID for cloud signing. Set DEVELOPMENT_TEAM." >&2; exit 1; }
  echo "No local Developer ID certificate: using cloud-managed Developer ID signing through Xcode."
fi
echo "== Ember $VERSION, team $TEAM, signing: $MODE"

if [ "$SIGN_ONLY" = 0 ] && ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "Notary profile '$NOTARY_PROFILE' not found or not working. See the setup notes at the top of this script." >&2
  exit 1
fi

if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "Working tree has uncommitted changes; commit them first so the release matches a commit." >&2
  exit 1
fi

OUT="build/release"
ARCHIVE="$OUT/Ember.xcarchive"
mkdir -p "$OUT"
[ -d "$ARCHIVE" ] && mv "$ARCHIVE" "$HOME/.Trash/Ember-$(date +%s).xcarchive"

"$XCODEGEN" generate --quiet

APP="$OUT/Ember.app"
[ -d "$APP" ] && mv "$APP" "$HOME/.Trash/Ember-$(date +%s).app"

if [ "$MODE" = local ]; then
  echo "== Archive (local Developer ID, hardened runtime, secure timestamp)"
  xcodebuild -project Ember.xcodeproj -scheme Ember -configuration Release \
    -archivePath "$ARCHIVE" -derivedDataPath build/DerivedData-release \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" DEVELOPMENT_TEAM="$TEAM" \
    PROVISIONING_PROFILE_SPECIFIER="" OTHER_CODE_SIGN_FLAGS="--timestamp" \
    archive | tail -3
  ditto "$ARCHIVE/Products/Applications/Ember.app" "$APP"
else
  echo "== Archive (development signing), then export with cloud-managed Developer ID"
  xcodebuild -project Ember.xcodeproj -scheme Ember -configuration Release \
    -archivePath "$ARCHIVE" -derivedDataPath build/DerivedData-release \
    CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM="$TEAM" -allowProvisioningUpdates \
    archive | tail -3
  EXPORT="$OUT/export"
  [ -d "$EXPORT" ] && mv "$EXPORT" "$HOME/.Trash/Ember-export-$(date +%s)"
  cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>$TEAM</string>
</dict>
</plist>
PLIST
  xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates | tail -3
  ditto "$EXPORT/Ember.app" "$APP"
fi

echo "== Verify signatures"
codesign --verify --strict --deep --verbose=2 "$APP"
for item in "$APP" "$APP/Contents/MacOS/EmberHelper" "$APP/Contents/Frameworks/EmberKit.framework"; do
  info="$(codesign -dvv "$item" 2>&1)"
  echo "$info" | grep -q "Authority=Developer ID Application" || { echo "$item is not Developer ID signed" >&2; exit 1; }
  echo "$info" | grep -q "Timestamp=" || { echo "$item has no secure timestamp" >&2; exit 1; }
  echo "$info" | grep -q "flags=.*runtime" || { echo "$item lacks the hardened runtime" >&2; exit 1; }
  echo "ok: $item"
done
if codesign -d --entitlements - "$APP" 2>/dev/null | grep -q "get-task-allow"; then
  echo "Release build carries get-task-allow; refusing to ship a debuggable build." >&2
  exit 1
fi

if [ "$SIGN_ONLY" = 1 ]; then
  echo "Signed build checks passed (not notarised): $APP"
  exit 0
fi

ZIP="$OUT/Ember-$VERSION.zip"
echo "== Notarise"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"

echo "== Final zip (with the stapled ticket)"
ditto -c -k --keepParent "$APP" "$ZIP"
# Name the zip without its folder so `shasum -c` works next to a downloaded copy.
(cd "$OUT" && shasum -a 256 "$(basename "$ZIP")") | tee "$ZIP.sha256"

if [ "$PUBLISH" = 1 ]; then
  echo "== Publish v$VERSION on GitHub"
  NOTES="$(awk -v v="$VERSION" '$0 ~ "^## \\[?"v {f=1; next} /^## / && f {exit} f' CHANGELOG.md)"
  "$GH" release create "v$VERSION" "$ZIP" "$ZIP.sha256" --title "Ember $VERSION" --notes "$NOTES" --target "$(git rev-parse HEAD)"
fi
echo "Done: $ZIP"
