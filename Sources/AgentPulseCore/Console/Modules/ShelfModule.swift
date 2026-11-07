import Foundation

public struct ShelfItem: Sendable, Equatable, Identifiable {
    public var id: URL { url }
    public var url: URL
    public var name: String { url.lastPathComponent }

    public init(url: URL) {
        self.url = url
    }
}

/// Полка: ссылки на файлы, только в памяти. Выход из приложения очищает полку, сами файлы никто не трогает.
public struct ShelfModule: ConsoleModule {
    public let id = ConsoleModuleID.shelf
    public let title = "Полка"
    public let accent: UInt32 = 0x5E5CE6
    public private(set) var items: [ShelfItem] = []

    public init() {}

    public func priority(now: Date) -> ConsolePriority? {
        items.isEmpty ? nil : .shelf
    }

    public func capsule(now: Date) -> CapsuleContent {
        let count = items.count
        let text = "\(count) \(HumanTime.plural(count, "файл", "файла", "файлов"))"
        return CapsuleContent(rings: [], label: text, text: text, icon: "folder-with-files")
    }

    public mutating func add(_ urls: [URL]) -> [ToolSignal] {
        let fresh = urls.filter { url in !items.contains { $0.url == url } }
        guard !fresh.isEmpty else { return [] }
        items.append(contentsOf: fresh.map(ShelfItem.init))
        return [.shelfChanged]
    }

    public mutating func remove(_ url: URL) {
        items.removeAll { $0.url == url }
    }

    public mutating func clear() {
        items.removeAll()
    }

    public mutating func tick(now: Date) -> [ToolSignal] { [] }
}

/// Вид файла на полке: по расширению, содержимое не читается.
public enum ShelfFileKind: Sendable, Equatable {
    case image, pdf, archive, presentation, document, spreadsheet, other

    public init(name: String) {
        switch (name as NSString).pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "heic", "heif", "tif", "tiff", "webp", "bmp", "svg":
            self = .image
        case "pdf":
            self = .pdf
        case "zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar", "dmg":
            self = .archive
        case "key", "ppt", "pptx", "odp":
            self = .presentation
        case "doc", "docx", "pages", "rtf", "txt", "md", "odt":
            self = .document
        case "xls", "xlsx", "numbers", "csv", "ods":
            self = .spreadsheet
        default:
            self = .other
        }
    }

    /// Метка на листе: расширение, не длиннее четырёх букв. Нет расширения — нет метки.
    public static func badge(name: String) -> String? {
        let suffix = (name as NSString).pathExtension.uppercased()
        guard !suffix.isEmpty, suffix.count <= 4 else { return nil }
        return suffix
    }
}
