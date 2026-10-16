#!/usr/bin/env python3
"""Exercise Aphrodite's production TextEditor inset modifier in a native grouped Form.

Run on macOS with Xcode: rtk proxy python3 Scripts/test_aphrodite_text_editor_inset.py
The probe attaches a hosting view to an NSWindow because SwiftUIIntrospect's
callback runs only after native view attachment. It checks the production
modifier's 8-point text inset and first-line visible coordinate at 80 and 100
point editor heights. No network or persisted app data is used.
"""

from pathlib import Path
import subprocess
import tempfile


HARNESS = r'''
import AppKit
import SwiftUI

struct Probe: View {
    @State private var text = "Ágj first line"
    let height: CGFloat
    var body: some View {
        Form { TextEditor(text: $text).aphroditeTextEditorInset().frame(minHeight: height) }
            .formStyle(.grouped)
            .frame(width: 360, height: height + 80)
    }
}

@MainActor func textView(in view: NSView) -> NSTextView? {
    if let text = view as? NSTextView { return text }
    for child in view.subviews { if let found = textView(in: child) { return found } }
    return nil
}

@MainActor func check(height: CGFloat) {
    let host = NSHostingView(rootView: Probe(height: height))
    host.frame = NSRect(x: 0, y: 0, width: 360, height: height + 80)
    let window = NSWindow(contentRect: host.bounds, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    window.makeKey()
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(1))
    host.layoutSubtreeIfNeeded()
    guard let text = textView(in: host) else { fatalError("NSTextView not found") }
    guard text.textContainerInset.height == 8 else { fatalError("expected 8, got \(text.textContainerInset.height)") }
    guard let manager = text.layoutManager, let container = text.textContainer else { fatalError("layout unavailable") }
    manager.ensureLayout(for: container)
    var glyph = NSRange(location: 0, length: 0)
    let fragment = manager.lineFragmentRect(forGlyphAt: 0, effectiveRange: &glyph)
    let visibleTop = text.textContainerOrigin.y + fragment.minY
    guard visibleTop >= text.textContainerInset.height else {
        fatalError("first line \(visibleTop) is above inset \(text.textContainerInset.height)")
    }
    window.orderOut(nil)
    print("PASS height=\(height) inset=\(text.textContainerInset.height) firstLine=\(visibleTop)")
}

@main struct Harness {
    static func main() { check(height: 80); check(height: 100) }
}
'''


def main():
    root = Path(__file__).resolve().parents[1]
    introspect = next(Path.home().joinpath("Library/Developer/Xcode/DerivedData").glob(
        "OnlySwitch-*/SourcePackages/checkouts/swiftui-introspect"
    ), None)
    if introspect is None:
        raise RuntimeError("SwiftUIIntrospect checkout is unavailable; build OnlySwitch once first.")
    modifier = root / "Modules/Sources/Aphrodite/AphroditeTextEditorInset.swift"
    with tempfile.TemporaryDirectory(prefix="aphrodite-inset-") as temporary:
        directory = Path(temporary)
        source = directory / "Sources/AphroditeInsetHarness"
        source.mkdir(parents=True)
        (source / "main.swift").write_text(HARNESS)
        (source / "AphroditeTextEditorInset.swift").symlink_to(modifier)
        (directory / "Package.swift").write_text(f'''// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "AphroditeInsetHarness", platforms: [.macOS(.v26)], dependencies: [.package(path: "{introspect}")], targets: [.executableTarget(name: "AphroditeInsetHarness", dependencies: [.product(name: "SwiftUIIntrospect", package: "swiftui-introspect")])])
''')
        subprocess.run(["swift", "run", "--package-path", str(directory)], check=True, cwd=root, timeout=120)


if __name__ == "__main__":
    main()
