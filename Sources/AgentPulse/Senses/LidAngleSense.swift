import AgentPulseCore
import Foundation
import IOKit.hid

/// Эксперимент: угол крышки MacBook через неофициальный HID-датчик. За флагом, при неудаче молча выключается.
@MainActor
final class LidAngleSense: Sense {
    let id = SenseID.lidAngle
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var timer: Timer?
    private var last: Double?

    func start(emit: @escaping @Sendable (Signal) -> Void) {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: 0x05AC, kIOHIDProductIDKey: 0x8104,
            kIOHIDPrimaryUsagePageKey: 0x0020, kIOHIDPrimaryUsageKey: 0x008A,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess,
              let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let device = devices.first,
              IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return }
        self.manager = manager
        self.device = device
        // Датчик отдаёт угол только по запросу — опрос раз в секунду, пока эксперимент включён.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let angle = self.read() else { return }
                if self.last.map({ abs($0 - angle) >= 3 }) ?? true {
                    self.last = angle
                    emit(Signal(.lidAngle, .lidAngle, value: angle))
                }
            }
        }
    }

    private func read() -> Double? {
        guard let device else { return nil }
        var report = [UInt8](repeating: 0, count: 8)
        var length = CFIndex(report.count)
        guard IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &report, &length) == kIOReturnSuccess, length >= 3 else {
            return nil
        }
        return Double(UInt16(report[1]) | UInt16(report[2]) << 8)
    }

    func stop() {
        timer?.invalidate()
        if let device { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
        if let manager { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
    }
}
