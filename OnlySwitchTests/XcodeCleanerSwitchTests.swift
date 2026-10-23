import ComposableArchitecture
import Defines
import Extensions
import Foundation
import RemoteCore
import Switches
import Testing
@testable import OnlySwitch

@MainActor
struct XcodeCleanerSwitchTests {
    @Test func visibilityProviderReadsAndWritesBothStatesWithoutTouchingOtherSwitches() async throws {
        var shown = false
        let provider = XcodeCleanerSwitch(visibility: { shown }, setVisibility: { shown = $0 }, notifySettingsChanged: {})
        #expect(provider.type == .xcodeCleaner)
        #expect(await provider.currentInfo() == "")
        #expect(await provider.currentStatus() == false)
        try await provider.operateSwitch(isOn: true)
        #expect(shown)
        #expect(await provider.currentStatus())
        try await provider.operateSwitch(isOn: false)
        #expect(!shown)
        #expect(provider.isVisible())
    }

    @Test func changingVisibilityPostsSettingsRefresh() async throws {
        let notifications = TestMutex(0)
        let center = NotificationCenter()
        let observer = center.addObserver(forName: .changeSettings, object: nil, queue: nil) { _ in notifications.withLock { $0 += 1 } }
        defer { center.removeObserver(observer) }
        let provider = XcodeCleanerSwitch(visibility: { false }, setVisibility: { _ in }, notifySettingsChanged: {
            center.post(name: .changeSettings, object: nil)
        })
        try await provider.operateSwitch(isOn: true)
        #expect(notifications.withLock { $0 } >= 1)
    }

    @Test func missingPreferenceDefaultsToVisibleAndSettingUsesOneSharedKey() async throws {
        let suite = "XcodeCleanerVisibilityTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let provider = XcodeCleanerSwitch(
            visibility: { defaults.object(forKey: UserDefaults.Key.showXcodeCleanerTab) as? Bool ?? true },
            setVisibility: { defaults.set($0, forKey: UserDefaults.Key.showXcodeCleanerTab) },
            notifySettingsChanged: {}
        )
        #expect(await provider.currentStatus())
        try await provider.operateSwitch(isOn: false)
        #expect(defaults.object(forKey: "showXcodeCleanerTabKey") as? Bool == false)
        defaults.set(true, forKey: UserDefaults.Key.showXcodeCleanerTab)
        #expect(await provider.currentStatus())
    }

    @Test func stableIdentityMetadataAndBackupEligibilityRemainExplicit() {
        #expect(SwitchType.xcodeCleaner.legacyIdentifier == 70_368_744_177_664)
        #expect(SwitchType(legacyIdentifier: 70_368_744_177_664) == .xcodeCleaner)
        #expect(SwitchType.allCases.dropLast().last == .xcodeCleaner)
        #expect(Set(SwitchType.allCases.map(\.legacyIdentifier)).count == SwitchType.allCases.count)
        #expect(SwitchType.claudeUsage.legacyIdentifier == 35_184_372_088_832)
        #expect(SwitchType.xcodeCache.legacyIdentifier == 2_048)
        #expect(SwitchType.xcodeCleaner.barInfo().title == "Xcode Cleaner")
        #expect(SwitchType.xcodeCleaner.barInfo().controlType == .Switch)
        #expect(BuiltInSwitchCatalog.section(for: .xcodeCleaner) == .cleanupAndStorage)
        #expect(UserDefaults.Key.exportableKeys.contains(UserDefaults.Key.showXcodeCleanerTab))
        #expect(!UserDefaults.Key.exportableKeys.contains(UserDefaults.Key.didInstallXcodeCleanerSwitch))
    }

    @Test func sectionVisibilityAppendsCleanerAndPreservesExistingOrderAndIcon() {
        let hidden = SectionBar.sections(authenticator: false, soundMixer: false, systemMonitor: false, codexUsage: false, xcodeCleaner: false)
        let shown = SectionBar.sections(authenticator: true, soundMixer: true, systemMonitor: true, codexUsage: true, claudeUsage: true, aphrodite: true, xcodeCleaner: true)
        #expect(hidden == [.controls])
        #expect(shown == [.controls, .authenticator, .soundMixer, .systemMonitor, .codexUsage, .claudeUsage, .aphrodite, .xcodeCleaner])
        #expect(SectionBar.Section.xcodeCleaner.symbolName == "hammer.fill")
        #expect(SectionBar.Section.xcodeCleaner.assetName == nil)
        #expect(!SectionBar.Section.xcodeCleaner.title.isEmpty)
    }

    @Test func hidingSelectedCleanerReturnsOnlyControlToControls() async {
        let store = TestStore(initialState: OnlyControlReducer.State(selectedSection: .xcodeCleaner)) { OnlyControlReducer() }
        await store.send(.availableSectionsChanged([.controls])) { $0.selectedSection = .controls }
    }

    @Test func cleanerIsExcludedFromRemoteCatalogAndForgedStatusLookup() async throws {
        let provider = RemoteCatalogProvider(
            builtIns: { [.xcodeCleaner] },
            makeBuiltIn: { _ in XcodeCleanerSwitch(visibility: { true }, setVisibility: { _ in Issue.record("Remote catalog must not instantiate cleaner") }, notifySettingsChanged: {}) },
            shortcutNames: { [] }, evolutions: { [] }
        )
        #expect(try await provider.catalog().isEmpty)
        do {
            _ = try await provider.status(.init(kind: .builtIn, value: "70368744177664"), 1)
            Issue.record("A local cleaner must not expose remote status")
        } catch let error as RemoteProtocolError {
            #expect(error.code == .controlNotFound)
        }
    }

    @Test func forgedRemoteCleanerCommandCannotOperateLocalVisibility() async {
        var writes = 0
        let cleaner = XcodeCleanerSwitch(visibility: { true }, setVisibility: { _ in writes += 1 }, notifySettingsChanged: {})
        let router = RemoteCommandRouter(resolveBuiltIn: { _ in cleaner })
        let result = await router.perform(.init(requestID: UUID(), controlID: .init(kind: .builtIn, value: "70368744177664"), action: .setState(false)))
        guard case let .failure(error) = result.result else { Issue.record("Forged local-only command succeeded"); return }
        #expect(error.code == .controlNotFound)
        #expect(writes == 0)
    }
}
