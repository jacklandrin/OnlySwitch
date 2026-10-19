import ComposableArchitecture
import SwiftUI

@available(macOS 14.0, *)
public struct ClaudeUsagePanelContainer: View {
    @State private var store: StoreOf<ClaudeUsageReducer>
    private let managesScrolling: Bool
    public init(managesScrolling: Bool = true) {
        self.managesScrolling = managesScrolling
        _store = State(initialValue: Store(initialState: ClaudeUsageReducer.State()) { ClaudeUsageReducer() })
    }
    public var body: some View { ClaudeUsageView(store: store, managesScrolling: managesScrolling) }
}
