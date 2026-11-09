/// Распознаёт короткое отдельное нажатие Shift без чтения текста клавиш.
public struct ShiftTap: Sendable {
    private var down = false
    private var start: Double?
    private var activity: UInt64 = 0

    public init() {}

    /// Активность — общий счётчик нажатий и мыши, без их содержимого.
    public mutating func observe(shift: Bool, otherModifier: Bool, activity: UInt64, time: Double) -> Bool {
        defer { down = shift }
        if otherModifier { start = nil; return false }
        if shift {
            if !down { start = time; self.activity = activity }
            return false
        }
        guard down, let start else { return false }
        self.start = nil
        return time >= start && time - start <= 0.45 && activity == self.activity
    }
}
