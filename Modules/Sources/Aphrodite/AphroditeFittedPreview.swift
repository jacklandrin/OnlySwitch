import SwiftUI

#if os(macOS)
@available(macOS 26.0, *)
struct AphroditeFittedPreview: View {
    let app: AphroditeApp
    @State private var contentSize = CGSize(width: 640, height: 240)

    var body: some View {
        GeometryReader { proxy in
            if let layout = AphroditeEditorPreviewScalePolicy.layout(content: contentSize, available: proxy.size) {
                Color.clear
                    .frame(width: layout.displayedSize.width, height: layout.displayedSize.height)
                    .overlay(alignment: .topLeading) {
                        SecureAphroditeWebView(app: app, onContentSizeChange: { contentSize = $0 })
                            .frame(width: layout.logicalSize.width, height: layout.logicalSize.height)
                            .scaleEffect(layout.scale, anchor: .topLeading)
                    }
                    .clipped()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .onChange(of: app.html) { contentSize = CGSize(width: 640, height: 240) }
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
#endif
