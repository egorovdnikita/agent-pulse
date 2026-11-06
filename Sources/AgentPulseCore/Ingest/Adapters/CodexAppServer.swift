import Foundation

/// Лимиты Codex: `codex app-server` по JSON-RPC, построчно в stdin/stdout.
/// Только `initialize`, `initialized`, `account/rateLimits/read`. `account/read` не вызывается: он возвращает e-mail.
/// Процесс живёт только на время запроса.
public enum CodexAppServer {
    public static let timeout: TimeInterval = 12

    static let initialize = #"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"agent-pulse","version":"1"}}}"#
    static let initialized = #"{"method":"initialized"}"#
    static let readLimits = #"{"id":2,"method":"account/rateLimits/read"}"#

    /// Окна определяются по `windowDurationMins`, а не по названиям `primary` и `secondary`.
    public static func parse(_ line: Data, now: Date = Date()) -> LimitSnapshot? {
        guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              object["id"] as? Int == 2,
              let result = object["result"] as? [String: Any],
              let limits = result["rateLimits"] as? [String: Any] else { return nil }
        let windows = ["primary", "secondary"].compactMap { key -> LimitWindow? in
            guard let window = limits[key] as? [String: Any],
                  let used = ClaudeStatusline.number(window["usedPercent"]),
                  let kind = kind(minutes: ClaudeStatusline.number(window["windowDurationMins"])) else { return nil }
            return LimitWindow(
                kind: kind, usedPercent: ClaudeStatusline.clamp(used),
                resetsAt: ClaudeStatusline.number(window["resetsAt"]).flatMap(ClaudeStatusline.date)
            )
        }
        return windows.isEmpty ? nil : LimitSnapshot(service: .codex, windows: windows, at: now)
    }

    static func kind(minutes: Double?) -> LimitWindowKind? {
        switch minutes {
        case 300: .fiveHour
        case 10080: .week
        default: nil
        }
    }

    /// Где искать `codex`, если путь не задан: приложение запускается с урезанным PATH.
    public static func candidates(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [String] {
        [".local/bin/codex", ".npm-global/bin/codex"].map { home.appending(path: $0).path(percentEncoded: false) }
            + ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
    }

    public static func locate(configured: String?) -> String? {
        if let configured, !configured.isEmpty { return FileManager.default.isExecutableFile(atPath: configured) ? configured : nil }
        return candidates().first(where: FileManager.default.isExecutableFile(atPath:))
    }

    /// Папки аккаунтов Codex на этом Mac: своя и аккаунты Orca. Смотрим только, есть ли вход; содержимое не читается.
    public static func accountHomes(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [String] {
        let accounts = home.appending(path: "Library/Application Support/orca/codex-accounts", directoryHint: .isDirectory)
        let orca = ((try? FileManager.default.contentsOfDirectory(at: accounts, includingPropertiesForKeys: nil)) ?? [])
            .map { $0.appending(path: "home", directoryHint: .isDirectory) }
            .sorted { $0.path < $1.path }
        return orca.filter { FileManager.default.fileExists(atPath: $0.appending(path: "auth.json").path) }
            .map { $0.path(percentEncoded: false) }
    }

    /// Окружение процесса. `codex` из npm — node-скрипт, поэтому рядом нужен каталог с node.
    /// Папка аккаунта задаётся явно: в Orca свой `CODEX_HOME`, без него прочитается `~/.codex`.
    static func environment(codex: String, home: String?, base: [String: String]) -> [String: String] {
        var environment = base
        let directory = URL(fileURLWithPath: codex).resolvingSymlinksInPath().deletingLastPathComponent().path(percentEncoded: false)
        let user = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        let extra = [directory, "\(user).local/bin", "\(user).npm-global/bin", "/opt/homebrew/bin", "/usr/local/bin"]
        environment["PATH"] = (extra + [base["PATH"] ?? "/usr/bin:/bin"]).joined(separator: ":")
        environment["CODEX_HOME"] = home?.isEmpty == false ? home : nil
        return environment
    }

    /// Запрос целиком; не вышло — nil, а Пульт честно покажет «нет данных».
    public static func fetch(codex: String, home: String?) async -> LimitSnapshot? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: run(codex: codex, home: home))
            }
        }
    }

    private static func run(codex: String, home: String?) -> LimitSnapshot? {
        let process = Process()
        let input = Pipe(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: codex)
        process.arguments = ["app-server"]
        process.environment = environment(codex: codex, home: home, base: ProcessInfo.processInfo.environment)
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let killer = DispatchWorkItem { process.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        defer {
            killer.cancel()
            if process.isRunning { process.terminate() }
            try? input.fileHandleForWriting.close()
        }
        func send(_ line: String) { try? input.fileHandleForWriting.write(contentsOf: Data((line + "\n").utf8)) }

        send(initialize)
        var buffer = Data()
        let handle = output.fileHandleForReading
        while true {
            // `availableData`, а не `read(upToCount:)`: тот ждёт полный буфер, а сервер держит поток открытым.
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return nil }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[buffer.startIndex..<newline])
                buffer = Data(buffer[buffer.index(after: newline)...])
                if let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any], object["id"] as? Int == 1 {
                    send(initialized)
                    send(readLimits)
                } else if let snapshot = parse(line) {
                    return snapshot
                } else if let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                          object["id"] as? Int == 2 {
                    return nil
                }
            }
        }
    }
}
