import ComposableArchitecture
import Foundation
import Testing
@testable import OnlySwitchRemote

@MainActor
struct MacManagementFeatureTests {
    private let studio = PairedMac(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000911")!,
        displayName: "Studio",
        lastEndpointDescription: "studio.local",
        lastConnectedAt: Date(timeIntervalSince1970: 1_000),
        requiresPairing: false
    )

    @Test func forgetRequiresConfirmationAndMutatesOnlyAfterStorageSucceeds() async {
        let recorder = ForgetRecorder()
        let store = TestStore(initialState: MacManagementFeature.State(mac: studio)) {
            MacManagementFeature()
        } withDependencies: {
            $0.remotePersistence.forgetMac = { try await recorder.forget($0) }
        }

        await store.send(.forgetTapped) { $0.isForgetConfirmationPresented = true }
        await store.send(.confirmForgetTapped) {
            $0.isForgetConfirmationPresented = false; $0.isForgetting = true; $0.issue = nil
        }
        #expect(store.state.mac == studio)
        await store.receive(.forgetResponse(.success)) { $0.isForgetting = false }
        await store.receive(.delegate(.forgotten(studio.id)))
        #expect(await recorder.ids == [studio.id])
    }

    @Test func partialForgetFailureKeepsMacAndCanRetry() async {
        let recorder = ForgetRecorder(failFirst: true)
        let store = TestStore(initialState: MacManagementFeature.State(mac: studio)) {
            MacManagementFeature()
        } withDependencies: {
            $0.remotePersistence.forgetMac = { try await recorder.forget($0) }
        }

        await store.send(.confirmForgetTapped) { $0.isForgetting = true; $0.issue = nil }
        await store.receive(.forgetResponse(.failure)) { $0.isForgetting = false; $0.issue = .forgetFailed }
        await store.send(.retryForgetTapped) { $0.isForgetting = true; $0.issue = nil }
        await store.receive(.forgetResponse(.success)) { $0.isForgetting = false }
        await store.receive(.delegate(.forgotten(studio.id)))
        #expect(await recorder.ids == [studio.id, studio.id])
    }

    @Test func rePairDelegatesWithoutForgetting() async {
        let store = TestStore(initialState: MacManagementFeature.State(mac: studio)) { MacManagementFeature() }
        await store.send(.rePairTapped)
        await store.receive(.delegate(.rePair(studio.id)))
    }
}

private actor ForgetRecorder {
    private(set) var ids: [UUID] = []
    private var failFirst: Bool
    init(failFirst: Bool = false) { self.failFirst = failFirst }
    func forget(_ id: UUID) throws {
        ids.append(id)
        if failFirst { failFirst = false; throw MacManagementTestError.failed }
    }
}

private enum MacManagementTestError: Error { case failed }
