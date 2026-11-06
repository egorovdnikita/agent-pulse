import Foundation

/// Что играет. Маскот об этом не знает: у него только занятый звуковой выход.
public struct NowPlaying: Sendable, Equatable {
    public var title: String
    public var artist: String?
    public var isPlaying: Bool
    public var duration: TimeInterval?
    public var elapsed: TimeInterval
    /// Момент, к которому относится `elapsed`.
    public var at: Date
    public var artwork: Data?

    public init(title: String, artist: String?, isPlaying: Bool, duration: TimeInterval?, elapsed: TimeInterval, at: Date, artwork: Data? = nil) {
        self.title = title
        self.artist = artist
        self.isPlaying = isPlaying
        self.duration = duration
        self.elapsed = elapsed
        self.at = at
        self.artwork = artwork
    }

    public func position(now: Date) -> TimeInterval {
        let moved = isPlaying ? elapsed + now.timeIntervalSince(at) : elapsed
        return min(max(0, moved), duration ?? .infinity)
    }

    public var line: String {
        [artist, title].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " — ")
    }
}

public enum MediaAvailability: Sendable, Equatable {
    case unknown, available
    /// Ни один способ не работает на этой системе: модуль так и говорит, а не врёт.
    case unavailable
}

public enum MediaCommand: Int, Sendable {
    case togglePlayPause = 2, next = 4, previous = 5
}

public struct MediaModule: ConsoleModule {
    public let id = ConsoleModuleID.media
    public let title = "Музыка"
    public let accent: UInt32 = 0xFF2D78
    public var playing: NowPlaying?
    public var availability = MediaAvailability.unknown

    public init() {}

    public func priority(now: Date) -> ConsolePriority? {
        playing?.isPlaying == true ? .music : nil
    }

    public func capsule(now: Date) -> CapsuleContent {
        let line = playing?.line ?? title
        return CapsuleContent(rings: [], label: line, text: line, icon: "music-note")
    }

    public mutating func tick(now: Date) -> [ToolSignal] { [] }
}

/// Поток `mediaremote-adapter stream --no-diff`: одна строка JSON на изменение. Пустой `payload` — ничего не играет.
public enum MediaRemoteStream {
    public enum Update: Sendable, Equatable {
        case playing(NowPlaying)
        case nothing
    }

    public static func parse(_ line: Data, now: Date = Date()) -> Update? {
        guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              object["type"] as? String == "data",
              let payload = object["payload"] as? [String: Any] else { return nil }
        guard !payload.isEmpty, payload["playing"] != nil else { return .nothing }
        let number = { (key: String) in (payload[key] as? NSNumber)?.doubleValue }
        // Часть плееров отдаёт бесконечную длительность.
        let duration = number("duration").flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let stamp = (payload["timestamp"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
        return .playing(NowPlaying(
            title: payload["title"] as? String ?? "Без названия",
            artist: payload["artist"] as? String,
            isPlaying: payload["playing"] as? Bool ?? false,
            duration: duration,
            elapsed: number("elapsedTime") ?? 0,
            at: stamp ?? now,
            artwork: (payload["artworkData"] as? String).flatMap { Data(base64Encoded: $0) }
        ))
    }
}
