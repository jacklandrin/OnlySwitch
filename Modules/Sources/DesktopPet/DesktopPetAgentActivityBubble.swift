import SwiftUI

struct DesktopPetAgentActivityBubble: View {
    let completion: DesktopPetAgentCompletion
    let onDismiss: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text(completion.agent.name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(completionDescription)
            Button(action: onDismiss) {
                Label(String(localized: "Dismiss notification", bundle: .main), systemImage: "xmark")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
            .padding(2)
        }
        .font(.caption)
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .padding(.vertical, 6)
        .frame(width: DesktopPetMetrics.agentStatusWidth, height: DesktopPetMetrics.agentStatusHeight - 8)
        .modifier(DesktopPetAgentBubbleBackground())
        .padding(.vertical, 4)
        .help(completionDescription)
        .accessibilityElement(children: .contain)
    }

    private var completionDescription: String {
        completion.agent.name + ": " + String(localized: "Agent task completed", bundle: .main)
    }
}

private struct DesktopPetAgentBubbleBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: DesktopPetSpeechBubbleShape())
        } else {
            content.background(.regularMaterial, in: DesktopPetSpeechBubbleShape())
        }
    }
}

private struct DesktopPetSpeechBubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let bubble = CGRect(x: rect.minX, y: rect.minY, width: rect.width - 8, height: rect.height)
        var path = RoundedRectangle(cornerRadius: 14).path(in: bubble)
        path.move(to: CGPoint(x: bubble.maxX, y: rect.midY - 7))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: bubble.maxX, y: rect.midY + 7))
        path.closeSubpath()
        return path
    }
}
