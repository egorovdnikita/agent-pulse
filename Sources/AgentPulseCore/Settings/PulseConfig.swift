import Foundation

/// JSON-конфиг в Application Support. Отсутствующие ключи берутся из значений по умолчанию.
public struct PulseConfig: Codable, Sendable, Equatable {
    public var version = 1
    public var sources = Sources()
    public var display = Display()
    public var events = Events()
    public var mirror = Mirror()
    public var mascot = Mascot()
    public var privacy = Privacy()

    public init() {}

    public struct Sources: Codable, Sendable, Equatable {
        public var claudeCode = true
        public var figmaMCP = true
        public var figmaMirror = true
    }

    public struct Display: Codable, Sendable, Equatable {
        public enum Anchor: String, Codable, Sendable, CaseIterable {
            case topRight = "top-right", topLeft = "top-left", bottomRight = "bottom-right", bottomLeft = "bottom-left"

            public var isRight: Bool { self == .topRight || self == .bottomRight }
            public var isTop: Bool { self == .topRight || self == .topLeft }
        }

        public var mode = "mascot"
        public var mascotSize: Double = 48
        public var anchor: Anchor = .topRight
        /// `active` — монитор с курсором; также `main`, `builtin`.
        public var screen = "active"
        public var autoHideWhenSourceVisible = true
        public var expandOn = ["awaitingUser", "done"]
    }

    public struct EventRule: Codable, Sendable, Equatable {
        public var overlay = true
        public var notification = true
        /// `none` | `soft`
        public var sound = "none"
    }

    public struct Events: Codable, Sendable, Equatable {
        public var awaitingUser = EventRule(overlay: true, notification: true, sound: "soft")
        public var done = EventRule(overlay: true, notification: true, sound: "none")
        public var toolActivity = EventRule(overlay: true, notification: false, sound: "none")
    }

    public struct Mirror: Codable, Sendable, Equatable {
        public var source = "companion"
        public var fallback = "rest"
        public var debounceMs = 800
        public var maxWidth = 320
    }

    public struct Mascot: Codable, Sendable, Equatable {
        public var skin = "default"
    }

    public struct Privacy: Codable, Sendable, Equatable {
        public var showPromptText = false
    }

    // MARK: - Загрузка и сохранение

    /// Пользовательский JSON накладывается поверх значений по умолчанию; битый файл → значения по умолчанию.
    public static func decode(_ data: Data) -> PulseConfig {
        guard
            let user = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let defaults = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(PulseConfig())) as? [String: Any],
            let merged = try? JSONSerialization.data(withJSONObject: deepMerge(defaults, user)),
            let config = try? JSONDecoder().decode(PulseConfig.self, from: merged)
        else { return PulseConfig() }
        return config
    }

    public static func load(from url: URL = PulsePaths.configURL) -> PulseConfig {
        guard let data = try? Data(contentsOf: url) else { return PulseConfig() }
        return decode(data)
    }

    public func save(to url: URL = PulsePaths.configURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    static func deepMerge(_ base: [String: Any], _ overlay: [String: Any]) -> [String: Any] {
        var result = base
        for (key, value) in overlay {
            if let nested = value as? [String: Any], let baseNested = base[key] as? [String: Any] {
                result[key] = deepMerge(baseNested, nested)
            } else {
                result[key] = value
            }
        }
        return result
    }
}
