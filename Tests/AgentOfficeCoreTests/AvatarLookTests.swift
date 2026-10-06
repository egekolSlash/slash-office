import Foundation
import Testing
@testable import AgentOfficeCore

@Suite struct AvatarLookTests {
    @Test func defaultIsStablePerSessionAndVaried() {
        #expect(AvatarLook.default(for: "abc") == AvatarLook.default(for: "abc"))
        let looks = (0..<200).map { AvatarLook.default(for: "session-\($0)") }
        #expect(Set(looks.map(\.hairStyle)).count == AvatarLook.HairStyle.allCases.count)
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
}
