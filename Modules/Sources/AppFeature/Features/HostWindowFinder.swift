//
//  HostWindowFinder.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/7/6.
//

import SwiftUI
import AppKit

struct HostingWindowFinder: NSViewRepresentable {
    var callback: (NSWindow?) -> ()

    func makeNSView(context: Self.Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { [weak view] in
            self.callback(view?.window)
        }

        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
