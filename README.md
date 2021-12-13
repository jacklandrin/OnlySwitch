![](https://img.shields.io/badge/UI-SwiftUI-blue)   ![](https://img.shields.io/badge/Platform-Monterey-purple)  ![](https://img.shields.io/badge/License-MIT-orange)
<p align="left">
<img alt="AppIcon" src="http://www.jacklandrin.com/wp-content/uploads/2021/12/only_switch_256.png" width="128px" align="center" />
</p>

# OnlySwitch

***Menubar is smaller, you only need an All-in-One switch.***

[**Download the app**](https://github.com/jacklandrin/OnlySwitch/releases/download/release_1.1/OnlySwitch.zip)

## What's the OnlySwitch
OnlySwitch provides a series toggle switch to simply your routine work, such as Hiden desktop icons, dark mode and hide ugly notch of new Mackbook Pro. The switches show on your statusbar, you can easily control them.

<p align="center">
<img alt="Sits in the status bar" src="https://www.jacklandrin.com/wp-content/uploads/2021/12/onlySwitch_11.png" width="60%" align="center" />
</p>

## Switch list

| Switch            | status            |
|:------------------|-------------------|
| Hide desktop      | finish            |
| Dark mode         | finish            |
| Screen Saver      | finish            |
| Night Shift       | finish            |
| Autohide Dock     | finish            |
| Airpods           | finish            |
| Bluetooth         | finish            |
| Xcode cache       | finish            |
| Autohide Menu Bar | finish            |
| Show hidden files | finish            |
| Radio Station     | finish            |
| Keep awake        | finish            |
| Hide notch        | exist some issues |
| Mute              | exist some issues |
| No disturb mode   | todo              |
| Empty trash       | todo              |
| Empty pasteboard  | todo              |

## About hiding new Macbook Notch 

The Hide notch switch only shows on build-in display of M1 Pro/Max Macbook Pro. The switch just controls current desktop, not for all work desktops.
Now, the Hide notch switch supports dynamic wallpaper, just the processing takes much longer time.
## About AirPods Switch 

I use classOfDevice(2360344) to check if a bluetooth device is Airpods Pro, but I'm not sure whether other AirPods modules are also 2360344, since I only have two AriPods Pros. If you are using AirPods 1~3, please tell me what the classOfDevice is. Or I can detect the count of battery value to check if AirPods(when count is 3, it's AirPods), like **AirPods Battery Monitor For MAC OS**.
## Screenshots

<p align="center">
<img alt="Sits in the status bar" src="http://www.jacklandrin.com/wp-content/uploads/2021/12/hidenotch.png" width="60%" align="center" />
</p>

## Reference

* NightShift switch refer to [Nocturnal](https://github.com/joshjon/nocturnal)
* [LaunchAtLogin](https://github.com/sindresorhus/LaunchAtLogin)
* AirPods Battery refer to [AirPods Battery Monitor For MAC OS](https://github.com/mohamed-arradi/AirpodsBattery-Monitor-For-Mac)
* Dynamic Wallpaper processing refer to https://itnext.io/macos-mojave-dynamic-wallpaper-fd26b0698223 and [wallpapper](https://github.com/mczachurski/wallpapper)
* [AlertToast](https://github.com/elai950/AlertToast)
* [AudioStreamer](https://github.com/syedhali/AudioStreamer) modified for live streaming
* [AudioSpectrum](https://github.com/potato04/AudioSpectrum) modified for Appkit
## License
MIT
## Donate
If you like it, help supporting this app by giving me a cup of tea in order for me to keep coding.
<p align="center">
<img alt="Sits in the status bar" src="http://www.jacklandrin.com/wp-content/uploads/2021/12/donation.jpeg" width="20%" align="left" title="Made by QRCobot"/>
</p>
