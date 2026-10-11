import Darwin

// Хук Claude Code: stdin JSON → unix-сокет Agent Pulse.
// Правила: отвечать быстро, никогда не блокировать агента, всегда exit 0 — даже если приложение не запущено.

// Жёсткий потолок времени работы: что бы ни случилось, через 300 ms выходим с 0.
signal(SIGALRM) { _ in _exit(0) }
signal(SIGPIPE, SIG_IGN)
var deadline = itimerval(it_interval: timeval(), it_value: timeval(tv_sec: 0, tv_usec: 300_000))
setitimer(ITIMER_REAL, &deadline, nil)

let maxPayload = 1 << 20

func readStdin() -> [UInt8] {
    var payload: [UInt8] = []
    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
    while true {
        let count = read(STDIN_FILENO, &buffer, buffer.count)
        if count > 0 {
            payload.append(contentsOf: buffer[0..<count])
            if payload.count > maxPayload { exit(0) }
        } else if count == 0 {
            return payload
        } else if errno == EINTR {
            continue
        } else {
            exit(0)
        }
    }
}

func env(_ name: String) -> String? {
    guard let value = getenv(name) else { return nil }
    let string = String(cString: value)
    return string.isEmpty ? nil : string
}

/// Должен совпадать с `PulsePaths.socketPath`.
func socketPath() -> String? {
    if let override = env("AGENT_PULSE_SOCKET") { return override }
    guard let home = env("HOME") else { return nil }
    return home + "/Library/Application Support/AgentPulse/pulse.sock"
}

/// macOS выставляет `__CFBundleIdentifier` процессам, запущенным из приложения (терминал, IDE).
/// По нему Agent Pulse активирует нужное окно по клику на маскота.
func hostBundleId() -> String {
    guard let raw = env("__CFBundleIdentifier") else { return "" }
    return String(raw.unicodeScalars.filter { scalar in
        scalar.isASCII && (scalar.properties.isAlphabetic || ("0"..."9").contains(scalar) || scalar == "." || scalar == "-" || scalar == "_")
    }.map(Character.init))
}

func send(_ bytes: [UInt8], to path: String) {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return }
    defer { close(fd) }

    var on: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    var timeout = timeval(tv_sec: 0, tv_usec: 100_000)
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
        } else if written < 0 && errno == EINTR {
            continue
        } else {
            return
        }
    }
}

let payload = readStdin()
if !payload.isEmpty, let path = socketPath() {
    let header = Array("PULSE1 bundle=\(hostBundleId())\n".utf8)
    send(header + payload, to: path)
}
exit(0)
