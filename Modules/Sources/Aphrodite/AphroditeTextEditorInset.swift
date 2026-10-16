import SwiftUI

#if os(macOS)
@_spi(Advanced) import SwiftUIIntrospect

extension View {
    func aphroditeTextEditorInset() -> some View {
        introspect(.textEditor, on: .macOS(.v26...)) { textView in
            let current = textView.textContainerInset
            let desired = CGSize(width: current.width, height: max(current.height, 8))
            guard current != desired else { return }
            textView.textContainerInset = desired
        }
    }
}
#else
extension View {
    func aphroditeTextEditorInset() -> some View { self }
}
#endif
