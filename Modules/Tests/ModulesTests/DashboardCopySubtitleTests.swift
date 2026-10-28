import ComposableArchitecture
import Foundation
import Testing
@testable import OnlyControl

@MainActor
struct DashboardCopySubtitleTests {
    private func item(subtitle: String? = "100.20.30.40", copyable: Bool = true) -> ControlItemViewState {
        var item = ControlItemViewState(id: "tailscale", title: "Tailscale", subtitle: subtitle, iconData: Data(), controlType: .Switch, status: true, weight: 4)
        item.copyableSubtitle = copyable
        return item
    }

    @Test func copySubtitleEmitsOnlyItsDelegateAndPreservesTheTile() async {
        let initial = DashboardReducer.State(items: [item()])
        let store = TestStore(initialState: initial) { DashboardReducer() }
        await store.send(.copySubtitle("tailscale"))
        await store.receive(.delegate(.copySubtitle("tailscale")))
        #expect(store.state == initial)
        await store.finish()
    }

    @Test func repeatedCopyDoesNotToggleOrReorder() async {
        let initial = DashboardReducer.State(items: [item()])
        let store = TestStore(initialState: initial) { DashboardReducer() }
        for _ in 0..<2 {
            await store.send(.copySubtitle("tailscale"))
            await store.receive(.delegate(.copySubtitle("tailscale")))
        }
        #expect(store.state == initial)
        await store.finish()
    }

    @Test func unknownIDDoesNotEmitAnyDelegate() async {
        let store = TestStore(initialState: DashboardReducer.State(items: [item()])) { DashboardReducer() }
        await store.send(.copySubtitle("missing"))
        await store.finish()
    }

    @Test(arguments: [nil, "", "   "] as [String?])
    func absentSubtitleDoesNotEmitAnyDelegate(subtitle: String?) async {
        let store = TestStore(initialState: DashboardReducer.State(items: [item(subtitle: subtitle)])) { DashboardReducer() }
        await store.send(.copySubtitle("tailscale"))
        await store.finish()
    }

    @Test func noncopyableSubtitleDoesNotEmitAnyDelegate() async {
        let store = TestStore(initialState: DashboardReducer.State(items: [item(copyable: false)])) { DashboardReducer() }
        await store.send(.copySubtitle("tailscale"))
        await store.finish()
    }

    @Test func existingTilesDefaultToNoCopyCapability() {
        let existing = ControlItemViewState(id: "existing", title: "Existing", subtitle: "description", iconData: Data(), controlType: .Switch)
        #expect(!existing.copyableSubtitle)
    }
}
