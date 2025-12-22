//
//  StateObserver.swift
//  Modules
//
//  Created by Bo Liu on 18.11.25.
//

import Foundation
import AppKit

@available(macOS 26.0, *)
public final class StateObserver {
    public static let shared = StateObserver()
    
    private init() {}
    
    public func captureSystemState() async -> SystemState {
        let runningApps = await getRunningApplications()
        let activeWindows = await getActiveWindows()
        let fileChanges: [String] = [] // Can be enhanced with file system monitoring
        let systemSettings: [String: String] = [:] // Can be enhanced with settings monitoring
        
        return SystemState(
            runningApplications: runningApps,
            activeWindows: activeWindows,
            recentFileChanges: fileChanges,
            systemSettings: systemSettings,
            timestamp: Date()
        )
    }
    
    public func compareStates(before: SystemState, after: SystemState) -> StateDiff {
        let newApps = Set(after.runningApplications).subtracting(before.runningApplications)
        let closedApps = Set(before.runningApplications).subtracting(after.runningApplications)
        let newWindows = Set(after.activeWindows).subtracting(before.activeWindows)
        let closedWindows = Set(before.activeWindows).subtracting(after.activeWindows)
        let fileChanges = Set(after.recentFileChanges).subtracting(before.recentFileChanges)
        
        var settingChanges: [String: String] = [:]
        for (key, value) in after.systemSettings {
            if before.systemSettings[key] != value {
                settingChanges[key] = value
            }
        }
        
        return StateDiff(
            newApplications: Array(newApps),
            closedApplications: Array(closedApps),
            newWindows: Array(newWindows),
            closedWindows: Array(closedWindows),
            fileChanges: Array(fileChanges),
            settingChanges: settingChanges
        )
    }
    
    private func getRunningApplications() async -> [String] {
        return await MainActor.run {
            let workspace = NSWorkspace.shared
            return workspace.runningApplications.compactMap { app in
                app.localizedName
            }
        }
    }
    
    private func getActiveWindows() async -> [String] {
        return await MainActor.run {
            var windowNames: [String] = []
            let workspace = NSWorkspace.shared
            for app in workspace.runningApplications {
                if let name = app.localizedName {
                    windowNames.append(name)
                }
            }
            return windowNames
        }
    }
}

