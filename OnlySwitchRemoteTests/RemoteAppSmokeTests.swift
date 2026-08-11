import ComposableArchitecture
import Foundation
import Testing
@testable import OnlySwitchRemote

@MainActor
struct RemoteAppSmokeTests {
    @Test func initialStateRequiresSetupWithoutPairedMacs() {
        let state = RemoteAppFeature.State(hasCompletedInitialSetup: false)
        #expect(state.requiresSetup)
        #expect(state.path.isEmpty)
        #expect(state.requiredSettings != nil)
    }

    @Test func reviewDemoWalkthroughDeclaresEveryReviewerScreen() {
        #expect(ReviewDemoScreen.allCases.count == 5)
        for screen in ReviewDemoScreen.allCases {
            switch screen {
            case .dashboard, .settings, .macManagement, .howToUse, .pairing:
                break
            }
        }
    }

    @Test func reviewDemoSettingsAndPresentedScreensArePopulated() async throws {
        let runtime = RemoteReviewDemoRuntime()
        let persistence = RemotePersistenceClient.reviewDemo(runtime: runtime)
        let studioID = RemoteReviewDemoRuntime.studioMacID
        let pairedMacs = try await persistence.loadPairedMacs()
        let studio = try #require(pairedMacs.first(where: { $0.id == studioID }))
        let layout = try #require(try await persistence.loadLayout(studioID))
        let catalog = try #require(try await persistence.loadCatalog(studioID))
        let state = SettingsFeature.State(
            isSetupRequired: false,
            pairedMacs: .init(uniqueElements: pairedMacs),
            selectedMacID: studioID,
            catalog: .init(uniqueElements: catalog.controls),
            catalogRevision: catalog.revision,
            selectedControlIDs: layout.selectedControlIDs,
            order: layout.order,
            connectionStatuses: [studioID: .connected]
        )
        let store = TestStore(initialState: state) {
            SettingsFeature()
        } withDependencies: {
            $0.remoteConnection = .reviewDemo(runtime: runtime)
            $0.remotePersistence = persistence
        }

        #expect(store.state.isSetupRequired == false)
        #expect(store.state.pairedMacs.map(\.displayName) == ["Studio", "Travel"])
        #expect(store.state.controls(kind: .builtIn).isEmpty == false)
        #expect(store.state.controls(kind: .shortcut).isEmpty == false)
        #expect(store.state.controls(kind: .evolution).isEmpty == false)

        await store.send(.manageMac(studioID)) {
            $0.management = .init(mac: studio, connectionStatus: .connected)
        }
        #expect(store.state.management?.mac.displayName == "Studio")

        await store.send(.pairAnotherTapped) {
            $0.pairing = .init()
        }
        #expect(store.state.pairing != nil)
    }
}
