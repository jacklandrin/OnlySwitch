//
//  ScheduleClients+App.swift
//  OnlySwitch
//

import AppKit
import Foundation
import RemoteCore
import Scheduler
import UserNotifications

extension ScheduleExecutorClient {
    /// Runs schedules through the same validated path as OnlyRemote: the live catalog offers the targets
    /// and `RemoteCommandRouter` executes built-ins, Evolutions and Shortcuts.
    @MainActor
    static let app: Self = {
        let router = RemoteCommandRouter.live
        let provider = RemoteCatalogProvider.live
        return Self(
            catalog: { (try? await provider.catalog()) ?? [] },
            run: { id, action in
                let response = await router.perform(
                    RemoteActionRequest(requestID: UUID(), controlID: id, action: action.remoteAction)
                )
                switch response.result {
                case .success: return .succeeded
                case let .failure(error): return .failed(error.message)
                }
            }
        )
    }()
}

extension ScheduleNotificationClient {
    static let app = Self(
        requestAuthorization: {
            (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        },
        post: { title, body in
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            try? await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            )
        }
    )
}

extension ScheduleSystemEventsClient {
    /// Wake, clock and time-zone changes; observers are removed when the stream terminates.
    static let app = Self(events: {
        AsyncStream { continuation in
            let registration = ScheduleSystemEventObservers(
                workspaceCenter: NSWorkspace.shared.notificationCenter,
                defaultCenter: .default
            ) {
                continuation.yield()
            }
            continuation.onTermination = { _ in
                registration.remove()
            }
        }
    })
}

/// Owns the notification observer tokens for one events stream. The tokens are only read again in
/// `remove()`, which `NotificationCenter` allows from any thread, and the lock makes removal idempotent.
private final class ScheduleSystemEventObservers: @unchecked Sendable {
    private let workspaceCenter: NotificationCenter
    private let defaultCenter: NotificationCenter
    private let lock = NSLock()
    private var workspaceTokens: [NSObjectProtocol]
    private var defaultTokens: [NSObjectProtocol]

    init(
        workspaceCenter: NotificationCenter,
        defaultCenter: NotificationCenter,
        onEvent: @escaping @Sendable () -> Void
    ) {
        self.workspaceCenter = workspaceCenter
        self.defaultCenter = defaultCenter
        workspaceTokens = [
            workspaceCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { _ in onEvent() },
        ]
        defaultTokens = [
            defaultCenter.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: nil) { _ in onEvent() },
            defaultCenter.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: nil) { _ in onEvent() },
        ]
    }

    func remove() {
        lock.lock()
        let workspace = workspaceTokens
        let standard = defaultTokens
        workspaceTokens = []
        defaultTokens = []
        lock.unlock()
        for token in workspace { workspaceCenter.removeObserver(token) }
        for token in standard { defaultCenter.removeObserver(token) }
    }
}
