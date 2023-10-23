//
//  Updater.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/10/12.
//

import Sparkle
import AppKit

class Updater: ObservableObject {

    private let updaterController: SPUStandardUpdaterController

    private static let shared = Updater()

    init() {
        updaterController = SPUStandardUpdaterController(startingUpdater: true,
                                                         updaterDelegate: .none,
                                                         userDriverDelegate: .none)
    }

    static func checkForUpdates() {
        shared.updaterController.checkForUpdates(.none)
    }

}
