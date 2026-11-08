import Foundation

/// The only public surface of the macOS app module, invoked from the
/// OnlySwitch target's `main.swift`.
public enum AppEntry {
    @MainActor
    public static func run() -> Never {
        // Dispatch before constructing the SwiftUI app or any application singletons.
        if CommandLine.arguments.contains(HostedAudioPlayer.helperArgument) {
            HostedAudioPlayer.runHelper()
        } else {
            CrashReportPrompt.beginMonitoring()
            OnlySwitchApp.main()
        }
        exit(EXIT_SUCCESS)
    }
}
