import ComposableArchitecture
import Foundation
import RemoteCore

extension AlertState where Action == DashboardFeature.Action.Alert {
    static func confirmDestructive(
        controlID: RemoteControlID,
        controlTitle: String,
        macName: String
    ) -> Self {
        AlertState {
            TextState(String(localized: "Run \(controlTitle)?"))
        } actions: {
            ButtonState(role: .destructive, action: .confirmDestructive(controlID)) {
                TextState("Run")
            }
            ButtonState(role: .cancel) { TextState("Cancel") }
        } message: {
            TextState(String(localized: "This will run \(controlTitle) on \(macName)."))
        }
    }

    static func actionFailed(message: String) -> Self {
        AlertState {
            TextState("Action Failed")
        } actions: {
            ButtonState(role: .cancel) { TextState("OK") }
        } message: {
            TextState(message)
        }
    }


    static func actionTimedOut(controlID: RemoteControlID, destructive: Bool) -> Self {
        AlertState {
            TextState(destructive ? "Outcome Unknown" : "Action Timed Out")
        } actions: {
            ButtonState(action: .retryTimedOut(controlID)) { TextState("Retry") }
            ButtonState(role: .cancel, action: .cancelTimedOut(controlID)) { TextState("Cancel") }
        } message: {
            TextState(destructive
                ? "The Mac may already have completed this action. Retrying sends the same request so OnlySwitch can safely deduplicate it."
                : "The Mac did not respond. Retry the same request?")
        }
    }
}
