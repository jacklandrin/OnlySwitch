import Foundation

// Dispatch before constructing the SwiftUI app or any application singletons.
if CommandLine.arguments.contains(HostedAudioPlayer.helperArgument) {
    HostedAudioPlayer.runHelper()
} else {
    OnlySwitchApp.main()
}
