//
//  SystemAudioMixer.swift
//  OnlySwitch
//
//  Created by OnlySwitch on 2026/07/13.
//

import AppKit
import AudioToolbox
import CoreAudio
import Darwin

/// Detects apps that are currently playing audio and adjusts the volume of any of them through
/// Core Audio process taps (macOS 14.4+).
///
/// Unlike ``SoundMixerService`` (which only reaches scriptable media apps), this works for
/// *any* app that outputs audio — including browsers such as Chrome. There is no public API for
/// an app's output level, so the tap routes that app's audio through a private aggregate device
/// and scales the samples itself: continuous gain `0...1`, of which muting is just the `0` case.
@available(macOS 14.4, *)
@MainActor
final class SystemAudioMixer {

    struct AudioApp: Identifiable {
        /// Every audio process belonging to the app. Browsers play through helper processes and
        /// can have several at once (one per tab), so a tap has to cover all of them.
        var processObjectIDs: [AudioObjectID]
        let pid: pid_t
        let bundleID: String?
        var name: String
        var icon: NSImage?
        /// 0...100. Always 100 while no tap is active — the app's audio is then untouched.
        var volume: Double
        var id: pid_t { pid }
    }

    /// State shared with the realtime callback. Raw memory on purpose: the callback runs on Core
    /// Audio's realtime thread and must not touch the Swift runtime (no ARC, no allocation).
    private struct TapState {
        /// Where the gain should be, 0...1. Written by the main actor, read by the callback.
        var targetGain: Float
        /// Where the gain currently is. Ramped towards `targetGain` to avoid audible clicks.
        var currentGain: Float
        /// False when the tap's format is not Float32 — then the callback can only silence.
        var canScale: Bool
        /// Set once a non-zero sample arrives. Without the audio-capture permission macOS hands
        /// out silence rather than an error, and this is the only way to tell the two apart.
        var sawAudio: Bool
    }

    /// A tap, the aggregate device that makes it effective, and the state its callback reads.
    ///
    /// A tap on its own does nothing at all — creating it succeeds, and the app keeps playing. It
    /// only takes effect once it runs inside a *started* aggregate device, which is why each entry
    /// owns a device and an IOProc rather than just a tap id.
    ///
    /// Deliberately plain data: it is handed between the main actor and the realtime thread, so
    /// nothing in here may be reference-counted.
    private struct AppTap {
        let tapID: AudioObjectID
        let aggregateID: AudioObjectID
        let procID: AudioDeviceIOProcID
        let state: UnsafeMutablePointer<TapState>
        /// The processes this tap was built to cover. A tap only reaches the processes named at
        /// creation, so when the app's set changes (a new browser tab) the tap must be rebuilt.
        let processObjectIDs: [AudioObjectID]
    }

    /// Active mute taps keyed by the owning app's pid.
    /// `nonisolated(unsafe)`: only mutated on the main actor; read once in `deinit`.
    nonisolated(unsafe) private var muteTaps: [pid_t: AppTap] = [:]

    deinit {
        for (_, tap) in muteTaps {
            Self.teardown(tap)
        }
    }

    // MARK: - Enumeration

    /// Apps that are currently outputting audio (plus any we are actively muting), excluding our
    /// own process and the given bundle ids (used to avoid duplicating scriptable apps).
    func audioPlayingApps(excludingBundleIDs excluded: Set<String>) -> [AudioApp] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var byApp: [pid_t: AudioApp] = [:]

        for object in Self.processObjectIDs() {
            guard let pid = Self.pidProperty(of: object) else { continue }

            // Audio is rarely played by the app the user sees: browsers use one helper process per
            // tab, other apps use XPC services. Both must be reported as the owning app.
            guard let owner = Self.owningApplication(of: pid), owner.processIdentifier != ownPID else { continue }
            let bundleID = owner.bundleIdentifier
            if let bundleID, excluded.contains(bundleID) { continue }

            // A tapped process reports no output of its own, so keep every process of a tapped app —
            // otherwise it would vanish from the list and could never be turned back up.
            let tap = muteTaps[owner.processIdentifier]
            guard tap != nil || Self.boolProperty(kAudioProcessPropertyIsRunningOutput, of: object) else { continue }

            byApp[owner.processIdentifier, default:
                AudioApp(processObjectIDs: [],
                         pid: owner.processIdentifier,
                         bundleID: bundleID,
                         name: owner.localizedName ?? bundleID ?? "pid \(owner.processIdentifier)",
                         icon: owner.icon,
                         volume: tap.map { Double($0.state.pointee.targetGain) * 100 } ?? 100)
            ].processObjectIDs.append(object)
        }

        // Drop taps of apps that are gone entirely. Iterate a copy: `destroyTap` mutates `muteTaps`.
        for pid in Array(muteTaps.keys) where byApp[pid] == nil {
            destroyTap(for: pid)
        }

        return byApp.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Volume

    /// Sets `volume` (0...1) for every given process. At full volume the tap is torn down again:
    /// leaving the audio untouched is both cheaper and safer than routing it through us for nothing.
    func setVolume(_ volume: Double, pid: pid_t, processObjectIDs: [AudioObjectID]) {
        let gain = Float(min(1, max(0, volume)))
        guard gain < 1 else {
            destroyTap(for: pid)
            return
        }
        if let tap = muteTaps[pid] {
            // The same set of processes just gets the new gain — the callback ramps to it.
            if Set(tap.processObjectIDs) == Set(processObjectIDs) {
                tap.state.pointee.targetGain = gain
                return
            }
            // The app gained or lost an audio process (e.g. a new browser tab) since the tap was
            // built. A tap only covers the processes it was created with, so rebuild it — otherwise
            // the new process would keep playing at full volume while the row shows it turned down.
            destroyTap(for: pid)
        }
        guard !processObjectIDs.isEmpty else { return }
        muteTaps[pid] = Self.makeAppTap(pid: pid, processObjectIDs: processObjectIDs, gain: gain)
    }

    /// Whether `pid`'s tap is actually receiving audio. `false` while nothing plays, but also when
    /// the audio-capture permission is missing — macOS then delivers silence instead of an error.
    func isReceivingAudio(pid: pid_t) -> Bool {
        muteTaps[pid]?.state.pointee.sawAudio ?? false
    }

    private func destroyTap(for pid: pid_t) {
        guard let tap = muteTaps.removeValue(forKey: pid) else { return }
        Self.teardown(tap)
    }

    /// Builds the whole chain: a muting tap, an aggregate device around the current output device
    /// that carries it, and a running IOProc. Returns `nil` — having cleaned up whatever was
    /// already created — if any step fails.
    ///
    /// `nonisolated` is load-bearing: the IOProc block below would otherwise inherit this type's
    /// main-actor isolation, and Core Audio calls it on a realtime thread. The resulting isolation
    /// check traps (`SIGTRAP`) on the very first audio callback.
    private nonisolated static func makeAppTap(pid: pid_t, processObjectIDs: [AudioObjectID],
                                              gain: Float) -> AppTap? {
        let description = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
        description.muteBehavior = .muted
        description.name = "OnlySwitch-mute-\(pid)"
        description.isPrivate = true

        var tapID = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr, tapID != kAudioObjectUnknown else {
            return nil
        }
        guard let tapUID = stringProperty(kAudioTapPropertyUID, of: tapID),
              let output = defaultOutputDevice(),
              let outputUID = stringProperty(kAudioDevicePropertyDeviceUID, of: output) else {
            AudioHardwareDestroyProcessTap(tapID)
            return nil
        }

        // The UID must be unique per device: reusing one that still exists fails with 'nope',
        // which silently broke every re-tap.
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "OnlySwitch Mute \(pid)",
            kAudioAggregateDeviceUIDKey: "com.onlyswitch.mute.\(pid).\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: tapUID,
            ]],
        ]
        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID) == noErr,
              aggregateID != kAudioObjectUnknown else {
            AudioHardwareDestroyProcessTap(tapID)
            return nil
        }

        // Scaling reinterprets the bytes as Float32. Verify that rather than assume it — "float"
        // alone is not enough (Float64 would be 8 bytes per sample), so require 32-bit too. On a
        // format we do not understand we would emit noise, so fall back to silencing.
        let canScale = tapFormat(of: tapID).map {
            $0.mFormatFlags & kAudioFormatFlagIsFloat != 0 && $0.mBitsPerChannel == 32
        } ?? false

        let state = UnsafeMutablePointer<TapState>.allocate(capacity: 1)
        state.initialize(to: TapState(targetGain: gain, currentGain: gain, canScale: canScale, sawAudio: false))

        // The device must actually run for the tap to take effect. The callback reads the app's
        // audio, scales it, and writes it to the real output — that is the whole volume control.
        var procID: AudioDeviceIOProcID?
        let ioStatus = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) {
            _, inInputData, _, outOutputData, _ in
            let outputs = UnsafeMutableAudioBufferListPointer(outOutputData)
            let target = state.pointee.targetGain

            // Silent path: no samples needed, so this works even without the capture permission.
            guard target > 0, state.pointee.canScale else {
                for index in 0..<outputs.count {
                    guard let data = outputs[index].mData else { continue }
                    memset(data, 0, Int(outputs[index].mDataByteSize))
                }
                state.pointee.currentGain = 0
                return
            }

            let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
            var gainCursor = state.pointee.currentGain
            var heard = false

            for index in 0..<outputs.count {
                guard let destination = outputs[index].mData else { continue }
                let outBytes = Int(outputs[index].mDataByteSize)
                guard index < inputs.count, let source = inputs[index].mData else {
                    memset(destination, 0, outBytes)
                    continue
                }
                let bytes = min(Int(inputs[index].mDataByteSize), outBytes)
                let count = bytes / MemoryLayout<Float>.size
                let src = source.assumingMemoryBound(to: Float.self)
                let dst = destination.assumingMemoryBound(to: Float.self)
                // Ramp across the buffer instead of jumping: a hard gain change clicks audibly.
                let step = count > 0 ? (target - gainCursor) / Float(count) : 0
                var g = gainCursor
                for frame in 0..<count {
                    g += step
                    let sample = src[frame]
                    if sample != 0 { heard = true }
                    dst[frame] = sample * g
                }
                gainCursor = g
                // Never leave the remainder of an output buffer stale.
                if outBytes > bytes {
                    memset(destination.advanced(by: bytes), 0, outBytes - bytes)
                }
            }
            state.pointee.currentGain = gainCursor
            if heard { state.pointee.sawAudio = true }
        }
        guard ioStatus == noErr, let procID else {
            state.deallocate()
            AudioHardwareDestroyAggregateDevice(aggregateID)
            AudioHardwareDestroyProcessTap(tapID)
            return nil
        }
        guard AudioDeviceStart(aggregateID, procID) == noErr else {
            AudioDeviceDestroyIOProcID(aggregateID, procID)
            state.deallocate()
            AudioHardwareDestroyAggregateDevice(aggregateID)
            AudioHardwareDestroyProcessTap(tapID)
            return nil
        }
        return AppTap(tapID: tapID, aggregateID: aggregateID, procID: procID, state: state,
                      processObjectIDs: processObjectIDs)
    }

    /// `nonisolated`: only touches Core Audio C calls, and `deinit` has to reach it.
    private nonisolated static func teardown(_ tap: AppTap) {
        // Order matters: stop the device before the callback's state goes away.
        AudioDeviceStop(tap.aggregateID, tap.procID)
        AudioDeviceDestroyIOProcID(tap.aggregateID, tap.procID)
        AudioHardwareDestroyAggregateDevice(tap.aggregateID)
        AudioHardwareDestroyProcessTap(tap.tapID)
        tap.state.deallocate()
    }

    // MARK: - Process ownership

    /// The app a given audio process belongs to: the process itself when it is a normal app, or
    /// the app that spawned it when it is a helper process. `nil` for daemons with no user-facing app.
    private static func owningApplication(of pid: pid_t) -> NSRunningApplication? {
        if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular {
            return app
        }
        // XPC services are children of launchd, so only the responsible process leads back to the app.
        if let responsible = responsiblePID(of: pid), responsible != pid,
           let app = NSRunningApplication(processIdentifier: responsible), app.activationPolicy == .regular {
            return app
        }
        // Helpers spawned by their app directly (Chrome's renderers) are found by walking up.
        var current = parentPID(of: pid)
        var hops = 0
        while let candidate = current, candidate > 1, hops < 4 {
            if let app = NSRunningApplication(processIdentifier: candidate), app.activationPolicy == .regular {
                return app
            }
            current = parentPID(of: candidate)
            hops += 1
        }
        return nil
    }

    private static func parentPID(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let ppid = info.kp_eproc.e_ppid
        return ppid > 0 ? ppid : nil
    }

    /// `responsibility_get_pid_responsible_for_pid` is SPI, so it is looked up at runtime; if it
    /// ever disappears the parent-chain walk above still covers the common cases.
    private static let responsibleForPID: (@convention(c) (pid_t) -> pid_t)? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), // RTLD_DEFAULT
                                 "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (pid_t) -> pid_t).self)
    }()

    private static func responsiblePID(of pid: pid_t) -> pid_t? {
        guard let resolve = responsibleForPID else { return nil }
        let responsible = resolve(pid)
        return responsible > 0 ? responsible : nil
    }

    // MARK: - Core Audio helpers

    private static func processObjectIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var dataSize: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &dataSize) == noErr else { return [] }
        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &dataSize, &ids) == noErr else { return [] }
        return ids
    }

    private static func pidProperty(of object: AudioObjectID) -> pid_t? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var dataSize = UInt32(MemoryLayout<pid_t>.size)
        var pid: pid_t = -1
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &dataSize, &pid) == noErr, pid > 0 else { return nil }
        return pid
    }

    private static func boolProperty(_ selector: AudioObjectPropertySelector, of object: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        var value: UInt32 = 0
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &dataSize, &value) == noErr else { return false }
        return value != 0
    }

    private nonisolated static func stringProperty(_ selector: AudioObjectPropertySelector,
                                                   of object: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString?
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &dataSize, $0)
        }
        guard status == noErr, let value else { return nil }
        let string = value as String
        return string.isEmpty ? nil : string
    }

    /// The tap's stream format. Used to confirm the samples really are Float32 before scaling them.
    private nonisolated static func tapFormat(of tapID: AudioObjectID) -> AudioStreamBasicDescription? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var format = AudioStreamBasicDescription()
        var dataSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(tapID, &address, 0, nil, &dataSize, &format) == noErr else { return nil }
        return format
    }

    private nonisolated static func defaultOutputDevice() -> AudioObjectID? {
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
}
