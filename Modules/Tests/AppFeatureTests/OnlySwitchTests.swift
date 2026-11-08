//
//  OnlySwitchTests.swift
//  OnlySwitchTests
//
//  Created by Jacklandrin on 2022/5/18.
//

import AppKit
import SwiftUI
import XCTest
import Testing
import Combine
import DesktopPet
import Defines
import Switches
import Utilities
import Aphrodite
import UserNotifications
import ComposableArchitecture
@testable import AppFeature

class OnlySwitchTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results with assertions afterwards.
    }

    @MainActor
    func testDimScreenSliderPublishesRoundedValue() {
        let viewModel = DimScreenSettingVM()

        viewModel.sliderValue = 0.73

        XCTAssertEqual(viewModel.sliderValue, 0.7)
        XCTAssertEqual(Preferences.shared.dimScreenPercent, 0.7)
    }

    @MainActor
    func testAppearanceNotificationSeesNewValue() {
        let originalAppearance = Preferences.shared.currentAppearance
        let newAppearance = originalAppearance == SwitchListAppearance.single.rawValue
            ? SwitchListAppearance.dual.rawValue
            : SwitchListAppearance.single.rawValue
        var observedAppearance: String?
        let observer = NotificationCenter.default.addObserver(
            forName: .shouldHidePopover,
            object: nil,
            queue: .main
        ) { _ in
            observedAppearance = Preferences.shared.currentAppearance
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
            Preferences.shared.currentAppearance = originalAppearance
        }

        Preferences.shared.currentAppearance = newAppearance

        XCTAssertEqual(observedAppearance, newAppearance)
    }

    @MainActor
    func testGeneralVMPublishesAppearanceSelection() {
        let viewModel = GeneralVM()
        let originalAppearance = viewModel.currentAppearance
        let newAppearance = originalAppearance == SwitchListAppearance.single.rawValue
            ? SwitchListAppearance.dual.rawValue
            : SwitchListAppearance.single.rawValue
        var didPublishChange = false
        let cancellable = viewModel.objectWillChange.sink {
            didPublishChange = true
        }
        defer {
            viewModel.currentAppearance = originalAppearance
            cancellable.cancel()
        }

        viewModel.currentAppearance = newAppearance

        XCTAssertTrue(didPublishChange)
        XCTAssertEqual(viewModel.currentAppearance, newAppearance)
    }

    @MainActor
    func testDesktopPetIsHiddenByDefaultAndPublishesChanges() {
        let defaults = UserDefaults.standard
        let key = UserDefaults.Key.showDesktopPet
        let original = defaults.object(forKey: key)
        defer {
            if let original {
                defaults.set(original, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        defaults.removeObject(forKey: key)

        XCTAssertFalse(Preferences.shared.showDesktopPet)

        var observed: Bool?
        let observer = NotificationCenter.default.addObserver(
            forName: .desktopPetVisibilityChanged,
            object: nil,
            queue: .main
        ) { _ in
            observed = Preferences.shared.showDesktopPet
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        Preferences.shared.showDesktopPet = true

        XCTAssertEqual(observed, true)
    }

    func testPomodoroDesktopPetStateParsesFocusCountdown() {
        let state = PomodoroTimerSwitch.desktopPetState(from: "w-24:59")

        XCTAssertEqual(state, .init(phase: .focus, remainingTime: "24:59"))
    }

    func testPomodoroDesktopPetStateParsesBreakCountdown() {
        let state = PomodoroTimerSwitch.desktopPetState(from: "r-04:59")

        XCTAssertEqual(state, .init(phase: .breakTime, remainingTime: "04:59"))
    }

    func testPomodoroDesktopPetStateRejectsStoppedAndMalformedValues() {
        for value in ["", "n-25:00", "w-", "w-25", "w-25:99", "x-05:00", "w-05:00-extra"] {
            XCTAssertNil(PomodoroTimerSwitch.desktopPetState(from: value), value)
        }
    }

    @MainActor
    func testHiddenDesktopPetDoesNotRetainPomodoroPresentation() {
        let appDelegate = AppDelegate()
        let controller = TestDesktopPetPomodoroPresenter()
        let focus = DesktopPetPomodoroState(phase: .focus, remainingTime: "24:59")

        appDelegate.applyDesktopPetPomodoroState(focus, to: controller)

        XCTAssertNil(controller.pomodoroState)
    }

    @MainActor
    func testVisibleDesktopPetReceivesPomodoroPresentation() {
        let appDelegate = AppDelegate()
        let controller = TestDesktopPetPomodoroPresenter()
        controller.isVisible = true
        let breakState = DesktopPetPomodoroState(phase: .breakTime, remainingTime: "04:59")

        appDelegate.applyDesktopPetPomodoroState(breakState, to: controller)

        XCTAssertEqual(controller.pomodoroState, breakState)
    }

    
    
    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        measure {
            // Put the code you want to measure the time of here.
        }
    }

}

@MainActor
@Test func aphroditeBuiltInSwitchUpdatesTheSharedTabPreference() async throws {
    var isVisible = true
    let control = AphroditeSwitch(
        visibility: { isVisible },
        setVisibility: { isVisible = $0 }
    )

    #expect(control.type == .aphrodite)
    #expect(await control.currentStatus())
    try await control.operateSwitch(isOn: false)
    #expect(await control.currentStatus() == false)
}

@Test func bundledModelCatalogIncludesLatestVerifiedModelsAndRetainsLegacyChoices() throws {
    // Package tests run outside the app host, so read the app's bundled catalog from the source tree.
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "OnlySwitch/Resource/models.json")
    let catalog = try JSONDecoder().decode(TestModelCatalog.self, from: Data(contentsOf: url))

    #expect(catalog.items(provider: "openai", family: "gpt").contains("gpt-6.1-sol"))
    #expect(catalog.items(provider: "openai", family: "gpt").contains("gpt-5.6"))
    #expect(catalog.items(provider: "google", family: "gemini").contains("gemini-3.8-flash"))
    #expect(catalog.items(provider: "anthropic", family: "claude").contains("claude-opus-5-5"))
}

private struct TestModelCatalog: Decodable {
    struct Group: Decodable {
        let provider: String
        let family: String
        let items: [String]
    }

    let models: [Group]

    func items(provider: String, family: String) -> [String] {
        models.first { $0.provider == provider && $0.family == family }?.items ?? []
    }
}

@MainActor
@Test func desktopPetBuiltInSwitchMapsVisibilityWithoutAdditionalEffects() async throws {
    var isVisible = false
    var writes: [Bool] = []
    let control = DesktopPetSwitch(
        visibility: { isVisible },
        setVisibility: { value in
            writes.append(value)
            isVisible = value
        }
    )

    #expect(control.type == .desktopPet)
    #expect(SwitchType.desktopPet.barInfo().title == "Show Desktop Pet")
    #expect(SwitchType.desktopPet.barInfo().controlType == .Switch)
    #expect(control.isVisible())
    #expect(await control.currentStatus() == false)
    #expect(await control.currentInfo() == "")

    try await control.operateSwitch(isOn: true)
    #expect(await control.currentStatus() == true)
    #expect(writes == [true])

    try await control.operateSwitch(isOn: false)
    #expect(await control.currentStatus() == false)
    #expect(writes == [true, false])
}

@MainActor
@Test func codexUsageBuiltInSwitchControlsTabVisibility() async throws {
    var isVisible = true
    let control = CodexUsageSwitch(
        visibility: { isVisible },
        setVisibility: { isVisible = $0 }
    )

    #expect(control.type == .codexUsage)
    #expect(SwitchType.codexUsage.barInfo().title == "Codex Usage")
    #expect(await control.currentStatus())

    try await control.operateSwitch(isOn: false)

    #expect(await control.currentStatus() == false)
}

@MainActor
@Test func systemMonitorBuiltInSwitchControlsTabVisibility() async throws {
    var isVisible = true
    var writes: [Bool] = []
    let control = SystemMonitorSwitch(
        visibility: { isVisible },
        setVisibility: {
            writes.append($0)
            isVisible = $0
        }
    )

    #expect(control.type == .systemMonitor)
    #expect(SwitchType.systemMonitor.legacyIdentifier == 1 << 42)
    #expect(SwitchType.systemMonitor.barInfo().title == "System Monitor")
    #expect(control.isVisible())
    #expect(await control.currentStatus())

    try await control.operateSwitch(isOn: false)

    #expect(await control.currentStatus() == false)
    #expect(writes == [false])

    try await control.operateSwitch(isOn: true)

    #expect(await control.currentStatus())
    #expect(writes == [false, true])
}

@MainActor
@Test func reverseScrollDirectionBuiltInSwitchMapsStatusAndControllerRequests() async throws {
    var isReversed = false
    var writes: [Bool] = []
    let control = ReverseScrollDirectionSwitch(
        readStatus: { isReversed },
        writeStatus: { value in
            writes.append(value)
            isReversed = value
        }
    )

    #expect(control.type == .reverseScrollDirection)
    #expect(SwitchType.reverseScrollDirection.legacyIdentifier == 1 << 41)
    #expect(SwitchType.reverseScrollDirection.barInfo().title == "Natural Scrolling")
    #expect(control.isVisible())
    #expect(await control.currentStatus() == false)

    try await control.operateSwitch(isOn: true)
    #expect(await control.currentStatus())
    #expect(writes == [true])

    try await control.operateSwitch(isOn: false)
    #expect(await control.currentStatus() == false)
    #expect(writes == [true, false])
}

@MainActor
@Test func reverseScrollDirectionBuiltInSwitchHandlesCommandErrors() async {
    let readFailure = ReverseScrollDirectionSwitch(
        readStatus: { throw ReverseScrollDirectionTestError.failed },
        writeStatus: { _ in }
    )
    #expect(await readFailure.currentStatus() == false)

    let writeFailure = ReverseScrollDirectionSwitch(
        readStatus: { false },
        writeStatus: { _ in throw ReverseScrollDirectionTestError.failed }
    )
    await #expect(throws: SwitchError.self) {
        try await writeFailure.operateSwitch(isOn: true)
    }
}

private enum ReverseScrollDirectionTestError: Error {
    case failed
}

struct ScrollWheelEventTraitsTests {
    @Test func ordinaryVerticalWheelIsInverted() {
        let traits = ScrollWheelEventTraits(
            isContinuous: false,
            scrollPhase: 0,
            momentumPhase: 0,
            tabletDeviceID: 0,
            sourceUserData: 0,
            vertical: .init(line: 3, point: 24, fixedPoint: 24 << 16),
            horizontal: .init(line: 0, point: 0, fixedPoint: 0)
        )

        #expect(traits.shouldInvert)
    }

    @Test func continuousTrackpadEventPassesThrough() {
        let traits = ScrollWheelEventTraits(
            isContinuous: true,
            scrollPhase: 0,
            momentumPhase: 0,
            tabletDeviceID: 0,
            sourceUserData: 0,
            vertical: .init(line: 1, point: 8, fixedPoint: 8 << 16),
            horizontal: .init(line: 0, point: 0, fixedPoint: 0)
        )

        #expect(traits.shouldInvert == false)
    }

    @Test func phaseBearingEventsPassThrough() {
        let gesture = ScrollWheelEventTraits(
            isContinuous: false,
            scrollPhase: 1,
            momentumPhase: 0,
            tabletDeviceID: 0,
            sourceUserData: 0,
            vertical: .init(line: 1, point: 8, fixedPoint: 8 << 16),
            horizontal: .init(line: 0, point: 0, fixedPoint: 0)
        )
        let momentum = ScrollWheelEventTraits(
            isContinuous: false,
            scrollPhase: 0,
            momentumPhase: 1,
            tabletDeviceID: 0,
            sourceUserData: 0,
            vertical: .init(line: 1, point: 8, fixedPoint: 8 << 16),
            horizontal: .init(line: 0, point: 0, fixedPoint: 0)
        )

        #expect(gesture.shouldInvert == false)
        #expect(momentum.shouldInvert == false)
    }

    @Test func tabletAndDiagonalEventsPassThrough() {
        let tablet = ScrollWheelEventTraits(
            isContinuous: false,
            scrollPhase: 0,
            momentumPhase: 0,
            tabletDeviceID: 7,
            sourceUserData: 0,
            vertical: .init(line: 1, point: 8, fixedPoint: 8 << 16),
            horizontal: .init(line: 0, point: 0, fixedPoint: 0)
        )
        let diagonal = ScrollWheelEventTraits(
            isContinuous: false,
            scrollPhase: 0,
            momentumPhase: 0,
            tabletDeviceID: 0,
            sourceUserData: 0,
            vertical: .init(line: 1, point: 8, fixedPoint: 8),
            horizontal: .init(line: 1, point: 4, fixedPoint: 4 << 16)
        )

        #expect(tablet.shouldInvert == false)
        #expect(diagonal.shouldInvert == false)
    }

    @Test func syntheticReplacementEventPassesThrough() {
        let traits = ScrollWheelEventTraits(
            isContinuous: false,
            scrollPhase: 0,
            momentumPhase: 0,
            tabletDeviceID: 0,
            sourceUserData: ScrollDirectionEventTap.syntheticEventTag,
            vertical: .init(line: 1, point: 8, fixedPoint: 8 << 16),
            horizontal: .init(line: 0, point: 0, fixedPoint: 0)
        )

        #expect(traits.shouldInvert == false)
    }
}

struct VerticalScrollInversionPlanTests {
    @Test func ordinaryWheelInvertsAllVerticalDeltaRepresentations() {
        let inverted = VerticalScrollDeltas(
            line: -2,
            point: -17,
            fixedPoint: -(17 << 16)
        ).inverted

        #expect(inverted == VerticalScrollDeltas(line: 2, point: 17, fixedPoint: 17 << 16))
    }

    @Test func minimumIntegerDeltasAreNegatedWithoutOverflow() {
        let inverted = VerticalScrollDeltas(line: .min, point: .min, fixedPoint: .min).inverted

        #expect(inverted.line == .max)
        #expect(inverted.point == .max)
        #expect(inverted.fixedPoint == .max)
    }
}

struct ReverseScrollRuntimeStateTests {
    @Test func requestedStateCanSurviveAStoppedTapAndResumeLater() {
        var state = ReverseScrollRuntimeState(isRequested: true)

        #expect(state.isRequested)
        #expect(state.currentStatus == false)

        state.didStart()
        #expect(state.currentStatus)

        state.didStop()
        #expect(state.isRequested)
        #expect(state.currentStatus == false)

        state.didStart()
        #expect(state.currentStatus)
    }

    @Test func disablingClearsBothRequestedAndRunningState() {
        var state = ReverseScrollRuntimeState(isRequested: true)
        state.didStart()

        state.setRequested(false)

        #expect(state.isRequested == false)
        #expect(state.isRunning == false)
        #expect(state.currentStatus == false)
    }
}

struct LegacyScrollDirectionMigrationTests {
    @MainActor
    @Test func migrationRestoresAndRemovesSavedPreferenceAfterSuccess() throws {
        let suiteName = "LegacyScrollDirectionMigrationTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = UserDefaults.Key.reverseScrollDirectionOriginalNaturalScrolling
        defaults.set(false, forKey: key)
        var restoredValues: [Bool] = []

        let succeeded = restoreLegacyScrollDirectionIfNeeded(
            defaults: defaults,
            preference: GlobalScrollDirectionPreference(setNatural: { value in
                restoredValues.append(value)
                return true
            })
        )

        #expect(succeeded)
        #expect(restoredValues == [false])
        #expect(defaults.object(forKey: key) == nil)
    }

    @MainActor
    @Test func migrationKeepsSavedPreferenceWhenRestoreFails() throws {
        let suiteName = "LegacyScrollDirectionMigrationTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = UserDefaults.Key.reverseScrollDirectionOriginalNaturalScrolling
        defaults.set(true, forKey: key)

        let succeeded = restoreLegacyScrollDirectionIfNeeded(
            defaults: defaults,
            preference: GlobalScrollDirectionPreference(setNatural: { _ in false })
        )

        #expect(succeeded == false)
        #expect(defaults.object(forKey: key) as? Bool == true)
    }
}

struct BrightnessSyncStateTests {
    @Test func pollingRequiresRunningSyncWithBuiltInAndExternalDisplays() {
        var state = BrightnessSyncState()

        #expect(!state.shouldPoll)

        state.start()
        #expect(!state.shouldPoll)

        let generation = state.topologyChanged(hasBuiltInDisplay: true)
        #expect(!state.shouldPoll)
        let emptyRefreshAccepted = state.acceptRefresh(generation: generation, externalDisplayCount: 0)
        #expect(emptyRefreshAccepted)
        #expect(!state.shouldPoll)
        let externalRefreshAccepted = state.acceptRefresh(generation: generation, externalDisplayCount: 1)
        #expect(externalRefreshAccepted)
        #expect(state.shouldPoll)

        _ = state.topologyChanged(hasBuiltInDisplay: false)
        #expect(!state.shouldPoll)
    }

    @Test func stopAndStaleRefreshesCannotReenablePolling() {
        var state = BrightnessSyncState()
        state.start()
        let generation = state.topologyChanged(hasBuiltInDisplay: true)

        state.stop()

        let stoppedRefreshAccepted = state.acceptRefresh(generation: generation, externalDisplayCount: 1)
        #expect(!stoppedRefreshAccepted)
        #expect(!state.shouldPoll)
    }

    @Test func currentTopologyRefreshIsAcceptedAndSupersedesOlderRefreshes() {
        var state = BrightnessSyncState()
        state.start()
        let oldGeneration = state.topologyChanged(hasBuiltInDisplay: true)
        let currentGeneration = state.topologyChanged(hasBuiltInDisplay: true)

        let staleRefreshAccepted = state.acceptRefresh(generation: oldGeneration, externalDisplayCount: 2)
        #expect(!staleRefreshAccepted)
        #expect(!state.shouldPoll)
        let currentRefreshAccepted = state.acceptRefresh(generation: currentGeneration, externalDisplayCount: 2)
        #expect(currentRefreshAccepted)
        #expect(state.shouldPoll)
    }
}

@MainActor
private final class TestDesktopPetPomodoroPresenter: DesktopPetPomodoroPresenting {
    var isVisible = false
    private(set) var pomodoroState: DesktopPetPomodoroState?

    func setPomodoroState(_ state: DesktopPetPomodoroState?) {
        pomodoroState = state
    }
}

@MainActor
struct SettingsViewTests {
    @Test(
        "The open settings sidebar refreshes titles after a language change",
        .serialized,
        .disabled("Requires the app host after package migration: hosts SettingsView in an NSWindow and pumps the main run loop")
    )
    func sidebarTitlesRefreshAfterLanguageChange() {
        let languageManager = LanguageManager.sharedManager
        let originalLanguage = languageManager.currentLang
        let originalSystemLanguagePriority = languageManager.systemLangPriority
        let originalSelection = SettingsVM.shared.selection
        defer {
            SettingsVM.shared.selection = originalSelection
            if originalSystemLanguagePriority {
                languageManager.setSystemLangPriority()
            } else {
                languageManager.setCertainLang(originalLanguage)
            }
        }

        languageManager.setCertainLang("en")
        SettingsVM.shared.selection = .Customize

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let hostingView = NSHostingView(rootView: SettingsView())
        window.contentView = hostingView
        window.orderFrontRegardless()
        hostingView.layoutSubtreeIfNeeded()
        defer { window.close() }

        #expect(
            waitForAccessibilityValue("General", in: hostingView),
            "The sidebar should initially show the English title."
        )

        languageManager.setCertainLang("ja")

        #expect(
            waitForAccessibilityValue("一般", in: hostingView),
            "The open sidebar should refresh its localized titles without recreating the settings window."
        )
    }

    @Test(
        "The split-view detail renders the restored sidebar destination",
        .serialized,
        .disabled("Requires the app host after package migration: hosts SettingsView in an NSWindow and pumps the main run loop")
    )
    func splitViewDetailRendersRestoredSelection() {
        let originalSelection = SettingsVM.shared.selection
        defer { SettingsVM.shared.selection = originalSelection }
        SettingsVM.shared.selection = .Customize

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let hostingView = NSHostingView(rootView: SettingsView())
        window.contentView = hostingView
        window.orderFrontRegardless()
        hostingView.layoutSubtreeIfNeeded()
        defer { window.close() }

        #expect(
            waitForAccessibilityValue(
                "To add or remove any switches on list".localized(),
                in: hostingView
            ),
            "Settings should display the restored Customize page instead of General."
        )
    }

    private func waitForAccessibilityValue(
        _ value: String,
        in element: any NSAccessibilityProtocol
    ) -> Bool {
        let deadline = Date().addingTimeInterval(1)

        repeat {
            if accessibilityTree(of: element).contains(value) {
                return true
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        } while Date() < deadline

        return accessibilityTree(of: element).contains(value)
    }

    private func accessibilityTree(of element: any NSAccessibilityProtocol) -> [String] {
        let children = element.accessibilityChildren() as? [any NSAccessibilityProtocol] ?? []

        return [
            element.accessibilityLabel(),
            element.accessibilityValueDescription(),
            element.accessibilityValue() as? String
        ]
            .compactMap { $0 }
            + children.flatMap { accessibilityTree(of: $0) }
    }
}

@MainActor
struct SettingsVMAphroditeLifetimeTests {
    @Test func retainedStoreFinishesGenerationAfterPresentationIsReleased() async throws {
        guard #available(macOS 26.0, *) else { return }
        let taskID = UUID()
        let continuation = LockIsolated<CheckedContinuation<String, Error>?>(nil)
        let delivered = LockIsolated(0)
        let library = LockIsolated<AphroditeLibrary?>(nil)
        let owner = SettingsVM()
        var initialState = AphroditeReducer.State(
            prompt: "Build a counter",
            selection: .init(provider: .openai, model: "gpt-test"),
            storageState: .ready
        )
        initialState.models = [.openai: ["gpt-test"]]
        owner.aphroditeStore = Store(initialState: initialState) {
            AphroditeReducer()
        } withDependencies: {
            $0.uuid = .constant(taskID)
            $0.date.now = .distantPast
            $0.modelProviderService.generateApp = { _ in
                try await withCheckedThrowingContinuation { pending in
                    continuation.withValue { $0 = pending }
                }
            }
            $0.aphroditePersistence.insert = { app, selection in
                let persisted = AphroditeLibrary(apps: [app], selection: selection)
                library.withValue { $0 = persisted }
                return persisted
            }
            $0.aphroditeLocalNotification.requestAuthorization = { true }
            $0.aphroditeLocalNotification.deliver = { _ in delivered.withValue { $0 += 1 } }
        }

        var presentation: NSHostingView<AphroditeSettingsView>? = NSHostingView(
            rootView: AphroditeSettingsView(store: owner.aphroditeStore)
        )
        let operation = owner.aphroditeStore.send(.generateTapped)
        presentation = nil
        #expect(presentation == nil)
        while continuation.value == nil { await Task.yield() }
        continuation.withValue { $0?.resume(returning: "<!doctype html><html><head><title>Counter</title></head><body></body></html>") }
        await operation.finish()

        let recreated = NSHostingView(rootView: AphroditeSettingsView(store: owner.aphroditeStore))
        let persisted = try #require(library.value)
        #expect(owner.aphroditeStore.apps == IdentifiedArray(uniqueElements: persisted.apps))
        #expect(delivered.value == 1)
        _ = recreated

        #expect(owner.aphroditeStore === owner.aphroditeStore)
    }
}

struct AphroditeForegroundNotificationTests {
    @Test func foregroundCompletionUsesBannerAndSound() {
        let options = AppDelegate.aphroditeForegroundNotificationOptions

        #expect(options.contains(.banner))
        #expect(options.contains(.sound))
    }
}

struct LocalNetworkPermissionMetadataTests {
    @Test("The host app declares its local-network and Bonjour pairing metadata")
    func hostAppDeclaresLocalNetworkPairingMetadata() throws {
        // Package tests run outside the app host, so read the app's Info.plist from the source tree.
        let infoPlistURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "OnlySwitch/Info.plist")
        let infoPlist = try #require(NSDictionary(contentsOf: infoPlistURL))
        let localNetworkPurpose = try #require(
            infoPlist["NSLocalNetworkUsageDescription"] as? String
        )
        let bonjourServices = try #require(
            infoPlist["NSBonjourServices"] as? [String]
        )

        #expect(
            localNetworkPurpose == "Only Switch uses your local network to let OnlyRemote on your iPhone or iPad discover and control this Mac."
        )
        #expect(bonjourServices.contains("_onlyswitch._tcp"))
    }
}

struct CrashReportDiscoveryTests {
    private let bundleIdentifier = "jacklandrin.OnlySwitch"
    private let cutoff = Date(timeIntervalSince1970: 1_793_790_970)
    private var launch: Date { cutoff.addingTimeInterval(3) }

    @Test func selectsNewestIncidentByReportTimeRatherThanFileTimeOrName() throws {
        try withReportDirectory { directory in
            let older = try writeReport(in: directory, name: "OnlySwitch-zzz.ips", second: "11")
            let newest = try writeReport(in: directory, name: "OnlySwitch-aaa.ips", second: "12")
            try FileManager.default.setAttributes([.modificationDate: launch], ofItemAtPath: older.path)
            try FileManager.default.setAttributes([.modificationDate: cutoff], ofItemAtPath: newest.path)

            #expect(latest(in: directory)?.lastPathComponent == newest.lastPathComponent)
        }
    }

    @Test func excludesAcknowledgedIncidentsAndIncludesReportsAtLaunchBoundary() throws {
        try withReportDirectory { directory in
            _ = try writeReport(in: directory, name: "OnlySwitch-handled.ips", second: "10")
            _ = try writeReport(in: directory, name: "OnlySwitch-too-new.ips", second: "14")
            #expect(latest(in: directory) == nil)

            let report = try writeReport(in: directory, name: "OnlySwitch-at-launch.ips", second: "13")
            #expect(latest(in: directory)?.lastPathComponent == report.lastPathComponent)
            #expect(CrashReportDiscovery.latest(
                in: directory, bundleIdentifier: bundleIdentifier, after: launch, through: launch
            ) == nil)
        }
    }

    @Test func ignoresOtherProcessesOtherDiagnosticTypesAndMalformedFiles() throws {
        try withReportDirectory { directory in
            _ = try writeReport(
                in: directory, name: "OnlySwitch-widget.ips", identifier: "jacklandrin.OnlySwitch.OnlyWidget"
            )
            _ = try writeReport(in: directory, name: "OnlySwitch-fault.ips", bugType: "288")
            _ = try writeReport(in: directory, name: "OnlySwitch-other-platform.ips", platform: 2)
            _ = try writeReport(in: directory, name: "OnlySwitch-not-ips.txt")
            try Data("{\"bug_type\":\"309\"".utf8).write(
                to: directory.appendingPathComponent("OnlySwitch-malformed.ips")
            )
            _ = try writeReport(in: directory, name: "OnlySwitch-no-newline.ips", hasNewline: false)

            #expect(latest(in: directory) == nil)
        }
    }

    @Test func ignoresSymbolicLinksToReportsOutsideTheDirectory() throws {
        try withReportDirectory { directory in
            try withReportDirectory { externalDirectory in
                let externalReport = try writeReport(in: externalDirectory, name: "OnlySwitch-external.ips")
                try FileManager.default.createSymbolicLink(
                    at: directory.appendingPathComponent("OnlySwitch-linked.ips"),
                    withDestinationURL: externalReport
                )

                #expect(latest(in: directory) == nil)
            }
        }
    }

    private func latest(in directory: URL) -> URL? {
        CrashReportDiscovery.latest(
            in: directory, bundleIdentifier: bundleIdentifier, after: cutoff, through: launch
        )?.url
    }

    private func withReportDirectory(_ run: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        try run(directory)
    }

    private func writeReport(
        in directory: URL,
        name: String,
        second: String = "12",
        identifier: String = "jacklandrin.OnlySwitch",
        bugType: String = "309",
        platform: Int = 1,
        hasNewline: Bool = true
    ) throws -> URL {
        let report = directory.appendingPathComponent(name)
        var contents = try JSONSerialization.data(withJSONObject: [
            "app_name": "OnlySwitch",
            "bundleID": identifier,
            "bug_type": bugType,
            "incident_id": UUID().uuidString,
            "platform": platform,
            "timestamp": "2026-11-04 12:16:\(second).00 +0100"
        ])
        if hasNewline {
            contents.append(contentsOf: "\n{\"procName\":\"OnlySwitch\"}\n".utf8)
        }
        try contents.write(to: report)
        return report
    }
}

struct CrashReportPromptTests {
    @MainActor
    @Test(arguments: [false, true])
    func acknowledgesAcrossRelaunchAndRevealsOnlyOnRequest(revealRequested: Bool) async throws {
        let suite = "OnlySwitch.CrashReportPromptTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let initialLaunch = Date(timeIntervalSince1970: 1_793_790_970)
        let report = CrashReportDiscovery.Report(
            url: URL(fileURLWithPath: "/tmp/OnlySwitch-test.ips"),
            timestamp: initialLaunch.addingTimeInterval(60)
        )
        let presentation = PresentationProbe()
        let watermark = CrashReportWatermark(defaults: defaults)
        watermark.beginMonitoring(at: initialLaunch)

        func launch(using watermark: CrashReportWatermark) async -> Bool {
            await withDependencies {
                $0.crashReport.cutoff = { watermark.cutoff }
                $0.crashReport.latest = { report.timestamp > $0 ? report : nil }
                $0.crashReport.present = {
                    presentation.count += 1
                    return revealRequested
                }
                $0.crashReport.acknowledge = { watermark.acknowledge($0) }
                $0.crashReport.reveal = { presentation.revealed.append($0) }
            } operation: {
                await CrashReportPrompt().presentIfNeeded()
            }
        }

        #expect(await launch(using: watermark))

        let relaunchedDefaults = try #require(UserDefaults(suiteName: suite))
        let relaunchedWatermark = CrashReportWatermark(defaults: relaunchedDefaults)
        relaunchedWatermark.beginMonitoring(at: report.timestamp.addingTimeInterval(60))
        #expect(relaunchedWatermark.cutoff == report.timestamp)
        #expect(await launch(using: relaunchedWatermark) == false)
        #expect(presentation.count == 1)
        #expect(presentation.revealed == (revealRequested ? [report.url] : []))
    }

    @MainActor
    private final class PresentationProbe {
        var count = 0
        var revealed: [URL] = []
    }
}
