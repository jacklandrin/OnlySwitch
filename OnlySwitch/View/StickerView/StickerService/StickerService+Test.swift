//
//  StickerService+Test.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/10/29.
//

import Dependencies
import Foundation
import XCTestDynamicOverlay

extension StickerService: TestDependencyKey {
    static let testValue = Self(
        saveSticker: unimplemented("\(Self.self).saveSticker"),
        loadSticker: unimplemented("\(Self.self).loadSticker")
    )
}
