import Foundation
import CryptoKit

/// Слово, на котором остановилось чтение. Другой текст никогда не продолжится с чужого места.
public struct PrompterCheckpoint: Codable, Sendable {
    public let fingerprint: String
    public let wordCount: Int
    public let position: Double
    public let savedAt: Date
    public init(text: String, position: Double, now: Date = Date()) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        fingerprint = Self.digest(normalized)
        wordCount = normalized.split(whereSeparator: \.isWhitespace).count
        self.position = position
        savedAt = now
    }
    public func fraction(for candidate: String) -> Double? {
        let candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        let count = candidate.split(whereSeparator: \.isWhitespace).count
        guard Self.digest(candidate) == fingerprint, count == wordCount, count > 0, position.isFinite, position > 0, position < Double(count) else { return nil }
        return position / Double(count)
    }
    private static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    public static var url: URL { PulsePaths.supportDirectory.appending(path: "prompter-position.json") }
    public static func load(from url: URL = Self.url, now: Date = Date()) -> Self? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        struct Legacy: Decodable { let text: String; let position: Double; let savedAt: Date }
        let saved = (try? JSONDecoder().decode(Self.self, from: data)) ?? (try? JSONDecoder().decode(Legacy.self, from: data)).map {
            Self(text: $0.text, position: $0.position, now: $0.savedAt)
        }
        guard let saved, saved.savedAt <= now, now.timeIntervalSince(saved.savedAt) <= 30 * 24 * 3600,
              saved.position.isFinite, saved.position > 0, saved.position < Double(saved.wordCount) else { return nil }
        return saved
    }
    public func save(to url: URL = Self.url) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    public static func erase(at url: URL = Self.url) { try? FileManager.default.removeItem(at: url) }
}
