import Foundation
import Testing
@testable import AgentOfficeCore

@Suite struct AvatarLookTests {
    @Test func defaultIsStablePerSessionAndVaried() {
        #expect(AvatarLook.default(for: "abc") == AvatarLook.default(for: "abc"))
        let looks = (0..<200).map { AvatarLook.default(for: "session-\($0)") }
        // Yeni saç modelleri Randomize'dan gelir; varsayılan dört klasik modelde kalır.
        #expect(Set(looks.map(\.hairStyle)) == [.short, .pigtails, .spiky, .bob])
        #expect(Set(looks.map(\.glasses)).count == 2)
        #expect(looks.allSatisfy { AvatarLook.hairColors.indices.contains($0.hairColor) && AvatarLook.skinTones.indices.contains($0.skin) })
        #expect(looks.allSatisfy { $0.shirtColor == nil })  // varsayılan: proje rengi
    }

    @Test func randomStaysInRange() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<50 {
            let look = AvatarLook.random(using: &rng)
            #expect(AvatarLook.hairColors.indices.contains(look.hairColor))
            #expect(look.shirtColor.map { AvatarLook.shirtColors.indices.contains($0) } ?? true)
        }
    }

    @Test func roomStyleDefaultsAreStableAndInRange() {
        let style = RoomStyle.default(for: "/git/juice-merge")
        #expect(style == RoomStyle.default(for: "/git/juice-merge"))
        #expect((0..<RoomStyle.wallpaperCount).contains(style.wallpaper))
        #expect((0..<RoomStyle.floorCount).contains(style.floor))
    }

    @Test func storeRemovesAndPersists() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("looks-\(UUID()).json")
        #expect(StyleStore<AvatarLook>.load(from: url).isEmpty)
        var looks = ["a": AvatarLook.default(for: "a"), "b": AvatarLook.default(for: "b")]
        looks["a"]?.glasses.toggle()
        try StyleStore.save(looks, to: url)
        #expect(StyleStore<AvatarLook>.load(from: url) == looks)
        looks["b"] = nil
        try StyleStore.save(looks, to: url)
        #expect(StyleStore<AvatarLook>.load(from: url).keys.sorted() == ["a"])
    }

    @Test func paletteStillStableAfterHashRefactor() {
        #expect(StableHash.fnv1a("") == 0xcbf29ce484222325)
        #expect(ProjectPalette.index(for: "/Users/me/git/juice-merge") == ProjectPalette.index(for: "/Users/me/git/juice-merge"))
    }

    /// Eski kayıt (yeni alanlar yok): bugünkü görünüm; isim yok.
    @Test func oldLookDecodesUnchanged() throws {
        let json = Data(#"{"hairStyle":"bob","hairColor":2,"skin":1,"shirtPattern":"dots","shirtColor":3,"glasses":true}"#.utf8)
        let look = try JSONDecoder().decode(AvatarLook.self, from: json)
        #expect(look.hairStyle == .bob && look.glasses && look.shirtColor == 3)
        #expect(look.name == nil && look.hat == .none && look.eyes == .round && look.brows == .none && look.mouth == .smile)
        #expect(look.pantsColor == 0 && look.shoeColor == 0 && !look.freckles && look.blush)
        let again = try JSONDecoder().decode(AvatarLook.self, from: JSONEncoder().encode(look))
        #expect(again == look)
    }

    /// Kaydedilmemiş görünüm (oturum kimliğinden) yeni alanlarda bugünkü görünümü verir: mevcut köylüler değişmez.
    @Test func defaultKeepsTodaysNewFields() {
        for id in ["a", "b", "c", "d"] {
            let look = AvatarLook.default(for: id)
            #expect(look.hat == .none && look.eyes == .round && look.brows == .none && look.mouth == .smile)
            #expect(look.pantsColor == 0 && look.shoeColor == 0 && !look.freckles && look.blush && look.name == nil)
        }
    }

    @Test func randomCoversNewFields() {
        var rng = SystemRandomNumberGenerator()
        let looks = (0..<400).map { _ in AvatarLook.random(using: &rng) }
        #expect(Set(looks.map(\.hat)) == Set(AvatarLook.Hat.allCases))
        #expect(Set(looks.map(\.hairStyle)) == Set(AvatarLook.HairStyle.allCases))
        #expect(Set(looks.map(\.eyes)) == Set(AvatarLook.Eyes.allCases))
        #expect(Set(looks.map(\.mouth)) == Set(AvatarLook.Mouth.allCases))
        #expect(looks.allSatisfy { AvatarLook.pantsColors.indices.contains($0.pantsColor) && AvatarLook.shoeColors.indices.contains($0.shoeColor) })
        #expect(looks.allSatisfy { $0.name == nil })
    }

    @Test func nameIsTrimmedAndEmptyIsNil() {
        #expect(AvatarLook.trimmedName("  Ayşe \n") == "Ayşe")
        #expect(AvatarLook.trimmedName("   ") == nil)
        #expect(AvatarLook.trimmedName("") == nil)
    }

    /// Çizicinin varyant baytları: grup → seçili değer (0: o gruptan hiçbir şey görünmez).
    @Test func variantValuesMapEveryGroup() {
        var look = AvatarLook(hairStyle: .bun, hairColor: 0, skin: 0, shirtPattern: .plain, shirtColor: nil, glasses: true)
        look.eyes = .sleepy; look.brows = .bold; look.mouth = .flat; look.freckles = true; look.blush = false
        var v = look.variantValues
        #expect(v.count == 16)
        #expect(v[VillagerVariant.hair] == 7 && v[VillagerVariant.hat] == 0)
        #expect(v[VillagerVariant.eyes] == 3 && v[VillagerVariant.brows] == 2 && v[VillagerVariant.mouth] == 3)
        #expect(v[VillagerVariant.freckles] == 1 && v[VillagerVariant.blush] == 0 && v[VillagerVariant.glasses] == 1)
        #expect(v[VillagerVariant.hairCap] == 1 && v[VillagerVariant.hairTop] == 7)
        // Şapka varken saçın tepesi ve tepe süsleri gizlenir; yanlar kalır.
        look.hat = .cap
        v = look.variantValues
        #expect(v[VillagerVariant.hat] == 2 && v[VillagerVariant.hairCap] == 0 && v[VillagerVariant.hairTop] == 0)
        #expect(v[VillagerVariant.hair] == 7)
        #expect(v[0] == 0)
    }

    /// Köylünün adı varsa oturum başlığının yerine geçer; başlık (proje) altta kalır.
    @Test func displayNameUsesTheVillagerName() {
        var look = AvatarLook.default(for: "x")
        #expect(look.displayName(title: "juice-merge") == "juice-merge" && look.subtitle(title: "juice-merge") == nil)
        look.name = "Ayşe"
        #expect(look.displayName(title: "juice-merge") == "Ayşe" && look.subtitle(title: "juice-merge") == "juice-merge")
    }

    /// Paletin ilk pantolon ve ayakkabı rengi, Blender'da pişirilmiş bugünkü renklerin sRGB karşılığı (çizici
    /// boyamayı sRGB sayar): mevcut köylülerin pantolonu ve ayakkabısı değişmez.
    @Test func firstPantsAndShoeColorsMatchTheBakedOnes() {
        func srgb(_ c: Double) -> Double { c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055 }
        let pants = AvatarLook.pantsColors[0], shoes = AvatarLook.shoeColors[0]
        #expect(abs(pants.red - srgb(0.25)) < 0.01 && abs(pants.green - srgb(0.30)) < 0.01 && abs(pants.blue - srgb(0.45)) < 0.01)
        #expect(abs(shoes.red - srgb(0.55)) < 0.01 && abs(shoes.green - srgb(0.32)) < 0.01 && abs(shoes.blue - srgb(0.20)) < 0.01)
    }
}

