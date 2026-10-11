import Foundation

/// Приём сообщений по unix-сокету: одно соединение = одно сообщение, клиент пишет и закрывает.
/// Сокет доступен только владельцу (0600 в каталоге 0700).
public final class SocketServer: @unchecked Sendable {
    public typealias Handler = @Sendable (Data) -> Void

    public enum Failure: Error, CustomStringConvertible {
        case pathTooLong(String)
        case system(String, Int32)

        public var description: String {
            switch self {
            case .pathTooLong(let path): "путь сокета слишком длинный: \(path)"
            case .system(let call, let code): "\(call): \(String(cString: strerror(code)))"
            }
        }
    }

    public static let maxMessageBytes = 1 << 20

    private let path: String
    private let handler: Handler
    private let queue = DispatchQueue(label: "agentpulse.socket")
    private var source: DispatchSourceRead?

    public init(path: String, handler: @escaping Handler) {
        self.path = path
        self.handler = handler
    }

    deinit {
        source?.cancel()
    }

    public func start() throws {
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = path.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw Failure.pathTooLong(path) }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            pathBytes.withUnsafeBytes { raw.copyMemory(from: $0) }
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure.system("socket", errno) }

        // Остался от прошлого запуска — убираем, иначе bind упадёт с EADDRINUSE.
        unlink(path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else {
            let code = errno
            close(fd)
            throw Failure.system("bind", code)
        }
        chmod(path, 0o600)
        guard listen(fd, 32) == 0 else {
            let code = errno
            close(fd)
            throw Failure.system("listen", code)
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        let handler = handler
        source.setEventHandler {
            Self.acceptPending(listener: fd, handler: handler)
        }
        source.setCancelHandler { [path] in
            close(fd)
            unlink(path)
        }
        source.resume()
        self.source = source
    }

    public func stop() {
        source?.cancel()
        source = nil
    }

    private static func acceptPending(listener: Int32, handler: @escaping Handler) {
        while true {
            let client = accept(listener, nil, nil)
            guard client >= 0 else { return }
            // На BSD принятый сокет наследует O_NONBLOCK — читаем блокирующе с таймаутом.
            _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)
            var timeout = timeval(tv_sec: 1, tv_usec: 0)
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            var on: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            DispatchQueue.global(qos: .userInitiated).async {
                if let data = readAll(client) { handler(data) }
            }
        }
    }

    private static func readAll(_ fd: Int32) -> Data? {
        defer { close(fd) }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
                if data.count > maxMessageBytes { return nil }
            } else if count == 0 {
                return data.isEmpty ? nil : data
            } else if errno == EINTR {
                continue
            } else {
                return nil
            }
        }
    }
}
