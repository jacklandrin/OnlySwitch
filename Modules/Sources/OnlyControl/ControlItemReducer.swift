//
//  ControlItemReducer.swift
//
//
//  Created by Jacklandrin on 2024/8/24.
//

import AppKit
import ComposableArchitecture
import Foundation
import Switches

@Reducer
public struct ControlItemReducer {
    @ObservableState
    public struct State: Equatable, Hashable, Identifiable {
        public var id: Int
        var title: String
        var iconData: Data
        var type: ControlType
        var status: Bool

        public init(
            id: Int = 0,
            title: String,
            iconData: Data,
            type: ControlType,
            status: Bool = false
        ) {
            self.id = id
            self.title = title
            self.iconData = iconData
            self.type = type
            self.status = status
        }
    }

    public enum Action: Equatable {
        case didTap
        case delegate(Delegate)

        public enum Delegate: Equatable {
            case didTap
        }
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
                case .didTap:
                    if state.type == .Switch {
                        state.status.toggle()
                    }
                    
                    return .none
                case .delegate(.didTap):
                    return .none
            }
        }
    }
}

public extension ControlItemReducer {
    static func preview(id: Int = 0) -> ControlItemReducer.State {
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
