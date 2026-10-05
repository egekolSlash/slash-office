#!/bin/sh
# Agent Office'i bildirimlerin ve mikrofonun çalışabileceği bir .app paketine koyar.
# Kullanım: scripts/make-app.sh [hedef.app]   (varsayılan: build/AgentOffice.app)
set -eu
cd "$(dirname "$0")/.."
swift build -c release
BIN=$(swift build -c release --show-bin-path)
APP=${1:-build/AgentOffice.app}
STAGE=$(mktemp -d)/AgentOffice.app
mkdir -p "$STAGE/Contents/MacOS"
cp Resources/Info.plist "$STAGE/Contents/Info.plist"
cp "$BIN/AgentOffice" "$BIN/agent-office-hook" "$STAGE/Contents/MacOS/"
codesign --force --sign - "$STAGE" >/dev/null
# Paket önce geçici yerde hazırlanır, sonra tek adımda yerine konur.
rm -rf "$APP"
mkdir -p "$(dirname "$APP")"
mv "$STAGE" "$APP"
echo "$APP"
