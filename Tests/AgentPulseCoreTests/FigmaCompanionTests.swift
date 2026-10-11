import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct FigmaCompanionTests {
    func message(_ json: String) -> Data {
        Data(json.utf8)
    }

    @Test func burstBecomesAIDrawing() throws {
        guard case .events(let events) = FigmaCompanion.parse(message(#"{"v":1,"file":"Лендинг","kind":"activity","state":"generating"}"#)) else {
            Issue.record("ожидали события"); return
        }
        var table = SessionTable()
        events.forEach { table.apply($0) }
        let session = try #require(table.sessions["figma-Лендинг"])
        guard case .working(let activity) = session.phase else { Issue.record("ожидали working"); return }
        #expect(activity.target == .figma)
        #expect(activity.text == "Генерирует макет")
        #expect(session.source == .figmaAI)
        #expect(session.context == "Лендинг")

        guard case .events(let done) = FigmaCompanion.parse(message(#"{"v":1,"file":"Лендинг","kind":"activity","state":"idle"}"#)) else {
            Issue.record("ожидали события"); return
        }
        done.forEach { table.apply($0) }
        #expect(table.sessions["figma-Лендинг"]?.phase == .done(summary: "Готово"))
    }

    @Test func frameMustBePNG() {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]).base64EncodedString()
        guard case .frame(let frame) = FigmaCompanion.parse(message(#"{"v":1,"file":"F","kind":"frame","node":"Hero","png":"\#(png)"}"#)) else {
            Issue.record("ожидали кадр"); return
        }
        #expect(frame.node == "Hero")
        let gif = Data("GIF89a".utf8).base64EncodedString()
        #expect(FigmaCompanion.parse(message(#"{"v":1,"kind":"frame","png":"\#(gif)"}"#)) == nil)
    }

    @Test func changeAndGarbage() {
        #expect(FigmaCompanion.parse(message(#"{"v":1,"kind":"change"}"#)) == .change)
        #expect(FigmaCompanion.parse(message(#"{"v":2,"kind":"change"}"#)) == nil)
        #expect(FigmaCompanion.parse(message("nope")) == nil)
        #expect(String(decoding: FigmaCompanion.reply(mirror: true), as: UTF8.self) == #"{"mirror":true}"#)
    }

    @Test func httpParsing() {
        let raw = Data("POST /figma HTTP/1.1\r\nHost: localhost\r\nContent-Length: 4\r\n\r\nbody".utf8)
        guard case .complete(let request) = LocalHTTPServer.parse(raw) else { Issue.record("ожидали запрос"); return }
        #expect(request.method == "POST")
        #expect(request.path == "/figma")
        #expect(request.body == Data("body".utf8))

        guard case .incomplete = LocalHTTPServer.parse(Data("POST /figma HTTP/1.1\r\nContent-Length: 10\r\n\r\nbody".utf8)) else {
            Issue.record("ожидали неполный"); return
        }
    }
}

@Suite struct LocalHTTPServerTests {
    @Test func servesLoopbackWithCORS() async throws {
        let port = UInt16.random(in: 49_200...49_900)
        let server = LocalHTTPServer(port: port) { request in
            LocalHTTPServer.Response(body: Data(#"{"echo":\#(request.body.count)}"#.utf8))
        }
        try server.start()
        defer { server.stop() }
        try await Task.sleep(for: .milliseconds(200))

        var request = URLRequest(url: URL(string: "http://localhost:\(port)/figma")!)
        request.httpMethod = "POST"
        request.httpBody = Data(#"{"v":1}"#.utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 200)
        #expect(http.value(forHTTPHeaderField: "Access-Control-Allow-Origin") == "*")
        #expect(String(decoding: data, as: UTF8.self) == #"{"echo":7}"#)
    }
}
