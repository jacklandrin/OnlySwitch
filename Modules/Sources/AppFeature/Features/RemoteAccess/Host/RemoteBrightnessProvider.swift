import ComposableArchitecture
import DisplayBrightness
import Extensions
import Foundation
import RemoteCore

/// Bridges the session-retained brightness store to remote peers. A subscribed peer counts as a
/// store host, so display observation runs only while someone is looking.
@MainActor
final class RemoteBrightnessProvider {
    static let shared = RemoteBrightnessProvider(store: SettingsVM.shared.brightnessStore)

    private let store: StoreOf<DisplayBrightnessFeature>
    private let pollInterval: Duration
    private let isEnabled: @MainActor () -> Bool
    private var revision: UInt64 = 0

    init(
        store: StoreOf<DisplayBrightnessFeature>,
        pollInterval: Duration = .milliseconds(400),
        isEnabled: @escaping @MainActor () -> Bool = { UserDefaults.isDisplayBrightnessEnabled() }
    ) {
        self.store = store
        self.isEnabled = isEnabled
        self.pollInterval = pollInterval
    }

    static func remoteSnapshot(from snapshot: BrightnessSnapshot, revision: UInt64) -> RemoteBrightnessSnapshot {
        .init(revision: revision, displays: snapshot.displays.map {
            .init(id: $0.id, name: $0.name, control: .init($0.control), level: $0.level, hasError: $0.error)
        })
    }

    func currentSnapshot() -> RemoteBrightnessSnapshot {
        revision &+= 1
        return Self.remoteSnapshot(from: isEnabled() ? store.snapshot : BrightnessSnapshot(), revision: revision)
    }

    func snapshots(hostID: UUID) -> AsyncStream<RemoteBrightnessSnapshot> {
        AsyncStream { continuation in
            // Master switch off: no `.appeared` (so nothing scans) until it is turned back on.
            var registered = false
            if isEnabled() {
                store.send(.appeared(hostID: hostID))
                registered = true
            }
            // The task alone owns the host registration, so it is released exactly once when the loop
            // ends (consumer cancelled/terminated, or provider gone), even if cancelled while sleeping.
            let task = Task { @MainActor [weak self, store, pollInterval, registered] in
                var registered = registered
                var last: BrightnessSnapshot?
                // `guard let self` per iteration so the loop ends once the provider is gone.
                while !Task.isCancelled {
                    guard let self else { break }
                    let enabled = self.isEnabled()
                    if enabled != registered {
                        store.send(enabled ? .appeared(hostID: hostID) : .disappeared(hostID: hostID))
                        registered = enabled
                    }
                    // Compare what peers see, so flipping the master switch always pushes a snapshot.
                    let next = enabled ? store.snapshot : BrightnessSnapshot()
                    if next != last {
                        continuation.yield(self.currentSnapshot())
                        last = next
                    }
                    try? await Task.sleep(for: pollInterval)
                }
                if registered { store.send(.disappeared(hostID: hostID)) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func perform(_ command: RemoteBrightnessCommand) throws(RemoteProtocolError) -> RemoteBrightnessSnapshot {
        guard isEnabled() else {
            throw RemoteProtocolError(code: .controlUnavailable, message: "Display brightness is turned off")
        }
        switch command {
        case let .setLevel(displayID, level):
            guard let display = store.snapshot.displays.first(where: { $0.id == displayID }) else {
                throw RemoteProtocolError(code: .controlNotFound, message: "Display is no longer connected")
            }
            guard display.control != .unavailable else {
                throw RemoteProtocolError(code: .controlUnavailable, message: "This display's brightness can't be controlled")
            }
            store.send(.levelChanged(screenID: displayID, level: level.isFinite ? min(1, max(0, level)) : 1))
        }
        return currentSnapshot()
    }
}

private extension RemoteBrightnessDisplay.Control {
    init(_ control: DisplayBrightness.BrightnessControl) {
        switch control {
        case .native: self = .native
        case .ddc: self = .ddc
        case .software: self = .software
        case .unavailable: self = .unavailable
        }
    }
}
