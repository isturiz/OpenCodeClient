import Foundation

enum OpenCodeEventMapper {
    static func domain(from envelope: EventEnvelopeDTO) -> OpenCodeGlobalEvent {
        let properties = envelope.payload.properties
        let event: OpenCodeEvent

        switch envelope.payload.type {
        case "server.connected":
            event = .connected
        case "session.created":
            event = sessionEvent({ .sessionCreated($0) }, properties: properties)
        case "session.updated":
            event = sessionEvent({ .sessionUpdated($0) }, properties: properties)
        case "session.deleted":
            event = sessionEvent({ .sessionDeleted($0) }, properties: properties)
        case "session.status":
            if let sessionID = properties["sessionID"]?.stringValue,
                let status = decode(SessionStatusDTO.self, from: properties["status"])
            {
                event = .sessionStatus(sessionID: sessionID, status: status.domain())
            } else {
                event = .unknown(envelope.payload.type)
            }
        case "session.idle":
            if let sessionID = properties["sessionID"]?.stringValue {
                event = .sessionIdle(sessionID: sessionID)
            } else {
                event = .unknown(envelope.payload.type)
            }
        case "message.updated":
            if let info = decode(MessageDTO.self, from: properties["info"]) {
                event = .messageChanged(sessionID: info.sessionID)
            } else {
                event = .unknown(envelope.payload.type)
            }
        case "message.part.updated":
            if let part = decode(PartDTO.self, from: properties["part"]) {
                event = .partUpdated(
                    sessionID: part.sessionID,
                    messageID: part.messageID,
                    part: part.domain(),
                    delta: properties["delta"]?.stringValue
                )
            } else {
                event = .unknown(envelope.payload.type)
            }
        case "message.part.removed":
            if let sessionID = properties["sessionID"]?.stringValue,
                let messageID = properties["messageID"]?.stringValue,
                let partID = properties["partID"]?.stringValue
            {
                event = .partRemoved(sessionID: sessionID, messageID: messageID, partID: partID)
            } else {
                event = .unknown(envelope.payload.type)
            }
        case "permission.updated":
            if let permission = decode(PermissionDTO.self, from: properties) {
                event = .permissionUpdated(permission.domain())
            } else {
                event = .unknown(envelope.payload.type)
            }
        case "permission.replied":
            if let sessionID = properties["sessionID"]?.stringValue,
                let permissionID = properties["permissionID"]?.stringValue
            {
                event = .permissionReplied(sessionID: sessionID, permissionID: permissionID)
            } else {
                event = .unknown(envelope.payload.type)
            }
        case "session.error":
            let message =
                properties["error"]?["data"]?["message"]?.stringValue
                ?? properties["error"]?["message"]?.stringValue
            event = .sessionError(sessionID: properties["sessionID"]?.stringValue, message: message)
        default:
            event = .unknown(envelope.payload.type)
        }

        return OpenCodeGlobalEvent(directory: envelope.directory, event: event)
    }

    private static func sessionEvent(
        _ constructor: (OpenCodeSession) -> OpenCodeEvent,
        properties: JSONValue
    ) -> OpenCodeEvent {
        guard let session = decode(SessionDTO.self, from: properties["info"]) else {
            return .unknown("session")
        }
        return constructor(session.domain())
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, from value: JSONValue?) -> Value? {
        guard let value, let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
