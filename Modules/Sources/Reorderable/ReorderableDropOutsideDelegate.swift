//
//  ReorderableDropOutsideDelegate.swift
//  Modules
//
//  Created by Jacklandrin on 2024/9/21.
//

import SwiftUI

struct ReorderableDropOutsideDelegate<Item: Reorderable>: DropDelegate {

    @Binding var active: Item?

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        active = nil
        return true
    }
}

public extension View {
    func reorderableForEachContainer<Item: Reorderable>(
        active: Binding<Item?>
    ) -> some View {
        onDrop(of: [.item], delegate: ReorderableDropOutsideDelegate(active: active))
    }
}
