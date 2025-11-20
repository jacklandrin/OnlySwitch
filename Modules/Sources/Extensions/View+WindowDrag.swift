//
//  View+WindowDrag.swift
//  Modules
//
//  Created by Bo Liu on 17.11.25.
//

import SwiftUI
import AppKit

public struct WindowDragView: NSViewRepresentable {
    public init() {}
    public func makeNSView(context: Context) -> NSView {
        let view = DraggableNSView()
        view.setFrameSize(NSSize(width: 100, height: 100))
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {}
}

class DraggableNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    
    override func mouseDown(with event: NSEvent) {
        self.window?.performDrag(with: event)
    }
}

public extension View {
    func appKitWindowDrag() -> some View {
        self.background(WindowDragView())
    }
}

