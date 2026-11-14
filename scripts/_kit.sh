# Sourced by every script: moves to the repo root, loads kit.env and VERSION, shared helpers.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
set -a
. ./kit.env
APP_VERSION="$(tr -d '[:space:]' < VERSION)"
set +a
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || nproc)"

die() { echo "error: $*" >&2; exit 1; }
need() { command -v "$1" > /dev/null || die "$1 not found: $2"; }

# ios_prepare <iphoneos|iphonesimulator>: raylib built for that SDK, Xcode project generated.
ios_prepare() {
    need xcodegen "brew install xcodegen"
    if [[ ! -f "vendor-ios/lib-$1/libraylib.a" ]]; then
        [[ "$1" == iphoneos ]] && ios/build-raylib.sh device || ios/build-raylib.sh sim
    fi
    (cd ios && xcodegen generate --quiet)
}

# The Apple Developer team that signs device and App Store builds.
need_team() {
    [[ -n "${TEAM_ID:-}" ]] || die "set TEAM_ID to your Apple Developer team id (developer.apple.com/account > Membership)"
}
