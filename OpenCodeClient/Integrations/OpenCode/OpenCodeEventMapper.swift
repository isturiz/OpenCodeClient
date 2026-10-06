import Foundation

enum OpenCodeEventMapper {
    static func domain(from envelope: EventEnvelopeDTO) -> OpenCodeGlobalEvent {
        let data = envelope.data
        let sessionID = data?["sessionID"]?.stringValue
        let event: OpenCodeEvent

        switch envelope.type {
        case "server.connected":
            event = .connected
        case "session.status":
            if let sessionID, let status = decode(SessionStatusDTO.self, from: data?["status"]) {
                event = .sessionStatus(sessionID: sessionID, status: status.domain())
            } else {
                event = .unknown(envelope.type)
            }
        case "session.execution.started":
            event = sessionID.map { .sessionStatus(sessionID: $0, status: .busy) } ?? .unknown(envelope.type)
        case "session.retry.scheduled":
            if let sessionID {
                event = .sessionStatus(
                    sessionID: sessionID,
                    status: .retry(
                        attempt: Int(exactly: data?["attempt"]?.doubleValue ?? 0) ?? 0,
                        message: data?["error"]?["message"]?.stringValue ?? "",
                        next: data?["at"]?.doubleValue.map(SessionDTO.date(from:))
                    )
                )
            } else {
                event = .unknown(envelope.type)
            }
        case "session.idle", "session.execution.succeeded", "session.execution.interrupted":
            event = sessionID.map { .sessionIdle(sessionID: $0) } ?? .unknown(envelope.type)
        case "session.execution.failed":
            event = .sessionError(sessionID: sessionID, message: data?["error"]?["message"]?.stringValue)
        case "session.deleted":
            event = sessionID.map { .sessionRemoved(sessionID: $0) } ?? .unknown(envelope.type)
        case "session.created", "session.renamed", "session.moved", "session.agent.selected",
            "session.model.selected":
            event = sessionID.map { .sessionChanged(sessionID: $0) } ?? .unknown(envelope.type)
        case "permission.asked":
            event =
                decode(PermissionDTO.self, from: data).map { .permissionUpdated($0.domain()) }
                ?? .unknown(envelope.type)
        case "permission.replied":
            if let sessionID, let requestID = data?["requestID"]?.stringValue {
                event = .permissionReplied(sessionID: sessionID, permissionID: requestID)
            } else {
                event = .unknown(envelope.type)
            }
        default:
            // The V2 timeline is a projection, not V1 message-part patches. Coalesced
            // reads keep partial text and tool state authoritative without guessing ordinals.
            let timelinePrefixes = [
                "session.text.", "session.reasoning.", "session.tool.", "session.step.",
                "session.inbox.", "session.compaction.", "session.retry.", "session.revert.",
                "session.shell.", "session.skill.", "session.synthetic", "session.forked",
            ]
            if let sessionID, timelinePrefixes.contains(where: { envelope.type.hasPrefix($0) }) {
                event = .messageChanged(sessionID: sessionID)
            } else {
                event = .unknown(envelope.type)
            }
        }

        return OpenCodeGlobalEvent(directory: envelope.location?.directory, event: event)
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, from value: JSONValue?) -> Value? {
        guard let value, let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
