//
//  ControlItemReducer.swift
//
//
//  Created by Jacklandrin on 2024/8/24.
//

import AppKit
import Foundation
import Switches

public struct ControlItemViewState: Equatable, Hashable, Identifiable {
    public var id: Int
    var title: String
    var iconData: Data
    var type: ControlType
    var status: Bool
    var weight: Int

    public init(
        id: Int = 0,
        title: String,
        iconData: Data,
        type: ControlType,
        status: Bool = false,
        weight: Int = 0
    ) {
        self.id = id
        self.title = title
        self.iconData = iconData
        self.type = type
        self.status = status
        self.weight = weight
    }
}

public extension ControlItemViewState {
    static func preview(id: Int = 0) -> Self {
        .init(
            id: id,
            title: "Long Long Control Item",
            iconData: NSImage(systemSymbolName: "gear")
                .resizeMaintainingAspectRatio(withSize: NSSize(width: 50, height: 50))!
                .pngData!,
            type: .Switch
        )
    }
}
