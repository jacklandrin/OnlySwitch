import Foundation
import Testing
@testable import DisplayBrightness

struct BrightnessPercentInputTests {
    private let english = Locale(identifier: "en_US")

    @Test(arguments: [("50", 0.5), (" 75 ", 0.75), ("40%", 0.4), ("40 %", 0.4), ("12.5", 0.125), ("0", 0.0), ("100", 1.0)])
    func parsesWholeAndFractionalPercents(text: String, level: Double) {
        #expect(BrightnessPercentInput.level(from: text, locale: english) == level)
    }

    @Test(arguments: [("150", 1.0), ("-20", 0.0), ("1000", 1.0)])
    func clampsOutOfRangeValues(text: String, level: Double) {
        #expect(BrightnessPercentInput.level(from: text, locale: english) == level)
    }

    @Test(arguments: ["", "   ", "%", "abc", "5o", "nan", "inf", "1e9", "1,2,3", "1.2.3", "--5"])
    func rejectsInputThatIsNotANumber(text: String) {
        #expect(BrightnessPercentInput.level(from: text, locale: english) == nil)
    }

    @Test func acceptsTheLocaleDecimalSeparator() {
        #expect(BrightnessPercentInput.level(from: "12,5", locale: Locale(identifier: "de_DE")) == 0.125)
    }

    @Test func formatsLevelsAsWholePercents() {
        #expect(BrightnessPercentInput.text(for: 0.456) == "46")
        #expect(BrightnessPercentInput.text(for: 1) == "100")
    }
}
