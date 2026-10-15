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

/// Реплики окрашиваются настроением: уставший договаривает с «…», радостному есть что добавить.
public enum MoodVoice {
    /// Варианты, которые появляются только в хорошем настроении.
    static func joyful(_ trigger: BubbleTrigger) -> [String] {
        switch trigger {
        case .done: ["Ура, готово", "Красота, глянь"]
        case .notice: ["О, давай"]
        default: []
        }
    }

    public static func pool(for trigger: BubbleTrigger, mood: Mood?) -> [String] {
        let base = Phrases.pool(for: trigger)
        guard let mood, mood.joy > 0.7 else { return base }
        return base + joyful(trigger)
    }

    /// Уставший договаривает с «…»: «Готово» → «Готово…». Вопросы и восклицания не трогаем.
    public static func color(_ text: String, mood: Mood?) -> String {
        guard let mood, mood.energy < 0.35, let last = text.last, !"…?!".contains(last) else { return text }
        return text + "…"
    }
}

/// Пулы реплик. Говорит от себя, как живой: «У меня готово», «Я жду тебя» — но без рода
/// («нашлось», а не «нашёл»): у существа нет пола. Правила тона: ≤ 10 слов, без рода в прошедшем времени, без техники, без эмодзи и капса.
/// Лимит проверяется тестом по всем репликам.
public enum Phrases {
    public static let maxWords = 10

    /// Слова — последовательности букв и цифр; «Так-так» и «Что-то» считаются одним словом.
    public static func wordCount(_ phrase: String) -> Int {
        phrase.split { $0.isWhitespace }.filter { $0.contains { $0.isLetter || $0.isNumber } }.count
    }

    public static func pool(for trigger: BubbleTrigger) -> [String] {
        switch trigger {
        case .notice: ["Ага, беру", "Берусь", "Сейчас сделаю", "Так-так, смотрю"]
        case .think: ["Хмм…", "Думаю…", "Дай подумать…", "Прикидываю…"]
        case .workRead: ["Читаю…", "Изучаю…", "Вчитываюсь…"]
        case .workEditCode: ["Пишу…", "Правлю…", "Дописываю…"]
        case .workEditFigma: ["Рисую…", "Двигаю слои…", "Леплю макет…"]
        case .workRun: ["Запускаю…", "Проверяю…", "Гоняю…"]
        case .workSearch: ["Ищу…", "Сейчас найду…", "Выясняю…"]
        case .step: ["Есть", "Так, дальше…", "Одно готово"]
        case .waitPermission: ["Можно?", "Разрешишь?", "Мне можно?"]
        case .waitInput: ["Глянешь?", "Я жду тебя", "Ты тут?"]
        case .done: ["Готово, проверь", "У меня готово", "Принимай работу", "Вот, держи"]
        case .error: ["Упс…", "У меня не вышло", "Что-то не то"]
        case .fallAsleep: ["Вздремну", "Я подремлю"]
        case .hoverSleep: ["Привет", "Я тут"]
        case .line: []
        }
    }
}
