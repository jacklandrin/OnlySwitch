//
//  LanguageManager.swift
//  QRAssistant
//
//  Created by jack on 2021/10/21.
//

import Foundation
import Defines
import Extensions

public class LanguageManager: ObservableObject {
    private let languageUserDefaults = UserDefaults(suiteName: "group.onlyswitch.shared")!
    public static let sharedManager = LanguageManager()
    public var systemLangPriority:Bool {
        get {
            languageUserDefaults.bool(forKey: UserDefaults.Key.systemLangPriority)
        }
        set {
            languageUserDefaults.set(newValue, forKey: UserDefaults.Key.systemLangPriority)
            languageUserDefaults.synchronize()
            print("systemLangPriority:\(newValue)")
        }
    }
    
    @Published public var currentLang:String
    {
        didSet {
            Bundle.setLanguage(lang: currentLang)
            NotificationCenter.default.post(name: .changeSettings, object: nil)
        }
    }
    
    public init() {
        let _systemLangPriority = languageUserDefaults.bool(forKey: UserDefaults.Key.systemLangPriority)
        currentLang = _systemLangPriority ? Bundle.systemLanguage() : Bundle.currentLanguage()
        NotificationCenter.default.addObserver(self, selector: #selector(didBecomeActiveNotification(_:)), name: .showPopover, object: nil)
    }
    
    @objc private func didBecomeActiveNotification(_ noti:Notification) {
        if systemLangPriority {
            currentLang = Bundle.systemLanguage()
        }
    }
    
    public func setSystemLangPriority() {
        currentLang = Bundle.systemLanguage()
        systemLangPriority = true
    }
    
    public func setCertainLang(_ lang:String) {
        currentLang = lang
        systemLangPriority = false
    }
}
