//
//  Data++.swift
//  IntentsExtension
//
//  Created by Jacklandrin on 2022/1/3.
//

import Foundation
import UniformTypeIdentifiers

extension Data {
    /**
    Write the data to a unique temporary path and return the `URL`.

    By default, the file has no file extension.
    */
    func writeToUniqueTemporaryFile(
        filename: String = "file",
        contentType: UTType = .data
    ) throws -> URL {
        let destinationUrl = try URL.uniqueTemporaryDirectory()
            .appendingPathComponent(filename, conformingTo: contentType)

        try write(to: destinationUrl)

        return destinationUrl
    }
}
