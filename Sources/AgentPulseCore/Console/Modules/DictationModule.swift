import Foundation

/// Диктовка: зажал ⌃⌥D — говоришь, отпустил — текст встаёт туда, где курсор. Всё на этом Mac.
public struct DictationModule: ConsoleModule {
    public enum Phase: Sendable, Equatable {
        case idle, recording, recognizing
    }

    /// Короткое сообщение в капсуле.
    public enum Notice: Sendable, Equatable {
        case needsModel, inClipboard, inserted, failed, noMicrophone, corrected, correctionUnavailable, correctionFailed

        public var text: String {
            switch self {
            case .needsModel: "Скачай модель"
            case .inClipboard: "Текст в буфере"
            case .inserted: "Вставлено"
            case .failed: "Не вышло распознать"
            case .noMicrophone: "Нет доступа к микрофону"
            case .corrected: "Исправлено"
            case .correctionUnavailable: "Нечего исправлять"
            case .correctionFailed: "Исправление не вышло"
            }
        }
    }

    /// Короче — случайное нажатие: звук выбрасывается.
    public static let minimumHold: TimeInterval = 0.3
    /// Длиннее одна запись не идёт: память и время распознавания не бесконечны.
    public static let maximumLength: TimeInterval = 300
    public static let noticeLength: TimeInterval = 4
    public static let insertedLength: TimeInterval = 1.5

    public let id = ConsoleModuleID.dictation
    public let title = "Диктовка"
    public let accent: UInt32 = 0xFF375F

    public private(set) var phase = Phase.idle
    public private(set) var correcting = false
    public private(set) var notice: Notice?
    private var noticeUntil = Date.distantPast
    private var startedAt = Date.distantPast

    public init() {}

    /// Клавиша нажата. false — записи не будет: модели нет или запись уже идёт.
    public mutating func press(now: Date, modelReady: Bool, correcting: Bool = false) -> Bool {
        guard phase == .idle else { return false }
        guard modelReady else {
            show(.needsModel, now: now)
            return false
        }
        self.correcting = correcting
        phase = .recording
        startedAt = now
        notice = nil
        return true
    }

    /// Клавиша отпущена. true — звук идёт в распознавание, false — это было случайное нажатие.
    public mutating func release(now: Date) -> Bool {
        guard phase == .recording else { return false }
        guard now.timeIntervalSince(startedAt) >= Self.minimumHold else {
            phase = .idle
            correcting = false
            return false
        }
        phase = .recognizing
        return true
    }

    /// Запись упёрлась в предел: дальше как при отпускании.
    public func reachedLimit(now: Date) -> Bool {
        phase == .recording && now.timeIntervalSince(startedAt) >= Self.maximumLength
    }

    /// Распознавание и вставка закончились.
    public mutating func finish(now: Date, notice: Notice?) {
        phase = .idle
        correcting = false
        if let notice { show(notice, now: now) }
    }

    private mutating func show(_ notice: Notice, now: Date) {
        self.notice = notice
        // Удача — короткий знак, а не сообщение: читать тут нечего.
        noticeUntil = now.addingTimeInterval((notice == .inserted || notice == .corrected) ? Self.insertedLength : Self.noticeLength)
    }

    private func visibleNotice(now: Date) -> Notice? {
        now < noticeUntil ? notice : nil
    }

    public func priority(now: Date) -> ConsolePriority? {
        phase != .idle || visibleNotice(now: now) != nil ? .activeMode : nil
    }

    public func capsule(now: Date) -> CapsuleContent {
        if phase == .idle, let notice = visibleNotice(now: now) {
            return CapsuleContent(rings: [], label: notice.text, text: notice.text, icon: "document-text")
        }
        return CapsuleContent(rings: [], label: correcting ? "Исправление" : title, wave: true)
    }

    public mutating func tick(now: Date) -> [ToolSignal] { [] }

    /// Пока идёт запись, маскот молчит, а лидер не меняется.
    public func wantsQuiet(now: Date) -> Bool { phase == .recording }
}

/// Правила замены «произнесённое → записанное». Регистр произнесённого не важен, слова целиком.
public struct DictationRule: Codable, Sendable, Equatable, Identifiable {
    public var id: String { spoken }
    public var spoken: String
    public var written: String
    public var exactSpelling: Bool?
    public var variants: [String] { spoken.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }

    public init(spoken: String, written: String, exactSpelling: Bool = false) {
        self.spoken = spoken
        self.written = written
        self.exactSpelling = exactSpelling ? true : nil
    }
}

public enum DictationRules {
    /// Встроенный набор для разработки.
    public static let builtIn: [DictationRule] = [
        .init(spoken: "диплой", written: "deploy"),
        .init(spoken: "деплой", written: "deploy"),
        .init(spoken: "пул реквест", written: "pull request"),
        .init(spoken: "пулл реквест", written: "pull request"),
        .init(spoken: "пул реквист", written: "pull request"),
        .init(spoken: "коммит", written: "commit"),
        .init(spoken: "гитхаб", written: "GitHub"),
        .init(spoken: "гитхэб", written: "GitHub"),
        .init(spoken: "гитхэп", written: "GitHub"),
    ]

    /// Свои правила важнее встроенных; длинные фразы — раньше коротких.
    public static func apply(_ text: String, custom: [DictationRule] = []) -> String {
        var seen = Set<String>()
        let expanded = (custom + builtIn).flatMap { rule in
            rule.variants.map { DictationRule(spoken: $0, written: rule.written, exactSpelling: rule.exactSpelling == true) }
        }
        let rules = expanded
            .filter { !$0.spoken.trimmingCharacters(in: .whitespaces).isEmpty && seen.insert($0.spoken.lowercased()).inserted }
            .sorted { $0.spoken.count > $1.spoken.count }
        let alternatives = rules.map { NSRegularExpression.escapedPattern(for: $0.spoken.trimmingCharacters(in: .whitespaces)) }.joined(separator: "|")
        guard !alternatives.isEmpty else { return text }
        let pattern = "(?<![\\p{L}\\p{N}])(?:" + alternatives + ")(?![\\p{L}\\p{N}])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        var output = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let originalRange = Range(match.range, in: text), let range = Range(match.range, in: output) else { continue }
            let spoken = String(text[originalRange])
            guard let rule = rules.first(where: { $0.spoken.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(spoken) == .orderedSame }) else { continue }
            let capitalized = rule.exactSpelling != true && spoken.first?.isUppercase == true
            output.replaceSubrange(range, with: capitalized ? rule.written.prefix(1).uppercased() + rule.written.dropFirst() : rule.written)
        }
        return output
    }
}

/// Длинная запись режется на куски по паузам: память модели растёт вместе с длиной звука.
public enum DictationChunks {
    public static let sampleRate = 16000
    public static let limit = 25 * sampleRate
    /// В конце куска ищем самое тихое место.
    static let searchWindow = 5 * sampleRate
    static let step = sampleRate / 10

    public static func ranges(of samples: [Float]) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var start = 0
        while samples.count - start > limit {
            let end = quietestPoint(in: samples, from: start + limit - searchWindow, to: start + limit)
            result.append(start..<end)
            start = end
        }
        if start < samples.count { result.append(start..<samples.count) }
        return result
    }

    private static func quietestPoint(in samples: [Float], from: Int, to: Int) -> Int {
        var best = to
        var bestEnergy = Float.infinity
        var position = from
        while position + step <= to {
            var energy: Float = 0
            for index in position..<(position + step) { energy += samples[index] * samples[index] }
            if energy < bestEnergy {
                bestEnergy = energy
                best = position + step / 2
            }
            position += step
        }
        return best
    }
}

/// Как вставить текст. Текст не должен теряться: куда бы ни шла вставка, он либо встал, либо лежит в буфере.
public enum DictationInsertPlan: Sendable, Equatable {
    /// Запись в поле через Accessibility, с проверкой; не встал — ⌘V с возвратом буфера.
    case field
    /// Поле не опознано: ⌘V, текст остаётся в буфере на случай, если вставлять было некуда.
    case pasteKeepingClipboard
    /// Только буфер.
    case clipboard

    public static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

    public static func choose(accessibility: Bool, role: String?) -> DictationInsertPlan {
        guard accessibility else { return .clipboard }
        if let role, textRoles.contains(role) { return .field }
        return .pasteKeepingClipboard
    }
}

/// История диктовки: выключена по умолчанию; только текст, 30 дней. Аудио не сохраняется никогда.
public struct DictationHistory: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable, Identifiable {
        public var id: Date { date }
        public var date: Date
        public var text: String
    }

    public static let keepDays = 30.0
    public private(set) var entries: [Entry] = []

    public init() {}

    public static var url: URL { PulsePaths.supportDirectory.appending(path: "dictation.json") }

    public mutating func add(_ text: String, now: Date) {
        entries.insert(Entry(date: now, text: text), at: 0)
        prune(now: now)
    }

    public mutating func prune(now: Date) {
        entries.removeAll { now.timeIntervalSince($0.date) > Self.keepDays * 86400 }
    }

    public static func load(from url: URL = DictationHistory.url, now: Date = Date()) -> DictationHistory {
        var history = (try? Data(contentsOf: url)).flatMap { Self.decoded($0) } ?? DictationHistory()
        history.prune(now: now)
        return history
    }

    private static func decoded(_ data: Data) -> DictationHistory? {
        try? JSONDecoder().decode(Self.self, from: data)
    }

    public func save(to url: URL = DictationHistory.url) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path(percentEncoded: false))
    }

    /// Сброс: файла больше нет.
    public static func erase(at url: URL = DictationHistory.url) {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Модель распознавания: скачивается кнопкой, в сборку не входит. Архив закреплён контрольной суммой.
public enum DictationModelSpec {
    public static let folder = "gigaam-v3-punct"
    public static let url = URL(string:
        "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-transducer-punct-giga-am-v3-russian-2025-12-16.tar.bz2")!
    public static let sha256 = "f9620a0099019c6afcee26525ef9ed3297fa50dd5691c1902af0c948fc1a470b"
    public static let archiveRoot = "sherpa-onnx-nemo-transducer-punct-giga-am-v3-russian-2025-12-16"
    /// Сколько качать и сколько займёт на диске, MB.
    public static let downloadMB = 170
    public static let diskMB = 232
    /// Файл и его точный размер: недокачанная или чужая модель не считается установленной.
    public static let files: [(name: String, bytes: Int)] = [
        ("encoder.int8.onnx", 224_570_820),
        ("decoder.onnx", 4_600_132),
        ("joiner.onnx", 2_712_896),
        ("tokens.txt", 13_354),
        ("LICENSE", 1_070),
    ]

    public static var directory: URL { PulsePaths.supportDirectory.appending(path: "Models/\(folder)") }

    public static func isInstalled(at directory: URL = DictationModelSpec.directory) -> Bool {
        files.allSatisfy { file in
            let path = directory.appending(path: file.name).path(percentEncoded: false)
            let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int
            return size == file.bytes
        }
    }
}
