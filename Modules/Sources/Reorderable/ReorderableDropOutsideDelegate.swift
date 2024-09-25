//
//  ReorderableDropOutsideDelegate.swift
//  Modules
//
//  Created by Jacklandrin on 2024/9/21.
//

import SwiftUI

struct ReorderableDropOutsideDelegate<Item: Reorderable>: DropDelegate {

    @Binding var active: Item?
    var onEnded: () -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        active = nil
        onEnded()
        return true
    }
}

public extension View {
    func reorderableForEachContainer<Item: Reorderable>(
        active: Binding<Item?>,
        onEnded: @escaping () -> Void
    ) -> some View {
        onDrop(of: [.item], delegate: ReorderableDropOutsideDelegate(active: active, onEnded: onEnded))
    }
}
