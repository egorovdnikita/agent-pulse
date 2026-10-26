import AgentPulseCore
import CoreGraphics
import Foundation

extension PulseModel {
    /// Знакомство: облачка по очереди, каждое со своей позой; на «жду тебя» — поза ожидания
    /// (только тело: без облачка ожидания и уведомления, состояние модели не меняется).
    /// `force` — показать ещё раз и сразу, даже в тишине (`--intro`, отладка).
    func introduce(force: Bool = false) {
        guard force || !config.introduced else { return }
        Task { @MainActor [weak self] in
            // Даём панели появиться и маскоту проснуться. Тишину не нарушаем: в тихие часы, на созвоне
            // или пока тебя нет — ждём; знакомство засчитывается, только когда его видно.
            try? await Task.sleep(for: .seconds(2))
            while !force, let self, self.scheduler.quiet || self.overlayOccluded || Self.idleSeconds() > 30 {
                try? await Task.sleep(for: .seconds(5))
            }
            guard let self else { return }
            self.config.introduced = true
            try? self.config.save()
            for step in Introduction.steps(hooksInstalled: self.hooksInstalled) {
                let pause = Introduction.pause(after: step)
                switch step.pose {
                case .hello: self.animator.enqueue(.done)
                case .look: self.animator.enqueue(.lookAround)
                case .purr: self.animator.enqueue(.purr)
                case .waiting: self.animator.setState(.waitYou(.input), at: Date.timeIntervalSinceReferenceDate)
                }
                if force { self.scheduler.quiet = false }
                self.scheduler.say(step.line, duration: pause - 0.6, category: .together, now: Date())
                try? await Task.sleep(for: .seconds(pause))
                if step.pose == .waiting { self.animator.setState(self.state, at: Date.timeIntervalSinceReferenceDate) }
            }
        }
    }

    /// Сколько секунд ни мыши, ни клавиатуры.
    static func idleSeconds() -> Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }
}
