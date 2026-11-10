import Foundation

/// Только явно добавленные термины, локально и без истории переводов.
public struct TranslationTerms: Codable, Sendable, Equatable {
    public private(set) var terms: [String] = []
    public static let capacity = 200
    public init() {}
    public mutating func add(_ raw: String) {
        let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, term.count <= 120, !term.contains(where: \.isNewline), terms.count < Self.capacity, !terms.contains(term) else { return }
        terms.append(term)
    }
    public mutating func remove(_ term: String) { terms.removeAll { $0 == term } }
    public static var url: URL { PulsePaths.supportDirectory.appending(path: "translation-terms.json") }
    public static func load(from url: URL = Self.url) -> Self {
        guard let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        var result = Self()
        decoded.terms.forEach { result.add($0) }
        return result
    }
    public func save(to url: URL = Self.url) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
