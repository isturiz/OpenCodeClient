import Foundation
import Testing

@testable import OpenCodeClient

struct OpenCodeContractTests {
    @Test func unknownPartDoesNotFailWholeMessage() throws {
        let data = Data(
            #"""
            [{
              "info": {
                "id": "msg_1",
                "sessionID": "ses_1",
                "role": "assistant",
                "time": {"created": 1784500000000},
                "providerID": "openai",
                "modelID": "gpt-5.6-sol"
              },
              "parts": [
                {
                  "id": "part_1",
                  "sessionID": "ses_1",
                  "messageID": "msg_1",
                  "type": "text",
                  "text": "Hello"
                },
                {
                  "id": "part_2",
                  "sessionID": "ses_1",
                  "messageID": "msg_1",
                  "type": "future-part",
                  "payload": {"new": true}
                }
              ]
            }]
            """#.utf8
        )

        let envelopes = try JSONDecoder().decode([MessageEnvelopeDTO].self, from: data)
        let messages = envelopes.map { $0.domain() }

        #expect(messages.count == 1)
        #expect(messages[0].parts.count == 2)
        #expect(messages[0].parts[0].plainText == "Hello")
        #expect(messages[0].parts[1].type == "future-part")
        #expect(messages[0].providerID == "openai")
    }

    @Test func decodesCompletedToolState() throws {
        let data = Data(
            #"""
            {
              "id": "part_tool",
              "sessionID": "ses_1",
              "messageID": "msg_1",
              "type": "tool",
              "callID": "call_1",
              "tool": "bash",
              "state": {
                "status": "completed",
                "input": {"command": "swift test"},
                "title": "Run tests",
                "output": "ok",
                "metadata": {},
                "time": {"start": 1, "end": 2}
              }
            }
            """#.utf8
        )
        let part = try JSONDecoder().decode(PartDTO.self, from: data).domain()

        guard case let .tool(call) = part else {
            Issue.record("Expected a tool part")
            return
        }
        #expect(call.status == .completed)
        #expect(call.title == "Run tests")
        #expect(call.input?["command"]?.stringValue == "swift test")
        #expect(call.output == "ok")
    }

    @Test func mapsPermissionUpdatedEvent() throws {
        let data = Data(
            #"""
            {
              "directory": "/tmp/project",
              "payload": {
                "type": "permission.updated",
                "properties": {
                  "id": "perm_1",
                  "type": "bash",
                  "pattern": ["rm *", "git reset *"],
                  "sessionID": "ses_1",
                  "messageID": "msg_1",
                  "title": "Run a command",
                  "metadata": {},
                  "time": {"created": 1}
                }
              }
            }
            """#.utf8
        )
        let envelope = try JSONDecoder().decode(EventEnvelopeDTO.self, from: data)
        let globalEvent = OpenCodeEventMapper.domain(from: envelope)

        guard case let .permissionUpdated(permission) = globalEvent.event else {
            Issue.record("Expected a permission event")
            return
        }
        #expect(globalEvent.directory == "/tmp/project")
        #expect(permission.patterns == ["rm *", "git reset *"])
        #expect(permission.sessionID == "ses_1")
    }

    @Test func preservesUnknownEventType() throws {
        let data = Data(
            #"{"directory":"/tmp/project","payload":{"type":"future.event","properties":{}}}"#.utf8
        )
        let envelope = try JSONDecoder().decode(EventEnvelopeDTO.self, from: data)

        #expect(OpenCodeEventMapper.domain(from: envelope).event == .unknown("future.event"))
    }

    @Test func parsesFragmentedSSEDataLines() throws {
        var parser = SSEParser()

        #expect(parser.consume(line: ": keep-alive") == nil)
        #expect(parser.consume(line: "event: message") == nil)
        #expect(parser.consume(line: "data: {\"hello\":") == nil)
        #expect(parser.consume(line: "data: \"world\"}") == nil)
        let flushed = parser.consume(line: "")
        let data = try #require(flushed)

        #expect(String(decoding: data, as: UTF8.self) == "{\"hello\":\n\"world\"}")
        #expect(parser.finish() == nil)
    }

    @Test func ignoresSSEDoneSentinel() {
        var parser = SSEParser()

        #expect(parser.consume(line: "data: [DONE]") == nil)
        #expect(parser.consume(line: "") == nil)
    }
}
