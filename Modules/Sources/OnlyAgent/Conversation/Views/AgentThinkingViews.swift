//
//  AgentThinkingViews.swift
//  Modules
//

import Extensions
import SwiftUI

@available(macOS 26.0, *)
struct ThinkingDotsView: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.4)) { timeline in
            let phase = Int(timeline.date.timeIntervalSinceReferenceDate * 2.5) % 4
            Text("Thinking".localized() + String(repeating: ".", count: phase))
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .frame(minWidth: 90, alignment: .leading)
        }
        .accessibilityLabel("Thinking".localized())
    }
}

/// Shows the tail of the model's streamed reasoning with a gentle typing reveal.
@available(macOS 26.0, *)
struct ThinkingTypingView: View {
    let text: String

    @State private var visibleCharacters = 0

    var body: some View {
        Text(String(text.suffix(240).prefix(visibleCharacters)))
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(3, reservesSpace: false)
            .frame(maxWidth: .infinity, alignment: .leading)
            .task(id: text) {
                let target = min(text.count, 240)
                if visibleCharacters > target { visibleCharacters = target }
                while visibleCharacters < target, !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(16))
                    let remaining = target - visibleCharacters
                    visibleCharacters = min(target, visibleCharacters + (remaining > 80 ? 4 : remaining > 24 ? 2 : 1))
                }
            }
            .accessibilityHidden(true)
    }
}

@available(macOS 26.0, *)
struct AgentThinkingRow: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ThinkingDotsView()
            if !text.isEmpty {
                ThinkingTypingView(text: text)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
    }
}
