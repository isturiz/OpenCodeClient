import Foundation

// Released OpenCode V2 wire contracts, separate from presentation models.
struct DataResponseDTO<Value: Decodable & Sendable>: Decodable, Sendable {
    let data: Value
}

struct PageDTO<Value: Decodable & Sendable>: Decodable, Sendable {
    struct Cursor: Decodable, Sendable {
        let previous: String?
        let next: String?
    }

    let data: [Value]
    let cursor: Cursor
}

struct HealthDTO: Decodable, Sendable {
    let version: String
}

struct LocationDTO: Codable, Sendable {
    let directory: String?
}

struct ModelReferenceDTO: Codable, Sendable {
    let id: String
    let providerID: String
    let variant: String?
}

struct ProjectDTO: Decodable, Sendable {
    let id: String
    let canonical: String
    let vcs: String?

    func domain() -> OpenCodeProject {
        OpenCodeProject(id: id, worktree: canonical, vcs: vcs)
    }
}

struct SessionDTO: Decodable, Sendable {
    struct TimeDTO: Decodable, Sendable {
        let created: Double
        let updated: Double
    }

    let id: String
    let projectID: String
    let location: LocationDTO
    let parentID: String?
    let title: String?
    let time: TimeDTO
    let agent: String?
    let model: ModelReferenceDTO?

    func domain() -> OpenCodeSession {
        OpenCodeSession(
            id: id,
            projectID: projectID,
            directory: location.directory ?? "",
            parentID: parentID,
            title: title ?? String(localized: "New Chat"),
            version: "",
            createdAt: Self.date(from: time.created),
            updatedAt: Self.date(from: time.updated),
            summary: nil,
            agentID: agent,
            providerID: model?.providerID,
            modelID: model?.id,
            variant: model?.variant
        )
    }

    static func date(from timestamp: Double) -> Date {
        // V2 wire timestamps are always epoch milliseconds, including small fixture values.
        Date(timeIntervalSince1970: timestamp / 1_000)
    }
}

struct SessionUpdateDTO: Encodable, Sendable {
    let title: String
}

struct FileDiffDTO: Decodable, Sendable {
    let file: String
    let status: String
    let additions: Int
    let deletions: Int
    let patch: String

    func domain() -> OpenCodeFileDiff {
        let domainStatus: OpenCodeFileDiffStatus
        switch status {
        case "added": domainStatus = .added
        case "modified": domainStatus = .modified
        case "deleted": domainStatus = .deleted
        default: domainStatus = .unknown(status)
        }
        return OpenCodeFileDiff(
            path: file, status: domainStatus, additions: additions, deletions: deletions,
            patch: patch, before: nil, after: nil
        )
    }
}

struct FileNodeDTO: Decodable, Sendable {
    let path: String
    let type: String

    func domain() -> OpenCodeFileNode {
        let domainType: OpenCodeFileNodeType
        switch type {
        case "file": domainType = .file
        case "directory": domainType = .directory
        default: domainType = .unknown(type)
        }
        return OpenCodeFileNode(
            name: URL(fileURLWithPath: path).lastPathComponent,
            path: path, absolutePath: nil, type: domainType, isIgnored: false
        )
    }
}

struct SessionStatusDTO: Decodable, Sendable {
    let type: String
    let attempt: Int?
    let message: String?
    let next: Double?

    func domain() -> OpenCodeSessionStatus {
        switch type {
        case "idle": .idle
        case "busy", "running": .busy
        case "retry":
            .retry(attempt: attempt ?? 0, message: message ?? "", next: next.map(SessionDTO.date(from:)))
        default: .unknown(type)
        }
    }
}

struct MessageDTO: Decodable, Sendable {
    struct TimeDTO: Decodable, Sendable {
        let created: Double
        let completed: Double?
    }

    let id: String
    let type: String
    let time: TimeDTO
    private let value: JSONValue

    private enum CodingKeys: String, CodingKey {
        case id, type, time
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        time = try container.decode(TimeDTO.self, forKey: .time)
        value = try JSONValue(from: decoder)
    }

    func domain(sessionID: String) -> ChatMessage {
        let parts: [MessagePart]
        switch type {
        case "assistant":
            parts = (value["content"]?.arrayValue ?? []).enumerated().map { index, part in
                PartDTO.domain(from: part, id: "\(id)-content-\(index)")
            }
        case "user", "synthetic", "system", "skill":
            var content: [MessagePart] = [
                .text(id: "\(id)-text", text: value["text"]?.stringValue ?? "", synthetic: type != "user")
            ]
            for (index, file) in (value["files"]?.arrayValue ?? []).enumerated() {
                let mime = file["mime"]?.stringValue ?? "application/octet-stream"
                content.append(
                    .file(
                        id: "\(id)-file-\(index)", filename: file["name"]?.stringValue, mime: mime,
                        url: "data:\(mime);base64,\(file["data"]?.stringValue ?? "")"
                    )
                )
            }
            parts = content
        case "shell":
            parts = [
                .tool(
                    ToolCall(
                        id: id, callID: value["shellID"]?.stringValue ?? id, tool: "shell",
                        status: value["status"]?.stringValue == "running" ? .running : .completed,
                        title: value["command"]?.stringValue, input: nil,
                        output: value["output"]?["output"]?.stringValue, error: nil
                    )
                )
            ]
        case "compaction":
            parts = [.text(id: "\(id)-text", text: value["summary"]?.stringValue ?? "", synthetic: true)]
        default:
            parts = [.unknown(id: id, type: type)]
        }
        return ChatMessage(
            id: id, sessionID: sessionID,
            role: type == "user" ? .user : (type == "assistant" ? .assistant : .unknown),
            createdAt: SessionDTO.date(from: time.created),
            completedAt: time.completed.map(SessionDTO.date(from:)),
            providerID: value["model"]?["providerID"]?.stringValue,
            modelID: value["model"]?["id"]?.stringValue,
            errorMessage: value["error"]?["message"]?.stringValue, parts: parts
        )
    }
}

enum PartDTO {
    static func domain(from value: JSONValue, id: String) -> MessagePart {
        let type = value["type"]?.stringValue ?? "unknown"
        switch type {
        case "text": return .text(id: id, text: value["text"]?.stringValue ?? "", synthetic: false)
        case "reasoning": return .reasoning(id: id, text: value["text"]?.stringValue ?? "")
        case "tool":
            let state = value["state"]
            let status = state?["status"]?.stringValue ?? "unknown"
            return .tool(
                ToolCall(
                    id: value["id"]?.stringValue ?? id, callID: value["id"]?.stringValue ?? id,
                    tool: value["name"]?.stringValue ?? String(localized: "Tool"),
                    status: status == "streaming" ? .pending : (ToolCallStatus(rawValue: status) ?? .unknown),
                    title: state?["metadata"]?["title"]?.stringValue, input: state?["input"],
                    output: state?["content"]?.arrayValue?.compactMap { $0["text"]?.stringValue }
                        .joined(separator: "\n"),
                    error: state?["error"]?["message"]?.stringValue
                )
            )
        default: return .unknown(id: id, type: type)
        }
    }
}

struct PermissionDTO: Decodable, Sendable {
    struct Source: Decodable, Sendable {
        let messageID: String?
    }

    let id: String
    let sessionID: String
    let action: String
    let resources: [String]
    let source: Source?
    let message: String?

    func domain() -> PermissionRequest {
        PermissionRequest(
            id: id, sessionID: sessionID, messageID: source?.messageID ?? "",
            type: action, title: message ?? action, patterns: resources
        )
    }
}

struct ModelDTO: Decodable, Sendable {
    struct Variant: Decodable, Sendable {
        let id: String
    }

    let id: String
    let providerID: String
    let name: String
    let enabled: Bool
    let variants: [Variant]

    func domain() -> [ModelOption] {
        let base = ModelOption(
            providerID: providerID, modelID: id, providerName: providerID, name: name, isConnected: enabled
        )
        return [base]
            + variants.map {
                ModelOption(
                    providerID: providerID, modelID: id, providerName: providerID,
                    name: "\(name) · \($0.id)", isConnected: enabled, variant: $0.id
                )
            }
    }
}

struct AgentDTO: Decodable, Sendable {
    let id: String
    let name: String
    let description: String?
    let mode: String
    let hidden: Bool

    func domain() -> AgentOption {
        AgentOption(name: name, description: description, mode: mode, isBuiltIn: false, agentID: id)
    }
}

struct EventEnvelopeDTO: Decodable, Sendable {
    let type: String
    let location: LocationDTO?
    let data: JSONValue?
}

struct PromptBodyDTO: Encodable, Sendable {
    let id: String
    let text: String
}
