//
//  HideWindowsSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/12/20.
//

import Foundation
import AppKit
import Switches
import Defines

class HideWindowsSwitch:SwitchProvider {
    var type: SwitchType = .hideWindows
    
    var delegate: SwitchDelegate?
    
    func currentStatus() -> Bool {
        return Preferences.shared.windowsHidden
    }
    
    func currentInfo() -> String {
        return ""
    }
    
    @MainActor
    func operateSwitch(isOn: Bool) async throws {
        if isOn {
            try saveSessionGlobal()
        } else {
            try restoreSessionGlobal()
        }
    }
    
    func isVisible() -> Bool {
        return true
    }
    
    private func saveSessionGlobal() throws {
        guard !Preferences.shared.windowsHidden else {return}
        var apps = [AppsSession]()
        NSApp.setActivationPolicy(.regular)
        var runningApps = NSWorkspace.shared.runningApplications
        if let frontmostApp = NSWorkspace.shared.frontmostApplication {
            runningApps.append(frontmostApp)
        }
    
        for runningApp in runningApps {
            let session = AppsSession(appName: runningApp.localizedName!,
                                      appUrl: runningApp.executableURL!.absoluteString)
            if runningApp.activationPolicy == .regular &&
                session.appName != "Only Switch" {
                runningApp.hide()
                apps.append(session)
            }
            
        }
        
        if let data = try? JSONEncoder().encode(apps) {
            Preferences.shared.hiddenWindowsInfo = data
            Preferences.shared.windowsHidden = true
        }
    
    }
    
    private func restoreSessionGlobal() throws {
        guard Preferences.shared.windowsHidden,
              let data = Preferences.shared.hiddenWindowsInfo else {return}
        
        if let apps = try? JSONDecoder().decode([AppsSession].self, from: data) {
            for appSession in apps {
                try activate(name: appSession.appName, url: appSession.appUrl)
            }
            Preferences.shared.windowsHidden = false
            Preferences.shared.hiddenWindowsInfo = nil
        }
        
    }
    
    private func activate(name: String, url:String) throws {
        guard let app = NSWorkspace.shared.runningApplications.filter ({
            return $0.localizedName == name
        }).first else {
            do {
                let task = Process()
                task.executableURL = URL.init(string:url)
                try task.run()
            } catch {
                throw SwitchError.RestoreWindowsFailed
            }
            return
        }

        app.unhide()
    }
}

struct AppsSession:Codable {
    let appName:String
    let appUrl:String
    
    enum CodingKeys:String, CodingKey {
        case appName
        case appUrl
    }
}

