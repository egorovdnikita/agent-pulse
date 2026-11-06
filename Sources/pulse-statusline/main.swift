import Foundation

// Обёртка statusline Claude Code: stdin JSON → копия лимитов в сокет Pulse → исходная команда с тем же stdin.
// Правила: своя часть ≤ 50 ms и до запуска исходной команды — Claude Code отменяет незавершённый запуск.
// Вывод исходной команды не меняется. В сокет уходят только проценты и время сброса.
// Аргумент — исходная команда в base64; пусто — своей строки не было, печатать нечего.

signal(SIGPIPE, SIG_IGN)

let maxPayload = 1 << 20

func readStdin() -> [UInt8] {
    var payload: [UInt8] = []
    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
    while true {
        let count = read(STDIN_FILENO, &buffer, buffer.count)
        if count > 0 {
            payload.append(contentsOf: buffer[0..<count])
        } else if count == 0 || errno != EINTR {
            return payload
        }
    }
}

/// Только два окна и только два числа: путь проекта, модель и стоимость сессии сюда не попадают.
func limits(_ payload: [UInt8]) -> [UInt8]? {
    guard payload.count <= maxPayload,
          let object = (try? JSONSerialization.jsonObject(with: Data(payload))) as? [String: Any],
          let limits = object["rate_limits"] as? [String: Any] else { return nil }
    var trimmed: [String: [String: Double]] = [:]
    for key in ["five_hour", "seven_day"] {
        guard let window = limits[key] as? [String: Any], let used = (window["used_percentage"] as? NSNumber)?.doubleValue else { continue }
        var numbers = ["used_percentage": used]
        if let reset = (window["resets_at"] as? NSNumber)?.doubleValue { numbers["resets_at"] = reset }
        trimmed[key] = numbers
    }
    guard !trimmed.isEmpty, let data = try? JSONSerialization.data(withJSONObject: trimmed) else { return nil }
    return Array(data)
}

/// Должен совпадать с `PulsePaths.socketPath`.
func socketPath() -> String? {
    let environment = ProcessInfo.processInfo.environment
    if let override = environment["AGENT_PULSE_SOCKET"], !override.isEmpty { return override }
    return environment["HOME"].map { $0 + "/Library/Application Support/AgentPulse/pulse.sock" }
}

func send(_ bytes: [UInt8], to path: String) {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return }
    defer { close(fd) }
    var on: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    var timeout = timeval(tv_sec: 0, tv_usec: 30_000)
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = path.utf8CString
    guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return }
    withUnsafeMutableBytes(of: &address.sun_path) { raw in
        pathBytes.withUnsafeBytes { raw.copyMemory(from: $0) }
    }
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    let connected = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard connected == 0 else { return }
    var offset = 0
    while offset < bytes.count {
        let written = bytes[offset...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        if written > 0 {
            offset += written
        } else if written >= 0 || errno != EINTR {
            return
        }
    }
}

/// Stdin исходной команды — неименованный временный файл: читается целиком и не зависит от размера payload.
func replaceStdin(with payload: [UInt8]) -> Bool {
    var template = Array((NSTemporaryDirectory() + "pulse-statusline.XXXXXX").utf8CString)
    let fd = mkstemp(&template)
    guard fd >= 0 else { return false }
    unlink(template)
    var offset = 0
    while offset < payload.count {
        let written = payload[offset...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        if written > 0 {
            offset += written
        } else if written < 0 && errno == EINTR {
            continue
        } else {
            close(fd)
            return false
        }
    }
    lseek(fd, 0, SEEK_SET)
    return dup2(fd, STDIN_FILENO) >= 0
}

let payload = readStdin()
if let copy = limits(payload), let path = socketPath() {
    send(Array("PULSE1 bundle= channel=statusline\n".utf8) + copy, to: path)
}

guard CommandLine.arguments.count > 1,
      let decoded = Data(base64Encoded: CommandLine.arguments[1]),
      let original = String(data: decoded, encoding: .utf8), !original.isEmpty,
      replaceStdin(with: payload) else { exit(0) }

// exec, а не дочерний процесс: сигнал отмены от Claude Code дойдёт до исходной команды, вывод идёт напрямую.
let arguments: [UnsafeMutablePointer<CChar>?] = [strdup("/bin/sh"), strdup("-c"), strdup(original), nil]
execv("/bin/sh", arguments)
exit(0)
