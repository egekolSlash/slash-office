#!/bin/sh
# Slash Office'i bildirimlerin ve mikrofonun çalışabileceği bir .app paketine koyar.
# Kullanım: scripts/make-app.sh [hedef.app]   (varsayılan: build/SlashOffice.app)
set -eu
cd "$(dirname "$0")/.."
swift build -c release
BIN=$(swift build -c release --show-bin-path)
APP=${1:-build/SlashOffice.app}
STAGE=$(mktemp -d)/SlashOffice.app
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp Resources/Info.plist "$STAGE/Contents/Info.plist"
# Uyarlanabilir ikon (macOS 26 Icon Composer: açık/koyu/renklendirilmiş, Liquid Glass) actool ile Assets.car'a
# derlenir; eski sistemler için AppIcon.icns de yanında. actool yoksa depodaki AppIcon.icns kullanılır.
if xcrun --find actool >/dev/null 2>&1; then
    xcrun actool tools/app-icon/AppIcon.icon --compile "$STAGE/Contents/Resources" --platform macosx \
        --minimum-deployment-target 26.0 --app-icon AppIcon \
        --output-partial-info-plist "$(dirname "$STAGE")/icon-info.plist" >/dev/null
else
    cp Resources/AppIcon.icns "$STAGE/Contents/Resources/AppIcon.icns"
fi
# Ofis v3 varlıkları (köylü + eşyalar, scripts/build-office-art.sh ile üretilir).
cp -R Resources/OfficeArt "$STAGE/Contents/Resources/OfficeArt"
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
