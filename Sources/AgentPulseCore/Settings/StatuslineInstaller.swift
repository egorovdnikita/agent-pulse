import Foundation

/// Обёртка statusline в `~/.claude/settings.json`. Statusline у пользователя одна, а чужое мы не трогаем:
/// исходная команда остаётся внутри нашей и работает как раньше. Только с согласия, с бэкапом; удаление её возвращает.
///
/// Исходная строка лежит в base64. Открытым текстом нельзя: Orca при запуске затирает команду,
/// если видит в ней `agent-hooks/claude-statusline.sh` (проверено её же функцией на версии 1.4.250).
public enum StatuslineInstaller {
    public enum Failure: Error, CustomStringConvertible {
        case unsupported

        public var description: String {
            switch self {
            case .unsupported: "В statusLine не команда — такую настройку обернуть нельзя, файл не изменён"
            }
        }
    }

    public static let marker = "pulse-statusline"
    private static let originalKey = "o='"

    /// `|| true` здесь не годится: statusline пользователя погасла бы вместе с приложением.
    /// Обёртки нет — команда сама запускает исходную строку.
    public static func command(wrapperPath: String, original: String?) -> String {
        let encoded = Data((original ?? "").utf8).base64EncodedString()
        return "w=\(quoted(wrapperPath)); \(originalKey)\(encoded)'; if [ -x \"$w\" ]; then exec \"$w\" \"$o\"; fi; "
            + "if [ -n \"$o\" ]; then exec /bin/sh -c \"$(printf %s \"$o\" | /usr/bin/base64 -D)\"; fi; exec /bin/cat >/dev/null"
    }

    static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public static func isOurs(_ command: String?) -> Bool {
        command?.contains(marker) == true && command?.contains(originalKey) == true
    }

    /// Исходная команда из нашей: nil — её не было.
    public static func original(from command: String) -> String? {
        guard let start = command.range(of: originalKey)?.upperBound,
              let end = command[start...].firstIndex(of: "'"),
              let data = Data(base64Encoded: String(command[start..<end])),
              let text = String(data: data, encoding: .utf8), !text.isEmpty else { return nil }
        return text
    }

    static func currentCommand(_ settings: [String: Any]) -> String? {
        (settings["statusLine"] as? [String: Any])?["command"] as? String
    }

    public static func isInstalled(_ settings: [String: Any]) -> Bool {
        isOurs(currentCommand(settings))
    }

    public static func installing(into settings: [String: Any], wrapperPath: String) throws -> [String: Any] {
        var settings = settings
        var line = settings["statusLine"] as? [String: Any] ?? ["type": "command"]
        if let type = line["type"] as? String, type != "command" { throw Failure.unsupported }
        let current = line["command"] as? String
        let original = isOurs(current) ? current.flatMap(original(from:)) : current
        line["command"] = command(wrapperPath: wrapperPath, original: original)
        settings["statusLine"] = line
        return settings
    }

    public static func removing(from settings: [String: Any]) -> [String: Any] {
        guard let current = currentCommand(settings), isOurs(current), var line = settings["statusLine"] as? [String: Any] else {
            return settings
        }
        var settings = settings
        if let original = original(from: current) {
            line["command"] = original
            settings["statusLine"] = line
        } else {
            settings["statusLine"] = nil
        }
        return settings
    }

    /// Обёртка стоит, но указывает на другой путь: приложение переехали.
    public static func needsUpdate(_ settings: [String: Any], wrapperPath: String) -> Bool {
        guard let current = currentCommand(settings), isOurs(current) else { return false }
        return current != command(wrapperPath: wrapperPath, original: original(from: current))
    }

    /// Пока стоит обёртка, Orca не обновляет свою команду. Сверяем при запуске: скрипт, на который она ссылается, ещё на месте?
    public static func originalIsBroken(_ settings: [String: Any], home: String) -> Bool {
        guard let current = currentCommand(settings), let original = original(from: current) else { return false }
        let script = "/.orca/agent-hooks/claude-statusline.sh"
        return original.contains(script) && !FileManager.default.isExecutableFile(atPath: home + script)
    }

    // MARK: - Файл

    public static func isInstalled(settingsURL: URL = PulsePaths.claudeSettingsURL) -> Bool {
        (try? HookInstaller.readSettings(settingsURL.resolvingSymlinksInPath())).map(isInstalled) ?? false
    }

    public static func originalIsBroken(settingsURL: URL = PulsePaths.claudeSettingsURL) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        return (try? HookInstaller.readSettings(settingsURL.resolvingSymlinksInPath())).map {
            originalIsBroken($0, home: String(home.dropLast()))
        } ?? false
    }

    @discardableResult
    public static func install(wrapperPath: String, settingsURL: URL = PulsePaths.claudeSettingsURL, now: Date = Date()) throws -> URL? {
        let url = settingsURL.resolvingSymlinksInPath()
        let current = try HookInstaller.readSettings(url)
        let updated = try installing(into: current, wrapperPath: wrapperPath)
        let backup = try HookInstaller.backUp(url, now: now)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try HookInstaller.write(updated, to: url)
        return backup
    }

    @discardableResult
    public static func uninstall(settingsURL: URL = PulsePaths.claudeSettingsURL, now: Date = Date()) throws -> URL? {
        let url = settingsURL.resolvingSymlinksInPath()
        let current = try HookInstaller.readSettings(url)
        guard isInstalled(current) else { return nil }
        let backup = try HookInstaller.backUp(url, now: now)
        try HookInstaller.write(removing(from: current), to: url)
        return backup
    }

    /// Приложение переехало — молча чиним путь.
    public static func repair(wrapperPath: String, settingsURL: URL = PulsePaths.claudeSettingsURL, now: Date = Date()) {
        let url = settingsURL.resolvingSymlinksInPath()
        guard let current = try? HookInstaller.readSettings(url), needsUpdate(current, wrapperPath: wrapperPath) else { return }
        _ = try? install(wrapperPath: wrapperPath, settingsURL: settingsURL, now: now)
    }
}
