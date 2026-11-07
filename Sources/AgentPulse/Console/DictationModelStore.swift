import AgentPulseCore
import CryptoKit
import Foundation
import Observation

/// Модель диктовки: разовая загрузка по кнопке. Архив закреплён контрольной суммой, из него берутся только нужные файлы.
@MainActor
@Observable
final class DictationModelStore {
    enum State: Equatable {
        case absent
        case downloading(Double)
        case unpacking
        case ready
        case failed(String)
    }

    private(set) var state: State = DictationModelSpec.isInstalled() ? .ready : .absent
    @ObservationIgnored private var session: URLSession?

    var isReady: Bool { state == .ready }

    func download() {
        switch state {
        case .downloading, .unpacking, .ready: return
        default: break
        }
        state = .downloading(0)
        let relay = DownloadRelay { [weak self] fraction in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.progress(fraction) } }
        } finished: { [weak self] result in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.downloaded(result) } }
        }
        let session = URLSession(configuration: .ephemeral, delegate: relay, delegateQueue: nil)
        self.session = session
        session.downloadTask(with: DictationModelSpec.url).resume()
    }

    func cancel() {
        session?.invalidateAndCancel()
        session = nil
        state = .absent
    }

    func remove() {
        try? FileManager.default.removeItem(at: DictationModelSpec.directory)
        state = .absent
    }

    private func progress(_ fraction: Double) {
        if case .downloading = state { state = .downloading(fraction) }
    }

    private func downloaded(_ result: Result<URL, Error>) {
        session?.finishTasksAndInvalidate()
        session = nil
        guard case .downloading = state else { return }
        switch result {
        case .failure:
            state = .failed("Не удалось скачать. Проверь сеть и попробуй ещё раз")
        case .success(let archive):
            state = .unpacking
            Task { [weak self] in
                let installed = await Self.install(archive)
                self?.state = installed ? .ready : .failed("Файл не прошёл проверку. Попробуй ещё раз")
            }
        }
    }

    /// Проверка и распаковка вне главного потока: архив весит 170 MB.
    nonisolated private static func install(_ archive: URL) async -> Bool {
        defer { try? FileManager.default.removeItem(at: archive) }
        guard sha256(of: archive) == DictationModelSpec.sha256 else { return false }
        let manager = FileManager.default
        let work = manager.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? manager.removeItem(at: work) }
        do {
            try manager.createDirectory(at: work, withIntermediateDirectories: true)
            let tar = Process()
            tar.executableURL = URL(filePath: "/usr/bin/tar")
            tar.arguments = ["-xjf", archive.path(percentEncoded: false), "-C", work.path(percentEncoded: false)]
                + DictationModelSpec.files.map { "\(DictationModelSpec.archiveRoot)/\($0.name)" }
            try tar.run()
            tar.waitUntilExit()
            let unpacked = work.appending(path: DictationModelSpec.archiveRoot, directoryHint: .isDirectory)
            guard tar.terminationStatus == 0, DictationModelSpec.isInstalled(at: unpacked) else { return false }
            let target = DictationModelSpec.directory
            try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? manager.removeItem(at: target)
            try manager.moveItem(at: unpacked, to: target)
            return true
        } catch {
            return false
        }
    }

    nonisolated private static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try? handle.read(upToCount: 1 << 20), !data.isEmpty {
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Прогресс и итог загрузки. Временный файл живёт только внутри обратного вызова, поэтому он переносится сразу.
private final class DownloadRelay: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progress: @Sendable (Double) -> Void
    private let finished: @Sendable (Result<URL, Error>) -> Void
    private var lastShown = 0.0

    init(progress: @escaping @Sendable (Double) -> Void, finished: @escaping @Sendable (Result<URL, Error>) -> Void) {
        self.progress = progress
        self.finished = finished
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytes: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        if fraction - lastShown >= 0.01 {
            lastShown = fraction
            progress(fraction)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let kept = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        guard (downloadTask.response as? HTTPURLResponse)?.statusCode == 200 else {
            finished(.failure(URLError(.badServerResponse)))
            return
        }
        do {
            try FileManager.default.moveItem(at: location, to: kept)
            finished(.success(kept))
        } catch {
            finished(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error { finished(.failure(error)) }
    }
}
