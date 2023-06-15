//
//  EvolutionBarVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/6/15.
//

import Foundation

class EvolutionBarVM: BarProvider, ObservableObject {

    var barName: String {
        evolutionItem.name
    }

    var controlType: ControlType {
        evolutionItem.controlType
    }

    @Published var weight: Int = 0
    @Published var processing = false
    @Published var isOn = false

    private let evolutionItem: EvolutionItem
    private let refreshSwitchQueue = DispatchQueue(label: "jacklandrin.onlyswitch.refreshswitch",attributes: .concurrent)

    init(evolutionItem: EvolutionItem) {
        self.evolutionItem = evolutionItem
    }

    func refreshAsync() {
        self.processing = true
        refreshSwitchQueue.async {
            guard let command = self.evolutionItem.statusCommand else { return }
            let _isOn = try? command.commandString.runAppleScript(isShellCMD: command.executeType == .shell) == command.trueCondition
            DispatchQueue.main.async {
                self.processing = false
                self.isOn = _isOn ?? false
            }
        }
    }

    func doSwitch(isOn: Bool) {
        processing = true
        if isOn {
            if evolutionItem.controlType == .Button {
                guard let command = evolutionItem.singleCommand else { return }
                _ = try? command.commandString.runAppleScript(isShellCMD: command.executeType == .shell)
            } else {
                guard let command = evolutionItem.onCommand else { return }
                _ = try? command.commandString.runAppleScript(isShellCMD: command.executeType == .shell)
            }
        } else {
            guard let command = evolutionItem.offCommand else { return }
            _ = try? command.commandString.runAppleScript(isShellCMD: command.executeType == .shell)
        }
        processing = false
    }
}
