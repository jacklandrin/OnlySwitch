import ComposableArchitecture
import SwiftUI

@available(macOS 14.0, *)
public struct CodexUsagePanelContainer: View {
    @State private var store: StoreOf<CodexUsageReducer>

    public init() {
        _store = State(initialValue: Store(initialState: CodexUsageReducer.State()) {
            CodexUsageReducer()
        })
    }

    public var body: some View {
        CodexUsageView(store: store)
    }
}
