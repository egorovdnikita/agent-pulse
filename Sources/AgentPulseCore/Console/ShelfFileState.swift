import Foundation

/// Лёгкая проверка только явно добавленных URL, без чтения содержимого файлов.
public struct ShelfFileState: Sendable, Equatable {
    public let available: Bool
    public let modified: Date?
    public let size: Int?
    public static func read(_ url: URL) -> ShelfFileState {
        // URLResourceValues кешируются у URL: stat должен увидеть повторную запись сразу.
        guard FileManager.default.isReadableFile(atPath: url.path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return ShelfFileState(available: false, modified: nil, size: nil)
        }
        return ShelfFileState(available: true, modified: attributes[.modificationDate] as? Date,
                              size: (attributes[.size] as? NSNumber)?.intValue)
    }
}
