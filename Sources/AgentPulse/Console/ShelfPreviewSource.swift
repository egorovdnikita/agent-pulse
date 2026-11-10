import AppKit
import QuickLookUI

/// Системный Quick Look получает только явно выбранные файлы, в порядке сетки.
@MainActor
final class ShelfPreviewSource: NSObject, @preconcurrency QLPreviewPanelDataSource {
    var urls: [URL] = []
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        guard urls.indices.contains(index) else { return nil }
        return urls[index] as NSURL
    }
}
