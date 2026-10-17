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
    public var senses = Senses()
    public var character = Character()

    public init() {}

    /// Какие органы чувств включены.
    public struct Senses: Codable, Sendable, Equatable {
        public var agents = true
        public var body = true
        public var rhythm = true
        public var audio = true
        public var experimental = false
    }

    /// Характер: два слайдера вместо двадцати переключателей.
    public struct Character: Codable, Sendable, Equatable {
        public var talkativeness = 0.5
        public var mischief = 0.5
        /// «HH:mm».
        public var quietFrom: String? = "23:30"
        public var quietTo: String? = "08:00"
        /// «MM-dd».
        public var birthday: String?
        public var hideWhenIdle = true
        /// Время от времени рассказывает новости **[решение]**: больше всего — дизайн.
        public var designNews = true
        /// Какие темы новостей включены (`NewsTopic.rawValue`).
        public var newsTopics: [String] = NewsTopic.allCases.map(\.rawValue)

        public var enabledNewsTopics: Set<NewsTopic> {
            Set(newsTopics.compactMap(NewsTopic.init(rawValue:)))
        }
        public var hideAfterMinutes = 30

        static func minutes(_ text: String?) -> Int? {
            guard let parts = text?.split(separator: ":"), parts.count == 2,
                  let hours = Int(parts[0]), let minutes = Int(parts[1]) else { return nil }
            return hours * 60 + minutes
        }

        public var directorSettings: DirectorSettings {
            var settings = DirectorSettings()
            settings.talkativeness = talkativeness
            settings.mischief = mischief
            settings.quietFrom = Self.minutes(quietFrom)
            settings.quietTo = Self.minutes(quietTo)
            if let parts = birthday?.split(separator: "-"), parts.count == 2, let month = Int(parts[0]), let day = Int(parts[1]) {
                settings.birthday = DateComponents(month: month, day: day)
            }
            return settings
        }
    }

    public struct Sources: Codable, Sendable, Equatable {
        public var claudeCode = true
        public var cowork = true
        public var claudeChat = false
        public var figmaMCP = true
        public var figmaAI = true
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
        /// Справа снизу — рядом с Dock, где обычно пусто.
        public var anchor: Anchor = .bottomRight
        /// `dock` — дисплей, где закреплён Dock (если Dock скрыт — основной);
        /// также `main` (с меню-баром), `active` (с курсором), `builtin`.
        public var screen = "dock"
        public var autoHideWhenSourceVisible = true
        public var expandOn = ["awaitingUser", "done"]
        /// Куда маскота перетащили: сдвиг от угла по умолчанию, pt, на каждый монитор (ключ — номер дисплея).
        public var offsets: [String: [Double]] = [:]
        /// Отпущенный посреди экрана маскот падает на «пол». Выключено: висит, где поставили.
        public var gravity = false
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
