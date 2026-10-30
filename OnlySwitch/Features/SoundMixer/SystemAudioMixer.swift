import AppKit
import AudioToolbox
import CoreAudio
import CSoundMixerEQ
import Darwin
import SoundMixerEQ

/// Shared owner of private process-tap chains. All control operations stay on the main actor;
/// the IOProc calls only the preallocated C processor.
@available(macOS 14.4, *)
@MainActor
final class SystemAudioMixer {
    struct AudioApp: Identifiable {
        var processObjectIDs: [AudioObjectID]
        let pid: pid_t
        let bundleID: String?
        var name: String
        var icon: NSImage?
        var volume: Double
        var id: pid_t { pid }
    }

    /// No ARC-backed fields: teardown may also run from deinit outside the main actor.
    private struct AppTap {
        let tapID: AudioObjectID
        let aggregateID: AudioObjectID
        let procID: AudioDeviceIOProcID
        let state: OpaquePointer
        let processSignature: UInt64
        let outputSignature: Int
        let sampleRate: Double
    }
    private struct Configuration {
        var gain: Double
        var processes: [AudioObjectID]
        var settings: EqualizerSettings
        var routing: OutputRouteSelection
        var ownerBundleID: String?
        var ownerLaunchDate: Date?
        var helperGeneration: UUID?
    }
    nonisolated(unsafe) private var muteTaps: [pid_t: AppTap] = [:]
    private var configurations: [pid_t: Configuration] = [:]
    private struct PlaybackHelper {
        let pid: pid_t
        let generation: UUID
        let isAlive: @MainActor () -> Bool
    }
    private var playbackHelper: PlaybackHelper?

    /// Register only the child retained by the playback owner. A generation belongs to one
    /// Process instance, so a recycled PID cannot inherit a previous player's tap.
    @discardableResult
    func configurePlaybackHelper(pid: pid_t, generation: UUID,
                                 isAlive: @escaping @MainActor () -> Bool) -> Bool {
        guard pid > 0, pid != ProcessInfo.processInfo.processIdentifier,
              isAlive(), Self.parentPID(of: pid) == ProcessInfo.processInfo.processIdentifier else {
            releasePlaybackHelper()
            return false
        }
        if let previous = playbackHelper, previous.pid != pid || previous.generation != generation {
            releasePlaybackHelper()
        }
        playbackHelper = PlaybackHelper(pid: pid, generation: generation, isAlive: isAlive)
        return true
    }

    func releasePlaybackHelper() {
        guard let helper = playbackHelper else { return }
        destroyTap(for: helper.pid)
        configurations[helper.pid] = nil
        playbackHelper = nil
    }

    func playbackHelperProcessObjectIDs() -> [AudioObjectID] {
        guard let helper = playbackHelper,
              playbackHelperIsCurrent(pid: helper.pid, generation: helper.generation) else { return [] }
        return Self.processObjectIDs().filter { Self.pidProperty(of: $0) == helper.pid }
    }

    private func playbackHelperIsCurrent(pid: pid_t, generation: UUID) -> Bool {
        guard let helper = playbackHelper, helper.pid == pid, helper.generation == generation,
              pid != ProcessInfo.processInfo.processIdentifier, helper.isAlive() else { return false }
        return Self.parentPID(of: pid) == ProcessInfo.processInfo.processIdentifier
    }
    // Keep callback allocations retired for the process lifetime. A callback can arrive after
    // AudioDeviceStop; its atomic retirement gate must remain readable even then.
    nonisolated(unsafe) private static var retiredStates: [OpaquePointer] = []
    private nonisolated static let retiredStatesLock = NSLock()
    nonisolated(unsafe) private var outputListener: AudioObjectPropertyListenerBlock?
    nonisolated(unsafe) private var deviceListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var endpointSnapshot: [SoundMixerService.OutputEndpoint] = []
    var onOutputDevicesChanged: (@MainActor () -> Void)?

    init() {
        endpointSnapshot = SoundMixerService().outputEndpoints()
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.handleDeviceChange() }
        }
        outputListener = listener
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDevices] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        }
        updateDeviceListeners()
    }

    deinit {
        if let outputListener {
            for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDevices] {
                var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                         mElement: kAudioObjectPropertyElementMain)
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, outputListener)
            }
        }
        for (device, listener) in deviceListeners {
            Self.removeDeviceListener(listener, from: device)
        }
        for tap in muteTaps.values { Self.teardown(tap) }
    }

    private func updateDeviceListeners() {
        let ids = SoundMixerService().outputObservationDeviceIDs()
        for id in Array(deviceListeners.keys) where !ids.contains(id) {
            if let listener = deviceListeners.removeValue(forKey: id) { Self.removeDeviceListener(listener, from: id) }
        }
        for id in ids where deviceListeners[id] == nil {
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.handleDeviceChange() }
            }
            deviceListeners[id] = listener
            for selector in [kAudioDevicePropertyNominalSampleRate, kAudioDevicePropertyDeviceIsAlive,
                             kAudioDevicePropertyStreamFormat, kAudioDevicePropertyStreamConfiguration] {
                var address = Self.deviceListenerAddress(selector)
                AudioObjectAddPropertyListenerBlock(id, &address, .main, listener)
            }
        }
    }
    private nonisolated static func deviceListenerAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector,
            mScope: selector == kAudioDevicePropertyStreamFormat || selector == kAudioDevicePropertyStreamConfiguration
                ? kAudioDevicePropertyScopeOutput : kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
    }
    private nonisolated static func removeDeviceListener(_ listener: @escaping AudioObjectPropertyListenerBlock, from device: AudioObjectID) {
        for selector in [kAudioDevicePropertyNominalSampleRate, kAudioDevicePropertyDeviceIsAlive,
                         kAudioDevicePropertyStreamFormat, kAudioDevicePropertyStreamConfiguration] {
            var address = deviceListenerAddress(selector)
            AudioObjectRemovePropertyListenerBlock(device, &address, .main, listener)
        }
    }
    private func handleDeviceChange() {
        let endpoints = SoundMixerService().outputEndpoints()
        // Ignore our own aggregate add/remove notifications. Failed setup must not retry itself
        // forever through kAudioHardwarePropertyDevices notifications.
        // Listener maintenance is independent of the usable endpoint snapshot: dead devices
        // remain observed until HAL actually removes their object IDs.
        updateDeviceListeners()
        guard endpoints != endpointSnapshot else { return }
        endpointSnapshot = endpoints
        for (pid, config) in Array(configurations) {
            _ = setConfiguration(gain: config.gain, settings: config.settings, pid: pid,
                                 processObjectIDs: config.processes, live: false, routing: config.routing)
        }
        onOutputDevicesChanged?()
    }

    private nonisolated static func signature(of ids: [AudioObjectID]) -> UInt64 {
        var sum: UInt64 = 0, xor: UInt64 = 0
        for id in ids { let mixed = UInt64(id) &* 0x9E37_79B9_7F4A_7C15; sum = sum &+ mixed; xor ^= mixed }
        return sum ^ (xor &* 31) ^ UInt64(ids.count)
    }

    func audioPlayingApps(excludingBundleIDs excluded: Set<String>) -> [AudioApp] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        if let helper = playbackHelper,
           !playbackHelperIsCurrent(pid: helper.pid, generation: helper.generation) {
            releasePlaybackHelper()
        }
        var byApp: [pid_t: AudioApp] = [:]
        for object in Self.processObjectIDs() {
            guard let pid = Self.pidProperty(of: object), pid != playbackHelper?.pid,
                  let owner = Self.owningApplication(of: pid),
                  owner.processIdentifier != ownPID else { continue }
            let bundleID = owner.bundleIdentifier
            if let bundleID, excluded.contains(bundleID) { continue }
            if let config = configurations[owner.processIdentifier],
               config.ownerBundleID != bundleID || config.ownerLaunchDate != owner.launchDate {
                destroyTap(for: owner.processIdentifier)
                configurations[owner.processIdentifier] = nil
            }
            let tap = muteTaps[owner.processIdentifier]
            let retained = configurations[owner.processIdentifier].map {
                EqualizerTapPolicy.requiresTap(gain: $0.gain, settings: $0.settings, hasExplicitRoute: !$0.routing.followsSystem)
            } ?? false
            guard tap != nil || retained || Self.boolProperty(kAudioProcessPropertyIsRunningOutput, of: object) else { continue }
            byApp[owner.processIdentifier, default: AudioApp(processObjectIDs: [], pid: owner.processIdentifier,
                bundleID: bundleID, name: owner.localizedName ?? bundleID ?? "pid \(owner.processIdentifier)",
                icon: owner.icon, volume: tap.map { Double(OSEQGetGain($0.state)) * 100 }
                    ?? configurations[owner.processIdentifier].map { $0.gain * 100 } ?? 100)
            ].processObjectIDs.append(object)
        }
        for pid in Set(muteTaps.keys).union(configurations.keys) {
            let alive: Bool
            if let generation = configurations[pid]?.helperGeneration {
                alive = playbackHelperIsCurrent(pid: pid, generation: generation)
            } else {
                alive = NSRunningApplication(processIdentifier: pid)?.isTerminated == false
            }
            if !alive { destroyTap(for: pid); configurations[pid] = nil }
        }
        return byApp.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func setVolume(_ volume: Double, pid: pid_t, processObjectIDs: [AudioObjectID], live: Bool) {
        _ = setConfiguration(gain: volume, settings: configurations[pid]?.settings ?? .flat,
                             pid: pid, processObjectIDs: processObjectIDs, live: live,
                             routing: configurations[pid]?.routing ?? .init())
    }

    @discardableResult
    func setConfiguration(gain: Double, settings: EqualizerSettings, pid: pid_t,
                          processObjectIDs: [AudioObjectID], live: Bool, routing: OutputRouteSelection = .init()) -> Bool {
        // The host renders every processed app: tapping it would create an audio feedback loop.
        guard pid != ProcessInfo.processInfo.processIdentifier else { return false }
        let helperGeneration = playbackHelper.flatMap { $0.pid == pid ? $0.generation : nil }
        if let helperGeneration,
           !playbackHelperIsCurrent(pid: pid, generation: helperGeneration) {
            destroyTap(for: pid); configurations[pid] = nil
            return false
        }
        let gain = gain.isFinite ? min(1, max(0, gain)) : 1
        let previous = configurations[pid]
        let owner = NSRunningApplication(processIdentifier: pid)
        if let previous {
            let sameOwner = previous.helperGeneration == helperGeneration &&
                (helperGeneration != nil || (previous.ownerBundleID == owner?.bundleIdentifier &&
                                             previous.ownerLaunchDate == owner?.launchDate))
            guard sameOwner else { destroyTap(for: pid); configurations[pid] = nil; return false }
        }
        configurations[pid] = Configuration(gain: gain, processes: processObjectIDs, settings: settings, routing: routing,
                                            ownerBundleID: owner?.bundleIdentifier, ownerLaunchDate: owner?.launchDate,
                                            helperGeneration: helperGeneration)
        let needsTap = EqualizerTapPolicy.requiresTap(gain: gain, settings: settings, hasExplicitRoute: !routing.followsSystem)
        if !needsTap && !live { destroyTap(for: pid); return true }
        let endpoints = SoundMixerService().outputEndpoints()
        let resolution = OutputRouteResolution(selection: routing, devices: endpoints.map(\.device))
        let outputs = endpoints.filter { resolution.onlineUIDs.contains($0.device.id) }
        guard !outputs.isEmpty else { destroyTap(for: pid); return false }
        var hasher = Hasher()
        for output in outputs {
            hasher.combine(output.objectID); hasher.combine(output.device.id)
            hasher.combine(output.sampleRate); hasher.combine(output.device.channelCount)
            hasher.combine(output.formatSignature)
        }
        let outputSignature = hasher.finalize()
        // Validate the helper before the cached-tap fast path too. A dead child or stale HAL
        // object must never continue rendering after a reconnect or PID reuse.
        if helperGeneration != nil {
            guard !processObjectIDs.isEmpty,
                  processObjectIDs.allSatisfy({ Self.pidProperty(of: $0) == pid }) else {
                destroyTap(for: pid)
                return false
            }
        }
        if let tap = muteTaps[pid] {
            if tap.processSignature == Self.signature(of: processObjectIDs), tap.outputSignature == outputSignature {
                OSEQSetGain(tap.state, Float(gain))
                if previous?.settings != settings { EqualizerDSP.publish(settings, sampleRate: tap.sampleRate, to: tap.state) }
                return true
            }
            destroyTap(for: pid)
        }
        guard needsTap || live, !processObjectIDs.isEmpty else { return !needsTap }
        // Device reconnects may happen long after a source exited. Never reuse a stale PID/audio
        // object association when restoring its desired route from the listener.
        guard helperGeneration != nil || NSRunningApplication(processIdentifier: pid)?.isTerminated == false else {
            configurations[pid] = nil; return false
        }
        guard processObjectIDs.allSatisfy({ object in
            guard let processPID = Self.pidProperty(of: object) else { return false }
            if helperGeneration != nil { return processPID == pid }
            guard let owner = Self.owningApplication(of: processPID) else { return false }
            return owner.processIdentifier == pid
        }) else {
            // The owner still exists, but a browser/helper may be rebuilding its audio object.
            // Keep gain/EQ/routing intent until refresh supplies its new process handles.
            return false
        }
        guard let tap = Self.makeAppTap(pid: pid, processObjectIDs: processObjectIDs, gain: Float(gain),
                                        settings: settings, outputs: outputs, outputSignature: outputSignature) else { return false }
        muteTaps[pid] = tap
        return true
    }

    func isReceivingAudio(pid: pid_t) -> Bool { muteTaps[pid].map { OSEQSawAudio($0.state) } ?? false }
    func releaseAllTaps() {
        configurations.removeAll()
        for pid in Array(muteTaps.keys) { destroyTap(for: pid) }
    }
    private func destroyTap(for pid: pid_t) {
        guard let tap = muteTaps.removeValue(forKey: pid) else { return }
        Self.teardown(tap)
    }

    private nonisolated static func makeAppTap(pid: pid_t, processObjectIDs: [AudioObjectID], gain: Float,
                                               settings: EqualizerSettings, outputs: [SoundMixerService.OutputEndpoint],
                                               outputSignature: Int) -> AppTap? {
        let description = CATapDescription(stereoMixdownOfProcesses: processObjectIDs.map { $0 })
        description.muteBehavior = .muted
        description.name = "OnlySwitch-audio-\(pid)"
        description.isPrivate = true
        var tapID = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr, tapID != kAudioObjectUnknown else { return nil }
        guard let tapUID = stringProperty(kAudioTapPropertyUID, of: tapID),
              let outputUID = outputs.first?.device.id,
              let format = tapFormat(of: tapID), supported(format) else {
            AudioHardwareDestroyProcessTap(tapID); return nil
        }
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "OnlySwitch Audio \(pid)",
            kAudioAggregateDeviceUIDKey: "com.onlyswitch.audio.\(pid).\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: outputs.enumerated().map { index, endpoint in
                [kAudioSubDeviceUIDKey: endpoint.device.id, kAudioSubDeviceDriftCompensationKey: index == 0 ? 0 : 1] as [String: Any]
            },
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: tapUID]],
        ]
        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID) == noErr,
              aggregateID != kAudioObjectUnknown else { AudioHardwareDestroyProcessTap(tapID); return nil }
        // An output device can also expose a microphone. Never interpret those hardware
        // input channels as the process tap or accidentally play them through the speakers.
        guard let inputFormat = stereoInputFormat(aggregateID),
              let layout = outputLayout(aggregateID, selected: outputs, sampleRate: inputFormat.mSampleRate),
              let state = layout.ranges.withUnsafeBufferPointer({
                  OSEQCreateRouted(inputFormat.mSampleRate, 2, $0.baseAddress, UInt32($0.count), UInt32(layout.channelCount))
              }) else {
            AudioHardwareDestroyAggregateDevice(aggregateID); AudioHardwareDestroyProcessTap(tapID); return nil
        }
        OSEQSetGain(state, gain)
        EqualizerDSP.publish(settings, sampleRate: inputFormat.mSampleRate, to: state)
        var procID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) { _, input, _, output, _ in
            OSEQProcessAudioBuffers(state, input, output)
        }
        guard status == noErr, let procID else {
            retire(state); AudioHardwareDestroyAggregateDevice(aggregateID); AudioHardwareDestroyProcessTap(tapID); return nil
        }
        guard AudioDeviceStart(aggregateID, procID) == noErr else {
            retire(state); AudioDeviceDestroyIOProcID(aggregateID, procID)
            AudioHardwareDestroyAggregateDevice(aggregateID); AudioHardwareDestroyProcessTap(tapID); return nil
        }
        return AppTap(tapID: tapID, aggregateID: aggregateID, procID: procID, state: state,
                      processSignature: signature(of: processObjectIDs), outputSignature: outputSignature,
                      sampleRate: inputFormat.mSampleRate)
    }

    private nonisolated static func supported(_ format: AudioStreamBasicDescription) -> Bool {
        format.mFormatID == kAudioFormatLinearPCM && format.mFormatFlags & kAudioFormatFlagIsFloat != 0
        && format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0 && format.mBitsPerChannel == 32
        && format.mChannelsPerFrame == 2 && format.mSampleRate.isFinite && format.mSampleRate > 0
        && format.mBytesPerFrame == (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0 ? 4 : 8)
    }

    /// Accept only an unambiguous stereo tap input. Full-duplex devices whose hardware inputs
    /// are included in the aggregate fail setup and retain their original audio routing.
    private nonisolated static func stereoInputFormat(_ device: AudioObjectID) -> AudioStreamBasicDescription? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                 mScope: kAudioDevicePropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioBufferList>.size else { return nil }
        let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, storage) == noErr else { return nil }
        let list = storage.assumingMemoryBound(to: AudioBufferList.self)
        let count = Int(list.pointee.mNumberBuffers)
        guard count > 0, count <= 2,
              Int(size) >= MemoryLayout<AudioBufferList>.size + (count - 1) * MemoryLayout<AudioBuffer>.size else { return nil }
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        guard buffers.allSatisfy({ $0.mNumberChannels > 0 }),
              buffers.reduce(0, { $0 + $1.mNumberChannels }) == 2 else { return nil }
        address.mSelector = kAudioDevicePropertyStreamFormat
        var format = AudioStreamBasicDescription()
        size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &format) == noErr,
              supported(format) else { return nil }
        return format
    }

    /// Confirm the actual active-subdevice order and aggregate streams before freezing the C map.
    /// A list with the right total but unknown device ordering is not enough to safely fan out.
    private nonisolated static func outputLayout(_ aggregate: AudioObjectID,
                                                  selected: [SoundMixerService.OutputEndpoint],
                                                  sampleRate: Double) -> (ranges: [OSEQOutputRange], channelCount: Int)? {
        guard !selected.isEmpty, selected.count <= 16,
              let active = objectList(kAudioAggregateDevicePropertyActiveSubDeviceList, of: aggregate,
                                      scope: kAudioObjectPropertyScopeGlobal), active.count == selected.count else { return nil }
        var ranges: [OSEQOutputRange] = []
        var total = 0
        var seen = Set<String>()
        for id in active {
            guard let uid = stringProperty(kAudioDevicePropertyDeviceUID, of: id),
                  let endpoint = selected.first(where: { $0.objectID == id && $0.device.id == uid }),
                  seen.insert(uid).inserted, (1...64).contains(endpoint.device.channelCount) else { return nil }
            ranges.append(OSEQOutputRange(firstChannel: UInt32(total), channelCount: UInt32(endpoint.device.channelCount)))
            total += endpoint.device.channelCount
        }
        guard total > 0, total <= 1024 else { return nil }
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                 mScope: kAudioDevicePropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(aggregate, &address, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioBufferList>.size, size <= 65_536 else { return nil }
        let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        guard AudioObjectGetPropertyData(aggregate, &address, 0, nil, &size, storage) == noErr else { return nil }
        let list = storage.assumingMemoryBound(to: AudioBufferList.self)
        let count = Int(list.pointee.mNumberBuffers)
        guard count > 0, count <= 1024,
              Int(size) >= MemoryLayout<AudioBufferList>.size + (count - 1) * MemoryLayout<AudioBuffer>.size else { return nil }
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        guard buffers.allSatisfy({ (1...64).contains($0.mNumberChannels) }),
              buffers.reduce(0, { $0 + Int($1.mNumberChannels) }) == total,
              let streams = objectList(kAudioDevicePropertyStreams, of: aggregate, scope: kAudioDevicePropertyScopeOutput),
              !streams.isEmpty else { return nil }
        var streamChannels = 0
        for stream in streams {
            address = AudioObjectPropertyAddress(mSelector: kAudioStreamPropertyVirtualFormat,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
            var format = AudioStreamBasicDescription()
            size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            guard AudioObjectGetPropertyData(stream, &address, 0, nil, &size, &format) == noErr,
                  format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                  format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0, format.mBitsPerChannel == 32,
                  (1...64).contains(format.mChannelsPerFrame), format.mSampleRate == sampleRate,
                  format.mBytesPerFrame == (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
                    ? 4 : 4 * format.mChannelsPerFrame) else { return nil }
            streamChannels += Int(format.mChannelsPerFrame)
        }
        guard streamChannels == total else { return nil }
        return (ranges, total)
    }

    private nonisolated static func objectList(_ selector: AudioObjectPropertySelector, of object: AudioObjectID,
                                               scope: AudioObjectPropertyScope) -> [AudioObjectID]? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr,
              size > 0, size <= 65_536 else { return nil }
        var result = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard !result.isEmpty, AudioObjectGetPropertyData(object, &address, 0, nil, &size, &result) == noErr else { return nil }
        return result
    }

    private nonisolated static func sampleRate(of device: AudioObjectID) -> Double? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var rate: Double = 0
        var size = UInt32(MemoryLayout<Double>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &rate) == noErr, rate.isFinite, rate > 0 else { return nil }
        return rate
    }

    private nonisolated static func teardown(_ tap: AppTap) {
        retire(tap.state)
        AudioDeviceStop(tap.aggregateID, tap.procID)
        AudioDeviceDestroyIOProcID(tap.aggregateID, tap.procID)
        AudioHardwareDestroyAggregateDevice(tap.aggregateID)
        AudioHardwareDestroyProcessTap(tap.tapID)
    }
    private nonisolated static func retire(_ state: OpaquePointer) {
        OSEQRetire(state)
        retiredStatesLock.lock(); retiredStates.append(state); retiredStatesLock.unlock()
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
