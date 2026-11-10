import AgentPulseCore
import AppKit

extension ConsoleModel {
    func shelfTargets(from url: URL? = nil) -> [URL] {
        if let url { return shelfSelection.dragged(from: url, order: shelfOrder) }
        return shelfOrder.filter(shelfSelection.contains)
    }

    func openShelfFiles(from url: URL? = nil) {
        for file in shelfTargets(from: url) where FileManager.default.isReadableFile(atPath: file.path) {
            NSWorkspace.shared.open(file)
        }
    }

    func revealShelfFiles(from url: URL? = nil) {
        let urls = shelfTargets(from: url).filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}
