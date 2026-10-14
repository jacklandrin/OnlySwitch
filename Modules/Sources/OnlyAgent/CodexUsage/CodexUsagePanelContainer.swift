import ComposableArchitecture
import SwiftUI

@available(macOS 14.0, *)
public struct CodexUsagePanelContainer: View {
    @State private var store: StoreOf<CodexUsageReducer>
    private let managesScrolling: Bool

    public init(managesScrolling: Bool = true) {
        self.managesScrolling = managesScrolling
        _store = State(initialValue: Store(initialState: CodexUsageReducer.State()) {
            CodexUsageReducer()
        })
    }

    public var body: some View {
        CodexUsageView(store: store, managesScrolling: managesScrolling)
    }
}
