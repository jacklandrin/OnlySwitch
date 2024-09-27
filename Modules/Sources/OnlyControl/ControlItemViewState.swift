//
//  ControlItemReducer.swift
//
//
//  Created by Jacklandrin on 2024/8/24.
//

import AppKit
import Foundation
import Switches
import Defines

public struct ControlItemViewState: Equatable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var weight: Int
    public var unitType: UnitType
    public var status: Bool
    var iconData: Data
    var controlType: ControlType

    public init(
        id: String,
        title: String,
        iconData: Data,
        controlType: ControlType,
        status: Bool = false,
        weight: Int = 0,
        unitType: UnitType = .builtIn
    ) {
        self.id = id
        self.title = title
        self.iconData = iconData
        self.controlType = controlType
        self.status = status
        self.weight = weight
        self.unitType = unitType
    }
}

public extension ControlItemViewState {
    static func preview(id: String = "") -> Self {
        .init(
            id: id,
            title: "Long Long Control Item",
            iconData: NSImage(systemSymbolName: "gear")
                .resizeMaintainingAspectRatio(withSize: NSSize(width: 50, height: 50))!
                .pngData!,
            controlType: .Switch
        )
    }
}
