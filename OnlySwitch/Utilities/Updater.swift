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

    @Published
    var findValidUpdate = false

    init() {
        updaterController = SPUStandardUpdaterController(startingUpdater: true,
                                                         updaterDelegate: .none,
                                                         userDriverDelegate: .none)
        checkForUpdateInformation()
    }


    private func checkForUpdateInformation() {
        updaterController.updater.checkForUpdateInformation()
        NotificationCenter.default
            .publisher(for: .SUUpdaterDidNotFindUpdate)
            .map { _ in false }
            .receive(on: DispatchQueue.main)
            .assign(to: &$findValidUpdate)
        NotificationCenter.default
            .publisher(for: .SUUpdaterDidFindValidUpdate)
            .map { _ in true }
            .receive(on: DispatchQueue.main)
            .assign(to: &$findValidUpdate)
    }


    static func checkForUpdates() {
        shared.updaterController.checkForUpdates(.none)
    }

}
