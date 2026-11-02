import AgentPulseCore
import AppKit
import DiskArbitration
import IOKit
import IOKit.usb

/// Гости: флешки и внешние диски, iPhone по кабелю. Только факт подключения — ни имён томов, ни файлов.
/// Публичные NSWorkspace, DiskArbitration и IOKit, без разрешений.
@MainActor
final class DeviceSense: Sense {
    let id = SenseID.devices
    private var observers: [NSObjectProtocol] = []
    /// Тома, которые извлекают штатно (пришёл willUnmount) — их уход не «вынули без извлечения».
    private var ejecting: Set<URL> = []
    private var port: IONotificationPortRef?
    private var iterator: io_iterator_t = 0
    private var emit: (@Sendable (Signal) -> Void)?

    func start(emit: @escaping @Sendable (Signal) -> Void) {
        self.emit = emit
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { note in
            guard let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL, Self.isGuest(url) else { return }
            emit(Signal(.devices, .diskMounted))
        })
        observers.append(center.addObserver(forName: NSWorkspace.willUnmountNotification, object: nil, queue: .main) { [weak self] note in
            guard let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            MainActor.assumeIsolated { _ = self?.ejecting.insert(url) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { [weak self] note in
            guard let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                // Штатное извлечение присылает willUnmount заранее; выдернутый диск — только didUnmount.
                if self.ejecting.remove(url) == nil, !url.path.contains("/Volumes/.") {
                    emit(Signal(.devices, .diskYanked))
                }
            }
        })
        watchPhones()
    }

    func stop() {
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers.removeAll()
        if iterator != 0 { IOObjectRelease(iterator) }
        if let port { IONotificationPortDestroy(port) }
        iterator = 0
        port = nil
    }

    /// Гость — съёмный внешний том, а не образ диска (.dmg) и не системный.
    nonisolated static func isGuest(_ url: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.volumeIsInternalKey, .volumeIsLocalKey, .volumeIsBrowsableKey]
        guard let values = try? url.resourceValues(forKeys: keys),
              values.volumeIsInternal == false, values.volumeIsLocal == true, values.volumeIsBrowsable == true,
              let session = DASessionCreate(kCFAllocatorDefault),
              let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL),
              let description = DADiskCopyDescription(disk) as? [String: Any] else { return false }
        let protocolName = description[kDADiskDescriptionDeviceProtocolKey as String] as? String
        let model = description[kDADiskDescriptionDeviceModelKey as String] as? String
        return protocolName != "Virtual Interface" && model != "Disk Image"
    }

    /// iPhone по кабелю: появилось USB-устройство Apple с именем iPhone.
    private func watchPhones() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        self.port = port
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)
        let matching = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary
        matching[kUSBVendorID] = 0x05AC
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOServiceMatchingCallback = { context, iterator in
            guard let context else { return }
            let sense = Unmanaged<DeviceSense>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { sense.drain(iterator, announce: true) }
        }
        guard IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, matching, callback, context, &iterator) == KERN_SUCCESS else { return }
        // Уже подключённые к запуску — не гости.
        drain(iterator, announce: false)
    }

    private func drain(_ iterator: io_iterator_t, announce: Bool) {
        var phone = false
        while case let service = IOIteratorNext(iterator), service != 0 {
            let name = IORegistryEntryCreateCFProperty(service, kUSBProductString as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String
            if name?.contains("iPhone") == true { phone = true }
            IOObjectRelease(service)
        }
        if announce, phone { emit?(Signal(.devices, .phoneConnected)) }
    }
}

/// Большая загрузка: счётчики байтов интерфейсов (`getifaddrs`), раз в 5 s. Что качается — неизвестно.
@MainActor
final class DownloadSense: Sense {
    let id = SenseID.network
    /// Быстрее этого полминуты подряд — «Что-то качается».
    static let threshold = 5.0 // MB/s
    static let hold: TimeInterval = 30
    private var timer: Timer?
    private var last: (Date, UInt64)?
    private var fastSince: Date?
    private var sent = false

    func start(emit: @escaping @Sendable (Signal) -> Void) {
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check(emit) }
        }
    }

    func stop() {
        timer?.invalidate()
    }

    private func check(_ emit: @Sendable (Signal) -> Void) {
        let now = Date()
        let bytes = Self.receivedBytes()
        defer { last = (now, bytes) }
        guard let (then, previous) = last, bytes >= previous else { return }
        let rate = Double(bytes - previous) / now.timeIntervalSince(then) / 1_000_000
        guard rate >= Self.threshold else {
            fastSince = nil
            sent = false
            return
        }
        let since = fastSince ?? then
        fastSince = since
        if !sent, now.timeIntervalSince(since) >= Self.hold {
            sent = true
            emit(Signal(.network, .bigDownload, value: rate))
        }
    }

    /// Принято байт по всем физическим интерфейсам (en*), без петли и туннелей.
    nonisolated static func receivedBytes() -> UInt64 {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return 0 }
        defer { freeifaddrs(head) }
        var total: UInt64 = 0
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard entry.ifa_addr?.pointee.sa_family == UInt8(AF_LINK), String(cString: entry.ifa_name).hasPrefix("en"),
                  let data = entry.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            total += UInt64(data.pointee.ifi_ibytes)
        }
        return total
    }
}
