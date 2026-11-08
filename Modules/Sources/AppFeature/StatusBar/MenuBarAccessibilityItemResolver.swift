//
//  MenuBarAccessibilityItemResolver.swift
//  OnlySwitch
//

import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation

struct AXMenuBarItemRecord: Hashable, Sendable {
    var midX: CGFloat
    var bundleIdentifier: String?
    var systemItemIdentifier: Int?
}

struct AXMenuBarItemTreeNode: Equatable, Sendable {
    var role: String
    var frame: CGRect?
    var bundleIdentifier: String?
    var systemItemIdentifier: Int?
    var children: [AXMenuBarItemTreeNode]
}

enum AXMenuBarRecordCollector {
    static func records(
        from windows: [AXMenuBarItemTreeNode],
        preferredDisplayBounds: CGRect
    ) throws -> [AXMenuBarItemRecord] {
        guard isUsable(preferredDisplayBounds),
              let window = windows.first(where: { node in
                  node.role == kAXWindowRole as String
                      && node.frame.map { isUsable($0) && $0.intersects(preferredDisplayBounds) } == true
                      && node.children.contains { $0.role == kAXGroupRole as String }
              })
        else {
            throw MenuBarIconHidingError.invalidMarkerPosition
        }

        return try window.children
            .filter { $0.role == kAXGroupRole as String }
            .map { group in
                guard let frame = group.frame, isUsable(frame) else {
                    throw MenuBarIconHidingError.nativeOperationFailed
                }

                let directApplicationBundle = group.children
                    .first { $0.role == kAXApplicationRole as String }
                    .flatMap(\.bundleIdentifier)
                let directButtonBundle = group.children
                    .first { $0.role == kAXButtonRole as String }
                    .flatMap(\.bundleIdentifier)
                let bundleIdentifier = nonempty(directApplicationBundle)
                    ?? nonempty(directButtonBundle)
                    ?? nonempty(group.bundleIdentifier)
                let systemItemIdentifier = bundleIdentifier == nil
                    ? directSystemItemIdentifier(in: group)
                    : nil

                return AXMenuBarItemRecord(
                    midX: frame.midX,
                    bundleIdentifier: bundleIdentifier,
                    systemItemIdentifier: systemItemIdentifier
                )
            }
    }

    private static func directSystemItemIdentifier(in group: AXMenuBarItemTreeNode) -> Int? {
        for childGroup in group.children where childGroup.role == kAXGroupRole as String {
            if let identifier = childGroup.children.first(where: {
                $0.role == kAXMenuBarItemRole as String
            })?.systemItemIdentifier {
                return identifier
            }
        }
        return nil
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value, value.isEmpty == false else { return nil }
        return value
    }

    private static func isUsable(_ frame: CGRect) -> Bool {
        frame.isNull == false
            && frame.isInfinite == false
            && frame.minX.isFinite
            && frame.minY.isFinite
            && frame.width.isFinite
            && frame.height.isFinite
            && frame.width > 0
            && frame.height > 0
    }
}

@MainActor
protocol AXMenuBarSource: AnyObject {
    var isTrusted: Bool { get }
    func visibleMenuBarItems() throws -> [AXMenuBarItemRecord]
}

@MainActor
final class AXMenuBarVisibleItemResolver: MenuBarVisibleItemResolving {
    private let markerScreenX: () -> CGFloat?
    private let mainItemScreenX: () -> CGFloat?
    private let ownBundleIdentifier: () -> String?
    private let runningBundleIdentifiers: () -> Set<String>
    private let source: AXMenuBarSource

    init(
        markerScreenX: @escaping () -> CGFloat?,
        mainItemScreenX: @escaping () -> CGFloat? = { nil },
        runningBundleIdentifiers: @escaping () -> Set<String> = {
            Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        },
        ownBundleIdentifier: @escaping () -> String?,
        source: AXMenuBarSource
    ) {
        self.markerScreenX = markerScreenX
        self.mainItemScreenX = mainItemScreenX
        self.runningBundleIdentifiers = runningBundleIdentifiers
        self.ownBundleIdentifier = ownBundleIdentifier
        self.source = source
    }

    func itemsToKeepVisible() throws -> MenuBarVisibleItems {
        guard let markerX = markerScreenX(), markerX.isFinite else {
            throw MenuBarIconHidingError.invalidMarkerPosition
        }
        guard let mainX = mainItemScreenX(), mainX.isFinite, mainX >= markerX else {
            throw MenuBarIconHidingError.invalidMarkerPosition
        }
        guard source.isTrusted else {
            throw MenuBarIconHidingError.accessibilityDenied
        }

        let items = try source.visibleMenuBarItems()
        let ownBundleIdentifiers = Set(
            [ownBundleIdentifier()].compactMap { $0 }.filter { $0.isEmpty == false }
        )
        let runningBundles = Set(
            runningBundleIdentifiers().filter { $0.isEmpty == false }
        )
        var leftBundleIdentifiers = Set<String>()
        var rightBundleIdentifiers = Set<String>()
        var systemItemIdentifiers = Set<Int>()

        for item in items where item.midX.isFinite {
            if let bundleIdentifier = item.bundleIdentifier, bundleIdentifier.isEmpty == false {
                if item.midX < markerX {
                    leftBundleIdentifiers.insert(bundleIdentifier)
                } else {
                    rightBundleIdentifiers.insert(bundleIdentifier)
                }
            }
            if item.midX >= markerX,
               let systemItemIdentifier = item.systemItemIdentifier,
               MBSystemItemIdentifier(rawValue: systemItemIdentifier) != nil {
                systemItemIdentifiers.insert(systemItemIdentifier)
            }
        }

        let leftOnlyBundleIdentifiers = leftBundleIdentifiers
            .subtracting(rightBundleIdentifiers)
            .subtracting(ownBundleIdentifiers)
        let allowedBundleIdentifiers = runningBundles
            .subtracting(leftOnlyBundleIdentifiers)
            .union(rightBundleIdentifiers)
            .union(ownBundleIdentifiers)

        return MenuBarVisibleItems(
            allowedBundleIdentifiers: allowedBundleIdentifiers.sorted(),
            allowedSystemItemIdentifiers: systemItemIdentifiers.sorted()
        )
    }
}

@MainActor
final class SystemAXMenuBarSource: AXMenuBarSource {
    private enum SystemItemKind {
        case battery
        case bluetooth
        case clock
        case displays
        case keyboard
        case volume
        case wifi
        case screenMirroring
        case primaryBento

        var identifier: MBSystemItemIdentifier {
            switch self {
            case .battery: .battery
            case .bluetooth: .bluetooth
            case .clock: .clock
            case .displays: .displays
            case .keyboard: .keyboard
            case .volume: .volume
            case .wifi: .wifi
            case .screenMirroring: .screenMirroring
            case .primaryBento: .primaryBento
            }
        }
    }

    private let preferredDisplayBounds: () -> CGRect

    init(preferredDisplayBounds: @escaping () -> CGRect = {
        CGDisplayBounds(CGMainDisplayID())
    }) {
        self.preferredDisplayBounds = preferredDisplayBounds
    }

    var isTrusted: Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func visibleMenuBarItems() throws -> [AXMenuBarItemRecord] {
        guard let menuBarAgent = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent")
            .first
        else {
            throw MenuBarIconHidingError.nativeOperationFailed
        }

        let application = AXUIElementCreateApplication(menuBarAgent.processIdentifier)
        guard let windows: [AXUIElement] = attribute(kAXWindowsAttribute, from: application) else {
            throw MenuBarIconHidingError.nativeOperationFailed
        }

        let displayBounds = preferredDisplayBounds()
        guard let selectedWindow = windows.first(where: { window in
            guard let windowFrame = frame(of: window) else { return false }
            return windowFrame.intersects(displayBounds)
        }) else {
            throw MenuBarIconHidingError.invalidMarkerPosition
        }

        return try AXMenuBarRecordCollector.records(
            from: [makeWindowNode(from: selectedWindow)],
            preferredDisplayBounds: displayBounds
        )
    }

    private func makeWindowNode(from window: AXUIElement) -> AXMenuBarItemTreeNode {
        let directGroups: [AXMenuBarItemTreeNode] = directChildren(of: window)
            .map(makeItemGroupNode)
        return AXMenuBarItemTreeNode(
            role: kAXWindowRole as String,
            frame: frame(of: window),
            bundleIdentifier: nil,
            systemItemIdentifier: nil,
            children: directGroups
        )
    }

    private func makeItemGroupNode(from group: AXUIElement) -> AXMenuBarItemTreeNode {
        let directChildElements = directChildren(of: group)
        let fallbackBundleIdentifier = directChildElements.lazy.compactMap {
            self.bundleIdentifier(for: $0)
        }.first
        let childNodes = directChildElements.compactMap { child -> AXMenuBarItemTreeNode? in
            let childRole = role(of: child)
            if childRole == kAXApplicationRole as String {
                return AXMenuBarItemTreeNode(
                    role: kAXApplicationRole as String,
                    frame: nil,
                    bundleIdentifier: bundleIdentifier(for: child),
                    systemItemIdentifier: nil,
                    children: []
                )
            }
            if childRole == kAXButtonRole as String {
                return AXMenuBarItemTreeNode(
                    role: kAXButtonRole as String,
                    frame: nil,
                    bundleIdentifier: bundleIdentifier(for: child),
                    systemItemIdentifier: nil,
                    children: []
                )
            }
            if childRole == kAXGroupRole as String {
                let menuBarItems = directChildren(of: child).compactMap { menuBarItem -> AXMenuBarItemTreeNode? in
                    guard role(of: menuBarItem) == kAXMenuBarItemRole as String else { return nil }
                    return AXMenuBarItemTreeNode(
                        role: kAXMenuBarItemRole as String,
                        frame: nil,
                        bundleIdentifier: nil,
                        systemItemIdentifier: systemItemKind(for: menuBarItem)?.identifier.rawValue,
                        children: []
                    )
                }
                return AXMenuBarItemTreeNode(
                    role: kAXGroupRole as String,
                    frame: nil,
                    bundleIdentifier: nil,
                    systemItemIdentifier: nil,
                    children: menuBarItems
                )
            }
            return nil
        }

        return AXMenuBarItemTreeNode(
            role: kAXGroupRole as String,
            frame: frame(of: group),
            bundleIdentifier: bundleIdentifier(for: group) ?? fallbackBundleIdentifier,
            systemItemIdentifier: nil,
            children: childNodes
        )
    }

    private func directChildren(of element: AXUIElement) -> [AXUIElement] {
        attribute(kAXChildrenAttribute, from: element) ?? []
    }

    private func role(of element: AXUIElement) -> String? {
        attribute(kAXRoleAttribute, from: element)
    }

    private func bundleIdentifier(for element: AXUIElement) -> String? {
        var processIdentifier: pid_t = 0
        guard AXUIElementGetPid(element, &processIdentifier) == .success,
              let bundleIdentifier = NSRunningApplication(processIdentifier: processIdentifier)?.bundleIdentifier,
              bundleIdentifier.isEmpty == false,
              bundleIdentifier != "com.apple.MenuBarAgent"
        else { return nil }
        return bundleIdentifier
    }

    private func systemItemKind(for element: AXUIElement) -> SystemItemKind? {
        let identifier: String? = attribute(kAXIdentifierAttribute, from: element)
        let title: String? = attribute(kAXTitleAttribute, from: element)
        let itemDescription: String? = attribute(kAXDescriptionAttribute, from: element)
        let value = [identifier, title, itemDescription]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")

        if value.contains("battery") { return .battery }
        if value.contains("bluetooth") { return .bluetooth }
        if value.contains("clock") || value.contains("datetime") { return .clock }
        if value.contains("display") && value.contains("mirroring") == false { return .displays }
        if value.contains("keyboard") || value.contains("textinput") || value.contains("inputmenu") {
            return .keyboard
        }
        if value.contains("volume") || value.contains("sound") { return .volume }
        if value.contains("wifi") || value.contains("airport") { return .wifi }
        if value.contains("screenmirroring") || value.contains("mirroring") { return .screenMirroring }
        if value.contains("controlcenter") || value.contains("bento") { return .primaryBento }
        return nil
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue: AXValue = attribute(kAXPositionAttribute, from: element),
              let sizeValue: AXValue = attribute(kAXSizeAttribute, from: element),
              AXValueGetType(positionValue) == .cgPoint,
              AXValueGetType(sizeValue) == .cgSize
        else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: position, size: size)
    }

    private func attribute<Value>(_ name: String, from element: AXUIElement) -> Value? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value as? Value
    }
}
