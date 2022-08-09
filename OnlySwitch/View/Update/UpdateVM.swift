//
//  UpdateVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/8/9.
//

import AppKit

class UpdateVM:ObservableObject {
    private let checkUpdatePresenter: GitHubPresenter!
    
    init(presenter:GitHubPresenter) {
        self.checkUpdatePresenter = presenter
    }
    
    var latestVersion:String {
        return checkUpdatePresenter.latestVersion
    }
    
    func downloadDMG() {
        checkUpdatePresenter.downloadDMG{ result in
            switch result {
            case let .success(path):
                self.openDMG(path: path)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    NSApp.terminate(self)
                }
            case let .failure(error):
                print(error.localizedDescription)
            }
        }
    }
    
    private func openDMG(path:String) {
        let finder = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder")
        let configuration: NSWorkspace.OpenConfiguration = NSWorkspace.OpenConfiguration()
        configuration.promptsUserIfNeeded = true
        NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: finder!, configuration: configuration, completionHandler: nil)
    }
}
