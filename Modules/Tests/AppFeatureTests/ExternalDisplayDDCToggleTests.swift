import Defines
import Extensions
import Foundation
import Testing
@testable import AppFeature

/// Issue #232: the DDC toggle in Display settings writes the gate and announces each flip once.
/// Serialized because it mutates `UserDefaults.standard`; the stored value is restored afterwards.
@MainActor
@Suite(.serialized)
struct ExternalDisplayDDCToggleTests {
    private let key = UserDefaults.Key.externalDisplayDDCEnabled
    private let saved = UserDefaults.standard.object(forKey: UserDefaults.Key.externalDisplayDDCEnabled)

    init() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private func restore() {
        if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
    }

    @Test func settingsToggleReflectsStoredGateOnCreation() {
        defer { restore() }
        #expect(!DimScreenSettingVM().isExternalDisplayDDCEnabled)
        UserDefaults.standard.set(true, forKey: key)
        #expect(DimScreenSettingVM().isExternalDisplayDDCEnabled)
    }

    @Test func settingsToggleWritesGateAndPostsOneChangePerFlip() {
        defer { restore() }
        let posts = TestMutex(0)
        let observer = NotificationCenter.default.addObserver(
            forName: .externalDisplayDDCEnabledDidChange, object: nil, queue: nil
        ) { _ in posts.withLock { $0 += 1 } }
        defer { NotificationCenter.default.removeObserver(observer) }
        let viewModel = DimScreenSettingVM()

        viewModel.isExternalDisplayDDCEnabled = true
        #expect(UserDefaults.standard.object(forKey: key) as? Bool == true)
        #expect(UserDefaults.isExternalDisplayDDCEnabled())
        #expect(posts.withLock { $0 } == 1)

        viewModel.isExternalDisplayDDCEnabled = true
        #expect(posts.withLock { $0 } == 1)

        viewModel.isExternalDisplayDDCEnabled = false
        #expect(!UserDefaults.isExternalDisplayDDCEnabled())
        #expect(posts.withLock { $0 } == 2)
    }
}
