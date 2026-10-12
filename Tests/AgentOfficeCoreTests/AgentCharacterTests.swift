import Foundation
import Testing
@testable import AgentOfficeCore

/// Karakterler, oda kayıtları, kadrodan atama, eski görünüşlerin taşınması ve paketler.
@Suite struct AgentCharacterTests {
    static let look = AvatarLook.default(for: "x")

    @Test func characterRoundTripsAndOldFieldsDefault() throws {
        var c = AgentCharacter(id: "c1", name: "Ada", role: "frontend", look: Self.look)
        c.personality.favorites[.arcade] = 3
        c.personality.pace = .brisk
        c.signature = Signature(celebration: .peace, restingMouth: .flat)
        c.look.colors.top = AvatarLook.Color(0.1, 0.2, 0.3)
        c.look.top = "coat.tweed"
        #expect(try JSONDecoder().decode(AgentCharacter.self, from: JSONEncoder().encode(c)) == c)
        #expect(c.label == "Ada · frontend")
        // Kişilik ve imza olmadan kaydedilmiş karakter; tanınmayan eşya ve sevinç adları atlanır.
        let json = #"{"id":"c2","name":"Bo","look":{"hairStyle":"bob","hairColor":1,"skin":2,"shirtPattern":"dots","glasses":false},"personality":{"favorites":{"rocket":2,"sofa":0}},"signature":{"celebration":"moonwalk"}}"#
        let old = try JSONDecoder().decode(AgentCharacter.self, from: Data(json.utf8))
        #expect(old.role == nil && old.personality.weight(.sofa) == 0 && old.personality.weight(.arcade) == 1)
        #expect(old.signature.celebration == .cheer && old.look.top == "tee")
    }

    @Test func roomRecordReadsTheOldStyleFormat() throws {
        let old = #"{"wallpaper":1,"floor":2,"rug":"plain"}"#
        let record = try JSONDecoder().decode(RoomRecord.self, from: Data(old.utf8))
        #expect(record.style == RoomStyle(wallpaper: 1, floor: 2, rug: .plain) && record.cast.isEmpty && record.name == nil)
        let full = RoomRecord(name: "API", style: nil, cast: ["a", "b"])
        #expect(try JSONDecoder().decode(RoomRecord.self, from: JSONEncoder().encode(full)) == full)
        #expect(RoomRecord().isEmpty && !full.isEmpty)
    }

    @Test func castGivesTheFirstFreeCharacterPerRoom() {
        typealias Seat = CastAssignment.Seat
        let rooms = ["/a": RoomRecord(cast: ["x", "y"]), "/b": RoomRecord(cast: ["x"])]
        let chars: Set = ["x", "y", "z"]
        let seats = [Seat(id: "1", roomKey: "/a", choice: nil), Seat(id: "2", roomKey: "/a", choice: nil),
                     Seat(id: "3", roomKey: "/a", choice: nil), Seat(id: "4", roomKey: "/b", choice: nil),
                     Seat(id: "5", roomKey: "/c", choice: nil)]
        let result = CastAssignment.assign(seats, rooms: rooms, characters: chars)
        // Sırayla: x, y; üçüncü kadroda yer kalmadı (rastgele); başka oda aynı karakteri kullanabilir; kadrosuz oda yok.
        #expect(result == ["1": "x", "2": "y", "4": "x"])
        // Elle seçilmiş karakter yerini korur, otomatikler kalanı alır; "rastgele" seçimi kadrodan almaz.
        let manual = [Seat(id: "1", roomKey: "/a", choice: nil), Seat(id: "2", roomKey: "/a", choice: "x"),
                      Seat(id: "3", roomKey: "/a", choice: CastAssignment.random)]
        #expect(CastAssignment.assign(manual, rooms: rooms, characters: chars) == ["2": "x", "1": "y"])
        // Silinmiş karakter seçimi otomatiğe döner.
        let gone = [Seat(id: "1", roomKey: "/a", choice: "deleted")]
        #expect(CastAssignment.assign(gone, rooms: rooms, characters: chars) == ["1": "x"])
    }

    @Test func migrationTurnsSavedLooksIntoCharacters() {
        var named = Self.look
        named.name = "Ayşe"
        let result = CharacterMigration.migrate(looks: ["s1": named, "s2": Self.look], titles: ["s1": "api", "s2": "web"],
                                                roomKeys: ["s1": "/api", "s2": "/web"],
                                                rooms: ["/api": RoomRecord(style: RoomStyle(wallpaper: 0, floor: 0, rug: .dots))])
        #expect(result.characters.map(\.name).sorted() == ["Ayşe", "web"])
        #expect(result.characters.allSatisfy { $0.look.name == nil })
        #expect(result.rooms["/api"]?.cast == [result.choices["s1"]!] && result.rooms["/api"]?.style != nil)
        #expect(result.rooms["/web"]?.cast == [result.choices["s2"]!])
    }

    @Test func missingGarmentsFallBackToTheirBaseItem() throws {
        let art = try CharacterArt.decode(CharacterArtTests.pack(fallbacks: ["coat": "tee"]), directory: URL(fileURLWithPath: "/tmp"))
        let names = art.outfits.map(\.name)
        #expect(art.resolve("dress", in: art.outfits) == names.firstIndex(of: "dress"))
        // Paket öğesi yok: kalıba (`dress.lace` → `dress`), kalıp da yoksa temel karşılığa (`coat` → `tee`), o da yoksa ilk öğe.
        #expect(art.resolve("dress.lace", in: art.outfits) == names.firstIndex(of: "dress"))
        #expect(art.resolve("coat.tweed", in: art.outfits) == names.firstIndex(of: "tee"))
        #expect(art.resolve("kimono.blue", in: art.outfits) == 0)
    }

    @Test func personalityWeightsSteerIdleChoices() {
        var counts: [RoomSpot.Kind: Int] = [:]
        for i in 0..<300 {
            var p = Personality()
            p.favorites = [.arcade: 3, .sofa: 0, .plant: 1]
            var behavior = AvatarBehavior(id: "v\(i)", personality: p)
            behavior.setActivity(.dozing, finishedNow: false)
            if case .goal(.spot(let kind, _, _, _))? = behavior.advance(dt: 0.1, freeSpots: [.arcade, .sofa, .plant]) {
                counts[kind, default: 0] += 1
            }
        }
        #expect(counts[.sofa] == nil)
        #expect((counts[.arcade] ?? 0) > (counts[.plant] ?? 0) * 2)
    }

    @Test func packInstallVerifiesTheChecksum() throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("pack-test-\(UUID().uuidString)")
        let source = work.appendingPathComponent("wardrobe")
        try fm.createDirectory(at: source.appendingPathComponent("tex"), withIntermediateDirectories: true)
        try Data(#"{"meshes":{}}"#.utf8).write(to: source.appendingPathComponent("pack.json"))
        let zip = work.appendingPathComponent("wardrobe.zip")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--keepParent", source.path, zip.path]
        try ditto.run()
        ditto.waitUntilExit()
        let root = work.appendingPathComponent("Packs")
        let sha = try PackStore.sha256(of: zip)
        let bad = PackInfo(id: "wardrobe", title: "W", version: "1", url: "", sha256: String(repeating: "0", count: 64), bytes: 1)
        #expect(throws: PackStore.Failure.checksum) { try PackStore.install(zip: zip, info: bad, root: root) }
        #expect(PackStore.installed(in: root).isEmpty)
        var good = bad
        good.sha256 = sha
        try PackStore.install(zip: zip, info: good, root: root)
        let installed = PackStore.installed(in: root)
        #expect(installed.map(\.id) == ["wardrobe"] && installed.first?.version == "1")
        try PackStore.remove(id: "wardrobe", root: root)
        #expect(PackStore.installed(in: root).isEmpty)
        try? fm.removeItem(at: work)
    }
}
