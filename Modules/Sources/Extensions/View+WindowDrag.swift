//
//  View+WindowDrag.swift
//  Modules
//
//  Created by Bo Liu on 17.11.25.
//

import SwiftUI
import AppKit

public struct WindowDragView: NSViewRepresentable {
    private let onDoubleClick: (() -> Void)?

    public init(onDoubleClick: (() -> Void)? = nil) {
        self.onDoubleClick = onDoubleClick
    }

    public func makeNSView(context: Context) -> NSView {
        let view = DraggableNSView(onDoubleClick: onDoubleClick)
        view.setFrameSize(NSSize(width: 100, height: 100))
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        guard let nsView = nsView as? DraggableNSView else { return }
        nsView.onDoubleClick = onDoubleClick
    }
}

class DraggableNSView: NSView {
    var onDoubleClick: (() -> Void)?

    init(onDoubleClick: (() -> Void)?) {
        self.onDoubleClick = onDoubleClick
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var mouseDownCanMoveWindow: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2, let onDoubleClick {
            onDoubleClick()
        } else {
            window?.performDrag(with: event)
        }
    }
}

public extension View {
    func appKitWindowDrag() -> some View {
        self.background(WindowDragView())
    }
}
