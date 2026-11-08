import AgentPulseCore
import AppKit
import SwiftUI

/// Отладка: `AgentPulse --promo-sheet папка` — исходники промо-ролика без окон на экране.
/// Сценарий `папка/script.json` пишет монтажный скрипт; здесь настоящий `MascotAnimator` проходит его
/// на виртуальных часах, а облачка, капсула и страницы Пульта рисуются настоящими видами. Камеру
/// и клики добавляет монтаж.
@MainActor
enum PromoSheet {
    struct Script: Decodable {
        struct StateMark: Decodable { let t: Double; let state: String }
        struct ReactionMark: Decodable { let t: Double; let name: String }
        struct Bubble: Decodable { let id: String; let category: String; let title: String; let text: String }
        let assetsOnly: Bool?
        let fps: Double
        let duration: Double
        let diameter: Double
        let scale: Double
        let states: [StateMark]
        let reactions: [ReactionMark]
        /// Наведение: интервалы [начало, конец].
        let hover: [[Double]]
        /// Курсор относительно центра маскота, pt, y вниз; null — курсора рядом нет.
        let cursor: [[Double]?]
        let bubbles: [Bubble]
    }

    static func render(app: AppDelegate, to folder: URL) {
        guard let data = try? Data(contentsOf: folder.appending(path: "script.json")),
              let script = try? JSONDecoder().decode(Script.self, from: data) else {
            print("promo: нет script.json")
            return
        }
        if script.assetsOnly != true { renderMascot(script, to: folder.appending(path: "mascot")) }
        for bubble in script.bubbles {
            guard let category = BubbleCategory(rawValue: bubble.category) else { continue }
            let message = BubbleMessage(category: category, title: bubble.title, text: bubble.text)
            snapshot(BubbleView(message: message, tailOnRight: true).padding(12), scale: script.scale,
                     to: folder.appending(path: "bubble-\(bubble.id).png"))
        }
        renderConsole(scale: script.scale, to: folder)

    }

    private static func state(_ name: String) -> MascotState {
        switch name {
        case "sleep": .sleep
        case "think": .think
        case "read": .work(.read)
        case "edit": .work(.edit)
        case "run": .work(.run)
        case "search": .work(.search)
        case "work": .work(.general)
        case "permission": .waitYou(.permission)
        case "input": .waitYou(.input)
        default: .idle
        }
    }

    private static func renderMascot(_ script: Script, to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let animator = MascotAnimator()
        animator.screenCenter = .zero
        let skin = PalSkin(bot: PalSkin.defaultBot)
        precondition(skin.isComplete(), "Для промо нужен установленный Agent Pals / Circle")
        animator.skin = skin
        let box = MascotView.boxSize(script.diameter)
        let view = MascotLayerView(animator: animator, diameter: script.diameter)
        view.preparePromoPal()
        view.frame = CGRect(x: 0, y: 0, width: box, height: box)
        view.layoutSubtreeIfNeeded()
        var states = script.states.sorted { $0.t < $1.t }
        var reactions = script.reactions.sorted { $0.t < $1.t }
        let frames = Int((script.duration * script.fps).rounded())
        let side = Int(box * script.scale)
        for index in 0..<frames {
            // Время с запасом: часы аниматора не начинаются с нуля, иначе первые паузы совпадут с «запуском».
            let t = Double(index) / script.fps
            let clock = 100 + t
            while let next = states.first, next.t <= t {
                animator.setState(state(next.state), at: clock)
                states.removeFirst()
            }
            while let next = reactions.first, next.t <= t {
                if let reaction = MascotReaction(rawValue: next.name) { animator.enqueue(reaction, at: clock) }
                reactions.removeFirst()
            }
            animator.hovered = script.hover.contains { $0.count == 2 && t >= $0[0] && t < $0[1] }
            let offset = index < script.cursor.count ? script.cursor[index] : nil
            let cursor = offset.map { CGPoint(x: $0[0], y: -$0[1]) }
            view.apply(animator.pose(at: clock, cursor: cursor))
            let clip = animator.choreo.clip
            let elapsed = max(0, clock - animator.choreo.since)
            view.seekPromoPal(progress: elapsed.truncatingRemainder(dividingBy: clip.loop) / clip.loop,
                              transition: elapsed / PalChoreographer.crossfade)
            guard let context = CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { continue }
            context.scaleBy(x: script.scale, y: script.scale)
            view.layer?.render(in: context)
            guard let image = context.makeImage() else { continue }
            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                .write(to: folder.appending(path: String(format: "%04d.png", index)))
        }
    }

    private static func renderConsole(scale: Double, to folder: URL) {
        let model = ConsoleModel(promo: true)
        model.translatorEnabled = true
        model.tick(now: Date(), agentWaiting: false, inputActive: false)
        model.showPanelNow()
        let panel = CGSize(width: ConsoleLayout.expandedWidth, height: ConsoleLayout.expandedHeight)
        func page(_ name: String, _ tab: ConsoleModuleID) {
            model.tab = tab
            snapshot(PanelPreview(model: model).frame(width: panel.width, height: panel.height).padding(8),
                     scale: scale, to: folder.appending(path: "panel-\(name).png"))
        }
        page("limits-empty", .limits)
        let now = Date()
        for (service, used, week) in [(LimitService.claude, 31, 64), (.codex, 12, 27)] {
            model.ingest(LimitSnapshot(service: service, windows: [
                LimitWindow(kind: .fiveHour, usedPercent: Double(used), resetsAt: now.addingTimeInterval(3 * 3600)),
                LimitWindow(kind: .week, usedPercent: Double(week), resetsAt: now.addingTimeInterval(4 * 86_400)),
            ], at: now))
            page(service == .claude ? "limits-claude" : "limits", .limits)
        }
        snapshot(CapsulePreview(model: model).padding(8), scale: scale, to: folder.appending(path: "capsule.png"))
        page("shelf-empty", .shelf)
        model.dropTargeted = true
        page("shelf-drop", .shelf)
        model.dropTargeted = false
        let files = ["Доклад.pdf", "Заметки.md", "Бюджет.xlsx", "Презентация.key"].map { URL(filePath: "/tmp/pulse-promo-fiction/\($0)") }
        model.addToShelf(Array(files.prefix(1)))
        page("shelf-one", .shelf)
        model.addToShelf(Array(files.dropFirst()))
        page("shelf", .shelf)
        model.selectAllShelf()
        page("shelf-selected", .shelf)
        model.removeSelectedFiles()
        page("shelf-cleared", .shelf)
        page("prompter-empty", .prompter)
        let speech = "Привет! Сегодня покажу Пульт.\n\nЛимиты нейросетей всегда под рукой. Файлы можно сохранить на полке, а текст — быстро перевести.\n\nВсё работает прямо на этом Mac."
        for count in 1...speech.count {
            model.prompterDraft = String(speech.prefix(count))
            page("prompter-type-\(count)", .prompter)
        }
        page("prompter", .prompter)
        model.setPrompterSpeed(160)
        page("prompter-speed", .prompter)
        model.prompterDraft = ""
        page("prompter-cleared", .prompter)
        page("translate-empty", .translate)
        let source = "Маскот показывает, что агент ждёт тебя."
        for count in 1...source.count {
            model.translateInput = String(source.prefix(count))
            page("translate-type-\(count)", .translate)
        }
        _ = model.pressTranslate(selection: source, clipboard: nil)
        page("translate-working", .translate)
        model.finishTranslate(source: source, result: .success("The mascot shows that the agent is waiting for you."))
        page("translate", .translate)
        model.translateCopied = true
        page("translate-copied", .translate)
        model.clearTranslation()
        page("translate-cleared", .translate)
    }

    /// Прозрачный фон: монтаж кладёт картинку на свой рабочий стол.
    private static func snapshot(_ view: some View, scale: Double, to url: URL) {
        let host = NSHostingView(rootView: view.fixedSize())
        host.appearance = NSAppearance(named: .darkAqua)
        let size = host.fittingSize
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale), bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return }
        bitmap.size = size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }
}
