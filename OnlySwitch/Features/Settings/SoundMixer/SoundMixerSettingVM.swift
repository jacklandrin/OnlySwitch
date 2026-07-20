//
//  SoundMixerSettingVM.swift
//  OnlySwitch
//
//  Created by OnlySwitch on 2026/07/13.
//

import AppKit
import CoreAudio
import SwiftUI

@MainActor
final class SoundMixerSettingVM: ObservableObject {

    /// How a row's volume is applied. Both offer a slider; only the mechanism differs.
    enum Control {
        /// Via AppleScript's `sound volume` (scriptable media apps like Spotify).
        case scriptable
        /// Via a Core Audio process tap (any audio app, e.g. a browser).
        case systemTap
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

    @Published var rows: [AppRow] = []
    @Published var systemVolume: Double = 50
    /// The current default output device, shown in the panel's "Output" section.
    @Published var outputDevice: SoundMixerService.OutputDevice?

    private let service = SoundMixerService()
    /// Stored type-erased so the class stays available below macOS 14.4 (scriptable apps still work).
    private var systemMixerBox: AnyObject?
    // Only mutated on the main actor during init; read once in deinit after the last release.
    nonisolated(unsafe) private var workspaceObservers: [NSObjectProtocol] = []
    private var autoRefreshTask: Task<Void, Never>?
    /// While the user drags a slider we must not rebuild rows underneath them.
    private var isInteracting = false
    /// Latest value still to be written, keyed by row id (or ``systemVolumeKey``), plus the task
    /// draining it. A drag emits far more updates than an AppleScript round-trip can keep up with,
    /// so only the newest value survives and writes are rate-limited.
    private var pendingVolumes: [String: Int] = [:]
    private var volumeWriters: [String: Task<Void, Never>] = [:]
    private static let systemVolumeKey = "__system__"
    /// ~16 writes per second: fast enough to sound immediate, slow enough for AppleScript.
    private static let volumeWriteInterval: UInt64 = 60_000_000

    @available(macOS 14.4, *)
    private var systemMixer: SystemAudioMixer? { systemMixerBox as? SystemAudioMixer }

    init() {
        if #available(macOS 14.4, *) {
            systemMixerBox = SystemAudioMixer()
        }
        observeRunningApps()
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            center.removeObserver(observer)
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
    }

    // MARK: - Refresh

    func refresh() async {
        // Never fight an in-progress drag.
        guard !isInteracting else { return }

        if let sys = await service.systemVolume() {
            systemVolume = Double(sys)
        }

        outputDevice = service.currentOutputDevice()

        var newRows: [AppRow] = []

        // Scriptable media apps → full volume slider.
        let scriptable = service.runningControllableApps()
        let scriptableBundleIDs = Set(scriptable.map { $0.app.bundleID })
        for entry in scriptable {
            let volume = await service.volume(of: entry.app) ?? 0
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
            for audioApp in mixer.audioPlayingApps(excludingBundleIDs: scriptableBundleIDs) {
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

        rows = newRows
    }

    // MARK: - Interaction

    func beginInteractive() { isInteracting = true }
    func endInteractive() { isInteracting = false }

    /// Slider movement for a `.volume` row: apply right away, so the change is audible while
    /// dragging rather than only on release. Ignored unless a drag is in progress — otherwise a
    /// refresh replacing the rows would echo its own values back into the app.
    func applyVolumeWhileDragging(for id: String) {
        guard isInteracting else { return }
        applyVolume(for: id)
    }

    /// Slider release for a `.volume` row: pin the mute state and write the final value.
    func commitVolume(for id: String) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].isMuted = rows[index].volume == 0
        if rows[index].volume > 0 {
            rows[index].volumeBeforeMute = rows[index].volume
        }
        applyVolume(for: id)
    }

    private func applyVolume(for id: String) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        switch rows[index].control {
        case .scriptable:
            guard let app = rows[index].scriptableApp else { return }
            let service = service
            scheduleWrite(Int(rows[index].volume), key: id) { await service.setVolume($0, of: app) }
        case .systemTap:
            // The tap's own callback applies the gain, so there is no round-trip to rate-limit.
            guard #available(macOS 14.4, *), let mixer = systemMixer, let pid = rows[index].pid else { return }
            mixer.setVolume(rows[index].volume / 100, pid: pid, processObjectIDs: rows[index].processObjectIDs)
        }
    }

    /// Queues `value` and starts a writer for `key` if none is draining it yet.
    private func scheduleWrite(_ value: Int, key: String, write: @escaping (Int) async -> Void) {
        pendingVolumes[key] = value
        guard volumeWriters[key] == nil else { return }
        volumeWriters[key] = Task { [weak self] in
            while true {
                guard let self else { return }
                // No suspension between reading the entry and clearing the writer, so this stays
                // atomic against another `scheduleWrite` arriving on the main actor.
                guard let next = pendingVolumes.removeValue(forKey: key) else {
                    volumeWriters[key] = nil
                    return
                }
                await write(next)
                try? await Task.sleep(nanoseconds: Self.volumeWriteInterval)
            }
        }
    }

    func toggleMute(for id: String) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        switch rows[index].control {
        case .scriptable:
            toggleScriptableMute(at: index)
        case .systemTap:
            toggleSystemMute(at: index)
        }
    }

    private func toggleScriptableMute(at index: Int) {
        guard let app = rows[index].scriptableApp else { return }
        if rows[index].isMuted {
            let restore = rows[index].volumeBeforeMute > 0 ? rows[index].volumeBeforeMute : 50
            rows[index].volume = restore
            rows[index].isMuted = false
        } else {
            if rows[index].volume > 0 { rows[index].volumeBeforeMute = rows[index].volume }
            rows[index].volume = 0
            rows[index].isMuted = true
        }
        let value = Int(rows[index].volume)
        Task { await service.setVolume(value, of: app) }
    }

    private func toggleSystemMute(at index: Int) {
        if rows[index].isMuted {
            let restore = rows[index].volumeBeforeMute > 0 ? rows[index].volumeBeforeMute : 100
            rows[index].volume = restore
            rows[index].isMuted = false
        } else {
            if rows[index].volume > 0 { rows[index].volumeBeforeMute = rows[index].volume }
            rows[index].volume = 0
            rows[index].isMuted = true
        }
        applyVolume(for: rows[index].id)
    }

    /// Same live-while-dragging behaviour as the per-app sliders.
    func applySystemVolumeWhileDragging() {
        guard isInteracting else { return }
        commitSystemVolume()
    }

    func commitSystemVolume() {
        let service = service
        scheduleWrite(Int(systemVolume), key: Self.systemVolumeKey) { await service.setSystemVolume($0) }
    }

    // MARK: - Menu bar item

    /// Mirrors ``Preferences/soundMixerMenubarItem``; toggling it adds or removes the item.
    var menubarItemEnabled: Bool {
        get { Preferences.shared.soundMixerMenubarItem }
        set {
            objectWillChange.send()
            Preferences.shared.soundMixerMenubarItem = newValue
        }
    }

    /// Opens the system Sound settings, so the panel can stand in for "Sound Settings…".
    func openSoundSettings() {
        open("x-apple.systempreferences:com.apple.Sound-Settings.extension")
    }

    /// Where the system's own sound menu bar item is turned off, so this one can take its place.
    func openControlCenterSettings() {
        open("x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
