import Foundation

/// Направление перевода определяется по тексту: кириллицы больше — с русского.
public enum TranslateDirection: Sendable, Equatable {
    case ruToEn, enToRu

    public static func detect(_ text: String) -> TranslateDirection {
        var cyrillic = 0
        var latin = 0
        for scalar in text.unicodeScalars {
            if (0x0400...0x04FF).contains(scalar.value) {
                cyrillic += 1
            } else if scalar.isASCII, CharacterSet.letters.contains(scalar) {
                latin += 1
            }
        }
        return cyrillic >= latin ? .ruToEn : .enToRu
    }

    public var source: String { self == .ruToEn ? "ru" : "en" }
    public var target: String { self == .ruToEn ? "en" : "ru" }
    public var title: String { self == .ruToEn ? "Русский → английский" : "Английский → русский" }
    public var opposite: TranslateDirection { self == .ruToEn ? .enToRu : .ruToEn }
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
    /// Направление развёрнуто вручную.
    public private(set) var flipped = false
    private var askedAt = Date.distantPast

    public init() {}

    /// Нажатие ⌃⌥T. Возвращает текст, который пора переводить.
    /// `editable` — выделение стоит в поле, его можно заменить; текст на странице заменить нельзя.
    public mutating func press(selection: String?, clipboard: String?, now: Date, editable: Bool = true) -> String? {
        if let text = Self.cleaned(selection) {
            state = .working(source: text)
            replaceable = editable
            flipped = false
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
        replaceable = false
        guard let text = Self.cleaned(text) else {
            state = .idle
            return nil
        }
        state = .working(source: text)
        return text
    }

    public func direction(of text: String) -> TranslateDirection {
        let found = TranslateDirection.detect(text)
        return flipped ? found.opposite : found
    }

    public mutating func flip() {
        flipped.toggle()
    }

    public mutating func finish(source: String, result: String) {
        guard state == .working(source: source) else { return }
        state = .done(source: source, result: result)
    }

    public mutating func fail(source: String, problem: String) {
        guard state == .working(source: source) else { return }
        state = .failed(problem)
    }

    public mutating func reset() {
        state = .idle
        replaceable = false
        flipped = false
    }

    private static func cleaned(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    public func priority(now: Date) -> ConsolePriority? { nil }
    public func capsule(now: Date) -> CapsuleContent { CapsuleContent(rings: [], label: title) }
    public mutating func tick(now: Date) -> [ToolSignal] { [] }
}
