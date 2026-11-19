import AgentOfficeCore
import Foundation
import SwiftUI

extension SessionSort {
    var title: LocalizedStringKey {
        switch self {
        case .manual: "Manual"
        case .activity: "Most Active"
        case .recent: "Recently Active"
        case .project: "Project"
        case .name: "Name"
        case .status: "Status"
        }
    }

    var symbol: String {
        switch self {
        case .manual: "hand.draw"
        case .activity: "flame"
        case .recent: "clock"
        case .project: "folder"
        case .name: "textformat"
        case .status: "exclamationmark.bubble"
        }
    }
}

extension AppModel {
    static let sessionSortKey = "sessionSort"

    /// Listede gösterilen sıra; ⌘[ / ⌘], bekleyene atlama ve "Tümünü devam ettir" de bu sırayı izler.
    func listedSessionIDs(now: Date = .now) -> [String] {
        let sessions = store.sessions
        guard sessionSort != .manual else { return sessions.map(\.id) }
        let heat = sessionSort == .activity
            ? ActivityHeat.levels(Dictionary(sessions.map { ($0.id, $0.activity) }) { first, _ in first }, now: now)
            : [:]
        let items = sessions.map { session in
            SessionOrder.Item(
                id: session.id,
                name: session.title,
                project: URL(fileURLWithPath: roomKey(for: session.cwd)).lastPathComponent,
                state: session.state,
                lastActive: [session.lastEventAt, session.attentionSince].compactMap(\.self).max(),
                heat: heat[session.id] ?? 0
            )
        }
        return SessionOrder.sorted(items, by: sessionSort)
    }

    /// Listede sürükleyerek yer değiştirme: gösterilen sıra elle sıra olur ve sıralama "Elle"ye geçer.
    func moveSessions(from offsets: IndexSet, to destination: Int, shown: [String]) {
        store.reorder(SessionOrder.moving(shown, from: offsets, to: destination))
        sessionSort = .manual
        saveRecords()
    }
}
