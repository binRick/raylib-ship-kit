#!/usr/bin/env bash
# Build for the iOS simulator, install and launch. No signing, no cable, no Apple account.
#   scripts/ios-sim.sh                      # first iPhone simulator (or any, if there is none)
#   DEVICE="iPad Pro 13-inch (M5)" scripts/ios-sim.sh
#   scripts/ios-sim.sh -- --debug           # anything after -- goes to the game
# Screenshot it with: xcrun simctl io booted screenshot shot.png
. "$(dirname "$0")/_kit.sh"
args=()
if [[ "${1:-}" == "--" ]]; then shift; args=("$@"); fi

ios_prepare iphonesimulator
DERIVED="ios/build-sim"
APP="$DERIVED/Build/Products/Release-iphonesimulator/$APP_SLUG.app"

if [[ -n "${DEVICE:-}" ]]; then
    UDID="$(xcrun simctl list devices available | grep -F "$DEVICE (" | head -1 | grep -oE '[0-9A-F-]{36}' || true)"
else
    # an iPhone if there is one, else whatever simulator exists
    UDID="$( (xcrun simctl list devices available | grep -E '^ +iPhone' || xcrun simctl list devices available | grep -E '^ +') \
        | head -1 | grep -oE '[0-9A-F-]{36}' || true)"
fi
[[ -n "$UDID" ]] || die "no matching simulator. List them: xcrun simctl list devices available"
if ! xcrun simctl list devices booted | grep -q "$UDID"; then
    echo "==> Booting simulator $UDID"
    xcrun simctl boot "$UDID"
    xcrun simctl bootstatus "$UDID" -b > /dev/null
fi
open -b com.apple.iphonesimulator 2> /dev/null || echo "    (no Simulator app: running headless)"

echo "==> Building"
xcodebuild build -project ios/Game.xcodeproj -scheme Game -configuration Release \
    -destination "id=$UDID" -derivedDataPath "$DERIVED" -quiet

echo "==> Installing and launching ($(du -sh "$APP" | cut -f1))"
xcrun simctl install "$UDID" "$APP"
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2> /dev/null || true
xcrun simctl launch "$UDID" "$BUNDLE_ID" ${args[@]+"${args[@]}"}
