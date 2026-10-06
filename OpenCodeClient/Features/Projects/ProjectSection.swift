import Foundation

struct ProjectSection: Identifiable, Sendable {
    let project: OpenCodeProject
    var sessions: [OpenCodeSession]

    var id: String { project.id }
}

struct SessionListItem: Identifiable, Sendable {
    let project: OpenCodeProject
    let session: OpenCodeSession

    var id: String { "\(project.id):\(session.id)" }
}

enum SessionChronologyBucket: Int, CaseIterable, Identifiable, Sendable {
    case today
    case yesterday
    case previousSevenDays
    case earlier

    var id: Int { rawValue }
}

struct SessionChronologySection: Identifiable, Sendable {
    let bucket: SessionChronologyBucket
    var items: [SessionListItem]

    var id: SessionChronologyBucket { bucket }
}

struct ProjectChronologySection: Identifiable, Sendable {
    let project: OpenCodeProject
    var pinned: [SessionListItem]
    var chronology: [SessionChronologySection]

    var id: String { project.id }
}

struct SessionRoute: Hashable, Identifiable, Sendable {
    let profileID: UUID
    let project: OpenCodeProject
    let session: OpenCodeSession

    var id: String { "\(profileID.uuidString):\(session.id)" }
}

struct NewChatRoute: Hashable, Sendable {
    let profileID: UUID?
    let project: OpenCodeProject?
}

struct ConversationRoute: Hashable, Identifiable, Sendable {
    enum Destination: Hashable, Sendable {
        case session(SessionRoute)
        case newChat(NewChatRoute)
    }

    let id: UUID
    var destination: Destination

    init(id: UUID = UUID(), destination: Destination) {
        self.id = id
        self.destination = destination
    }

    var profileID: UUID? {
        switch destination {
        case let .session(route):
            route.profileID
        case let .newChat(route):
            route.profileID
        }
    }
}
