//
//  Task++.swift
//  Modules
//
//  Created by Jacklandrin on 2025/2/9.
//

import Foundation

public extension Task where Success == Never, Failure == Never {
    static func sleep(second: TimeInterval) async throws {
        try await Self.sleep(nanoseconds: UInt64(second * 1_000_000_000))
    }
}
