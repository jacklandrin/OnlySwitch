//
//  RequestError.swift
//  OnlySwitchTests
//
//  Created by Jacklandrin on 2022/5/19.
//

import Foundation

enum RequestError:Error {
    case failed
    case notReachable
    case invalidURL
    case analyseModelFailed
}
