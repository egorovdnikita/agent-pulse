import Foundation

/// Дочитывает новые строки из растущих JSONL-файлов. Помнит смещение по каждому файлу;
/// незавершённую строку держит до следующего чтения; при усечении файла начинает сначала.
public struct JSONLTailer: Sendable {
    private struct Cursor: Sendable {
        var offset: UInt64
        var partial = Data()
    }

    public static let maxLineBytes = 4 << 20

    private var cursors: [String: Cursor] = [:]

    public init() {}

    public func isTracking(_ path: String) -> Bool {
        cursors[path] != nil
    }

    /// Начать следить с текущего конца файла — история не проигрывается.
    public mutating func prime(_ path: String) {
        cursors[path] = Cursor(offset: Self.size(of: path) ?? 0)
    }

    /// Начать с начала (файл появился уже после запуска).
    public mutating func track(_ path: String) {
        cursors[path] = Cursor(offset: 0)
    }

    public mutating func forget(_ path: String) {
        cursors[path] = nil
    }

    /// Новые полные строки с прошлого чтения.
    public mutating func readNewLines(_ path: String) -> [Data] {
        guard var cursor = cursors[path], let size = Self.size(of: path) else { return [] }
        if size < cursor.offset {
            cursor = Cursor(offset: 0)
        }
        guard size > cursor.offset, let handle = FileHandle(forReadingAtPath: path) else {
            cursors[path] = cursor
            return []
        }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: cursor.offset)
            let chunk = try handle.read(upToCount: Int(size - cursor.offset)) ?? Data()
            cursor.offset += UInt64(chunk.count)
            var buffer = cursor.partial + chunk
            var lines: [Data] = []
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<newline]
                if !line.isEmpty { lines.append(Data(line)) }
                buffer = Data(buffer[buffer.index(after: newline)...])
            }
            // Строка без конца растёт бесконечно — это не наш формат, сбрасываем.
            cursor.partial = buffer.count > Self.maxLineBytes ? Data() : buffer
            cursors[path] = cursor
            return lines
        } catch {
            cursors[path] = cursor
            return []
        }
    }

    static func size(of path: String) -> UInt64? {
        (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.uint64Value
    }
}
