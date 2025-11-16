//
//  SupportedLanguage.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/5/23.
//

import Foundation

struct Language:Hashable {
    let name:String
    let code:String
}

struct SupportedLanguages {
    static let english = Language(name: "English", code: "en")
    static let simplifiedChinese = Language(name: "简体中文", code: "zh-Hans")
    static let german = Language(name: "Deutsch", code: "de")
    static let croatian = Language(name: "Hrvatski", code: "hr")
    static let turkish = Language(name: "Türkçe", code: "tr")
    static let polish = Language(name: "Polski", code: "pl")
    static let filipino = Language(name: "Filipino", code: "fil")
    static let dutch = Language(name: "Nederlands", code: "nl")
    static let italian = Language(name: "Italiano", code: "it")
    static let russian = Language(name: "Русский", code: "ru")
    static let spanish = Language(name: "Español", code: "es")
    static let japanese = Language(name: "日本語", code: "ja")
    static let somali = Language(name: "Somali", code: "so")
    static let korean = Language(name: "한국어", code: "ko")
    static let french = Language(name: "Français", code: "fr")
    static let ukrainian = Language(name: "Українська", code: "uk")
    static let slovak = Language(name: "Slovenský", code: "sk")
    static let brazilianPortuguese = Language(name: "Português (Brasil)", code: "pt-BR")
    static let czech = Language(name: "Čeština", code: "cs")

    static let langList = [
        SupportedLanguages.english,
        SupportedLanguages.simplifiedChinese,
        SupportedLanguages.german,
        SupportedLanguages.croatian,
        SupportedLanguages.turkish,
        SupportedLanguages.polish,
        SupportedLanguages.filipino,
        SupportedLanguages.dutch,
        SupportedLanguages.italian,
        SupportedLanguages.russian,
        SupportedLanguages.spanish,
        SupportedLanguages.japanese,
        SupportedLanguages.somali,
        SupportedLanguages.korean,
        SupportedLanguages.french,
        SupportedLanguages.ukrainian,
        SupportedLanguages.slovak,
        SupportedLanguages.brazilianPortuguese,
        SupportedLanguages.czech
    ]

    static func getLangName(code: String) -> String {
        let lang = SupportedLanguages.langList.filter{$0.code == code}.first
        return lang?.name ?? "English"
    }
}
