import AppKit

/// Отдача трекпада Force Touch: маскот «мурчит» под пальцем. Публичный API, без разрешений;
/// с мышью или без касания трекпада ничего не происходит.
@MainActor
enum Haptics {
    /// Поглаживание: три мягких тика, как мурчание.
    static func purr() {
        for (index, delay) in [0.0, 0.11, 0.22].enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                NSHapticFeedbackManager.defaultPerformer.perform(index == 1 ? .generic : .levelChange, performanceTime: .now)
            }
        }
    }

    /// Тычок: один щелчок.
    static func tap() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
