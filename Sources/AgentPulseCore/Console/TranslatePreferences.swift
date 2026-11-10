import Foundation

/// Только языки: введённый и переведённый текст здесь не сохраняются.
public struct TranslatePreferences: Codable, Sendable, Equatable {
    public var source: String?
    public var target: String
    public init(source: String? = "en", target: String = "ru") { self.source = source; self.target = target }
    public static var url: URL { PulsePaths.supportDirectory.appending(path: "translation-languages.json") }
    public static func load(from url: URL = Self.url) -> Self {
        guard let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(Self.self, from: data),
              valid(value.target), value.source.map(valid) ?? true else { return Self() }
        return value
    }
    private static func valid(_ code: String) -> Bool {
        !code.isEmpty && code.count <= 64 && code.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }
    public func save(to url: URL = Self.url) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
