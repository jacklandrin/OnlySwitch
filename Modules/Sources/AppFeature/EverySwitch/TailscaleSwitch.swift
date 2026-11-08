import ComposableArchitecture
import Defines
import Extensions
import Foundation
import Switches
import Tailscale

/// Local connection adapter. Credentials and account mutations stay in Tailscale.
final class TailscaleSwitch: SwitchProvider, Sendable {
    let type: SwitchType = .tailscale
    private let client: TailscaleClient
    private let notifyStateChanged: @MainActor @Sendable () -> Void
    private let delegateBox = TailscaleWeakDelegateBox()
    @MainActor private var confirmed: TailscaleSnapshot?
    @MainActor private var failure: TailscaleError?
    @MainActor private var readGeneration = 0
    @MainActor private var mutationInFlight = false
    var delegate: SwitchDelegate? {
        get { delegateBox.value }
        set { delegateBox.value = newValue }
    }

    init(
        client: TailscaleClient,
        notifyStateChanged: @escaping @MainActor @Sendable () -> Void = {
            NotificationCenter.default.post(name: .changeSettings, object: nil)
        }
    ) {
        self.client = client
        self.notifyStateChanged = notifyStateChanged
    }

    @MainActor convenience init() {
        @Dependency(\.tailscaleClient) var client
        self.init(client: client)
    }

    @MainActor func currentStatus() async -> Bool {
        guard !mutationInFlight else { return confirmed?.connection.status == .running }
        readGeneration += 1
        let ticket = readGeneration
        do {
            let snapshot = try await client.snapshot()
            if ticket == readGeneration, !mutationInFlight {
                confirmed = snapshot
                failure = nil
            }
        } catch is CancellationError {
            // A cancelled presentation read does not change confirmed state.
        } catch {
            if ticket == readGeneration, !mutationInFlight {
                failure = TailscaleError.sanitized(error)
            }
        }
        return confirmed?.connection.status == .running
    }

    @MainActor func currentInfo() async -> String {
        if confirmed == nil && failure == nil { _ = await currentStatus() }
        return failure?.localizationKey ?? copyableIPAddress ?? confirmed?.connection.status.localizationKey ?? TailscaleError.unavailable.localizationKey
    }

    @MainActor var copyableIPAddress: String? {
        guard !mutationInFlight, failure == nil, confirmed?.connection.status == .running else { return nil }
        return TailscaleConnection.validatedIPAddress(confirmed?.connection.primaryIPAddress)
    }

    @MainActor func operateSwitch(isOn: Bool) async throws {
        guard !mutationInFlight else { throw TailscaleError.busy }
        mutationInFlight = true
        readGeneration += 1
        defer { mutationInFlight = false }
        do {
            try await client.perform(isOn ? .connect : .disconnect)
            let snapshot = try await client.snapshot()
            guard snapshot.connection.status == (isOn ? .running : .stopped) else { throw TailscaleError.commandFailed }
            readGeneration += 1
            confirmed = snapshot
            failure = nil
            notifyStateChanged()
        } catch {
            readGeneration += 1
            failure = TailscaleError.sanitized(error)
            throw error
        }
    }

    func isVisible() -> Bool { true }
}

/// Protects the synchronous weak delegate required by SwitchProvider.
private final class TailscaleWeakDelegateBox: @unchecked Sendable {
    private let lock = NSLock()
    private weak var stored: SwitchDelegate?
    var value: SwitchDelegate? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
