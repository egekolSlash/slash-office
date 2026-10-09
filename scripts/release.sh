#!/bin/sh
# Builds a release archive: universal app, signed (Developer ID + notarized when configured), zipped with a checksum.
#
#   scripts/release.sh 0.1.0
#
# Environment:
#   DEVELOPER_ID     "Developer ID Application: …" identity; enables hardened runtime. Without it the app is ad-hoc signed.
#   NOTARY_PROFILE   notarytool keychain profile (xcrun notarytool store-credentials …); notarizes and staples.
# Output: build/release/SlashOffice.zip and SlashOffice.zip.sha256. The GitHub release is created separately
# (the command is printed at the end).
set -eu
cd "$(dirname "$0")/.."
VERSION=${1:?usage: scripts/release.sh <version>}
PLIST_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
[ "$VERSION" = "$PLIST_VERSION" ] || { echo "Info.plist says $PLIST_VERSION, not $VERSION" >&2; exit 1; }

OUT=build/release
rm -rf "$OUT"
mkdir -p "$OUT"
APP="$OUT/SlashOffice.app"

# Derleme çıktısı günlüğe gider; başarısız olursa sonu gösterilir (yoksa hata sessizce kaybolur).
LOG="$OUT/make-app.log"
build() {
    echo "building the universal app (arm64 + x86_64; the first build takes a few minutes)…"
    if ! "$@" > "$LOG" 2>&1; then
        echo "error: scripts/make-app.sh failed; last lines of $LOG:" >&2
        tail -n 40 "$LOG" >&2
        exit 1
    fi
}
if [ -n "${DEVELOPER_ID:-}" ]; then
    build env ARCHS="arm64 x86_64" CODESIGN_IDENTITY="$DEVELOPER_ID" CODESIGN_RUNTIME=1 scripts/make-app.sh "$APP"
else
    echo "note: DEVELOPER_ID not set — ad-hoc signed; use install.sh or Homebrew to avoid Gatekeeper prompts" >&2
    build env ARCHS="arm64 x86_64" CODESIGN_IDENTITY=- scripts/make-app.sh "$APP"
fi
lipo -archs "$APP/Contents/MacOS/AgentOffice"
codesign --verify --strict "$APP"

if [ -n "${DEVELOPER_ID:-}" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
    ditto -c -k --keepParent "$APP" "$OUT/notarize.zip"
    xcrun notarytool submit "$OUT/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    rm "$OUT/notarize.zip"
    spctl --assess --type execute --verbose "$APP"
fi

ditto -c -k --keepParent "$APP" "$OUT/SlashOffice.zip"
(cd "$OUT" && shasum -a 256 SlashOffice.zip > SlashOffice.zip.sha256)
cat "$OUT/SlashOffice.zip.sha256"
echo
echo "After pushing tag v$VERSION, put this sha256 into the Homebrew formula:"
echo "  curl -fsSL https://github.com/egekolSlash/slash-office/archive/refs/tags/v$VERSION.tar.gz | shasum -a 256"
echo "Create the release with:"
echo "  gh release create v$VERSION $OUT/SlashOffice.zip $OUT/SlashOffice.zip.sha256 --title \"Slash Office $VERSION\" --notes-file <notes.md>"
