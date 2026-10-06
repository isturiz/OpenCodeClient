import Foundation

struct SSEParser: Sendable {
    private var dataLines: [String] = []
    private var eventName: String?
    private var dataByteCount = 0
    private(set) var lastEventName: String?
    private(set) var didExceedLimit = false

    mutating func consume(line: String) -> Data? {
        if line.isEmpty {
            return flush()
        }
        if line.hasPrefix(":") {
            return nil
        }
        if line.hasPrefix("event:") {
            eventName = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            return nil
        }
        guard line.hasPrefix("data:") else {
            return nil
        }

        var value = String(line.dropFirst(5))
        if value.first == " " {
            value.removeFirst()
        }
        dataByteCount += value.utf8.count + 1
        guard dataByteCount <= 4 * 1_024 * 1_024 else {
            didExceedLimit = true
            dataLines.removeAll()
            return nil
        }
        dataLines.append(value)
        return nil
    }

    mutating func finish() -> Data? {
        flush()
    }

    private mutating func flush() -> Data? {
        lastEventName = eventName
        eventName = nil
        dataByteCount = 0
        guard !dataLines.isEmpty else { return nil }
        let value = dataLines.joined(separator: "\n")
        dataLines.removeAll(keepingCapacity: true)
        guard value != "[DONE]" else { return nil }
        return Data(value.utf8)
    }
}
