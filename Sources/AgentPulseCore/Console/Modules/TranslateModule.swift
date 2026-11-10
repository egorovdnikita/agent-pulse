import Foundation
import NaturalLanguage

/// Явная пара языков, в том числе после автоматического определения исходного.
public struct TranslateDirection: Sendable, Equatable, Hashable {
    public let source: String
    public let target: String
    public init(source: String, target: String) { self.source = source; self.target = target }
    public static let ruToEn = Self(source: "ru", target: "en")
    public static let enToRu = Self(source: "en", target: "ru")
    public var opposite: Self { Self(source: target, target: source) }
    public var title: String { Self.languageTitle(source) + " → " + Self.languageTitle(target).lowercased() }
    public static func languageTitle(_ code: String) -> String {
        let name = Locale(identifier: "ru").localizedString(forIdentifier: code) ?? code
        return name.prefix(1).uppercased() + name.dropFirst()
    }
    /// Совместимость с прежним автоматическим направлением RU ↔ EN.
    public static func detect(_ text: String) -> Self {
        let cyrillic = text.unicodeScalars.filter { (0x0400...0x04FF).contains($0.value) }.count
        let latin = text.unicodeScalars.filter { $0.isASCII && CharacterSet.letters.contains($0) }.count
        return cyrillic >= latin ? .ruToEn : .enToRu
    }
    public static func detectLanguage(_ text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue ?? "en"
    }
}

/// Переводчик: выделил, ⌃⌥T — Пульт раскрывается с переводом. Видит только то, что ты дал нажатием.
public struct TranslateModule: ConsoleModule {
    public enum State: Sendable, Equatable {
        case idle
        /// Выделение не прочиталось: подсказка, следующее нажатие возьмёт буфер.
        case askToCopy
        case working(source: String)
        case done(source: String, result: String)
        case failed(String)
    }

    public static let askToCopyHint = "Скопируй текст и нажми ⌃⌥T снова"
    /// Столько живёт подсказка: через час буфер уже о другом.
    public static let askToCopyLength: TimeInterval = 60

    public let id = ConsoleModuleID.translate
    public let title = "Переводчик"
    public let accent: UInt32 = 0x5E5CE6

    public private(set) var state = State.idle
    /// Текст пришёл из выделения: его можно заменить.
    public private(set) var replaceable = false
    /// nil — определить язык по введённому тексту.
    public private(set) var sourceLanguage: String? = "en"
    public private(set) var targetLanguage = "ru"
    public private(set) var recentSources = ["en", "ru", "de"]
    public private(set) var recentTargets = ["en", "ru", "de"]
    public private(set) var requestVersion = 0
    private var askedAt = Date.distantPast

    public init() {}

    /// Нажатие ⌃⌥T. Возвращает текст, который пора переводить.
    /// `editable` — выделение стоит в поле, его можно заменить; текст на странице заменить нельзя.
    public mutating func press(selection: String?, clipboard: String?, now: Date, editable: Bool = true) -> String? {
        requestVersion += 1
        if let text = Self.cleaned(selection) {
            state = .working(source: text)
            replaceable = editable
            return text
        }
        if state == .askToCopy, now.timeIntervalSince(askedAt) < Self.askToCopyLength, let text = Self.cleaned(clipboard) {
            state = .working(source: text)
            replaceable = false
            return text
        }
        state = .askToCopy
        askedAt = now
        replaceable = false
        return nil
    }

    /// Текст введён на странице. Возвращает то, что пора переводить.
    public mutating func type(_ text: String) -> String? {
        requestVersion += 1
        replaceable = false
        guard let text = Self.cleaned(text) else {
            state = .idle
            return nil
        }
        state = .working(source: text)
        return text
    }

    public func direction(of text: String) -> TranslateDirection {
        TranslateDirection(source: sourceLanguage ?? TranslateDirection.detectLanguage(text), target: targetLanguage)
    }

    public mutating func selectSource(_ code: String?) {
        if let code, code == targetLanguage {
            targetLanguage = sourceLanguage ?? (code == "en" ? "ru" : "en")
            Self.remember(targetLanguage, in: &recentTargets)
        }
        sourceLanguage = code
        if let code { Self.remember(code, in: &recentSources) }
        invalidate()
    }

    public mutating func selectTarget(_ code: String) {
        if code == sourceLanguage {
            sourceLanguage = targetLanguage
            Self.remember(targetLanguage, in: &recentSources)
        }
        targetLanguage = code
        Self.remember(code, in: &recentTargets)
        invalidate()
    }

    @discardableResult
    public mutating func flip(sourceText: String = "") -> String? {
        let newInput: String?
        if case .done(_, let result) = state { newInput = result } else { newInput = nil }
        let previous = direction(of: sourceText)
        sourceLanguage = previous.target
        targetLanguage = previous.source
        Self.remember(previous.target, in: &recentSources)
        Self.remember(previous.source, in: &recentTargets)
        invalidate()
        return newInput
    }

    private mutating func invalidate() { requestVersion += 1; state = .idle; replaceable = false }
    private static func remember(_ code: String, in list: inout [String]) {
        guard !list.contains(code) else { return }
        list.insert(code, at: 0)
        list = Array(list.prefix(3))
    }

    public mutating func finish(source: String, result: String, request: Int? = nil) {
        guard request == nil || request == requestVersion else { return }
        guard state == .working(source: source) else { return }
        state = .done(source: source, result: result)
    }

    public mutating func fail(source: String, problem: String, request: Int? = nil) {
        guard request == nil || request == requestVersion else { return }
        guard state == .working(source: source) else { return }
        state = .failed(problem)
    }

    public mutating func reset() {
        requestVersion += 1
        state = .idle
        replaceable = false
    }

    private static func cleaned(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    public func priority(now: Date) -> ConsolePriority? { nil }
    public func capsule(now: Date) -> CapsuleContent { CapsuleContent(rings: [], label: title) }
    public mutating func tick(now: Date) -> [ToolSignal] { [] }
}
