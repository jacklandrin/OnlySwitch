//
//  Logger++.swift
//  Modules
//
//  Created by Jacklandrin on 27.04.25.
//

import OSLog

public extension Logger {
    static let internalSwitch = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "Internal Switch")
}
