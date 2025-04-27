//
//  SwitchProtocal.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/30.
//

import Foundation
import Combine

/// protocol for every switch
public protocol SwitchProvider:AnyObject {
    var type: SwitchType { get }
    var delegate: SwitchDelegate? { get set }
    @MainActor func currentStatus() async -> Bool
    @MainActor func currentInfo() async -> String
    @MainActor func operateSwitch(isOn:Bool) async throws
    func isVisible() -> Bool
}


public protocol SwitchDelegate:AnyObject {
    /// switch need to update itself for UI
    func shouldRefreshIfNeed(aSwitch:SwitchProvider)
}
