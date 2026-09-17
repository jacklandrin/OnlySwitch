//
//  MenuBarIconHiding.swift
//  OnlySwitch
//

import Foundation

enum MenuBarIconHidingBackend: Equatable, Sendable {
    case legacyMarkerSpacer
    case nativeVisibilityAssertion
}

enum MenuBarIconHidingError: Error, Equatable, Sendable {
    case invalidMarkerPosition
    case accessibilityDenied
    case nativeAPIUnavailable
    case nativeOperationFailed
}

struct MenuBarVisibleItems: Equatable, Sendable {
    var allowedBundleIdentifiers: [String]
    var allowedSystemItemIdentifiers: [Int]

    static let empty = Self(allowedBundleIdentifiers: [], allowedSystemItemIdentifiers: [])
}

/// Values used by MBAssessmentModeConfiguration on macOS 27.
enum MBSystemItemIdentifier: Int, CaseIterable, Sendable {
    case battery = 0
    case bluetooth = 1
    case clock = 2
    case displays = 3
    case keyboard = 4
    case volume = 5
    case wifi = 6
    case screenMirroring = 7
    case primaryBento = 8
}

@MainActor
protocol MenuBarVisibilityApplying: AnyObject {
    func applyCollapse(allowing items: MenuBarVisibleItems) async throws
    func applyExpansion() async
}

@MainActor
protocol MenuBarVisibleItemResolving: AnyObject {
    func itemsToKeepVisible() throws -> MenuBarVisibleItems
}

actor MenuBarTransitionGate {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        guard isLocked else {
            isLocked = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        guard waiters.isEmpty == false else {
            isLocked = false
            return
        }
        waiters.removeFirst().resume()
    }
}

@MainActor
final class MenuBarIconHidingCoordinator {
    private let operatingSystemMajorVersion: @Sendable () -> Int
    private let nativeApplier: MenuBarVisibilityApplying
    private let legacyApplier: MenuBarVisibilityApplying
    private let visibleItemResolver: MenuBarVisibleItemResolving
    private let gate = MenuBarTransitionGate()

    init(
        operatingSystemMajorVersion: @escaping @Sendable () -> Int = {
            ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        },
        nativeApplier: MenuBarVisibilityApplying,
        legacyApplier: MenuBarVisibilityApplying,
        visibleItemResolver: MenuBarVisibleItemResolving
    ) {
        self.operatingSystemMajorVersion = operatingSystemMajorVersion
        self.nativeApplier = nativeApplier
        self.legacyApplier = legacyApplier
        self.visibleItemResolver = visibleItemResolver
    }

    var backend: MenuBarIconHidingBackend {
        operatingSystemMajorVersion() >= 27 ? .nativeVisibilityAssertion : .legacyMarkerSpacer
    }

    func setCollapsed(_ isCollapsed: Bool) async throws {
        await gate.acquire()
        do {
            try await performTransition(isCollapsed)
            await gate.release()
        } catch {
            await gate.release()
            throw error
        }
    }

    private func performTransition(_ isCollapsed: Bool) async throws {
        let applier = backend == .nativeVisibilityAssertion ? nativeApplier : legacyApplier
        guard isCollapsed else {
            await applier.applyExpansion()
            return
        }

        let items: MenuBarVisibleItems
        if backend == .nativeVisibilityAssertion {
            items = try visibleItemResolver.itemsToKeepVisible()
        } else {
            items = .empty
        }
        try await applier.applyCollapse(allowing: items)
    }
}

@MainActor
protocol PrivateMenuBarBridging: AnyObject {
    var isAvailable: Bool { get }
    func activate(allowedSystemItems: [Int], allowedBundleIdentifiers: [String]) async throws
    func invalidate()
}

@MainActor
final class MenuBarClientCoreBridgeAdapter: PrivateMenuBarBridging {
    private let bridge: MenuBarClientCoreBridge

    init(bridge: MenuBarClientCoreBridge = MenuBarClientCoreBridge()) {
        self.bridge = bridge
    }

    var isAvailable: Bool {
        bridge.isAvailable
    }

    func activate(allowedSystemItems: [Int], allowedBundleIdentifiers: [String]) async throws {
        let numberItems: [NSNumber] = allowedSystemItems.map { NSNumber(value: $0) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            bridge.activate(
                withAllowedSystemItems: numberItems,
                allowedBundleIdentifiers: allowedBundleIdentifiers
            ) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func invalidate() {
        bridge.invalidate()
    }
}

@MainActor
final class MenuBarClientCoreVisibilityApplier: MenuBarVisibilityApplying {
    private let bridge: PrivateMenuBarBridging
    private var hasActiveAssertion = false

    init(bridge: PrivateMenuBarBridging) {
        self.bridge = bridge
    }

    func applyCollapse(allowing items: MenuBarVisibleItems) async throws {
        guard bridge.isAvailable else {
            throw MenuBarIconHidingError.nativeAPIUnavailable
        }

        let systemItems = Array(Set(items.allowedSystemItemIdentifiers)).sorted()
        guard systemItems.allSatisfy({ MBSystemItemIdentifier(rawValue: $0) != nil }) else {
            throw MenuBarIconHidingError.nativeOperationFailed
        }
        let bundleIdentifiers = Array(Set(items.allowedBundleIdentifiers)).sorted()

        if hasActiveAssertion {
            bridge.invalidate()
            hasActiveAssertion = false
        }

        do {
            try await bridge.activate(
                allowedSystemItems: systemItems,
                allowedBundleIdentifiers: bundleIdentifiers
            )
            hasActiveAssertion = true
        } catch {
            hasActiveAssertion = false
            throw MenuBarIconHidingError.nativeOperationFailed
        }
    }

    func applyExpansion() async {
        guard hasActiveAssertion else { return }
        bridge.invalidate()
        hasActiveAssertion = false
    }

    func invalidateSynchronously() {
        bridge.invalidate()
        hasActiveAssertion = false
    }
}

@MainActor
final class LegacyMarkerVisibilityApplier: MenuBarVisibilityApplying {
    private let setCollapsed: @MainActor (Bool) -> Void

    init(setCollapsed: @escaping @MainActor (Bool) -> Void) {
        self.setCollapsed = setCollapsed
    }

    func applyCollapse(allowing items: MenuBarVisibleItems) async throws {
        setCollapsed(true)
    }

    func applyExpansion() async {
        setCollapsed(false)
    }
}
