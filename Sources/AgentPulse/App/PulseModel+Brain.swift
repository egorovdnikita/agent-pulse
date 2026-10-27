import AgentPulseCore
import AppKit

/// Органы чувств → Director → тело и голос.
extension PulseModel {
    func handleSignal(_ signal: Signal) async {
        if signal.kind == .minute || signal.kind == .systemWake {
            let hour = Calendar.current.component(.hour, from: signal.ts)
            // После заката свечение теплеет — без реплики.
            body.night = hour >= 20 || hour < 6
            body.hour = hour
        }
        body.apply(signal)
        if signal.kind == .lidAngle, let angle = signal.value {
            // Крышка раскрыта шире — смотрит вверх, прикрыта — вниз.
            animator.lidGaze = max(-0.6, min(0.6, (110 - angle) / 60))
        }

        let outcome = await director.handle(signal)
        if outcome.mood != mood { mood = outcome.mood }
        scheduler.mood = outcome.mood
        if outcome.quiet != quiet {
            quiet = outcome.quiet
            scheduler.quiet = outcome.quiet
        }
        animator.baseline = Baseline.from(mood: outcome.mood, body: body)
        // Агент закончил без тебя — маскот ждёт с новостями; ты вернулся — рассказывает.
        animator.contented = outcome.newsPending
        if let news = outcome.deliveredNews {
            awayNews = news
            awayNewsAt = signal.ts
        }
        if today != outcome.today { today = outcome.today }
        if week != outcome.week { week = outcome.week }
        handleIdleHide(signal)
        await saveMemoryIfNeeded(signal.ts)

        guard let decision = outcome.decision else { return }
        lastReaction = decision.reaction
        lastLine = decision.line
        if let behavior = decision.behavior { animator.enqueue(behavior) }
        if decision.special == .news {
            tellNews(at: signal.ts, duration: decision.bubbleDuration, leadIn: decision.line)
        } else if let special = decision.special {
            onSpecial?(special, decision.line)
        } else if let line = decision.line {
            let category = BubbleCategory.forReaction(decision.reaction)
            let title = category == .claude ? BubbleCategory.agentTitle(lastTask?.source) : nil
            scheduler.say(
                line, duration: decision.bubbleDuration, category: category, title: title,
                agent: decision.tier == .agent, now: signal.ts
            )
        }
    }

    /// SignalSimulator: любой сигнал вручную, чтобы настроить реакцию.
    func simulate(_ kind: SignalKind, value: Double? = nil) {
        inbox.yield(.signal(Signal(kind.defaultSense, kind, value: value)))
    }

    /// Агентный конвейер подсказывает Director: задача, ошибки, длинная задача.
    func feedAgentSignals(_ event: AgentEvent) {
        let signal: Signal?
        switch event.kind {
        case .promptSubmitted:
            promptAt[event.sessionId] = event.ts
            toolErrorStreak = 0
            signal = nil
        case .toolStarted:
            let duration = promptAt[event.sessionId].map { event.ts.timeIntervalSince($0) } ?? 0
            signal = Signal(.agents, .agentStep, value: duration, ts: event.ts)
        case .toolFinished:
            toolErrorStreak = event.isError ? toolErrorStreak + 1 : 0
            signal = toolErrorStreak == 3 ? Signal(.agents, .agentErrorStreak, ts: event.ts) : nil
        case .stopped:
            signal = Signal(.agents, .agentDone, ts: event.ts)
        case .error:
            signal = Signal(.agents, .agentError, ts: event.ts)
        default:
            signal = nil
        }
        if let signal { inbox.yield(.signal(signal)) }
    }

    /// Агент работает или ждёт — приколы молчат. Ждёт > 5 мин — «Эй…».
    func updateAgentBusy(now: Date) {
        let busy: Bool = switch state {
        case .work, .think, .waitYou: true
        default: false
        }
        if busy != agentBusy {
            agentBusy = busy
            let director = director
            Task { await director.update { $0.agentBusy = busy } }
        }
        if state.isWaiting, !waitLongSent, now.timeIntervalSince(stateSince) > 5 * 60 {
            waitLongSent = true
            inbox.yield(.signal(Signal(.agents, .agentWaitingLong, ts: now)))
        }
    }

    /// hideWhenIdle: прячется после долгого простоя, возвращается к твоему приходу. Агент важнее.
    private func handleIdleHide(_ signal: Signal) {
        guard config.character.hideWhenIdle else { return }
        switch signal.kind {
        case .minute where !hiddenForIdle && !agentBusy:
            if PresenceSense.idleSeconds > Double(config.character.hideAfterMinutes * 60) {
                hiddenForIdle = true
                onIdleHide?(true)
            }
        case .userBack, .screenUnlocked, .systemWake, .agentStep, .agentDone, .agentWaitingLong:
            if signal.kind != .agentStep { onUserBack?() }
            if hiddenForIdle {
                hiddenForIdle = false
                onIdleHide?(false)
            }
        default:
            break
        }
    }

    private func saveMemoryIfNeeded(_ now: Date) async {
        guard now.timeIntervalSince(lastMemorySave) > 10 * 60 else { return }
        lastMemorySave = now
        let memory = await director.snapshot.memory
        try? memory.save()
    }

    /// Применить характер из настроек (слайдеры, тихие часы, день рождения).
    func applyCharacter() {
        try? config.save()
        let settings = config.character.directorSettings
        let director = director
        Task { await director.update { $0.settings = settings } }
    }

    func resetMemory() {
        let director = director
        Task {
            await director.update { $0.memory.reset() }
            try? DayMemory().save()
        }
    }

    // MARK: - Новости дизайна

    /// Свежие ленты: запомнить и сказать Director, сколько новостей ждёт.
    func receiveNews(_ items: [NewsItem]) {
        newsDesk.update(items)
        simulate(.newsFresh, value: Double(newsDesk.available(now: Date()).count))
    }

    /// Director решил: пора рассказать новость. (Отладка: `--news-now` — сразу.)
    func tellNews(at now: Date, duration: TimeInterval, leadIn: String? = nil, ignoringQuiet: Bool = false) {
        guard ignoringQuiet || !quiet, let item = newsDesk.take(now: now, lastSource: currentNews?.source, lastTopic: currentNews?.topic) else { return }
        currentNews = item
        currentNewsAt = now
        lastReaction = Self.newsReaction
        lastLine = item.teaser
        // Как человек: сначала «Смотри, что нашлось», потом суть своими словами.
        // Заход утра или возвращения — только к дизайну; у остальных тем свой: «Из мира ИТ».
        let category = BubbleCategory.news(item.topic)
        let opener = item.topic == .design ? leadIn ?? item.topic.leadIns.randomElement() : item.topic.leadIns.randomElement()
        scheduler.say(opener ?? "", duration: 1.6, category: category, now: now)
        scheduler.say(item.teaser, duration: duration, category: category, note: item.shortSource, now: now)
        try? newsDesk.save()
        simulate(.newsFresh, value: Double(newsDesk.available(now: now).count))
    }

    // MARK: - «Мило» и «бесит»

    static var feedbackURL: URL {
        PulsePaths.supportDirectory.appending(path: "feedback.jsonl")
    }

    /// Локальный лог оценок последней реакции — для недели валидации.
    /// Оценка рассказанной новости: не повод глушить новости, а вкус — тема и источник звучат реже или чаще.
    static let newsReaction = "news.item"

    func feedback(_ verdict: String) {
        guard let reaction = lastReaction else { return }
        if reaction == Self.newsReaction, let item = currentNews {
            newsDesk.record(verdict == "бесит" ? .disliked : .liked, for: item)
            try? newsDesk.save()
        }
        let entry: [String: Any] = [
            "ts": ISO8601DateFormatter().string(from: Date()), "reaction": reaction, "verdict": verdict,
            "line": lastLine ?? "",
        ]
        guard var data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) else { return }
        data.append(0x0A)
        let url = Self.feedbackURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
        feedbackToday[verdict, default: 0] += 1
        let muted = Self.loadMuted()
        if muted != mutedReactions {
            mutedReactions = muted
            let director = director
            Task { await director.update { $0.mutedReactions = muted } }
        }
    }

    /// Что глушить по логу «мило / бесит» за последнюю неделю.
    static func loadMuted(now: Date = Date()) -> Set<String> {
        guard let data = try? Data(contentsOf: feedbackURL) else { return [] }
        return FeedbackLog.muted(FeedbackLog.parse(data), now: now)
    }
}
