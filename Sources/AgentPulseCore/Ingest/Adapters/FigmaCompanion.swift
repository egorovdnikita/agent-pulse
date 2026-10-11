import Foundation

/// Кадр зеркала: PNG изменённого фрейма от плагина-компаньона.
public struct FigmaFrame: Sendable, Equatable {
    public var file: String
    public var node: String
    public var png: Data
    public var at: Date
}

/// Сообщения плагина-компаньона Figma → события и кадры зеркала.
///
/// Плагин видит только изменения документа и не знает, кто их сделал. Поэтому «ИИ Figma генерирует»
/// выводится эвристикой на стороне плагина — всплеск созданных объектов, которого руками не сделать.
public enum FigmaCompanion {
    public enum Message: Sendable, Equatable {
        case events([AgentEvent])
        /// Документ меняется; плагин спрашивает, нужен ли кадр зеркала.
        case change
        case frame(FigmaFrame)
    }

    public static let aiTool = "FigmaAI"
    public static let hostBundleId = "com.figma.Desktop"

    public static func parse(_ body: Data, now: Date = Date()) -> Message? {
        guard
            let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
            object["v"] as? Int == 1,
            let kind = object["kind"] as? String
        else { return nil }
        let file = (object["file"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Figma"
        let session = "figma-\(file)"

        func event(_ kind: AgentEvent.Kind, tool: String? = nil, summary: String? = nil) -> AgentEvent {
            AgentEvent(
                source: .figmaAI, sessionId: session, kind: kind, tool: tool, summary: summary,
                context: file, hostBundleId: hostBundleId, ts: now
            )
        }

        switch kind {
        case "activity":
            switch object["state"] as? String {
            case "generating":
                return .events([
                    event(.promptSubmitted),
                    event(.toolStarted, tool: aiTool, summary: Humanizer.classify(tool: aiTool).text),
                ])
            case "idle":
                return .events([event(.stopped)])
            default:
                return nil
            }
        case "closed":
            return .events([event(.sessionEnded)])
        case "change":
            return .change
        case "frame":
            guard
                let encoded = object["png"] as? String,
                let png = Data(base64Encoded: encoded),
                png.starts(with: [0x89, 0x50, 0x4E, 0x47])
            else { return nil }
            return .frame(FigmaFrame(file: file, node: object["node"] as? String ?? "", png: png, at: now))
        default:
            return nil
        }
    }

    public static func reply(mirror: Bool) -> Data {
        Data(#"{"mirror":\#(mirror)}"#.utf8)
    }
}

/// Флаг «агент рисует в Figma — нужен кадр зеркала». Пишет главный поток, читает HTTP-сервер.
public final class MirrorWish: @unchecked Sendable {
    private let lock = NSLock()
    private var wanted = false

    public init() {}

    public var value: Bool {
        get { lock.withLock { wanted } }
        set { lock.withLock { wanted = newValue } }
    }
}
