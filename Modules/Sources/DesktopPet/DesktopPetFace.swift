import SwiftUI

/// The pet's eyes: upright capsules normally, closed happy arcs while eating or being petted.
struct DesktopPetFace: View {
    let isHappy: Bool
    let eyeScale: Double

    var body: some View {
        HStack(spacing: 5) {
            eye
            eye
        }
    }

    @ViewBuilder
    private var eye: some View {
        if isHappy {
            DesktopPetHappyEye()
                .stroke(Color(red: 0.04, green: 0.17, blue: 0.32), style: .init(lineWidth: 2, lineCap: .round))
                .frame(width: 7, height: 5)
        } else {
            Capsule()
                .fill(Color(red: 0.04, green: 0.17, blue: 0.32))
                .frame(width: 4, height: 10)
                .scaleEffect(x: 1, y: eyeScale)
        }
    }
}
