import Foundation
import OnlyControl
import RemoteCore
import Switches

extension RemoteCatalogProvider {
    @MainActor
    init(
        builtIns: @escaping @MainActor @Sendable () -> [SwitchType],
        makeBuiltIn: @escaping @MainActor @Sendable (SwitchType) -> SwitchProvider,
        shortcutNames: @escaping @MainActor @Sendable () async -> [String],
        evolutions: @escaping @MainActor @Sendable () async throws -> [EvolutionItem],
        evolutionStatus: @escaping @MainActor @Sendable (EvolutionItem) async throws -> Bool? = { _ in nil },
        now: @escaping @MainActor @Sendable () -> Date = Date.init
    ) {
        catalog = {
            let builtInDescriptors = builtIns().map { type in
                Self.descriptor(for: type, control: makeBuiltIn(type))
            }
            let shortcutDescriptors = await shortcutNames().map(Self.descriptor(forShortcut:))
            let evolutionDescriptors = try await evolutions().map(Self.descriptor(for:))
            return builtInDescriptors + shortcutDescriptors + evolutionDescriptors
        }

        status = { id, revision in
            switch id.kind {
            case .builtIn:
                guard let rawValue = UInt64(id.value),
                      String(rawValue) == id.value,
                      let type = SwitchType(rawValue: rawValue),
                      builtIns().contains(type) else {
                    throw RemoteProtocolError(code: .controlNotFound, message: "Control not found")
                }
                return await Self.status(
                    for: type,
                    control: makeBuiltIn(type),
                    revision: revision,
                    now: now()
                )

            case .shortcut:
                guard await shortcutNames().contains(id.value) else {
                    throw RemoteProtocolError(code: .controlNotFound, message: "Shortcut not found")
                }
                return Self.statelessStatus(id: id, revision: revision, now: now())

            case .evolution:
                guard let uuid = UUID(uuidString: id.value), uuid.uuidString == id.value,
                      let evolution = try await evolutions().first(where: { $0.id == uuid }) else {
                    throw RemoteProtocolError(code: .controlNotFound, message: "Evolution not found")
                }
                let availability = Self.availability(for: evolution)
                let isOn: Bool? = if availability.isAvailable && evolution.controlType != .Button {
                    try await evolutionStatus(evolution)
                } else {
                    nil
                }
                return RemoteControlStatus(
                    id: id,
                    isAvailable: availability.isAvailable,
                    unavailableReason: availability.reason,
                    isOn: isOn,
                    secondaryInformation: nil,
                    isProcessing: false,
                    revision: revision,
                    updatedAt: now()
                )
            }
        }
    }

    @MainActor
    static var live: RemoteCatalogProvider {
        RemoteCatalogProvider(
            builtIns: { SwitchType.allCases },
            makeBuiltIn: { $0.getNewSwitchInstance() },
            shortcutNames: { await ShortcutsSettingVM.shared.getAllInstalledShortcutName() ?? [] },
            evolutions: { try await EvolutionListService.liveValue.loadEvolutionList() },
            evolutionStatus: { evolution in
                guard let statusCommand = evolution.statusCommand,
                      let trueCondition = statusCommand.trueCondition else {
                    return nil
                }
                return try await EvolutionCommandService.liveValue.executeCommand(statusCommand) == trueCondition
            },
            now: { Date() }
        )
    }

    @MainActor
    private static func descriptor(
        for type: SwitchType,
        control: SwitchProvider
    ) -> RemoteControlDescriptor {
        let barInfo = type.barInfo()
        let availability = availability(for: type, control: control)
        return RemoteControlDescriptor(
            id: .init(kind: .builtIn, value: String(type.rawValue)),
            title: barInfo.title,
            behavior: behavior(for: barInfo.controlType),
            icon: RemoteIconAdapter.icon(for: type, barInfo: barInfo),
            isAvailable: availability.isAvailable,
            unavailableReason: availability.reason,
            isDestructive: type == .emptyTrash || type == .xcodeCache,
            supportsStatus: barInfo.controlType != .Button,
            supportsSecondaryInformation: true
        )
    }

    private static func descriptor(forShortcut name: String) -> RemoteControlDescriptor {
        RemoteControlDescriptor(
            id: .init(kind: .shortcut, value: name),
            title: name,
            behavior: .button,
            icon: .systemSymbol("command"),
            isAvailable: true,
            unavailableReason: nil,
            isDestructive: false,
            supportsStatus: false,
            supportsSecondaryInformation: false
        )
    }

    @MainActor
    private static func descriptor(for evolution: EvolutionItem) -> RemoteControlDescriptor {
        let availability = availability(for: evolution)
        return RemoteControlDescriptor(
            id: .init(kind: .evolution, value: evolution.id.uuidString),
            title: evolution.name,
            behavior: behavior(for: evolution.controlType),
            icon: RemoteIconAdapter.icon(for: evolution),
            isAvailable: availability.isAvailable,
            unavailableReason: availability.reason,
            isDestructive: false,
            supportsStatus: evolution.controlType != .Button && evolution.statusCommand != nil,
            supportsSecondaryInformation: false
        )
    }

    @MainActor
    private static func status(
        for type: SwitchType,
        control: SwitchProvider,
        revision: UInt64,
        now: Date
    ) async -> RemoteControlStatus {
        let availability = availability(for: type, control: control)
        let controlType = type.barInfo().controlType
        let isOn = controlType == .Button ? nil : await control.currentStatus()
        let info = await control.currentInfo()
        return RemoteControlStatus(
            id: .init(kind: .builtIn, value: String(type.rawValue)),
            isAvailable: availability.isAvailable,
            unavailableReason: availability.reason,
            isOn: isOn,
            secondaryInformation: ControlItemSecondaryInformation.subtitle(
                info: info,
                isAirPods: type == .airPods
            ),
            isProcessing: false,
            revision: revision,
            updatedAt: now
        )
    }

    private static func statelessStatus(
        id: RemoteControlID,
        revision: UInt64,
        now: Date
    ) -> RemoteControlStatus {
        RemoteControlStatus(
            id: id,
            isAvailable: true,
            unavailableReason: nil,
            isOn: nil,
            secondaryInformation: nil,
            isProcessing: false,
            revision: revision,
            updatedAt: now
        )
    }

    @MainActor
    static func availability(for type: SwitchType, control: SwitchProvider) -> RemoteControlAvailability {
        guard control.isVisible() else {
            return .unavailable(unavailableReason(for: type))
        }
        return .available
    }

    static func availability(for evolution: EvolutionItem) -> RemoteControlAvailability {
        switch evolution.controlType {
        case .Button:
            guard evolution.singleCommand != nil else {
                return .unavailable("This Evolution is missing its command")
            }
        case .Switch, .Player:
            guard evolution.onCommand != nil,
                  evolution.offCommand != nil,
                  evolution.statusCommand?.trueCondition != nil else {
                return .unavailable("This Evolution is missing its on, off, or status command")
            }
        }
        return .available
    }

    private static func behavior(for controlType: ControlType) -> RemoteControlDescriptor.Behavior {
        switch controlType {
        case .Switch: .switch
        case .Button: .button
        case .Player: .player
        }
    }

    private static func unavailableReason(for type: SwitchType) -> String {
        switch type {
        case .airPods: "No compatible AirPods are configured or connected"
        case .topNotch: "This Mac does not have a supported display notch"
        case .trueTone: "The active display does not support True Tone"
        case .keyLight: "This Mac does not support keyboard backlight control"
        case .xcodeCache: "Xcode Derived Data is not available on this Mac"
        case .spotify: "Spotify is not running on this Mac"
        case .applemusic: "Apple Music is not running on this Mac"
        case .bluetooth: "Bluetooth is not available on this Mac"
        case .muteMicrophone: "Microphone control permission or hardware is unavailable"
        case .ejectDiscs: "No ejectable discs are connected"
        case .authenticator: "Authenticator has not been configured on this Mac"
        case .radioStation: "Radio Player is disabled in OnlySwitch settings"
        case .backNoises: "Background Noises is disabled in OnlySwitch settings"
        case .hideMenubarIcons: "Menu bar icon collapsing is disabled in OnlySwitch settings"
        case .fkey: "Function-key mode control is not supported by this keyboard"
        case .smallLaunchpadIcon: "Launchpad icon sizing is not supported on macOS 26 or later"
        case .aiCommender: "Only Agent requires macOS 26 or later"
        default: "Not available on this Mac"
        }
    }
}
