import Foundation

/// Читаем только явно выбранный текстовый файл с ограничением размера.
public enum PrompterTextFile {
    public static let maximumBytes = 2_000_000
    public static func supports(_ url: URL) -> Bool {
        url.isFileURL && ["txt", "md"].contains(url.pathExtension.lowercased())
    }
    public static func read(_ url: URL) throws -> String {
        guard supports(url) else { throw CocoaError(.fileReadUnsupportedScheme) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw CocoaError(.fileReadTooLarge) }
        guard let text = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        return text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    }
}
