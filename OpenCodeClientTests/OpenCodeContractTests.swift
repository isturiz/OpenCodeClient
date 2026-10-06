import Foundation
import Testing

@testable import OpenCodeClient

struct OpenCodeContractTests {
    @Test func unknownContentAndMessageTypesDoNotFailTimeline() throws {
        let data = Data(
            #"""
            {"data":[
              {"id":"msg_1","type":"assistant","time":{"created":1784500000000},
               "agent":"build","model":{"id":"example-model","providerID":"example"},
               "content":[{"type":"text","text":"Hello"},
                          {"type":"future-part","text":{"new":true}}]},
              {"id":"msg_2","type":"future-message","time":{"created":1784500001000},
               "content":{"new":true}}
            ],"cursor":{}}
            """#.utf8
        )
        let response = try JSONDecoder().decode(PageDTO<MessageDTO>.self, from: data)
        let messages = response.data.map { $0.domain(sessionID: "ses_1") }

        #expect(messages.count == 2)
        #expect(messages[0].parts[0].plainText == "Hello")
        #expect(messages[0].parts[1].type == "future-part")
        #expect(messages[0].providerID == "example")
        #expect(messages[1].parts[0].type == "future-message")
        #expect(messages.allSatisfy { $0.sessionID == "ses_1" })
    }

    @Test func decodesCompletedAndFailedToolStates() throws {
        let value = try JSONDecoder().decode(
            JSONValue.self,
            from: Data(
                #"""
                {"type":"tool","id":"call_1","name":"shell",
                 "state":{"status":"completed","input":{"command":"swift test"},
                          "metadata":{"title":"Run tests"},
                          "content":[{"type":"text","text":"ok"}]}}
                """#.utf8
            )
        )
        guard case let .tool(call) = PartDTO.domain(from: value, id: "content_1") else {
            Issue.record("Expected a tool part")
            return
        }
        #expect(call.id == "call_1")
        #expect(call.status == .completed)
        #expect(call.title == "Run tests")
        #expect(call.input?["command"]?.stringValue == "swift test")
        #expect(call.output == "ok")

        let failure = try JSONDecoder().decode(
            JSONValue.self,
            from: Data(
                #"{"type":"tool","id":"call_2","name":"shell","state":{"status":"error","input":{},"error":{"type":"unknown","message":"Failed"}}}"#
                    .utf8
            )
        )
        guard case let .tool(failed) = PartDTO.domain(from: failure, id: "content_2") else {
            Issue.record("Expected a failed tool")
            return
        }
        #expect(failed.error == "Failed")
        #expect(failed.status == .error)
    }

    @Test func mapsPermissionAskedEventAndLocation() throws {
        let event = try mappedEvent(
            #"""
            {"type":"permission.asked","location":{"directory":"/tmp/project"},
             "data":{"id":"per_1","action":"shell","resources":["rm *","git reset *"],
                     "sessionID":"ses_1","source":{"type":"tool","messageID":"msg_1","id":"call_1"},
                     "message":"Run a command"}}
            """#
        )
        guard case let .permissionUpdated(permission) = event.event else {
            Issue.record("Expected a permission event")
            return
        }
        #expect(event.directory == "/tmp/project")
        #expect(permission.patterns == ["rm *", "git reset *"])
        #expect(permission.messageID == "msg_1")
        #expect(permission.type == "shell")
    }

    @Test func mapsPermissionReplyAndExecutionLifecycle() throws {
        #expect(
            try mappedEvent(
                #"{"type":"permission.replied","data":{"sessionID":"ses_1","requestID":"per_1","reply":"once"}}"#
            ).event == .permissionReplied(sessionID: "ses_1", permissionID: "per_1")
        )
        #expect(
            try mappedEvent(#"{"type":"session.execution.started","data":{"sessionID":"ses_1"}}"#).event
                == .sessionStatus(sessionID: "ses_1", status: .busy)
        )
        #expect(
            try mappedEvent(#"{"type":"session.execution.succeeded","data":{"sessionID":"ses_1"}}"#).event
                == .sessionIdle(sessionID: "ses_1")
        )
        #expect(
            try mappedEvent(#"{"type":"session.deleted","data":{"sessionID":"ses_1"}}"#).event
                == .sessionRemoved(sessionID: "ses_1")
        )
    }

    @Test func timelineDeltasRequestAuthoritativeProjection() throws {
        for type in [
            "session.text.delta", "session.reasoning.delta", "session.tool.success", "session.inbox.enqueued",
        ] {
            let json = "{\"type\":\"\(type)\",\"data\":{\"sessionID\":\"ses_1\",\"delta\":\"Hi\"}}"
            #expect(try mappedEvent(json).event == .messageChanged(sessionID: "ses_1"))
        }
    }

    @Test func mapsRetryDeadlineFromDurableEvent() throws {
        let event = try mappedEvent(
            #"{"type":"session.retry.scheduled","data":{"sessionID":"ses_1","attempt":2,"at":5000,"error":{"type":"provider","message":"Retrying"}}}"#
        )
        #expect(
            event.event
                == .sessionStatus(
                    sessionID: "ses_1",
                    status: .retry(attempt: 2, message: "Retrying", next: Date(timeIntervalSince1970: 5))
                )
        )
    }

    @Test func preservesUnknownEventTypeAndAbsentLocation() throws {
        #expect(try mappedEvent(#"{"type":"future.event","data":{}}"#).event == .unknown("future.event"))
        #expect(try mappedEvent(#"{"type":"future.event"}"#).directory == nil)
    }

    @Test func usesMillisecondsAndOptionalSessionTitle() throws {
        let dto = try JSONDecoder().decode(
            SessionDTO.self,
            from: Data(
                #"{"id":"ses_1","projectID":"project","location":{"directory":"/tmp/project"},"time":{"created":1000,"updated":2000},"model":{"id":"model","providerID":"provider","variant":"high"},"agent":"plan"}"#
                    .utf8
            )
        )
        let session = dto.domain()
        #expect(session.createdAt == Date(timeIntervalSince1970: 1))
        #expect(!session.title.isEmpty)
        #expect(session.variant == "high")
        #expect(session.agentID == "plan")
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
        #expect(parser.lastEventName == "message")
        #expect(parser.finish() == nil)
    }

    @Test func preservesStreamFailureEventNameAndLimitsFrameSize() {
        var parser = SSEParser()
        _ = parser.consume(line: "event: effect/httpapi/stream/failure")
        _ = parser.consume(line: "data: []")
        #expect(parser.consume(line: "") != nil)
        #expect(parser.lastEventName == "effect/httpapi/stream/failure")
        _ = parser.consume(line: "data: " + String(repeating: "x", count: 4 * 1_024 * 1_024))
        #expect(parser.didExceedLimit)
    }

    @Test func ignoresSSEDoneSentinel() {
        var parser = SSEParser()
        #expect(parser.consume(line: "data: [DONE]") == nil)
        #expect(parser.consume(line: "") == nil)
    }
}

private func mappedEvent(_ json: String) throws -> OpenCodeGlobalEvent {
    let envelope = try JSONDecoder().decode(EventEnvelopeDTO.self, from: Data(json.utf8))
    return OpenCodeEventMapper.domain(from: envelope)
}
