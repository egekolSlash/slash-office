#!/bin/sh
# Slash Office installer: downloads the latest release, verifies its checksum and installs it into
# /Applications (or ~/Applications when /Applications is not writable).
#
#   curl -fsSL https://raw.githubusercontent.com/egekolSlash/slash-office/main/install.sh | sh
#
# Files downloaded with curl are not quarantined, so Gatekeeper does not block the app.
# SLASH_OFFICE_ZIP_URL / SLASH_OFFICE_SHA_URL / SLASH_OFFICE_DEST override the download and the install folder
# (used for testing); SLASH_OFFICE_NO_OPEN=1 skips opening the app.
set -eu

REPO="egekolSlash/slash-office"
ZIP_URL="${SLASH_OFFICE_ZIP_URL:-https://github.com/$REPO/releases/latest/download/SlashOffice.zip}"
SHA_URL="${SLASH_OFFICE_SHA_URL:-$ZIP_URL.sha256}"
APP_NAME="SlashOffice.app"

say() { printf '%s\n' "$*"; }
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "Slash Office runs on macOS only."
major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 26 ] 2>/dev/null || fail "Slash Office needs macOS 26 or later (this Mac has $(sw_vers -productVersion))."

if [ -n "${SLASH_OFFICE_DEST:-}" ]; then DEST=$SLASH_OFFICE_DEST
elif [ -w /Applications ]; then DEST=/Applications
else DEST="$HOME/Applications"; fi
mkdir -p "$DEST"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

say "Downloading Slash Office…"
curl -fL --progress-bar -o "$TMP/SlashOffice.zip" "$ZIP_URL" || fail "download failed ($ZIP_URL)."
curl -fsSL -o "$TMP/SlashOffice.zip.sha256" "$SHA_URL" || fail "checksum download failed ($SHA_URL)."

expected=$(awk '{print $1}' "$TMP/SlashOffice.zip.sha256")
actual=$(shasum -a 256 "$TMP/SlashOffice.zip" | awk '{print $1}')
[ -n "$expected" ] && [ "$expected" = "$actual" ] || fail "checksum mismatch — the download may be corrupted. Nothing was installed."

ditto -x -k "$TMP/SlashOffice.zip" "$TMP/unpacked" || fail "could not unpack the archive."
[ -d "$TMP/unpacked/$APP_NAME" ] || fail "the archive does not contain $APP_NAME."

# Quit the copy being replaced if it is running (its agents can be resumed after the update).
BINARY="$DEST/$APP_NAME/Contents/MacOS/AgentOffice"
if pgrep -qf "$BINARY"; then
    say "Quitting the running Slash Office…"
    osascript -e "tell application \"$DEST/$APP_NAME\" to quit" >/dev/null 2>&1 || true
    i=0
    while pgrep -qf "$BINARY" && [ $i -lt 50 ]; do sleep 0.2; i=$((i + 1)); done
    pgrep -qf "$BINARY" && fail "Slash Office is still running; quit it and run the installer again."
fi

# Copy next to the old app, move the old one aside, then swap: a failure at any step leaves a working app behind.
NEW="$DEST/$APP_NAME.new"
OLD="$DEST/$APP_NAME.old"
rm -rf "$NEW" "$OLD"
ditto "$TMP/unpacked/$APP_NAME" "$NEW" || { rm -rf "$NEW"; fail "could not copy into $DEST."; }
if [ -e "$DEST/$APP_NAME" ]; then
    mv "$DEST/$APP_NAME" "$OLD" || { rm -rf "$NEW"; fail "could not replace $DEST/$APP_NAME (is it owned by another user?)."; }
fi
if ! mv "$NEW" "$DEST/$APP_NAME"; then
    [ -e "$OLD" ] && mv "$OLD" "$DEST/$APP_NAME"
    fail "could not install into $DEST."
fi
rm -rf "$OLD" 2>/dev/null || say "Note: could not remove the previous copy at $OLD; delete it when convenient."

version=$(defaults read "$DEST/$APP_NAME/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "?")
say "Installed Slash Office $version in $DEST."
[ "${SLASH_OFFICE_NO_OPEN:-0}" = 1 ] || open "$DEST/$APP_NAME"
