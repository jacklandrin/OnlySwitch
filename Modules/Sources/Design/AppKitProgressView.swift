//
//  AppKitProgressView.swift
//  Modules
//
//  Created by Bo Liu on 11.11.25.
//

import SwiftUI

public struct AppKitProgressView: NSViewRepresentable {
    public init() {}
    public func makeNSView(context: Context) -> NSProgressIndicator {
        let progress = NSProgressIndicator()
        progress.style = .spinning
        progress.isIndeterminate = true
        progress.startAnimation(self)
        progress.translatesAutoresizingMaskIntoConstraints = false
        return progress
    }

    public func updateNSView(_ nsView: NSProgressIndicator, context: Context) {}
}
