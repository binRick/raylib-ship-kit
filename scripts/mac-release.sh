#!/usr/bin/env bash
# Build "<App Name>.app" (Apple Silicon + Intel), sign it with your Developer ID, notarize it
# with Apple, staple the ticket and zip it: dist/<slug>-macos.zip
#   scripts/mac-release.sh                 full release: sign + notarize + staple
#   scripts/mac-release.sh --no-notarize   build and Developer ID sign only
#   scripts/mac-release.sh --adhoc         no Apple account needed: ad-hoc signed, runs on this Mac
#
# One-time setup for a real release:
#   1. A "Developer ID Application" certificate in the login keychain
#      (Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application).
#   2. A notarytool keychain profile (name it anything; pass it as NOTARY_PROFILE):
#        xcrun notarytool store-credentials my-notary --apple-id <apple-id> \
#            --team-id <team id> --password <app-specific password from account.apple.com>
. "$(dirname "$0")/_kit.sh"
[[ "$(uname -s)" == Darwin ]] || die "macOS only"

MODE="${1:-}"
PROFILE="${NOTARY_PROFILE:-}"
APP="build-mac/$APP_NAME.app"
ZIP="dist/$APP_SLUG-macos.zip"

if [[ "$MODE" == "--adhoc" ]]; then
    IDENTITY="-"
else
    IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application[^"]*\)".*/\1/p' | head -1)"
    [[ -n "$IDENTITY" ]] || die "no Developer ID Application certificate in the keychain (see the header of this script), or use --adhoc"
fi
if [[ -z "$MODE" ]]; then
    [[ -n "$PROFILE" ]] || die "set NOTARY_PROFILE to your notarytool keychain profile (see the header of this script)"
    xcrun notarytool history --keychain-profile "$PROFILE" > /dev/null 2>&1 || die "notarytool profile \"$PROFILE\" isn't set up"
fi

echo "==> Building (Release, arm64 + x86_64)"
[[ -f build-mac/CMakeCache.txt ]] || cmake -S . -B build-mac -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0
cmake --build build-mac -j "$JOBS"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "build-mac/$APP_SLUG" "$APP/Contents/MacOS/$APP_SLUG"
sed -e "s/__VERSION__/$APP_VERSION/g" -e "s/__APP_NAME__/$APP_NAME/g" -e "s/__APP_SLUG__/$APP_SLUG/g" \
    -e "s/__BUNDLE_ID__/$BUNDLE_ID/g" -e "s/__APP_CATEGORY__/$APP_CATEGORY/g" macos/Info.plist > "$APP/Contents/Info.plist"
cp -R assets "$APP/Contents/Resources/"
find "$APP" -name .DS_Store -delete
iconset=build-mac/icon.iconset
rm -rf "$iconset" && mkdir -p "$iconset"
for s in 16 32 128 256 512; do
    sips -z $s $s assets/icon.png --out "$iconset/icon_${s}x${s}.png" > /dev/null
    sips -z $((s * 2)) $((s * 2)) assets/icon.png --out "$iconset/icon_${s}x${s}@2x.png" > /dev/null
done
iconutil -c icns "$iconset" -o "$APP/Contents/Resources/icon.icns"

echo "==> Signing ($([[ "$IDENTITY" == "-" ]] && echo ad-hoc || echo "$IDENTITY"))"
if [[ "$IDENTITY" == "-" ]]; then
    codesign --force --sign - "$APP"
else
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"

mkdir -p dist && rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
if [[ -n "$MODE" ]]; then
    echo "Signed, not notarized: $ZIP"
    exit 0
fi

echo "==> Notarizing (usually 2-5 minutes)"
log="$(mktemp -t notary)"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait --output-format plist > "$log"
id="$(/usr/libexec/PlistBuddy -c 'Print :id' "$log")"
status="$(/usr/libexec/PlistBuddy -c 'Print :status' "$log")"
echo "    submission $id: $status"
if [[ "$status" != "Accepted" ]]; then
    xcrun notarytool log "$id" --keychain-profile "$PROFILE" >&2 || true
    exit 1
fi

echo "==> Stapling the ticket and zipping"
xcrun stapler staple "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
spctl --assess --type execute --verbose=2 "$APP"
ls -la "$ZIP"
