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
    @ObservationIgnored private var replayVersion = 0
    @ObservationIgnored private var replay: RecentDictation?
    @ObservationIgnored private var correctionMode = false
    @ObservationIgnored private var lastInsertion: (context: RecentDictation, selection: TextInsertion.Selection)?
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
        console.onForgetRecentDictation = { [weak self] in self?.forgetRecentDictation() }
        console.onReplayDictation = { [weak self] in self?.replayLastDictation() }
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
        let correcting = correctionMode
        correctionMode = false
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
        Task { await recognize(samples, correcting: correcting) }
    }

    private func recognize(_ samples: [Float], correcting: Bool) async {
        defer { scheduleUnload() }
        guard !samples.isEmpty else {
            console.finishDictation(notice: nil)
            return
        }
        do {
            let raw = russian ? try await helper.transcribe(samples) : try await DictationEnglish.transcribe(samples)
            guard demoSamples != nil || (settings().enabled && settings().dictation) else {
                console.finishDictation(notice: nil)
                return
            }
            let formatted = DictationFormatting.apply(raw, enabled: !correcting && settings().dictationFormatting)
            let text = DictationRules.apply(formatted, custom: settings().dictationRules)
            guard !text.isEmpty else {
                console.finishDictation(notice: nil)
                return
            }
            if correcting { await applyCorrection(text); return }
            let pasteboard = demoSamples != nil ? NSPasteboard(name: Self.demoPasteboard) : .general
            let outcome = await TextInsertion.insert(text, accessibility: settings().accessibility, pasteboard: pasteboard)
            setReplay(text)
            captureInsertion(text: text, outcome: outcome)
            remember(text)
            console.finishDictation(notice: outcome == .inClipboard ? .inClipboard : .inserted)
        } catch {
            console.finishDictation(notice: .failed)
        }
    }

    private func setReplay(_ text: String) {
        replayVersion += 1
        replay = RecentDictation(text: text, now: Date())
        console.dictationReplayUntil = Date().addingTimeInterval(RecentDictation.lifetime)
    }

    func replayLastDictation() {
        guard console.dictationEnabled, !console.dictationReplaying, console.dictation.phase == .idle, !console.prompter.isActive,
              let replay, replay.isCurrent(now: Date()) else { return }
        let version = replayVersion
        console.dictationReplaying = true
        console.setExpanded(false)
        Task {
            defer { console.dictationReplaying = false }
            try? await Task.sleep(for: .milliseconds(150))
            guard self.console.dictation.phase == .idle, settings().enabled, settings().dictation, replayVersion == version, replay.isCurrent(now: Date()) else { return }
            let outcome = await TextInsertion.insert(replay.text, accessibility: settings().accessibility)
            captureInsertion(text: replay.text, outcome: outcome)
            console.finishDictation(notice: outcome == .inClipboard ? .inClipboard : .inserted)
        }
    }

    func pressCorrection() {
        guard console.dictationEnabled, console.dictation.phase == .idle else { return }
        guard settings().accessibility, AXIsProcessTrusted(), lastInsertion?.context.isCurrent(now: Date()) == true else {
            console.finishDictation(notice: .correctionUnavailable)
            return
        }
        correctionMode = true
        console.pressDictation(correcting: true)
        if console.dictation.phase != .recording { correctionMode = false }
    }

    private func captureInsertion(text: String, outcome: TextInsertion.Outcome) {
        guard outcome == .inserted, let target = TextInsertion.insertedSelection(text: text, accessibility: settings().accessibility) else {
            lastInsertion = nil
            return
        }
        lastInsertion = (RecentDictation(text: text, now: Date()), target)
    }

    private func applyCorrection(_ utterance: String) async {
        guard let recent = lastInsertion, let text = recent.context.correcting(utterance, now: Date()) else {
            console.finishDictation(notice: .correctionFailed)
            return
        }
        let outcome = await TextInsertion.replace(recent.selection, with: text)
        captureInsertion(text: text, outcome: outcome)
        if outcome == .inserted { setReplay(text); remember(text) }
        console.finishDictation(notice: outcome == .inserted ? .corrected : .inClipboard)
    }

    private func remember(_ text: String) {
        guard settings().dictationHistory else { return }
        history.add(text, now: Date())
        history.save()
    }

    func forgetRecentDictation() {
        replayVersion += 1
        replay = nil
        console.dictationReplayUntil = .distantPast
        lastInsertion = nil
    }

    func clearHistory() {
        forgetRecentDictation()
        history = DictationHistory()
        DictationHistory.erase()
    }

    private func scheduleUnload() {
        unloadTask?.cancel()
        unloadTask = Task { [weak self] in
            try? await Task.sleep(for: Self.unloadAfter)
            guard !Task.isCancelled else { return }
            self?.helper.unload()
            self?.lastInsertion = nil
            self?.replay = nil
            self?.console.dictationReplayUntil = .distantPast
        }
    }

    // MARK: - Перевод

    func pressTranslate() {
        Task { await readAndTranslate() }
    }

    private func readAndTranslate() async {
        let readable = settings().accessibility && AXIsProcessTrusted()
        // Раскрытый Пульт держит клавиатуру: ⌘C ушла бы ему, а не твоему приложению.
        if readable, console.expanded {
            console.setExpanded(false)
            try? await Task.sleep(for: .milliseconds(150))
        }
        selection = readable ? await TextInsertion.selection() : nil
        // Буфер читаем только на втором нажатии: ты сам сказал взять его.
        let clipboard = console.translate.state == .askToCopy ? NSPasteboard.general.string(forType: .string) : nil
        guard let text = console.pressTranslate(
            selection: selection?.text, clipboard: clipboard, editable: selection?.editable ?? false
        ) else { return }
        await console.runTranslation(text)
    }

    private func replaceSelection(with text: String) {
        guard let selection else { return }
        console.setExpanded(false)
        Task {
            // Пульт отдаёт фокус не мгновенно, а ⌘V должна уйти в твоё приложение.
            try? await Task.sleep(for: .milliseconds(150))
            let outcome = await TextInsertion.replace(selection, with: text)
            if outcome == .inClipboard {
                self.console.translateCopied = true
                self.console.setExpanded(true)
                self.console.tab = .translate
            }
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
