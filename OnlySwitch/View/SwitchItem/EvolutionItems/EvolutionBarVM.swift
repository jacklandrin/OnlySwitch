//
//  EvolutionBarVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/6/15.
//

import Dependencies
import Foundation
import Switches

@dynamicMemberLookup
class EvolutionBarVM: BarProvider, ObservableObject {

    var barName: String {
        evolutionItem.name
    }

    var controlType: ControlType {
        evolutionItem.controlType
    }

    var iconName: String? {
        evolutionItem.iconName
    }

    var id: String {
        evolutionItem.id.uuidString
    }

    @Published var weight: Int = 0
    @Published var processing = false
    @Published var isOn = false

    @Dependency(\.evolutionCommandService) var evolutionCommandService

    private let evolutionItem: EvolutionItem
    private let refreshSwitchQueue = DispatchQueue(label: "jacklandrin.onlyswitch.refreshswitch",attributes: .concurrent)

    init(evolutionItem: EvolutionItem) {
        self.evolutionItem = evolutionItem
    }

    func refreshAsync() {
        guard evolutionItem.controlType == .Switch else { return }
        self.processing = true
        refreshSwitchQueue.async {
            let _isOn = try? self.evolutionCommandService.executeCommand(self.statusCommand) == self.statusCommand?.trueCondition
            DispatchQueue.main.async {
                self.processing = false
                self.isOn = _isOn ?? false
            }
        }
    }

    func refresh() async {
        guard evolutionItem.controlType == .Switch else { return }
        self.processing = true
        let _isOn = try? self.evolutionCommandService.executeCommand(self.statusCommand) == self.statusCommand?.trueCondition
        self.processing = false
        self.isOn = _isOn ?? false
    }

    func doSwitch(isOn: Bool) {
        processing = true
        Task { @MainActor in
            if isOn {
                if evolutionItem.controlType == .Button {
                    _ = try? self.evolutionCommandService.executeCommand(self.singleCommand)
                } else {
                    _ = try? self.evolutionCommandService.executeCommand(self.onCommand)
                    self.isOn = true
                }
            } else {
                _ = try? self.evolutionCommandService.executeCommand(self.offCommand)
                self.isOn = false
            }
            processing = false
        }
    }

    func doSwitch() {
        evolutionItem.doSwitch()
    }

    subscript<T>(dynamicMember keyPath: KeyPath<EvolutionItem, T>) -> T {
        evolutionItem[keyPath: keyPath]
    }
}
