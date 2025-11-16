//
//  AICommanderSwitch.swift
//  OnlySwitch
//
//  Created by Bo Liu on 16.11.25.
//

import Switches
import Defines
import OnlyAgent

final class AICommanderSwitch: SwitchProvider {
    weak var delegate: SwitchDelegate?
    var type: SwitchType = .aiCommender
    
    @MainActor
    func currentStatus() async -> Bool {
        true
    }
    
    @MainActor
    func currentInfo() async -> String {
        ""
    }
    
    @MainActor
    func operateSwitch(isOn: Bool) async throws {
        if #available(macOS 26.0, *) {
            let generater = try AgentCommandGenerater(modelProvider: "Ollama")
            try await generater.execute(description: "Switch to dark mode", model: "qwen3:30b")
        }
    }
    
    func isVisible() -> Bool {
        if #available(macOS 26.0, *) {
            return true
        }
        return false
    }
}
