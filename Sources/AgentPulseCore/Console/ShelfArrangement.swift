import Foundation

public enum ShelfSort: String, CaseIterable, Sendable {
    case name, kind, added
    public var title: String {
        switch self {
        case .name: "По имени"
        case .kind: "По типу"
        case .added: "Сначала новые"
        }
    }
}

extension ShelfModule {
    /// Явная сортировка меняет порядок один раз; новые файлы не пересортировывают полку.
    public mutating func sort(_ method: ShelfSort) {
        guard method != .added else {
            restore(items.sorted { $0.addedAt < $1.addedAt })
            return
        }
        let order = displayItems.enumerated().sorted { lhs, rhs in
            let a = lhs.element, b = rhs.element
            let left = method == .kind ? a.url.pathExtension.lowercased() : a.name
            let right = method == .kind ? b.url.pathExtension.lowercased() : b.name
            let comparison = left.localizedStandardCompare(right)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            if method == .kind {
                let names = a.name.localizedStandardCompare(b.name)
                if names != .orderedSame { return names == .orderedAscending }
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
        restore(Array(order.reversed()))
    }

    /// Альтернатива перетаскиванию для клавиатуры и VoiceOver.
    public mutating func bringToFront(_ urls: [URL]) {
        let selected = Set(urls)
        let order = displayItems
        let arranged = [true, false].flatMap { pinned in
            let group = order.filter { $0.isPinned == pinned }
            return group.filter { selected.contains($0.url) } + group.filter { !selected.contains($0.url) }
        }
        restore(Array(arranged.reversed()))
    }

    /// Внутреннее перемещение сохраняет относительный порядок выбранных файлов и закрепление.
    public mutating func move(_ urls: [URL], before target: URL) {
        let selected = Set(urls)
        guard !selected.contains(target), let targetItem = items.first(where: { $0.url == target }) else { return }
        let moving = displayItems.filter { selected.contains($0.url) && $0.isPinned == targetItem.isPinned }
        guard !moving.isEmpty, moving.count == selected.count else { return }
        let moved = Set(moving.map(\.url))
        var order = displayItems.filter { !moved.contains($0.url) }
        guard let index = order.firstIndex(where: { $0.url == target }) else { return }
        order.insert(contentsOf: moving, at: index)
        restore(Array(order.reversed()))
    }
}
