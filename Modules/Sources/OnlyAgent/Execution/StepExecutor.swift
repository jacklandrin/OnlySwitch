//
//  StepExecutor.swift
//  Modules
//
//  Created by Bo Liu on 18.11.25.
//

import Foundation
import Extensions

@available(macOS 26.0, *)
public final class StepExecutor {
    public static let shared = StepExecutor()
    private let stateObserver = StateObserver.shared
    
    private init() {}
    
    public func executeStep(_ step: ExecutionStep) async throws -> StepResult {
        let startTime = Date()
        var output: String? = nil
        var errorString: String? = nil
        var success = false
        
        do {
            output = try await step.appleScript.runAppleScript()
            success = true
        } catch {
            errorString = error.localizedDescription
            success = false
        }
        
        let executionTime = Date().timeIntervalSince(startTime)
        
        return StepResult(
            stepId: step.id,
            success: success,
            output: output,
            error: errorString,
            executionTime: executionTime
        )
    }
    
    public func observeSystemState(after step: ExecutionStep) async -> SystemState {
        return await stateObserver.captureSystemState()
    }
}

