import AgentPulseCore
import AudioToolbox
import CoreAudio
import Foundation

/// Звук: наушники (Bluetooth или разъём) и громкость на максимуме. Слушатели CoreAudio — без опроса.
@MainActor
final class AudioSense: Sense {
    let id = SenseID.audio
    private var emit: (@Sendable (Signal) -> Void)?
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var headphones = false
    private var loud = Hysteresis(enter: 0.99, exit: 0.9, falling: false)
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    func start(emit: @escaping @Sendable (Signal) -> Void) {
        self.emit = emit
        listen(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal) { [weak self] in
            self?.attach()
        }
        attach()
        headphones = Self.isHeadphones(device)
    }

    func stop() {
        for (object, address, block) in listeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(object, &address, DispatchQueue.main, block)
        }
        listeners.removeAll()
    }

    /// Новое устройство вывода: перевесить слушателей громкости и источника.
    private func attach() {
        listeners.removeAll { entry in
            guard entry.0 != AudioObjectID(kAudioObjectSystemObject) else { return false }
            var address = entry.1
            AudioObjectRemovePropertyListenerBlock(entry.0, &address, DispatchQueue.main, entry.2)
            return true
        }
        device = Self.defaultOutput()
        guard device != kAudioObjectUnknown else { return }
        listen(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput) { [weak self] in
            self?.checkVolume()
        }
        listen(device, kAudioDevicePropertyDataSource, kAudioDevicePropertyScopeOutput) { [weak self] in
            self?.checkHeadphones()
        }
        checkHeadphones()
        checkVolume()
    }

    private func listen(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope, _ action: @escaping @MainActor () -> Void) {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { _, _ in MainActor.assumeIsolated { action() } }
        if AudioObjectAddPropertyListenerBlock(object, &address, DispatchQueue.main, block) == noErr {
            listeners.append((object, address, block))
        }
    }

    private func checkHeadphones() {
        let now = Self.isHeadphones(device)
        guard now != headphones else { return }
        headphones = now
        emit?(Signal(.audio, now ? .headphonesOn : .headphonesOff))
    }

    private func checkVolume() {
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr else { return }
        if loud.update(Double(volume)) == .entered {
            emit?(Signal(.audio, .volumeMax, value: Double(volume)))
        }
    }

    static func defaultOutput() -> AudioObjectID {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return device
    }

    static func isHeadphones(_ device: AudioObjectID) -> Bool {
        var transport = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport)
        if transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE {
            return true
        }
        // Встроенный выход: источник «hdpn» — наушники в разъёме.
        var source = UInt32(0)
        address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDataSource, mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &source) == noErr else { return false }
        return source == 0x6864_706E // 'hdpn'
    }
}
