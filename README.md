![](https://badgen.net/github/release/jacklandrin/onlyswitch) ![](https://img.shields.io/badge/UI-SwiftUI-green)
[![Listed on TakoAPI](https://takoapi.com/api/badge/jacklandrin-onlyswitch)](https://takoapi.com/agents/jacklandrin-onlyswitch)
![](https://img.shields.io/badge/Platform-Tahoe-blue)
  ![](https://img.shields.io/badge/License-MIT-orange)
<p align="middle">
    <a href="https://onlyswitch.click">
        <img alt="AppIcon" src="https://github.com/jacklandrin/OnlySwitch/blob/main/OnlySwitch/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png?raw=true" width="128px" align="center" />
    </a>
</p>

‼️ **Auto-updating has failed from 2.5.6 and below, please manually update or use Homebrew.**

# OnlySwitch

***Menubar is smaller, you only need an All-in-One switch.***

## Install by Homebrew

```
brew install only-switch
```
## Manually Download
[**Download the app**](https://github.com/jacklandrin/OnlySwitch/releases/latest/download/OnlySwitch.dmg)

## Communities
Telegram group: https://t.me/OnlySwitchforMac

Discord: https://discord.gg/UzSNpYdPZj

## OnlyRemote for iPhone and iPad

Control OnlySwitch from your iPhone or iPad over your local network. Download [OnlyRemote on the App Store](https://apps.apple.com/us/app/onlyremote/id6793657946), then open **iOS Remote** in OnlySwitch settings to enable remote access and pair your device.
<p align="center">
<img alt="05-organized-controls-ipad-13" src="https://github.com/user-attachments/assets/8cbba2ca-ff02-4600-9c6f-265fd91d1d67"  width="70%" align="center" />
</p>

## What's the OnlySwitch?
OnlySwitch provides a series of toggle switches to simplify your routine work, such as Hidden desktop icons, dark mode, and hide notch of the new Macbook Pro. The switches show on your status bar, you can control them effortlessly. Switch and Shortcuts items can be customized (remove/add or sort) to show on the list. These functionalities even can be put on your desktop as Widgets.

## Milestones

Since Version 1.7, **Shortcuts** can be imported into OnlySwitch.

Since Version 2.0, supports **keyboard shortcuts**. You can control your all switches and Shortcuts with the keyboard.

<p align="center">
<img alt="Only Switch" src="https://github.com/user-attachments/assets/40d94175-6487-4c59-b09e-2261ac5b8453" width="80%" align="center" />
</p>

Since Version 2.3.6, the Switches Availability (including Player and Hide Menu Bar Icons) is moved to System's menu bar.

![](https://github.com/jacklandrin/OnlySwitch/assets/3782279/11c89e33-2007-4913-b320-47c188538b68)

Since Version 2.5.0, OnlySwitch has started to support **Apple Widgets** (Sonoma and above).

Since Version 2.5.4, OnlySwitch has Only Control appearance.

Since Version 2.7.0, OnlySwitch includes an optional **Desktop Pet**: a small, always-on-top desktop companion. Enable it in General settings, drag it anywhere on screen, and click it to show or dismiss Only Control.

<p align="center">
<img width="152" height="188" alt="desktop pet" src="https://github.com/user-attachments/assets/f45e4b4f-932e-4768-8bfd-845e22fdfff3" />
</p>

Since Version 2.7.5, OnlySwitch supports to be controlled via OnlyRemote

**Installed OnlySwitch but cannot see its icon?** See [OnlySwitch icon missing from the menu bar](#onlyswitch-icon-missing-from-the-menu-bar).

## OnlySwitch icon missing from the menu bar

OnlySwitch is accessed through its menu bar icon. On macOS 26.2, users have reported that the app appears not to open when OnlySwitch is disabled in the system's menu bar settings.

1. Open **System Settings → Menu Bar**.
2. Find **OnlySwitch** in the list and enable it.
3. Click the OnlySwitch icon in the menu bar to open its controls.

If OnlySwitch is already enabled but its icon is still missing, check whether other menu bar items are taking up the available space. Try removing some other items to make room. If you use OnlySwitch's own collapsing feature, see [Hide Menu Bar Icons](#hide-menu-bar-icons) for how its hidden section works.

If these checks do not restore access, add your macOS version, OnlySwitch version, and whether OnlySwitch is enabled in System Settings → Menu Bar to [issue #188](https://github.com/jacklandrin/OnlySwitch/issues/188).


## Shortcuts Gallery

Everyone can contribute macOS Shortcuts for OnlySwitch now. Please read [How to contribute to Shortcuts Gallery](ShortcutsGalleryContributing.md). The shared Shortcuts will be displayed here:

<p align="center">
<img alt="Sits in the status bar" src="https://github.com/jacklandrin/OnlySwitch/assets/3782279/a9d90eed-c540-4183-9332-396dce0f72d4" width="70%" align="center" />
</p>

## Switch list

#### Native Switches:

| Switch              | status          | Switch                   | status            |
|:--------------------|-----------------|:-------------------------|:------------------|
| Hide desktop        | finished        | Hide notch               | exist some issues |
| Dark mode           | finished        | Low power mode           | require password  |
| Screen Saver        | finished        | Show Finder Path Bar     | finished          |
| Night Shift         | finished        | Mute mic                 | finished          |
| Autohide Dock       | finished        | Small launchpad icon     | finished          |
| Airpods             | finished        | Pomodoro timer           | finished          |
| Bluetooth           | finished        | Show extension name      | finished          |
| Xcode cache         | finished        | Show user library folder | finished          |
| Autohide Menu Bar   | finished        | Mute                     | finished          |
| Show hidden files   | finished        | Empty pasteboard         | finished          |
| Radio Station       | finished        | Empty trash              | finished          |
| Keep awake          | finished        | Show Recent Apps on Dock | finished          |
| Spotify             | finished        | Apple Music              | finished          |
| Screen Test & Clean | finished        | Hide Menu Bar Icons      | partly finished   |
| FKey                | finished        | Back Noises              | finished          |
| Dim Screen          | finished        | Eject Discs              | finished          |
| Hide Windows        | partly finished | True Tone                | finished          |
| Top Sticker         | partly finished | Key Light                | finished          |
| Only Agent          | finished        | Authenticator            | finished          |
| Sound Mixer         | finished        |                          |                   |

Since Version 1.3, switches can be added to or removed from the list.

#### Shortcuts Gallery:

| Shortcuts                        | Remark                                          | Shortcuts                        | Remark  |
|----------------------------------|-------------------------------------------------|----------------------------------|:--------|
| Toggle Scroll Direction          | Monteray                                        | Invert Scroll Direction(Ventura) | Ventura |
| DarkMode Switch                  |                                                 | Network Details                  |         |
| Split-Screen Apps                |                                                 | Passwords                        |         |
| Google Translate                 |                                                 | IP Address Information           |         |
| Autohide menu bar in full screen | Monteray                                        | Flush DNS Cache                  |         |
| Do Not Disturb                   | Monteray or higher                              | Upcoming Events                  |         |
| S-GPT                            | works with S-GPT Encoder, needs OpenAI API key  | S-GPT Encoder                    |         |

#### Evolution Gallery:

| Evolution           | Remark | Evolution          | Remark                  |
|---------------------|--------|--------------------|:------------------------|
| Stage Manager       |        | Update Software    | installed via App Store |
| Hide desktop Widget | Sonoma | Hide Desktop Icons | Sonoma                  |
| Clamshell           |        | Wifi Switch        |                         |



## Shortcuts Actions

| Actions             | status            |
|---------------------|-------------------|
| Get wallpaper image | exist some issues |
| Get wallpaper url   | finished          |
| Is dark mode        | finished          |
| Set dark mode       | finished          |

## Supported Languages 🇺🇳
English, Simplified Chinese, German, Croatian, Turkish, Polish, Filipino, Dutch, Italian, Russian, Spanish, Japanese, Somali, Korean, French, Ukrainian, Slovak, Portuguese (BR), Czech

## Welcome to pull requests for these

* support other languages
* fix bugs

If you have other good ideas 💡, feel free to send an E-mail to me.

## Donate
If you like it, help support this app by giving me a cup of coffee to keep coding. [Donate here](https://www.paypal.com/donate/?hosted_button_id=V3NDUXWZ6GVYG)

## 🤖 Only Agent
Only Switch starts to support Only Agent since 2.6.0. You can control your mac by **English** via AI now. After you write down your purpose, AI can generate an Apple Script to engage it. If the Agent mode is on, the script will be immediately executed.  There are two available model providers, with Ollama, OpenAI and Gemini. Feel free to contribute more providers.

It supports only macOS 26.0 and above.

<p align="center">
<img alt="Only Agent" src="https://github.com/user-attachments/assets/3710ebf6-f93c-4436-bce2-6fcf2727e3e1" width="70%" align="center" />
</p>

### OpenClaw (natural language)

You can also control OnlySwitch by **natural language** using [OpenClaw](https://openclaw.ai/). An OpenClaw-compatible skill is included in this repo: say things like *"empty trash"*, *"toggle keep awake"*, or *"turn on dark mode"* and OpenClaw will trigger the matching switch via deeplink. See [OpenClaw/README.md](OpenClaw/README.md) for setup (extra skill directory or copy into `~/.openclaw/skills`).

## System Monitor

System Monitor shows live CPU, GPU, memory, disk, and network usage. Open the **System Monitor** tab in Only Control, and choose its dashboard cards and optional menu-bar indicators in **OnlySwitch Settings → System Monitor**. CPU and memory cards can expand to show the busiest processes, while Network Details includes Wi-Fi or Ethernet information, local and public IP addresses, and—when macOS makes them available—SSID, signal strength, and link rate.

Enabled menu-bar indicators keep the monitor sampling while the Only Control popover is closed. The sampling interval has a one-second minimum. Public IP lookup makes external requests to ipify’s IPv4 and IPv6 endpoints; results are cached for up to five minutes.

Some values may appear as unavailable when the hardware or macOS does not expose them, including temperature readings. GPU reporting relies on private, undocumented macOS APIs and may stop working after a system update. Network usage is system-wide; per-process network rates are not available.

## Only Widget

Only Switch supports Apple Widgets since version 2.5.0. The Widgets can be edited to any built-in switches and buttons. Clicking them will trigger the reflection of relevant switches and buttons. You can put Only Widgets anywhere, desktop or notification center.

Since version 2.5.2, Only Widget supports Evolution.

**NOTE:** After updating version 2.5.0, you might need to reset your language. If your widgets didn't follow your language settings, please kill Only Widget process, it will update.

<img width="370" alt="Only Widget" src="https://github.com/jacklandrin/OnlySwitch/assets/3782279/0c1be202-9e5f-41dd-b62d-52d5a7147139">

## Evolution🔥
Evolution has come following version 2.4, you can freely DIY the switches and buttons that you want. Currently, evolution supports **Shell** and **Apple Script**. They also can be invoked by hotkeys. Next, evolution will be able to be distributed by users as a shortcut utility platform.

Evolution settings page is implemented with TCA.
PS: Evolution feature needs macOS 13.0 and above.

![](https://github.com/jacklandrin/OnlySwitch/assets/3782279/69131917-bfe0-4c54-8b38-d4aeb26f749a)

Everyone can contribute Evolution for OnlySwitch since version 2.4.3. Please read [How to contribute to Evolution Gallery](EvolutionGalleryContributing.md). The shared Evolutions will be displayed here:

<p align="center">
<img alt="Sits in the status bar" src="https://github.com/jacklandrin/OnlySwitch/assets/3782279/f3299ae0-0222-49a3-864a-80c6601bac6a" width="70%" align="center" />
</p>


### How to create an Evolution?
So far, Evolution offers two types, with Switch and Button. 
1. Button is very simple, when Run button is pressed, the script you added will be executed.
2. Regarding Switch, there are four fields you can edit.
* Check status: When OnlySwitch list appeared or some settings are changed, the switch status will be checked whether on or off. At this moment, the script of check status will be executed. You can press the debug button to output the result of this script.
* True condition: You can input a true condition to define what is on or off for the switch status. If the true condition matches the output result, the status will be on, and vice versa.
* Turn on: the script can change the status to on.
* Turn off: the script can change the status to off.

The debug button can verify if your scripts are valid. Before you save evolution, all scripts must pass the test.

## AirPods Switch 
I use `classOfDevice`(2360344) to check if a Bluetooth device is Airpods Pro, but I'm not sure whether other AirPods modules are also 2360344, since I only have two AirPods Pros. If you are using AirPods 1~3, please tell me what the `classOfDevice` is. Or I can detect the count of battery value to check if AirPods (when the count is 3, it's AirPods), like **AirPods Battery Monitor For MAC OS**.

## Radio Player
Radio Player supports m3u, and aac stream, but without sound wave effect. Please send me the crash log and stream URL if your Radio Player crashes. You can close the sound wave effect on the Radio setting, and that player is AVPlayer, more stable. In version 2.3.5, the radio play can be set to enable/disabled. If the function is disabled, the switch will be invisible in the list, and the radio player will be unregistered from Now Playing(But I don't know why there will be a little delay. It should be a problem by macOS).

Since Version 2.3.11, the radio list can be exported and imported.

## Hiding new Macbook Notch 

The Hide notch switch only shows on the built-in display of M1 Pro/Max Macbook Pro. The switch just controls the current desktop, not all work desktops.
Now, the Hide notch switch supports dynamic wallpaper, just the processing takes a much longer time.
<p align="center">
<img alt="Sits in the status bar" src="https://github.com/jacklandrin/OnlySwitch/assets/3782279/efddd8d3-edfe-4497-bea0-5051d27625ca" width="60%" align="center" />
</p>


## Low Power Mode
Low Power Mode uses Terminal commands that require root access, so the app will ask you to enter the password on every toggle.

## Screen Test & Clean
In Version 2.3, Only Switch brings a new feature, Screen Test. It provides a pure color view in full-screen mode, you can check dead pixels via it. Press the left and right arrow keys, the color will change from black, white, red, green, and blue. This functionality also can be used for screen cleaning, as you can see the stains on the screen.

## Hide Menu Bar Icons
This feature is new in version 2.3.2. To be honest, Hidden and Dozer are both good apps for this function. Many users install OnlySwitch and them simultaneously, but this also squeezes the menu bar, which is already lacking in space. Therefore, the feature integrates into OnlySwitch.
![](https://github.com/jacklandrin/OnlySwitch/assets/3782279/fdda284e-929f-400e-aba5-9c628f065de6)
When the switch is on, items on the left of the split(arrow-pointing) icon are hidden. Hold ⌘ (command) and drag the icon to configure the hidden section. If you want to use it no longer, you can disable it in preferences, the split icon will disappear. You also can set the interval of autohide for it here. If your date on the menu bar is truncated when it's on, you can set this: System Preferences -> Dock & Menu Bar -> Clock -> Show date -> always.

Since version 2.3.10, this switch can be controlled via right-click icons.

On macOS 27 or later, OnlySwitch uses the system's native menu-bar visibility mechanism. The first collapse asks for Accessibility permission so OnlySwitch can keep the icons to the right of its divider visible. If permission is denied or a macOS update makes the native integration not available, OnlySwitch leaves the menu bar unchanged and the switch stays off. This macOS 27 implementation relies on a private API and is not suitable for Mac App Store distribution; future macOS updates can disable it.

On macOS 27 or later, this feature uses the system’s native menu-bar hiding mechanism. While it is active, macOS also hides Now Playing and can hide Camera, AirDrop, Focus, and Timer. These are system-level collateral items that OnlySwitch cannot exempt or keep visible.

For development testing on macOS 27, run the signed build from `/Applications`, not Xcode's `DerivedData` directory. The system's visibility matcher can fail to recognize a DerivedData-launched app even when its bundle identifier is explicitly allowed, hiding OnlySwitch's own icons. Quit the Xcode-run instance before launching the Applications copy. This was verified with the same build: both OnlySwitch icons remained visible with the switch enabled from Applications.

If both OnlySwitch menu-bar icons disappear after command-dragging the divider, re-enable OnlySwitch under System Settings → Menu Bar → Allow in the Menu Bar. macOS 27 can disable the entire app there when an older, non-removable status item is dragged; current builds mark both OnlySwitch items as removable to prevent that system-wide disable.

## They talk about it

|                                                                                                                                 |                                                                                                                                            |                                                                                                                                  |                                                                                                                        |
|---------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------|:-----------------------------------------------------------------------------------------------------------------------|
| [itopnews.de](https://www.itopnews.de/?s=OnlySwitch)                                                                            | [Ifun.de](https://www.ifun.de/suche/OnlySwitch)                                                                                            | [appgefahren.de](https://www.appgefahren.de/onlyswitch-kleines-tool-mit-wichtigen-aktionen-fuer-die-mac-menueleiste-312135.html) | [CASCHYS BLOG](https://stadt-bremerhaven.de/only-switch-fuer-macos-schnellzugriff-auf-einige-systemoptionen/)          |
| [softpedia](https://mac.softpedia.com/get/System-Utilities/OnlySwitch.shtml)                                                    | [macupdate](https://www.macupdate.com/app/mac/63719/onlyswitch)                                                                            | [v1tx](https://www.v1tx.com/post/onlyswitch/)                                                                                    | [OSCHINA](https://www.oschina.net/p/onlyswitch)                                                                        |
| [Macken](https://www.macken.xyz/2021/12/gratis-ar-gott-alla-installningar-pa-ett-stalle-onlyswitch/)                            | [AAPL Ch](https://applech2.com/archives/20220111-onlyswitch-all-in-one-status-bar-button-for-mac.html)                                     | [appsofter](https://appsofter.com/download/1265.html)                                                                            | [lifehacker.ru](https://lifehacker.ru/onlyswitch)                                                                      |
| [appletechnikblog](https://appletechnikblog.com/de/2022/02/25/app-tipp-der-woche-only-switch-fuer-die-menueleiste-auf-dem-mac/) | [All-in-One person](https://en.blog.themarfa.name/how-to-quickly-manage-macos-system-settings/)                                            | [Mac Gadget](https://www.macgadget.de/News/2022/03/24/OnlySwitch-Schnellzugriff-auf-viele-Systemfunktionen-per-Mac-Menueleiste)  | [MaxiApple](https://www.maxiapple.com/2022/05/onlyswitch-macos-mac-gratuit.html)                                       |
| [insmac](https://insmac.org/macosx/5018-onlyswitch.html)                                                                        | [tchgdns](https://tchgdns.de/onlyswitch-macos-open-source/)                                                                                | [insmac](https://insmac.org/macosx/5018-onlyswitch.html)                                                                         | [macbff](https://macbff.com/onlyswitch-2-3-1/)                                                                         |
| [korben](https://korben.info/controler-macos-onlyswitch.html)                                                                   | [macg](https://www.macg.co/logiciels/2023/03/onlyswitch-ajoute-une-pelletee-de-raccourcis-pratiques-votre-barre-des-menus-135357)          | [korben.info](https://korben.info/controler-macos-onlyswitch.html)                                                               | [AlternativeTo](https://alternativeto.net/software/only-switch)                                                        |
| [macsoft.jp](https://macsoft.jp/onlyswitch/)                                                                                    | [macgeneration](https://www.macg.co/logiciels/2023/03/onlyswitch-ajoute-une-pelletee-de-raccourcis-pratiques-votre-barre-des-menus-135357) | [hdwh.de](https://hdwh.de/onlyswitch-vereinfacht-eure-routinearbeit-mit-praktischen-schaltern/)                                  | [MacKed](https://macked.app/onlyswitch.html)                                                                           |
| [Mac Torrents](https://www.tntmactorrent.net/onlyswitch-for-mac-free-download/)                                                 | [PCtipp](https://www.pctipp.ch/praxis/mac/mac-tipp-onlyswitch-2-2892320.html)                                                              | [lifehacker](https://lifehacker.com/tech/change-hidden-mac-settings-with-onlyswitch)                                             | [PHAPLUAT](https://kynguyenso.plo.vn/su-dung-onlyswitch-de-tuy-chinh-tat-ca-cai-dat-may-mac-nhanh-hon-post776151.html) |
| [Techgedöns](https://tchgdns.de/onlyswitch-menueleisten-multitool-bekommt-widgets-fuer-den-mac-desktop/)                        | [MacVince](https://www.youtube.com/watch?v=ARfBLKzRQY4&t=41s)                                                                              |  [onmymenubar](https://onmymenubar.app/onlyswitch/)                                                                                                                                |                                                                                                                        |


## Reference

* NightShift switch refers to [Nocturnal](https://github.com/joshjon/nocturnal)
* [LaunchAtLogin](https://github.com/sindresorhus/LaunchAtLogin)
* AirPods Battery refers to [AirPods Battery Monitor For MAC OS](https://github.com/mohamed-arradi/AirpodsBattery-Monitor-For-Mac)
* Dynamic Wallpaper processing refer to https://itnext.io/macos-mojave-dynamic-wallpaper-fd26b0698223 and [wallpapper](https://github.com/mczachurski/wallpapper)
* [AlertToast](https://github.com/elai950/AlertToast)
* [AudioStreamer](https://github.com/syedhali/AudioStreamer) modified for live streaming
* [AudioSpectrum](https://github.com/potato04/AudioSpectrum) modified for AppKit
* [Alamofire](https://github.com/Alamofire/Alamofire)
* Sound Source: [mixkit](https://mixkit.co) and [pixabay](https://pixabay.com)
* [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)
* Apple Music & Spotify Switch refer to [SpotMenu](https://github.com/kmikiy/SpotMenu)
* The idea of hiding menu bar icons from [Hidden](https://github.com/dwarvesf/hidden)
* FKey refer to [Fluor](https://github.com/Pyroh/Fluor)
* Hide Windows refer to [Later](https://github.com/alyssaxuu/later)
* [The composable architecture](https://github.com/pointfreeco/swift-composable-architecture)
* [Sparkle](https://github.com/sparkle-project/Sparkle)
* True Tone refers to [Shifty](https://github.com/thompsonate/Shifty)
* [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui)
* Key Light refers to [mac-brightnessctl](https://github.com/rakalex/mac-brightnessctl)
* [AIProxySwift](https://github.com/lzell/AIProxySwift)
* [ollama-swift](https://github.com/mattt/ollama-swift)
* [CodexKit](https://github.com/timazed/CodexKit)

## Contributors

**Translation:**

| Language | Contributor              | Language        | Contributor    |
|----------|--------------------------|:----------------|:---------------|
| German   | @C0d3Br3aker             | Italian         | @bellaposa     |
| Croatian | @milotype                | Russian         | @kirillyakopov |
| Turkish  | @berkbatuhans            | Spanish         | @kant          |
| Polish   | @kpacholak               | Japanese        | @ShogoKoyama   |
| Dutch    | Alex                     | Somali          | @abdorizak     |
| Filipino | Rosel                    | Korean          | @iosdevted     |
| French   | @BtKent and Ange Lefrère | Ukrainian       | @andryua       |
| Slovak   | @Svec-Tomas              | Portuguese (BR) | @EvertonCa     |
| Czech    | @ForksApps               |                 |                |

@wrngwrld for the volume slider of the radio player

@kant for syntax issue 

@Ryderwe for Authenticator

@lou1s19 for Claud models of OnlyAgent, Sound Mixer and dim mode for the external monitor

@oecer for settings backup
## License
MIT
