import Foundation

/// Тема новости. Дизайн — главная: большая часть рассказанного **[решение]**; остальное — для разнообразия.
public enum NewsTopic: String, Sendable, Codable, CaseIterable {
    case design, it, economy, science

    public var title: String {
        switch self {
        case .design: "Новости дизайна"
        case .it: "Новости ИТ"
        case .economy: "Экономика"
        case .science: "Наука"
        }
    }

    /// Заход перед сутью — от себя и без рода.
    public var leadIns: [String] {
        switch self {
        case .design: ["Смотри, что нашлось", "Я тут читаю новости", "О, свежее из дизайна", "Интересное попалось"]
        case .it: ["Что нового в технологиях", "Из мира ИТ", "Технологии не стоят на месте"]
        case .economy: ["Про деньги и рынки", "Новости экономики", "Из мира экономики"]
        case .science: ["Новость из науки", "Учёные снова удивляют", "Наука, смотри"]
        }
    }
}

/// Новость из публичной ленты или открытого Telegram-канала.
public struct NewsItem: Sendable, Equatable, Codable {
    public var title: String
    public var link: String
    public var source: String
    public var date: Date?
    /// Суть новости простыми словами — показывается в облачке вместо заголовка.
    public var gist: String
    public var topic: NewsTopic

    public init(title: String, link: String, source: String, date: Date?, gist: String? = nil, topic: NewsTopic = .design) {
        self.title = title
        self.link = link
        self.source = source
        self.date = date
        self.gist = gist ?? NewsGist.clip(title)
        self.topic = topic
    }

    enum CodingKeys: String, CodingKey { case title, link, source, date, gist, topic }

    /// Старый `news.json` без темы — это дизайн.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        link = try c.decode(String.self, forKey: .link)
        source = try c.decode(String.self, forKey: .source)
        date = try c.decodeIfPresent(Date.self, forKey: .date)
        gist = try c.decode(String.self, forKey: .gist)
        topic = try c.decodeIfPresent(NewsTopic.self, forKey: .topic) ?? .design
    }

    /// Облачко: суть новости, а не заголовок.
    public var teaser: String { gist }

    /// Рассказывать стоит: есть внятная суть, это не реклама, курс или вакансия.
    public var isTellable: Bool {
        !gist.hasSuffix("…") && NewsGist.words(gist).count >= NewsGist.minWords && !NewsGist.isWeak(gist) && !NewsFeeds.isPromo(self) && !NewsFeeds.isGrim(self)
    }
}

/// Как маскот подводит к новости — своими словами, от первого лица и без рода («нашлось», а не «нашёл»).
public enum NewsVoice {
    public static let leadIns = NewsTopic.design.leadIns
    public static var allLeadIns: [String] { NewsTopic.allCases.flatMap(\.leadIns) }
}

/// Суть новости из анонса — без внешних сервисов: пропускаем вступления («Привет, Хабр! Меня зовут…»),
/// берём самое короткое законченное содержательное предложение; если все длинные — первую смысловую часть.
public enum NewsGist {
    /// Новость — не реплика: суть почти никогда не влезает в 10 слов, 14 — три строки облачка.
    public static let maxWords = 14
    static let minWords = 4
    /// Облачко 220 pt × 4 строки — около 120 знаков; суть держим в 90, чтобы читалась с одного взгляда.
    public static let maxChars = 90

    static let introMarkers = ["привет", "всем привет", "меня зовут", "на связи", "tl;dr", "hello", "добрый день", "в этой статье"]

    /// `preferTitle` — у новостных лент и Telegram заголовок (первая строка) и есть суть по-человечески;
    /// у статей заголовок часто кликбейт, и суть ищется в анонсе.
    public static func make(title: String, description: String, preferTitle: Bool = false) -> String {
        if preferTitle {
            let head = headline(title)
            // Длинный заголовок — его первая часть до двоеточия или тире, если она сама по себе мысль.
            let parts = [head] + [": ", " — ", " – ", ". "].compactMap { separator in
                head.range(of: separator).map { String(head[..<$0.lowerBound]) }
            }
            if let good = parts.first(where: { fits($0) && !isWeak($0) && !isIntro($0) && !$0.hasSuffix("?") }) {
                return humanize(good)
            }
        }
        return humanize(pick(title: title, description: description))
    }

    /// Заголовок без газетных приёмов: «Котяков: МРОТ вырастет» → «МРОТ вырастет»; без «[Перевод]» и «(видео)».
    static func headline(_ title: String) -> String {
        var value = clean(title)
        value = value.replacingOccurrences(of: "^\\[[^\\]]+\\]\\s*", with: "", options: .regularExpression)
        // «Госзаказ учится на предписаниях // ФАС отчиталась…» — рубрика до «//».
        if let slashes = value.range(of: " // ") { value = String(value[..<slashes.lowerBound]) }
        value = value.replacingOccurrences(of: "\\s*\\((видео|фото|опрос|обновлено)\\)", with: "", options: [.regularExpression, .caseInsensitive])
        // Цитата-заголовок: до двух слов с большой буквы и двоеточие — кто сказал, а не что случилось.
        if let colon = value.range(of: ": "), words(String(value[..<colon.lowerBound])).count <= 2,
           value.first?.isUppercase == true {
            let rest = String(value[colon.upperBound...])
            if words(rest).count >= minWords { value = rest.prefix(1).uppercased() + rest.dropFirst() }
        }
        return value.trimmingCharacters(in: .whitespaces)
    }

    static func fits(_ text: String) -> Bool {
        (minWords...maxWords).contains(words(text).count) && text.count <= maxChars
    }

    static func pick(title: String, description: String) -> String {
        let sentences = Self.sentences(clean(description)).filter { !isIntro($0) }.map(dropFiller)
        // Рассказ от первого лица и придаточные — слабая суть; тогда заголовок, он часто сам и есть мысль.
        let candidates = Array(sentences.prefix(3)).filter { !isWeak($0) }
        if let fitting = candidates.first(where: fits) {
            return fitting
        }
        if let first = candidates.first {
            // Первая смысловая часть: до двоеточия или тире — если она сама по себе мысль. По запятой рвётся на обрывки.
            for separator in [": ", " — ", " – ", " - "] {
                if let range = first.range(of: separator) {
                    let head = String(first[..<range.lowerBound])
                    if fits(head), !isWeak(head) { return head }
                }
            }
        }
        if words(title).count <= maxWords, title.count <= maxChars { return title }
        return clip(candidates.first ?? title)
    }

    /// Заголовок-вопрос — пересказом: «Как мы делали X» → «Тут рассказывают, как делали X».
    static func retell(title: String) -> String {
        let plain = title.trimmingCharacters(in: CharacterSet(charactersIn: "?!. "))
        let lowered = plain.lowercased()
        let frames: [(String, String)] = [
            ("как мы ", "Тут рассказывают, как "), ("как я ", "Тут рассказывают, как "),
            ("как ", "Тут разбирают, как "), ("почему ", "Тут объясняют, почему "),
            ("зачем ", "Тут объясняют, зачем "), ("что такое ", "Тут объясняют, что такое "),
        ]
        for (prefix, frame) in frames where lowered.hasPrefix(prefix) {
            let rest = plain.dropFirst(prefix.count)
            // «Как сделать…», «Как мы делали…» — да; «Как тебе такое» — не разбор, а возглас.
            if prefix == "как ", let verb = words(String(rest)).first?.lowercased(),
               !["ть", "ться", "чь", "ти"].contains(where: { verb.hasSuffix($0) }) {
                return plain
            }
            return frame + rest
        }
        return plain
    }

    /// Канцелярит → разговорный: «является» → «это», «в настоящее время» → «сейчас». Без точки в конце — это реплика.
    static let plainWords: [(String, String)] = [
        ("в настоящее время", "сейчас"), ("на сегодняшний день", "сейчас"), ("представляет собой", "это"),
        ("является", "это"), ("являются", "это"), ("с целью", "чтобы"), ("в рамках", "в"), ("данный", "этот"),
        ("данная", "эта"), ("данное", "это"), ("осуществляет", "делает"), ("осуществлять", "делать"),
        ("необходимо", "нужно"), ("в случае если", "если"), ("на основе", "по"),
    ]

    static func humanize(_ text: String) -> String {
        let text = text.replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "^\\[[^\\]]+\\]\\s*", with: "", options: .regularExpression)
            .replacingOccurrences(of: " ,", with: ",")
        var value = retell(title: text)
        if value.count > maxChars { value = text }
        value = value.replacingOccurrences(of: "\\s*\\([^)]*\\)", with: "", options: .regularExpression)
        for (formal, plain) in plainWords {
            value = value.replacingOccurrences(of: " \(formal) ", with: " \(plain) ")
        }
        value = value.replacingOccurrences(of: "\u{FE0F}", with: "").trimmingCharacters(in: .whitespaces)
        if value.hasSuffix("."), !value.hasSuffix("..") { value.removeLast() }
        return value
    }

    static let weakStarts = ["когда ", "если ", "чтобы ", "хотя ", "пока ", "после того", "в этой ", "в сегодняшнем ", "сегодня ", "недавно ", "я ", "мы ", "хотелось", "хочется ",
        // Разговорные заходы и куски истории — не суть.
        "ну ", "теперь ", "итак", "так ли", "представ", "давайте", "часть ", "в первой", "в прошлой", "в предыдущей",
        "решил", "«", "\"", "вот ", "и вот",
        // Ссылки на соседний текст: без него непонятно, о ком и о чём.
        "его ", "ее ", "её ", "их ", "им ", "это ", "этот ", "эта ", "эти ", "об этом", "такая ", "такой ", "такие ", "там ",
        "тогда ", "при этом", "однако", "но ", "и ", "а ", "также", "кроме того", "в той", "в таком", "в этом", "мера ",
        "источник", "фото", "—", "–", "- ", "в посте", "даты ", "он ", "она ", "они ", "на это", "за это время", "ждём ", "ждем ", "как тебе",
    ]
    /// Рассказ автора о себе и обещания «расскажу» — тоже не суть.
    static let personalWords = ["расскажу", "покажу", "разберу", "давайте", "моих", "мой ", "моя ", "моё ", "мне ", "мою ", "моей ", "моём ", "моем "]
    static let fillers = ["Кажется, ", "Итак, ", "Короче, ", "Как известно, "]

    static func isWeak(_ sentence: String) -> Bool {
        let lowered = sentence.lowercased()
        if weakStarts.contains(where: { lowered.hasPrefix($0) }) { return true }
        if lowered.first?.isNumber == true { return true }
        // Оборванная мысль: «Вновь копаем в самое интересное:», «Поговорим про цвета,».
        if let last = lowered.last, ":,;—".contains(last) { return true }
        if personalWords.contains(where: { lowered.contains($0) }) { return true }
        // Рассказ о себе: «я работаю», «мы сделали» в первой половине предложения.
        let head = lowered.prefix(max(20, lowered.count / 2))
        return [" я ", " мы ", " меня ", " нас "].contains { head.contains($0) }
    }

    static func dropFiller(_ sentence: String) -> String {
        for filler in fillers where sentence.hasPrefix(filler) {
            let rest = sentence.dropFirst(filler.count)
            return rest.prefix(1).uppercased() + rest.dropFirst()
        }
        return sentence
    }

    static func clean(_ text: String) -> String {
        var value = text.replacingOccurrences(of: "<br\\s*/?>", with: ". ", options: .regularExpression)
        value = value.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        // Telegram и новостные ленты: ссылки, хэштеги, упоминания, эмодзи, служебные хвосты.
        value = value.replacingOccurrences(of: "https?://\\S+", with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: "[#@][\\w_]+", with: " ", options: .regularExpression)
        value = String(value.unicodeScalars.filter { !($0.properties.isEmojiPresentation || ($0.properties.isEmoji && $0.value > 0x2000)) || $0.value == 0x2014 }.map(Character.init))
        for tail in ["Подробнее:", "Подробнее", "Регистрация по ссылке:", "Читать полностью", "Источник:", "Подписаться"] {
            value = value.replacingOccurrences(of: tail, with: " ")
        }
        value = value.replacingOccurrences(of: "^(Срочно|Молния|Главное|Важно)\\s*[:.!—-]+\\s*", with: "", options: .regularExpression)
        for (entity, char) in ["&nbsp;": " ", "&amp;": "&", "&quot;": "\"", "&laquo;": "«", "&raquo;": "»", "&mdash;": "—", "&#39;": "'", "&lt;": "<", "&gt;": ">"] {
            value = value.replacingOccurrences(of: entity, with: char)
        }
        for tail in ["Читать далее", "Читать дальше", "Read more"] {
            value = value.replacingOccurrences(of: tail, with: "")
        }
        value = value.replacingOccurrences(of: "TL;DR.", with: "")
        value = value.replacingOccurrences(of: "\u{FE0F}", with: "")
        return value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }

    static func sentences(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        let chars = Array(text)
        for (index, char) in chars.enumerated() {
            current.append(char)
            let end = ".!?…".contains(char)
            let next = index + 1 < chars.count ? chars[index + 1] : " "
            if end, next == " " || next == "\n" {
                let sentence = current.trimmingCharacters(in: .whitespaces)
                if !sentence.isEmpty { result.append(sentence) }
                current = ""
            }
        }
        let rest = current.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { result.append(rest) }
        return result
    }

    static func isIntro(_ sentence: String) -> Bool {
        let lowered = sentence.lowercased()
        return introMarkers.contains { lowered.hasPrefix($0) || lowered.contains("меня зовут") }
            || words(sentence).count < 3
    }

    public static func words(_ text: String) -> [Substring] {
        text.split(whereSeparator: \.isWhitespace)
    }

    public static func clip(_ text: String) -> String {
        let all = words(text)
        return all.count <= maxWords ? all.joined(separator: " ") : all.prefix(maxWords).joined(separator: " ") + "…"
    }
}

/// Источники новостей — только русскоязычные **[решение]**: публичные RSS и открытые Telegram-каналы
/// (веб-версия `t.me/s/…`, без аккаунта и ключей). Запросы не несут никаких данных пользователя.
public enum NewsFeeds {
    public enum Format: Sendable { case rss, telegram }

    public struct Feed: Sendable {
        public let name: String
        public let url: URL
        public let topic: NewsTopic
        public let format: Format
        /// Лента шире темы — берём только статьи по теме.
        public let needsTopicFilter: Bool
        /// Новостная лента: заголовок и есть суть. У статей — суть из анонса.
        public let headlines: Bool

        static func rss(_ name: String, _ url: String, _ topic: NewsTopic, filter: Bool = false, headlines: Bool = false) -> Feed {
            Feed(name: name, url: URL(string: url)!, topic: topic, format: .rss, needsTopicFilter: filter, headlines: headlines)
        }

        /// В Telegram первая строка поста — почти всегда заголовок.
        static func telegram(_ name: String, _ channel: String, _ topic: NewsTopic, filter: Bool = false) -> Feed {
            Feed(name: name, url: URL(string: "https://t.me/s/\(channel)")!, topic: topic, format: .telegram, needsTopicFilter: filter, headlines: true)
        }
    }

    public static let all: [Feed] = [
        // Дизайн — большая часть источников и рассказанного.
        .rss("Хабр · Интерфейсы", "https://habr.com/ru/rss/hubs/ui/articles/", .design),
        .rss("Хабр · Дизайн", "https://habr.com/ru/rss/hubs/design/articles/", .design, filter: true),
        .rss("Хабр · Веб-дизайн", "https://habr.com/ru/rss/hubs/web_design/articles/", .design),
        .rss("Хабр · Юзабилити", "https://habr.com/ru/rss/hubs/usability/articles/", .design),
        .rss("Хабр · Типографика", "https://habr.com/ru/rss/hubs/typography/articles/", .design),
        .rss("Хабр · Доступность", "https://habr.com/ru/rss/hubs/accessibility/articles/", .design),
        .rss("Дизайн-кабак", "https://designpub.ru/feed", .design),
        .rss("Sostav", "https://www.sostav.ru/rss", .design, filter: true, headlines: true),
        .rss("Cossa", "https://www.cossa.ru/rss/", .design, filter: true, headlines: true),
        .telegram("UX Notes", "uxnotes", .design),
        .telegram("Figma", "figma_ru", .design),
        .telegram("Ozon Design", "ozondesign", .design, filter: true),
        // ИТ.
        .rss("Хабр · Новости", "https://habr.com/ru/rss/news/", .it, headlines: true),
        .rss("3DNews", "https://3dnews.ru/news/rss/", .it, headlines: true),
        .rss("iXBT", "https://www.ixbt.com/export/news.rss", .it, headlines: true),
        .telegram("Техномедиа", "techmedia", .it),
        // Экономика.
        .rss("Ведомости · Экономика", "https://www.vedomosti.ru/rss/rubric/economics", .economy, headlines: true),
        .rss("Коммерсантъ · Экономика", "https://www.kommersant.ru/RSS/section-economics.xml", .economy, headlines: true),
        .telegram("The Bell", "thebell_io", .economy),
        // Наука.
        .rss("N + 1", "https://nplus1.ru/rss", .science, headlines: true),
        .rss("Naked Science", "https://naked-science.ru/feed", .science, headlines: true),
        .rss("Популярная механика", "https://www.popmech.ru/out/public-all.xml", .science, headlines: true),
    ]

    static let topicWords = [
        "дизайн", "интерфейс", "ux", "ui", "макет", "figma", "фигм", "типограф", "шрифт", "логотип", "бренд",
        "иконк", "экран", "прототип", "пользовател", "верстк", "анимац", "визуал", "цвет", "кнопк", "айдентик",
        "иллюстрац", "упаковк", "редизайн",
    ]

    public static func isOnTopic(_ item: NewsItem) -> Bool {
        let text = (item.title + " " + item.gist).lowercased()
        return topicWords.contains { text.contains($0) }
    }

    /// Реклама, курсы, вакансии и подборки — не новость.
    static let promoWords = [
        "вебинар", "курс ", "курсы", "скидк", "промокод", "ваканси", "розыгрыш", "реклам", "партнёрск", "партнерск",
        "дайджест", "регистрац", "интенсив", "марафон", "мы ищем", "в команду", "erid", "повышение цены",
        // Викторины и тесты на внимательность.
        "сможете ли", "ответ раскроет", "головоломк", "проверьте себя", "только гений", "найдите ", "тест:", "тест на",
        "попробуйте найти", "отличия между", "челлендж", "тест-",
    ]

    public static func isPromo(_ item: NewsItem) -> Bool {
        let text = (item.title + " " + item.gist).lowercased()
        return promoWords.contains { text.contains($0) }
    }

    /// Тяжёлые темы маскот не пересказывает: он для настроения, а не для тревоги.
    static let grimWords = [
        "погиб", "убит", "убий", "смерт", "умер", "теракт", "взрыв", "атак", "обстрел", "ракет", "беспилотник", "дрон",
        "войн", "сво ", "всу", "мобилиз", "катастроф", "крушени", "пострадав", "жертв", "заложник", "насили", "задержан",
        "арест", "приговор", "санкци", "удар", "путин", "кремл", "допрос", "уголовн", "обыск", "силовик",
    ]

    public static func isGrim(_ item: NewsItem) -> Bool {
        let text = " " + (item.title + " " + item.gist).lowercased() + " "
        return grimWords.contains { text.contains($0) }
    }

    public static func filter(_ items: [NewsItem], feed: Feed) -> [NewsItem] {
        (feed.needsTopicFilter ? items.filter(isOnTopic) : items).filter(\.isTellable)
    }

    public static func parse(_ data: Data, feed: Feed) -> [NewsItem] {
        switch feed.format {
        case .rss: FeedParser.parse(data, source: feed.name, topic: feed.topic, headlines: feed.headlines)
        case .telegram: TelegramParser.parse(data, source: feed.name, topic: feed.topic)
        }
    }
}

/// Открытый Telegram-канал (`t.me/s/канал`) → новости. Заголовок — первая строка поста, суть — из всего текста.
public enum TelegramParser {
    public static func parse(_ data: Data, source: String, topic: NewsTopic) -> [NewsItem] {
        guard let html = String(data: data, encoding: .utf8) else { return [] }
        var items: [NewsItem] = []
        // Каждый пост — блок `tgme_widget_message` с `data-post="канал/123"`.
        for block in html.components(separatedBy: "tgme_widget_message_wrap").dropFirst() {
            guard
                let post = capture(block, #"data-post="([^"]+)""#),
                let raw = capture(block, #"tgme_widget_message_text[^>]*>([\s\S]*?)</div>"#)
            else { continue }
            let text = NewsGist.clean(raw)
            let firstLine = raw.components(separatedBy: "<br").first.map(NewsGist.clean) ?? text
            guard NewsGist.words(text).count >= NewsGist.minWords else { continue }
            let title = NewsGist.words(firstLine).count >= 3 ? firstLine : NewsGist.clip(text)
            let rest = text.hasPrefix(firstLine) ? String(text.dropFirst(firstLine.count)) : text
            let date = capture(block, #"datetime="([^"]+)""#).flatMap(FeedParser.date)
            items.append(NewsItem(
                title: NewsGist.clip(title), link: "https://t.me/\(post)", source: source, date: date,
                gist: NewsGist.make(title: title, description: rest, preferTitle: true), topic: topic
            ))
        }
        return Array(items.suffix(FeedParser.maxItems))
    }

    static func capture(_ text: String, _ pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}

/// RSS 2.0 и Atom → новости. Берём только заголовок, ссылку и дату.
public final class FeedParser: NSObject, XMLParserDelegate {
    public static let maxItems = 30

    private let source: String
    private let topic: NewsTopic
    private let headlines: Bool
    private var items: [NewsItem] = []
    private var inItem = false
    private var element = ""
    private var title = ""
    private var link = ""
    private var dateText = ""
    private var summary = ""

    private init(source: String, topic: NewsTopic, headlines: Bool) {
        self.source = source
        self.topic = topic
        self.headlines = headlines
    }

    public static func parse(_ data: Data, source: String, topic: NewsTopic = .design, headlines: Bool = false) -> [NewsItem] {
        let delegate = FeedParser(source: source, topic: topic, headlines: headlines)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.items
    }

    public func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        if name == "item" || name == "entry" {
            inItem = true
            title = ""
            link = ""
            dateText = ""
            summary = ""
        }
        element = name
        // Atom: <link href="…" rel="alternate"/>.
        if inItem, name == "link", let href = attributes["href"], link.isEmpty, (attributes["rel"] ?? "alternate") == "alternate" {
            link = href
        }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inItem else { return }
        switch element {
        case "title": title += string
        case "link": link += string
        case "pubDate", "published", "updated", "dc:date": if dateText.isEmpty || element == "pubDate" { dateText += string }
        case "description", "summary", "content:encoded", "content": if summary.count < 4000 { summary += string }
        default: break
        }
    }

    public func parser(_ parser: XMLParser, foundCDATA block: Data) {
        guard inItem, let text = String(data: block, encoding: .utf8) else { return }
        switch element {
        case "title": title += text
        case "description", "summary", "content:encoded", "content": if summary.count < 4000 { summary += text }
        default: break
        }
    }

    public func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "item" || name == "entry" {
            inItem = false
            let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
            let cleanLink = link.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanTitle.isEmpty, cleanLink.hasPrefix("http") {
                items.append(NewsItem(
                    title: cleanTitle, link: cleanLink, source: source, date: Self.date(dateText),
                    gist: NewsGist.make(title: cleanTitle, description: summary, preferTitle: headlines), topic: topic
                ))
            }
            if items.count >= Self.maxItems { parser.abortParsing() }
        }
        element = ""
    }

    static func date(_ text: String) -> Date? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if let iso = ISO8601DateFormatter().date(from: value) { return iso }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let iso = fractional.date(from: value) { return iso }
        let rfc = DateFormatter()
        rfc.locale = Locale(identifier: "en_US_POSIX")
        for format in ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss zzz", "EEE, d MMM yyyy HH:mm:ss Z"] {
            rfc.dateFormat = format
            if let date = rfc.date(from: value) { return date }
        }
        return nil
    }
}

/// Какие новости уже показаны (локально) и какую рассказать следующей.
public struct NewsDesk: Sendable, Codable {
    public static let maxAge: TimeInterval = 3 * 86_400
    public static let seenLimit = 500

    public private(set) var seen: [String] = []
    public private(set) var items: [NewsItem] = []

    public init() {}

    /// Одна статья из двух лент — одна новость.
    public mutating func update(_ fresh: [NewsItem]) {
        var links: Set<String> = []
        items = fresh.filter { links.insert($0.link).inserted }
    }

    /// Свежие (до трёх дней) и ещё не показанные; новые сначала.
    public func available(now: Date) -> [NewsItem] {
        let seenSet = Set(seen)
        return items
            .filter { !seenSet.contains($0.link) && ($0.date.map { now.timeIntervalSince($0) < Self.maxAge } ?? false) }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// Доля дизайна среди рассказанного **[решение]**: остальное — ИТ, экономика, наука по очереди.
    public static let designShare = 0.65

    /// Взять следующую новость и запомнить как показанную. Тема: дизайн с вероятностью `designShare`
    /// (`roll` — случайное 0…1), иначе другая тема — не та, что была последней. Источники чередуются.
    public mutating func take(now: Date, lastSource: String? = nil, lastTopic: NewsTopic? = nil, roll: Double = .random(in: 0..<1)) -> NewsItem? {
        let fresh = available(now: now)
        let design = fresh.filter { $0.topic == .design }
        let others = fresh.filter { $0.topic != .design }
        let preferred = others.filter { $0.topic != lastTopic }
        let pool: [NewsItem] = if roll < Self.designShare, !design.isEmpty {
            design
        } else if !preferred.isEmpty {
            preferred
        } else if !others.isEmpty {
            others
        } else {
            design
        }
        guard let item = pool.first(where: { $0.source != lastSource }) ?? pool.first else { return nil }
        seen.append(item.link)
        if seen.count > Self.seenLimit { seen.removeFirst(seen.count - Self.seenLimit) }
        return item
    }

    public static var defaultURL: URL {
        PulsePaths.supportDirectory.appending(path: "news.json")
    }

    public static func load(from url: URL = defaultURL) -> NewsDesk {
        guard let data = try? Data(contentsOf: url), let desk = try? JSONDecoder().decode(NewsDesk.self, from: data) else {
            return NewsDesk()
        }
        return desk
    }

    public func save(to url: URL = defaultURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}
