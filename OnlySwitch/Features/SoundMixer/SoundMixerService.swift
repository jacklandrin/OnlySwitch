//
//  SoundMixerService.swift
//  OnlySwitch
//
//  Created by OnlySwitch on 2026/07/13.
//

import AppKit
import AudioToolbox
import CoreAudio
import DisplayDDC
import Extensions
import Switches
import SoundMixerEQ

/// Discovers controllable running apps and reads/writes their volume through AppleScript.
@MainActor
struct SoundMixerService {

    struct RunningApp {
        let app: ScriptableAudioApp
        let icon: NSImage?
    }

    /// The known scriptable-audio apps that are currently running, de-duplicated by bundle id.
    func runningControllableApps() -> [RunningApp] {
        var seen = Set<String>()
        var result: [RunningApp] = []
        for running in NSWorkspace.shared.runningApplications {
            guard let bundleID = running.bundleIdentifier,
                  let app = ScriptableAudioApp.known(forBundleID: bundleID),
                  !seen.contains(bundleID) else { continue }
            seen.insert(bundleID)
            result.append(RunningApp(app: app, icon: running.icon))
        }
        return result
    }

    /// The current volume of `app` in `0...100`, or `nil` if it could not be read.
    func volume(of app: ScriptableAudioApp) async -> Int? {
        guard let raw = try? await app.getVolumeCommand.runAppleScript() else { return nil }
        return Int(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func setVolume(_ value: Int, of app: ScriptableAudioApp) async {
        _ = try? await app.setVolumeCommand(value.clampedToVolume).runAppleScript()
    }

    /// How the master slider reaches the current output device.
    enum SystemVolumeControl: Equatable {
        /// macOS owns the device's volume.
        case system
        /// The device has no macOS volume; its display is controlled over DDC/CI.
        case display(audioDeviceName: String)
        /// Neither macOS nor DDC can change this device's volume.
        case unavailable
    }

    /// The output volume in `0...100` and how it was reached. `value` is `nil` if it could not be read.
    func systemVolume() async -> (control: SystemVolumeControl, value: Int?) {
        switch Self.systemVolumeControl() {
        case .system:
            guard let raw = try? await VolumeCMD.getOutput.runAppleScript() else { return (.system, nil) }
            return (.system, Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)))
        case let .display(name):
            guard let value = await DDCDisplayController.shared.speakerVolume(forAudioDeviceNamed: name) else {
                return (.unavailable, nil)
            }
            return (.display(audioDeviceName: name), value)
        case .unavailable:
            return (.unavailable, nil)
        }
    }

    func setSystemVolume(_ value: Int, via control: SystemVolumeControl) async {
        switch control {
        case .system:
            _ = try? await (VolumeCMD.setOutput + String(value.clampedToVolume)).runAppleScript()
        case let .display(name):
            await DDCDisplayController.shared.setSpeakerVolume(value.clampedToVolume, forAudioDeviceNamed: name)
        case .unavailable:
            break
        }
    }

    /// DisplayPort/HDMI monitors usually expose no volume to macOS (`output volume` is
    /// `missing value`), but many accept DDC/CI from the Mac instead.
    private static func systemVolumeControl() -> SystemVolumeControl {
        guard let device = defaultOutputDeviceID() else { return .system }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var settable: DarwinBoolean = false
        if AudioObjectHasProperty(device, &address),
           AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue {
            return .system
        }
        // Only display audio: another device (e.g. a Thunderbolt interface) must never fall back
        // to changing a connected monitor's volume.
        guard transportType(of: device).map({ [kAudioDeviceTransportTypeDisplayPort,
                                               kAudioDeviceTransportTypeHDMI].contains($0) }) == true,
              let name = deviceName(of: device) else { return .unavailable }
        return .display(audioDeviceName: name)
    }

    // MARK: - Output device

    /// Name and transport of the current default output device, mirroring the "Output" section of
    /// the system sound panel. `nil` when Core Audio reports no usable default device.
    func currentOutputDevice() -> OutputDevice? {
        guard let device = Self.defaultOutputDeviceID(),
              let name = Self.deviceName(of: device) else { return nil }
        return OutputDevice(name: name, symbolName: Self.symbolName(for: device))
    }

    struct OutputDevice: Equatable {
        let name: String
        /// SF Symbol picked from the device's transport type, like the system panel does.
        let symbolName: String
    }

    struct OutputEndpoint: Equatable, Sendable {
        let objectID: AudioObjectID
        let device: OutputRouteDevice
        let sampleRate: Double
        let formatSignature: Int
    }

    /// Keep alive listeners on HAL-listed devices even while they temporarily have no usable
    /// output. Some wireless devices change only DeviceIsAlive when reconnecting.
    func outputObservationDeviceIDs() -> Set<AudioObjectID> {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard !ids.isEmpty, AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return Set(ids.filter { id in
            guard let uid = Self.stringProperty(kAudioDevicePropertyDeviceUID, of: id) else { return true }
            return !uid.hasPrefix("com.onlyswitch.audio.") && !uid.hasPrefix("com.onlyswitch.mute.")
        })
    }

    /// Only alive output devices; our private per-App aggregates are never selectable destinations.
    func outputEndpoints() -> [OutputEndpoint] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard !ids.isEmpty, AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        let defaultID = Self.defaultOutputDeviceID()
        return ids.compactMap { id -> OutputEndpoint? in
            guard let uid = Self.stringProperty(kAudioDevicePropertyDeviceUID, of: id),
                  !uid.hasPrefix("com.onlyswitch.audio."), !uid.hasPrefix("com.onlyswitch.mute."),
                  let name = Self.deviceName(of: id), let channels = Self.outputChannelCount(id),
                  (1...64).contains(channels) else { return nil }
            var alive: UInt32 = 0
            var count = UInt32(MemoryLayout<UInt32>.size)
            var property = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsAlive,
                                                      mScope: kAudioObjectPropertyScopeGlobal,
                                                      mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(id, &property, 0, nil, &count, &alive) == noErr, alive != 0 else { return nil }
            property.mSelector = kAudioDevicePropertyNominalSampleRate
            var rate: Double = 0
            count = UInt32(MemoryLayout<Double>.size)
            guard AudioObjectGetPropertyData(id, &property, 0, nil, &count, &rate) == noErr,
                  rate.isFinite, rate > 0 else { return nil }
            return OutputEndpoint(objectID: id, device: .init(id: uid, name: name, isDefault: id == defaultID,
                                                            channelCount: channels), sampleRate: rate,
                                  formatSignature: Self.outputFormatSignature(id))
        }.sorted { $0.device.id < $1.device.id }
    }

    /// Includes raw virtual stream formats and buffer layout, so duplicate HAL notifications
    /// are harmless while real format changes still invalidate an active routing chain.
    private static func outputFormatSignature(_ device: AudioObjectID) -> Int {
        var hasher = Hasher()
        for selector in [kAudioDevicePropertyStreams, kAudioDevicePropertyStreamConfiguration] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput,
                                                     mElement: kAudioObjectPropertyElementMain)
            var size: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr,
                  size > 0, size <= 65_536 else { hasher.combine(selector); continue }
            let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
            defer { storage.deallocate() }
            guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, storage) == noErr else { continue }
            if selector == kAudioDevicePropertyStreams {
                let streams = storage.assumingMemoryBound(to: AudioObjectID.self)
                for index in 0..<(Int(size) / MemoryLayout<AudioObjectID>.size) {
                    var formatAddress = AudioObjectPropertyAddress(mSelector: kAudioStreamPropertyVirtualFormat,
                                                                  mScope: kAudioObjectPropertyScopeGlobal,
                                                                  mElement: kAudioObjectPropertyElementMain)
                    var format = AudioStreamBasicDescription()
                    var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
                    hasher.combine(streams[index])
                    if AudioObjectGetPropertyData(streams[index], &formatAddress, 0, nil, &formatSize, &format) == noErr {
                        hasher.combine(format.mSampleRate.bitPattern); hasher.combine(format.mFormatID)
                        hasher.combine(format.mFormatFlags); hasher.combine(format.mBytesPerPacket)
                        hasher.combine(format.mFramesPerPacket); hasher.combine(format.mBytesPerFrame)
                        hasher.combine(format.mChannelsPerFrame); hasher.combine(format.mBitsPerChannel)
                    }
                }
            } else if size >= MemoryLayout<AudioBufferList>.size {
                let list = storage.assumingMemoryBound(to: AudioBufferList.self)
                let count = Int(list.pointee.mNumberBuffers)
                if count > 0, count <= 64,
                   Int(size) >= MemoryLayout<AudioBufferList>.size + (count - 1) * MemoryLayout<AudioBuffer>.size {
                    for buffer in UnsafeMutableAudioBufferListPointer(list) { hasher.combine(buffer.mNumberChannels) }
                }
            }
        }
        return hasher.finalize()
    }

    private static func outputChannelCount(_ device: AudioObjectID) -> Int? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                 mScope: kAudioDevicePropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioBufferList>.size, size <= 65_536 else { return nil }
        let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, storage) == noErr else { return nil }
        let list = storage.assumingMemoryBound(to: AudioBufferList.self)
        let count = Int(list.pointee.mNumberBuffers)
        guard count > 0, count <= 64,
              Int(size) >= MemoryLayout<AudioBufferList>.size + (count - 1) * MemoryLayout<AudioBuffer>.size else { return nil }
        return UnsafeMutableAudioBufferListPointer(list).reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func stringProperty(_ selector: AudioObjectPropertySelector, of device: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var result: CFString?
        let status = withUnsafeMutablePointer(to: &result) { AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0) }
        guard status == noErr, let result, !(result as String).isEmpty else { return nil }
        return result as String
    }

    private static func defaultOutputDeviceID() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        var device = AudioObjectID(kAudioObjectUnknown)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                         &dataSize, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        return device
    }

    private static func deviceName(of device: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString?
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(device, &address, 0, nil, &dataSize, $0)
        }
        guard status == noErr, let value else { return nil }
        let name = value as String
        return name.isEmpty ? nil : name
    }

    private static func transportType(of device: AudioObjectID) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        var transport: UInt32 = 0
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &dataSize, &transport) == noErr else { return nil }
        return transport
    }

    private static func symbolName(for device: AudioObjectID) -> String {
        guard let transport = transportType(of: device) else { return "hifispeaker.fill" }
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn:   return "laptopcomputer"
        case kAudioDeviceTransportTypeBluetooth,
             kAudioDeviceTransportTypeBluetoothLE: return "airpodspro"
        case kAudioDeviceTransportTypeAirPlay:   return "airplayaudio"
        case kAudioDeviceTransportTypeDisplayPort,
             kAudioDeviceTransportTypeHDMI:      return "display"
        case kAudioDeviceTransportTypeUSB:       return "hifispeaker.fill"
        case kAudioDeviceTransportTypeVirtual,
             kAudioDeviceTransportTypeAggregate: return "waveform"
        default:                                 return "hifispeaker.fill"
        }
    }
}

private extension Int {
    /// Clamped into the valid volume range `0...100`.
    var clampedToVolume: Int { Swift.min(100, Swift.max(0, self)) }
}
