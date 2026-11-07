import AVFoundation
import Foundation
import Speech

/// Голос суфлёра: распознавание только на устройстве. Аудио не пишется и не уходит с машины.
@MainActor
final class PrompterVoice {
    enum Failure: String {
        case denied = "Нет доступа к микрофону или распознаванию речи"
        case noOnDevice = "На этом Mac нет распознавания этого языка без сети"
        case audio = "Не удалось включить микрофон"
    }

    var onWords: (([String]) -> Void)?
    var onFailure: ((Failure) -> Void)?
    private var recognizer: SFSpeechRecognizer?
    private var pipe: VoicePipe?
    private var task: SFSpeechRecognitionTask?
    private var running = false

    /// Язык — по тексту: кириллицы больше, значит русский.
    static func locale(for text: String) -> Locale {
        let letters = text.unicodeScalars.filter(CharacterSet.letters.contains)
        let cyrillic = letters.filter { (0x0400...0x04FF).contains($0.value) }.count
        return Locale(identifier: cyrillic * 2 >= letters.count ? "ru-RU" : "en-US")
    }

    /// Проверка при включении: о том, что языка нет, лучше узнать сейчас, а не посреди созвона.
    static func check(text: String) async -> Failure? {
        guard await authorize() else { return .denied }
        let recognizer = SFSpeechRecognizer(locale: locale(for: text))
        return recognizer?.supportsOnDeviceRecognition == true ? nil : .noOnDevice
    }

    func start(text: String) {
        guard !running else { return }
        running = true
        let locale = Self.locale(for: text)
        Task { [weak self] in
            guard await Self.authorize() else {
                self?.fail(.denied)
                return
            }
            self?.begin(locale: locale)
        }
    }

    func stop() {
        guard running else { return }
        running = false
        tearDown()
        QuietSense.ownMicrophoneRunning = false
        QuietSense.ownMicrophoneUntil = Date().addingTimeInterval(5)
    }

    private func fail(_ failure: Failure) {
        stop()
        onFailure?(failure)
    }

    nonisolated private static func authorize() async -> Bool {
        let speech = await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { done.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVCaptureDevice.requestAccess(for: .audio)
    }

    private func begin(locale: Locale) {
        guard running else { return }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.supportsOnDeviceRecognition else {
            fail(.noOnDevice)
            return
        }
        self.recognizer = recognizer
        QuietSense.ownMicrophoneRunning = true
        recognize()
    }

    /// Одна задача распознавания живёт ограниченно: закончилась — начинается новая.
    private func recognize() {
        guard running, let recognizer else { return }
        tearDown()
        self.recognizer = recognizer
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        guard let pipe = VoicePipe(request: request) else {
            fail(.audio)
            return
        }
        self.pipe = pipe
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let words = result?.bestTranscription.segments.map(\.substring)
            let ended = error != nil || result?.isFinal == true
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.running else { return }
                    if let words, !words.isEmpty { self.onWords?(words) }
                    if ended { self.restart() }
                }
            }
        }
    }

    private func restart() {
        tearDown(keepRecognizer: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            MainActor.assumeIsolated { self?.recognize() }
        }
    }

    private func tearDown(keepRecognizer: Bool = false) {
        task?.cancel()
        task = nil
        pipe?.stop()
        pipe = nil
        if !keepRecognizer { recognizer = nil }
    }
}

/// Звук с микрофона в распознаватель. Живёт вне главного актора: аудио приходит из своего потока.
private final class VoicePipe: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let request: SFSpeechAudioBufferRecognitionRequest

    init?(request: SFSpeechAudioBufferRecognitionRequest) {
        self.request = request
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return nil }
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [request] buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            return nil
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        request.endAudio()
    }
}
