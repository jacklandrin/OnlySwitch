//
//  ShortcutsSettingVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/1/1.
//

import AppKit
import Foundation
import KeyboardShortcuts
import Alamofire
import Networking
import Switches

class ShortcutsItem: ObservableObject {
    let error:(_ info:String) -> Void
    @Published var name:String
    @Published var toggle:Bool
    {
        didSet {
            let shortcutsDic = Preferences.shared.shortcutsDic
            guard let shortcutsDic = shortcutsDic else {
                return
            }
            if toggle {
                let showShortcutsCount = shortcutsDic.filter{$0.value == true}.count
                if showShortcutsCount > 9 {
                    error("The maximum number of shortcuts is 10")
                    toggle = false
                    return
                }
            }
            
            var newShortcutsDic = shortcutsDic
            newShortcutsDic[name] = toggle
            Preferences.shared.shortcutsDic = newShortcutsDic
            NotificationCenter.default.post(name: .changeSettings, object: nil)
        }
    }
    
    @Published var keyboardShortcutName:KeyboardShortcuts.Name
    
    init(name:String, toggle:Bool, error: @escaping (_ info:String) -> Void) {
        self.name = name
        self.toggle = toggle
        self.error = error
        self.keyboardShortcutName = KeyboardShortcuts.Name(rawValue: name)!
    }
    
    func doShortcuts() {
        let shortcutName = self.name
        Task {
            _ = try? await ShorcutsCMD.runShortcut(name: shortcutName).runAppleScript(isShellCMD: true)
        }
    }
    
}

final class ShortcutsSettingVM:ObservableObject, @unchecked Sendable {
    static let shared = ShortcutsSettingVM()
    
    var shortcutsList:[ShortcutsItem] {
        get {
            return model.shortcutsList
        }
        set {
            model.shortcutsList = newValue
        }
    }
    
    var errorInfo:String {
        return model.errorInfo
    }
    
    var showErrorToast: Bool {
        get {
            return model.showErrorToast
        }
        set {
            model.showErrorToast = newValue
        }
    }
    
    var sharedShortcutsList:[SharedShortcutsItem] {
        return model.sharedShortcutsList
    }
    
    @Published private var model = ShortcutsSettingModel()
    private var presenter = GitHubPresenter()
    
    init() {
        shouldLoadShortcutsList()
    }
    
    func shouldLoadShortcutsList() {
        DispatchQueue.global().async {
            self.loadShortcutsList()
        }
    }
    
    private func loadShortcutsList() {
        Task { @MainActor in
            var result: String = ""
            do {
                result = try await ShorcutsCMD.getList.runAppleScript(isShellCMD: true)
            } catch {

            }
            let allshortcuts = result.split(separator: "\r")
            let shortcutsDic = Preferences.shared.shortcutsDic
            var newShortcutsDic:[String:Bool] = [String:Bool]()
            if let shortcutsDic = shortcutsDic {
                self.model.shortcutsList = [ShortcutsItem]()
                for name in allshortcuts {
                    if let toggle = shortcutsDic[String(name)] {
                        self.addItem(name: String(name), toggle: toggle)
                        newShortcutsDic[String(name)] = toggle
                    } else {
                        self.addItem(name: String(name), toggle: false)
                        newShortcutsDic[String(name)] = false
                    }
                }
            } else {
                self.model.shortcutsList = allshortcuts.map{ ShortcutsItem(name: String($0), toggle: false, error: {[weak self] info in
                    guard let strongSelf = self else {return}
                    strongSelf.model.errorInfo = info
                    strongSelf.model.showErrorToast = true
                }) }
                for name in allshortcuts {
                    newShortcutsDic[String(name)] = false
                }
            }

            Preferences.shared.shortcutsDic = newShortcutsDic
            refreshShortcutAppearances(for: newShortcutsDic.compactMap { $0.value ? $0.key : nil })
        }
    }

    private func refreshShortcutAppearances(for names: [String]) {
        guard !names.isEmpty else {
            ShortcutAppearanceCache.replace([])
            return
        }

        // Apple Events launch their target application by default. Keep the
        // cached artwork when Shortcuts is closed so opening OnlySwitch never
        // opens the Shortcuts app as a side effect.
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.shortcuts").isEmpty == false else {
            return
        }

        let appearances = names.compactMap { name -> ShortcutAppearance? in
                let escapedName = name
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                let source = "tell application id \"com.apple.shortcuts\" to get icon of shortcut \"\(escapedName)\""
                var error: NSDictionary?
                guard let script = NSAppleScript(source: source) else { return nil }
                let descriptor = script.executeAndReturnError(&error)
                let tiffData = descriptor.data
                guard
                      let image = NSImage(data: tiffData),
                      let resized = image.resizeMaintainingAspectRatio(withSize: NSSize(width: 64, height: 64)),
                      let pngData = resized.pngData,
                      pngData.count <= 64 * 1024
                else {
                    if let error { print("Unable to read Shortcuts icon for \(name): \(error)") }
                    return nil
                }
                return ShortcutAppearance(id: name, name: name, iconPNGData: pngData)
            }
        ShortcutAppearanceCache.replace(appearances)
        NotificationCenter.default.post(name: .changeSettings, object: nil)
    }

    func addItem(name: String, toggle: Bool) {
        self.model.shortcutsList.append(ShortcutsItem(name: String(name), toggle: toggle, error: {[weak self] info in
            guard let strongSelf = self else {return}
            strongSelf.model.errorInfo = info
            strongSelf.model.showErrorToast = true
        }))
    }
    
    func getAllInstalledShortcutName() async -> [String]? {
        do {
            let result = try await ShorcutsCMD.getList.runAppleScript(isShellCMD: true)
            let allshortcuts = result.split(separator: "\r")
            return allshortcuts.map{String($0)}
        } catch {
            return nil
        }
        
    }
    
    func checkIfInstalled() {
        Task { @MainActor in
            let installedShortcuts = await getAllInstalledShortcutName()
            guard let installedShortcuts = installedShortcuts else {
                return
            }

            for item in sharedShortcutsList {
                if installedShortcuts.contains(item.name) {
                    item.hasInstalled = true
                }
            }
            objectWillChange.send()
        }
    }
    
    /// load json data from github
    func loadData() {
        //for test
        //        self.loadDataFromLocal()
        self.presenter.requestShortcutsJson(type: [ShortcutOnMarket].self) { result in
            switch result {
            case let .success(list):
                self.model.sharedShortcutsList = list.map{SharedShortcutsItem(shortcutInfo: $0)}
                self.checkIfInstalled()
            case .failure(_):
                DispatchQueue.main.async {
                    self.loadDataFromLocal()
                }
            }
        }
    }
    
    
    func loadDataFromLocal() {
        guard let url = Bundle.main.url(forResource: "ShortcutsMarket", withExtension: "json") else {
            print("json file not found")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let allShortcutsOnMarket = try JSONDecoder().decode([ShortcutOnMarket].self, from: data)
            self.model.sharedShortcutsList = allShortcutsOnMarket.map{SharedShortcutsItem(shortcutInfo: $0)}
            self.checkIfInstalled()
        } catch {
            print("json convert failed")
        }
    }
}

class SharedShortcutsItem:ObservableObject {
    @Published private var shortcutInfo:ShortcutOnMarket
    @Published var hasInstalled = false
    
    var name:String {
        return shortcutInfo.name
    }
    
    var link:String {
        return shortcutInfo.link
    }
    
    var author:String {
        return shortcutInfo.author
    }
    
    var description:String {
        return shortcutInfo.description
    }
    
    init(shortcutInfo:ShortcutOnMarket) {
        self.shortcutInfo = shortcutInfo
    }
}
