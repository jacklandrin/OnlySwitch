import SwiftUI

struct DesktopPetInteractionShape: Shape {
    let size: CGSize

    func path(in rect: CGRect) -> Path {
        Path(
            CGRect(
                x: rect.midX - size.width / 2,
                y: rect.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
        )
    }
}
