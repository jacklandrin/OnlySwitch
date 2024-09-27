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
        case dashboardAction(DashboardReducer.Action)
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
                        refreshDashboard(),
                        .publisher {
                            NotificationCenter.default.publisher(for: .refreshSingleSwitchStatus)
                                .compactMap {
                                    if let type = $0.object as? SwitchType {
                                        return .refreshSingleSwitchType(type)
                                    } else {
                                        return nil
                                    }
                                }
                        }
                    )

                case .refreshDashboard:
                    return refreshDashboard()

                case .refreshSingleSwitchType(let type):
                    guard let switchControl = state.switchList.first(where: { $0.switchType == type}) else {
                        return .none
                    }

                    return .run { [state, switchControl] send in
                        let isOn = await switchControl.switchOperator.currentStatusAsync()
                        if var item = state.dashboard.items.first(where: { $0.id == switchControl.id }) {
                            item.status = isOn
                            await send(.updateItem(item))
                        }
                    }

                case .showControl:
                    state.blurRadius = 0
                    state.opacity = 1
                    return .none

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
            }
        }
    }

    private func refreshDashboard() -> EffectOf<Self> {
        .run { send in
            let switches = client.fetchSwitchList()
            for switchControl in switches {
                let isOn = await switchControl.switchOperator.currentStatusAsync()
                switchControl.isOn = isOn
            }
            let shortcuts = client.fetchShortcutsList()
            let evolutions = client.fetchEvolutionList()
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
                    let image = switchVM.onImage ?? NSImage(named: "shortcuts_icon")!

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
