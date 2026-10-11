import AgentPulseCore
import Foundation
import IOKit.ps

/// Батарея, зарядка, Low Power Mode. События IOKit — без опроса.
@MainActor
final class PowerSense: Sense {
    let id = SenseID.power
    private var emit: (@Sendable (Signal) -> Void)?
    private var source: CFRunLoopSource?
    private var low = Hysteresis(enter: 20, exit: 30)
    private var critical = Hysteresis(enter: 5, exit: 10)
    private var onAC: Bool?
    private var charged = false
    private var observer: NSObjectProtocol?

    func start(emit: @escaping @Sendable (Signal) -> Void) {
        self.emit = emit
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let sense = Unmanaged<PowerSense>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { sense.read() }
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            self.source = source
        }
        observer = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { _ in
            let on = ProcessInfo.processInfo.isLowPowerModeEnabled
            emit(Signal(.power, on ? .lowPowerOn : .lowPowerOff))
        }
        if ProcessInfo.processInfo.isLowPowerModeEnabled { emit(Signal(.power, .lowPowerOn)) }
        read()
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }
        if let observer { NotificationCenter.default.removeObserver(observer) }
        source = nil
    }

    private func read() {
        guard let emit else { return }
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let list = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        guard let battery = list.lazy.compactMap({
            IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any]
        }).first(where: { $0[kIOPSTypeKey] as? String == kIOPSInternalBatteryType }) else { return }

        let capacity = Double(battery[kIOPSCurrentCapacityKey] as? Int ?? 100)
        let maxCapacity = Double(battery[kIOPSMaxCapacityKey] as? Int ?? 100)
        let percent = maxCapacity > 0 ? capacity / maxCapacity * 100 : capacity
        let ac = battery[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
        let isCharged = battery[kIOPSIsChargedKey] as? Bool ?? false

        if let previous = onAC, previous != ac {
            emit(Signal(.power, ac ? .chargerConnected : .chargerDisconnected, value: percent))
        }
        onAC = ac
        if ac, isCharged, !charged { emit(Signal(.power, .fullyCharged, value: percent)) }
        charged = isCharged

        switch critical.update(percent) {
        case .entered: emit(Signal(.power, .batteryCritical, value: percent))
        default: break
        }
        switch low.update(percent) {
        case .entered: if !critical.active { emit(Signal(.power, .batteryLow, value: percent)) }
        case .exited: emit(Signal(.power, .batteryRecovered, value: percent))
        case nil: break
        }
    }
}
