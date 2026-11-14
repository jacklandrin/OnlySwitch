import ComposableArchitecture
import Defines
import Foundation

/// Tells the running desktop pet to re-read the selected skin.
struct DesktopPetSkinNotifier: Sendable {
    static func live(notificationCenter: NotificationCenter = .default) -> @Sendable () -> Void {
        // `NotificationCenter` is documented as thread-safe but is not declared `Sendable`.
        let center = UncheckedSendable(notificationCenter)
        return {
            // The observer (`AppDelegate`) is main-actor isolated and notifications are delivered
            // on the posting thread, so always post from the main actor.
            Task { @MainActor in
                center.value.post(name: .desktopPetSkinChanged, object: nil)
            }
        }
    }
}

private enum DesktopPetSkinNotifierKey: DependencyKey {
    static let liveValue: @Sendable () -> Void = DesktopPetSkinNotifier.live()
    static let testValue: @Sendable () -> Void = unimplemented("desktopPetSkinNotifier")
}

extension DependencyValues {
    var desktopPetSkinNotifier: @Sendable () -> Void {
        get { self[DesktopPetSkinNotifierKey.self] }
        set { self[DesktopPetSkinNotifierKey.self] = newValue }
    }
}
