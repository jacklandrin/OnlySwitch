//
//  PrivilegedAccessViewModelTests.swift
//  OnlySwitchTests
//

import Synchronization
import Testing
@testable import OnlySwitch

@MainActor
struct PrivilegedAccessViewModelTests {
    @Test(arguments: [
        (PrivilegedHelperStatus.enabled, "Privileged access enabled", nil),
        (.notInstalled, "One-time authorization required", .install),
        (.requiresApproval, "Authorization approval needed", .openSystemSettings),
        (.disabled, "Privileged access disabled", .repair),
        (.unavailable, "Privileged helper unavailable", .repair)
    ])
    func mapsStatusToRecoveryPresentation(
        status: PrivilegedHelperStatus,
        titleKey: String,
        action: PrivilegedAccessAction?
    ) async {
        let model = PrivilegedAccessViewModel(client: client(status: status))

        await model.refresh()

        #expect(model.presentation.titleKey == titleKey)
        #expect(model.presentation.primaryAction == action)
    }

    @Test
    func registrationOnlyOccursForAnExplicitLocalInstallOrRepairAction() async {
        let registrations = Mutex(0)
        let model = PrivilegedAccessViewModel(client: client(
            status: .notInstalled,
            register: { registrations.withLock { $0 += 1 } }
        ))

        await model.refresh()
        #expect(registrations.withLock { $0 } == 0)

        await model.installOrRepair()
        #expect(registrations.withLock { $0 } == 1)
    }

    @Test
    func registrationReportsApprovalNeededWhenMacOSHasNotEnabledTheHelperYet() async {
        let status = Mutex(PrivilegedHelperStatus.notInstalled)
        let model = PrivilegedAccessViewModel(client: PrivilegedOperationClient(
            status: { status.withLock { $0 } },
            installFromInteractiveUI: { status.withLock { $0 = .requiresApproval } },
            removeFromInteractiveUI: {},
            perform: { _, _ in },
            openSystemSettings: {}
        ))

        await model.installOrRepair()

        #expect(model.status == .requiresApproval)
        #expect(model.messageKey == "Authorization approval needed")
    }

    @Test
    func removalOnlyUsesTheLocalRemovalAction() async {
        let removals = Mutex(0)
        let model = PrivilegedAccessViewModel(client: client(
            status: .enabled,
            remove: { removals.withLock { $0 += 1 } }
        ))

        await model.refresh()
        #expect(removals.withLock { $0 } == 0)

        await model.remove()
        #expect(removals.withLock { $0 } == 1)
    }

    private func client(
        status: PrivilegedHelperStatus,
        register: @escaping @Sendable () -> Void = {},
        remove: @escaping @Sendable () -> Void = {}
    ) -> PrivilegedOperationClient {
        PrivilegedOperationClient(
            status: { status },
            installFromInteractiveUI: { register() },
            removeFromInteractiveUI: { remove() },
            perform: { _, _ in },
            openSystemSettings: {}
        )
    }
}
