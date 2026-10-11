import Foundation

/// Установка и удаление хуков в `~/.claude/settings.json`.
/// Только с явного согласия, с бэкапом, аккуратным мержем: чужие хуки не трогаем. Удаление — чистый откат.
public enum HookInstaller {
    public enum Failure: Error, CustomStringConvertible {
        case unreadableSettings(URL)

        public var description: String {
            switch self {
            case .unreadableSettings(let url): "Не удалось разобрать \(url.path): файл не изменён"
            }
        }
    }

    public static let events = [
        "UserPromptSubmit", "PreToolUse", "PostToolUse", "Notification", "SubagentStop", "Stop", "SessionEnd",
    ]
    static let toolEvents: Set<String> = ["PreToolUse", "PostToolUse"]
    /// Наши записи узнаём по имени бинаря в команде.
    public static let marker = "pulse-hook"
    public static let timeoutSeconds = 2

    // MARK: - Чистые преобразования

    public static func installing(into settings: [String: Any], command: String) -> [String: Any] {
        var settings = removing(from: settings)
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for event in events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            var group: [String: Any] = [
                "hooks": [["type": "command", "command": command, "timeout": timeoutSeconds]],
            ]
            if toolEvents.contains(event) { group["matcher"] = "*" }
            groups.append(group)
            hooks[event] = groups
        }
        settings["hooks"] = hooks
        return settings
    }

    public static func removing(from settings: [String: Any]) -> [String: Any] {
        guard var hooks = settings["hooks"] as? [String: Any] else { return settings }
        var changed = false
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            var cleaned: [[String: Any]] = []
            for group in groups {
                guard let list = group["hooks"] as? [Any] else {
                    cleaned.append(group)
                    continue
                }
                let kept = list.filter { !isOurs($0) }
                if kept.count == list.count {
                    cleaned.append(group)
                } else {
                    changed = true
                    if !kept.isEmpty {
                        var trimmed = group
                        trimmed["hooks"] = kept
                        cleaned.append(trimmed)
                    }
                }
            }
            if cleaned.count != groups.count || changed {
                hooks[event] = cleaned.isEmpty ? nil : cleaned
            }
        }
        guard changed else { return settings }
        var settings = settings
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        return settings
    }

    public static func isInstalled(_ settings: [String: Any]) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { value in
            (value as? [[String: Any]] ?? []).contains { group in
                (group["hooks"] as? [Any] ?? []).contains(where: isOurs)
            }
        }
    }

    /// Хуки стоят, но указывают на другой `pulse-hook` (приложение переехали или пересобрали в другом месте).
    public static func needsUpdate(_ settings: [String: Any], command: String) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        let commands = hooks.values.flatMap { value in
            (value as? [[String: Any]] ?? []).flatMap { group in
                (group["hooks"] as? [Any] ?? []).filter(isOurs).compactMap { ($0 as? [String: Any])?["command"] as? String }
            }
        }
        return !commands.isEmpty && (commands.contains { $0 != command } || !events.allSatisfy { event in
            (hooks[event] as? [[String: Any]] ?? []).contains { ($0["hooks"] as? [Any] ?? []).contains(where: isOurs) }
        })
    }

    public static func needsUpdate(command: String, settingsURL: URL = PulsePaths.claudeSettingsURL) -> Bool {
        (try? readSettings(settingsURL.resolvingSymlinksInPath())).map { needsUpdate($0, command: command) } ?? false
    }

    static func isOurs(_ hook: Any) -> Bool {
        ((hook as? [String: Any])?["command"] as? String)?.contains(marker) == true
    }

    // MARK: - Файл

    public static func isInstalled(settingsURL: URL = PulsePaths.claudeSettingsURL) -> Bool {
        (try? readSettings(settingsURL.resolvingSymlinksInPath())).map(isInstalled) ?? false
    }

    /// Возвращает путь к бэкапу, если исходный файл существовал.
    @discardableResult
    public static func install(command: String, settingsURL: URL = PulsePaths.claudeSettingsURL, now: Date = Date()) throws -> URL? {
        // Многие держат dotfiles симлинками — пишем в настоящий файл, а не поверх ссылки.
        let url = settingsURL.resolvingSymlinksInPath()
        let current = try readSettings(url)
        let backup = try backUp(url, now: now)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try write(installing(into: current, command: command), to: url)
        return backup
    }

    @discardableResult
    public static func uninstall(settingsURL: URL = PulsePaths.claudeSettingsURL, now: Date = Date()) throws -> URL? {
        let url = settingsURL.resolvingSymlinksInPath()
        let current = try readSettings(url)
        guard isInstalled(current) else { return nil }
        let backup = try backUp(url, now: now)
        try write(removing(from: current), to: url)
        return backup
    }

    static func readSettings(_ url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.unreadableSettings(url)
        }
        return object
    }

    static func backUp(_ url: URL, now: Date) throws -> URL? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backup = url.deletingLastPathComponent()
            .appending(path: "\(url.lastPathComponent).agentpulse-\(formatter.string(from: now)).bak")
        if FileManager.default.fileExists(atPath: backup.path) {
            try FileManager.default.removeItem(at: backup)
        }
        try FileManager.default.copyItem(at: url, to: backup)
        return backup
    }

    static func write(_ settings: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(
            withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: url, options: .atomic)
    }
}
