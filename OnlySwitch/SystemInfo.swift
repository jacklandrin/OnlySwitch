//
//  SystemInfo.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/5.
//

import Foundation
struct SystemInfo{
    static let infoDictionary = Bundle.main.infoDictionary
    static var appDisplayName:AnyObject? {
        infoDictionary!["CFBundleDisplayName"] as AnyObject //app name
    }
    static var majorVersion :AnyObject? {
        infoDictionary!["CFBundleShortVersionString"] as AnyObject//major version
    }
    static var minorVersion :AnyObject? {
        infoDictionary!["CFBundleVersion"] as AnyObject//build version
    }
    //device information
    static let isiOSAppOnMac = ProcessInfo.processInfo.isiOSAppOnMac
}
