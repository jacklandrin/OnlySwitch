import DesktopPet
import DesktopPetSkinKit
import SwiftUI

/// A small live preview of a pet: the built-in one when `skin` is nil, otherwise the skin.
struct DesktopPetSkinPreviewTile: View {
    static let tileSize = CGSize(width: 64, height: 70)
    private static let builtInCanvas = CGSize(width: 152, height: 160)
    private static let skinCanvas = CGSize(width: 120, height: 130)

    let skin: DesktopPetSkin?
    let isAnimating: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let canvas = skin == nil ? Self.builtInCanvas : Self.skinCanvas
        let scale = min(Self.tileSize.width / canvas.width, Self.tileSize.height / canvas.height)
        ZStack {
            if let skin {
                DesktopPetSkinWebView(
                    skin: skin,
                    state: DesktopPetAnimationState(),
                    reduceMotion: reduceMotion,
                    isPaused: !isAnimating
                )
                .frame(width: canvas.width, height: canvas.height)
            } else {
                DesktopPetView(isActive: isAnimating)
                    .frame(width: canvas.width, height: canvas.height)
            }
        }
        .scaleEffect(scale)
        .frame(width: Self.tileSize.width, height: Self.tileSize.height)
        .clipShape(.rect(cornerRadius: 10))
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
