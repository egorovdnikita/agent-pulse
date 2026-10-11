import AgentPulseCore
import AppKit
import CoreAudio
import CoreMediaIO

/// Тишина: созвон (микрофон или камера заняты) и полноэкранное окно. Без разрешений:
/// «устройство где-то используется» и размеры окон — без названий приложений и содержимого.
@MainActor
final class QuietSense: Sense {
    let id = SenseID.quiet
    private var timer: Timer?
    private var quiet = false
    private var spaceObserver: NSObjectProtocol?

    func start(emit: @escaping @Sendable (Signal) -> Void) {
        let check: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            let now = Self.microphoneInUse() || Self.cameraInUse() || Self.fullScreenWindow()
            guard now != self.quiet else { return }
            self.quiet = now
            emit(Signal(.quiet, now ? .quietOn : .quietOff))
        }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in MainActor.assumeIsolated { check() } }
        // Переход в полноэкранное приложение — это смена рабочего стола: проверяем сразу.
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { MainActor.assumeIsolated { check() } }
        }
        check()
    }

    func stop() {
        timer?.invalidate()
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
    }

    static func microphoneInUse() -> Bool {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return false }
        var running = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running)
        return running != 0
    }

    static func cameraInUse() -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var size = UInt32(0)
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == 0, size > 0 else { return false }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used = UInt32(0)
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &devices) == 0 else { return false }
        for device in devices {
            var running = UInt32(0)
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            var runningAddress = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
            )
            if CMIOObjectGetPropertyData(device, &runningAddress, 0, nil, runningSize, &runningSize, &running) == 0, running != 0 {
                return true
            }
        }
        return false
    }

    /// Окно обычного уровня, закрывающее экран целиком. Читаем только слой, размеры и pid — не названия.
    static func fullScreenWindow() -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        let ownPid = ProcessInfo.processInfo.processIdentifier
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        // Экраны в координатах CoreGraphics (начало — левый верхний угол главного экрана).
        let screens = NSScreen.screens.map { screen in
            CGRect(x: screen.frame.minX, y: mainHeight - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height)
        }
        for window in windows {
            guard window[kCGWindowLayer as String] as? Int == 0,
                  window[kCGWindowOwnerPID as String] as? Int32 != ownPid,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { continue }
            if screens.contains(where: { abs($0.width - rect.width) < 1 && abs($0.height - rect.height) < 1 && abs($0.minX - rect.minX) < 1 && abs($0.minY - rect.minY) < 1 }) {
                return true
            }
        }
        return false
    }
}
