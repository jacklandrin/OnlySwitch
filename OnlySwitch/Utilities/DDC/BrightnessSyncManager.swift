//
//  BrightnessSyncManager.swift
//  OnlySwitch
//
//  Compatibility entry point; DisplayBrightnessService owns discovery and synchronization.
//

import Foundation
import AppKit
import Combine
import Defines

struct BrightnessSyncState {
    private(set) var isRunning = false
    private(set) var topologyGeneration: UInt64 = 0
    private(set) var hasBuiltInDisplay = false
    private(set) var externalDisplayCount = 0

    var shouldPoll: Bool {
        isRunning && hasBuiltInDisplay && externalDisplayCount > 0
    }

    mutating func start() {
        isRunning = true
    }

    mutating func stop() {
        isRunning = false
        externalDisplayCount = 0
        topologyGeneration &+= 1
    }

    mutating func topologyChanged(hasBuiltInDisplay: Bool) -> UInt64 {
        self.hasBuiltInDisplay = hasBuiltInDisplay
        externalDisplayCount = 0
        topologyGeneration &+= 1
        return topologyGeneration
    }

    @discardableResult
    mutating func acceptRefresh(generation: UInt64, externalDisplayCount: Int) -> Bool {
        guard isRunning, generation == topologyGeneration else { return false }
        self.externalDisplayCount = externalDisplayCount
        return true
    }
}

/// Compatibility entry point for existing Preferences/AppDelegate notifications.
@MainActor
final class BrightnessSyncManager {
    static let shared = BrightnessSyncManager()
    private init() {}
    func updateState() {
        DisplayBrightnessService.shared.start()
        Task { @MainActor in
            await DisplayBrightnessService.shared.updateSettings(DisplayBrightnessSettingsPersistence.load())
        }
    }
}
