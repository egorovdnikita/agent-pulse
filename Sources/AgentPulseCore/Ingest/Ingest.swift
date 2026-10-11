import Foundation

/// Конверт сообщения в сокете: необязательная строка `PULSE1 bundle=<id> channel=<канал>\n`, затем тело.
public struct PulseEnvelope: Sendable, Equatable {
    public static let prefix = "PULSE1"

    public var host: String?
    public var channel: String?
    public var body: Data

    public init(_ data: Data) {
        guard data.starts(with: Data(Self.prefix.utf8)), let newline = data.firstIndex(of: 0x0A) else {
            body = data
            return
        }
        let header = String(decoding: data[data.startIndex..<newline], as: UTF8.self)
        for part in header.split(separator: " ") {
            let pair = part.split(separator: "=", maxSplits: 1)
            guard pair.count == 2, !pair[1].isEmpty else { continue }
            switch pair[0] {
            case "bundle": host = String(pair[1])
            case "channel": channel = String(pair[1])
            default: break
            }
        }
        body = Data(data[data.index(after: newline)...])
    }
}

/// Маршрутизатор: сообщение из сокета → адаптер нужного источника.
public enum Ingest {
    public static func parse(_ data: Data, now: Date = Date()) -> [AgentEvent] {
        let envelope = PulseEnvelope(data)
        switch envelope.channel {
        case "browser":
            return BrowserBridge.parse(envelope.body, host: envelope.host, now: now)
        default:
            return ClaudeCodeHooks.parse(data, now: now).map { [$0] } ?? []
        }
    }
}
