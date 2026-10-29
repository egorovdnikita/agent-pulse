import Foundation

/// К чему относится реплика: заголовок облачка, иконка и её цвет. Работа Claude и Figma — иконкой самого приложения,
/// остальное — иконками Solar (стиль Bold, как в box-ui), у каждой категории свой цвет.
public enum BubbleCategory: String, Sendable, CaseIterable, Codable {
    case claude, figma, orca, news, newsIT, newsEconomy, newsScience, newsArt, newsGames, newsSpace, battery, wellbeing, network, devices, day, holiday, together, mood, rest

    public var title: String {
        switch self {
        case .claude: "Claude"
        case .figma: "Figma"
        case .orca: "Orca"
        case .news: NewsTopic.design.title
        case .newsIT: NewsTopic.it.title
        case .newsEconomy: NewsTopic.economy.title
        case .newsScience: NewsTopic.science.title
        case .newsArt: NewsTopic.art.title
        case .newsGames: NewsTopic.games.title
        case .newsSpace: NewsTopic.space.title
        case .battery: "Батарея"
        case .wellbeing: "Самочувствие"
        case .network: "Сеть"
        case .devices: "Вокруг меня"
        case .day: "Наш день"
        case .holiday: "Праздник"
        case .together: "Мы с тобой"
        case .mood: "Настроение"
        case .rest: "Отдых"
        }
    }

    /// Иконка Solar Bold; для приложений — запасная, если приложение не установлено.
    public var icon: String {
        switch self {
        case .claude, .figma, .orca: "stars"
        case .news: "palette"
        case .newsIT: "code-square"
        case .newsEconomy: "graph-up"
        case .newsScience: "atom"
        case .newsArt: "gallery"
        case .newsGames: "gamepad"
        case .newsSpace: "rocket"
        case .battery: "battery-charge"
        case .wellbeing: "heart-pulse"
        case .network: "wi-fi-router-round"
        case .devices: "devices"
        case .day: "sun"
        case .holiday: "confetti"
        case .together: "hand-heart"
        case .mood: "emoji-funny-circle"
        case .rest: "moon-sleep"
        }
    }

    /// Цвет иконки, sRGB hex.
    public var color: UInt32 {
        switch self {
        case .claude: 0xD97757
        case .figma: 0xA259FF
        case .orca: 0x1C1C1E
        case .news: 0x2F6BFF
        case .newsIT: 0x3A3A3C
        case .newsEconomy: 0x00875A
        case .newsScience: 0x0B7285
        case .newsArt: 0x8B5E3C
        case .newsGames: 0xD9480F
        case .newsSpace: 0x1B1F5E
        case .battery: 0x2DBE5C
        case .wellbeing: 0xFF3B30
        case .network: 0x00A8C8
        case .devices: 0x5E5CE6
        case .day: 0xFF9500
        case .holiday: 0xF2B200
        case .together: 0xFF2D78
        case .mood: 0xAF52DE
        case .rest: 0x6E7B91
        }
    }

    /// Работу агента показываем иконкой его приложения.
    public var appBundleId: String? {
        switch self {
        case .claude: "com.anthropic.claudefordesktop"
        case .figma: "com.figma.Desktop"
        case .orca: OrcaStatus.hostBundleId
        default: nil
        }
    }

    /// Агентный источник → приложение в заголовке.
    public static func agent(_ source: AgentEvent.Source?) -> BubbleCategory {
        switch source {
        case .figmaAI, .figmaMCP, .figmaCompanion: .figma
        case .orca: .orca
        default: .claude
        }
    }

    /// Заголовок агентной реплики — приложение, в котором идёт работа.
    public static func agentTitle(_ source: AgentEvent.Source?) -> String {
        switch source {
        case .claudeCode: "Claude Code"
        case .cowork: "Claude Cowork"
        case .claudeChat, nil: "Claude"
        case .figmaAI: "Figma AI"
        case .figmaMCP, .figmaCompanion: "Figma"
        case .orca: "Orca"
        }
    }

    /// Строка сессии в меню: кто работает и где. «Codex в Orca · agent-pulse».
    public static func sessionTitle(_ session: SessionInfo) -> String {
        var name = session.agent ?? agentTitle(session.source)
        if session.hostBundleId == OrcaStatus.hostBundleId, name != "Orca" { name += " в Orca" }
        return [name, session.context].compactMap(\.self).joined(separator: " · ")
    }

    public var isNews: Bool {
        [.news, .newsIT, .newsEconomy, .newsScience, .newsArt, .newsGames, .newsSpace].contains(self)
    }

    /// Новость → категория облачка по теме.
    public static func news(_ topic: NewsTopic) -> BubbleCategory {
        switch topic {
        case .design: .news
        case .it: .newsIT
        case .economy: .newsEconomy
        case .science: .newsScience
        case .art: .newsArt
        case .games: .newsGames
        case .space: .newsSpace
        }
    }

    /// Реакция каталога → категория по её id.
    public static func forReaction(_ id: String) -> BubbleCategory {
        let prefix = String(id.prefix { $0 != "." })
        switch prefix {
        case "agent": return .claude
        case "news": return .news
        case "battery", "charger", "lowPower": return .battery
        case "thermal", "memory", "disk", "uptime": return .wellbeing
        case "network": return .network
        case "display", "headphones", "volume", "capsLock", "theme": return .devices
        case "newYear", "birthday", "aprilFools": return .holiday
        case "poke", "stroke", "flyby", "drag", "thrown", "dropped", "spaces": return .together
        case "fun": return .mood
        case "sleep", "nodOff": return .rest
        default: return .day
        }
    }
}

/// Сколько прошло — по-человечески, для заголовка при наведении: «только что», «5 мин назад», «час назад».
public enum HumanTime {
    public static func ago(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<60: return "только что"
        case ..<3600: return "\(Int(seconds / 60)) мин назад"
        case ..<86_400:
            let hours = Int(seconds / 3600)
            return hours == 1 ? "час назад" : "\(hours) ч назад"
        default: return "давно"
        }
    }

    /// Русское множественное: 1 задача, 2 задачи, 5 задач, 21 задача.
    public static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let mod10 = n % 10, mod100 = n % 100
        if mod10 == 1 && mod100 != 11 { return one }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return few }
        return many
    }
}

/// Что нарисовать в облачке: заголовок с иконкой категории и суть.
public struct BubbleMessage: Sendable, Equatable {
    public var category: BubbleCategory
    public var title: String
    public var text: String
    /// Когда это было — при наведении: «5 мин назад».
    public var when: String?

    public init(category: BubbleCategory, title: String, text: String, when: String? = nil) {
        self.category = category
        self.title = title
        self.text = text
        self.when = when
    }

    public init(_ bubble: Bubble) {
        self.init(category: bubble.category, title: bubble.title, text: bubble.text, when: bubble.note)
    }
}
