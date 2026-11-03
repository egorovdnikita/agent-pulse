import Foundation
import Network

/// Крошечный HTTP-сервер только на loopback — для плагина Figma: из песочницы плагина доступен лишь `localhost`.
/// Одно соединение = один запрос. Соединения не с loopback-адреса сбрасываются.
/// Из браузера принимается только origin `null` (iframe плагина Figma): обычный сайт не может подделать событие.
public final class LocalHTTPServer: @unchecked Sendable {
    public struct Request: Sendable {
        public var method: String
        public var path: String
        public var body: Data
        /// Заголовок `Origin`, если браузер его прислал.
        public var origin: String? = nil
    }

    public struct Response: Sendable {
        public var status: Int
        public var body: Data

        public init(status: Int = 200, body: Data = Data()) {
            self.status = status
            self.body = body
        }
    }

    public typealias Handler = @Sendable (Request) -> Response

    public static let defaultPort: UInt16 = 47811
    public static let maxBodyBytes = 4 << 20

    private let port: UInt16
    private let handler: Handler
    private let queue = DispatchQueue(label: "agentpulse.http")
    private var listener: NWListener?

    public init(port: UInt16 = LocalHTTPServer.defaultPort, handler: @escaping Handler) {
        self.port = port
        self.handler = handler
    }

    public func start() throws {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let listener = try NWListener(using: parameters, on: nwPort)
        let handler = handler
        listener.newConnectionHandler = { connection in
            guard Self.isLoopback(connection.endpoint) else {
                connection.cancel()
                return
            }
            Self.serve(connection, handler: handler, queue: DispatchQueue.global(qos: .userInitiated))
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    static func isLoopback(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let address): return address.isLoopback
        case .ipv6(let address): return address.isLoopback || address == .loopback
        case .name(let name, _): return name == "localhost"
        @unknown default: return false
        }
    }

    private static func serve(_ connection: NWConnection, handler: @escaping Handler, queue: DispatchQueue) {
        connection.start(queue: queue)
        receive(connection, buffer: Data(), handler: handler)
    }

    private static func receive(_ connection: NWConnection, buffer: Data, handler: @escaping Handler) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { chunk, _, isComplete, error in
            var buffer = buffer
            if let chunk { buffer.append(chunk) }
            if buffer.count > maxBodyBytes + 64 * 1024 || error != nil {
                connection.cancel()
                return
            }
            switch parse(buffer) {
            case .complete(let request) where !allows(origin: request.origin):
                respond(connection, Response(status: 403))
            case .complete(let request):
                respond(connection, handler(request))
            case .incomplete where !isComplete:
                receive(connection, buffer: buffer, handler: handler)
            default:
                respond(connection, Response(status: 400))
            }
        }
    }

    /// Без `Origin` — не браузер (локальный процесс); `null` — песочница плагина Figma. Остальные сайты — нет.
    static func allows(origin: String?) -> Bool {
        origin == nil || origin == "null"
    }

    enum Parsed {
        case complete(Request)
        case incomplete
        case invalid
    }

    static func parse(_ data: Data) -> Parsed {
        guard let headerEnd = data.firstRange(of: Data("\r\n\r\n".utf8)) else { return .incomplete }
        let head = String(decoding: data[data.startIndex..<headerEnd.lowerBound], as: UTF8.self)
        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.first?.split(separator: " ") ?? []
        guard requestLine.count >= 2 else { return .invalid }
        var length = 0
        var origin: String?
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            switch parts[0].trimmingCharacters(in: .whitespaces).lowercased() {
            case "content-length": length = Int(value) ?? -1
            case "origin": origin = value
            default: break
            }
        }
        guard length >= 0, length <= maxBodyBytes else { return .invalid }
        let bodyStart = headerEnd.upperBound
        guard data.count - (bodyStart - data.startIndex) >= length else { return .incomplete }
        let body = Data(data[bodyStart..<(bodyStart + length)])
        return .complete(Request(method: String(requestLine[0]), path: String(requestLine[1]), body: body, origin: origin))
    }

    private static func respond(_ connection: NWConnection, _ response: Response) {
        let reason = response.status < 300 ? "OK" : "Error"
        // Плагин Figma живёт в iframe с origin `null` — разрешён только он, не любой сайт.
        let head = """
            HTTP/1.1 \(response.status) \(reason)\r
            Content-Type: application/json\r
            Access-Control-Allow-Origin: null\r
            Access-Control-Allow-Methods: POST, OPTIONS\r
            Access-Control-Allow-Headers: Content-Type\r
            Content-Length: \(response.body.count)\r
            Connection: close\r
            \r

            """
        connection.send(content: Data(head.utf8) + response.body, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
