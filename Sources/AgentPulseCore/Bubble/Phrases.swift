import Foundation

public enum BubbleTrigger: String, Sendable, CaseIterable, Codable {
    case notice
    case think
    case workRead, workEditCode, workEditFigma, workRun, workSearch
    case step
    case waitPermission, waitInput
    case done
    case error
    case fallAsleep
    case hoverSleep
    /// Реплика каталога реакций: текст выбирает Director.
    case line

    /// Фоновые реплики `think`/`work`: троттлятся, вытесняются реакциями.
    public var isAmbient: Bool {
        switch self {
        case .think, .workRead, .workEditCode, .workEditFigma, .workRun, .workSearch: true
        default: false
        }
    }

    /// Держатся до реакции пользователя и вытесняют всё остальное.
    public var isWait: Bool {
        self == .waitPermission || self == .waitInput
    }
}

/// Пулы реплик. Правила тона: ≤ 10 слов, без рода в прошедшем времени, без техники, без эмодзи и капса.
/// Лимит проверяется тестом по всем репликам.
public enum Phrases {
    public static let maxWords = 10

    /// Слова — последовательности букв и цифр; «Так-так» и «Что-то» считаются одним словом.
    public static func wordCount(_ phrase: String) -> Int {
        phrase.split { $0.isWhitespace }.filter { $0.contains { $0.isLetter || $0.isNumber } }.count
    }

    public static func pool(for trigger: BubbleTrigger) -> [String] {
        switch trigger {
        case .notice: ["Ага, беру", "Берусь", "Сейчас…", "Так-так"]
        case .think: ["Хмм…", "Думаю…", "Секунду…", "Прикину…"]
        case .workRead: ["Читаю…", "Изучаю…", "Смотрю…"]
        case .workEditCode: ["Пишу…", "Правлю…", "Собираю…"]
        case .workEditFigma: ["Рисую…", "Двигаю…", "Леплю…"]
        case .workRun: ["Запускаю…", "Проверяю…", "Гоняю…"]
        case .workSearch: ["Ищу…", "Поищу…", "Выясняю…"]
        case .step: ["Есть", "Шаг есть", "Дальше…"]
        case .waitPermission: ["Можно?", "Разрешишь?", "Пустишь?"]
        case .waitInput: ["Глянешь?", "Жду тебя", "Ты тут?"]
        case .done: ["Готово", "Всё готово", "Принимай", "Вот, держи"]
        case .error: ["Упс…", "Не вышло", "Что-то не то"]
        case .fallAsleep: ["Вздремну"]
        case .hoverSleep: ["Привет", "Я тут"]
        case .line: []
        }
    }
}
