//
//  ShellCommandDefine.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/29.
//

import Foundation

protocol SwitchCMD {
    static var status:String { get }
    static var on:String { get }
    static var off:String { get }
}

struct HideDesktopCMD:SwitchCMD {
    static var status: String = "defaults read com.apple.finder CreateDesktop"
    static var on: String = "defaults write com.apple.finder CreateDesktop 0; killall Finder"
    static var off: String = "defaults write com.apple.finder CreateDesktop 1; killall Finder"
}

struct DarkModeCMD:SwitchCMD {
    static var status: String = "defaults read -g AppleInterfaceStyle"
    static var on: String = """
                            tell application "System Events"
                                tell appearance preferences
                                    set dark mode to true
                                end tell
                            end tell
                            """
    static var off: String = """
                               tell application "System Events"
                                   tell appearance preferences
                                       set dark mode to false
                                   end tell
                               end tell
                             """
}


let getCurrentWallpaperUrl = "tell app \"finder\" to get posix path of (get desktop picture as alias)"

struct VolumeCMD {
    static let getOutput = "set ovol to output volume of (get volume settings)"
    static let setOutput = "set volume output volume " //+value
    static let getInput = "set ovol to input volume of (get volume settings)"
    static let setInput = "set volume input volume " //+value
}


struct ScreenSaverCMD:SwitchCMD {
    static var status: String = "tell application \"System Events\" to tell screen saver preferences to get delay interval"
    static var on: String = "tell application \"System Events\" to tell screen saver preferences to set delay interval to " // + value
    static var off: String = "tell application \"System Events\" to tell screen saver preferences to set delay interval to 0"
}

struct AutohideDockCMD:SwitchCMD {
    static var status: String = "tell application \"System Events\" to get the autohide of the dock preferences"
    static var on: String = "tell application \"System Events\" to set the autohide of the dock preferences to true"
    static var off: String = "tell application \"System Events\" to set the autohide of the dock preferences to false"
}


struct AutoHideMenuBarCMD:SwitchCMD {
    static var status: String = """
                                    tell application "System Events"
                                        tell dock preferences to get autohide menu bar
                                    end tell
                                """
    static var on: String = """
                                tell application "System Events"
                                    tell dock preferences to set autohide menu bar to true
                                end tell
                            """
    static var off: String = """
                                tell application "System Events"
                                    tell dock preferences to set autohide menu bar to false
                                end tell
                            """
}


struct ShowHiddenFilesCMD:SwitchCMD {
    static var status: String = "defaults read com.apple.Finder AppleShowAllFiles"
    static var on: String = "defaults write com.apple.Finder AppleShowAllFiles true; killall Finder"
    static var off: String = "defaults write com.apple.Finder AppleShowAllFiles false; killall Finder"
}


let emptyTrashCMD = """
                    tell application "Finder"
                        set warns before emptying of trash to false
                        empty trash
                    end tell
                    """

struct ShowExtensionNameCMD:SwitchCMD {
    static var status: String = "defaults read NSGlobalDomain AppleShowAllExtensions"
    static var on: String = "defaults write NSGlobalDomain AppleShowAllExtensions -bool true; killall Finder"
    static var off: String = "defaults write NSGlobalDomain AppleShowAllExtensions -bool false; killall Finder"
}

struct SmallLaunchpadCMD:SwitchCMD {
    static let status: String = "defaults read com.apple.dock springboard-rows"
    static let on: String = """
                        defaults write com.apple.dock springboard-rows -int 6; killall Dock
                        """
    static let off: String = """
                    defaults write com.apple.dock springboard-rows -int 5; killall Dock
                    """
}

struct LowpowerModeCMD:SwitchCMD {
    static let status: String = "pmset -g | grep lowpowermode"
    static let on = "sudo pmset -a lowpowermode 1"
    static let off = "sudo pmset -a lowpowermode 0"
}



struct ShowPathBarCMD:SwitchCMD {
    static let status: String = "defaults read com.apple.finder ShowPathbar"
    static let on: String = "defaults write com.apple.finder ShowPathbar -bool true"
    static let off: String = "defaults write com.apple.finder ShowPathbar -bool false"
}

struct ShowDockRecentCMD:SwitchCMD {
    static var on: String = "defaults write com.apple.dock show-recents -bool true; killall Dock"
    
    static var off: String = "defaults write com.apple.dock show-recents -bool false; killall Dock"
    
    static let status:String = "defaults read com.apple.dock show-recents"
}

struct ShorcutsCMD {
    static let getList = "shortcuts list"
    
    static func runShortcut(name:String) -> String {
        return "shortcuts run \'\(name)\'"
    }
    
    static func showShortcut(name:String) -> String {
        return "shortcuts view \'\(name)\'"
    }
}


func displayNotificationCMD(title:String, content:String, subtitle:String) -> String {
    "display notification \"\(content)\" with title \"\(title)\" subtitle \"\(subtitle)\""
}

func scriptDiskFilePath(scriptName: String) -> String {
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

func directoryExistsAtPath(_ path: String) -> Bool {
    var isDirectory = ObjCBool(true)
    let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
    return exists && isDirectory.boolValue
}

func fileExistAtPath(_ path:String) -> Bool {
    var isDirectory = ObjCBool(false)
    let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
    return exists && isDirectory.boolValue
}



let getAirpodsBatteryShell = "battery-airpods-monterey"

func notificationCMD(content:String, title:String) -> String {
    "display notification \"\(content)\" with title \"\(title)\""
}
