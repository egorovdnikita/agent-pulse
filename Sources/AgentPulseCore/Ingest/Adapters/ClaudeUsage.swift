import Foundation
import Darwin

/// Лимиты через собственную авторизацию Claude Code. Только два control-запроса;
/// пользовательских сообщений, инструментов, чтения ключей и сохранения сессии нет.
public enum ClaudeUsage {
    public static let timeout: TimeInterval = 20
    static let initialize = #"{"type":"control_request","request_id":"pulse-init","request":{"subtype":"initialize","hooks":{}}}"#
    static let readUsage = #"{"type":"control_request","request_id":"pulse-usage","request":{"subtype":"get_usage","skip_behaviors":true}}"#
    static let arguments = [
        "--print", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
        "--no-session-persistence", "--setting-sources", "", "--strict-mcp-config",
        "--mcp-config", #"{"mcpServers":{}}"#, "--disable-slash-commands", "--tools", "",
        "--system-prompt", "", "--settings", #"{"disableAllHooks":true}"#,
    ]

    public static func locate(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        ([home.appending(path: ".local/bin/claude").path, home.appending(path: ".npm-global/bin/claude").path]
         + ["/opt/homebrew/bin/claude", "/usr/local/bin/claude"])
            .first(where: FileManager.default.isExecutableFile(atPath:))
    }

    /// Берём только окна подписки. Стоимость сессии, персональные данные и behaviors отбрасываются.
    public static func parse(_ line: Data, now: Date = Date()) -> LimitSnapshot? {
        guard let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              root["type"] as? String == "control_response",
              let response = root["response"] as? [String: Any],
              response["request_id"] as? String == "pulse-usage", response["subtype"] as? String == "success",
              let value = response["response"] as? [String: Any], value["rate_limits_available"] as? Bool == true,
              let limits = value["rate_limits"] as? [String: Any] else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        let windows = [("five_hour", LimitWindowKind.fiveHour), ("seven_day", .week)].compactMap { key, kind -> LimitWindow? in
            guard let window = limits[key] as? [String: Any], let percent = window["utilization"] as? NSNumber,
                  CFGetTypeID(percent) != CFBooleanGetTypeID(), percent.doubleValue.isFinite, percent.doubleValue >= 0 else { return nil }
            let reset = (window["resets_at"] as? String).flatMap { fractional.date(from: $0) ?? plain.date(from: $0) }
            return LimitWindow(kind: kind, usedPercent: min(100, percent.doubleValue), resetsAt: reset)
        }
        return windows.isEmpty ? nil : LimitSnapshot(service: .claude, windows: windows, at: now, origin: .claudeUsage)
    }

    public static func shouldRefresh(lastAttempt: Date, now: Date, frequent: Bool, inFlight: Bool) -> Bool {
        !inFlight && now.timeIntervalSince(lastAttempt) >= (frequent ? 60 : 300)
    }

    public static func fetch(executable: String, timeout: TimeInterval = Self.timeout) async -> LimitSnapshot? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { continuation.resume(returning: run(executable: executable, timeout: timeout)) }
        }
    }

    private static func run(executable: String, timeout: TimeInterval) -> LimitSnapshot? {
        guard timeout.isFinite, timeout > 0 else { return nil }
        let directory = FileManager.default.temporaryDirectory.appending(path: "pulse-usage-" + UUID().uuidString)
        guard (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: directory) }
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        var environment = ProcessInfo.processInfo.environment
        environment["CLAUDECODE"] = nil
        let binaryFolder = URL(fileURLWithPath: executable).resolvingSymlinksInPath().deletingLastPathComponent().path
        environment["PATH"] = [binaryFolder, "/opt/homebrew/bin", "/usr/local/bin", environment["PATH"] ?? "/usr/bin:/bin"].joined(separator: ":")
        process.environment = environment
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        defer {
            if process.isRunning {
                process.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
            }
            try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
        }
        func send(_ line: String) -> Bool {
            do { try input.fileHandleForWriting.write(contentsOf: Data((line + "\n").utf8)); return true }
            catch { return false }
        }
        guard send(initialize) else { return nil }
        var buffer = Data(), initialized = false, received = 0
        let expires = ProcessInfo.processInfo.systemUptime + timeout
        let fd = output.fileHandleForReading.fileDescriptor
        var bytes = [UInt8](repeating: 0, count: 8192)
        while ProcessInfo.processInfo.systemUptime < expires {
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, 100)
            if ready < 0 { if errno == EINTR { continue }; return nil }
            if ready == 0 { continue }
            let count = read(fd, &bytes, bytes.count)
            guard count > 0 else { return nil }
            received += count
            guard received <= 2_097_152 else { return nil }
            buffer.append(contentsOf: bytes.prefix(count))
            guard buffer.count <= 1_048_576 else { return nil }
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                guard let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      root["type"] as? String == "control_response", let response = root["response"] as? [String: Any] else { continue }
                if response["request_id"] as? String == "pulse-init", !initialized {
                    guard response["subtype"] as? String == "success", send(readUsage) else { return nil }
                    initialized = true
                } else if response["request_id"] as? String == "pulse-usage" { return parse(line) }
            }
        }
        return nil
    }
}
