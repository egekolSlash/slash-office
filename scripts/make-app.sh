#!/bin/sh
# Slash Office'i bildirimlerin ve mikrofonun çalışabileceği bir .app paketine koyar.
# Kullanım: scripts/make-app.sh [hedef.app]   (varsayılan: build/SlashOffice.app)
# Ortam:
#   ARCHS="arm64 x86_64"   evrensel derleme (varsayılan: bu makinenin mimarisi)
#   CODESIGN_IDENTITY      imza kimliği (varsayılan: varsa "Apple Development", yoksa ad-hoc)
#   CODESIGN_RUNTIME=1     hardened runtime ile imzala (Developer ID + notarize için)
#   SWIFT_BUILD_FLAGS      swift build'e ek bayraklar (Homebrew: --disable-sandbox)
set -eu
cd "$(dirname "$0")/.."
APP=${1:-build/SlashOffice.app}
STAGE=$(mktemp -d)/SlashOffice.app
# Her mimari ayrı derlenip lipo ile birleştirilir (tek komutta çok mimari SwiftPM'i Xcode derleyicisine geçirir;
# o da SwiftTerm'in eklentisini çözemiyor).
BINS=""
for arch in ${ARCHS:-}; do
    # shellcheck disable=SC2086
    swift build -c release --arch "$arch" ${SWIFT_BUILD_FLAGS:-}
    # shellcheck disable=SC2086
    BINS="$BINS $(swift build -c release --arch "$arch" ${SWIFT_BUILD_FLAGS:-} --show-bin-path)"
done
if [ -z "$BINS" ]; then
    # shellcheck disable=SC2086
    swift build -c release ${SWIFT_BUILD_FLAGS:-}
    # shellcheck disable=SC2086
    BINS=$(swift build -c release ${SWIFT_BUILD_FLAGS:-} --show-bin-path)
fi
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp Resources/Info.plist "$STAGE/Contents/Info.plist"
# Derleme numarası: commit sayısı (her sürümde artar).
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD 2>/dev/null || echo 1)" "$STAGE/Contents/Info.plist"
# Uyarlanabilir ikon (macOS 26 Icon Composer: açık/koyu/renklendirilmiş, Liquid Glass) actool ile Assets.car'a
# derlenir; eski sistemler için AppIcon.icns de yanında. actool yoksa depodaki AppIcon.icns kullanılır.
if xcrun --find actool >/dev/null 2>&1; then
    xcrun actool tools/app-icon/AppIcon.icon --compile "$STAGE/Contents/Resources" --platform macosx \
        --minimum-deployment-target 26.0 --app-icon AppIcon \
        --output-partial-info-plist "$(dirname "$STAGE")/icon-info.plist" >/dev/null
else
    cp Resources/AppIcon.icns "$STAGE/Contents/Resources/AppIcon.icns"
fi
# Arayüz metinleri: İngilizce kaynak, Türkçe çeviri (String Catalog → en.lproj / tr.lproj).
if xcrun --find xcstringstool >/dev/null 2>&1; then
    xcrun xcstringstool compile Resources/Localizable.xcstrings --output-directory "$STAGE/Contents/Resources" >/dev/null
else
    echo "uyarı: xcstringstool yok (Xcode gerekli); uygulama sadece İngilizce olacak" >&2
fi
mkdir -p "$STAGE/Contents/Resources/tr.lproj" "$STAGE/Contents/Resources/en.lproj"
cp Resources/tr.lproj/InfoPlist.strings "$STAGE/Contents/Resources/tr.lproj/"
# en.lproj de olmalı: yoksa Türkçe sistemde "English" seçilince macOS tek mevcut dil olan Türkçeye düşer.
[ -f "$STAGE/Contents/Resources/en.lproj/Localizable.strings" ] || cp Resources/en.lproj/Localizable.strings "$STAGE/Contents/Resources/en.lproj/"
# Ofis v3 varlıkları (köylü + eşyalar, scripts/build-office-art.sh ile üretilir).
cp -R Resources/OfficeArt "$STAGE/Contents/Resources/OfficeArt"
for exe in AgentOffice agent-office-hook; do
    # shellcheck disable=SC2086
    lipo -create $(for bin in $BINS; do printf '%s/%s ' "$bin" "$exe"; done) -output "$STAGE/Contents/MacOS/$exe"
done
# macOS izinleri (klasör erişimi, mikrofon) imzaya bağlı: ad-hoc imza her derlemede değişip izinleri sıfırlar.
# Sabit bir sertifika varsa onunla imzalanır; CODESIGN_IDENTITY ile seçilebilir, yoksa ad-hoc'a düşer.
IDENTITY=${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development/ {print $2; exit}')}
SIGN_FLAGS="--force --sign ${IDENTITY:--}"
APP_FLAGS=""
if [ "${CODESIGN_RUNTIME:-0}" = 1 ]; then
    SIGN_FLAGS="$SIGN_FLAGS --options runtime --timestamp"
    APP_FLAGS="--entitlements Resources/SlashOffice.entitlements"
fi
# İçteki yardımcı önce, sonra paket (--deep yerine).
# shellcheck disable=SC2086
codesign $SIGN_FLAGS "$STAGE/Contents/MacOS/agent-office-hook" >/dev/null
# shellcheck disable=SC2086
codesign $SIGN_FLAGS $APP_FLAGS "$STAGE" >/dev/null
# Paket önce geçici yerde hazırlanır, sonra tek adımda yerine konur.
rm -rf "$APP"
mkdir -p "$(dirname "$APP")"
mv "$STAGE" "$APP"
echo "$APP"
