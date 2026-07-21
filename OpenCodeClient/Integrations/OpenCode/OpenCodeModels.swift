import Foundation

struct OpenCodeHealth: Equatable, Sendable {
    let isHealthy: Bool
    let version: String
}

struct OpenCodeProject: Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let worktree: String
    let vcs: String?

    var name: String {
        let value = URL(fileURLWithPath: worktree).lastPathComponent
        return value.isEmpty ? worktree : value
    }
}

struct OpenCodeSession: Equatable, Hashable, Identifiable, Sendable {
    struct Summary: Equatable, Hashable, Sendable {
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
    let createdAt: Date
    let updatedAt: Date
    let summary: Summary?
}

enum OpenCodeSessionStatus: Equatable, Sendable {
    case idle
    case busy
    case retry(attempt: Int, message: String, next: Date?)
    case unknown(String)

    var isBusy: Bool {
        switch self {
        case .busy, .retry:
            true
        default:
            false
        }
    }
}

enum ChatRole: String, Equatable, Sendable {
    case user
    case assistant
    case unknown
}

enum ToolCallStatus: String, Equatable, Sendable {
    case pending
    case running
    case completed
    case error
    case unknown
}

struct ToolCall: Equatable, Identifiable, Sendable {
    let id: String
    let callID: String
    let tool: String
    let status: ToolCallStatus
    let title: String?
    let input: JSONValue?
    let output: String?
    let error: String?
}

enum MessagePart: Equatable, Identifiable, Sendable {
    case text(id: String, text: String, synthetic: Bool)
    case reasoning(id: String, text: String)
    case tool(ToolCall)
    case file(id: String, filename: String?, mime: String, url: String)
    case patch(id: String, files: [String])
    case unknown(id: String, type: String)

    var id: String {
        switch self {
        case let .text(id, _, _), let .reasoning(id, _), let .file(id, _, _, _),
            let .patch(id, _), let .unknown(id, _):
            id
        case let .tool(call):
            call.id
        }
    }

    var type: String {
        switch self {
        case .text: "text"
        case .reasoning: "reasoning"
        case .tool: "tool"
        case .file: "file"
        case .patch: "patch"
        case let .unknown(_, type): type
        }
    }

    var plainText: String? {
        switch self {
        case let .text(_, text, _), let .reasoning(_, text):
            text
        default:
            nil
        }
    }
}

struct ChatMessage: Equatable, Identifiable, Sendable {
    let id: String
    let sessionID: String
    let role: ChatRole
    let createdAt: Date
    let completedAt: Date?
    let providerID: String?
    let modelID: String?
    let errorMessage: String?
    var parts: [MessagePart]
}

struct PermissionRequest: Equatable, Identifiable, Sendable {
    let id: String
    let sessionID: String
    let messageID: String
    let type: String
    let title: String
    let patterns: [String]
}

enum PermissionResponse: String, Encodable, Sendable {
    case once
    case always
    case reject
}

struct ModelOption: Equatable, Hashable, Identifiable, Sendable {
    let providerID: String
    let modelID: String
    let providerName: String
    let name: String
    let isConnected: Bool

    var id: String { "\(providerID)/\(modelID)" }
}

struct AgentOption: Equatable, Hashable, Identifiable, Sendable {
    let name: String
    let description: String?
    let mode: String
    let isBuiltIn: Bool

    var id: String { name }
}

enum OpenCodeEvent: Equatable, Sendable {
    case connected
    case sessionCreated(OpenCodeSession)
    case sessionUpdated(OpenCodeSession)
    case sessionDeleted(OpenCodeSession)
    case sessionStatus(sessionID: String, status: OpenCodeSessionStatus)
    case sessionIdle(sessionID: String)
    case messageChanged(sessionID: String)
    case partUpdated(sessionID: String, messageID: String, part: MessagePart, delta: String?)
    case partRemoved(sessionID: String, messageID: String, partID: String)
    case permissionUpdated(PermissionRequest)
    case permissionReplied(sessionID: String, permissionID: String)
    case sessionError(sessionID: String?, message: String?)
    case unknown(String)
}

struct OpenCodeGlobalEvent: Equatable, Sendable {
    let directory: String?
    let event: OpenCodeEvent
}
