//
//  SwitchBarVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/1.
//

import SwiftUI
import ComposableArchitecture
import Switches
import Sharing
import Tailscale

class SwitchBarVM : BarProvider, ObservableObject, @MainActor SwitchDelegate {
    enum PrivilegedHelperRecovery: Hashable, Identifiable {
        case install
        case openSystemSettings
        case openTailscaleSettings

        var id: Self { self }
    }

    @Shared(.appStorage(UserDefaults.Key.hideMenuAfterRunning)) var hideMenuAfterRunningShared: Bool = false
    let refreshSwitchQueue = DispatchQueue(label: "jacklandrin.onlyswitch.refreshswitch",attributes: .concurrent)
    
    var barName: String {
        switchType.barInfo().title
    }
    
    var switchType: SwitchType {
        return switchOperator.type
    }
    
    var title: String {
        return switchType.barInfo().title
    }
    
    var onImage: NSImage? {
        return switchType.barInfo().onImage
    }
    
    var offImage: NSImage? {
        return switchType.barInfo().offImage
    }
    
    var controlType: ControlType {
        return switchType.barInfo().controlType
    }
    
    var category: SwitchCategory {
        return switchType.barInfo().category
    }
    
    var isHidden: Bool {
        return model.isHidden
    }
    
    var isOn: Bool {
        get {
            return model.isOn
        }
        set {
            model.isOn = newValue
        }
    }
    
    var processing: Bool {
        return model.processing
    }
    
    var info: String {
        return model.info
    }

    @MainActor var copyableInfo: String? { copyableInformation(matching: model.info) }

    @MainActor func copyInfo(displayedInfo: String? = nil) async {
        guard let address = copyableInformation(matching: displayedInfo ?? model.info) else { return }
        _ = await pasteboard.copy(address)
    }

    @MainActor private func copyableInformation(matching displayedInfo: String) -> String? {
        guard switchType == .tailscale, !processing, !operationInFlight, !hasFailedOperation, isOn,
              let address = (switchOperator as? TailscaleSwitch)?.copyableIPAddress,
              displayedInfo == address else { return nil }
        return address
    }

    var weight: Int {
        get {
            return model.weight
        }
        set {
            model.weight = newValue
        }
    }

    var id: String {
        String(switchType.legacyIdentifier)
    }

    @Published private var model = SwitchBarModel()
    @Published private(set) var switchOperator:SwitchProvider
    @Published var privilegedHelperRecovery: PrivilegedHelperRecovery?
    private let pasteboard: RemotePasteboardClient
    let copyTarget: SwitchBarCopyTarget
    @MainActor private var refreshGeneration = 0
    @MainActor private var operationInFlight = false
    @MainActor private var hasFailedOperation = false
    
    @MainActor
    init(switchOperator: SwitchProvider, pasteboard: RemotePasteboardClient? = nil) {
        let copyTarget = SwitchBarCopyTarget()
        self.copyTarget = copyTarget
        @Dependency(\.remotePasteboard) var defaultPasteboard
        self.pasteboard = pasteboard ?? defaultPasteboard
        self.switchOperator = switchOperator
        self.switchOperator.delegate = self
        model.isHidden = !switchOperator.isVisible()
        copyTarget.owner = self
    }
    
    @MainActor
    func refreshStatus() {
        if switchType == .xcodeCache {
            if info == "" || info != "Calculating..." {
                model.info = "Calculating..."
                refreshAsync()
            }
        } else {
            refreshAsync()
        }
    }
    
    @MainActor
    func refreshAsync() {
        Task { await refresh() }
    }

    @MainActor
    func refresh() async {
        guard !operationInFlight else { return }
        refreshGeneration += 1
        let ticket = refreshGeneration
        model.processing = true
        let isOn = await switchOperator.currentStatus()
        let information = await switchOperator.currentInfo()
        guard ticket == refreshGeneration, !operationInFlight else { return }
        model.isOn = isOn
        model.info = information
        hasFailedOperation = false
        model.processing = false
    }
    
    @MainActor
    func doSwitch(isOn: Bool) async {
        guard !operationInFlight else { return }
        operationInFlight = true
        refreshGeneration += 1
        defer {
            operationInFlight = false
            model.processing = false
        }
        model.processing = true
        do {
            _ = try await switchOperator.operateSwitch(isOn: isOn)
            self.model.isOn = isOn
            if info != "" || switchType == .tailscale {
                _ = await switchOperator.currentStatus()
                model.info = await switchOperator.currentInfo()
            }
            hasFailedOperation = false
            if hideMenuAfterRunningShared
                && switchType.barInfo().controlType == .Button
                && switchType.barInfo().category == .none {
                NotificationCenter.default.post(name: .shouldHidePopover, object: nil)
            }
        } catch {
            if switchType == .tailscale {
                hasFailedOperation = true
                model.isOn = await switchOperator.currentStatus()
                model.info = TailscaleError.sanitized(error).localizationKey
                privilegedHelperRecovery = .openTailscaleSettings
                return
            }
            guard switchType == .lowpowerMode,
                  let error = error as? PrivilegedOperationClientError else { return }
            switch error {
            case .notInstalled, .unavailable:
                privilegedHelperRecovery = .install
            case .requiresApproval, .disabled:
                privilegedHelperRecovery = .openSystemSettings
            default:
                break
            }
        }
    }

    @MainActor
    func openTailscaleSettings() {
        SettingsVM.shared.selection = .Tailscale
        OpenWindows.Setting.open()
        privilegedHelperRecovery = nil
    }

    @MainActor
    func installPrivilegedHelper() async {
        guard let lowPowerMode = switchOperator as? LowPowerModeSwitch else { return }
        do {
            try await lowPowerMode.installHelperFromInteractiveUI()
        } catch {
            privilegedHelperRecovery = .openSystemSettings
        }
        refreshAsync()
    }

    @MainActor
    func openPrivilegedHelperSettings() async {
        guard let lowPowerMode = switchOperator as? LowPowerModeSwitch else { return }
        await lowPowerMode.openPrivilegedHelperSettings()
        privilegedHelperRecovery = nil
    }
    
    @MainActor
    func shouldRefreshIfNeed(aSwitch:SwitchProvider) {
        guard switchOperator === aSwitch else {return}
        refreshAsync()
    }
}

/// A sendable capability whose VM reference is only read on the main actor.
/// Reducer effects capture this target rather than transferring mutable VM state.
@MainActor
final class SwitchBarCopyTarget {
    weak var owner: SwitchBarVM?

    func copy(_ displayedInfo: String) async {
        await owner?.copyInfo(displayedInfo: displayedInfo)
    }
}
