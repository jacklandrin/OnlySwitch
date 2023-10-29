//
//  ColorDefine.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/1/17.
//

import Foundation
import SwiftUI
import AppKit

extension NSColor {
    static let themePink = NSColor(calibratedRed: 252/255, green: 70/255, blue: 174/255, alpha: 1)
    static let themeBlue = NSColor(calibratedRed: 49/255, green: 111/255, blue: 219/255, alpha: 1)
    static let themePurple = NSColor(calibratedRed: 100/255, green: 117/255, blue: 237/255, alpha: 1)
    static let themeLightPink = NSColor(calibratedRed: 227/255, green: 100/255, blue: 90/255, alpha: 1)
    static let themeGreen = NSColor(calibratedRed: 138/255, green: 164/255, blue: 64/255, alpha: 1)
}

protocol StickerColorConfiguration {
    var content: NSColor { get }
    var stroke: NSColor { get }
    var bar: NSColor { get }
    var name: String { get }
}

enum StickerColor: StickerColorConfiguration, CaseIterable {
    var content: NSColor {
        switch self {
            case .yellow:
                return NSColor(calibratedRed: 253/255, green: 245/255, blue: 166/255, alpha: 1)
            case .blue:
                return NSColor(calibratedRed: 189/255, green: 242/255, blue: 253/255, alpha: 1)
            case .green:
                return NSColor(calibratedRed: 194/255, green: 253/255, blue: 170/255, alpha: 1)
            case .pink:
                return NSColor(calibratedRed: 247/255, green: 201/255, blue: 200/255, alpha: 1)
            case .purple:
                return NSColor(calibratedRed: 186/255, green: 201/255, blue: 251/255, alpha: 1)
            case .gray:
                return NSColor(calibratedRed: 238/255, green: 238/255, blue: 238/255, alpha: 1)
        }
    }

    var stroke: NSColor {
        switch self {
            case .yellow:
                return NSColor(calibratedRed: 57/255, green: 39/255, blue: 5/255, alpha: 0.4)
            case .blue:
                return NSColor(calibratedRed: 9/255, green: 38/255, blue: 53/255, alpha: 0.4)
            case .green:
                return NSColor(calibratedRed: 7/255, green: 39/255, blue: 4/255, alpha: 0.4)
            case .pink:
                return NSColor(calibratedRed: 30/255, green: 5/255, blue: 32/255, alpha: 0.4)
            case .purple:
                return NSColor(calibratedRed: 24/255, green: 6/255, blue: 55/255, alpha: 0.4)
            case .gray:
                return NSColor(calibratedRed: 35/255, green: 35/255, blue: 35/255, alpha: 0.4)
        }
    }

    var bar: NSColor {
        switch self {
            case .yellow:
                return NSColor(calibratedRed: 248/255, green: 216/255, blue: 65/255, alpha: 1)
            case .blue:
                return NSColor(calibratedRed: 78/255, green: 134/255, blue: 190/255, alpha: 1)
            case .green:
                return NSColor(calibratedRed: 16/255, green: 235/255, blue: 21/255, alpha: 1)
            case .pink:
                return NSColor(calibratedRed: 220/255, green: 90/255, blue: 218/255, alpha: 1)
            case .purple:
                return NSColor(calibratedRed: 123/255, green: 84/255, blue: 176/255, alpha: 1)
            case .gray:
                return NSColor(calibratedRed: 155/255, green: 155/255, blue: 155/255, alpha: 1)
        }
    }

    var name: String {
        switch self {
            case .yellow:
                return "yellow"
            case .blue:
                return "blue"
            case .green:
                return "green"
            case .pink:
                return "pink"
            case .purple:
                return "purple"
            case .gray:
                return "gray"
        }
    }

    static func generateColor(from name: String) -> Self {
        switch name {
            case "yellow":
                return .yellow
            case "blue":
                return .blue
            case "green":
                return .green
            case "pink":
                return .pink
            case "purple":
                return .purple
            case "gray":
                return .gray
            default:
                return .yellow
        }
    }

    case yellow
    case blue
    case green
    case pink
    case purple
    case gray
}
