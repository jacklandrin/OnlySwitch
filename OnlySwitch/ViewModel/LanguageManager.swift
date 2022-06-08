//
//  LanguageManager.swift
//  QRAssistant
//
//  Created by jack on 2021/10/21.
//

import Foundation

class LanguageManager:ObservableObject {
    var systemLangPriority:Bool {
        get {
            UserDefaults.standard.bool(forKey: UserDefaults.Key.systemLangPriority)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaults.Key.systemLangPriority)
            UserDefaults.standard.synchronize()
            print("systemLangPriority:\(newValue)")
        }
    }
    
    @Published var currentLang:String
    {
        didSet {
            Bundle.setLanguage(lang: currentLang)
            NotificationCenter.default.post(name: .changeSettings, object: nil)
        }
    }
    
    init() {
        let _systemLangPriority = UserDefaults.standard.bool(forKey: UserDefaults.Key.systemLangPriority)
        currentLang = _systemLangPriority ? Bundle.systemLanguage() : Bundle.currentLanguage()
        NotificationCenter.default.addObserver(self, selector: #selector(didBecomeActiveNotification(_:)), name: .showPopover, object: nil)
    }
    
    @objc private func didBecomeActiveNotification(_ noti:Notification) {
        if systemLangPriority {
            self.currentLang = Bundle.systemLanguage()
        }
    }
    
    func setSystemLangPriority() {
        self.currentLang = Bundle.systemLanguage()
        systemLangPriority = true
    }
    
    func setCertainLang(_ lang:String) {
        self.currentLang = lang
        self.systemLangPriority = false
    }
    
    static let sharedManager = LanguageManager()
}
