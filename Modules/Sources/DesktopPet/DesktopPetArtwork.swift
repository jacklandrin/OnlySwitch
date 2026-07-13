import SwiftUI

struct DesktopPetArtwork: View {
    let verticalOffset: Double
    let eyeScale: Double
    let sliderOffset: Double
    let isControlPresented: Bool
    let isDragging: Bool
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            Ellipse()
                .fill(.black.opacity(0.18))
                .frame(width: 72, height: 12)
                .blur(radius: 4)
                .offset(y: 54)

            Capsule()
                .fill(.linearGradient(
                    colors: [.indigo.opacity(0.9), .blue],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .frame(width: 19, height: 38)
                .rotationEffect(.degrees(22))
                .offset(x: -48, y: 10)

            Capsule()
                .fill(.linearGradient(
                    colors: [.indigo.opacity(0.9), .blue],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .frame(width: 19, height: 38)
                .rotationEffect(.degrees(-22))
                .offset(x: 48, y: 10)

            Capsule()
                .fill(.indigo)
                .frame(width: 24, height: 34)
                .offset(x: -24, y: 46)

            Capsule()
                .fill(.indigo)
                .frame(width: 24, height: 34)
                .offset(x: 24, y: 46)

            RoundedRectangle(cornerRadius: 35)
                .fill(.linearGradient(
                    colors: isControlPresented
                        ? [Color(red: 0.31, green: 0.9, blue: 0.83), .blue]
                        : [Color(red: 0.42, green: 0.64, blue: 1), .indigo],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .stroke(.white.opacity(0.45), lineWidth: 2)
                .frame(width: 108, height: 88)
                .shadow(
                    color: (isControlPresented ? Color.cyan : .blue).opacity(0.45),
                    radius: isControlPresented ? 14 : 10,
                    y: 5
                )

            Capsule()
                .fill(Color(red: 0.07, green: 0.12, blue: 0.28))
                .stroke(.white.opacity(0.16), lineWidth: 1.5)
                .frame(width: 86, height: 48)

            Circle()
                .fill(.linearGradient(
                    colors: [Color(red: 0.42, green: 0.95, blue: 1), .blue],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 38, height: 38)
                .shadow(color: .cyan.opacity(0.6), radius: 5)
                .offset(x: (isControlPresented ? 20 : -20) + sliderOffset)

            HStack(spacing: 5) {
                Capsule()
                    .fill(Color(red: 0.04, green: 0.17, blue: 0.32))
                    .frame(width: 4, height: 10)
                Capsule()
                    .fill(Color(red: 0.04, green: 0.17, blue: 0.32))
                    .frame(width: 4, height: 10)
            }
            .scaleEffect(x: 1, y: eyeScale)
            .offset(x: (isControlPresented ? 20 : -20) + sliderOffset)

            Circle()
                .stroke(.mint, lineWidth: 3)
                .frame(width: 13, height: 13)
                .opacity(isControlPresented ? 1 : 0)
                .offset(x: -23)

            Capsule()
                .fill(.cyan.opacity(0.75))
                .frame(width: 16, height: 4)
                .opacity(isControlPresented ? 0 : 1)
                .offset(x: 24)

            Circle()
                .fill(.white.opacity(0.58))
                .frame(width: 9, height: 9)
                .blur(radius: 1)
                .offset(x: -31, y: -29)
        }
        .scaleEffect(isDragging ? 1.04 : 1)
        .offset(y: verticalOffset)
        .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: isDragging)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: isControlPresented)
    }
}
