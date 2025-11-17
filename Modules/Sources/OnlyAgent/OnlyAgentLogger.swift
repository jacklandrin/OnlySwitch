//
//  OnlyAgentLogger.swift
//  Modules
//
//  Created by Bo Liu on 16.11.25.
//

import OSLog

extension Logger {
    private static var subsystem = Bundle.main.bundleIdentifier!
    static let onlyAgentDebug = Logger(subsystem: subsystem, category: "OnlyAgent")
}
