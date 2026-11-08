//
//  Updater.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/10/12.
//

import Sparkle
import AppKit

final class Updater: ObservableObject, @unchecked Sendable {

    private let updaterController: SPUStandardUpdaterController

    private static let shared = Updater()

    init() {
        updaterController = SPUStandardUpdaterController(startingUpdater: true,
                                                         updaterDelegate: .none,
                                                         userDriverDelegate: .none)
    }

    static func checkForUpdates() {
        Task { @MainActor in
            shared.updaterController.checkForUpdates(.none)
        }
    }

}
