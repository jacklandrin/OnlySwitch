//
//  ShellCommandDefine.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/29.
//

import Foundation

let hiddleDesktopCMD = "defaults write com.apple.finder CreateDesktop 0; killall Finder"
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

let getCurrentVolume = "set ovol to output volume of (get volume settings)"

let setOutputVolumeCMD = "set volume output volume " //+value
