import SwiftUI

#if os(macOS)
@available(macOS 26.0, *)
struct AphroditeFittedPreview: View {
    let html: String
    @State private var contentSize = CGSize(width: 640, height: 240)

    var body: some View {
        GeometryReader { proxy in
            if let layout = AphroditeEditorPreviewScalePolicy.layout(content: contentSize, available: proxy.size) {
                Color.clear
                    .frame(width: layout.displayedSize.width, height: layout.displayedSize.height)
                    .overlay(alignment: .topLeading) {
                        SecureAphroditeWebView(html: html, onContentSizeChange: { contentSize = $0 })
                            .frame(width: layout.logicalSize.width, height: layout.logicalSize.height)
                            .scaleEffect(layout.scale, anchor: .topLeading)
                    }
                    .clipped()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .onChange(of: html) { contentSize = CGSize(width: 640, height: 240) }
    }
}
#endif
