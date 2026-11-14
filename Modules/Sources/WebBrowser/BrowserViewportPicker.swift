import ComposableArchitecture
import SwiftUI

struct BrowserViewportPicker: View {
    let store: StoreOf<BrowserFeature>

    var body: some View {
        Picker(BrowserStrings.text("Browser Page Size"), selection: Binding(
            get: { store.viewportSize },
            set: { store.send(.viewportSizeChanged($0)) }
        )) {
            ForEach(BrowserViewportSize.allCases, id: \.self) { size in
                Text(verbatim: size.label).tag(size)
            }
        }
    }
}
