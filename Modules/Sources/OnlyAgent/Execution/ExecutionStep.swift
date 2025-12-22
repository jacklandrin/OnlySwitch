//
//  ExecutionStep.swift
//  Modules
//
//  Created by Bo Liu on 18.11.25.
//

import Foundation

@available(macOS 26.0, *)
public struct ExecutionStep: Identifiable, Equatable {
    public let id: UUID
    public let stepNumber: Int
    public let description: String
    public let appleScript: String
    public let expectedOutcome: String?
    public var status: StepStatus
    public var result: StepResult?
    
    public init(
        id: UUID = UUID(),
        stepNumber: Int,
        description: String,
        appleScript: String,
        expectedOutcome: String? = nil,
        status: StepStatus = .pending,
        result: StepResult? = nil
    ) {
        self.id = id
        self.stepNumber = stepNumber
        self.description = description
        self.appleScript = appleScript
        self.expectedOutcome = expectedOutcome
        self.status = status
        self.result = result
    }
}

@available(macOS 26.0, *)
public enum StepStatus: Equatable {
    case pending
    case executing
    case completed
    case failed
    case skipped
}

@available(macOS 26.0, *)
public struct StepResult: Codable, Equatable {
    public let stepId: UUID
    public let success: Bool
    public let output: String?
    public let error: String?
    public let executionTime: TimeInterval
    
    public init(
        stepId: UUID,
        success: Bool,
        output: String? = nil,
        error: String? = nil,
        executionTime: TimeInterval
    ) {
        self.stepId = stepId
        self.success = success
        self.output = output
        self.error = error
        self.executionTime = executionTime
    }
}

