//
//  OnlyControl.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2024/9/21.
//

import ComposableArchitecture
import OnlyControl
import AppKit
import Defines
import Switches
import Extensions

@Reducer
struct OnlyControlReducer {
    @ObservableState
    struct State: Equatable {
        static func == (lhs: OnlyControlReducer.State, rhs: OnlyControlReducer.State) -> Bool {
            if lhs.dashboard != rhs.dashboard {
                return false
            } else if lhs.blurRadius != rhs.blurRadius {
                return false
            } else if lhs.opacity != rhs.opacity {
                return false
            } else if areArraysEqual(lhs: lhs.allUnits, rhs: rhs.allUnits) == false {
                return false
            } else if lhs.isAirPodsConnected != rhs.isAirPodsConnected {
                return false
            } else if lhs.airPodsBatteryValues != rhs.airPodsBatteryValues {
                return false
            }

            return true
        }

        private static func areArraysEqual(lhs: [BarProvider], rhs: [BarProvider]) -> Bool {
            guard lhs.count == rhs.count else {
                return false
            }

            for (index, item) in lhs.enumerated() {
                if item.id != rhs[index].id {
                    return false
                }
            }
            return true
        }

        var dashboard: DashboardReducer.State = .init()
        var blurRadius: CGFloat = 20
        var opacity: Double = 0
        var allUnits: [BarProvider] = []
        var switchList: [SwitchBarVM] = []
        var isAirPodsConnected: Bool = false
        var airPodsBatteryValues: [Float] = []

        var soundWaveEffectDisplay: Bool {
            Preferences.shared.soundWaveEffectDisplay
        }
    }

    enum Action {
        case task
        case refreshDashboard
        case refreshSingleSwitchType(SwitchType)
        case showControl
        case hideControl
        case updateItems([BarProvider], [ControlItemViewState], [SwitchBarVM])
        case updateItem(ControlItemViewState)
        case openSettings
        case dashboardAction(DashboardReducer.Action)
        case refreshAirPodsBattery
        case updateAirPodsBattery(isConnected: Bool, batteryValues: [Float])
    }

    @Dependency(\.onlyControlClient) var client

    var body: some ReducerOf<Self> {
        Scope(state: \.dashboard, action: \.dashboardAction) {
            DashboardReducer()
        }

        Reduce { state, action in
            switch action {
                case .task:
                    return .merge(
                        .onSwitchListChanged(perform: .refreshDashboard),
                        .singleItemChanged(perform: {.refreshSingleSwitchType($0)})
                    )

                case .refreshDashboard:
                    return refreshDashboard()

                case .refreshSingleSwitchType(let type):
                    guard let switchControl = state.switchList.first(where: { $0.switchType == type}) else {
                        if type == .airPods {
                            return .send(.refreshAirPodsBattery)
                        }
                        return .none
                    }

                    let additionalEffect: EffectOf<Self> = type == .airPods ? .send(.refreshAirPodsBattery) : .none

                    return .merge(
                        .run { [state, switchControl] send in
                            let isOn = await switchControl.switchOperator.currentStatus()
                            if var item = state.dashboard.items.first(where: { $0.id == switchControl.id }) {
                                item.status = isOn
                                let image = (isOn ? switchControl.onImage : switchControl.offImage) ?? NSImage(named: "shortcuts_icon")!
                                item.iconData = image
                                    .resizeMaintainingAspectRatio(withSize: NSSize(width: 60, height: 60))!
                                    .pngData!
                                await send(.updateItem(item))
                            }
                        },
                        additionalEffect
                    )

                case .showControl:
                    state.blurRadius = 0
                    state.opacity = 1
                    return .merge(
                        .send(.refreshDashboard),
                        .send(.refreshAirPodsBattery)
                    )

                case .hideControl:
                    state.blurRadius = 20
                    state.opacity = 0
                    return .none

                case let .updateItems(units, items, switches):
                    let items = items.sorted { $0.weight < $1.weight }
                    state.dashboard.items = IdentifiedArray(uniqueElements: items)
                    state.allUnits = units
                    state.switchList = switches
                    return .none

                case let .updateItem(item):
                    state.dashboard.items[id: item.id] = item
                    return .none

                case let .dashboardAction(.delegate(.didTapItem(id))):
                    guard let control = state.allUnits.first(where: { $0.id == id }) else {
                        return .none
                    }
                    if let switchControl = control as? SwitchBarVM {
                        switchControl.switchType.doSwitch()
                    } else if let shortcutControl = control as? ShortcutsBarVM {
                        shortcutControl.runShortCut()
                    } else if let evolutionControl = control as? EvolutionBarVM {
                        evolutionControl.doSwitch()
                    }
                    return .none

                case .openSettings:
                    SettingsWindow.shared.show()
                    return .none

                case .dashboardAction(.delegate(.orderChanged)):
                    var orderDic = [String: Int]()
                    for (index, item) in state.dashboard.items.enumerated() {
                        let key = item.unitType.prefix() + item.id
                        orderDic[key] = index
                    }
                    UserDefaults.standard.set(orderDic, forKey: UserDefaults.Key.onlyControlOrderWeight)
                    UserDefaults.standard.synchronize()
                    return .none

                case .dashboardAction:
                    return .none

                case .refreshAirPodsBattery:
                    return .run { send in
                        guard let airPodsSwitch = SwitchManager.shared.getSwitch(of: .airPods) as? AirPodsSwitch else {
                            await send(.updateAirPodsBattery(isConnected: false, batteryValues: []))
                            return
                        }

                        let connected = await airPodsSwitch.currentStatus()
                        if connected {
                            let info = await airPodsSwitch.currentInfo()
                            let batteryValues = convertBattery(info: info)
                            await send(.updateAirPodsBattery(isConnected: true, batteryValues: batteryValues))
                        } else {
                            await send(.updateAirPodsBattery(isConnected: false, batteryValues: []))
                        }
                    }

                case let .updateAirPodsBattery(isConnected, batteryValues):
                    state.isAirPodsConnected = isConnected
                    state.airPodsBatteryValues = batteryValues
                    return .none
            }
        }
    }

    private func convertBattery(info: String) -> [Float] {
        let pattern = "(-?\\d+)"
        let groups = info.groups(for: pattern).compactMap({ $0.first }).map { Float($0)! < 0 ? 0.0 : (Float($0)! / 100.0) }
        return groups
    }

    private func refreshDashboard() -> EffectOf<Self> {
        .run { send in
            let switches = await client.fetchSwitchList()
            for switchControl in switches {
                let isOn = await switchControl.switchOperator.currentStatus()
                switchControl.isOn = isOn
            }
            let shortcuts = await client.fetchShortcutsList()
            let evolutions = await client.fetchEvolutionList()
            for evolutionControl in evolutions {
                await evolutionControl.refresh()
            }

            let allUnits: [BarProvider] = switches + shortcuts + evolutions

            let orderDic = UserDefaults.standard.dictionary(forKey: UserDefaults.Key.onlyControlOrderWeight) as? [String: Int] ?? [String: Int]()

            let items: [ControlItemViewState] = allUnits.compactMap { (unit: BarProvider) -> ControlItemViewState? in
                if let switchVM = unit as? SwitchBarVM {
                    guard !switchVM.isHidden else {
                        return nil
                    }

                    let key = "switch-" + switchVM.id
                    let weight = orderDic[key] ?? switchVM.weight
                    let image = (switchVM.isOn ? switchVM.onImage : switchVM.offImage) ?? NSImage(named: "shortcuts_icon")!

                    return ControlItemViewState(
                        id: switchVM.id,
                        title: switchVM.barName.localized(),
                        iconData: image
                            .resizeMaintainingAspectRatio(withSize: NSSize(width: 60, height: 60))!
                            .pngData!,
                        controlType: switchVM.controlType,
                        status: switchVM.isOn,
                        weight: weight,
                        unitType: .builtIn
                    )
                } else if let shortcutVM = unit as? ShortcutsBarVM {
                    guard !shortcutVM.isHidden else {
                        return nil
                    }

                    let key = "shortcuts-" + shortcutVM.id
                    let weight = orderDic[key] ?? shortcutVM.weight
                    let image = NSImage(named: "shortcuts_icon")!

                    return ControlItemViewState(
                        id: shortcutVM.id,
                        title: shortcutVM.barName,
                        iconData: image
                            .resizeMaintainingAspectRatio(withSize: NSSize(width: 60, height: 60))!
                            .pngData!,
                        controlType: .Button,
                        status: false,
                        weight: weight,
                        unitType: .shortcuts
                    )
                } else if let evolutionVM = unit as? EvolutionBarVM {
                    let key = "evolution-" + evolutionVM.id
                    let weight = orderDic[key] ?? evolutionVM.weight
                    let imageName = evolutionVM.iconName ??
                    (
                        evolutionVM.controlType == .Switch
                        ? "lightswitch.on.square"
                        : "button.programmable.square.fill"
                    )
                    let image = NSImage(systemSymbolName: imageName)

                    return ControlItemViewState(
                        id: evolutionVM.id,
                        title: evolutionVM.barName,
                        iconData: image
                            .resizeMaintainingAspectRatio(withSize: NSSize(width: 60, height: 60))!
                            .pngData!,
                        controlType: evolutionVM.controlType,
                        status: evolutionVM.isOn,
                        weight: weight,
                        unitType: .evolution
                    )
                } else {
                    return nil
                }
            }

           await send(.updateItems(allUnits, items, switches))
        }
    }
}

private extension UnitType {
    func prefix() -> String {
        switch self {
            case .builtIn:
                return "switch-"
            case .shortcuts:
                return "shortcuts-"
            case .evolution:
                return "evolution-"
        }
    }
}
