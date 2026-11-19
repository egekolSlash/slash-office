import AgentOfficeCore
import Foundation

extension AppModel {
    /// Odaktaki oturumun planı, To-Do sekmesinde en son görülenden farklı (yeni adım ya da işaretlenen adım).
    var hasUnseenTodos: Bool {
        guard inspectorTab != .todo, let id = layout.focused, let todos = store.session(id)?.todos, !todos.isEmpty else { return false }
        return seenTodos[id] != todos
    }

    func markTodosSeen(_ id: String) {
        guard let todos = store.session(id)?.todos, seenTodos[id] != todos else { return }
        seenTodos[id] = todos
    }
}
