import Extensions
import SwiftUI

/// A small capsule marking a newly added Settings page in the sidebar.
struct SettingsNewBadge: View {
    var body: some View {
        Text("Settings New Badge".localized())
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.gradient, in: .capsule)
            .fixedSize()
    }
}
