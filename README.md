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
[**Download the app**](https://github.com/jacklandrin/OnlySwitch/releases/download/release_2.3.5/OnlySwitch.dmg)

## What's the OnlySwitch?
OnlySwitch provides a series of toggle switches to simplify your routine work, such as Hidden desktop icons, dark mode, and hide notch of the new Macbook Pro. The switches show on your status bar, you can control them effortlessly. Switch and Shortcuts items can be customized (remove/add or sort) to show on the list.

Since Version 1.7, **Shortcuts** can be imported into OnlySwitch.

Since Version 2.0, supports **keyboard shortcuts**. You can control your all switches and Shortcuts by the keyboard.

<p align="center">
<img alt="Sits in the status bar" src="https://www.jacklandrin.com/wp-content/uploads/2022/01/onlySwitch_19.png" width="60%" align="center" />
</p>

## Shortcuts Gallery

Everyone can contribute macOS Shortcuts for OnlySwitch now. Please read [How to contribute for Shortcuts Gallery](ShortcutsGalleryContributing.md). The shared Shortcuts will be displayed here:

<p align="center">
<img alt="Sits in the status bar" src="https://www.jacklandrin.com/wp-content/uploads/2022/01/shortcutsgallery.png" width="60%" align="center" />
</p>

## Switch list

| Switch            | status          | Switch                   | status            |
|:------------------|-----------------|:-------------------------|:------------------|
| Hide desktop      | finished        | Hide notch               | exist some issues |
| Dark mode         | finished        | Low power mode           | require password  |
| Screen Saver      | finished        | Show Finder Path Bar     | finished          |
| Night Shift       | finished        | Mute mic                 | finished          |
| Autohide Dock     | finished        | Small launchpad icon     | finished          |
| Airpods           | finished        | Pomodoro timer           | finished          |
| Bluetooth         | finished        | Show extension name      | finished          |
| Xcode cache       | finished        | Show user library folder | finished          |
| Autohide Menu Bar | finished        | Mute                     | finished          |
| Show hidden files | finished        | Empty pasteboard         | finished          |
| Radio Station     | finished        | Empty trash              | finished          |
| Keep awake        | finished        | Show Recent Apps on Dock | finished          |
| Spotify           | finished        | Apple Music              | finished          |
| Screen Test       | partly finished | Hide Menu Bar Icons      | partly finished   |

Since Version 1.3, switches can be added to or removed from the list.

## Shortcuts Actions

| Actions             | status            |
|---------------------|-------------------|
| Get wallpaper image | exist some issues |
| Get wallpaper url   | finished          |
| Is dark mode        | finished          |
| Set dark mode       | finished          |

## Supported Languages
English, Simplified Chinese, German, Croatian, Turkish, Polish, Filipino, Dutch, Italian, Russian, Spanish, Japanese, Somali

## Welcome to pull request for these

* support Big Sur
* support other languages
* fix bug: radio player crash

If you have other good ideas 💡, feel free to send an E-mail to me.

## About hiding new Macbook Notch 

The Hide notch switch only shows on the built-in display of M1 Pro/Max Macbook Pro. The switch just controls the current desktop, not for all work desktops.
Now, the Hide notch switch supports dynamic wallpaper, just the processing takes a much longer time.
## About AirPods Switch 

I use `classOfDevice`(2360344) to check if a Bluetooth device is Airpods Pro, but I'm not sure whether other AirPods modules are also 2360344, since I only have two AirPods Pros. If you are using AirPods 1~3, please tell me what the `classOfDevice` is. Or I can detect the count of battery value to check if AirPods (when the count is 3, it's AirPods), like **AirPods Battery Monitor For MAC OS**.

## About Radio Player
Radio Player supports m3u, and aac stream, but without sound wave effect. If your Radio Player crashes, please send the crash log and stream URL to me. You can close the sound wave effect on the Radio setting, and that player is AVPlayer, more stable. In version 2.3.5, the radio play can be set to enable/disabled. If the function is disabled, the switch will be invisible in the list, and the radio player will be unregistered from Now Playing.

## About Low Power Mode
Low Power Mode uses Terminal commands that require root access, so the app will ask you to enter the password on every toggle.

## About Screen Test
In Version 2.3, Only Switch brings a new feature, Screen Test. It provides a pure color view in full-screen mode, you can check dead pixels via it. Press the left and right arrow keys, the color will change from black, white, red, green, and blue. This function also can be used for screen cleaning, as you can clearly see the stains on the screen.

## About Hide Menu Bar Icons
This feature is new in version 2.3.2. To be honest, Hidden and Dozer are both good apps for this function. Many users install OnlySwitch and them simultaneously, but this also squeezes the menu bar, which is already lacking in space. Therefore, the feature integrates into OnlySwitch.
![](https://www.jacklandrin.com/wp-content/uploads/2022/06/mark_icon_guide.png)
When the switch is on, items on the left of the split(arrow-pointing) icon are hidden. Hold ⌘ (command) and drag the icon to configure the hidden section. If you want to use it no longer, you can disable it in preferences, the split icon will disappear. You also can set the interval of autohide for it here.

## About Shortcuts
Shortcuts is a powerful iOS app that can help people make fantastic automation functions. It comes to macOS in Monterey as well. Many users are eager OnlySwitch to have more customizable features, and one good news is that the app supports Shortcuts display since Version 1.7. More menubar space, therefore, is saved. 
In the next versions, OnlySwitch will also provide more Shortcuts actions to improve user experience.

Since Version 2.0, keyboard shortcuts can be set for Shortcuts.

OnlySwitch offers some Shortcuts actions since Version 1.8. For example, you can config your own dark mode switch. (**Set Appearance** action by Shortcuts can also set dark mode, but the appearance status cannot be detected. So, OnlySwitch provides a set dark mode action)

<p align="center">
<img alt="Sits in the status bar" src="http://www.jacklandrin.com/wp-content/uploads/2022/01/shortcutsdarkmode.png" width="60%" align="center" />
</p>

## Screenshots

<p align="center">
<img alt="Sits in the status bar" src="http://www.jacklandrin.com/wp-content/uploads/2021/12/hidenotch.png" width="60%" align="center" />
</p>

## They talk about it

|                                                                                                                                 |                                                                                                        |                                                                                                                                  |                                                                                                               |
|---------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------|:--------------------------------------------------------------------------------------------------------------|
| [German Article - itopnews.de](https://www.itopnews.de/?s=OnlySwitch)                                                           | [Ifun.de](https://www.ifun.de/suche/OnlySwitch)                                                        | [appgefahren.de](https://www.appgefahren.de/onlyswitch-kleines-tool-mit-wichtigen-aktionen-fuer-die-mac-menueleiste-312135.html) | [CASCHYS BLOG](https://stadt-bremerhaven.de/only-switch-fuer-macos-schnellzugriff-auf-einige-systemoptionen/) |
| [softpedia](https://mac.softpedia.com/get/System-Utilities/OnlySwitch.shtml)                                                    | [macupdate](https://www.macupdate.com/app/mac/63719/onlyswitch)                                        | [v1tx](https://www.v1tx.com/post/onlyswitch/)                                                                                    | [OSCHINA](https://www.oschina.net/p/onlyswitch)                                                               |
| [Macken](https://www.macken.xyz/2021/12/gratis-ar-gott-alla-installningar-pa-ett-stalle-onlyswitch/)                            | [AAPL Ch](https://applech2.com/archives/20220111-onlyswitch-all-in-one-status-bar-button-for-mac.html) | [appsofter](https://appsofter.com/download/1265.html)                                                                            | [lifehacker](https://lifehacker.ru/onlyswitch)                                                                |
| [appletechnikblog](https://appletechnikblog.com/de/2022/02/25/app-tipp-der-woche-only-switch-fuer-die-menueleiste-auf-dem-mac/) | [All-in-One person](https://en.blog.themarfa.name/how-to-quickly-manage-macos-system-settings/)        | [Mac Gadget](https://www.macgadget.de/News/2022/03/24/OnlySwitch-Schnellzugriff-auf-viele-Systemfunktionen-per-Mac-Menueleiste)  | [MaxiApple](https://www.maxiapple.com/2022/05/onlyswitch-macos-mac-gratuit.html)                              |
| [insmac](https://insmac.org/macosx/5018-onlyswitch.html)                                                                        | [tchgdns](https://tchgdns.de/onlyswitch-macos-open-source/)                                            |                                                                                                                                  |                                                                                                               |


## Reference

* NightShift switch refer to [Nocturnal](https://github.com/joshjon/nocturnal)
* [LaunchAtLogin](https://github.com/sindresorhus/LaunchAtLogin)
* AirPods Battery refers to [AirPods Battery Monitor For MAC OS](https://github.com/mohamed-arradi/AirpodsBattery-Monitor-For-Mac)
* Dynamic Wallpaper processing refer to https://itnext.io/macos-mojave-dynamic-wallpaper-fd26b0698223 and [wallpapper](https://github.com/mczachurski/wallpapper)
* [AlertToast](https://github.com/elai950/AlertToast)
* [AudioStreamer](https://github.com/syedhali/AudioStreamer) modified for live streaming
* [AudioSpectrum](https://github.com/potato04/AudioSpectrum) modified for Appkit
* [Alamofire](https://github.com/Alamofire/Alamofire)
* Sound Source: [mixkit](https://mixkit.co)
* [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)
* Apple Music & Spotify Switch refer to [SpotMenu](https://github.com/kmikiy/SpotMenu)
* The idea of hiding menu bar icons from [Hidden](https://github.com/dwarvesf/hidden)

## Contributors

@C0d3Br3aker for German translation

@milotype for Croatian translation

@berkbatuhans for Turkish translation

@wrngwrld for volume slider of the radio player

@kpacholak for Polish translation

Alex for Dutch translation

Rosel for Filipino translation

@bellaposa for Italian translation

@kirillyakopov for Russian translation

@kant for syntax issue and Spanish translation

@ShogoKoyama for Japanese translation

@abdorizak for Somali translation

## Telegram group
https://t.me/OnlySwitchforMac

## License
MIT
## Donate
If you like it, help support this app by giving me a cup of tea in order for me to keep coding.
<p align="center">
<img alt="Sits in the status bar" src="http://www.jacklandrin.com/wp-content/uploads/2021/12/donation.jpeg" width="20%" align="left" title="Made by QRCobot"/>
</p>
