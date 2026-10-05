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
# macOS izinleri (klasör erişimi, mikrofon) imzaya bağlı: ad-hoc imza her derlemede değişip izinleri sıfırlar.
# Sabit bir sertifika varsa onunla imzalanır; CODESIGN_IDENTITY ile seçilebilir, yoksa ad-hoc'a düşer.
IDENTITY=${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk '/Apple Development/ {print $2; exit}')}
codesign --force --sign "${IDENTITY:--}" "$STAGE" >/dev/null
# Paket önce geçici yerde hazırlanır, sonra tek adımda yerine konur.
rm -rf "$APP"
mkdir -p "$(dirname "$APP")"
mv "$STAGE" "$APP"
echo "$APP"
