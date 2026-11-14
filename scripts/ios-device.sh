#!/usr/bin/env bash
# Build, install on a connected iPhone or iPad, and launch.
#   TEAM_ID=ABCDE12345 scripts/ios-device.sh           # first paired device
#   TEAM_ID=ABCDE12345 scripts/ios-device.sh <UDID>    # a specific one
# The device must be plugged in (or on the same Wi-Fi), unlocked, and trusting this Mac.
# A free Apple ID works; its builds expire after 7 days.
. "$(dirname "$0")/_kit.sh"
need_team
ios_prepare iphoneos
DERIVED="ios/build"
APP="$DERIVED/Build/Products/Release-iphoneos/$APP_SLUG.app"

echo "==> Building for device (team $TEAM_ID)"
xcodebuild build -project ios/Game.xcodeproj -scheme Game -configuration Release \
    -destination 'generic/platform=iOS' -derivedDataPath "$DERIVED" \
    DEVELOPMENT_TEAM="$TEAM_ID" -allowProvisioningUpdates -quiet
[[ -d "$APP" ]] || die "build did not produce $APP"

UDID="${1:-}"
if [[ -z "$UDID" ]]; then
    json="$(mktemp)"
    xcrun devicectl list devices --json-output "$json" > /dev/null 2>&1 || true
    UDID="$(python3 - "$json" <<'PY' || true
import json, sys
for dev in json.load(open(sys.argv[1])).get("result", {}).get("devices", []):
    if dev.get("connectionProperties", {}).get("pairingState") == "paired" \
            and dev.get("hardwareProperties", {}).get("reality") == "physical":
        print(dev.get("identifier", ""))
        break
PY
)"
fi
[[ -n "$UDID" ]] || die "no paired device found. Plug it in, unlock it, trust this Mac (xcrun devicectl list devices)"

echo "==> Installing on $UDID"
xcrun devicectl device install app --device "$UDID" "$APP"
xcrun devicectl device process launch --device "$UDID" "$BUNDLE_ID"
echo 'If iOS says "Untrusted Developer": Settings > General > VPN & Device Management > trust your certificate.'
