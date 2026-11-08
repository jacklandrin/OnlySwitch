import ComposableArchitecture
import Foundation
import RemoteCore

extension DashboardFeature {
    func startAction(
        _ id: RemoteControlID,
        descriptor: RemoteControlDescriptor,
        state: inout State
    ) -> Effect<Action> {
        state.actionFailures[id] = nil
        let action: RemoteControlAction
        switch descriptor.behavior {
        case .button:
            action = .trigger
        case .switch, .player:
            action = .setState(!(state.statuses[id]?.value.isOn ?? false))
        }
        guard let macID = state.selectedMacID, let sessionID = state.activeSessionID else { return .none }
        let request = RemoteActionRequest(requestID: uuid(), controlID: id, action: action)
        return sendAction(
            id,
            invocation: .init(macID: macID, sessionID: sessionID, request: request),
            state: &state
        )
    }

    func sendAction(
        _ id: RemoteControlID,
        invocation: RemoteActionInvocation,
        state: inout State
    ) -> Effect<Action> {
        state.actionFailures[id] = nil
        state.requestsInFlight.insert(id)
        state.requestIDs[id] = invocation.request.requestID
        return .run { [connection] send in
            do {
                await send(.actionResponse(
                    id,
                    invocation.request.requestID,
                    .success(try await connection.send(invocation))
                ))
            } catch let error as RemoteProtocolError {
                if error.code == .requestTimedOut {
                    await send(.actionCompleted(id, invocation, .failure(error)))
                } else {
                    await send(.actionResponse(id, invocation.request.requestID, .failure(error)))
                }
            } catch is CancellationError {
                return
            } catch {
                await send(.actionResponse(id, invocation.request.requestID, .failure(.init(
                    code: .executionFailed,
                    message: String(localized: "The Mac could not complete this action.")
                ))))
            }
        }
        .cancellable(id: CancelID.action(id), cancelInFlight: true)
    }

    func handleActionResponse(
        id: RemoteControlID,
        requestID: UUID,
        response: Result<RemoteActionResult, RemoteProtocolError>,
        state: inout State
    ) -> Effect<Action> {
        guard state.requestIDs[id] == requestID else { return .none }
        switch response {
        case let .failure(error):
            state.requestsInFlight.remove(id)
            state.requestIDs[id] = nil
            state.actionFailures[id] = error.message
            state.alert = .actionFailed(message: error.message)
        case let .success(result):
            guard result.requestID == requestID else { return .none }
            state.requestsInFlight.remove(id)
            state.requestIDs[id] = nil
            switch result.result {
            case let .failure(error):
                state.actionFailures[id] = error.message
                state.alert = .actionFailed(message: error.message)
            case let .success(status):
                if let status { apply(status, to: &state) }
            }
        }
        return .none
    }
}
