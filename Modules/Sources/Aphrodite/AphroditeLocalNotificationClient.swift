import ComposableArchitecture
import Foundation
import UserNotifications

public struct AphroditeCompletionNotification: Equatable, Sendable {
    public let identifier: String
    public let title: String
    public let body: String

    public init(identifier: String, title: String, body: String) {
        self.identifier = identifier
        self.title = title
        self.body = body
    }
}

@DependencyClient
public struct AphroditeLocalNotificationClient: Sendable {
    public var requestAuthorization: @Sendable () async throws -> Bool
    public var deliver: @Sendable (AphroditeCompletionNotification) async throws -> Void
}

extension AphroditeLocalNotificationClient: DependencyKey {
    public static let liveValue = Self(
        requestAuthorization: {
            try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        },
        deliver: { notification in
            let content = UNMutableNotificationContent()
            content.title = notification.title
            content.body = notification.body
            content.sound = .default
            try await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: notification.identifier, content: content, trigger: nil)
            )
        }
    )

    public static let testValue = Self(
        requestAuthorization: { true },
        deliver: { _ in }
    )
}

public extension DependencyValues {
    var aphroditeLocalNotification: AphroditeLocalNotificationClient {
        get { self[AphroditeLocalNotificationClient.self] }
        set { self[AphroditeLocalNotificationClient.self] = newValue }
    }
}
