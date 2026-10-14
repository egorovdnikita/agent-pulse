import Foundation

/// Новость о UI/UX-дизайне из публичной ленты.
public struct NewsItem: Sendable, Equatable, Codable {
    public var title: String
    public var link: String
    public var source: String
    public var date: Date?

    public init(title: String, link: String, source: String, date: Date?) {
        self.title = title
        self.link = link
        self.source = source
        self.date = date
    }

    /// Облачко: «Источник: заголовок», не больше 10 слов — длиннее обрезается «…».
    public var teaser: String {
        let words = "\(source): \(title)".split(whereSeparator: \.isWhitespace)
        let limit = Phrases.maxWords
        return words.count <= limit ? words.joined(separator: " ") : words.prefix(limit).joined(separator: " ") + "…"
    }
}

/// Ленты о UI/UX-дизайне. Только публичные RSS/Atom; запросы не несут никаких данных пользователя.
public enum DesignFeeds {
    public struct Feed: Sendable {
        public let name: String
        public let url: URL
    }

    public static let all: [Feed] = [
        Feed(name: "Smashing", url: URL(string: "https://www.smashingmagazine.com/feed/")!),
        Feed(name: "NN/g", url: URL(string: "https://www.nngroup.com/feed/rss/")!),
        Feed(name: "UX Collective", url: URL(string: "https://uxdesign.cc/feed")!),
        Feed(name: "Sidebar", url: URL(string: "https://sidebar.io/feed.xml")!),
        Feed(name: "Figma", url: URL(string: "https://www.figma.com/blog/feed/atom.xml")!),
        Feed(name: "A List Apart", url: URL(string: "https://alistapart.com/main/feed/")!),
        Feed(name: "UX Planet", url: URL(string: "https://uxplanet.org/feed")!),
    ]
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
        default: break
        }
    }

    public func parser(_ parser: XMLParser, foundCDATA block: Data) {
        guard inItem, element == "title", let text = String(data: block, encoding: .utf8) else { return }
        title += text
    }

    public func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "item" || name == "entry" {
            inItem = false
            let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
            let cleanLink = link.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanTitle.isEmpty, cleanLink.hasPrefix("http") {
                items.append(NewsItem(title: cleanTitle, link: cleanLink, source: source, date: Self.date(dateText)))
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

    public mutating func update(_ fresh: [NewsItem]) {
        items = fresh
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
