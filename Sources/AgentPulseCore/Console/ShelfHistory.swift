import Foundation

/// Отмена меняет только ссылки Библиотеки, никогда не трогает сами файлы.
public struct ShelfHistory: Sendable {
    private var past: [[ShelfItem]] = []
    private var future: [[ShelfItem]] = []
    public static let capacity = 20
    public init() {}
    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }

    public mutating func record(_ items: [ShelfItem]) {
        if past.last != items { past.append(items) }
        if past.count > Self.capacity { past.removeFirst(past.count - Self.capacity) }
        future = []
    }
    public mutating func undo(current: [ShelfItem]) -> [ShelfItem]? {
        guard let previous = past.popLast() else { return nil }
        future.append(current)
        return previous
    }
    public mutating func redo(current: [ShelfItem]) -> [ShelfItem]? {
        guard let next = future.popLast() else { return nil }
        past.append(current)
        return next
    }
}
