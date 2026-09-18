//
//  LowPowerModeSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/1/1.
//

import Foundation
import Switches
import Defines

final class LowPowerModeSwitch: SwitchProvider, @unchecked Sendable {
    typealias StatusReader = @MainActor @Sendable () async -> Bool

    var type: SwitchType = .lowpowerMode
    weak var delegate: SwitchDelegate?
    private let client: PrivilegedOperationClient
    private let statusReader: StatusReader

    @MainActor
    init(
        client: PrivilegedOperationClient = .live,
        statusReader: @escaping StatusReader = LowPowerModeSwitch.readUnprivilegedStatus
    ) {
        self.client = client
        self.statusReader = statusReader
    }

    @MainActor
    func currentStatus() async -> Bool {
        await statusReader()
    }

    @MainActor
    func currentInfo() async -> String {
        switch await client.status() {
        case .enabled:
            return "Privileged access enabled".localized()
        case .notInstalled:
            return "One-time authorization required".localized()
        case .requiresApproval:
            return "Approve privileged access in System Settings".localized()
        case .disabled:
            return "Privileged access disabled".localized()
        case .unavailable:
            return "Privileged helper unavailable".localized()
        }
    }

    @MainActor
    func operateSwitch(isOn: Bool) async throws {
        try await client.perform(.lowPowerMode, isOn)
    }

    @MainActor
    private static func readUnprivilegedStatus() async -> Bool {
        do {
            let result = try await LowpowerModeCMD.status.runAppleScript(isShellCMD: true)
            return result.contains("1")
        } catch {
            return false
        }
    }
    
    func isVisible() -> Bool {
        return true
    }
}
