#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/mwitch.app"

echo "==> Building (arm64, $CONFIG)"
swift build -c "$CONFIG" --arch arm64

BIN_DIR="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)"
BIN="$BIN_DIR/mwitch"
if [[ ! -x "$BIN" ]]; then
    echo "error: build output not found at $BIN" >&2
    exit 1
fi

if [[ ! -f "$ROOT/Resources/AppIcon.icns" ]]; then
    echo "==> Generating AppIcon.icns"
    "$ROOT/tools/make_icons.sh"
fi

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/mwitch"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
chmod +x "$APP/Contents/MacOS/mwitch"

# Stamp the version from MWITCH_VERSION or VERSION, and the build number
# from the git commit count.
MARKETING_VERSION="${MWITCH_VERSION:-$(tr -d '[:space:]' < "$ROOT/VERSION" 2>/dev/null || echo 0.0.0)}"
BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
echo "==> Version $MARKETING_VERSION (build $BUILD_NUMBER)"
plutil -replace CFBundleShortVersionString -string "$MARKETING_VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"

# Prefer a stable signing identity over ad-hoc so TCC grants (Accessibility,
# etc.) persist across rebuilds. Developer ID Application is best (also
# notarizable); Apple Development is fine for local use.
IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
SIGN_ID="$(echo "$IDENTITIES" | { grep -E '"Developer ID Application: .*"' || true; } | head -1 \
    | sed -E 's/.*"(Developer ID Application: [^"]+)".*/\1/')"
IS_DEVELOPER_ID=1
if [[ -z "$SIGN_ID" ]]; then
    SIGN_ID="$(echo "$IDENTITIES" | { grep -E '"Apple Development: .*"' || true; } | head -1 \
        | sed -E 's/.*"(Apple Development: [^"]+)".*/\1/')"
    IS_DEVELOPER_ID=0
fi

if [[ -n "$SIGN_ID" && "$IS_DEVELOPER_ID" -eq 1 ]]; then
    echo "==> Signing with: $SIGN_ID"
    codesign --force \
        --options runtime \
        --timestamp \
        --entitlements "$ROOT/Resources/mwitch.entitlements" \
        --sign "$SIGN_ID" \
        "$APP"
    codesign --verify --strict --deep --verbose=2 "$APP"
    echo "==> Signed with Developer ID (ready for notarization)"
elif [[ -n "$SIGN_ID" ]]; then
    echo "==> Signing with: $SIGN_ID (local-use cert; not notarizable)"
    codesign --force \
        --options runtime \
        --entitlements "$ROOT/Resources/mwitch.entitlements" \
        --sign "$SIGN_ID" \
        "$APP"
    codesign --verify --strict --deep --verbose=2 "$APP"
    echo "==> Signed (TCC grants will persist across rebuilds)"
else
    echo "==> No signing cert found — falling back to ad-hoc signing"
    echo "    (TCC permissions will not persist across rebuilds.)"
    echo "    Create one in Xcode: Settings → Accounts → Manage Certificates → + → Developer ID Application"
    codesign --force --sign - "$APP"
    codesign --verify --strict --deep --verbose=2 "$APP"
fi

echo ""
echo "Built: $APP"

# Install local builds at a stable path so privacy permissions survive rebuilds.
# Release automation only needs the bundle under build/.
RUN_APP="$APP"
if [[ "${MWITCH_INSTALL:-1}" == "1" && "${CI:-false}" != "true" ]]; then
    INSTALL_APP="/Applications/mwitch.app"
    INSTALL_STAGE="$(mktemp -d /Applications/.mwitch-install.XXXXXX)"
    trap 'rm -rf "$INSTALL_STAGE"' EXIT
    ditto "$APP" "$INSTALL_STAGE/mwitch.app"
    echo "==> Stopping any running mwitch instance"
    if pgrep -x mwitch >/dev/null; then
        osascript -e 'tell application "mwitch" to quit'
    fi
    echo "==> Installing $INSTALL_APP"
    # Replace the bundle so removed frameworks and helpers cannot linger.
    rm -rf "$INSTALL_APP"
    mv "$INSTALL_STAGE/mwitch.app" "$INSTALL_APP"
    rmdir "$INSTALL_STAGE"
    trap - EXIT
    RUN_APP="$INSTALL_APP"
    echo "==> Starting $INSTALL_APP"
    open "$INSTALL_APP"
fi

echo "Run:   open '$RUN_APP'"
echo "       (or '$RUN_APP/Contents/MacOS/mwitch' to see stdout)"
echo ""
