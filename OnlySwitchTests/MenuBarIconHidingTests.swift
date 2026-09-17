import AppKit
@preconcurrency import ApplicationServices
import Foundation
import Testing
@testable import OnlySwitch

@MainActor
struct StatusBarControllerStatusItemConfigurationTests {
    @Test("new status items permit removal and are immediately visible")
    func configureStatusItemPermitsRemovalAndMakesItemVisible() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        defer { NSStatusBar.system.removeStatusItem(item) }

        item.behavior.remove(.removalAllowed)
        item.isVisible = false

        StatusBarController.configureStatusItem(item)

        #expect(item.behavior.contains(.removalAllowed))
        #expect(item.isVisible)
    }
}

@MainActor
struct HideMenubarIconsSettingVMTests {
    @Test("native visibility limitation notice is macOS 27 only")
    func nativeVisibilityLimitationNoticeAvailability() {
        let legacy = HideMenubarIconsSettingVM(operatingSystemMajorVersion: { 26 })
        let native = HideMenubarIconsSettingVM(operatingSystemMajorVersion: { 27 })

        #expect(!legacy.showsNativeVisibilityLimitation)
        #expect(native.showsNativeVisibilityLimitation)
    }
}

@MainActor
struct MenuBarIconHidingCoordinatorTests {
    @Test("macOS 27 uses the native backend without marker resizing")
    func macOS27UsesNativeBackendWithoutChangingMarkerLength() async throws {
        let native = RecordingApplier()
        let legacy = RecordingApplier()
        let coordinator = MenuBarIconHidingCoordinator(
            operatingSystemMajorVersion: { 27 }, nativeApplier: native, legacyApplier: legacy,
            visibleItemResolver: RecordingResolver(.success(.init(
                allowedBundleIdentifiers: ["jacklandrin.OnlySwitch"], allowedSystemItemIdentifiers: []
            )))
        )

        try await coordinator.setCollapsed(true)

        #expect(native.requests == [.collapse(.init(
            allowedBundleIdentifiers: ["jacklandrin.OnlySwitch"], allowedSystemItemIdentifiers: []
        ))])
        #expect(legacy.requests.isEmpty)
    }

    @Test("macOS 26 keeps the legacy spacer backend")
    func macOS26UsesLegacySpacerBackend() async throws {
        let native = RecordingApplier()
        let legacy = RecordingApplier()
        let coordinator = MenuBarIconHidingCoordinator(
            operatingSystemMajorVersion: { 26 }, nativeApplier: native, legacyApplier: legacy,
            visibleItemResolver: RecordingResolver(.failure(.accessibilityDenied))
        )

        try await coordinator.setCollapsed(true)

        #expect(legacy.requests == [.collapse(.empty)])
        #expect(native.requests.isEmpty)
    }

    @Test("resolver failure leaves both backends untouched")
    func resolverFailureDoesNotCallEitherBackend() async {
        let native = RecordingApplier()
        let legacy = RecordingApplier()
        let coordinator = MenuBarIconHidingCoordinator(
            operatingSystemMajorVersion: { 27 }, nativeApplier: native, legacyApplier: legacy,
            visibleItemResolver: RecordingResolver(.failure(.accessibilityDenied))
        )

        do {
            try await coordinator.setCollapsed(true)
            Issue.record("Expected Accessibility failure.")
        } catch {
            #expect((error as? MenuBarIconHidingError) == .accessibilityDenied)
        }
        #expect(native.requests.isEmpty)
        #expect(legacy.requests.isEmpty)
    }

    @Test("expansion uses only the selected backend")
    func expansionUsesSelectedBackend() async throws {
        let native = RecordingApplier()
        let legacy = RecordingApplier()
        let coordinator = MenuBarIconHidingCoordinator(
            operatingSystemMajorVersion: { 27 }, nativeApplier: native, legacyApplier: legacy,
            visibleItemResolver: RecordingResolver(.failure(.accessibilityDenied))
        )

        try await coordinator.setCollapsed(false)

        #expect(native.requests == [.expand])
        #expect(legacy.requests.isEmpty)
    }

    @Test("native activation failure does not fall back to the legacy spacer")
    func nativeActivationFailureDoesNotFallBackToLegacySpacer() async {
        let native = RecordingApplier(collapseError: .nativeOperationFailed)
        let legacy = RecordingApplier()
        let coordinator = MenuBarIconHidingCoordinator(
            operatingSystemMajorVersion: { 27 }, nativeApplier: native, legacyApplier: legacy,
            visibleItemResolver: RecordingResolver(.success(.empty))
        )

        do {
            try await coordinator.setCollapsed(true)
            Issue.record("Expected native activation failure.")
        } catch {
            #expect((error as? MenuBarIconHidingError) == .nativeOperationFailed)
        }
        #expect(native.requests == [.collapse(.empty)])
        #expect(legacy.requests.isEmpty)
    }

    @Test("overlapping requests execute in FIFO order")
    func overlappingRequestsExecuteInFIFOOrder() async throws {
        let native = BlockingApplier()
        let coordinator = MenuBarIconHidingCoordinator(
            operatingSystemMajorVersion: { 27 }, nativeApplier: native, legacyApplier: RecordingApplier(),
            visibleItemResolver: RecordingResolver(.success(.empty))
        )

        let collapse = Task { @MainActor in try await coordinator.setCollapsed(true) }
        await native.waitUntilCollapseStarts()
        let expand = Task { @MainActor in try await coordinator.setCollapsed(false) }
        await Task.yield()

        #expect(native.requests == [.collapse(.empty)])
        #expect(native.maximumConcurrentRequests == 1)

        await native.releaseCollapse()
        try await collapse.value
        try await expand.value
        #expect(native.requests == [.collapse(.empty), .expand])
        #expect(native.maximumConcurrentRequests == 1)
    }
}

@MainActor
struct MenuBarClientCoreVisibilityApplierTests {
    @Test("native adapter passes numeric identifiers to the bridge")
    func nativeApplierPassesDeduplicatedAllowlistToBridge() async throws {
        let bridge = RecordingBridge(isAvailable: true)
        let applier = MenuBarClientCoreVisibilityApplier(bridge: bridge)

        try await applier.applyCollapse(allowing: .init(
            allowedBundleIdentifiers: ["jacklandrin.OnlySwitch", "com.apple.controlcenter", "jacklandrin.OnlySwitch"],
            allowedSystemItemIdentifiers: [2, 2]
        ))

        #expect(bridge.activations == [.init(
            systemItems: [2], bundleIdentifiers: ["com.apple.controlcenter", "jacklandrin.OnlySwitch"]
        )])
    }

    @Test("unavailable or signature-ineligible native bridge rejects before activation")
    func nativeApplierRejectsUnavailableBridgeBeforeActivation() async {
        let bridge = RecordingBridge(isAvailable: false)
        let applier = MenuBarClientCoreVisibilityApplier(bridge: bridge)

        do {
            try await applier.applyCollapse(allowing: .empty)
            Issue.record("Expected unavailable native API failure.")
        } catch {
            #expect((error as? MenuBarIconHidingError) == .nativeAPIUnavailable)
        }
        #expect(bridge.activations.isEmpty)
    }

    @Test("native adapter invalidates before replacement and expansion")
    func nativeApplierInvalidatesBeforeReplacingOrExpandingAssertion() async throws {
        let bridge = RecordingBridge(isAvailable: true)
        let applier = MenuBarClientCoreVisibilityApplier(bridge: bridge)

        try await applier.applyCollapse(allowing: .empty)
        try await applier.applyCollapse(allowing: .empty)
        await applier.applyExpansion()

        #expect(bridge.invalidationCount == 2)
        #expect(!bridge.hasActiveAssertion)
    }

    @Test("native adapter recovers after a failed activation")
    func nativeApplierRecoversAfterFailedActivation() async throws {
        let bridge = RecordingBridge(isAvailable: true, results: [.failure(.nativeOperationFailed), .success(())])
        let applier = MenuBarClientCoreVisibilityApplier(bridge: bridge)

        do {
            try await applier.applyCollapse(allowing: .empty)
            Issue.record("Expected native activation failure.")
        } catch {
            #expect((error as? MenuBarIconHidingError) == .nativeOperationFailed)
        }
        #expect(!bridge.hasActiveAssertion)

        try await applier.applyCollapse(allowing: .empty)
        #expect(bridge.activations.count == 2)
        #expect(bridge.hasActiveAssertion)
    }
}

@MainActor
struct AXMenuBarVisibleItemResolverTests {
    @Test("resolver keeps the marker's visible-side items")
    func resolverKeepsOnlySwitchAndItemsAtOrRightOfMarker() throws {
        let resolver = AXMenuBarVisibleItemResolver(
            markerScreenX: { 500 }, mainItemScreenX: { 600 }, runningBundleIdentifiers: { [] }, ownBundleIdentifier: { "jacklandrin.OnlySwitch" },
            source: RecordingAXSource(isTrusted: true, items: [
                .init(midX: 420, bundleIdentifier: "com.left.app", systemItemIdentifier: nil),
                .init(midX: 500, bundleIdentifier: "com.equal.app", systemItemIdentifier: nil),
                .init(midX: 620, bundleIdentifier: nil, systemItemIdentifier: 2)
            ])
        )

        #expect(try resolver.itemsToKeepVisible() == .init(
            allowedBundleIdentifiers: ["com.equal.app", "jacklandrin.OnlySwitch"], allowedSystemItemIdentifiers: [2]
        ))
    }

    @Test("untrusted Accessibility prevents AX enumeration")
    func resolverRejectsUntrustedAccessibilityWithoutEnumeratingItems() {
        let source = RecordingAXSource(isTrusted: false, items: [])
        let resolver = AXMenuBarVisibleItemResolver(
            markerScreenX: { 500 }, mainItemScreenX: { 600 }, runningBundleIdentifiers: { [] }, ownBundleIdentifier: { "jacklandrin.OnlySwitch" }, source: source
        )

        do {
            _ = try resolver.itemsToKeepVisible()
            Issue.record("Expected Accessibility failure.")
        } catch {
            #expect((error as? MenuBarIconHidingError) == .accessibilityDenied)
        }
        #expect(source.readCount == 0)
    }

    @Test("missing marker coordinate is rejected")
    func resolverRejectsMissingMarkerCoordinate() {
        let resolver = AXMenuBarVisibleItemResolver(
            markerScreenX: { nil }, mainItemScreenX: { 600 }, runningBundleIdentifiers: { [] }, ownBundleIdentifier: { "jacklandrin.OnlySwitch" },
            source: RecordingAXSource(isTrusted: true, items: [])
        )

        do {
            _ = try resolver.itemsToKeepVisible()
            Issue.record("Expected marker-position failure.")
        } catch {
            #expect((error as? MenuBarIconHidingError) == .invalidMarkerPosition)
        }
    }

    @Test("system-item mapping uses the verified macOS 27 identifiers")
    func resolverUsesVerifiedSystemItemIdentifiers() throws {
        let records = MBSystemItemIdentifier.allCases.reversed().map {
            AXMenuBarItemRecord(midX: 600, bundleIdentifier: nil, systemItemIdentifier: $0.rawValue)
        }
        let resolver = AXMenuBarVisibleItemResolver(
            markerScreenX: { 500 }, mainItemScreenX: { 600 }, runningBundleIdentifiers: { [] }, ownBundleIdentifier: { "jacklandrin.OnlySwitch" },
            source: RecordingAXSource(isTrusted: true, items: records)
        )

        #expect(try resolver.itemsToKeepVisible().allowedSystemItemIdentifiers == [0, 1, 2, 3, 4, 5, 6, 7, 8])
    }

    @Test("resolver ignores unidentified records while retaining known right-side items")
    func resolverIgnoresUnidentifiedRecordsAndExcludesLeftSideItems() throws {
        let resolver = AXMenuBarVisibleItemResolver(
            markerScreenX: { 500 }, mainItemScreenX: { 600 }, runningBundleIdentifiers: { [] }, ownBundleIdentifier: { "jacklandrin.OnlySwitch" },
            source: RecordingAXSource(isTrusted: true, items: [
                .init(midX: 420, bundleIdentifier: "com.left.bundle", systemItemIdentifier: nil),
                .init(midX: 450, bundleIdentifier: nil, systemItemIdentifier: 2),
                .init(midX: 580, bundleIdentifier: nil, systemItemIdentifier: nil),
                .init(midX: 620, bundleIdentifier: nil, systemItemIdentifier: nil),
                .init(midX: 650, bundleIdentifier: "com.right.bundle", systemItemIdentifier: nil),
                .init(midX: 700, bundleIdentifier: nil, systemItemIdentifier: 6)
            ])
        )

        #expect(try resolver.itemsToKeepVisible() == .init(
            allowedBundleIdentifiers: ["com.right.bundle", "jacklandrin.OnlySwitch"],
            allowedSystemItemIdentifiers: [6]
        ))
    }

    @Test("unrecognized system identifiers do not prevent native collapse")
    func unrecognizedSystemIdentifierIsExcludedBeforeNativeCollapse() async throws {
        let native = RecordingApplier()
        let resolver = AXMenuBarVisibleItemResolver(
            markerScreenX: { 500 }, mainItemScreenX: { 600 }, runningBundleIdentifiers: { [] }, ownBundleIdentifier: { "jacklandrin.OnlySwitch" },
            source: RecordingAXSource(isTrusted: true, items: [
                .init(midX: 600, bundleIdentifier: nil, systemItemIdentifier: 99)
            ])
        )
        let coordinator = MenuBarIconHidingCoordinator(
            operatingSystemMajorVersion: { 27 }, nativeApplier: native, legacyApplier: RecordingApplier(),
            visibleItemResolver: resolver
        )

        try await coordinator.setCollapsed(true)

        #expect(native.requests == [.collapse(.init(
            allowedBundleIdentifiers: ["jacklandrin.OnlySwitch"],
            allowedSystemItemIdentifiers: []
        ))])
    }

    @Test("missing main-item position is rejected before AX enumeration")
    func resolverRejectsMissingMainItemPosition() {
        let source = RecordingAXSource(isTrusted: true, items: [])
        let resolver = AXMenuBarVisibleItemResolver(
            markerScreenX: { 500 }, mainItemScreenX: { nil }, runningBundleIdentifiers: { [] }, ownBundleIdentifier: { "jacklandrin.OnlySwitch" }, source: source
        )

        do {
            _ = try resolver.itemsToKeepVisible()
            Issue.record("Expected main-item position failure.")
        } catch {
            #expect((error as? MenuBarIconHidingError) == .invalidMarkerPosition)
        }
        #expect(source.readCount == 0)
    }

    @Test("non-finite main-item position is rejected before AX enumeration")
    func resolverRejectsNonFiniteMainItemPosition() {
        let source = RecordingAXSource(isTrusted: true, items: [])
        let resolver = AXMenuBarVisibleItemResolver(
            markerScreenX: { 500 }, mainItemScreenX: { .nan }, runningBundleIdentifiers: { [] }, ownBundleIdentifier: { "jacklandrin.OnlySwitch" }, source: source
        )

        do {
            _ = try resolver.itemsToKeepVisible()
            Issue.record("Expected main-item position failure.")
        } catch {
            #expect((error as? MenuBarIconHidingError) == .invalidMarkerPosition)
        }
        #expect(source.readCount == 0)
    }

    @Test("main item left of the marker is rejected before AX enumeration")
    func resolverRejectsMainItemLeftOfMarker() {
        let source = RecordingAXSource(isTrusted: true, items: [])
        let resolver = AXMenuBarVisibleItemResolver(
            markerScreenX: { 500 }, mainItemScreenX: { 499 }, runningBundleIdentifiers: { [] }, ownBundleIdentifier: { "jacklandrin.OnlySwitch" }, source: source
        )

        do {
            _ = try resolver.itemsToKeepVisible()
            Issue.record("Expected main-item position failure.")
        } catch {
            #expect((error as? MenuBarIconHidingError) == .invalidMarkerPosition)
        }
        #expect(source.readCount == 0)
    }

    @Test("valid geometry keeps OnlySwitch visible even without other icons")
    func resolverKeepsOnlySwitchBundleWithValidGeometry() throws {
        let resolver = AXMenuBarVisibleItemResolver(
            markerScreenX: { 500 }, mainItemScreenX: { 600 }, runningBundleIdentifiers: { [] }, ownBundleIdentifier: { "jacklandrin.OnlySwitch" },
            source: RecordingAXSource(isTrusted: true, items: [])
        )

        #expect(try resolver.itemsToKeepVisible() == .init(
            allowedBundleIdentifiers: ["jacklandrin.OnlySwitch"], allowedSystemItemIdentifiers: []
        ))
    }

    @Test("running bundles absent from Accessibility stay allowed")
    func resolverKeepsRunningBundleAbsentFromAccessibility() throws {
        let resolver = AXMenuBarVisibleItemResolver(
            markerScreenX: { 500 },
            mainItemScreenX: { 600 },
            runningBundleIdentifiers: { Set(["com.running.not-in-ax"]) },
            ownBundleIdentifier: { "jacklandrin.OnlySwitch" },
            source: RecordingAXSource(isTrusted: true, items: [])
        )

        #expect(try resolver.itemsToKeepVisible().allowedBundleIdentifiers == [
            "com.running.not-in-ax", "jacklandrin.OnlySwitch"
        ])
    }

    @Test("a running bundle seen only left of the marker is removed")
    func resolverRemovesLeftOnlyRunningBundle() throws {
        let resolver = AXMenuBarVisibleItemResolver(
            markerScreenX: { 500 },
            mainItemScreenX: { 600 },
            runningBundleIdentifiers: { Set(["com.left.only", "com.not-in-ax"]) },
            ownBundleIdentifier: { "jacklandrin.OnlySwitch" },
            source: RecordingAXSource(isTrusted: true, items: [
                .init(midX: 420, bundleIdentifier: "com.left.only", systemItemIdentifier: nil)
            ])
        )

        #expect(try resolver.itemsToKeepVisible().allowedBundleIdentifiers == [
            "com.not-in-ax", "jacklandrin.OnlySwitch"
        ])
    }

    @Test("a running bundle on both marker sides remains allowed")
    func resolverKeepsBundleWhenRightSideOccurrenceWins() throws {
        let resolver = AXMenuBarVisibleItemResolver(
            markerScreenX: { 500 },
            mainItemScreenX: { 600 },
            runningBundleIdentifiers: { Set(["com.duplicate.bundle"]) },
            ownBundleIdentifier: { "jacklandrin.OnlySwitch" },
            source: RecordingAXSource(isTrusted: true, items: [
                .init(midX: 420, bundleIdentifier: "com.duplicate.bundle", systemItemIdentifier: nil),
                .init(midX: 620, bundleIdentifier: "com.duplicate.bundle", systemItemIdentifier: nil)
            ])
        )

        #expect(try resolver.itemsToKeepVisible().allowedBundleIdentifiers == [
            "com.duplicate.bundle", "jacklandrin.OnlySwitch"
        ])
    }

    @Test("OnlySwitch stays allowed even when Accessibility reports it left of the marker")
    func resolverAlwaysKeepsOwnBundle() throws {
        let resolver = AXMenuBarVisibleItemResolver(
            markerScreenX: { 500 },
            mainItemScreenX: { 600 },
            runningBundleIdentifiers: { Set<String>() },
            ownBundleIdentifier: { "jacklandrin.OnlySwitch" },
            source: RecordingAXSource(isTrusted: true, items: [
                .init(midX: 420, bundleIdentifier: "jacklandrin.OnlySwitch", systemItemIdentifier: nil)
            ])
        )

        #expect(try resolver.itemsToKeepVisible().allowedBundleIdentifiers == ["jacklandrin.OnlySwitch"])
    }

    @Test("unknown Accessibility records do not alter the bundle allowlist")
    func resolverIgnoresUnknownAccessibilityRecords() throws {
        let resolver = AXMenuBarVisibleItemResolver(
            markerScreenX: { 500 },
            mainItemScreenX: { 600 },
            runningBundleIdentifiers: { Set<String>() },
            ownBundleIdentifier: { "jacklandrin.OnlySwitch" },
            source: RecordingAXSource(isTrusted: true, items: [
                .init(midX: 420, bundleIdentifier: nil, systemItemIdentifier: nil),
                .init(midX: 620, bundleIdentifier: nil, systemItemIdentifier: 99)
            ])
        )

        #expect(try resolver.itemsToKeepVisible() == .init(
            allowedBundleIdentifiers: ["jacklandrin.OnlySwitch"], allowedSystemItemIdentifiers: []
        ))
    }
}

struct AXMenuBarRecordCollectorTests {
    @Test("WeChat uses its direct item-group frame and ignores nested application controls")
    @MainActor
    func weChatGroupFrameIsAuthoritative() throws {
        let preferredDisplayBounds = CGRect(x: 1400, y: 0, width: 500, height: 40)
        let weChatGroup = AXMenuBarItemTreeNode(
            role: kAXGroupRole as String,
            frame: CGRect(x: 1520, y: 0, width: 20, height: 24),
            bundleIdentifier: nil,
            systemItemIdentifier: nil,
            children: [
                AXMenuBarItemTreeNode(
                    role: kAXApplicationRole as String,
                    frame: nil,
                    bundleIdentifier: "com.tencent.xinWeChat",
                    systemItemIdentifier: nil,
                    children: [
                        AXMenuBarItemTreeNode(
                            role: kAXButtonRole as String,
                            frame: CGRect(x: 1580, y: 0, width: 16, height: 24),
                            bundleIdentifier: "com.tencent.xinWeChat",
                            systemItemIdentifier: nil,
                            children: []
                        ),
                        AXMenuBarItemTreeNode(
                            role: kAXMenuItemRole as String,
                            frame: CGRect(x: 1600, y: 0, width: 30, height: 24),
                            bundleIdentifier: "com.tencent.xinWeChat",
                            systemItemIdentifier: nil,
                            children: []
                        )
                    ]
                )
            ]
        )
        let preferredWindow = AXMenuBarItemTreeNode(
            role: kAXWindowRole as String,
            frame: preferredDisplayBounds,
            bundleIdentifier: nil,
            systemItemIdentifier: nil,
            children: [weChatGroup]
        )
        let otherDisplayWindow = AXMenuBarItemTreeNode(
            role: kAXWindowRole as String,
            frame: CGRect(x: 0, y: 0, width: 500, height: 40),
            bundleIdentifier: nil,
            systemItemIdentifier: nil,
            children: [
                AXMenuBarItemTreeNode(
                    role: kAXGroupRole as String,
                    frame: CGRect(x: 100, y: 0, width: 20, height: 24),
                    bundleIdentifier: "com.other.display",
                    systemItemIdentifier: nil,
                    children: []
                )
            ]
        )

        let records = try AXMenuBarRecordCollector.records(
            from: [otherDisplayWindow, preferredWindow],
            preferredDisplayBounds: preferredDisplayBounds
        )

        #expect(records == [
            .init(midX: 1530, bundleIdentifier: "com.tencent.xinWeChat", systemItemIdentifier: nil)
        ])
        #expect(records.allSatisfy { $0.midX < 1550 }, "Nested controls at x=1588 and x=1615 must not become menu-bar records.")

        let resolver = AXMenuBarVisibleItemResolver(
            markerScreenX: { 1550 },
            mainItemScreenX: { 1600 },
            runningBundleIdentifiers: { Set(["com.tencent.xinWeChat", "jacklandrin.OnlySwitch"]) },
            ownBundleIdentifier: { "jacklandrin.OnlySwitch" },
            source: RecordingAXSource(isTrusted: true, items: records)
        )

        #expect(try resolver.itemsToKeepVisible() == .init(
            allowedBundleIdentifiers: ["jacklandrin.OnlySwitch"],
            allowedSystemItemIdentifiers: []
        ))
    }

    @Test("missing preferred display bounds fail closed")
    func missingPreferredDisplayBoundsAreRejected() {
        do {
            _ = try AXMenuBarRecordCollector.records(from: [], preferredDisplayBounds: .null)
            Issue.record("Expected missing-display failure.")
        } catch {
            #expect((error as? MenuBarIconHidingError) == .invalidMarkerPosition)
        }
    }

    @Test("negative-origin displays select their intersecting menu-bar window")
    func negativeOriginPreferredDisplaySelectsItsWindow() throws {
        let preferredDisplayBounds = CGRect(x: -1920, y: 0, width: 1920, height: 40)
        let preferredWindow = AXMenuBarItemTreeNode(
            role: kAXWindowRole as String,
            frame: preferredDisplayBounds,
            bundleIdentifier: nil,
            systemItemIdentifier: nil,
            children: [
                AXMenuBarItemTreeNode(
                    role: kAXGroupRole as String,
                    frame: CGRect(x: -1800, y: 0, width: 20, height: 24),
                    bundleIdentifier: "com.negative-origin.extra",
                    systemItemIdentifier: nil,
                    children: []
                )
            ]
        )
        let otherWindow = AXMenuBarItemTreeNode(
            role: kAXWindowRole as String,
            frame: CGRect(x: 0, y: 0, width: 1920, height: 40),
            bundleIdentifier: nil,
            systemItemIdentifier: nil,
            children: [
                AXMenuBarItemTreeNode(
                    role: kAXGroupRole as String,
                    frame: CGRect(x: 100, y: 0, width: 20, height: 24),
                    bundleIdentifier: "com.other-display.extra",
                    systemItemIdentifier: nil,
                    children: []
                )
            ]
        )

        let records = try AXMenuBarRecordCollector.records(
            from: [otherWindow, preferredWindow],
            preferredDisplayBounds: preferredDisplayBounds
        )

        #expect(records == [
            .init(midX: -1790, bundleIdentifier: "com.negative-origin.extra", systemItemIdentifier: nil)
        ])
    }
}

@MainActor
struct HideMenubarIconsSwitchTransitionTests {
    @Test("switch persists and notifies only after a successful native transition")
    func switchPersistsAndNotifiesOnlyAfterSuccessfulNativeTransition() async throws {
        var events: [String] = []
        let sut = HideMenubarIconsSwitch(
            transition: { isCollapsed in events.append("backend:\(isCollapsed)") }, persistedState: false
        )
        let observer = NotificationCenter.default.addObserver(
            forName: .toggleMenubarCollapse, object: nil, queue: .main
        ) { _ in events.append("notification") }
        defer { NotificationCenter.default.removeObserver(observer) }

        try await sut.operateSwitch(isOn: true)

        #expect(events == ["backend:true", "notification"])
        #expect(await sut.currentStatus())
    }

    @Test("failed native transition changes neither persistence nor notification")
    func switchDoesNotPersistOrNotifyWhenNativeTransitionFails() async {
        let sut = HideMenubarIconsSwitch(
            transition: { _ in throw MenuBarIconHidingError.nativeAPIUnavailable }, persistedState: false
        )
        var notificationCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: .toggleMenubarCollapse, object: nil, queue: .main
        ) { _ in notificationCount += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        do {
            try await sut.operateSwitch(isOn: true)
            Issue.record("Expected native transition failure.")
        } catch {
            #expect(error is SwitchError)
        }
        #expect(await sut.currentStatus() == false)
        #expect(notificationCount == 0)
    }
}

@Test("README retains macOS 27 distribution and permission caveats")
func hideMenuBarIconsREADMEExplainsMacOS27Limitations() throws {
    let repositoryURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let readme = try String(contentsOf: repositoryURL.appending(path: "README.md"), encoding: .utf8)

    #expect(readme.contains("macOS 27"))
    #expect(readme.contains("Accessibility"))
    #expect(readme.contains("private API"))
    #expect(readme.contains("not available"))
}

@MainActor
private final class RecordingApplier: MenuBarVisibilityApplying {
    enum Request: Equatable {
        case collapse(MenuBarVisibleItems)
        case expand
    }

    private(set) var requests: [Request] = []
    private let collapseError: MenuBarIconHidingError?

    init(collapseError: MenuBarIconHidingError? = nil) {
        self.collapseError = collapseError
    }

    func applyCollapse(allowing items: MenuBarVisibleItems) async throws {
        requests.append(.collapse(items))
        if let collapseError { throw collapseError }
    }

    func applyExpansion() async {
        requests.append(.expand)
    }
}

@MainActor
private final class RecordingResolver: MenuBarVisibleItemResolving {
    private let result: Result<MenuBarVisibleItems, MenuBarIconHidingError>

    init(_ result: Result<MenuBarVisibleItems, MenuBarIconHidingError>) {
        self.result = result
    }

    func itemsToKeepVisible() throws -> MenuBarVisibleItems {
        try result.get()
    }
}

@MainActor
private final class BlockingApplier: MenuBarVisibilityApplying {
    enum Request: Equatable {
        case collapse(MenuBarVisibleItems)
        case expand
    }

    private let blocker = CollapseBlocker()
    private(set) var requests: [Request] = []
    private(set) var maximumConcurrentRequests = 0
    private var concurrentRequests = 0

    func applyCollapse(allowing items: MenuBarVisibleItems) async throws {
        requests.append(.collapse(items))
        beginRequest()
        defer { finishRequest() }
        await blocker.signalStartAndWaitForRelease()
    }

    func applyExpansion() async {
        requests.append(.expand)
        beginRequest()
        finishRequest()
    }

    func waitUntilCollapseStarts() async {
        await blocker.waitUntilStarted()
    }

    func releaseCollapse() async {
        await blocker.release()
    }

    private func beginRequest() {
        concurrentRequests += 1
        maximumConcurrentRequests = max(maximumConcurrentRequests, concurrentRequests)
    }

    private func finishRequest() {
        concurrentRequests -= 1
    }
}

private actor CollapseBlocker {
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func signalStartAndWaitForRelease() async {
        started = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

@MainActor
private final class RecordingBridge: PrivateMenuBarBridging {
    struct Activation: Equatable {
        var systemItems: [Int]
        var bundleIdentifiers: [String]
    }

    let isAvailable: Bool
    private var results: [Result<Void, MenuBarIconHidingError>]
    private(set) var activations: [Activation] = []
    private(set) var invalidationCount = 0
    private(set) var hasActiveAssertion = false

    init(isAvailable: Bool, results: [Result<Void, MenuBarIconHidingError>] = [.success(())]) {
        self.isAvailable = isAvailable
        self.results = results
    }

    func activate(allowedSystemItems: [Int], allowedBundleIdentifiers: [String]) async throws {
        activations.append(.init(systemItems: allowedSystemItems, bundleIdentifiers: allowedBundleIdentifiers))
        let result = results.isEmpty ? .success(()) : results.removeFirst()
        try result.get()
        hasActiveAssertion = true
    }

    func invalidate() {
        invalidationCount += 1
        hasActiveAssertion = false
    }
}

@MainActor
private final class RecordingAXSource: AXMenuBarSource {
    let isTrusted: Bool
    private let items: [AXMenuBarItemRecord]
    private(set) var readCount = 0

    init(isTrusted: Bool, items: [AXMenuBarItemRecord]) {
        self.isTrusted = isTrusted
        self.items = items
    }

    func visibleMenuBarItems() throws -> [AXMenuBarItemRecord] {
        readCount += 1
        return items
    }
}
