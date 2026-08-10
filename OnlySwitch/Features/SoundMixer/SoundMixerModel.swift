//
//  SoundMixerModel.swift
//  OnlySwitch
//
//  Created by OnlySwitch on 2026/07/13.
//

import Foundation

/// An application whose audio output can be managed through AppleScript's standard
/// `sound volume` property (an integer in the range `0...100`).
///
/// macOS provides no public API to control the volume of an arbitrary application, so
/// the mixer is limited to apps that expose this scripting property. Add new entries to
/// ``known`` to support additional apps.
struct ScriptableAudioApp: Identifiable, Hashable {
    /// The app's bundle identifier, used to detect whether it is currently running.
    let bundleID: String
    /// The name used inside `tell application "…"`.
    let appleScriptName: String
    /// The name shown to the user.
    let displayName: String

    var id: String { bundleID }

    /// Registry of well-known apps that expose the standard `sound volume` (0...100) property.
    static let known: [ScriptableAudioApp] = [
        .init(bundleID: "com.apple.Music",    appleScriptName: "Music",   displayName: "Music"),
        .init(bundleID: "com.spotify.client", appleScriptName: "Spotify", displayName: "Spotify"),
        .init(bundleID: "com.apple.TV",       appleScriptName: "TV",      displayName: "TV"),
        .init(bundleID: "com.apple.iTunes",   appleScriptName: "iTunes",  displayName: "iTunes"),
    ]

    static func known(forBundleID id: String) -> ScriptableAudioApp? {
        known.first { $0.bundleID == id }
    }

    /// AppleScript that reads the current volume. Only run this for a *running* app,
    /// otherwise `tell application` would launch it.
    var getVolumeCommand: String {
        "tell application \"\(appleScriptName)\" to get sound volume"
    }

    /// AppleScript that sets the volume to `value` (expected to already be clamped to `0...100`).
    func setVolumeCommand(_ value: Int) -> String {
        "tell application \"\(appleScriptName)\" to set sound volume to \(value)"
    }
}
