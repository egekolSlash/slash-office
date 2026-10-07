# Uygulama ikonu

- `slash-o-source.png`: Kaynak çizim (koyu zemin üzerinde "/o").
- `extract-glyph.swift`: Kaynaktan şeffaf "/o" katmanını çıkarır, büyütür ve göz için biraz yukarı alır. Çıktısı `AppIcon.icon/Assets/glyph.png`.
- `AppIcon.icon`: macOS 26 Icon Composer paketi.
  - Koyu degrade zemin ve "/o" katmanı.
  - Açık, koyu ve renklendirilmiş görünümler ile Liquid Glass sistemden gelir.
  - Icon Composer ile açılıp düzenlenebilir.
- `scripts/make-app.sh`: Paketi `actool` ile `Assets.car` ve `AppIcon.icns`'e derler.
- `Resources/AppIcon.icns`: `swift run` ve `actool` olmayan ortamlar için derlenmiş yedek.
- `make-icns.swift`: Eski yöntem: düz `.icns` (Apple ikon ızgarası).

Yeniden üretmek için:

    swift tools/app-icon/extract-glyph.swift tools/app-icon/slash-o-source.png tools/app-icon/AppIcon.icon/Assets/glyph.png
    xcrun actool tools/app-icon/AppIcon.icon --compile /tmp/icon --platform macosx --minimum-deployment-target 26.0 \
        --app-icon AppIcon --output-partial-info-plist /tmp/icon/info.plist && cp /tmp/icon/AppIcon.icns Resources/AppIcon.icns
