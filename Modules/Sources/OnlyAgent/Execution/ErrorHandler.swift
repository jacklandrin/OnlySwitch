//
//  ErrorHandler.swift
//  Modules
//
//  Created by Bo Liu on 18.11.25.
//

import Foundation

@available(macOS 26.0, *)
public enum RetryStrategy {
    case immediateRetry
    case fixAndRetry
    case skipAndContinue
    case stopExecution
}

@available(macOS 26.0, *)
public final class ErrorHandler {
    public static let shared = ErrorHandler()
    
    private init() {}
    
    public func handleStepError(
        step: ExecutionStep,
        error: Error,
        context: TaskContext
    ) async -> RetryStrategy {
        let errorMessage = error.localizedDescription.lowercased()
        
        // Analyze error type
        if isTransientError(errorMessage) {
            return .immediateRetry
        } else if isLogicError(errorMessage) {
            return .fixAndRetry
        } else if isNonCriticalError(errorMessage) {
            return .skipAndContinue
        } else {
            return .stopExecution
        }
    }
    
    private func isTransientError(_ error: String) -> Bool {
        let transientKeywords = ["timeout", "network", "temporarily", "busy", "locked"]
        return transientKeywords.contains { error.contains($0) }
    }
    
    private func isLogicError(_ error: String) -> Bool {
        let logicKeywords = ["syntax", "invalid", "not found", "doesn't exist", "permission", "denied"]
        return logicKeywords.contains { error.contains($0) }
    }
    
    private func isNonCriticalError(_ error: String) -> Bool {
        let nonCriticalKeywords = ["warning", "already", "exists", "duplicate"]
        return nonCriticalKeywords.contains { error.contains($0) }
    }
}

