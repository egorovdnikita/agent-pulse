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
    public let title = "Библиотека"
    public let accent: UInt32 = 0x5E5CE6
    public private(set) var items: [ShelfItem] = []

    public static let capacity = 20

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
        var seen = Set(items.map(\.url))
        let fresh = Array(urls.filter { seen.insert($0).inserted }.prefix(max(0, Self.capacity - items.count)))
        guard !fresh.isEmpty else { return [] }
        items.append(contentsOf: fresh.map(ShelfItem.init))
        return [.shelfChanged]
    }

    public mutating func remove(_ url: URL) {
        items.removeAll { $0.url == url }
    }

    public mutating func remove(_ urls: [URL]) {
        let gone = Set(urls)
        items.removeAll { gone.contains($0.url) }
    }

    public mutating func clear() {
        items.removeAll()
    }

    public mutating func tick(now: Date) -> [ToolSignal] { [] }
}

/// Выделение файлов: как в Finder. Клик — один файл, ⌘ — добавить или убрать, ⇧ — диапазон от последнего клика.
public struct ShelfSelection: Equatable, Sendable {
    public private(set) var urls: Set<URL> = []
    private var anchor: URL?

    public init() {}

    public var count: Int { urls.count }
    public var isEmpty: Bool { urls.isEmpty }

    public func contains(_ url: URL) -> Bool { urls.contains(url) }

    public mutating func click(_ url: URL, order: [URL], command: Bool = false, shift: Bool = false) {
        if shift, let anchor, let from = order.firstIndex(of: anchor), let to = order.firstIndex(of: url) {
            urls = Set(order[min(from, to)...max(from, to)])
            return
        }
        if command {
            if urls.remove(url) == nil { urls.insert(url) }
        } else {
            urls = [url]
        }
        anchor = url
    }

    public mutating func selectAll(_ order: [URL]) {
        urls = Set(order)
        anchor = order.first
    }

    /// Рамка мышью: выбрано то, что она задела сейчас.
    public mutating func replace(with touched: Set<URL>) {
        urls = touched
    }

    public mutating func clear() {
        urls = []
        anchor = nil
    }

    /// Файлов не стало — выделение их не помнит.
    public mutating func keep(only order: [URL]) {
        urls.formIntersection(order)
        if let anchor, !order.contains(anchor) { self.anchor = nil }
    }

    /// Что уносит перетаскивание: всё выбранное, если потянули за выбранный файл, иначе только его.
    public func dragged(from url: URL, order: [URL]) -> [URL] {
        urls.contains(url) ? order.filter(urls.contains) : [url]
    }
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
