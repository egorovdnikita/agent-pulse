import Foundation

/// Облик маскота из пака Agent Pals (Lottie, 18 ботов × 13 клипов).
///
/// Пак платный (лицензия UI8), поэтому в репозиторий не кладётся: его ставит
/// `scripts/install-agent-pals.sh` в `~/Library/Application Support/AgentPulse/Skins/AgentPals/<Бот>/<Клип>.json`.
/// Нет пака или нужного бота — маскот остаётся классическим светящимся кругом.
public struct PalSkin: Sendable, Equatable, Hashable {
    public static let prefix = "agent-pals/"
    /// Классический круг со свечением.
    public static let classic = "default"
    /// Бот по умолчанию, когда пак поставили, а облик ещё не выбран.
    public static let defaultBot = "Circle"

    public let bot: String

    public init(bot: String) {
        self.bot = bot
    }

    /// `"agent-pals/Circle"` → бот Circle; `"default"` и прочее — nil.
    public init?(config skin: String) {
        guard skin.hasPrefix(Self.prefix) else { return nil }
        let bot = String(skin.dropFirst(Self.prefix.count))
        guard !bot.isEmpty, !bot.contains("/"), !bot.contains("..") else { return nil }
        self.bot = bot
    }

    public var configValue: String { Self.prefix + bot }

    public static var directory: URL {
        PulsePaths.supportDirectory.appending(path: "Skins/AgentPals", directoryHint: .isDirectory)
    }

    public func url(_ clip: PalClip, in root: URL = PalSkin.directory) -> URL {
        root.appending(path: bot, directoryHint: .isDirectory).appending(path: clip.rawValue + ".json")
    }

    /// Бот годится, только если у него есть все 13 клипов: иначе посреди работы маскот бы пропал.
    public func isComplete(in root: URL = PalSkin.directory) -> Bool {
        PalClip.allCases.allSatisfy { FileManager.default.fileExists(atPath: url($0, in: root).path) }
    }

    /// Установленные боты по алфавиту.
    public static func installed(in root: URL = PalSkin.directory) -> [PalSkin] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.sorted().map(PalSkin.init(bot:)).filter { $0.isComplete(in: root) }
    }
}
