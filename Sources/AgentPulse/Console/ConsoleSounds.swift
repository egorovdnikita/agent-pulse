import AgentPulseCore
import AppKit

/// Проигрывание звуков Пульта. Тише системных: это знак, а не сообщение.
@MainActor
enum ConsoleSounds {
    private static let volume: Float = 0.2
    private static var loaded: [ConsoleSound: NSSound] = [:]

    static func play(_ sound: ConsoleSound) {
        let player = loaded[sound] ?? NSSound(data: sound.wav)
        loaded[sound] = player
        player?.volume = volume
        player?.stop()
        player?.play()
    }
}
