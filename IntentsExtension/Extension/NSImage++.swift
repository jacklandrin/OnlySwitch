//
//  NSImage++.swift
//  IntentsExtension
//
//  Created by Jacklandrin on 2022/1/3.
//

import AppKit
import Intents

extension NSImage {
    var toINFile:INFile? {
        try? tiffRepresentation?
            .writeToUniqueTemporaryFile(contentType: .tiff)
            .toINFile
    }
}
