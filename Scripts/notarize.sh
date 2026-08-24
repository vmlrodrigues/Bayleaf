#!/usr/bin/env bash
# Notarises dist/Bayleaf.app, staples the ticket, and packages a signed DMG.
#
# Verbatim ClawBar mechanism: App Store Connect API key from .env, two-stage
# notarisation (staple the app itself first, then ship the stapled app inside a
# notarised DMG) so Gatekeeper works offline on first launch.
#
# The only local addition: if this project has no .env, fall back to ClawBar's —
# same Apple account, same key, no reason to duplicate a credential file.

set -euo pipefail

APP_NAME="Bayleaf"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/$APP_NAME.dmg"

[ -d "$APP" ] || { echo "error: $APP not found — run Scripts/build.sh first" >&2; exit 1; }

ENV_FILE="$ROOT/.env"
[ -f "$ENV_FILE" ] || ENV_FILE="$ROOT/../ClawBar/.env"
[ -f "$ENV_FILE" ] || {
    echo "error: no .env here and none at ../ClawBar/.env" >&2
    echo "       cp $ROOT/.env.example $ROOT/.env   and fill it in" >&2
    exit 1
}

# shellcheck disable=SC1090
set -a; . "$ENV_FILE"; set +a

: "${NOTARY_KEY:?.env must set NOTARY_KEY (path to the App Store Connect .p8)}"
: "${NOTARY_KEY_ID:?.env must set NOTARY_KEY_ID}"
: "${NOTARY_ISSUER:?.env must set NOTARY_ISSUER}"
IDENTITY="${RELEASE_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Developer ID Application/{print $2; exit}')}"
[ -n "$IDENTITY" ] || { echo "error: no Developer ID identity; set RELEASE_SIGN_IDENTITY in .env" >&2; exit 1; }

[ -f "$NOTARY_KEY" ] || { echo "error: NOTARY_KEY file not found: $NOTARY_KEY" >&2; exit 1; }

echo "==> Verifying the app signature before submitting"
codesign --verify --strict --verbose=2 "$APP"

ZIP="$DIST/$APP_NAME-app.zip"
echo "==> [1/2] Notarising the app itself"
rm -f "$ZIP"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" \
    --key "$NOTARY_KEY" \
    --key-id "$NOTARY_KEY_ID" \
    --issuer "$NOTARY_ISSUER" \
    --wait
rm -f "$ZIP"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP" && echo "  App ticket: stapled"

echo "==> [2/2] Building DMG (containing the stapled app)"
rm -f "$DMG"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

echo "==> Signing the DMG"
codesign --force --sign "$IDENTITY" --timestamp "$DMG"

echo "==> Submitting for notarisation (usually a few minutes)"
xcrun notarytool submit "$DMG" \
    --key "$NOTARY_KEY" \
    --key-id "$NOTARY_KEY_ID" \
    --issuer "$NOTARY_ISSUER" \
    --wait

echo "==> Stapling the DMG"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG" && echo "  DMG ticket: stapled"

echo "==> Gatekeeper assessment"
spctl --assess --type open --context context:primary-signature --ignore-cache "$DMG" \
    && echo "  Gatekeeper: OK" \
    || echo "  Warning: Gatekeeper check failed"

echo
echo "Distributable: $DMG"
