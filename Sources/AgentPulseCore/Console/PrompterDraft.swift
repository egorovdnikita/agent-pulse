import Foundation

/// Черновик, включая отступы и пустую строку после очистки. Только локально.
public struct PrompterDraft: Codable, Sendable, Equatable {
    public var text: String
    public init(text: String = "") { self.text = text }
    public static var url: URL { PulsePaths.supportDirectory.appending(path: "prompter-draft.json") }
    public static func load(from url: URL = Self.url) -> Self {
        guard let data = try? Data(contentsOf: url), let draft = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return draft
    }
    public func save(to url: URL = Self.url) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
