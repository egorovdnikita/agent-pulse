import Foundation

/// Слово, на котором остановилось чтение. Другой текст никогда не продолжится с чужого места.
public struct PrompterCheckpoint: Codable, Sendable {
    public let text: String
    public let position: Double
    public let savedAt: Date
    public init(text: String, position: Double, now: Date = Date()) {
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.position = position
        savedAt = now
    }
    public func fraction(for candidate: String) -> Double? {
        let candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        let count = candidate.split(whereSeparator: \.isWhitespace).count
        guard candidate == text, count > 0, position.isFinite, position > 0, position < Double(count) else { return nil }
        return position / Double(count)
    }
    public static var url: URL { PulsePaths.supportDirectory.appending(path: "prompter-position.json") }
    public static func load(from url: URL = Self.url, now: Date = Date()) -> Self? {
        guard let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode(Self.self, from: data),
              saved.savedAt <= now, now.timeIntervalSince(saved.savedAt) <= 30 * 24 * 3600,
              saved.fraction(for: saved.text) != nil else { return nil }
        return saved
    }
    public func save(to url: URL = Self.url) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    public static func erase(at url: URL = Self.url) { try? FileManager.default.removeItem(at: url) }
}
