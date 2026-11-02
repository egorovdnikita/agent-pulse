import Foundation

/// Гардероб облика Agent Pals: какой бот сейчас на маскоте. Единственное место с правилами смены ботов.
///
/// Правила **[решение]**: бот меняется сам и не зависит от того, какой агент или программа работает.
/// 1. Повод сменить бота — начало: новая задача (из покоя или сна маскот начинает думать или работать)
///    и пробуждение (сон кончился). Посреди работы бот не меняется — характер работы читается по клипу.
/// 2. Не чаще раза в `minGap` (3 мин): быстрые задачи подряд не превращаются в карусель.
/// 3. Пока агент ждёт тебя, бот не меняется никогда — важное не тонет в милом.
/// 4. Боты идут «мешком»: все установленные в случайном порядке, без повторов, пока не покажутся все;
///    следующий мешок не начинается с только что показанного.
public struct PalWardrobe: Sendable {
    public enum Mode: Sendable, Equatable {
        case classic
        case shuffle
        case fixed(String)

        public static let shuffleConfig = "agent-pals/shuffle"
        /// Прежнее значение «Каждый день новый» — читается как «Меняется сам».
        static let legacyDaily = "agent-pals/daily"

        public init(config skin: String) {
            if skin == Self.shuffleConfig || skin == Self.legacyDaily {
                self = .shuffle
            } else if let pal = PalSkin(config: skin) {
                self = .fixed(pal.bot)
            } else {
                self = .classic
            }
        }
    }

    public static let minGap = 180.0

    public private(set) var bot: String?
    public private(set) var since = -Double.infinity
    private var bag: [String] = []
    private var lastState: MascotState?

    public init() {}

    /// Что сейчас происходит → какой бот на маскоте (nil — классический круг).
    @discardableResult
    public mutating func update<R: RandomNumberGenerator>(
        mode: Mode, installed: Set<String>, state: MascotState, at t: Double, using rng: inout R
    ) -> String? {
        let previous = lastState
        lastState = state
        switch mode {
        case .classic:
            bot = nil
            return nil
        case .fixed(let name):
            bot = installed.contains(name) ? name : nil
            return bot
        case .shuffle:
            break
        }
        guard !installed.isEmpty else {
            bot = nil
            return nil
        }
        guard let current = bot, installed.contains(current) else {
            return dress(next(installed, rng: &rng), at: t)
        }
        guard let previous, previous != state, !state.isWaiting, t - since >= Self.minGap else { return current }
        let taskStarts = !Self.isActive(previous) && Self.isActive(state)
        let wakes = previous == .sleep
        return taskStarts || wakes ? dress(next(installed, rng: &rng), at: t) : current
    }

    @discardableResult
    public mutating func update(mode: Mode, installed: Set<String>, state: MascotState, at t: Double) -> String? {
        var rng = SystemRandomNumberGenerator()
        return update(mode: mode, installed: installed, state: state, at: t, using: &rng)
    }

    static func isActive(_ state: MascotState) -> Bool {
        switch state {
        case .think, .work, .waitYou: true
        case .idle, .sleep: false
        }
    }

    private mutating func dress(_ name: String, at t: Double) -> String {
        bot = name
        since = t
        return name
    }

    private mutating func next<R: RandomNumberGenerator>(_ installed: Set<String>, rng: inout R) -> String {
        bag.removeAll { !installed.contains($0) }
        if bag.isEmpty {
            bag = installed.sorted().shuffled(using: &rng)
            // Новый мешок не начинается с того, кто только что был.
            if bag.count > 1, bag.last == bot { bag.swapAt(bag.count - 1, 0) }
        }
        return bag.removeLast()
    }
}
