import Foundation

/// Знакомство при первом запуске **[решение]**: несколько облачек подряд — кто я, что умею, как понять, что я жду.
/// Только реплики и позы, без кнопок; повторно — `--intro`.
public enum Introduction {
    public struct Step: Sendable, Equatable {
        public enum Pose: Sendable, Equatable {
            /// Радость: глаза-дуги, прыжки.
            case hello
            /// Осматривается.
            case look
            /// Поза «жду тебя»: смотрит прямо, глаза больше.
            case waiting
            /// Жмурится, как при поглаживании.
            case purr
        }

        public let line: String
        public let pose: Pose
    }

    /// `hooksInstalled` — Claude Code уже подключён: шаг про подключение не нужен.
    public static func steps(hooksInstalled: Bool) -> [Step] {
        var steps = [
            Step(line: "Привет, я тут живу", pose: .hello),
            Step(line: "Слежу, как себя чувствует твой Mac", pose: .look),
            Step(line: "Смотрю прямо на тебя — значит, жду тебя", pose: .waiting),
        ]
        if !hooksInstalled {
            steps.append(Step(line: "Подключи Claude Code — покажу, когда он ждёт", pose: .look))
        }
        steps.append(Step(line: "Погладь меня курсором, мне приятно", pose: .purr))
        return steps
    }

    /// Пауза между облачками: время чтения и полсекунды тишины.
    public static func pause(after step: Step) -> TimeInterval {
        BubbleTuning.readingTime(step.line) + 0.6
    }
}
