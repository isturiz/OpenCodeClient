import Foundation

struct ProjectSection: Identifiable, Sendable {
    let project: OpenCodeProject
    var sessions: [OpenCodeSession]

    var id: String { project.id }
}

struct SessionRoute: Hashable, Identifiable, Sendable {
    let profileID: UUID
    let project: OpenCodeProject
    let session: OpenCodeSession

    var id: String { "\(profileID.uuidString):\(session.id)" }
}
