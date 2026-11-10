//
//  ScriptCodeEditor.swift
//  Modules
//

import AppKit
import SwiftUI

/// A plain-text script editor with shell/AppleScript syntax highlighting.
///
/// Smart quotes, dashes, text replacement and spelling correction are off:
/// they silently turn `"` into `“` and break scripts. The bound text is only
/// replaced when it differs, so line endings (including `\r\n`) are kept.
public struct ScriptCodeEditor: View {
    @Binding private var text: String
    private let language: ScriptLanguage
    private let placeholder: String
    private let accessibilityLabel: String

    public init(
        text: Binding<String>,
        language: ScriptLanguage,
        placeholder: String = "",
        accessibilityLabel: String
    ) {
        _text = text
        self.language = language
        self.placeholder = placeholder
        self.accessibilityLabel = accessibilityLabel
    }

    public var body: some View {
        ScriptTextView(text: $text, language: language, accessibilityLabel: accessibilityLabel)
            .overlay(alignment: .topLeading) {
                if text.isEmpty, !placeholder.isEmpty {
                    Text(placeholder)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }
}

private struct ScriptTextView: NSViewRepresentable {
    @Binding var text: String
    let language: ScriptLanguage
    let accessibilityLabel: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, language: language)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.drawsBackground = false
        textView.font = ScriptHighlightTheme.font
        textView.typingAttributes = [.font: ScriptHighlightTheme.font, .foregroundColor: NSColor.textColor]
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.setAccessibilityLabel(accessibilityLabel)
        textView.string = text
        context.coordinator.highlight(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let coordinator = context.coordinator
        coordinator.text = $text
        textView.setAccessibilityLabel(accessibilityLabel)
        var needsHighlight = false
        if textView.string != text {
            textView.string = text
            needsHighlight = true
        }
        if coordinator.language != language {
            coordinator.language = language
            needsHighlight = true
        }
        if needsHighlight {
            coordinator.highlight(textView)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var language: ScriptLanguage

        init(text: Binding<String>, language: ScriptLanguage) {
            self.text = text
            self.language = language
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            highlight(textView)
            text.wrappedValue = textView.string
        }

        func highlight(_ textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let full = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.addAttribute(.font, value: ScriptHighlightTheme.font, range: full)
            storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: full)
            for token in ScriptTokenizer.tokens(in: storage.string, language: language)
            where NSMaxRange(token.range) <= storage.length {
                storage.addAttribute(
                    .foregroundColor,
                    value: ScriptHighlightTheme.color(for: token.kind),
                    range: token.range
                )
            }
            storage.endEditing()
        }
    }
}

#Preview {
    ScriptCodeEditor(
        text: .constant("if [ \"$HOME\" ]; then\n  echo 'hi' # greet\nfi"),
        language: .shell,
        accessibilityLabel: "Script"
    )
    .frame(width: 360, height: 120)
}
