import Foundation

/// Гардероб облика Agent Pals: какой бот сейчас на маскоте. Единственное место с правилами смены ботов.
///
/// Смысл **[решение]**: бот меняется не ради разнообразия, а чтобы ещё и сообщать.
/// 1. Дома маскот — «бот дня»: каждый день новый из домашних ботов, по кругу, без повторов подряд.
///    Новый день наступает не в полночь, а при тебе — первое появление за день, и переодевание видно.
/// 2. Пришёл агент — маскот переодевается в его бота: форма сразу говорит, кто работает
///    (Claude Code — Clover, Codex — Hexagon, Figma — Triangle…). Ботов агентов нет среди домашних —
///    не перепутать гостя с хозяином.
/// 3. Агент закончил — его бот ещё минуту доигрывает итог, потом маскот возвращается домой; заснул — сразу.
/// 4. Два агента работают вперемешку — бот сменяется не чаще раза в 20 s, иначе мельтешит.
///    «Ждёт тебя» — сразу: важно, кто именно ждёт.
/// 5. Любая смена держится хотя бы 3 s — успевает доиграть переодевание.
public struct PalWardrobe: Sendable {
    public enum Mode: Sendable, Equatable {
        case classic
        case daily
        case fixed(String)

        public static let dailyConfig = "agent-pals/daily"

        public init(config skin: String) {
            if skin == Self.dailyConfig {
                self = .daily
            } else if let pal = PalSkin(config: skin) {
                self = .fixed(pal.bot)
            } else {
                self = .classic
            }
        }
    }

    /// Домашние боты — по одному на день. Ботов агентов среди них нет.
    public static let homePool = ["Arch", "Cat", "Circle", "Drop", "Flame", "Ghost", "Heart", "Pill", "Scallop"]
    public static let agentHold = 20.0
    public static let leaveAfter = 60.0
    public static let minHold = 3.0

    /// Бот агента — по цвету и форме бренда.
    public static func costume(source: AgentEvent.Source, agent: String?) -> String {
        switch source {
        case .claudeCode: return "Clover"
        case .cowork: return "Briefcase"
        case .claudeChat: return "Cloud"
        case .figmaAI, .figmaMCP, .figmaCompanion: return "Triangle"
        case .orca:
            switch agent {
            case "Claude Code": return "Clover"
            case "Codex": return "Hexagon"
            case "Gemini": return "Star"
            case "Cursor": return "Square"
            default: return "Oval"
            }
        }
    }

    /// Все боты агентов — для подписи в настройках.
    public static let costumes: [(agent: String, bot: String)] = [
        ("Claude Code", "Clover"), ("Codex", "Hexagon"), ("Cowork", "Briefcase"), ("Claude Chat", "Cloud"),
        ("Figma", "Triangle"), ("Gemini", "Star"), ("Cursor", "Square"), ("Другие в Orca", "Oval"),
    ]

    /// Бот дня: шаг 5 по кругу из 9 обходит всех без повторов подряд.
    public static func dailyBot(day: Int, installed: Set<String>) -> String? {
        let pool = homePool.filter(installed.contains)
        guard !pool.isEmpty else { return installed.sorted().first }
        let index = ((day * 5) % pool.count + pool.count) % pool.count
        return pool[index]
    }

    /// Номер дня по местному календарю.
    public static func dayNumber(_ date: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: date)
        return Int((start.timeIntervalSinceReferenceDate / 86_400).rounded())
    }

    public private(set) var bot: String?
    public private(set) var since = -Double.infinity
    /// Сейчас надет бот агента.
    public private(set) var inCostume = false
    private var homeDay: Int?
    private var idleSince: Double?

    public init() {}

    /// Что сейчас происходит → какой бот на маскоте (nil — классический круг).
    @discardableResult
    public mutating func update(
        mode: Mode, costumes: Bool, installed: Set<String>, state: MascotState,
        source: AgentEvent.Source?, agent: String?, day: Int, present: Bool, at t: Double
    ) -> String? {
        let home: String?
        switch mode {
        case .classic:
            bot = nil
            inCostume = false
            return nil
        case .fixed(let name):
            home = installed.contains(name) ? name : nil
        case .daily:
            if homeDay == nil || (homeDay != day && present && !inCostume) { homeDay = day }
            home = Self.dailyBot(day: homeDay ?? day, installed: installed)
        }

        let active: Bool = switch state {
        case .think, .work, .waitYou: true
        case .idle, .sleep: false
        }
        idleSince = active ? nil : (idleSince ?? t)

        var wanted = home
        var wantedCostume = false
        if costumes, active, let source {
            let guest = Self.costume(source: source, agent: agent)
            if installed.contains(guest) {
                wanted = guest
                wantedCostume = true
            }
        } else if inCostume, state != .sleep, let idle = idleSince, t - idle < Self.leaveAfter {
            // Гость ещё доигрывает итог, потом уходит.
            wanted = bot
            wantedCostume = true
        }

        guard wanted != bot else {
            inCostume = wantedCostume && wanted != nil
            return bot
        }
        if bot != nil, !state.isWaiting {
            guard t - since >= Self.minHold else { return bot }
            if inCostume, wantedCostume, t - since < Self.agentHold { return bot }
        }
        bot = wanted
        inCostume = wantedCostume
        since = t
        return bot
    }
}
