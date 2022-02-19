//
//  File.swift
//  MusicPlayer
//
//  Created by Miklós Kristyán on 2017. 12. 09..
//  Copyright © 2017. KM. All rights reserved.
//

import Foundation
import ScriptingBridge

@objc public protocol SBObjectProtocol: NSObjectProtocol {
    func get() -> Any!
}

@objc public protocol SBApplicationProtocol: SBObjectProtocol {
    func activate()
    var delegate: SBApplicationDelegate! { get set }
    @objc optional var isRunning: Bool { get }
}
