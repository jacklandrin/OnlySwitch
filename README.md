![](https://badgen.net/github/release/jacklandrin/onlyswitch)![](https://img.shields.io/badge/UI-SwiftUI-green)   ![](https://img.shields.io/badge/Platform-Monterey-purple)  ![](https://img.shields.io/badge/License-MIT-orange)
<p align="left">
<img alt="AppIcon" src="http://www.jacklandrin.com/wp-content/uploads/2021/12/only_switch_256.png" width="128px" align="center" />
</p>

# OnlySwitch

***Menubar is smaller, you only need an All-in-One switch.***

## Install by Homebrew

```
brew install only-switch
```
## Manually Download
[**Download the app**](https://github.com/jacklandrin/OnlySwitch/releases/download/release_2.1/OnlySwitch.dmg)

## What's the OnlySwitch?
OnlySwitch provides a series of toggle switches to simply your routine work, such as Hiden desktop icons, dark mode and hide notch of new Macbook Pro. The switches show on your statusbar, you can control them effortlessly. Switch and Shortcuts items can be customized to show on the list.

Since Version 1.7, **Shortcuts** can be imported in OnlySwitch.

Since Version 2.0, supports **keyboard shortcuts**. You can control your all switches and Shortcuts by keyboard.
<p align="center">
<img alt="Sits in the status bar" src="https://www.jacklandrin.com/wp-content/uploads/2022/01/onlySwitch_19.png" width="60%" align="center" />
</p>


## Switch list

| Switch                   | status            |
|:-------------------------|-------------------|
| Hide desktop             | finish            |
| Dark mode                | finish            |
| Screen Saver             | finish            |
| Night Shift              | finish            |
| Autohide Dock            | finish            |
| Airpods                  | finish            |
| Bluetooth                | finish            |
| Xcode cache              | finish            |
| Autohide Menu Bar        | finish            |
| Show hidden files        | finish            |
| Radio Station            | finish            |
| Keep awake               | finish            |
| Empty trash              | finish            |
| Empty pasteboard         | finish            |
| Mute                     | finish            |
| Show user library folder | finish            |
| Show extension name      | finish            |
| Pomodoro timer           | finish            |
| Small launchpad icon     | finish            |
| Mute mic                 | finish            |
| Show Finder pathbar      | finish            |
| Low power mode           | require password  |
| Hide notch               | exist some issues |

Since Version 1.3, switches can be added or removed on list.

## Shortcuts Actions

| Actions             | status            |
|---------------------|-------------------|
| Get wallpaper image | exist some issues |
| Get wallpaper url   | finish            |
| is dark mode        | finish            |
| set dark mode       | finish            |

## Supported Languages
English, simplified Chinese, German, Croatian, Turkish

## Welcome to pull request for these

* support Big Sur
* support other languages
* fix bug: radio player crash

If you have other good idea💡, send E-mail to me.

## About hiding new Macbook Notch 

The Hide notch switch only shows on build-in display of M1 Pro/Max Macbook Pro. The switch just controls current desktop, not for all work desktops.
Now, the Hide notch switch supports dynamic wallpaper, just the processing takes much longer time.
## About AirPods Switch 

I use classOfDevice(2360344) to check if a bluetooth device is Airpods Pro, but I'm not sure whether other AirPods modules are also 2360344, since I only have two AriPods Pros. If you are using AirPods 1~3, please tell me what the classOfDevice is. Or I can detect the count of battery value to check if AirPods(when count is 3, it's AirPods), like **AirPods Battery Monitor For MAC OS**.

## About Radio Player
Radio Player supports m3u, acc stream, but without sound wave effect. If your Radio Player crashes, please send the crash log and stream url to me. You can close sound wave effect on Radio setting, and that player is AVPlayer, more stable.

## About Low Power Mode
Low Power Mode uses Terminal commands that require root access, so the app will ask you to enter password on every toggle.

## About Shortcuts
Shortcuts is a powerful iOS app which can help people make fantasitic automation functions. It comes to macOS in Monterey as well. Many users eager OnlySwitch has more customizable features, and one good news is that the app supports Shortcuts display since Version 1.7. More menubar space therefore is saved. 
In the next versions, OnlySwitch will also provide more Shortcuts actions to impove user experience.

Since Version 2.0, keyboard shortcuts can be set for Shortcuts.

<p align="center">
<img alt="Sits in the status bar" src="https://www.jacklandrin.com/wp-content/uploads/2022/01/sharedshortcuts.png" width="60%" align="center" />
</p>

OnlySwitch offers some Shortcus actions since Version 1.8. For example, you can config your own dark mode switch. (**Set Appearance** action by Shortcuts can also set dark mode, but the appearance status cannot be detected. So, OnlySwitch provides a set dark mode action)

<p align="center">
<img alt="Sits in the status bar" src="http://www.jacklandrin.com/wp-content/uploads/2022/01/shortcutsdarkmode.png" width="60%" align="center" />
</p>

## Can't compile preview by Xcode 13.2.1 on some Macs
I found I can't run the preview of SwiftUI by Xcode 13.2.1 on my M1 Pro Macbook. It'll show an error like this https://developer.apple.com/forums/thread/697037. Meanwhile, the OnlySwitch status bar icon will be missing, including old version app. However it's normal that I run it on my i7 Macbook. I'm not sure whether this is a bug of Xcode. The current workaround is installing back to Xcode 13.2.

## Screenshots

<p align="center">
<img alt="Sits in the status bar" src="http://www.jacklandrin.com/wp-content/uploads/2021/12/hidenotch.png" width="60%" align="center" />
</p>

## They talk about it
* German Article - itopnews.de https://www.itopnews.de/?s=OnlySwitch
* Ifun.de https://www.ifun.de/suche/OnlySwitch
* appgefahren.de https://www.appgefahren.de/onlyswitch-kleines-tool-mit-wichtigen-aktionen-fuer-die-mac-menueleiste-312135.html
* CASCHYS BLOG https://stadt-bremerhaven.de/only-switch-fuer-macos-schnellzugriff-auf-einige-systemoptionen/
* softpedia https://mac.softpedia.com/get/System-Utilities/OnlySwitch.shtml
* macupdate https://www.macupdate.com/app/mac/63719/onlyswitch
* v1tx https://www.v1tx.com/post/onlyswitch/
* OSCHINA https://www.oschina.net/p/onlyswitch
* Macken https://www.macken.xyz/2021/12/gratis-ar-gott-alla-installningar-pa-ett-stalle-onlyswitch/
* AAPL Ch https://applech2.com/archives/20220111-onlyswitch-all-in-one-status-bar-button-for-mac.html

## About Apple's warning at first open
Some users ask me why masOS shows a warning box below, when they first open Only Switch.
<p align="center">
<img alt="Sits in the status bar" src="http://www.jacklandrin.com/wp-content/uploads/2021/12/os_warning.png" width="35%" align="center" />
</p>

Because the app isn't got from App Store, and I use some private API in project. You can at [here](https://support.apple.com/guide/mac-help/apple-cant-check-app-for-malicious-software-mchleab3a043/mac) to learn more about it.
You can follow these steps to use Only Switch.
1. Open System Preference
2. Click Security & Privacy
3. Select General
4. Click **Open Anyway**
5. Finally click Open on the dialog box. Now macOS won't block that you open the app.
<p align="center">
<img alt="Sits in the status bar" src="http://www.jacklandrin.com/wp-content/uploads/2021/12/os_tip.png" width="60%" align="center" />
</p>


## Reference

* NightShift switch refer to [Nocturnal](https://github.com/joshjon/nocturnal)
* [LaunchAtLogin](https://github.com/sindresorhus/LaunchAtLogin)
* AirPods Battery refer to [AirPods Battery Monitor For MAC OS](https://github.com/mohamed-arradi/AirpodsBattery-Monitor-For-Mac)
* Dynamic Wallpaper processing refer to https://itnext.io/macos-mojave-dynamic-wallpaper-fd26b0698223 and [wallpapper](https://github.com/mczachurski/wallpapper)
* [AlertToast](https://github.com/elai950/AlertToast)
* [AudioStreamer](https://github.com/syedhali/AudioStreamer) modified for live streaming
* [AudioSpectrum](https://github.com/potato04/AudioSpectrum) modified for Appkit
* [Alamofire](https://github.com/Alamofire/Alamofire)
* Sound Source: [mixkit](https://mixkit.co)
* [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)

## Contributors

@C0d3Br3aker for German translation

@milotype for Croatian translation

@berkbatuhans for Turkish translation

@wrngwrld for volume slider of radio player

## License
MIT
## Donate
If you like it, help supporting this app by giving me a cup of tea in order for me to keep coding.
<p align="center">
<img alt="Sits in the status bar" src="http://www.jacklandrin.com/wp-content/uploads/2021/12/donation.jpeg" width="20%" align="left" title="Made by QRCobot"/>
</p>
