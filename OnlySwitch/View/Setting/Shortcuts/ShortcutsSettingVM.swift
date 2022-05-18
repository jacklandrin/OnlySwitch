//
//  ShortcutsSettingVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/1/1.
//

import Foundation
import KeyboardShortcuts
import Alamofire

let shorcutsDicKey = "shorcutsDicKey"

class ShorcutsItem:ObservableObject {
    let error:(_ info:String) -> Void
    @Published var name:String
    @Published var toggle:Bool
    {
        didSet {
            let shortcutsDic = UserDefaults.standard.dictionary(forKey: shorcutsDicKey)
            guard let shortcutsDic = shortcutsDic else {
                return
            }
            if toggle {
                let showShortcutsCount = shortcutsDic.filter{$0.value as! Bool == true}.count
                if showShortcutsCount > 9 {
                    error("The maximum number of shortcuts is 10")
                    toggle = false
                    return
                }
            }
            
            var newShortcutsDic = shortcutsDic
            newShortcutsDic[name] = toggle
            UserDefaults.standard.set(newShortcutsDic, forKey: shorcutsDicKey)
            UserDefaults.standard.synchronize()
            NotificationCenter.default.post(name: changeSettingNotification, object: nil)
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
        _ = try? ShorcutsCMD.runShortcut(name: self.name).runAppleScript(isShellCMD: true)
    }
    
}

class ShortcutsSettingVM:ObservableObject {
    static let shared = ShortcutsSettingVM()
    @Published var shortcutsList : [ShorcutsItem] = [ShorcutsItem]()
    @Published var errorInfo = ""
    @Published var showErrorToast = false
    @Published var sharedShortcutsList:[SharedShortcutsItem] = [SharedShortcutsItem]()

    init() {
        loadShortcutsList()
    }
    
    func loadShortcutsList() {
        DispatchQueue.main.async {
            do {
                let result = try ShorcutsCMD.getList.runAppleScript(isShellCMD: true)
                
                let allshortcuts = result.split(separator: "\r")
                let shortcutsDic = UserDefaults.standard.dictionary(forKey: shorcutsDicKey)
                var newShortcutsDic:[String:Bool] = [String:Bool]()
                if let shortcutsDic = shortcutsDic {
                    self.shortcutsList = [ShorcutsItem]()
                    for name in allshortcuts {
                        if let toggle = shortcutsDic[String(name)] as? Bool {
                            self.addItem(name: String(name), toggle: toggle)
                            newShortcutsDic[String(name)] = toggle
                        } else {
                            self.addItem(name: String(name), toggle: false)
                            newShortcutsDic[String(name)] = false
                        }
                    }
                } else {
                    self.shortcutsList = allshortcuts.map{ ShorcutsItem(name: String($0), toggle: false, error: {[weak self] info in
                        guard let strongSelf = self else {return}
                        strongSelf.errorInfo = info
                        strongSelf.showErrorToast = true
                    }) }
                    for name in allshortcuts {
                        newShortcutsDic[String(name)] = false
                    }
                }
                
                UserDefaults.standard.set(newShortcutsDic, forKey: shorcutsDicKey)
                UserDefaults.standard.synchronize()
            } catch {
                
            }
        }
        
    }
    
    func addItem(name:String, toggle:Bool) {
        self.shortcutsList.append(ShorcutsItem(name: String(name), toggle: toggle, error: {[weak self] info in
            guard let strongSelf = self else {return}
            strongSelf.errorInfo = info
            strongSelf.showErrorToast = true
        }))
    }
    
    func getAllInstalledShortcutName() -> [String]? {
        do {
            let result = try ShorcutsCMD.getList.runAppleScript(isShellCMD: true)
            let allshortcuts = result.split(separator: "\r")
            return allshortcuts.map{String($0)}
        } catch {
            return nil
        }
        
    }
    
    
    
    func checkIfInstalled() {
        let installedShortcuts = getAllInstalledShortcutName()
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
    
    func loadData() {
        let request = AF.request("https://raw.githubusercontent.com/jacklandrin/OnlySwitch/main/OnlySwitch/ShortcutsMarket/ShortcutsMarket.json")
        request.responseDecodable(of:[ShortcutOnMarket].self) { response in
            guard let list = response.value else {
                self.loadDataFromLocal()
                return
            }
            self.sharedShortcutsList = list.map{SharedShortcutsItem(shortcutInfo: $0)}
            self.checkIfInstalled()
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
            self.sharedShortcutsList = allShortcutsOnMarket.map{SharedShortcutsItem(shortcutInfo: $0)}
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

struct ShortcutOnMarket:Codable, Identifiable {
    enum CodingKeys:CodingKey {
        case name
        case link
        case author
        case description
    }
    var id = UUID()
    var name:String
    var link:String
    var author:String
    var description: String
}
