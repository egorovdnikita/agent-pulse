@preconcurrency import AVFoundation
import AgentPulseCore
import Foundation
import Speech

/// Запись для диктовки: звук живёт только в памяти, на диск не пишется никогда.
/// Живёт вне главного актора: аудио приходит из своего потока.
final class DictationRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private let onLevel: @Sendable (Float) -> Void

    init?(onLevel: @escaping @Sendable (Float) -> Void) {
        self.onLevel = onLevel
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0,
              let target = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: Double(DictationChunks.sampleRate), channels: 1, interleaved: false
              ),
              let converter = AVAudioConverter(from: format, to: target) else { return nil }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.append(buffer, converter: converter, target: target)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            return nil
        }
    }

    private func append(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, target: AVAudioFormat) {
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * target.sampleRate / buffer.format.sampleRate) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        nonisolated(unsafe) var supplied = false
        nonisolated(unsafe) let source = buffer
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return source
        }
        guard error == nil, let channel = output.floatChannelData?[0], output.frameLength > 0 else { return }
        let chunk = UnsafeBufferPointer(start: channel, count: Int(output.frameLength))
        var energy: Float = 0
        for sample in chunk { energy += sample * sample }
        lock.lock()
        samples.append(contentsOf: chunk)
        lock.unlock()
        onLevel((energy / Float(chunk.count)).squareRoot())
    }

    /// Останавливает запись и отдаёт звук: 16 kHz, моно.
    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.lock()
        defer {
            samples = []
            lock.unlock()
        }
        return samples
    }
}

enum DictationFailure: Error {
    case helper, noEnglish, denied
}

/// Помощник `pulse-asr`: модель живёт в его памяти и уходит вместе с ним.
/// Запускается по первому нажатию, закрывается после простоя или вместе с приложением (конец stdin).
final class DictationHelper: @unchecked Sendable {
    private let queue = DispatchQueue(label: "agent-pulse.dictation-helper", qos: .userInitiated)
    private var process: Process?
    private var input: FileHandle?
    private var reader: LineReader?
    /// Сколько ждём ответа на кусок до 25 s: в сотни раз дольше, чем нужно живому помощнику.
    private static let answerTimeout: TimeInterval = 60

    private static var executable: URL {
        Bundle.main.bundleURL.appending(path: "Contents/MacOS/pulse-asr")
    }

    /// Загрузить модель заранее, чтобы к отпусканию клавиши она уже была в памяти.
    func prepare() {
        queue.async { [self] in _ = launch() }
    }

    var isRunning: Bool { queue.sync { process?.isRunning == true } }

    func transcribe(_ samples: [Float]) async throws -> String {
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<String, Error>) in
            queue.async { [self] in
                do {
                    done.resume(returning: try recognize(samples))
                } catch {
                    shutDown()
                    done.resume(throwing: error)
                }
            }
        }
    }

    func unload() {
        queue.async { [self] in shutDown() }
    }

    private func launch() -> Bool {
        if process?.isRunning == true { return true }
        shutDown()
        let process = Process()
        let toHelper = Pipe()
        let fromHelper = Pipe()
        process.executableURL = Self.executable
        process.arguments = [DictationModelSpec.directory.path(percentEncoded: false)]
        process.standardInput = toHelper
        process.standardOutput = fromHelper
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return false
        }
        self.process = process
        input = toHelper.fileHandleForWriting
        let reader = LineReader(handle: fromHelper.fileHandleForReading)
        self.reader = reader
        return reader.readLine(timeout: Self.answerTimeout) == "ready"
    }

    private func recognize(_ samples: [Float]) throws -> String {
        guard launch(), let input, let reader else { throw DictationFailure.helper }
        var parts: [String] = []
        for range in DictationChunks.ranges(of: samples) {
            var count = UInt32(range.count).littleEndian
            var request = Data(bytes: &count, count: 4)
            samples[range].withUnsafeBytes { request.append(contentsOf: $0) }
            try input.write(contentsOf: request)
            guard let line = reader.readLine(timeout: Self.answerTimeout) else { throw DictationFailure.helper }
            if !line.isEmpty { parts.append(line.trimmingCharacters(in: .whitespaces)) }
        }
        return parts.joined(separator: " ")
    }

    private func shutDown() {
        try? input?.close()
        input = nil
        reader = nil
        if let process, process.isRunning { process.terminate() }
        process = nil
    }
}

/// Чтение строк из канала с пределом ожидания: зависший помощник не должен держать диктовку.
private final class LineReader: @unchecked Sendable {
    private let handle: FileHandle
    private let condition = NSCondition()
    private var buffer = Data()
    private var closed = false

    init(handle: FileHandle) {
        self.handle = handle
        handle.readabilityHandler = { [weak self] file in
            let data = file.availableData
            self?.receive(data)
            if data.isEmpty { file.readabilityHandler = nil }
        }
    }

    deinit { handle.readabilityHandler = nil }

    private func receive(_ data: Data) {
        condition.lock()
        if data.isEmpty { closed = true } else { buffer.append(data) }
        condition.broadcast()
        condition.unlock()
    }

    func readLine(timeout: TimeInterval) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }
        while true {
            if let end = buffer.firstIndex(of: 0x0A) {
                let line = String(decoding: buffer[buffer.startIndex..<end], as: UTF8.self)
                buffer.removeSubrange(buffer.startIndex...end)
                return line
            }
            if closed || !condition.wait(until: deadline) { return nil }
        }
    }
}

/// Английская диктовка: системный распознаватель только на устройстве, в сеть звук не уходит.
enum DictationEnglish {
    static func transcribe(_ samples: [Float]) async throws -> String {
        let authorized = await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { done.resume(returning: $0 == .authorized) }
        }
        guard authorized else { throw DictationFailure.denied }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.supportsOnDeviceRecognition,
              let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: Double(DictationChunks.sampleRate), channels: 1, interleaved: false
              ),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { throw DictationFailure.noEnglish }
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.append(buffer)
        request.endAudio()
        return try await withCheckedThrowingContinuation { (done: CheckedContinuation<String, Error>) in
            let once = Once()
            _ = recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    if once.claim() { done.resume(returning: result.bestTranscription.formattedString) }
                } else if error != nil, once.claim() {
                    done.resume(throwing: DictationFailure.noEnglish)
                }
            }
        }
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var used = false

        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            defer { used = true }
            return !used
        }
    }
}
