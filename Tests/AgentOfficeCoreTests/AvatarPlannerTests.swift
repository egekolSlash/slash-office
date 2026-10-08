import Testing
@testable import AgentOfficeCore

@Suite struct AvatarPlannerTests {
    func room(_ count: Int = 4) -> OfficePlan.Room {
        let members = (0..<count).map { OfficePlan.Member(id: "s\($0)", roomKey: "/r") }
        return OfficePlan.make(members, slots: OfficePlan.assignSlots(members, previous: [:])).rooms[0]
    }

    @Test func activityFollowsState() {
        #expect(AvatarActivity.for(state: .working(tool: "Edit")) == .typing)
        #expect(AvatarActivity.for(state: .waiting(.permission("Bash"))) == .waving)
        #expect(AvatarActivity.for(state: .idle) == .dozing)
        #expect(AvatarActivity.for(state: .starting) == .dozing)
        #expect(AvatarActivity.for(state: .exited) == .away)
        #expect(AvatarActivity.hasAvatar(kind: .claude, state: .idle))
        #expect(!AvatarActivity.hasAvatar(kind: .shell, state: .idle))
        #expect(AvatarActivity.hasAvatar(kind: .shell, state: .working(tool: "claude")))
    }

    @Test func clipFramesMatchArtTimeline() {
        #expect(AvatarClip.walk.frames == 31...54)
        #expect(AvatarClip.wave.frames == 141...164)
    }

    @Test func standSpotsAreUniquePerDesk() {
        let r = room(6)
        let spots = r.desks.map { r.standSpot(for: $0) }
        for (i, a) in spots.enumerated() {
            for b in spots.dropFirst(i + 1) {
                #expect(a.distance(to: b) > 0.25, "\(a) ve \(b) çakışıyor")
            }
        }
    }
}
