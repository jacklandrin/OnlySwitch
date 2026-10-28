import ComposableArchitecture
import Extensions
import Foundation
import OnlyControl
import RemoteCore
import Switches
import Tailscale
import Testing
@testable import OnlySwitch

@MainActor
struct TailscaleSwitchTests {
    @Test func menuCopiesOnlyTheDisplayedConfirmedIPWithoutOperatingTheSwitch() async {
        let value = TailscaleSnapshot(accounts: [], connection: .init(status: .running, primaryIPAddress: "100.20.30.40"))
        let copies = TestMutex<[String]>([])
        let operations = TestMutex<[TailscaleOperation]>([])
        let provider = TailscaleSwitch(client: .init(snapshot: { value }, perform: { operation in operations.withLock { $0.append(operation) } }), notifyStateChanged: {})
        let model = SwitchBarVM(switchOperator: provider, pasteboard: .init { value in copies.withLock { $0.append(value) }; return true })
        await model.refresh()
        #expect(model.copyableInfo == "100.20.30.40")
        await model.copyInfo()
        await model.copyInfo()
        #expect(copies.withLock { $0 } == ["100.20.30.40", "100.20.30.40"])
        #expect(operations.withLock { $0 }.isEmpty)
        #expect(model.isOn)
    }

    @Test(arguments: [TailscaleConnection.Status.stopped, .needsLogin, .starting, .unavailable])
    func menuCannotCopyNonrunningDescriptions(status: TailscaleConnection.Status) async {
        let value = TailscaleSnapshot(accounts: [], connection: .init(status: status, primaryIPAddress: "100.20.30.40"))
        let copies = TestMutex<[String]>([])
        let provider = TailscaleSwitch(client: .init(snapshot: { value }, perform: { _ in }), notifyStateChanged: {})
        let model = SwitchBarVM(switchOperator: provider, pasteboard: .init { value in copies.withLock { $0.append(value) }; return true })
        await model.refresh()
        await model.copyInfo()
        #expect(model.copyableInfo == nil)
        #expect(copies.withLock { $0 }.isEmpty)
    }

    @Test(arguments: [nil, "not an IP"] as [String?])
    func menuDoesNotCopyAConnectedDescriptionWithoutAValidIP(address: String?) async {
        let value = TailscaleSnapshot(accounts: [], connection: .init(status: .running, primaryIPAddress: address))
        let copies = TestMutex<[String]>([])
        let provider = TailscaleSwitch(client: .init(snapshot: { value }, perform: { _ in }), notifyStateChanged: {})
        let model = SwitchBarVM(switchOperator: provider, pasteboard: .init { value in copies.withLock { $0.append(value) }; return true })
        await model.refresh()
        await model.copyInfo()
        #expect(model.copyableInfo == nil)
        #expect(copies.withLock { $0 }.isEmpty)
    }

    @Test func changedProviderAddressCannotCopyTheOldMenuOrDashboardValue() async {
        let value = TailscaleSnapshot(accounts: [], connection: .init(status: .running, primaryIPAddress: "100.20.30.40"))
        let state = TestMutex<Result<TailscaleSnapshot, TailscaleError>>(.success(value))
        let copies = TestMutex<[String]>([])
        let provider = TailscaleSwitch(client: .init(snapshot: { try state.withLock { try $0.get() } }, perform: { _ in }), notifyStateChanged: {})
        let model = SwitchBarVM(switchOperator: provider, pasteboard: .init { value in copies.withLock { $0.append(value) }; return true })
        await model.refresh()
        state.withLock { $0 = .success(.init(accounts: [], connection: .init(status: .running, primaryIPAddress: "100.20.30.41"))) }
        _ = await provider.currentStatus()
        #expect(model.copyableInfo == nil)
        await model.copyInfo()
        await model.copyInfo(displayedInfo: "100.20.30.40")
        state.withLock { $0 = .failure(.unavailable) }
        _ = await provider.currentStatus()
        await model.copyInfo(displayedInfo: "100.20.30.41")
        #expect(copies.withLock { $0 }.isEmpty)
    }

    @Test func onlyControlCopiesItsVisibleIPWithoutDependingOnMenuInfoOrToggling() async {
        let value = TailscaleSnapshot(accounts: [], connection: .init(status: .running, primaryIPAddress: "100.20.30.40"))
        let copies = TestMutex<[String]>([])
        let operations = TestMutex<[TailscaleOperation]>([])
        let provider = TailscaleSwitch(client: .init(snapshot: { value }, perform: { operation in operations.withLock { $0.append(operation) } }), notifyStateChanged: {})
        let model = SwitchBarVM(switchOperator: provider, pasteboard: .init { value in copies.withLock { $0.append(value) }; return true })
        model.isOn = await provider.currentStatus()
        #expect(model.info.isEmpty)
        let item = ControlItemViewState(id: model.id, title: "Tailscale", subtitle: "100.20.30.40", copyableSubtitle: true, iconData: Data(), controlType: .Switch, status: true)
        var state = OnlyControlReducer.State()
        state.dashboard.items = [item]; state.switchList = [model]; state.allUnits = [model]
        let store = TestStore(initialState: state) { OnlyControlReducer() }
        await store.send(.dashboardAction(.copySubtitle(model.id)))
        await store.receive(\.dashboardAction, .delegate(.copySubtitle(model.id)))
        await store.finish()
        #expect(copies.withLock { $0 } == ["100.20.30.40"])
        #expect(operations.withLock { $0 }.isEmpty)
        #expect(store.state.dashboard.items[id: model.id]?.status == true)
    }

    @Test func onlyControlRevalidatesAStaleSubtitleBeforeCopying() async {
        let value = TailscaleSnapshot(accounts: [], connection: .init(status: .running, primaryIPAddress: "100.20.30.41"))
        let copies = TestMutex<[String]>([])
        let provider = TailscaleSwitch(client: .init(snapshot: { value }, perform: { _ in Issue.record("Copy must not toggle") }), notifyStateChanged: {})
        let model = SwitchBarVM(switchOperator: provider, pasteboard: .init { value in copies.withLock { $0.append(value) }; return true })
        model.isOn = await provider.currentStatus()
        let item = ControlItemViewState(id: model.id, title: "Tailscale", subtitle: "100.20.30.40", copyableSubtitle: true, iconData: Data(), controlType: .Switch, status: true)
        var state = OnlyControlReducer.State()
        state.dashboard.items = [item]; state.switchList = [model]; state.allUnits = [model]
        let store = TestStore(initialState: state) { OnlyControlReducer() }
        await store.send(.dashboardAction(.copySubtitle(model.id)))
        await store.receive(\.dashboardAction, .delegate(.copySubtitle(model.id)))
        await store.finish()
        #expect(copies.withLock { $0 }.isEmpty)
    }

    @Test func processingAndFailedOperationsDisableBothCopyEntrypoints() async {
        let value = TailscaleSnapshot(accounts: [], connection: .init(status: .running, primaryIPAddress: "100.20.30.40"))
        let gate = TailscaleProviderReadGate(first: .success(value), following: value, blockedRead: 2)
        let copies = TestMutex<[String]>([])
        let provider = TailscaleSwitch(client: .init(snapshot: { try await gate.read() }, perform: { _ in throw TailscaleError.commandFailed }), notifyStateChanged: {})
        let model = SwitchBarVM(switchOperator: provider, pasteboard: .init { value in copies.withLock { $0.append(value) }; return true })
        await model.refresh()
        #expect(model.copyableInfo == "100.20.30.40")
        let refresh = Task { await model.refresh() }
        await gate.waitUntilFirstRead()
        #expect(model.processing)
        await model.copyInfo()
        await model.copyInfo(displayedInfo: "100.20.30.40")
        await gate.releaseFirst()
        await refresh.value
        await model.doSwitch(isOn: false)
        await model.copyInfo()
        await model.copyInfo(displayedInfo: "100.20.30.40")
        #expect(model.copyableInfo == nil)
        #expect(copies.withLock { $0 }.isEmpty)
    }

    @Test(arguments: [false, true])
    func operationReadbackKeepsTheControlBusy(operationFails: Bool) async {
        let value = TailscaleSnapshot(accounts: [], connection: .init(status: .running, primaryIPAddress: "100.20.30.40"))
        let gate = TailscaleProviderReadGate(first: .success(value), following: value, blockedRead: operationFails ? 2 : 3)
        let provider = TailscaleSwitch(client: .init(snapshot: { try await gate.read() }, perform: { _ in
            if operationFails { throw TailscaleError.commandFailed }
        }), notifyStateChanged: {})
        let model = SwitchBarVM(switchOperator: provider, pasteboard: .init { _ in Issue.record("Busy controls cannot copy"); return true })
        await model.refresh()
        let operation = Task { await model.doSwitch(isOn: true) }
        await gate.waitUntilFirstRead()
        #expect(model.processing)
        #expect(model.copyableInfo == nil)
        await model.copyInfo(displayedInfo: "100.20.30.40")
        await gate.releaseFirst()
        await operation.value
        #expect(!model.processing)
    }

    @Test func runningProviderExposesTheConfirmedLocalIPAsInfo() async {
        let value = TailscaleSnapshot(accounts: [], connection: .init(status: .running, primaryIPAddress: "100.20.30.40"))
        let provider = TailscaleSwitch(client: .init(snapshot: { value }, perform: { _ in }), notifyStateChanged: {})
        #expect(await provider.currentStatus())
        #expect(await provider.currentInfo() == "100.20.30.40")
        #expect(provider.copyableIPAddress == "100.20.30.40")
    }

    @Test(arguments: [TailscaleConnection.Status.stopped, .needsLogin, .needsMachineAuth, .starting, .unavailable])
    func nonrunningProviderNeverOffersAnAddressToCopy(status: TailscaleConnection.Status) async {
        let value = TailscaleSnapshot(accounts: [], connection: .init(status: status, primaryIPAddress: "100.20.30.40"))
        let provider = TailscaleSwitch(client: .init(snapshot: { value }, perform: { _ in }), notifyStateChanged: {})
        #expect(!(await provider.currentStatus()))
        #expect(provider.copyableIPAddress == nil)
        #expect(await provider.currentInfo() == status.localizationKey)
    }

    @Test func runningWithoutAnAddressKeepsConnectedInfoAndNoCopy() async {
        let value = snapshot(.running)
        let provider = TailscaleSwitch(client: .init(snapshot: { value }, perform: { _ in }), notifyStateChanged: {})
        #expect(await provider.currentStatus())
        #expect(provider.copyableIPAddress == nil)
        #expect(await provider.currentInfo() == TailscaleConnection.Status.running.localizationKey)
    }

    @Test(arguments: ["not an IP", "100.20.30.40/32", "100.20.30.40\n", "fd7a:115c:a1e0::1%en0"])
    func dependencySnapshotsCannotMakeArbitraryTextCopyable(address: String) async {
        let value = TailscaleSnapshot(accounts: [], connection: .init(status: .running, primaryIPAddress: address))
        let provider = TailscaleSwitch(client: .init(snapshot: { value }, perform: { _ in }), notifyStateChanged: {})
        #expect(await provider.currentStatus())
        #expect(provider.copyableIPAddress == nil)
        #expect(await provider.currentInfo() == TailscaleConnection.Status.running.localizationKey)
    }

    @Test func failedReadSuppressesThePreviouslyCopyableAddress() async {
        let value = TailscaleSnapshot(accounts: [], connection: .init(status: .running, primaryIPAddress: "100.20.30.40"))
        let state = TestMutex<Result<TailscaleSnapshot, TailscaleError>>(.success(value))
        let provider = TailscaleSwitch(client: .init(snapshot: { try state.withLock { try $0.get() } }, perform: { _ in }), notifyStateChanged: {})
        #expect(await provider.currentStatus())
        #expect(provider.copyableIPAddress == "100.20.30.40")
        state.withLock { $0 = .failure(.unavailable) }
        #expect(await provider.currentStatus())
        #expect(provider.copyableIPAddress == nil)
        #expect(await provider.currentInfo() == TailscaleError.unavailable.localizationKey)
    }

    @Test func failedMutationSuppressesThePreviouslyCopyableAddress() async {
        let value = TailscaleSnapshot(accounts: [], connection: .init(status: .running, primaryIPAddress: "100.20.30.40"))
        let provider = TailscaleSwitch(client: .init(snapshot: { value }, perform: { _ in throw TailscaleError.commandFailed }), notifyStateChanged: {})
        _ = await provider.currentStatus()
        await #expect(throws: TailscaleError.commandFailed) { try await provider.operateSwitch(isOn: false) }
        #expect(provider.copyableIPAddress == nil)
        #expect(await provider.currentInfo() == TailscaleError.commandFailed.localizationKey)
    }

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
    private let blockedRead: Int

    init(first: Result<TailscaleSnapshot, TailscaleError>, following: TailscaleSnapshot, blockedRead: Int = 1) {
        self.first = first; self.following = following
        self.blockedRead = blockedRead
    }

    func read() async throws -> TailscaleSnapshot {
        reads += 1
        guard reads == blockedRead else { return following }
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
