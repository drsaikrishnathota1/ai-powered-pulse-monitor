#!/usr/bin/env bash
set -euo pipefail

# Archive → export IPA → upload with altool.
# Prereqs:
# - Xcode installed; sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
# - Apple Distribution cert in Keychain (security find-identity -v -p codesigning)
# - EITHER at least one iOS device registered on your Apple Developer team (common path),
#   OR manual signing + an App Store provisioning profile for this bundle ID.
# - ~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8 + Issuer ID + Key ID for upload

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/CamvitalScan/CamvitalScan.xcodeproj"
SCHEME="${SCHEME:-CamvitalScan}"
TEAM="${DEVELOPMENT_TEAM:-Q976JY4DNU}"
ARCHIVE="${ARCHIVE:-$HOME/Desktop/CamvitalScan.xcarchive}"
EXPORT_DIR="${EXPORT_DIR:-$HOME/Desktop/CamvitalExport}"
EXPORT_PLIST="${EXPORT_PLIST:-$ROOT/CamvitalScan/ExportOptions-appstore.plist}"

API_KEY_ID="${APPSTORE_API_KEY:?Set APPSTORE_API_KEY}"
API_ISSUER="${APPSTORE_ISSUER:?Set APPSTORE_ISSUER}"
export API_PRIVATE_KEYS_DIR="${API_PRIVATE_KEYS_DIR:-$HOME/.appstoreconnect/private_keys}"

AUTH_ARGS=()
if [[ -f "${ASC_AUTH_KEY_PATH:-}" ]]; then
  AUTH_ARGS+=( -authenticationKeyPath "$ASC_AUTH_KEY_PATH" )
  AUTH_ARGS+=( -authenticationKeyID "${ASC_AUTH_KEY_ID:-$API_KEY_ID}" )
  AUTH_ARGS+=( -authenticationKeyIssuerID "${ASC_AUTH_ISSUER:-$API_ISSUER}" )
fi

rm -rf "$ARCHIVE" "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"

echo "== Archive"
xcodebuild clean archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE" \
  CODE_SIGN_STYLE=Automatic \
  "DEVELOPMENT_TEAM=$TEAM" \
  -allowProvisioningUpdates \
  "${AUTH_ARGS[@]}"

echo "== Export IPA"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_PLIST" \
  -allowProvisioningUpdates \
  "${AUTH_ARGS[@]}"

IPA="$(ls "$EXPORT_DIR"/*.ipa | head -1)"
echo "IPA: $IPA"

echo "== Upload"
xcrun altool --upload-app \
  --type ios \
  --file "$IPA" \
  --apiKey "$API_KEY_ID" \
  --apiIssuer "$API_ISSUER" \
  --verbose

echo "Done. Check App Store Connect → Activity / TestFlight."
