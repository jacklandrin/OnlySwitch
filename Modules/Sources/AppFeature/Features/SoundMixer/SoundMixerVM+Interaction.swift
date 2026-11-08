//
//  SoundMixerVM+Interaction.swift
//  OnlySwitch
//

import AppKit
import ComposableArchitecture
import DisplayDDC

extension SoundMixerVM {
    // MARK: - Interaction


    /// The single way a slider changes a row. The view passes the value in rather than writing it
    /// through a `Binding` into ``rows``: a binding handed out by `ForEach` is written while
    /// SwiftUI still holds its own access to the array, and the resulting overlapping access
    /// corrupted the rows' storage.
    ///
    /// `live` is true while the slider is still under the pointer.
    func updateVolume(_ value: Double, for id: String, live: Bool) {
        isInteracting = live
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].volume = value
        if !live {
            rows[index].isMuted = value == 0
            if value > 0 { rows[index].volumeBeforeMute = value }
        }
        applyVolume(for: id, live: live)
    }

    /// `live` is true while the slider is still under the pointer. It keeps the tap path from
    /// rebuilding its Core Audio device on every movement.
    private func applyVolume(for id: String, live: Bool) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        switch rows[index].control {
        case .scriptable:
            guard let app = rows[index].scriptableApp else { return }
            let service = service
            scheduleWrite(Int(rows[index].volume), key: id) { await service.setVolume($0, of: app) }
        case .systemTap:
            // The tap's own callback applies the gain, so there is no round-trip to rate-limit.
            guard #available(macOS 14.4, *), let mixer = systemMixer, let pid = rows[index].pid else { return }
            mixer.setConfiguration(gain: rows[index].volume / 100,
                                   settings: equalizerStore.withState { $0.settings(for: id) }, pid: pid,
                                   processObjectIDs: rows[index].processObjectIDs, live: live,
                                   routing: outputRoutingStore.withState { $0.selection(for: id) })
        case .ownPlayer:
            ownPlayback.setVolume(rows[index].volume)
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
        case .systemTap, .ownPlayer:
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
        applyVolume(for: rows[index].id, live: false)
    }

    /// Same one-way flow as the per-app sliders.
    func updateSystemVolume(_ value: Double, live: Bool) {
        isInteracting = live
        guard isSystemVolumeAvailable else { return }
        systemVolume = value
        let service = service
        let control = systemVolumeControl
        scheduleWrite(Int(value.rounded()), key: Self.systemVolumeKey) { await service.setSystemVolume($0, via: control) }
    }

    /// Volume keys drive the display only while its volume is reached over DDC; otherwise the tap
    /// is stopped and macOS handles the keys itself.
    func updateVolumeKeyInterception() {
        let wantsKeys: Bool
        if enabled, case .display = systemVolumeControl { wantsKeys = true } else { wantsKeys = false }
        volumeKeyTap.interceptsVolumeKeys = wantsKeys
        guard wantsKeys else {
            if volumeKeyTap.isRunning { volumeKeyTap.stop() }
            needsAccessibilityForVolumeKeys = false
            return
        }
        if !volumeKeyTap.isRunning {
            let options = ["AXTrustedCheckOptionPrompt": !didPromptAccessibilityForVolumeKeys] as CFDictionary
            didPromptAccessibilityForVolumeKeys = true
            if AXIsProcessTrustedWithOptions(options) { _ = volumeKeyTap.start() }
        }
        needsAccessibilityForVolumeKeys = !volumeKeyTap.isRunning
    }

    func handleVolumeKey(_ key: VolumeKeyEvent.Key, fine: Bool) {
        guard enabled, isSystemVolumeAvailable, case let .display(name) = systemVolumeControl else { return }
        var level = DisplayVolumeLevel(volume: systemVolume, volumeBeforeMute: displayVolumeBeforeMute)
        level.apply(key, fine: fine)
        displayVolumeBeforeMute = level.volumeBeforeMute
        updateSystemVolume(level.volume, live: false)
        volumeHUD.show(volume: level.volume, isMuted: level.isMuted, onScreenNamed: name)
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }

    /// Opens the system Sound settings, so the panel can stand in for "Sound Settings…".
    func openSoundSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
