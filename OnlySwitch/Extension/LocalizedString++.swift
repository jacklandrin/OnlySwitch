//
//  LocalizedStringKey++.swift
//  QRAssistant
//
//  Created by jack on 2021/10/21.
//

import SwiftUI
extension Bundle {
    private static var bundle: Bundle!
    private static var supportLangs = ["en", "zh", "de", "hr", "tr","pl"]
    public static func localizedBundle() -> Bundle! {
        if bundle == nil {
            let appLang = UserDefaults.standard.string(forKey: "app_lang") ?? "en"
            let path = Bundle.main.path(forResource: appLang, ofType: "lproj")
            bundle = Bundle(path: path!)
        }

        return bundle;
    }

    public static func setLanguage(lang: String) {
        UserDefaults.standard.set(lang, forKey: "app_lang")
        let path = Bundle.main.path(forResource: lang, ofType: "lproj")
        bundle = Bundle(path: path!)
    }
    
    public static func currentLanguage() -> String {
        guard let lang = UserDefaults.standard.string(forKey: "app_lang") else {
            return systemLanguage()
        }
        return lang
    }
    
    public static func systemLanguage() -> String {
        guard let sysLang = Locale.current.languageCode else { return "en"}
        if supportLangs.contains(sysLang) {
            if sysLang == "zh" {
                return "zh-Hans"
            }
            return sysLang
        }
        return "en"
    }
}

extension String {
    func localized() -> String {
        return NSLocalizedString(self, tableName: nil, bundle: Bundle.localizedBundle(), value: "", comment: "")
    }

    func localizeWithFormat(arguments: CVarArg...) -> String{
        return String(format: self.localized(), arguments: arguments)
    }
}

func regulayExpression(regularExpress: String, validateString: String) -> [String] {
    do {
        let regex = try NSRegularExpression.init(pattern: regularExpress, options: [])
        let matches = regex.matches(in: validateString, options: [], range: NSRange(location: 0, length: validateString.count))
        var res: [String] = []
        for item in matches {
            let str = (validateString as NSString).substring(with: item.range)
            res.append(str)
        }
        return res
    } catch {
        return []
    }
}
func replace(validateStr: String, regularExpress: String, contentStr: String) -> String {
    do {
        let regrex = try NSRegularExpression.init(pattern: regularExpress, options: [])
        let modified = regrex.stringByReplacingMatches(in: validateStr, options: [], range: NSRange(location: 0, length: validateStr.count), withTemplate: contentStr)
        return modified
    } catch {
        return validateStr
    }
}
