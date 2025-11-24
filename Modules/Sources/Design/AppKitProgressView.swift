//
//  AppKitProgressView.swift
//  Modules
//
//  Created by Bo Liu on 11.11.25.
//

import SwiftUI
import AppKit

// Workaround for macOS 15 and below: Use SwiftUI ProgressView to avoid popover positioning issues
// On macOS 16+, use NSViewRepresentable version for better performance
@available(macOS 16.0, *)
private struct AppKitProgressViewRepresentable: NSViewRepresentable {
    public init() {}
    
    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    public func makeNSView(context: Context) -> NSProgressIndicator {
        let progress = NSProgressIndicator()
        progress.style = .spinning
        progress.isIndeterminate = true
        progress.controlSize = .small
        progress.startAnimation(nil)
        context.coordinator.progressIndicator = progress
        return progress
    }

    public func updateNSView(_ nsView: NSProgressIndicator, context: Context) {
        if !nsView.isHidden {
            nsView.startAnimation(nil)
        }
    }
    
    public static func dismantleNSView(_ nsView: NSProgressIndicator, coordinator: Coordinator) {
        nsView.stopAnimation(nil)
    }
    
    public class Coordinator {
        var progressIndicator: NSProgressIndicator?
    }
}

public struct AppKitProgressView: View {
    public init() {}
    
    public var body: some View {
        if #available(macOS 16.0, *) {
            AppKitProgressViewRepresentable()
        } else {
            // Use SwiftUI ProgressView on macOS 15 and below to avoid popover positioning issues
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
        }
    }
}
