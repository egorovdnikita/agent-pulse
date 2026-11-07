import AVFoundation
import AgentPulseCore
import AppKit
import ApplicationServices
import Observation

/// Диктовка и перевод от нажатия до вставки. Звук живёт в памяти и только до конца распознавания.
@MainActor
@Observable
final class DictationController {
    /// Модель держится в памяти столько после последней диктовки.
    static let unloadAfter: Duration = .seconds(120)

    let models = DictationModelStore()
    private(set) var history = DictationHistory.load()
    @ObservationIgnored private let console: ConsoleModel
    @ObservationIgnored private let settings: () -> PulseConfig.Console
    @ObservationIgnored private let helper = DictationHelper()
    @ObservationIgnored private var recorder: DictationRecorder?
    @ObservationIgnored private var unloadTask: Task<Void, Never>?
    @ObservationIgnored private var selection: TextInsertion.Selection?
    /// Отладка: звук из файла вместо микрофона и свой буфер вместо системного.
    @ObservationIgnored private var demoSamples: [Float]?
    @ObservationIgnored private var demoLevels: Timer?

    init(console: ConsoleModel, settings: @escaping () -> PulseConfig.Console, showSettings: @escaping () -> Void) {
        self.console = console
        self.settings = settings
        console.dictationModelReady = { [weak self] in
            guard let self else { return false }
            return self.russian ? self.models.isReady : true
        }
        console.onDictationNeedsModel = showSettings
        console.onDictationStart = { [weak self] in self?.startRecording() }
        console.onDictationStop = { [weak self] keep in self?.stopRecording(keep: keep) }
        console.onTranslateReplace = { [weak self] text in self?.replaceSelection(with: text) }
    }

    private var russian: Bool { settings().dictationLanguage != "en" }

    // MARK: - Запись

    private func startRecording() {
        unloadTask?.cancel()
        if russian { helper.prepare() }
        if demoSamples != nil {
            demoLevels = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.console.hearDictation(level: .random(in: 0.002...0.06)) }
            }
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            let console = console
            recorder = DictationRecorder { level in
                DispatchQueue.main.async { MainActor.assumeIsolated { console.hearDictation(level: level) } }
            }
            if recorder == nil {
                console.finishDictation(notice: .noMicrophone)
            } else {
                QuietSense.ownMicrophoneRunning = true
            }
        case .notDetermined:
            // Вопрос системы идёт, пока клавиша зажата: эту запись не начинаем, следующая сработает.
            console.finishDictation(notice: nil)
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        default:
            console.finishDictation(notice: .noMicrophone)
        }
    }

    private func stopRecording(keep: Bool) {
        demoLevels?.invalidate()
        demoLevels = nil
        let samples = demoSamples ?? recorder?.stop() ?? []
        recorder = nil
        if QuietSense.ownMicrophoneRunning {
            QuietSense.ownMicrophoneRunning = false
            QuietSense.ownMicrophoneUntil = Date().addingTimeInterval(5)
        }
        guard keep else {
            scheduleUnload()
            return
        }
        Task { await recognize(samples) }
    }

    private func recognize(_ samples: [Float]) async {
        defer { scheduleUnload() }
        guard !samples.isEmpty else {
            console.finishDictation(notice: nil)
            return
        }
        do {
            let raw = russian ? try await helper.transcribe(samples) : try await DictationEnglish.transcribe(samples)
            let text = DictationRules.apply(raw, custom: settings().dictationRules)
            guard !text.isEmpty else {
                console.finishDictation(notice: nil)
                return
            }
            let pasteboard = demoSamples != nil ? NSPasteboard(name: Self.demoPasteboard) : .general
            let outcome = await TextInsertion.insert(text, accessibility: settings().accessibility, pasteboard: pasteboard)
            remember(text)
            console.finishDictation(notice: outcome == .inClipboard ? .inClipboard : nil)
        } catch {
            console.finishDictation(notice: .failed)
        }
    }

    private func remember(_ text: String) {
        guard settings().dictationHistory else { return }
        history.add(text, now: Date())
        history.save()
    }

    func clearHistory() {
        history = DictationHistory()
        DictationHistory.erase()
    }

    private func scheduleUnload() {
        unloadTask?.cancel()
        unloadTask = Task { [weak self] in
            try? await Task.sleep(for: Self.unloadAfter)
            guard !Task.isCancelled else { return }
            self?.helper.unload()
        }
    }

    // MARK: - Перевод

    func pressTranslate() {
        let readable = settings().accessibility && AXIsProcessTrusted()
        selection = readable ? TextInsertion.selection() : nil
        // Буфер читаем только на втором нажатии: ты сам сказал взять его.
        let clipboard = console.translate.state == .askToCopy ? NSPasteboard.general.string(forType: .string) : nil
        guard let text = console.pressTranslate(selection: selection?.text, clipboard: clipboard) else { return }
        Task { [console] in
            console.finishTranslate(source: text, result: await ConsoleTranslator.translate(text))
        }
    }

    private func replaceSelection(with text: String) {
        guard let selection else { return }
        console.setExpanded(false)
        Task {
            // Пульт отдаёт фокус не мгновенно, а ⌘V должна уйти в твоё приложение.
            try? await Task.sleep(for: .milliseconds(150))
            _ = await TextInsertion.replace(selection, with: text)
        }
    }

    // MARK: - Отладка

    static let demoPasteboard = NSPasteboard.Name("io.github.egorovdnikita.agentpulse.demo")

    /// `--dictation-demo файл.wav`: весь путь от нажатия до вставки, но со звуком из файла и своим буфером.
    func runDemo(path: String, holdFor seconds: Double) {
        guard let file = try? AVAudioFile(forReading: URL(filePath: path), commonFormat: .pcmFormatFloat32, interleaved: false),
              file.fileFormat.sampleRate == Double(DictationChunks.sampleRate),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil, let channel = buffer.floatChannelData?[0] else { return }
        demoSamples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        console.dictationEnabled = true
        console.pressDictation()
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [console] in console.releaseDictation() }
    }
}
