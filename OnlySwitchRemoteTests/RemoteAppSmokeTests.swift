import ComposableArchitecture
import Foundation
import RemoteCore
import SwiftUI
import Testing
@testable import OnlySwitchRemote

@MainActor
struct RemoteAppSmokeTests {
    @Test func initialStateRequiresSetupWithoutPairedMacs() {
        let state = RemoteAppFeature.State(hasCompletedInitialSetup: false)
        #expect(state.requiresSetup)
        #expect(state.path.isEmpty)
        #expect(state.requiredGlobalSettings != nil)
    }

    @Test func screenshotsViewRendersEveryState() {
        let item = RemoteScreenshotItem(
            id: UUID(),
            fileName: "a.png",
            contentType: "public.png",
            createdAt: .now,
            isPinned: true,
            revision: 0,
            byteCount: 3
        )
        var empty = RemoteScreenshotsFeature.State()
        empty.selectedMacID = UUID()
        empty.connectionState = .authenticated
        empty.library = .init(revision: 1, isCollectionEnabled: false, items: [])
        var populated = empty
        populated.library = .init(revision: 2, isCollectionEnabled: true, items: [item])
        populated.isStreaming = true
        populated.hasLiveLibrary = true
        var offline = populated
        offline.connectionState = .offline(nil)
        offline.isStreaming = false
        offline.hasLiveLibrary = false
        var upgrade = empty
        upgrade.library = nil
        upgrade.availabilityMessage = "This Mac needs a newer OnlySwitch version to use Screenshots."
        var connecting = empty
        connecting.library = nil
        var busy = populated
        busy.downloadingItemIDs = [item.id]
        busy.loadingThumbnailIDs = [item.id]
        busy.copiedItemID = item.id
        busy.pendingDeleteItemID = item.id
        busy.operationError = "The screenshot could not be copied."
        var detail = offline
        detail.selectedItemID = item.id
        let states = [RemoteScreenshotsFeature.State(), empty, populated, offline, upgrade, connecting, busy, detail]
        for state in states {
            let store = Store(initialState: state) { RemoteScreenshotsFeature() }
            let grid = UIHostingController(rootView: RemoteScreenshotsView(store: store))
            grid.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            grid.view.layoutIfNeeded()
            let viewer = UIHostingController(rootView: RemoteScreenshotDetailView(store: store))
            viewer.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            viewer.view.layoutIfNeeded()
        }
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

        #expect(store.state.pairedMacs.map(\.displayName) == ["Studio", "Travel"])
        #expect(store.state.controls(kind: .builtIn).isEmpty == false)
        #expect(store.state.controls(kind: .shortcut).isEmpty == false)
        #expect(store.state.controls(kind: .evolution).isEmpty == false)

        let globalStore = TestStore(initialState: GlobalSettingsFeature.State(
            pairedMacs: .init(uniqueElements: pairedMacs),
            selectedMacID: studioID,
            connectionStatuses: [studioID: .connected]
        )) {
            GlobalSettingsFeature()
        }
        await globalStore.send(.manageMac(studioID)) {
            $0.management = .init(mac: studio, connectionStatus: .connected)
        }
        #expect(globalStore.state.management?.mac.displayName == "Studio")
        await globalStore.send(.pairNewMacTapped) { $0.pairing = .init() }
        #expect(globalStore.state.pairing != nil)
    }
}
