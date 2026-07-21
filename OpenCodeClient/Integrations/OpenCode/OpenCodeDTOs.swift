import Foundation

struct HealthDTO: Decodable, Sendable {
    let healthy: Bool
    let version: String
}

struct ProjectDTO: Decodable, Sendable {
    let id: String
    let worktree: String
    let vcs: String?

    func domain() -> OpenCodeProject {
        OpenCodeProject(id: id, worktree: worktree, vcs: vcs)
    }
}

struct SessionDTO: Decodable, Sendable {
    struct TimeDTO: Decodable, Sendable {
        let created: Double
        let updated: Double
    }

    struct SummaryDTO: Decodable, Sendable {
        let additions: Int
        let deletions: Int
        let files: Int
    }

    let id: String
    let projectID: String
    let directory: String
    let parentID: String?
    let title: String
    let version: String
    let time: TimeDTO
    let summary: SummaryDTO?

    func domain() -> OpenCodeSession {
        OpenCodeSession(
            id: id,
            projectID: projectID,
            directory: directory,
            parentID: parentID,
            title: title,
            version: version,
            createdAt: Self.date(from: time.created),
            updatedAt: Self.date(from: time.updated),
            summary: summary.map {
                .init(additions: $0.additions, deletions: $0.deletions, files: $0.files)
            }
        )
    }

    static func date(from timestamp: Double) -> Date {
        let seconds = timestamp > 10_000_000_000 ? timestamp / 1_000 : timestamp
        return Date(timeIntervalSince1970: seconds)
    }
}

struct SessionStatusDTO: Decodable, Sendable {
    let type: String
    let attempt: Int?
    let message: String?
    let next: Double?

    func domain() -> OpenCodeSessionStatus {
        switch type {
        case "idle":
            return .idle
        case "busy":
            return .busy
        case "retry":
            return .retry(
                attempt: attempt ?? 0,
                message: message ?? "",
                next: next.map(SessionDTO.date(from:))
            )
        default:
            return .unknown(type)
        }
    }
}

struct MessageEnvelopeDTO: Decodable, Sendable {
    let info: MessageDTO
    let parts: [PartDTO]

    func domain() -> ChatMessage {
        info.domain(parts: parts.map { $0.domain() })
    }
}

struct MessageDTO: Decodable, Sendable {
    struct TimeDTO: Decodable, Sendable {
        let created: Double
        let completed: Double?
    }

    struct ModelDTO: Decodable, Sendable {
        let providerID: String
        let modelID: String
    }

    let id: String
    let sessionID: String
    let role: String
    let time: TimeDTO
    let providerID: String?
    let modelID: String?
    let model: ModelDTO?
    let error: JSONValue?

    func domain(parts: [MessagePart]) -> ChatMessage {
        let errorMessage =
            error?["data"]?["message"]?.stringValue
            ?? error?["message"]?.stringValue
            ?? error?["name"]?.stringValue

        return ChatMessage(
            id: id,
            sessionID: sessionID,
            role: ChatRole(rawValue: role) ?? .unknown,
            createdAt: SessionDTO.date(from: time.created),
            completedAt: time.completed.map(SessionDTO.date(from:)),
            providerID: providerID ?? model?.providerID,
            modelID: modelID ?? model?.modelID,
            errorMessage: errorMessage,
            parts: parts
        )
    }
}

struct PartDTO: Decodable, Sendable {
    struct ToolStateDTO: Decodable, Sendable {
        let status: String
        let input: JSONValue?
        let title: String?
        let output: String?
        let error: String?
    }

    let id: String
    let sessionID: String
    let messageID: String
    let type: String
    let text: String?
    let synthetic: Bool?
    let tool: String?
    let callID: String?
    let state: ToolStateDTO?
    let filename: String?
    let mime: String?
    let url: String?
    let files: [String]?

    private enum CodingKeys: String, CodingKey {
        case id
        case sessionID
        case messageID
        case type
        case text
        case synthetic
        case tool
        case callID
        case state
        case filename
        case mime
        case url
        case files
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID) ?? ""
        messageID = try container.decodeIfPresent(String.self, forKey: .messageID) ?? ""
        id =
            try container.decodeIfPresent(String.self, forKey: .id)
            ?? "\(messageID)-\(type)-unknown"
        text = try container.decodeIfPresent(String.self, forKey: .text)
        synthetic = try container.decodeIfPresent(Bool.self, forKey: .synthetic)
        tool = try container.decodeIfPresent(String.self, forKey: .tool)
        callID = try container.decodeIfPresent(String.self, forKey: .callID)
        state = try container.decodeIfPresent(ToolStateDTO.self, forKey: .state)
        filename = try container.decodeIfPresent(String.self, forKey: .filename)
        mime = try container.decodeIfPresent(String.self, forKey: .mime)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        files = try container.decodeIfPresent([String].self, forKey: .files)
    }

    func domain() -> MessagePart {
        switch type {
        case "text":
            return .text(id: id, text: text ?? "", synthetic: synthetic ?? false)
        case "reasoning":
            return .reasoning(id: id, text: text ?? "")
        case "tool":
            let rawStatus = state?.status ?? "unknown"
            return .tool(
                ToolCall(
                    id: id,
                    callID: callID ?? id,
                    tool: tool ?? String(localized: "Tool"),
                    status: ToolCallStatus(rawValue: rawStatus) ?? .unknown,
                    title: state?.title,
                    input: state?.input,
                    output: state?.output,
                    error: state?.error
                )
            )
        case "file":
            return .file(id: id, filename: filename, mime: mime ?? "application/octet-stream", url: url ?? "")
        case "patch":
            return .patch(id: id, files: files ?? [])
        default:
            return .unknown(id: id, type: type)
        }
    }
}

struct PermissionDTO: Decodable, Sendable {
    let id: String
    let type: String
    let pattern: JSONValue?
    let sessionID: String
    let messageID: String
    let title: String

    func domain() -> PermissionRequest {
        let patterns: [String]
        switch pattern {
        case let .string(value):
            patterns = [value]
        case let .array(values):
            patterns = values.compactMap(\.stringValue)
        default:
            patterns = []
        }

        return PermissionRequest(
            id: id,
            sessionID: sessionID,
            messageID: messageID,
            type: type,
            title: title,
            patterns: patterns
        )
    }
}

struct ProviderResponseDTO: Decodable, Sendable {
    struct ProviderDTO: Decodable, Sendable {
        struct ModelDTO: Decodable, Sendable {
            let id: String?
            let name: String?
        }

        let id: String
        let name: String
        let models: [String: ModelDTO]
    }

    let all: [ProviderDTO]
    let connected: [String]

    func domain() -> [ModelOption] {
        let connectedSet = Set(connected)
        return all.flatMap { provider in
            provider.models.map { key, model in
                ModelOption(
                    providerID: provider.id,
                    modelID: model.id ?? key,
                    providerName: provider.name,
                    name: model.name ?? model.id ?? key,
                    isConnected: connectedSet.contains(provider.id)
                )
            }
        }
        .sorted {
            if $0.isConnected != $1.isConnected { return $0.isConnected }
            if $0.providerName != $1.providerName { return $0.providerName < $1.providerName }
            return $0.name < $1.name
        }
    }
}

struct AgentDTO: Decodable, Sendable {
    let name: String
    let description: String?
    let mode: String
    let builtIn: Bool

    func domain() -> AgentOption {
        AgentOption(name: name, description: description, mode: mode, isBuiltIn: builtIn)
    }
}

struct EventEnvelopeDTO: Decodable, Sendable {
    struct PayloadDTO: Decodable, Sendable {
        let type: String
        let properties: JSONValue
    }

    let directory: String?
    let payload: PayloadDTO
}

struct PromptBodyDTO: Encodable, Sendable {
    struct TextPart: Encodable, Sendable {
        let type = "text"
        let text: String
    }

    struct Model: Encodable, Sendable {
        let providerID: String
        let modelID: String
    }

    let model: Model?
    let agent: String?
    let parts: [TextPart]
}
