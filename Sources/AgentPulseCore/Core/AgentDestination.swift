import Foundation

/// Адрес строится только для известного веб-источника из уже полученного id сессии.
public enum AgentDestination {
    public static func webURL(source: AgentEvent.Source, sessionID: String) -> URL? {
        let host: String
        let path: String
        if source == .claudeChat, sessionID.hasPrefix("claude-"), let id = UUID(uuidString: String(sessionID.dropFirst(7))) {
            host = "claude.ai"
            path = "/chat/" + id.uuidString.lowercased()
        } else if source == .figmaAI, sessionID.hasPrefix("figmaMake-") {
            let key = String(sessionID.dropFirst(10))
            guard (8...128).contains(key.count), key.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return nil }
            host = "www.figma.com"
            path = "/make/" + key
        } else { return nil }
        var url = URLComponents()
        url.scheme = "https"; url.host = host; url.path = path
        return url.url
    }
}
