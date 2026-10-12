import AgentOfficeCore
import Foundation

/// Karakterler ve odalar: kayıt, kadrodan atama, eski görünüşlerin taşınması.
extension AppModel {
    var charactersURL: URL { supportDirectory.appendingPathComponent("characters.json") }

    func character(id: String) -> AgentCharacter? { characters.first { $0.id == id } }

    /// Oturumun karakteri (kadrodan ya da elle seçilmiş); karaktersizse nil.
    func character(for sessionID: String) -> AgentCharacter? { cast[sessionID].flatMap(character(id:)) }

    /// Köylünün üstündeki etiket: karakterin adı (· rol) ya da elle verilen ad; yoksa nil (etiket yok).
    func overheadLabel(for sessionID: String) -> String? {
        character(for: sessionID)?.label ?? avatarLooks[sessionID]?.name
    }

    func room(for key: String) -> RoomRecord { rooms[key] ?? RoomRecord() }

    /// Odanın görünen adı: verilen isim, yoksa klasör adı.
    func roomName(for key: String) -> String { rooms[key]?.name ?? (key as NSString).lastPathComponent }

    /// Oturumlara kadrodan karakter verir; yeni otomatik atamalar oturum kaydına yazılır (karakter sabit kalsın).
    /// Odası henüz bilinmeyen (git kökü aranıyor) oturum beklemede kalır.
    func refreshCast() {
        let ordered = records.values.filter { store.session($0.id) != nil }.sorted { $0.createdAt < $1.createdAt }
        let seats = ordered.compactMap { record -> CastAssignment.Seat? in
            guard let identity = roomIdentities[record.cwd] else {
                // Oda belli değil: elle seçilmiş karakter yine görünsün.
                return record.characterID.map { CastAssignment.Seat(id: record.id, roomKey: record.cwd, choice: $0) }
            }
            return CastAssignment.Seat(id: record.id, roomKey: identity.roomKey, choice: record.characterID)
        }
        let assigned = CastAssignment.assign(seats, rooms: rooms, characters: Set(characters.map(\.id)))
        var changed = false
        for (id, characterID) in assigned where records[id]?.characterID == nil {
            records[id]?.characterID = characterID
            changed = true
        }
        if changed { saveRecords() }
        if assigned != cast { cast = assigned }
    }

    /// Oturumun karakterini değiştirir: kimlik, `CastAssignment.random` ya da nil (kadrodan otomatik).
    func setCharacter(_ characterID: String?, for sessionID: String) {
        records[sessionID]?.characterID = characterID
        saveRecords()
        refreshCast()
    }

    /// Karaktersiz oturumun bugünkü görünüşünden karakter yapar, oturuma bağlar ve odasının kadrosuna ekler.
    @discardableResult
    func saveAsCharacter(_ sessionID: String) -> String {
        let title = store.session(sessionID)?.title ?? "?"
        var look = look(for: sessionID)
        let name = look.name ?? title
        look.name = nil
        let character = AgentCharacter(name: name, look: look)
        characters.append(character)
        saveCharacters()
        if let cwd = store.session(sessionID)?.cwd {
            let key = roomKey(for: cwd)
            var room = room(for: key)
            if !room.cast.contains(character.id) { room.cast.append(character.id) }
            setRoom(room, for: key)
        }
        setCharacter(character.id, for: sessionID)
        return character.id
    }

    @discardableResult
    func addCharacter(_ character: AgentCharacter? = nil) -> String {
        var rng = SystemRandomNumberGenerator()
        let new = character ?? AgentCharacter(name: String(localized: "New Character"), look: AvatarLook.random(using: &rng))
        characters.append(new)
        saveCharacters()
        return new.id
    }

    func updateCharacter(_ character: AgentCharacter) {
        guard let i = characters.firstIndex(where: { $0.id == character.id }), characters[i] != character else { return }
        characters[i] = character
        saveCharacters()
    }

    @discardableResult
    func duplicateCharacter(_ id: String) -> String? {
        guard var copy = character(id: id) else { return nil }
        copy.id = UUID().uuidString.lowercased()
        copy.name = String(localized: "\(copy.name) Copy")
        return addCharacter(copy)
    }

    /// Karakteri siler: kadrolardan çıkar; onu kullanan oturumlar kadrodan yeniden karakter alır.
    func deleteCharacter(_ id: String) {
        characters.removeAll { $0.id == id }
        saveCharacters()
        for key in rooms.keys where rooms[key]?.cast.contains(id) == true {
            var room = rooms[key]!
            room.cast.removeAll { $0 == id }
            setRoom(room, for: key, refresh: false)
        }
        for (sessionID, record) in records where record.characterID == id { records[sessionID]?.characterID = nil }
        saveRecords()
        refreshCast()
    }

    func moveCharacters(from source: IndexSet, to destination: Int) {
        characters.move(fromOffsets: source, toOffset: destination)
        saveCharacters()
    }

    func setRoom(_ room: RoomRecord, for key: String, refresh: Bool = true) {
        rooms[key] = room.isEmpty ? nil : room
        do { try StyleStore.save(rooms, to: roomStylesURL) } catch {
            errorMessage = String(localized: "The room could not be saved: \(error.localizedDescription)")
        }
        if refresh { refreshCast() }
    }

    /// Bir proje klasörü için oda kaydı açar (klasörün deposu anahtar olur); anahtarı döner.
    func addRoom(folder: URL) async -> String {
        let path = folder.path
        let identity = await Task.detached(priority: .userInitiated) { RepoIdentity.locate(path) }.value
        roomIdentities[path] = identity
        if rooms[identity.roomKey] == nil {
            setRoom(RoomRecord(name: folder.lastPathComponent), for: identity.roomKey)
        }
        return identity.roomKey
    }

    func deleteRoom(_ key: String) { setRoom(RoomRecord(), for: key) }

    func saveCharacters() {
        do { try CharacterFile.save(characters, to: charactersURL) } catch {
            errorMessage = String(localized: "The characters could not be saved: \(error.localizedDescription)")
        }
    }

    /// İlk açılışta eski oturum görünüşleri karaktere dönüşür (bir kez; `characters.json` yoksa). Eski dosya
    /// `avatars.migrated.json` olarak kalır.
    func migrateLooksIfNeeded() {
        guard !FileManager.default.fileExists(atPath: charactersURL.path), !avatarLooks.isEmpty else { return }
        let looks = avatarLooks.filter { records[$0.key] != nil }
        let titles = records.mapValues(\.title)
        let roomKeys = looks.keys.reduce(into: [String: String]()) { result, id in
            guard let cwd = records[id]?.cwd else { return }
            let identity = RepoIdentity.locate(cwd)
            roomIdentities[cwd] = identity
            result[id] = identity.roomKey
        }
        let result = CharacterMigration.migrate(looks: looks, titles: titles, roomKeys: roomKeys, rooms: rooms)
        characters = result.characters
        for (id, characterID) in result.choices { records[id]?.characterID = characterID }
        rooms = result.rooms
        saveCharacters()
        saveRecords()
        do { try StyleStore.save(rooms, to: roomStylesURL) } catch {}
        let backup = supportDirectory.appendingPathComponent("avatars.migrated.json")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: avatarsURL, to: backup)
        avatarLooks = [:]
    }
}
