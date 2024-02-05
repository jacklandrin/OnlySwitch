//
//  ShellCommandDefine.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/29.
//

import Foundation
import Extensions

public protocol SwitchCMD {
    static var status:String { get }
    static var on:String { get }
    static var off:String { get }
}

public struct HideDesktopCMD:SwitchCMD {
    public static var status: String = "defaults read com.apple.finder CreateDesktop"
    public static var on: String = "defaults write com.apple.finder CreateDesktop 0; killall Finder"
    public static var off: String = "defaults write com.apple.finder CreateDesktop 1; killall Finder"
}

public struct DarkModeCMD:SwitchCMD {
    public static var status: String = "defaults read -g AppleInterfaceStyle"
    public static var status_applescript = """
                                    tell application "System Events"
                                        tell appearance preferences to get dark mode
                                    end tell
                                    """
    public static var on: String = """
                            tell application "System Events"
                                tell appearance preferences
                                    set dark mode to true
                                end tell
                            end tell
                            """
    
    public static var off: String = """
                               tell application "System Events"
                                   tell appearance preferences
                                       set dark mode to false
                                   end tell
                               end tell
                             """
}


public let getCurrentWallpaperUrl = "tell app \"finder\" to get posix path of (get desktop picture as alias)"

public struct VolumeCMD {
    public static let getOutput = "set ovol to output volume of (get volume settings)"
    public static let setOutput = "set volume output volume " //+value
    public static let getInput = "set ovol to input volume of (get volume settings)"
    public static let setInput = "set volume input volume " //+value
}


public struct ScreenSaverCMD:SwitchCMD {
    public static var status: String = "tell application \"System Events\" to tell screen saver preferences to get delay interval"
    public static var on: String = "tell application \"System Events\" to tell screen saver preferences to set delay interval to " // + value
    public static var off: String = "tell application \"System Events\" to tell screen saver preferences to set delay interval to 0"
}

public struct AutohideDockCMD:SwitchCMD {
    public static var status: String = "tell application \"System Events\" to get the autohide of the dock preferences"
    public static var on: String = "tell application \"System Events\" to set the autohide of the dock preferences to true"
    public static var off: String = "tell application \"System Events\" to set the autohide of the dock preferences to false"
}


public struct AutoHideMenuBarCMD:SwitchCMD {
    public static var status: String = """
                                    tell application "System Events"
                                        tell dock preferences to get autohide menu bar
                                    end tell
                                """
    public static var on: String = """
                                tell application "System Events"
                                    tell dock preferences to set autohide menu bar to true
                                end tell
                            """
    public static var off: String = """
                                tell application "System Events"
                                    tell dock preferences to set autohide menu bar to false
                                end tell
                            """
}


public struct ShowHiddenFilesCMD:SwitchCMD {
    public static var status: String = "defaults read com.apple.Finder AppleShowAllFiles"
    public static var on: String = "defaults write com.apple.Finder AppleShowAllFiles true; killall Finder"
    public static var off: String = "defaults write com.apple.Finder AppleShowAllFiles false; killall Finder"
}


public let emptyTrashCMD = """
                    tell application "Finder"
                        set warns before emptying of trash to false
                        empty trash
                    end tell
                    """

public struct ShowExtensionNameCMD:SwitchCMD {
    public static var status: String = "defaults read NSGlobalDomain AppleShowAllExtensions"
    public static var on: String = "defaults write NSGlobalDomain AppleShowAllExtensions -bool true; killall Finder"
    public static var off: String = "defaults write NSGlobalDomain AppleShowAllExtensions -bool false; killall Finder"
}

public struct SmallLaunchpadCMD:SwitchCMD {
    public static let status: String = "defaults read com.apple.dock springboard-rows"
    public static let on: String = """
                        defaults write com.apple.dock springboard-rows -int 6; killall Dock
                        """
    public static let off: String = """
                    defaults write com.apple.dock springboard-rows -int 5; killall Dock
                    """
}

public struct LowpowerModeCMD:SwitchCMD {
    public static let status: String = "pmset -g | grep lowpowermode"
    public static let on = "sudo pmset -a lowpowermode 1"
    public static let off = "sudo pmset -a lowpowermode 0"
}



public struct ShowPathBarCMD:SwitchCMD {
    public static let status: String = "defaults read com.apple.finder ShowPathbar"
    public static let on: String = "defaults write com.apple.finder ShowPathbar -bool true"
    public static let off: String = "defaults write com.apple.finder ShowPathbar -bool false"
}

public struct ShowDockRecentCMD:SwitchCMD {
    public static var on: String = "defaults write com.apple.dock show-recents -bool true; killall Dock"

    public static var off: String = "defaults write com.apple.dock show-recents -bool false; killall Dock"

    public static let status:String = "defaults read com.apple.dock show-recents"
}

public struct ShorcutsCMD {
    public static let getList = "shortcuts list"

    public static func runShortcut(name:String) -> String {
        return "shortcuts run \'\(name)\'"
    }
    
    public static func showShortcut(name:String) -> String {
        return "shortcuts view \'\(name)\'"
    }
}


public func displayNotificationCMD(title:String, content:String, subtitle:String) -> String {
    "display notification \"\(content)\" with title \"\(title)\" subtitle \"\(subtitle)\""
}

public func scriptDiskFilePath(scriptName: String) -> String {
    let appBundleID = Bundle.main.infoDictionary?["CFBundleName"] as! String
    let appDirectory = "\(appBundleID)/script"
    guard let scriptFileURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
        return ""
    }
    
    let scriptDirectoryPath = "\(scriptFileURL)\(appDirectory)".replacingOccurrences(of: "file://", with: "")
    let scriptDirectoryURL = URL(fileURLWithPath: scriptDirectoryPath, isDirectory: true)
    let scriptFilePath = scriptDirectoryPath.appendingPathComponent(string: "\(scriptName).sh")
    if !fileExistAtPath(scriptDirectoryPath) {
        if !directoryExistsAtPath(scriptDirectoryPath) {
            guard let _ = try? FileManager.default.createDirectory(at: scriptDirectoryURL, withIntermediateDirectories: true) else {
                print("directory should be created and permissions allowed")
                return ""
            }
        }
    }
    guard let localScriptPath =  Bundle.main.path(forResource: scriptName, ofType: "sh") else {return ""}
    guard let _ = try? FileManager.default.createFile(atPath: scriptFilePath, contents: Data(contentsOf: URL(fileURLWithPath: localScriptPath)), attributes: nil) else {
        print("File has not been created at \(scriptFilePath)")
        return ""
    }
    return scriptFilePath
}

public func directoryExistsAtPath(_ path: String) -> Bool {
    var isDirectory = ObjCBool(true)
    let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
    return exists && isDirectory.boolValue
}

public func fileExistAtPath(_ path:String) -> Bool {
    var isDirectory = ObjCBool(false)
    let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
    return exists && isDirectory.boolValue
}

public let getAirpodsBatteryShell = "battery-airpods-monterey"

public func notificationCMD(content:String, title:String) -> String {
    "display notification \"\(content)\" with title \"\(title)\""
}

public let ejectDiscs = "tell application \"Finder\" to eject (every disk whose ejectable is true)"
