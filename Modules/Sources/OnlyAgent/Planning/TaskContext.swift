//
//  TaskContext.swift
//  Modules
//
//  Created by Bo Liu on 18.11.25.
//

import Foundation

@available(macOS 26.0, *)
public struct TaskContext: Codable, Equatable {
    public let originalPrompt: String
    public let goal: String
    public let constraints: [String]
    public let systemCapabilities: [String]
    public var executionHistory: [StepResult]
    public var currentSystemState: SystemState?
    public var userPreferences: [String: String]?
    
    public init(
        originalPrompt: String,
        goal: String,
        constraints: [String] = [],
        systemCapabilities: [String] = [],
        executionHistory: [StepResult] = [],
        currentSystemState: SystemState? = nil,
        userPreferences: [String: String]? = nil
    ) {
        self.originalPrompt = originalPrompt
        self.goal = goal
        self.constraints = constraints
        self.systemCapabilities = systemCapabilities
        self.executionHistory = executionHistory
        self.currentSystemState = currentSystemState
        self.userPreferences = userPreferences
    }
}

@available(macOS 26.0, *)
public struct SystemState: Codable, Equatable {
    public let runningApplications: [String]
    public let activeWindows: [String]
    public let recentFileChanges: [String]
    public let systemSettings: [String: String]
    public let timestamp: Date
    
    public init(
        runningApplications: [String] = [],
        activeWindows: [String] = [],
        recentFileChanges: [String] = [],
        systemSettings: [String: String] = [:],
        timestamp: Date = Date()
    ) {
        self.runningApplications = runningApplications
        self.activeWindows = activeWindows
        self.recentFileChanges = recentFileChanges
        self.systemSettings = systemSettings
        self.timestamp = timestamp
    }
}

@available(macOS 26.0, *)
public struct StateDiff: Equatable {
    public let newApplications: [String]
    public let closedApplications: [String]
    public let newWindows: [String]
    public let closedWindows: [String]
    public let fileChanges: [String]
    public let settingChanges: [String: String]
    
    public init(
        newApplications: [String] = [],
        closedApplications: [String] = [],
        newWindows: [String] = [],
        closedWindows: [String] = [],
        fileChanges: [String] = [],
        settingChanges: [String: String] = [:]
    ) {
        self.newApplications = newApplications
        self.closedApplications = closedApplications
        self.newWindows = newWindows
        self.closedWindows = closedWindows
        self.fileChanges = fileChanges
        self.settingChanges = settingChanges
    }
}

