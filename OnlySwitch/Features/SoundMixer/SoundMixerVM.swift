//
//  SoundMixerVM.swift
//  OnlySwitch
//
//  Created by OnlySwitch on 2026/07/13.
//

import AppKit
import ComposableArchitecture
import SoundMixerEQ
import CoreAudio
import DisplayDDC
import Extensions
import RemoteCore
import SwiftUI

/// Shared on purpose: the process tap is a system-wide resource, and a second instance would set
/// up a competing aggregate device for the same apps.
@MainActor
final class SoundMixerVM: ObservableObject {

    static let shared = SoundMixerVM()

    /// How a row's volume is applied. Both offer a slider; only the mechanism differs.
    enum Control {
        /// Via AppleScript's `sound volume` (scriptable media apps like Spotify).
        case scriptable
        /// Via a Core Audio process tap (any audio app, e.g. a browser).
        case systemTap
        /// OnlySwitch's native volume, with isolated helper playback for EQ and routing.
        case ownPlayer
    }

    struct AppRow: Identifiable {
        let id: String
        var name: String
        var icon: NSImage?
        var control: Control
        var volume: Double            // 0...100, used by `.volume` rows
        var isMuted: Bool
        var volumeBeforeMute: Double

        // Backing handles for the two control paths.
        var scriptableApp: ScriptableAudioApp?
        var pid: pid_t?
        /// Every audio process of a `.muteOnly` app — browsers play through one helper per tab.
        var processObjectIDs: [AudioObjectID] = []
    }

    /// Whether the panel is shown in the switch list. Owned here rather than in `Preferences`, so
    /// the mixer is turned on and off like every other switch instead of through its own setting.
    @Published var enabled: Bool {
        didSet {
            lifecycleRevision += 1
            UserDefaults.standard.set(enabled, forKey: UserDefaults.Key.soundMixerEnabled)
            guard !enabled else {
                Task { await refresh() }
                return
            }
            updateVolumeKeyInterception()
            stopAutoRefresh()
            rows = []
            equalizerStore.send(.sourcesChanged([]))
            outputRoutingStore.send(.sourcesChanged([]))
            if #available(macOS 14.4, *) {
                systemMixer?.releasePlaybackHelper()
                systemMixer?.releaseAllTaps()
            }
        }
    }

    @Published var rows: [AppRow] = []
    @Published var systemVolume: Double = 50
    /// False when the output device's volume can be changed neither by macOS nor over DDC.
    @Published var isSystemVolumeAvailable = true
    var systemVolumeControl: SoundMixerService.SystemVolumeControl = .system
    /// DDC reads occasionally fail, e.g. while another app talks to the display at the same time.
    private var missedDisplayVolumeReads = 0
    /// True while volume keys should drive the display but Accessibility is not granted yet.
    @Published var needsAccessibilityForVolumeKeys = false
    lazy var volumeKeyTap = DisplayVolumeKeyTap { [weak self] key, fine in
        self?.handleVolumeKey(key, fine: fine)
    }
    lazy var volumeHUD = DisplayVolumeHUD()
    var displayVolumeBeforeMute: Double = 50
    var didPromptAccessibilityForVolumeKeys = false
    // Only mutated on the main actor during init; read once in deinit after the last release.
    nonisolated(unsafe) private var accessibilityObserver: NSObjectProtocol?
    /// The current default output device, shown in the panel's "Output" section.
    @Published var outputDevice: SoundMixerService.OutputDevice?

    /// A single retained store serves both menu-bar hosts. Effects resolve current handles here,
    /// never in SwiftUI or in persistent feature state.
    lazy var equalizerStore: StoreOf<EqualizerFeature> = {
        let store = Store(initialState: EqualizerFeature.State()) { EqualizerFeature() } withDependencies: {
            $0.equalizerClient.apply = { [weak self] id, settings in
                self?.applyEqualizer(settings, for: id) ?? .pending
            }
        }
        store.send(.load)
        return store
    }()

    lazy var outputRoutingStore: StoreOf<OutputRoutingFeature> = {
        let store = Store(initialState: OutputRoutingFeature.State()) { OutputRoutingFeature() } withDependencies: {
            $0.outputRoutingClient.apply = { [weak self] id, selection in
                self?.applyOutputRoute(selection, for: id) ?? .pending
            }
        }
        store.send(.load)
        store.send(.devicesChanged(service.outputEndpoints().map(\.device)))
        return store
    }()

    private var lifecycleRevision = 0
    let service = SoundMixerService()
    let ownPlayback = OwnPlaybackSource.live
    /// Stored type-erased so the class stays available below macOS 14.4 (scriptable apps still work).
    private var systemMixerBox: AnyObject?
    // Only mutated on the main actor during init; read once in deinit after the last release.
    nonisolated(unsafe) private var workspaceObservers: [NSObjectProtocol] = []
    nonisolated(unsafe) private var ownPlaybackObserver: NSObjectProtocol?
    private var autoRefreshTask: Task<Void, Never>?
    /// While the user drags a slider we must not rebuild rows underneath them.
    var isInteracting = false
    /// Guards ``refresh()`` against overlapping itself across its suspension points.
    private var isRefreshing = false
    /// Latest value still to be written, keyed by row id (or ``systemVolumeKey``), plus the task
    /// draining it. A drag emits far more updates than an AppleScript round-trip can keep up with,
    /// so only the newest value survives and writes are rate-limited.
    var pendingVolumes: [String: Int] = [:]
    var volumeWriters: [String: Task<Void, Never>] = [:]
    static let systemVolumeKey = "__system__"
    /// ~16 writes per second: fast enough to sound immediate, slow enough for AppleScript.
    static let volumeWriteInterval: UInt64 = 60_000_000

    @available(macOS 14.4, *)
    var systemMixer: SystemAudioMixer? { systemMixerBox as? SystemAudioMixer }

    private init() {
        enabled = UserDefaults.standard.bool(forKey: UserDefaults.Key.soundMixerEnabled)
        if #available(macOS 14.4, *) {
            let mixer = SystemAudioMixer()
            systemMixerBox = mixer
            mixer.onOutputDevicesChanged = { [weak self] in
                self?.refreshRoutingDevices()
                Task { [weak self] in await self?.refresh() }
            }
        }
        observeRunningApps()
        ownPlaybackObserver = NotificationCenter.default.addObserver(
            forName: .ownPlaybackStateChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refresh() }
        }
        // Granting Accessibility in System Settings must start the volume keys without a restart.
        accessibilityObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                // The trust state settles shortly after the notification.
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, self.needsAccessibilityForVolumeKeys else { return }
                self.updateVolumeKeyInterception()
            }
        }
        // Display volume keys must follow the output without the panel ever being opened.
        if enabled { Task { await refresh() } }
    }

    deinit {
        if let ownPlaybackObserver { NotificationCenter.default.removeObserver(ownPlaybackObserver) }
        let center = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            center.removeObserver(observer)
        }
        if let accessibilityObserver {
            DistributedNotificationCenter.default().removeObserver(accessibilityObserver)
        }
    }

    // MARK: - Auto detection

    /// Detects apps launching/quitting instantly; a light poll additionally catches apps that
    /// merely *start or stop playing audio* (which fires no workspace notification).
    private func observeRunningApps() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { await self?.refresh() }
            }
            workspaceObservers.append(token)
        }
    }

    func startAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task { [weak self] in
            // `guard let self` (not `self?`) so the loop ends once the view model is gone, instead
            // of spinning every 2s forever against a nil weak reference.
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
        // The panel can go away mid-drag; otherwise the flag would block every later refresh.
        isInteracting = false
    }

    // MARK: - Refresh

    func refresh() async {
        // The workspace observers fire whatever the user picked in Customize, and enumerating audio
        // processes is what triggers the audio-capture permission prompt. Nothing runs while off.
        guard enabled else { return }
        // Never fight an in-progress drag.
        guard !isInteracting else { return }
        // Not re-entrant. Every AppleScript round-trip below suspends, and a browser spawns and
        // kills a helper process per tab, so the workspace observers fire constantly — without this
        // several refreshes interleave at those suspension points and take turns enumerating and
        // tearing down the same taps.
        guard !isRefreshing else { return }
        isRefreshing = true
        let revision = lifecycleRevision
        defer { isRefreshing = false }

        // Skip the device read while a write is queued; a DDC read would return the old value.
        if volumeWriters[Self.systemVolumeKey] == nil {
            let sys = await service.systemVolume()
            guard enabled, revision == lifecycleRevision, !Task.isCancelled, !isInteracting else { return }
            if case .display = systemVolumeControl, sys.control == .unavailable, missedDisplayVolumeReads < 1 {
                missedDisplayVolumeReads += 1
            } else {
                missedDisplayVolumeReads = 0
                systemVolumeControl = sys.control
                isSystemVolumeAvailable = sys.control != .unavailable
                if let value = sys.value { systemVolume = Double(value) }
            }
            updateVolumeKeyInterception()
        }

        refreshRoutingDevices()
        if #available(macOS 14.4, *), let mixer = systemMixer {
            if ownPlayback.isPlaying(), let identity = ownPlayback.helperIdentity() {
                let source = ownPlayback
                mixer.configurePlaybackHelper(pid: identity.pid, generation: identity.generation,
                                               isAlive: { source.ownsHelper(identity) })
            } else {
                mixer.releasePlaybackHelper()
            }
        }

        var newRows: [AppRow] = []

        // Scriptable media apps → full volume slider.
        let scriptable = service.runningControllableApps()
        let scriptableBundleIDs = Set(scriptable.map { $0.app.bundleID })
        for entry in scriptable {
            let volume = await service.volume(of: entry.app) ?? 0
            guard enabled, revision == lifecycleRevision, !Task.isCancelled, !isInteracting else { return }
            let previous = rows.first { $0.id == entry.app.bundleID }
            let restore = volume > 0 ? Double(volume) : (previous?.volumeBeforeMute ?? 50)
            newRows.append(
                AppRow(id: entry.app.bundleID,
                       name: entry.app.displayName,
                       icon: entry.icon,
                       control: .scriptable,
                       volume: Double(volume),
                       isMuted: volume == 0,
                       volumeBeforeMute: restore,
                       scriptableApp: entry.app)
            )
        }

        // Any other app currently playing audio (e.g. a browser) → volume via a process tap.
        if #available(macOS 14.4, *), let mixer = systemMixer {
            let audioApps = mixer.audioPlayingApps(excludingBundleIDs: [])
            for index in newRows.indices {
                if let audio = audioApps.first(where: { $0.bundleID == newRows[index].id }) {
                    newRows[index].pid = audio.pid
                    newRows[index].processObjectIDs = audio.processObjectIDs
                }
            }
            for audioApp in audioApps where !scriptableBundleIDs.contains(audioApp.bundleID ?? "") {
                let id = audioApp.bundleID ?? "pid-\(audioApp.pid)"
                let previous = rows.first { $0.id == id }
                newRows.append(
                    AppRow(id: id,
                           name: audioApp.name,
                           icon: audioApp.icon,
                           control: .systemTap,
                           volume: audioApp.volume,
                           isMuted: audioApp.volume == 0,
                           volumeBeforeMute: previous?.volumeBeforeMute ?? 100,
                           pid: audioApp.pid,
                           processObjectIDs: audioApp.processObjectIDs)
                )
            }
        }

        if let own = Self.ownPlaybackRow(isPlaying: ownPlayback.isPlaying(), volume: ownPlayback.volume(),
                                         previous: rows.first { $0.id == OwnPlaybackSource.rowID },
                                         icon: NSApp.applicationIconImage) {
            newRows.append(own)
        } else if #available(macOS 14.4, *) {
            systemMixer?.releasePlaybackHelper()
        }

        // Only publish real changes. Reassigning every two seconds relaid out the whole popover
        // under the pointer, which churned SwiftUI's focus tracking for no gain.
        if Self.signature(of: newRows) != Self.signature(of: rows) { rows = newRows }
        let supported: Bool
        if #available(macOS 14.4, *) { supported = true } else { supported = false }
        let sources = rows.map {
            EqualizerFeature.Source(id: $0.id, isPersistent: !$0.id.hasPrefix("pid-"), isSupported: supported,
                                    isAvailable: $0.control == .ownPlayer || ($0.pid != nil && !$0.processObjectIDs.isEmpty))
        }
        outputRoutingStore.send(.sourcesChanged(sources))
        equalizerStore.send(.sourcesChanged(sources))
    }

    private func applyEqualizer(_ settings: EqualizerSettings, for id: String) -> EqualizerFeature.Status {
        guard enabled else { return .pending }
        guard #available(macOS 14.4, *), let mixer = systemMixer else { return .unsupported }
        if id == OwnPlaybackSource.rowID {
            guard rows.contains(where: { $0.id == id }) else { return .pending }
            guard let identity = ownPlayback.helperIdentity(), ownPlayback.ownsHelper(identity) else { return .pending }
            let processes = mixer.playbackHelperProcessObjectIDs()
            guard !processes.isEmpty else { return .pending }
            guard mixer.setConfiguration(gain: 1, settings: settings, pid: identity.pid,
                processObjectIDs: processes, live: false,
                routing: outputRoutingStore.withState { $0.selection(for: id) }) else { return .unavailable }
            if settings.isFlat { return .flat }
            return mixer.isReceivingAudio(pid: identity.pid) ? .active : .waitingForAudio
        }
        guard let row = rows.first(where: { $0.id == id }), let pid = row.pid,
              !row.processObjectIDs.isEmpty else { return .pending }
        // Native/scriptable volume is already applied upstream. Its EQ chain must use unity gain.
        let gain = row.control == .scriptable ? 1 : row.volume / 100
        guard mixer.setConfiguration(gain: gain, settings: settings, pid: pid,
                                     processObjectIDs: row.processObjectIDs, live: false,
                                     routing: outputRoutingStore.withState { $0.selection(for: id) }) else { return .unavailable }
        if settings.isFlat { return .flat }
        return mixer.isReceivingAudio(pid: pid) ? .active : .waitingForAudio
    }

    private func refreshRoutingDevices() {
        outputDevice = service.currentOutputDevice()
        let devices = service.outputEndpoints().map(\.device)
        if outputRoutingStore.withState({ $0.devices }) != devices {
            outputRoutingStore.send(.devicesChanged(devices))
        }
    }

    private func applyOutputRoute(_ selection: OutputRouteSelection, for id: String) -> OutputRoutingFeature.Status {
        guard enabled else { return .pending }
        guard #available(macOS 14.4, *), let mixer = systemMixer else { return .unsupported }
        if id == OwnPlaybackSource.rowID {
            guard rows.contains(where: { $0.id == id }) else { return .pending }
            let resolution = OutputRouteResolution(selection: selection, devices: service.outputEndpoints().map(\.device))
            guard let identity = ownPlayback.helperIdentity(), ownPlayback.ownsHelper(identity) else { return .pending }
            let processes = mixer.playbackHelperProcessObjectIDs()
            guard !processes.isEmpty else { return .pending }
            let applied = mixer.setConfiguration(gain: 1,
                settings: equalizerStore.withState { $0.settings(for: id) }, pid: identity.pid,
                processObjectIDs: processes, live: false, routing: selection)
            if resolution.isWaiting { return .waitingForDevices }
            guard applied else { return .unavailable }
            if selection.followsSystem { return .followingSystem }
            if !resolution.missingUIDs.isEmpty { return .partial }
            return mixer.isReceivingAudio(pid: identity.pid) ? .active : .pending
        }
        guard let row = rows.first(where: { $0.id == id }), let pid = row.pid,
              !row.processObjectIDs.isEmpty else { return .pending }
        let resolution = OutputRouteResolution(selection: selection, devices: service.outputEndpoints().map(\.device))
        let gain = row.control == .scriptable ? 1 : row.volume / 100
        let applied = mixer.setConfiguration(gain: gain, settings: equalizerStore.withState { $0.settings(for: id) },
                                             pid: pid, processObjectIDs: row.processObjectIDs, live: false,
                                             routing: selection)
        if resolution.isWaiting { return .waitingForDevices }
        guard applied else { return .unavailable }
        if selection.followsSystem { return .followingSystem }
        if !resolution.missingUIDs.isEmpty { return .partial }
        return mixer.isReceivingAudio(pid: pid) ? .active : .pending
    }

    /// Everything the panel actually draws. Icons and the backing handles are left out: they follow
    /// from the id, and `NSImage` is not comparable in any cheap way.
    private static func signature(of rows: [AppRow]) -> [String] {
        rows.map { "\($0.id)|\($0.name)|\(Int($0.volume))|\($0.isMuted)|\($0.pid ?? 0)|\($0.processObjectIDs)" }
    }
}
