//
//  Logger++.swift
//  Modules
//
//  Created by Jacklandrin on 27.04.25.
//

import OSLog

public extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "jacklandrin.OnlySwitch"

    static let internalSwitch = Logger(subsystem: subsystem, category: "Internal Switch")
    static let app = Logger(subsystem: subsystem, category: "App")
    static let statusBar = Logger(subsystem: subsystem, category: "StatusBar")
    static let ui = Logger(subsystem: subsystem, category: "UI")
    static let audio = Logger(subsystem: subsystem, category: "Audio")
    static let player = Logger(subsystem: subsystem, category: "Player")
    static let shell = Logger(subsystem: subsystem, category: "Shell")
    static let persistence = Logger(subsystem: subsystem, category: "Persistence")
    static let settings = Logger(subsystem: subsystem, category: "Settings")
    static let bluetooth = Logger(subsystem: subsystem, category: "Bluetooth")
    static let browser = Logger(subsystem: subsystem, category: "Browser")
}
