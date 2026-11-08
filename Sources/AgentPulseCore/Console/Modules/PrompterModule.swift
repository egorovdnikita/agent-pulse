import Foundation
import CoreGraphics

/// Текст суфлёра: слова и их строки. Ширину строки знает только AppKit, поэтому она приходит снаружи.
public struct PrompterScript: Sendable, Equatable {
    public struct Line: Sendable, Equatable {
        /// Номера слов этой строки.
        public var words: Range<Int>
        public var text: String
    }

    public let text: String
    public let words: [String]
    /// Слова для сравнения с речью: без регистра, знаков и «ё».
    public let normalized: [String]

    public init(text: String) {
        self.text = text
        words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        normalized = words.map(Self.normalize)
    }

    public var isEmpty: Bool { words.isEmpty }

    public static func normalize(_ word: String) -> String {
        word.lowercased().replacingOccurrences(of: "ё", with: "е").filter { $0.isLetter || $0.isNumber }
    }

    /// Строки по словам. Абзац начинает новую строку, слово длиннее строки стоит одно.
    public func lines(fits: (String) -> Bool) -> [Line] {
        var result: [Line] = []
        var index = 0
        for paragraph in text.split(whereSeparator: \.isNewline) {
            var start = index
            var current = ""
            for word in paragraph.split(whereSeparator: \.isWhitespace).map(String.init) {
                let candidate = current.isEmpty ? word : "\(current) \(word)"
                if current.isEmpty || fits(candidate) {
                    current = candidate
                } else {
                    result.append(Line(words: start..<index, text: current))
                    start = index
                    current = word
                }
                index += 1
            }
            if !current.isEmpty { result.append(Line(words: start..<index, text: current)) }
        }
        return result
    }

    /// Доля строки, которую читаешь, пока она стоит у камеры. Дальше она плавно уступает место следующей.
    static let lineHold = 0.65

    /// Сколько строк прочитано, с дробной частью: на ней держится плавная прокрутка.
    public static func scroll(position: Double, in lines: [Line]) -> Double {
        guard !lines.isEmpty else { return 0 }
        let index = lineIndex(of: Int(position), in: lines)
        let words = lines[index].words
        let read = min(1, max(0, (position - Double(words.lowerBound)) / Double(max(1, words.count))))
        return Double(index) + max(0, read - lineHold) / (1 - lineHold)
    }

    /// Строка, в которой идёт слово.
    public static func lineIndex(of word: Int, in lines: [Line]) -> Int {
        lines.firstIndex { word < $0.words.upperBound } ?? max(0, lines.count - 1)
    }
}

/// Находит в тексте место, которое сейчас произносится.
public enum PrompterVoiceMatch {
    /// Сколько слов вперёд и назад смотреть от текущего места.
    static let lookAhead = 40
    static let lookBack = 6
    /// Сколько последних распознанных слов сверяется с текстом.
    static let tail = 6

    /// Слова совпали: целиком или, у длинных, началом — окончания распознаются хуже всего.
    static func same(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        guard a.count >= 5, b.count >= 5 else { return false }
        return a.prefix(4) == b.prefix(4)
    }

    /// Номер слова после произнесённого; nil — не нашлось или совпадение слишком слабое.
    public static func position(heard: [String], in script: [String], from current: Int) -> Int? {
        let spoken = heard.map(PrompterScript.normalize).filter { !$0.isEmpty }.suffix(tail)
        guard !spoken.isEmpty, !script.isEmpty else { return nil }
        let window = max(0, current - lookBack)..<min(script.count, current + lookAhead)
        var best: (end: Int, score: Int)?
        for end in window {
            var score = 0
            var scriptIndex = end
            var spokenIndex = spoken.endIndex - 1
            while spokenIndex >= spoken.startIndex, scriptIndex >= 0, same(spoken[spokenIndex], script[scriptIndex]) {
                score += 1
                scriptIndex -= 1
                spokenIndex -= 1
            }
            guard score > 0 else { continue }
            // При равном счёте — ближе к текущему месту: фразы в тексте повторяются.
            let isCloser = best.map { abs(end + 1 - current) < abs($0.end + 1 - current) } ?? true
            if score > (best?.score ?? 0) || (score == best?.score && isCloser) { best = (end, score) }
        }
        guard let best else { return nil }
        // Одно короткое слово («и», «в») ничего не доказывает: нужно длинное или хотя бы два подряд.
        let enough = best.score >= 2 || (script[best.end].count >= 5 && best.end >= current - 1)
        return enough ? best.end + 1 : nil
    }
}

/// Суфлёр. Время считается по словам: при смене скорости и при чтении голосом оно остаётся честным.
public struct PrompterModule: ConsoleModule {
    public enum Mode: Sendable, Equatable {
        case idle, running, paused
    }

    public static let defaultSpeed = 130
    public static let speedRange = 65...260
    /// Шаг множителя скорости.
    static let multiplierStep = 0.25
    /// Сколько текст держится после последнего слова.
    static let endHold: TimeInterval = 3
    /// Голосом: столько тишины — стоп.
    public static let voiceSilence: TimeInterval = 1.5

    public let id = ConsoleModuleID.prompter
    public let title = "Докладчик"
    public let accent: UInt32 = 0x30B0C7
    public private(set) var script = PrompterScript(text: "")
    public private(set) var mode = Mode.idle
    /// Слова в минуту.
    public private(set) var speed = PrompterModule.defaultSpeed
    /// Сколько слов уже прочитано; дробное, чтобы скорость не теряла точность.
    public private(set) var position = 0.0
    /// Текст идёт за голосом, а не по часам.
    public var followsVoice = false
    private var lastTick: Date?
    private var finishedAt: Date?
    private var lastHeard: Date?

    public init() {}

    public var isActive: Bool { mode != .idle }
    public var word: Int { min(Int(position), max(0, script.words.count - 1)) }
    /// Голос молчит: текст стоит, пока ты не заговоришь.
    public func voiceHolds(now: Date) -> Bool {
        guard followsVoice, mode == .running else { return false }
        return lastHeard.map { now.timeIntervalSince($0) >= Self.voiceSilence } ?? true
    }

    public var elapsed: TimeInterval { position / Double(speed) * 60 }
    public var total: TimeInterval { Double(script.words.count) / Double(speed) * 60 }

    public func priority(now: Date) -> ConsolePriority? {
        isActive ? .activeMode : nil
    }

    public func capsule(now: Date) -> CapsuleContent {
        let time = "\(Self.clock(elapsed)) из \(Self.clock(total))"
        return CapsuleContent(rings: [], label: "Суфлёр \(time)", text: "Суфлёр", tail: time, icon: "document-text")
    }

    public func wantsQuiet(now: Date) -> Bool { isActive }

    public static func clock(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded())
        return "\(whole / 60):" + String(format: "%02d", whole % 60)
    }

    // MARK: - Управление

    /// false — читать нечего.
    @discardableResult
    public mutating func start(text: String, now: Date) -> Bool {
        let fresh = PrompterScript(text: text)
        guard !fresh.isEmpty else { return false }
        script = fresh
        position = 0
        mode = .running
        lastTick = now
        lastHeard = nil
        finishedAt = nil
        return true
    }

    public mutating func stop() {
        mode = .idle
        position = 0
        lastTick = nil
        lastHeard = nil
        finishedAt = nil
    }

    public mutating func togglePause(now: Date) {
        switch mode {
        case .running: mode = .paused
        case .paused:
            mode = .running
            lastTick = now
            finishedAt = nil
        case .idle: break
        }
    }

    /// Скорость как множитель: 1.25x понятнее, чем слова в минуту.
    public var multiplier: Double {
        (Double(speed) / Double(Self.defaultSpeed) / Self.multiplierStep).rounded() * Self.multiplierStep
    }

    public var multiplierText: String { String(format: "%.2fx", multiplier) }

    /// Шаг 0.25x, от 0.5x до 2x.
    public mutating func changeSpeed(faster: Bool) {
        setMultiplier(multiplier + (faster ? Self.multiplierStep : -Self.multiplierStep))
    }

    /// Старое значение из настроек встаёт на ближайший шаг.
    public mutating func setSpeed(_ value: Int) {
        speed = min(Self.speedRange.upperBound, max(Self.speedRange.lowerBound, value))
        setMultiplier(multiplier)
    }

    private mutating func setMultiplier(_ value: Double) {
        let wanted = Int((value * Double(Self.defaultSpeed)).rounded())
        speed = min(Self.speedRange.upperBound, max(Self.speedRange.lowerBound, wanted))
    }

    /// Перемотка: доля текста от 0 до 1.
    public mutating func seek(toFraction fraction: Double, now: Date) {
        guard isActive else { return }
        move(to: Double(script.words.count) * min(1, max(0, fraction)), now: now)
    }

    /// Перемотка на строки. Назад всегда есть куда: сбился — вернулся к началу строки.
    public mutating func jump(lines step: Int, in lines: [PrompterScript.Line], now: Date) {
        guard isActive, !lines.isEmpty else { return }
        let target = min(lines.count - 1, max(0, PrompterScript.lineIndex(of: word, in: lines) + step))
        move(to: Double(lines[target].words.lowerBound), now: now)
    }

    private mutating func move(to place: Double, now: Date) {
        position = place
        lastTick = now
        lastHeard = now
        finishedAt = nil
    }

    /// Новые распознанные слова. Назад место не уходит: распознавание само переписывает начало фразы.
    public mutating func hear(_ words: [String], now: Date) {
        guard followsVoice, mode == .running else { return }
        lastHeard = now
        guard let found = PrompterVoiceMatch.position(heard: words, in: script.normalized, from: Int(position)) else { return }
        // Тире и прочие знаки не произносятся: перешагиваем, иначе текст не дойдёт до конца.
        var next = found
        while next < script.normalized.count, script.normalized[next].isEmpty { next += 1 }
        position = max(position, Double(next))
    }

    /// Двигает текст. Возвращает true, когда суфлёр дочитан и закрылся сам.
    public mutating func advance(now: Date) -> Bool {
        defer { lastTick = now }
        guard mode == .running else { return false }
        if !followsVoice, let lastTick {
            position += max(0, now.timeIntervalSince(lastTick)) * Double(speed) / 60
        }
        let count = Double(script.words.count)
        guard position >= count else { return false }
        position = count
        if finishedAt == nil { finishedAt = now }
        guard let finishedAt, now.timeIntervalSince(finishedAt) >= Self.endHold else { return false }
        stop()
        return true
    }

    /// Текст двигает свой таймер модели: секундного тика ему мало.
    public mutating func tick(now: Date) -> [ToolSignal] { [] }
}

/// Последние тексты суфлёра: только на этом Mac, удаляются кнопкой.
public struct PrompterLibrary: Codable, Sendable, Equatable {
    public static let capacity = 5
    public private(set) var texts: [String] = []

    public init() {}

    public mutating func remember(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        texts.removeAll { $0 == trimmed }
        texts.insert(trimmed, at: 0)
        texts = Array(texts.prefix(Self.capacity))
    }

    public mutating func remove(_ text: String) {
        texts.removeAll { $0 == text }
    }

    public static var url: URL { PulsePaths.supportDirectory.appending(path: "prompter.json") }

    public static func load(from url: URL = PrompterLibrary.url) -> PrompterLibrary {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Self.self, from: $0) } ?? PrompterLibrary()
    }

    public func save(to url: URL = PrompterLibrary.url) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Тексты могут быть личными: файл только для владельца.
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path(percentEncoded: false))
    }
}

/// Размер текста: расстояние до экрана у всех разное.
public enum PrompterTextSize: String, CaseIterable, Sendable, Codable {
    case small, medium, large

    public var points: Double {
        switch self {
        case .small: 17
        case .medium: 20
        case .large: 24
        }
    }

    public var title: String {
        switch self {
        case .small: "Маленький"
        case .medium: "Средний"
        case .large: "Большой"
        }
    }
}

/// Где встаёт суфлёр. Камера встроена в экран ноутбука: на нём панель выше всего, ближе к объективу.
public enum PrompterLayout {
    public static let width = 560.0
    public static let textHeight = 148.0
    /// Отступ под строкой меню, когда выреза нет.
    public static let menuBarGap = 6.0

    /// Яркость строки от читаемой вниз: глаз держится наверху, у камеры.
    public static func lineOpacity(row: Int) -> Double {
        switch row {
        case ..<1: 1
        case 1: 0.55
        case 2: 0.25
        default: max(0.25 * pow(0.82, Double(row - 2)), 0.1)
        }
    }

    /// `notch` — высота выреза; 0 — его нет. Координаты AppKit: начало внизу слева.
    public static func frame(
        screen: CGRect, visible: CGRect, notch: Double
    ) -> CGRect {
        let height = textHeight + notch
        let top = notch > 0 ? screen.maxY : visible.maxY - menuBarGap
        return CGRect(x: screen.midX - width / 2, y: top - height, width: width, height: height)
    }
}
