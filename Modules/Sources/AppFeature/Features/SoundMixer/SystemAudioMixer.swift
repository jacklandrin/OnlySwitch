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
    struct AppTap {
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
    nonisolated(unsafe) static var retiredStates: [OpaquePointer] = []
    nonisolated static let retiredStatesLock = NSLock()
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

    nonisolated static func signature(of ids: [AudioObjectID]) -> UInt64 {
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
}
