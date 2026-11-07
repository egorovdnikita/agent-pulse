import Foundation

/// Звуки Пульта. Их четыре, и они короткие: Пульт звучит, маскот осязается.
public enum ConsoleSound: Sendable, CaseIterable {
    case shelf, inserted, limitCritical, recordStart, recordStop

    /// Частоты нот, Гц, и длина каждой, s.
    var notes: [(frequency: Double, length: Double)] {
        switch self {
        case .shelf: [(880, 0.05)]
        case .inserted: [(740, 0.06), (988, 0.09)]
        case .limitCritical: [(622, 0.1), (466, 0.14)]
        case .recordStart: [(660, 0.07)]
        case .recordStop: [(494, 0.07)]
        }
    }

    /// Звук самой диктовки: своя запись созвоном не считается.
    public var isDictation: Bool {
        switch self {
        case .inserted, .recordStart, .recordStop: true
        case .shelf, .limitCritical: false
        }
    }

    /// Можно ли звучать сейчас. Режима фокуса здесь нет: узнать о нём приложение пока не может.
    public static func allowed(_ sound: ConsoleSound, enabled: Bool, prompter: Bool, call: Bool, quietHours: Bool) -> Bool {
        enabled && !prompter && !call && !quietHours
    }

    /// Звук как файл WAV: мягкая синусоида, без щелчка в начале и в конце.
    public var wav: Data {
        let rate = 44_100
        var samples: [Int16] = []
        for note in notes {
            let count = Int(note.length * Double(rate))
            for index in 0..<count {
                let time = Double(index) / Double(rate)
                let edge = min(1, min(time, note.length - time) / 0.008)
                let value = sin(2 * .pi * note.frequency * time) * edge * 0.8
                samples.append(Int16(value * Double(Int16.max)))
            }
        }
        var data = Data()
        let append32 = { (value: UInt32) in withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let append16 = { (value: UInt16) in withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8))
        append32(36 + bytes)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append32(16)
        append16(1)
        append16(1)
        append32(UInt32(rate))
        append32(UInt32(rate * 2))
        append16(2)
        append16(16)
        data.append(contentsOf: Array("data".utf8))
        append32(bytes)
        for sample in samples { append16(UInt16(bitPattern: sample)) }
        return data
    }
}
