/// Odadaki eşyalar (ofis hayatı spec §B2): oda düzenleyicisinden tek tek açılıp kapatılır, varsayılan hepsi açık.
/// Kapalı eşya çizilmez, engel değildir, köylüler oraya gitmez.
public enum RoomFurniture: String, CaseIterable, Codable, Sendable {
    case sofa, coffeeTable, waterCooler, plant, bookshelf, arcade, whiteboard, coffeeMachine

    public static let all = Set(allCases)
}

extension OfficePlan {
    /// Odaların eşyaları (oda stilinden); listede olmayan oda hepsini alır.
    public func applying(furniture: [String: Set<RoomFurniture>]) -> OfficePlan {
        var plan = self
        for i in plan.rooms.indices { plan.rooms[i].furniture = furniture[plan.rooms[i].key] ?? RoomFurniture.all }
        return plan
    }
}
