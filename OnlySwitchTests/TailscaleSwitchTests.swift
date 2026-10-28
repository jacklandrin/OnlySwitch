import ComposableArchitecture
import Extensions
import Foundation
import RemoteCore
import Switches
import Tailscale
import Testing
@testable import OnlySwitch

@MainActor
struct TailscaleSwitchTests {
    private func snapshot(_ status: TailscaleConnection.Status) -> TailscaleSnapshot {
        .init(accounts: [], connection: .init(status: status), preferences: [:], preferencesAvailable: false)
    }

    @Test func connectionReadsConfirmedStateAndPreservesItWhenRefreshFails() async {
        let state = TestMutex<Result<TailscaleSnapshot, TailscaleError>>(.success(snapshot(.running)))
        let provider = TailscaleSwitch(client: .init(snapshot: { try state.withLock { try $0.get() } }, perform: { _ in }), notifyStateChanged: {})
        #expect(await provider.currentStatus())
        state.withLock { $0 = .failure(.unavailable) }
        #expect(await provider.currentStatus())
        #expect(!(await provider.currentInfo()).isEmpty)
    }

    @Test func operationsUseClientAndPropagateFailure() async throws {
        let state = TestMutex(snapshot(.stopped))
        let operations = TestMutex<[TailscaleOperation]>([])
        let provider = TailscaleSwitch(client: .init(snapshot: { state.withLock { $0 } }, perform: { operation in
            operations.withLock { $0.append(operation) }
            state.withLock { $0.connection.status = operation == .connect ? .running : .stopped }
        }), notifyStateChanged: {})
        try await provider.operateSwitch(isOn: true)
        #expect(await provider.currentStatus())
        try await provider.operateSwitch(isOn: false)
        #expect(!(await provider.currentStatus()))
        #expect(operations.withLock { $0 } == [.connect, .disconnect])
        let failing = TailscaleSwitch(client: .init(snapshot: { throw TailscaleError.authenticationRequired }, perform: { _ in throw TailscaleError.authenticationRequired }), notifyStateChanged: {})
        await #expect(throws: TailscaleError.authenticationRequired) { try await failing.operateSwitch(isOn: true) }
    }

    @Test(arguments: [false, true])
    func olderReadCannotOverwriteNewerSnapshot(firstFails: Bool) async {
        let gate = TailscaleProviderReadGate(first: firstFails ? .failure(.unavailable) : .success(snapshot(.running)), following: snapshot(.stopped))
        let provider = TailscaleSwitch(client: .init(snapshot: { try await gate.read() }, perform: { _ in }), notifyStateChanged: {})
        let olderRead = Task { await provider.currentStatus() }
        await gate.waitUntilFirstRead()
        #expect(!(await provider.currentStatus()))
        await gate.releaseFirst()
        #expect(!(await olderRead.value))
        #expect(await provider.currentInfo() == TailscaleConnection.Status.stopped.localizationKey)
    }

    @Test func completedMutationInvalidatesPendingRead() async throws {
        let gate = TailscaleProviderReadGate(first: .success(snapshot(.running)), following: snapshot(.stopped))
        let provider = TailscaleSwitch(client: .init(snapshot: { try await gate.read() }, perform: { _ in }), notifyStateChanged: {})
        let olderRead = Task { await provider.currentStatus() }
        await gate.waitUntilFirstRead()
        try await provider.operateSwitch(isOn: false)
        await gate.releaseFirst()
        #expect(!(await olderRead.value))
        #expect(await provider.currentInfo() == TailscaleConnection.Status.stopped.localizationKey)
    }

    @Test func identityAndSettingsDiscoveryRemainStable() {
        #expect(SwitchType.tailscale.legacyIdentifier == 281_474_976_710_656)
        #expect(SwitchType(legacyIdentifier: 281_474_976_710_656) == .tailscale)
        #expect(SwitchType.tailscale.barInfo().controlType == .Switch)
        #expect(BuiltInSwitchCatalog.section(for: .tailscale) == .productivityAndTools)
        #expect(!UserDefaults.Key.exportableKeys.contains(UserDefaults.Key.didInstallTailscaleSwitch))
    }

    @Test func failedToggleRestoresConfirmedStateAndOffersSettingsRecovery() async {
        let snapshot = snapshot(.running)
        let provider = TailscaleSwitch(client: .init(snapshot: { snapshot }, perform: { _ in throw TailscaleError.commandFailed }), notifyStateChanged: {})
        _ = await provider.currentStatus()
        let model = SwitchBarVM(switchOperator: provider)
        model.isOn = false // The control binding changes before its async operation.
        await model.doSwitch(isOn: false)
        #expect(model.isOn)
        #expect(!model.processing)
        #expect(model.info == TailscaleError.commandFailed.localizationKey)
        #expect(model.privilegedHelperRecovery == .openTailscaleSettings)
    }

    @Test func visibilityUsesIdentifiersWithoutExtendingTheHistoricalBitmask() throws {
        let suite = "TailscaleVisibilityTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(String(SwitchType.tailscale.legacyIdentifier), forKey: UserDefaults.Key.SwitchState)
        #expect(!SwitchVisibilityState.visibleTypes(from: defaults).contains(.tailscale))
        SwitchVisibilityState.setVisible(.tailscale, for: true, in: defaults)
        #expect(SwitchVisibilityState.visibleTypes(from: defaults).contains(.tailscale))
        SwitchVisibilityState.setVisible(.tailscale, for: false, in: defaults)
        #expect(!SwitchVisibilityState.visibleTypes(from: defaults).contains(.tailscale))
    }

    @Test func remoteCannotDiscoverReadOrOperateTailscale() async throws {
        let calls = TestMutex(0)
        let provider = TailscaleSwitch(client: .init(snapshot: { throw TailscaleError.unavailable }, perform: { _ in calls.withLock { $0 += 1 } }), notifyStateChanged: {})
        let catalog = RemoteCatalogProvider(builtIns: { [.tailscale] }, makeBuiltIn: { _ in provider }, shortcutNames: { [] }, evolutions: { [] })
        #expect(try await catalog.catalog().isEmpty)
        let id = RemoteControlID(kind: .builtIn, value: String(SwitchType.tailscale.legacyIdentifier))
        do {
            _ = try await catalog.status(id, 1)
            Issue.record("Tailscale account status must stay local")
        } catch let error as RemoteProtocolError {
            #expect(error.code == .controlNotFound)
        }
        let router = RemoteCommandRouter(resolveBuiltIn: { _ in provider })
        let result = await router.perform(.init(requestID: UUID(), controlID: id, action: .setState(false)))
        guard case let .failure(error) = result.result else { Issue.record("Remote Tailscale operation succeeded"); return }
        #expect(error.code == .controlNotFound)
        #expect(calls.withLock { $0 } == 0)
    }
}

private actor TailscaleProviderReadGate {
    private let first: Result<TailscaleSnapshot, TailscaleError>
    private let following: TailscaleSnapshot
    private var reads = 0
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var firstWaiter: CheckedContinuation<Void, Never>?

    init(first: Result<TailscaleSnapshot, TailscaleError>, following: TailscaleSnapshot) {
        self.first = first; self.following = following
    }

    func read() async throws -> TailscaleSnapshot {
        reads += 1
        guard reads == 1 else { return following }
        await withCheckedContinuation { continuation in
            firstWaiter = continuation
            started = true
            startWaiter?.resume(); startWaiter = nil
        }
        return try first.get()
    }

    func waitUntilFirstRead() async {
        if started { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func releaseFirst() { firstWaiter?.resume(); firstWaiter = nil }
}
