import Foundation

public enum PulsePaths {
    public static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/AgentPulse", directoryHint: .isDirectory)
    }

    /// Должен совпадать с путём в `pulse-hook` (он не линкует ядро ради быстрого старта).
    public static var socketPath: String {
        if let override = ProcessInfo.processInfo.environment["AGENT_PULSE_SOCKET"], !override.isEmpty {
            return override
        }
        return supportDirectory.appending(path: "pulse.sock").path(percentEncoded: false)
    }

    public static var configURL: URL {
        supportDirectory.appending(path: "config.json")
    }

    public static var claudeSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/settings.json")
    }
}
