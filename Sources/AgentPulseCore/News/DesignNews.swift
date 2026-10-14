import Foundation

/// Новость о UI/UX-дизайне из публичной ленты.
public struct NewsItem: Sendable, Equatable, Codable {
    public var title: String
    public var link: String
    public var source: String
    public var date: Date?
    /// Суть новости простыми словами — показывается в облачке вместо заголовка.
    public var gist: String

    public init(title: String, link: String, source: String, date: Date?, gist: String? = nil) {
        self.title = title
        self.link = link
        self.source = source
        self.date = date
        self.gist = gist ?? NewsGist.clip(title)
    }

    /// Облачко: суть новости, а не заголовок.
    public var teaser: String { gist }
}

/// Суть новости из анонса — без внешних сервисов: пропускаем вступления («Привет, Хабр! Меня зовут…»),
/// берём самое короткое законченное содержательное предложение; если все длинные — первую смысловую часть.
public enum NewsGist {
    /// Новость — не реплика: суть почти никогда не влезает в 10 слов, 14 — три строки облачка.
    public static let maxWords = 14
    static let minWords = 4

    static let introMarkers = ["привет", "всем привет", "меня зовут", "на связи", "tl;dr", "hello", "добрый день", "в этой статье"]

    public static func make(title: String, description: String) -> String {
        let sentences = Self.sentences(clean(description)).filter { !isIntro($0) }.map(dropFiller)
        // Рассказ от первого лица и придаточные — слабая суть; тогда заголовок, он часто сам и есть мысль.
        let candidates = Array(sentences.prefix(3)).filter { !isWeak($0) }
        if let fitting = candidates.first(where: { (minWords...maxWords).contains(words($0).count) }) {
            return fitting
        }
        if let first = candidates.first {
            // Первая смысловая часть: до двоеточия, тире или запятой — если она сама по себе мысль.
            for separator in [": ", " — ", " – ", " - ", ", "] {
                if let range = first.range(of: separator) {
                    let head = String(first[..<range.lowerBound])
                    if (minWords...maxWords).contains(words(head).count), !isWeak(head) { return head }
                }
            }
        }
        if words(title).count <= maxWords { return title }
        return clip(candidates.first ?? title)
    }

    static let weakStarts = ["когда ", "если ", "чтобы ", "хотя ", "пока ", "после того", "в этой ", "в сегодняшнем ", "сегодня ", "недавно ", "я ", "мы ", "хотелось", "хочется "]
    static let fillers = ["Кажется, ", "Итак, ", "Короче, ", "Как известно, "]

    static func isWeak(_ sentence: String) -> Bool {
        let lowered = sentence.lowercased()
        if weakStarts.contains(where: { lowered.hasPrefix($0) }) { return true }
        if lowered.first?.isNumber == true { return true }
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
        var value = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (entity, char) in ["&nbsp;": " ", "&amp;": "&", "&quot;": "\"", "&laquo;": "«", "&raquo;": "»", "&mdash;": "—", "&#39;": "'", "&lt;": "<", "&gt;": ">"] {
            value = value.replacingOccurrences(of: entity, with: char)
        }
        for tail in ["Читать далее", "Читать дальше", "Read more"] {
            value = value.replacingOccurrences(of: tail, with: "")
        }
        value = value.replacingOccurrences(of: "TL;DR.", with: "")
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

    static func words(_ text: String) -> [Substring] {
        text.split(whereSeparator: \.isWhitespace)
    }

    public static func clip(_ text: String) -> String {
        let all = words(text)
        return all.count <= maxWords ? all.joined(separator: " ") : all.prefix(maxWords).joined(separator: " ") + "…"
    }
}

/// Русские ленты о UI/UX-дизайне **[решение]**. Только публичные RSS; запросы не несут никаких данных пользователя.
public enum DesignFeeds {
    public struct Feed: Sendable {
        public let name: String
        public let url: URL
        /// Лента шире дизайна интерфейсов — берём только статьи по теме.
        public let needsTopicFilter: Bool
    }

    public static let all: [Feed] = [
        Feed(name: "Хабр · Интерфейсы", url: URL(string: "https://habr.com/ru/rss/hubs/ui/articles/")!, needsTopicFilter: false),
        Feed(name: "Хабр · Дизайн", url: URL(string: "https://habr.com/ru/rss/hubs/design/articles/")!, needsTopicFilter: true),
        Feed(name: "Дизайн-кабак", url: URL(string: "https://designpub.ru/feed")!, needsTopicFilter: false),
    ]

    static let topicWords = [
        "дизайн", "интерфейс", "ux", "ui", "макет", "figma", "фигм", "типограф", "шрифт", "логотип", "бренд",
        "иконк", "экран", "прототип", "пользовател", "верстк", "анимац", "визуал", "цвет", "кнопк",
    ]

    public static func isOnTopic(_ item: NewsItem) -> Bool {
        let text = (item.title + " " + item.gist).lowercased()
        return topicWords.contains { text.contains($0) }
    }

    public static func filter(_ items: [NewsItem], feed: Feed) -> [NewsItem] {
        feed.needsTopicFilter ? items.filter(isOnTopic) : items
    }
}

/// RSS 2.0 и Atom → новости. Берём только заголовок, ссылку и дату.
public final class FeedParser: NSObject, XMLParserDelegate {
    public static let maxItems = 30

    private let source: String
    private var items: [NewsItem] = []
    private var inItem = false
    private var element = ""
    private var title = ""
    private var link = ""
    private var dateText = ""
    private var summary = ""

    private init(source: String) {
        self.source = source
    }

    public static func parse(_ data: Data, source: String) -> [NewsItem] {
        let delegate = FeedParser(source: source)
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
                    gist: NewsGist.make(title: cleanTitle, description: summary)
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

    /// Взять следующую новость и запомнить как показанную. Источники чередуются: не две подряд из одного.
    public mutating func take(now: Date, lastSource: String? = nil) -> NewsItem? {
        let fresh = available(now: now)
        guard let item = fresh.first(where: { $0.source != lastSource }) ?? fresh.first else { return nil }
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
