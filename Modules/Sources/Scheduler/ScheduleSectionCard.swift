import SwiftUI

/// A numbered editor section, styled after Lingon's ① ② ③ layout.
struct ScheduleSectionCard<Content: View>: View {
    let number: Int
    var title: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "\(number).circle.fill")
                    .font(.title2)
                    .foregroundStyle(.primary)
                    .accessibilityHidden(true)
                if let title {
                    Text(title)
                        .font(.title3.bold())
                        .accessibilityAddTraits(.isHeader)
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .scheduleCard()
    }
}
