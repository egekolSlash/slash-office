/// Odadaki eşyalar (ofis hayatı spec §B2): oda düzenleyicisinden tek tek açılıp kapatılır, varsayılan hepsi açık.
/// Kapalı eşya çizilmez, engel değildir, köylüler oraya gitmez.
public enum RoomFurniture: String, CaseIterable, Codable, Sendable {
    case sofa, coffeeTable, waterCooler, plant, bookshelf, arcade, whiteboard, coffeeMachine

    public static let all = Set(allCases)
}

/// Masaların yönü (ayarlar): yatayda masa enine durur, köylü arkasında oturup kameraya bakar; dikeyde masa boyuna
/// durur, köylü koridora bakar.
public enum DeskOrientation: String, CaseIterable, Codable, Sendable {
    case horizontal, vertical
}

extension OfficePlan {
    public func applying(deskOrientation: DeskOrientation) -> OfficePlan {
        var plan = self
        for i in plan.rooms.indices { plan.rooms[i].deskOrientation = deskOrientation }
        return plan
    }

    /// Odaların eşyaları (oda stilinden); listede olmayan oda hepsini alır.
    public func applying(furniture: [String: Set<RoomFurniture>]) -> OfficePlan {
        var plan = self
        for i in plan.rooms.indices { plan.rooms[i].furniture = furniture[plan.rooms[i].key] ?? RoomFurniture.all }
        return plan
    }
}
