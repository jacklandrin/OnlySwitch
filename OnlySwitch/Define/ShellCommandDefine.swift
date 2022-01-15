//
//  ShellCommandDefine.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/29.
//

import Foundation

let hideDesktopCMD = "defaults write com.apple.finder CreateDesktop 0; killall Finder"
let showDesktopCMD = "defaults write com.apple.finder CreateDesktop 1; killall Finder"
let currentDesktopStatusCMD = "defaults read com.apple.finder CreateDesktop"

let turnOnDarkModeCMD = """
                        tell application "System Events"
                            tell appearance preferences
                                set dark mode to true
                            end tell
                        end tell
                        """

let turnOffDarkModeCMD = """
                           tell application "System Events"
                               tell appearance preferences
                                   set dark mode to false
                               end tell
                           end tell
                        """

let currentInferfaceStyle = "defaults read -g AppleInterfaceStyle"

let getCurrentWallpaperUrl = "tell app \"finder\" to get posix path of (get desktop picture as alias)"
let getDesktopProperties = "tell application \"System Events\" to get properties of every desktop"

let getCurrentOutputVolume = "set ovol to output volume of (get volume settings)"

let setOutputVolumeCMD = "set volume output volume " //+value

let getCurrentInputVolume = "set ovol to input volume of (get volume settings)"

let setInputVolumeCMD = "set volume input volume " //+value

let screenSaverDisableCMD = "tell application \"System Events\" to tell screen saver preferences to set delay interval to 0"
let setSceenSaverIntervalCMD = "tell application \"System Events\" to tell screen saver preferences to set delay interval to "
let getScreenSaverIntervalCMD = "tell application \"System Events\" to tell screen saver preferences to get delay interval"

let getAutohideDockCMD = "tell application \"System Events\" to get the autohide of the dock preferences"
let setAutohideDockEnableCMD = "tell application \"System Events\" to set the autohide of the dock preferences to true"
let setAutohideDockDisableCMD = "tell application \"System Events\" to set the autohide of the dock preferences to false"

let getAutoHideMenuBarCMD = """
                                tell application "System Events"
                                    tell dock preferences to get autohide menu bar
                                end tell
                            """
let setAutohideMenuBarEnableCMD = """
                                    tell application "System Events"
                                        tell dock preferences to set autohide menu bar to true
                                    end tell
                                  """

let setAutohideMenuBarDisableCMD = """
                                        tell application "System Events"
                                            tell dock preferences to set autohide menu bar to false
                                        end tell
                                    """

let getHiddenFilesStateCMD = "defaults read com.apple.Finder AppleShowAllFiles"
let setHiddenFilesShowCMD = "defaults write com.apple.Finder AppleShowAllFiles true; killall Finder"
let setHiddenFilesHideCMD = "defaults write com.apple.Finder AppleShowAllFiles false; killall Finder"

let emptyTrashCMD = """
                    tell application "Finder"
                        set warns before emptying of trash to false
                        empty trash
                    end tell
                    """


let getExtensionNameStateCMD = "defaults read NSGlobalDomain AppleShowAllExtensions"
let showExtensionNameCMD = "defaults write NSGlobalDomain AppleShowAllExtensions -bool true; killall Finder"
let hideExtensionNameCMD = "defaults write NSGlobalDomain AppleShowAllExtensions -bool false; killall Finder"

let getLaunchpadRowCMD = "defaults read com.apple.dock springboard-rows"
let smallLaunchpadIconCMD = """
                            defaults write com.apple.dock springboard-rows -int 6; killall Dock
                            """
let bigLaunchpadIconCMD = """
                            defaults write com.apple.dock springboard-rows -int 5; killall Dock
                            """

let getLowpowerModeCMD = "pmset -g | grep lowpowermode"
let setLowpowerModeCMD = "sudo pmset -a lowpowermode 1"
let unsetLowpowerModeCMD = "sudo pmset -a lowpowermode 0"


let getShortcutsList = "shortcuts list"

let getPathbarStatusCMD = "defaults read com.apple.finder ShowPathbar"
let showPathbarCMD = "defaults write com.apple.finder ShowPathbar -bool true"
let hidePathbarCMD = "defaults write com.apple.finder ShowPathbar -bool false"


func runShortcut(name:String) -> String {
    return "shortcuts run \'\(name)\'"
}

func showShortcut(name:String) -> String {
    return "shortcuts view \'\(name)\'"
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
        guard let localScriptPath =  Bundle.main.path(forResource: scriptName, ofType: "sh") else {return ""}
        guard let _ = try? FileManager.default.createFile(atPath: scriptFilePath, contents: Data(contentsOf: URL(fileURLWithPath: localScriptPath)), attributes: nil) else {
            print("File has not been created at \(scriptFilePath)")
            return ""
        }
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
