//
//  SoundMixerService.swift
//  OnlySwitch
//
//  Created by OnlySwitch on 2026/07/13.
//

import AppKit
import CoreAudio
import Extensions
import Switches

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

    /// The system output volume in `0...100`, or `nil` if it could not be read.
    func systemVolume() async -> Int? {
        guard let raw = try? await VolumeCMD.getOutput.runAppleScript() else { return nil }
        return Int(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func setSystemVolume(_ value: Int) async {
        _ = try? await (VolumeCMD.setOutput + String(value.clampedToVolume)).runAppleScript()
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

    private static func symbolName(for device: AudioObjectID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        var transport: UInt32 = 0
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &dataSize, &transport) == noErr else {
            return "hifispeaker.fill"
        }
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
