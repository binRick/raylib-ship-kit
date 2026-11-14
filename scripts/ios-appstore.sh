#!/usr/bin/env bash
# Archive, export, validate and upload the iOS build to App Store Connect.
#   TEAM_ID=... ASC_KEY_ID=... ASC_ISSUER_ID=... scripts/ios-appstore.sh
#   TEAM_ID=... DRY_RUN=1 scripts/ios-appstore.sh      # stop after producing the .ipa
# Then scripts/asc-submit.py sends the uploaded build to review.
#
# One-time setup:
#   1. An app record at https://appstoreconnect.apple.com for BUNDLE_ID (kit.env).
#   2. Upload auth, either
#      A) an App Store Connect API key (Users and Access > Integrations > Keys), saved as
#         ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8, with ASC_KEY_ID + ASC_ISSUER_ID set; or
#      B) APPLE_ID + APP_PWD (an app-specific password).
#
# Apple rejects an upload whose version it has already seen: bump VERSION first.
. "$(dirname "$0")/_kit.sh"
need_team

AUTH=()
if [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]]; then
    AUTH=(--apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID")
elif [[ -n "${APPLE_ID:-}" && -n "${APP_PWD:-}" ]]; then
    AUTH=(--username "$APPLE_ID" --password "$APP_PWD")
elif [[ "${DRY_RUN:-0}" != "1" ]]; then
    die "no upload auth: set ASC_KEY_ID + ASC_ISSUER_ID, or APPLE_ID + APP_PWD, or DRY_RUN=1 (see the header of this script)"
fi

ios_prepare iphoneos
ARCHIVE="ios/build/$APP_SLUG.xcarchive"
EXPORT_DIR="ios/build/AppStore"
EXPORT_PLIST="ios/build/ExportOptions.plist"

echo "==> Archiving $APP_NAME $APP_VERSION (team $TEAM_ID)"
rm -rf "$ARCHIVE" "$EXPORT_DIR"
xcodebuild archive -project ios/Game.xcodeproj -scheme Game -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic -quiet
[[ -d "$ARCHIVE" ]] || die "archive did not produce $ARCHIVE"

echo "==> Exporting the App Store .ipa"
cat > "$EXPORT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>teamID</key><string>$TEAM_ID</string>
    <key>signingStyle</key><string>automatic</string>
    <key>uploadSymbols</key><true/>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_PLIST" -allowProvisioningUpdates -quiet
IPA="$(ls "$EXPORT_DIR"/*.ipa 2> /dev/null | head -1 || true)"
[[ -f "$IPA" ]] || die "no .ipa in $EXPORT_DIR"
echo "    $IPA ($(du -h "$IPA" | cut -f1))"

if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo "DRY_RUN=1: not uploading."
    exit 0
fi

echo "==> Validating"
xcrun altool --validate-app -f "$IPA" -t ios "${AUTH[@]}"
echo "==> Uploading (a few minutes)"
xcrun altool --upload-app -f "$IPA" -t ios "${AUTH[@]}"
echo "Uploaded. Send it to review with: scripts/asc-submit.py \"What's new in $APP_VERSION\""
