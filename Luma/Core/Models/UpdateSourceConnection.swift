import Foundation

nonisolated enum UpdateSourceConnectionState: String, Equatable, Sendable {
    case connected
    case signInRequired
}

nonisolated struct UpdateSourceConnection: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let state: UpdateSourceConnectionState

    init(
        id: String,
        name: String,
        state: UpdateSourceConnectionState
    ) {
        self.id = id
        self.name = name
        self.state = state
    }
}
