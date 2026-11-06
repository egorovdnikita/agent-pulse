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
