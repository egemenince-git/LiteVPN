#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/Build/DirectDistribution"
STAMP="$(date -u +%Y%m%d-%H%M%S)"
ARCHIVE_PATH="$BUILD_DIR/LiteVPN-$STAMP.xcarchive"
NOTARY_PROFILE="${NOTARY_PROFILE:-LiteVPN-Notary}"
TEAM_ID="99U7KZC748"
TUNNEL_BUNDLE_ID="com.egemenince.LiteVPN.Tunnel"
: "${LITEVPN_APP_PROFILE:?Set LITEVPN_APP_PROFILE to the app's Developer ID provisioning profile name}"
: "${LITEVPN_TUNNEL_PROFILE:?Set LITEVPN_TUNNEL_PROFILE to the system extension's Developer ID provisioning profile name}"

mkdir -p "$BUILD_DIR"

xcodebuild \
  -project "$ROOT_DIR/LiteVPN.xcodeproj" \
  -scheme LiteVPN \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  LITEVPN_APP_PROFILE="$LITEVPN_APP_PROFILE" \
  LITEVPN_TUNNEL_PROFILE="$LITEVPN_TUNNEL_PROFILE" \
  archive

APP_PATH="$ARCHIVE_PATH/Products/Applications/LiteVPN.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Archive did not contain LiteVPN.app: $APP_PATH" >&2
  exit 1
fi

SYSTEM_EXTENSION_PATH="$APP_PATH/Contents/Library/SystemExtensions/$TUNNEL_BUNDLE_ID.systemextension"
if [[ ! -d "$SYSTEM_EXTENSION_PATH" ]]; then
  echo "System extension must be embedded as $TUNNEL_BUNDLE_ID.systemextension: $SYSTEM_EXTENSION_PATH" >&2
  exit 1
fi

EMBEDDED_TUNNEL_BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SYSTEM_EXTENSION_PATH/Contents/Info.plist")
if [[ "$EMBEDDED_TUNNEL_BUNDLE_ID" != "$TUNNEL_BUNDLE_ID" ]]; then
  echo "Expected system extension ID $TUNNEL_BUNDLE_ID, found $EMBEDDED_TUNNEL_BUNDLE_ID" >&2
  exit 1
fi

SUBMISSION_ZIP="$BUILD_DIR/LiteVPN-$STAMP-for-notarization.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$SUBMISSION_ZIP"
xcrun notarytool submit "$SUBMISSION_ZIP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --team-id "$TEAM_ID" \
  --wait

xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

FINAL_ZIP="$BUILD_DIR/LiteVPN-$STAMP.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$FINAL_ZIP"
spctl --assess --type execute --verbose=4 "$APP_PATH"

printf 'Notarized distribution package: %s\n' "$FINAL_ZIP"
