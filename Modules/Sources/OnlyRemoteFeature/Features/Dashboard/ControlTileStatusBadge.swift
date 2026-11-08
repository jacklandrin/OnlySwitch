import SwiftUI

struct ControlTileStatusBadge: View {
    let presentation: ControlTilePresentation
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbolName)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(
                    .pulse,
                    options: .repeating,
                    isActive: presentation.visualState == .pending && reduceMotion == false
                )
            Text(title)
        }
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.14), in: .capsule)
        .overlay {
            Capsule()
                .strokeBorder(tint.opacity(0.24))
        }
        .animation(presentationAnimation, value: presentation.visualState)
        .accessibilityHidden(true)
    }

    private var title: LocalizedStringKey {
        switch presentation.visualState {
        case .on:
            "On"
        case .off:
            "Off"
        case .ready:
            "Run"
        case .pending:
            "Working"
        case .stale:
            "Last known status"
        case .offline:
            "Offline"
        case .unavailable:
            "Unavailable on this Mac"
        case .failed:
            "Action Failed"
        }
    }

    private var symbolName: String {
        switch presentation.visualState {
        case .on:
            "checkmark.circle.fill"
        case .off:
            "power"
        case .ready:
            "bolt.fill"
        case .pending:
            "arrow.triangle.2.circlepath"
        case .stale:
            "clock.arrow.circlepath"
        case .offline:
            "wifi.slash"
        case .unavailable:
            "exclamationmark.circle"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch presentation.visualState {
        case .on:
            .green
        case .pending:
            .accentColor
        case .off, .ready, .stale:
            .secondary
        case .offline:
            .orange
        case .unavailable, .failed:
            .red
        }
    }

    private var presentationAnimation: Animation? {
        guard reduceMotion == false else { return nil }
        switch presentation.visualState {
        case .on, .off, .ready:
            return .snappy(duration: 0.28)
        case .pending, .stale, .offline, .unavailable, .failed:
            return nil
        }
    }
}
