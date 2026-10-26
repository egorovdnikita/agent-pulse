import Foundation
import Testing
@testable import AgentPulseCore

@Suite struct PhrasesTests {
    @Test(arguments: BubbleTrigger.allCases.filter { $0 != .line })
    func everyPhraseFitsTheWordLimit(_ trigger: BubbleTrigger) {
        let pool = Phrases.pool(for: trigger)
        #expect(!pool.isEmpty)
        for phrase in pool {
            #expect(Phrases.wordCount(phrase) <= Phrases.maxWords, "«\(phrase)» длиннее \(Phrases.maxWords) слов")
            #expect(Phrases.wordCount(phrase) >= 1)
        }
    }

    @Test(arguments: BubbleTrigger.allCases)
    func toneRules(_ trigger: BubbleTrigger) {
        let technical = ["bash", "tool", "mcp", "запрос"]
        for phrase in Phrases.pool(for: trigger) {
            #expect(!phrase.contains("..."), "многоточие — один символ «…»: \(phrase)")
            #expect(phrase != phrase.uppercased() || phrase.count <= 1, "без капса: \(phrase)")
            #expect(!phrase.unicodeScalars.contains { $0.properties.isEmojiPresentation }, "без эмодзи: \(phrase)")
            #expect(!technical.contains { phrase.lowercased().contains($0) }, "без техники: \(phrase)")
        }
    }

    @Test func wordCounting() {
        #expect(Phrases.wordCount("Что-то не то") == 3)
        #expect(Phrases.wordCount("Так-так") == 1)
        #expect(Phrases.wordCount("Ага, беру") == 2)
        #expect(Phrases.wordCount("Хмм…") == 1)
        #expect(Phrases.wordCount("раз два три четыре пять шесть семь восемь девять десять одиннадцать") == 11)
    }

    @Test func pickerNeverRepeatsBackToBack() {
        var picker = PhrasePicker()
        var rng = SystemRandomNumberGenerator()
        for trigger in BubbleTrigger.allCases where Phrases.pool(for: trigger).count > 1 && trigger != .line {
            var last = ""
            for _ in 0..<100 {
                let phrase = picker.pick(trigger, using: &rng)
                #expect(phrase != last)
                last = phrase
            }
        }
    }
}

@Suite struct BubbleSchedulerTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    func at(_ offset: TimeInterval) -> Date {
        t0.addingTimeInterval(offset)
    }

    @Test func reactionShowsImmediatelyAndExpires() {
        var scheduler = BubbleScheduler()
        scheduler.react(.done, now: at(0))
        #expect(scheduler.current?.trigger == .done)
        scheduler.tick(now: at(3.9))
        #expect(scheduler.current != nil)
        scheduler.tick(now: at(4))
        #expect(scheduler.current == nil)
    }

    @Test func reactionsQueueInsteadOfInterrupting() {
        var scheduler = BubbleScheduler()
        scheduler.react(.notice, now: at(0))
        scheduler.react(.step, now: at(0.2))
        #expect(scheduler.current?.trigger == .notice)
        scheduler.tick(now: at(2.1))
        #expect(scheduler.current?.trigger == .step)
    }

    @Test func ambientIsThrottled() {
        var scheduler = BubbleScheduler()
        // Модус держится меньше 2 s — молчим.
        scheduler.ambient(.workRead, heldSince: at(0), now: at(1))
        #expect(scheduler.current == nil)
        scheduler.ambient(.workRead, heldSince: at(0), now: at(2))
        #expect(scheduler.current?.trigger == .workRead)
        scheduler.tick(now: at(5))
        #expect(scheduler.current == nil)
        // Не чаще раза в 12 s.
        scheduler.ambient(.workRead, heldSince: at(0), now: at(10))
        #expect(scheduler.current == nil)
        scheduler.ambient(.workRead, heldSince: at(0), now: at(14))
        #expect(scheduler.current?.trigger == .workRead)
    }

    @Test func reactionPreemptsAmbientAfterMinimumShow() {
        var scheduler = BubbleScheduler()
        scheduler.ambient(.think, heldSince: at(0), now: at(2))
        scheduler.react(.step, now: at(2.5))
        #expect(scheduler.current?.trigger == .think)
        scheduler.tick(now: at(3))
        #expect(scheduler.current?.trigger == .step)
    }

    @Test func waitPreemptsAndHoldsUntilUserReacts() {
        var scheduler = BubbleScheduler()
        scheduler.react(.notice, now: at(0))
        scheduler.react(.step, now: at(0.1))
        scheduler.react(.waitPermission, now: at(0.2))
        #expect(scheduler.current?.trigger == .waitPermission)

        scheduler.react(.done, now: at(1))
        scheduler.tick(now: at(60))
        #expect(scheduler.current?.trigger == .waitPermission)

        // Пользователь отреагировал сразу — облачко всё равно живёт минимум 1 s.
        var quick = BubbleScheduler()
        quick.react(.waitInput, now: at(0))
        quick.endWait(now: at(0.3))
        #expect(quick.current != nil)
        quick.tick(now: at(1))
        #expect(quick.current == nil)

        scheduler.endWait(now: at(61))
        #expect(scheduler.current == nil)
    }

    @Test func catalogLinesQueueBehindAgentAndRespectQuiet() {
        var scheduler = BubbleScheduler()
        scheduler.say("Жарко…", duration: 2.5, now: at(0))
        #expect(scheduler.current?.text == "Жарко…")
        scheduler.say("Тише…", duration: 2.5, now: at(0.1))
        scheduler.react(.done, now: at(0.2))
        // Агентная реплика обгоняет реплику тела и вытесняет текущую после минимального показа.
        scheduler.tick(now: at(1.1))
        #expect(scheduler.current?.trigger == .done)

        var quiet = BubbleScheduler()
        quiet.quiet = true
        quiet.say("Жарко…", duration: 2.5, now: at(0))
        quiet.react(.done, now: at(0))
        #expect(quiet.current == nil)
        quiet.say("Эй…", duration: 3, agent: true, now: at(0))
        #expect(quiet.current?.text == "Эй…")
        quiet.react(.waitPermission, now: at(1))
        #expect(quiet.current?.trigger == .waitPermission)
    }
}

@Suite struct IntroductionTests {
    @Test func linesFollowVoiceRules() {
        let gendered = ["устал", "понял", "нашёл", "сделал", "рад ", "рада", "готов ", "готова"]
        for hooks in [false, true] {
            for step in Introduction.steps(hooksInstalled: hooks) {
                #expect(Phrases.wordCount(step.line) <= Phrases.maxWords, "\(step.line)")
                #expect(!step.line.lowercased().contains("агент"), "\(step.line)")
                #expect(!gendered.contains { (step.line.lowercased() + " ").contains($0) }, "\(step.line)")
            }
        }
    }

    @Test func connectStepOnlyWithoutHooks() {
        #expect(Introduction.steps(hooksInstalled: false).contains { $0.line.contains("Claude Code") })
        #expect(!Introduction.steps(hooksInstalled: true).contains { $0.line.contains("Claude Code") })
        #expect(Introduction.steps(hooksInstalled: true).contains { $0.pose == .waiting })
    }
}
