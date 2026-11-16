import Defines
import DisplayBrightness
import Extensions
import Foundation
import Testing
@testable import AppFeature

/// Display Brightness master switch. Serialized because it mutates `UserDefaults.standard`
/// (restored afterwards); every test that reads the master key from `.standard` lives here.
@MainActor
@Suite(.serialized)
struct DisplayBrightnessMasterSwitchTests {
    private let key = UserDefaults.Key.displayBrightnessEnabled
    private let saved = UserDefaults.standard.object(forKey: UserDefaults.Key.displayBrightnessEnabled)

    init() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private func restore() {
        if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
    }

    @Test func settingsToggleStartsOnAndReflectsStoredValue() {
        defer { restore() }
        #expect(DimScreenSettingVM().isDisplayBrightnessEnabled)
        UserDefaults.standard.set(false, forKey: key)
        #expect(!DimScreenSettingVM().isDisplayBrightnessEnabled)
    }

    @Test func settingsToggleWritesKeyAndPostsOneChangePerFlip() {
        defer { restore() }
        let posts = TestMutex(0)
        let observer = NotificationCenter.default.addObserver(
            forName: .displayBrightnessEnabledDidChange, object: nil, queue: nil
        ) { _ in posts.withLock { $0 += 1 } }
        defer { NotificationCenter.default.removeObserver(observer) }
        let viewModel = DimScreenSettingVM()

        viewModel.isDisplayBrightnessEnabled = false
        #expect(UserDefaults.standard.object(forKey: key) as? Bool == false)
        #expect(posts.withLock { $0 } == 1)
        viewModel.isDisplayBrightnessEnabled = false
        #expect(posts.withLock { $0 } == 1)
        viewModel.isDisplayBrightnessEnabled = true
        #expect(UserDefaults.isDisplayBrightnessEnabled())
        #expect(posts.withLock { $0 } == 2)
    }

    @Test func serviceScansNothingAndRejectsWritesWhenOff() async {
        defer { restore() }
        UserDefaults.standard.set(false, forKey: key)
        let snapshot = await DisplayBrightnessService.shared.scan()
        #expect(snapshot == BrightnessSnapshot())
        await #expect(throws: BrightnessError.self) {
            try await DisplayBrightnessService.shared.apply(
                .init(screenID: 1, generation: 0, level: 0.5, revision: 0))
        }
    }

    @Test func dimScreenIsHiddenWhenOff() {
        defer { restore() }
        let dimScreen = DimScreenSwitch()
        #expect(dimScreen.isVisible())
        UserDefaults.standard.set(false, forKey: key)
        #expect(!dimScreen.isVisible())
    }
}
