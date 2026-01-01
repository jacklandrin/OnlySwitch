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
    convenience init(hex: String, alpha: CGFloat = 1.0) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0

        self.init(calibratedRed: r, green: g, blue: b, alpha: alpha)
    }

    static let themePink = NSColor(hex: "#FC46AE")
    static let themeBlue = NSColor(hex: "#316FDB")
    static let themePurple = NSColor(hex: "#6475ED")
    static let themeLightPink = NSColor(hex: "#E3645A")
    static let themeGreen = NSColor(hex: "#8AA440")
    static let themeFountainBlue = NSColor(hex: "#73C8D2")
    static let themeLila = NSColor(hex: "#BB8ED0")
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
                return NSColor(hex: "#FDF5A6")
            case .blue:
                return NSColor(hex: "#BDF2FD")
            case .green:
                return NSColor(hex: "#C2FDAA")
            case .pink:
                return NSColor(hex: "#F7C9C8")
            case .purple:
                return NSColor(hex: "#BAC9FB")
            case .gray:
                return NSColor(hex: "#EEEEEE")
        }
    }

    var stroke: NSColor {
        switch self {
            case .yellow:
                return NSColor(hex: "#392705", alpha: 0.4)
            case .blue:
                return NSColor(hex: "#092635", alpha: 0.4)
            case .green:
                return NSColor(hex: "#072704", alpha: 0.4)
            case .pink:
                return NSColor(hex: "#1E0520", alpha: 0.4)
            case .purple:
                return NSColor(hex: "#180637", alpha: 0.4)
            case .gray:
                return NSColor(hex: "#232323", alpha: 0.4)
        }
    }

    var bar: NSColor {
        switch self {
            case .yellow:
                return NSColor(hex: "#F8D841")
            case .blue:
                return NSColor(hex: "#4E86BE")
            case .green:
                return NSColor(hex: "#10EB15")
            case .pink:
                return NSColor(hex: "#DC5ADA")
            case .purple:
                return NSColor(hex: "#7B54B0")
            case .gray:
                return NSColor(hex: "#9B9B9B")
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
