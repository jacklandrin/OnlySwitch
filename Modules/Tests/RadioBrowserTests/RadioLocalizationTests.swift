#if os(macOS)
import Foundation
import Testing
import RadioBrowser

struct RadioLocalizationTests {
    @Test func allVisibleStringsHaveTranslationsInEverySupportedLanguage() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: repository.appendingPathComponent("Localization/Localizable.xcstrings"))
        let catalog = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(catalog["strings"] as? [String: [String: Any]])
        let languages = ["cs", "de", "en", "es", "fil", "fr", "hr", "it", "ja", "ko", "nl", "pl", "pt-BR", "ru", "sk", "so", "tr", "uk", "zh-Hans", "zh-Hant"]
        #expect(Set(RadioStrings.keys).count == RadioStrings.keys.count)
        for key in RadioStrings.keys {
            let entry = try #require(strings[key], "Missing radio string: \(key)")
            let localizations = try #require(entry["localizations"] as? [String: [String: Any]])
            for language in languages {
                let localization = try #require(localizations[language], "Missing \(language) translation: \(key)")
                let unit = try #require(localization["stringUnit"] as? [String: String])
                #expect(unit["state"] == "translated", "Untranslated \(language) string: \(key)")
                let value = try #require(unit["value"])
                #expect(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                for specifier in ["%@", "%lld"] where key.contains(specifier) {
                    #expect(value.contains(specifier), "\(language) translation of \(key) drops \(specifier)")
                }
            }
        }
    }
}
#endif
