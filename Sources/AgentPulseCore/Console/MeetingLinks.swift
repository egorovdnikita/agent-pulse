import Foundation

public enum MeetingService: String, Sendable, Codable, CaseIterable {
    case zoom, meet, teams, telemost

    public var title: String {
        switch self {
        case .zoom: "Zoom"
        case .meet: "Google Meet"
        case .teams: "Teams"
        case .telemost: "Телемост"
        }
    }
}

public struct MeetingLink: Sendable, Equatable {
    public var service: MeetingService
    public var url: URL

    public init(service: MeetingService, url: URL) {
        self.service = service
        self.url = url
    }
}

/// Ссылка на звонок из URL, места и заметок события. Только чтение: события не меняются.
public enum MeetingLinks {
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// Порядок важен: поле URL надёжнее места, место надёжнее заметок.
    public static func find(url: URL?, location: String?, notes: String?) -> MeetingLink? {
        if let url, let link = classify(url) { return link }
        for text in [location, notes] {
            guard let text, !text.isEmpty else { continue }
            if let link = links(in: text).lazy.compactMap(classify).first { return link }
        }
        return nil
    }

    static func links(in text: String) -> [URL] {
        let range = NSRange(text.startIndex..., in: text)
        var found = detector?.matches(in: text, range: range).compactMap(\.url) ?? []
        // NSDataDetector не считает ссылкой схему zoommtg и адрес без https.
        for word in text.split(whereSeparator: { $0.isWhitespace || "<>()\"'".contains($0) }) {
            let lower = word.lowercased()
            if lower.hasPrefix("zoommtg://") || lower.hasPrefix("meet.google.com/") || lower.hasPrefix("telemost.yandex.") {
                let plain = lower.hasPrefix("zoommtg://") ? String(word) : "https://\(word)"
                if let url = URL(string: plain) { found.append(url) }
            }
        }
        return found
    }

    public static func classify(_ url: URL) -> MeetingLink? {
        let url = unwrapped(url)
        guard let host = url.host?.lowercased() else { return nil }
        let path = url.path.lowercased()
        if url.scheme?.lowercased() == "zoommtg" { return MeetingLink(service: .zoom, url: url) }
        if host == "zoom.us" || host.hasSuffix(".zoom.us") || host.hasSuffix(".zoomgov.com") {
            return ["/j/", "/my/", "/w/", "/s/", "/wc/"].contains(where: path.hasPrefix) ? MeetingLink(service: .zoom, url: url) : nil
        }
        if host == "meet.google.com" {
            return path.count > 1 && !path.hasPrefix("/_") ? MeetingLink(service: .meet, url: url) : nil
        }
        if host == "teams.microsoft.com" || host == "teams.live.com" || host == "teams.microsoft.us" {
            let meeting = path.hasPrefix("/l/meetup-join") || path.hasPrefix("/meet/") || path.hasPrefix("/v2/")
            return meeting ? MeetingLink(service: .teams, url: url) : nil
        }
        if host.hasPrefix("telemost.") && host.contains("yandex.") {
            return path.hasPrefix("/j/") ? MeetingLink(service: .telemost, url: url) : nil
        }
        return nil
    }

    /// Почтовые обёртки Outlook и Google прячут настоящую ссылку в параметре.
    static func unwrapped(_ url: URL) -> URL {
        guard let host = url.host?.lowercased(),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return url }
        let key: String? = if host.hasSuffix("safelinks.protection.outlook.com") { "url" }
            else if host == "www.google.com" || host == "google.com", url.path == "/url" { "q" }
            else { nil }
        guard let key, let inner = items.first(where: { $0.name == key })?.value, let real = URL(string: inner) else { return url }
        return real
    }
}
