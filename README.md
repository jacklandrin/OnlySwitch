![](https://badgen.net/github/release/jacklandrin/onlyswitch) ![](https://img.shields.io/badge/UI-SwiftUI-green)
[![Listed on TakoAPI](https://takoapi.com/api/badge/jacklandrin-onlyswitch)](https://takoapi.com/agents/jacklandrin-onlyswitch)
![](https://img.shields.io/badge/Platform-Tahoe-blue) ![](https://img.shields.io/badge/License-MIT-orange)

<p align="center">
  <a href="https://onlyswitch.click">
    <img alt="OnlySwitch app icon" src="https://github.com/jacklandrin/OnlySwitch/blob/main/OnlySwitch/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png?raw=true" width="128" />
  </a>
</p>

# OnlySwitch

**A smaller menu bar starts with one all-in-one switch.**

OnlySwitch puts everyday macOS controls—such as hiding desktop icons, changing appearance, keeping the Mac awake, and managing the notch—into one customizable menu-bar app. Add, remove, and reorder switches and Shortcuts, assign keyboard shortcuts, or place controls on the desktop as widgets.

<p align="center">
  <img alt="OnlySwitch controls" src="https://github.com/user-attachments/assets/40d94175-6487-4c59-b09e-2261ac5b8453" width="80%" />
</p>

## Installation

### Homebrew

```sh
brew install only-switch
```

### Manual download

[Download the latest OnlySwitch DMG](https://github.com/jacklandrin/OnlySwitch/releases/latest/download/OnlySwitch.dmg).

> [!IMPORTANT]
> Automatic updating is broken in version 2.5.6 and earlier. If you are on one of those versions, update manually or reinstall with Homebrew.

## Quick start

1. Launch OnlySwitch and enable it under **System Settings → Menu Bar** if macOS does not show its icon.
2. Click the OnlySwitch menu-bar icon to open the control list.
3. Open settings to add, remove, and reorder switches or Shortcuts, configure hotkeys, and enable optional features.
4. On supported macOS versions, add Only Widget from the widget gallery for desktop or Notification Center access.

To control OnlySwitch from an iPhone or iPad, install [OnlyRemote from the App Store](https://apps.apple.com/us/app/onlyremote/id6793657946), then open **iOS Remote** in OnlySwitch settings to enable local-network access and pair the device.

<p align="center">
  <img alt="OnlyRemote controls on iPad" src="https://github.com/user-attachments/assets/8cbba2ca-ff02-4600-9c6f-265fd91d1d67" width="70%" />
</p>

<p align="center">
  <img alt="OnlyRemote App Store QR code" src="https://raw.githubusercontent.com/jacklandrin/OnlySwitch/main/OnlySwitch/Resource/Ads/OnlyRemoteQRCode.jpeg" width="160" />
</p>

## Features

### Highlights

- Import macOS Shortcuts into OnlySwitch and control switches and Shortcuts with keyboard shortcuts.
- Customize which controls appear and arrange them to fit your workflow.
- Use Apple Widgets on macOS Sonoma and later, including Evolution controls.
- Open the compact **Only Control** interface for a focused control panel.
- Pair OnlyRemote for local-network control from iPhone or iPad.
- Enable the optional Desktop Pet, drag it anywhere, and click it to show or dismiss Only Control.

<p align="center">
  <img alt="Switch availability in the macOS menu bar" src="https://github.com/jacklandrin/OnlySwitch/assets/3782279/11c89e33-2007-4913-b320-47c188538b68" />
</p>

<p align="center">
  <img alt="OnlySwitch desktop pet" src="https://github.com/user-attachments/assets/f45e4b4f-932e-4768-8bfd-845e22fdfff3" width="152" height="188" />
</p>

### Built-in switches

| Switch | Status | Switch | Status |
|:---|:---|:---|:---|
| Hide desktop | finished | Hide notch | has known issues |
| Dark mode | finished | Low power mode | requires initial authorization |
| Screen Saver | finished | Show Finder Path Bar | finished |
| Night Shift | finished | Mute mic | finished |
| Autohide Dock | finished | Small launchpad icon | finished |
| AirPods | finished | Pomodoro timer | finished |
| Bluetooth | finished | Show extension name | finished |
| Xcode cache | finished | Show user library folder | finished |
| Autohide Menu Bar | finished | Mute | finished |
| Show hidden files | finished | Empty pasteboard | finished |
| Radio Station | finished | Empty trash | finished |
| Keep awake | finished | Show Recent Apps on Dock | finished |
| Spotify | finished | Apple Music | finished |
| Screen Test & Clean | finished | Hide Menu Bar Icons | partially finished |
| FKey | finished | Back Noises | finished |
| Dim Screen | finished | Eject Discs | finished |
| Hide Windows | partially finished | True Tone | finished |
| Top Sticker | partially finished | Key Light | finished |
| Only Agent | finished | Authenticator | finished |
| Sound Mixer | finished | Natural Scrolling | finished |
| Show desktop pet | finished | Codex Usage | finished |

Switches can be added to or removed from the list.

### Shortcuts Gallery

Anyone can contribute macOS Shortcuts. See [How to contribute to the Shortcuts Gallery](ShortcutsGalleryContributing.md).

<p align="center">
  <img alt="Shortcuts Gallery" src="https://github.com/jacklandrin/OnlySwitch/assets/3782279/a9d90eed-c540-4183-9332-396dce0f72d4" width="70%" />
</p>

| Shortcut | Remark | Shortcut | Remark |
|---|---|---|:---|
| Toggle Scroll Direction | Monterey | Invert Scroll Direction (Ventura) | Ventura |
| DarkMode Switch | | Network Details | |
| Split-Screen Apps | | Passwords | |
| Google Translate | | IP Address Information | |
| Autohide menu bar in full screen | Monterey | Flush DNS Cache | |
| Do Not Disturb | Monterey or later | Upcoming Events | |
| S-GPT | works with S-GPT Encoder, needs OpenAI API key | S-GPT Encoder | |

### Shortcuts actions

| Action | Status |
|---|---|
| Get wallpaper image | has known issues |
| Get wallpaper URL | finished |
| Is dark mode | finished |
| Set dark mode | finished |

### Evolution

Evolution lets you build custom switches and buttons backed by Shell or AppleScript, invoke them with hotkeys, and share them through the Evolution Gallery. Evolution requires macOS 13 or later, and its settings are implemented with The Composable Architecture.

Evolution scripts run locally with the permissions of OnlySwitch. Review scripts before saving or importing them, especially scripts that execute shell commands, Apple Events, or privileged operations.

![](https://github.com/jacklandrin/OnlySwitch/assets/3782279/69131917-bfe0-4c54-8b38-d4aeb26f749a)

Anyone can contribute an Evolution. See [How to contribute to the Evolution Gallery](EvolutionGalleryContributing.md).

<p align="center">
  <img alt="Evolution Gallery" src="https://github.com/jacklandrin/OnlySwitch/assets/3782279/f3299ae0-0222-49a3-864a-80c6601bac6a" width="70%" />
</p>

| Evolution | Remark | Evolution | Remark |
|---|---|---|:---|
| Stage Manager | | Update Software | installed via App Store |
| Hide desktop Widget | Sonoma | Hide Desktop Icons | Sonoma |
| Clamshell | | Wi-Fi Switch | |

#### Creating an Evolution

Evolution supports two types:

1. A **Button** runs its script when you press **Run**.
2. A **Switch** has four editable fields:
   - **Check status:** runs when the OnlySwitch list appears or settings change. The debug button shows the script output.
   - **True condition:** defines the output that represents the on state.
   - **Turn on:** changes the state to on.
   - **Turn off:** changes the state to off.

Every script must pass the built-in test before the Evolution can be saved.

### Only Agent and OpenClaw

Only Agent lets you describe a task in English and generates AppleScript to control your Mac. When Agent mode is enabled, the generated script is executed immediately. Only Agent supports Ollama, OpenAI, and Gemini providers and requires macOS 26 or later. Provider-backed requests may send your prompt to the provider you select; review both the prompt and generated script before enabling immediate execution.

<p align="center">
  <img alt="Only Agent" src="https://github.com/user-attachments/assets/3710ebf6-f93c-4436-bce2-6fcf2727e3e1" width="70%" />
</p>

You can also control OnlySwitch with natural language through [OpenClaw](https://openclaw.ai/). Say things like *“empty trash”*, *“toggle keep awake”*, or *“turn on dark mode”* to trigger the matching switch through a deeplink. See [OpenClaw setup](OpenClaw/README.md) for installation as an extra skill directory or under `~/.openclaw/skills`.

### System Monitor

System Monitor shows live CPU, GPU, memory, disk, and network usage. Open its tab in Only Control, then choose dashboard cards and optional menu-bar indicators under **OnlySwitch Settings → System Monitor**. CPU and memory cards can expand to show the busiest processes. Network Details includes Wi-Fi or Ethernet information, local and public IP addresses, and—when macOS exposes them—SSID, signal strength, and link rate.

Enabled menu-bar indicators keep sampling while the Only Control popover is closed. The minimum sampling interval is one second. Public-IP lookup sends external requests to ipify's IPv4 and IPv6 endpoints; results are cached for up to five minutes.

Some values may be unavailable when the hardware or macOS does not expose them, including temperature readings. GPU reporting relies on private, undocumented macOS APIs and may stop working after a system update. Network usage is system-wide; per-process network rates are not available.

<p align="center">
  <img alt="OnlySwitch System Monitor" src="https://github.com/user-attachments/assets/ac8178f6-9f61-43be-a73b-a2103ac18ff7" width="30%" />
</p>

### Codex Usage

Codex Usage is an optional built-in tab showing the signed-in Codex account's plan, remaining five-hour and weekly usage, reset times, available credits, and reset-credit information. Enable the **Codex Usage** switch to show it in OnlySwitch and Only Control. It uses the existing local Codex sign-in, so OnlySwitch does not require a separate sign-in.

<p align="center">
  <img alt="Codex Usage" src="https://github.com/user-attachments/assets/dad0f898-fe19-4df4-be7f-9db278ba5334" width="30%" />
</p>

### Only Widget

Only Widget can be configured with any built-in switch or button and placed on the desktop or in Notification Center. Clicking a widget triggers the corresponding control. Evolution is supported in widgets.

<img width="370" alt="Only Widget" src="https://github.com/jacklandrin/OnlySwitch/assets/3782279/0c1be202-9e5f-41dd-b62d-52d5a7147139">

### Screen Test & Clean

Screen Test opens a full-screen solid-color view for checking dead pixels or cleaning the display. Use the left and right arrow keys to cycle through black, white, red, green, and blue.

## Known limitations and troubleshooting

### OnlySwitch icon missing from the menu bar

OnlySwitch is accessed through its menu-bar icon. On macOS 26.2, the app can appear not to open when it is disabled in the system menu-bar settings.

1. Open **System Settings → Menu Bar**.
2. Find **OnlySwitch** and enable it.
3. Click the OnlySwitch icon in the menu bar.

If the icon is still missing, other items may be using all available space. Remove or hide some items. If you use OnlySwitch's collapsing feature, also review [Hide Menu Bar Icons](#hide-menu-bar-icons). If the issue continues, add your macOS version, OnlySwitch version, and menu-bar setting to [issue #188](https://github.com/jacklandrin/OnlySwitch/issues/188).

### Hide Menu Bar Icons

When enabled, items to the left of the divider (arrow) icon are hidden. Hold Command and drag menu-bar icons to configure the hidden section. Settings let you disable the feature or change its auto-hide interval. If the date becomes truncated, choose **System Settings → Control Center → Clock Options → Show date → Always**. The switch can also be controlled by right-clicking its icons.

![](https://github.com/jacklandrin/OnlySwitch/assets/3782279/fdda284e-929f-400e-aba5-9c628f065de6)

On macOS 27 or later, OnlySwitch uses the system's native menu-bar visibility mechanism. The first collapse requests Accessibility permission so OnlySwitch can keep icons to the right of its divider visible. If permission is denied or a macOS update makes the integration unavailable, the menu bar remains unchanged and the switch stays off.

This macOS 27 integration relies on a private API, is not suitable for Mac App Store distribution, and may stop working after a macOS update. While active, macOS also hides Now Playing and may hide Camera, AirDrop, Focus, and Timer; OnlySwitch cannot exempt these system-level items.

For development testing on macOS 27, run the signed build from `/Applications`, not Xcode's `DerivedData` directory. The system visibility matcher may fail to recognize a DerivedData-launched app and hide OnlySwitch's icons. Quit the Xcode-run instance before launching the Applications copy.

If both OnlySwitch icons disappear after Command-dragging the divider, re-enable OnlySwitch under **System Settings → Menu Bar → Allow in the Menu Bar**. macOS 27 can disable the entire app when an older, non-removable status item is dragged; current builds mark both OnlySwitch items as removable to prevent this.

### Hide notch

Hide notch appears only on the built-in display of M1 Pro/Max MacBook Pro models. It controls the current desktop rather than every workspace. Dynamic wallpapers are supported but take longer to process.

<p align="center">
  <img alt="Hide notch" src="https://github.com/jacklandrin/OnlySwitch/assets/3782279/efddd8d3-edfe-4497-bea0-5051d27625ca" width="60%" />
</p>

### Low Power Mode

Low Power Mode uses commands that require root access. OnlySwitch asks for initial authorization to install or authorize its privileged helper; subsequent toggles do not prompt again while that authorization remains valid.

### AirPods detection

OnlySwitch uses `classOfDevice` value `2360344` to identify AirPods Pro. Other AirPods generations may report a different value. Reports from AirPods 1–3 owners are welcome; battery-value count may be a possible fallback.

### Radio Player

Radio Player supports M3U and AAC streams. If it crashes, include the crash log and stream URL in your report. Disabling the sound-wave effect in Radio settings uses the more stable AVPlayer path. Disabling Radio hides its switch and unregisters it from Now Playing, though macOS may introduce a short delay. Radio lists can be exported and imported.

### Widget language after updating

After updating from version 2.5.0, you may need to reset the app language. If widgets do not follow the selected language, quit the Only Widget process so it reloads the setting.

## Development

Start with [ARCHITECTURE.md](ARCHITECTURE.md), the source of truth for project boundaries and engineering constraints.

- `OnlySwitch/` is the main macOS menu-bar app and owns app-specific UI, persistence, audio, and system integrations.
- `OnlyWidget/` is the widget extension and uses extension-safe shared models and effects.
- `OnlySwitchRemote/` is the remote-control app and shares protocol contracts without importing main-app implementation details.
- `Modules/` is the primary Swift Package boundary for features, domain models, networking, remote transport, and shared utilities.
- `OpenClaw/` contains the deeplink-based natural-language integration and its setup documentation.

The app follows The Composable Architecture and uses injected dependencies for effects. Keep business logic out of SwiftUI views, preserve Swift 6 concurrency safety, and treat shell commands, Apple Events, keychain access, networking, system settings, and user permissions as explicit, testable boundaries.

## Community and contributions

Join the [Telegram group](https://t.me/OnlySwitchforMac) or [Discord server](https://discord.gg/UzSNpYdPZj).

Pull requests are welcome, especially for bug fixes and additional translations. If you have another idea, open an issue or send the maintainer an email.

### Supported languages

English, Simplified Chinese, German, Croatian, Turkish, Polish, Filipino, Dutch, Italian, Russian, Spanish, Japanese, Somali, Korean, French, Ukrainian, Slovak, Portuguese (BR), and Czech.

### Donate

If OnlySwitch is useful to you, [support its development with a donation](https://www.paypal.com/donate/?hosted_button_id=V3NDUXWZ6GVYG).

### Press and mentions

| | | | |
|---|---|---|:---|
| [itopnews.de](https://www.itopnews.de/?s=OnlySwitch) | [Ifun.de](https://www.ifun.de/suche/OnlySwitch) | [appgefahren.de](https://www.appgefahren.de/onlyswitch-kleines-tool-mit-wichtigen-aktionen-fuer-die-mac-menueleiste-312135.html) | [CASCHYS BLOG](https://stadt-bremerhaven.de/only-switch-fuer-macos-schnellzugriff-auf-einige-systemoptionen/) |
| [softpedia](https://mac.softpedia.com/get/System-Utilities/OnlySwitch.shtml) | [macupdate](https://www.macupdate.com/app/mac/63719/onlyswitch) | [v1tx](https://www.v1tx.com/post/onlyswitch/) | [OSCHINA](https://www.oschina.net/p/onlyswitch) |
| [Macken](https://www.macken.xyz/2021/12/gratis-ar-gott-alla-installningar-pa-ett-stalle-onlyswitch/) | [AAPL Ch](https://applech2.com/archives/20220111-onlyswitch-all-in-one-status-bar-button-for-mac.html) | [appsofter](https://appsofter.com/download/1265.html) | [lifehacker.ru](https://lifehacker.ru/onlyswitch) |
| [appletechnikblog](https://appletechnikblog.com/de/2022/02/25/app-tipp-der-woche-only-switch-fuer-die-menueleiste-auf-dem-mac/) | [All-in-One person](https://en.blog.themarfa.name/how-to-quickly-manage-macos-system-settings/) | [Mac Gadget](https://www.macgadget.de/News/2022/03/24/OnlySwitch-Schnellzugriff-auf-viele-Systemfunktionen-per-Mac-Menueleiste) | [MaxiApple](https://www.maxiapple.com/2022/05/onlyswitch-macos-mac-gratuit.html) |
| [insmac](https://insmac.org/macosx/5018-onlyswitch.html) | [tchgdns](https://tchgdns.de/onlyswitch-macos-open-source/) | [insmac](https://insmac.org/macosx/5018-onlyswitch.html) | [macbff](https://macbff.com/onlyswitch-2-3-1/) |
| [korben](https://korben.info/controler-macos-onlyswitch.html) | [macg](https://www.macg.co/logiciels/2023/03/onlyswitch-ajoute-une-pelletee-de-raccourcis-pratiques-votre-barre-des-menus-135357) | [korben](https://korben.info/controler-macos-onlyswitch.html) | [AlternativeTo](https://alternativeto.net/software/only-switch) |
| [macsoft.jp](https://macsoft.jp/onlyswitch/) | [macgeneration](https://www.macg.co/logiciels/2023/03/onlyswitch-ajoute-une-pelletee-de-raccourcis-pratiques-votre-barre-des-menus-135357) | [hdwh.de](https://hdwh.de/onlyswitch-vereinfacht-eure-routinearbeit-mit-praktischen-schaltern/) | [MacKed](https://macked.app/onlyswitch.html) |
| [Mac Torrents](https://www.tntmactorrent.net/onlyswitch-for-mac-free-download/) | [PCtipp](https://www.pctipp.ch/praxis/mac/mac-tipp-onlyswitch-2-2892320.html) | [lifehacker](https://lifehacker.com/tech/change-hidden-mac-settings-with-onlyswitch) | [PHAPLUAT](https://kynguyenso.plo.vn/su-dung-onlyswitch-de-tuy-chinh-tat-ca-cai-dat-may-mac-nhanh-hon-post776151.html) |
| [Techgedöns](https://tchgdns.de/onlyswitch-menueleisten-multitool-bekommt-widgets-fuer-den-mac-desktop/) | [MacVince](https://www.youtube.com/watch?v=ARfBLKzRQY4&t=41s) | [onmymenubar](https://onmymenubar.app/onlyswitch/) | |

### Contributors

#### Translation

| Language | Contributor | Language | Contributor |
|---|---|:---|:---|
| German | @C0d3Br3aker | Italian | @bellaposa |
| Croatian | @milotype | Russian | @kirillyakopov |
| Turkish | @berkbatuhans | Spanish | @kant |
| Polish | @kpacholak | Japanese | @ShogoKoyama |
| Dutch | Alex | Somali | @abdorizak |
| Filipino | Rosel | Korean | @iosdevted |
| French | @BtKent and Ange Lefrère | Ukrainian | @andryua |
| Slovak | @Svec-Tomas | Portuguese (BR) | @EvertonCa |
| Czech | @ForksApps | | |

Additional thanks to:

- @wrngwrld for the Radio Player volume slider.
- @kant for syntax fixes.
- @Ryderwe for Authenticator.
- @lou1s19 for Claude models in Only Agent, Sound Mixer, and external-monitor dimming.
- @oecer for settings backup.

## Acknowledgements

- Night Shift refers to [Nocturnal](https://github.com/joshjon/nocturnal).
- [LaunchAtLogin](https://github.com/sindresorhus/LaunchAtLogin).
- AirPods Battery refers to [AirPods Battery Monitor For Mac OS](https://github.com/mohamed-arradi/AirpodsBattery-Monitor-For-Mac).
- Dynamic-wallpaper processing refers to [this article](https://itnext.io/macos-mojave-dynamic-wallpaper-fd26b0698223) and [wallpapper](https://github.com/mczachurski/wallpapper).
- [AlertToast](https://github.com/elai950/AlertToast).
- [AudioStreamer](https://github.com/syedhali/AudioStreamer), modified for live streaming.
- [AudioSpectrum](https://github.com/potato04/AudioSpectrum), modified for AppKit.
- [Alamofire](https://github.com/Alamofire/Alamofire).
- Sounds from [Mixkit](https://mixkit.co) and [Pixabay](https://pixabay.com).
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts).
- Apple Music and Spotify switches refer to [SpotMenu](https://github.com/kmikiy/SpotMenu).
- The Hide Menu Bar Icons concept comes from [Hidden](https://github.com/dwarvesf/hidden).
- FKey refers to [Fluor](https://github.com/Pyroh/Fluor).
- Hide Windows refers to [Later](https://github.com/alyssaxuu/later).
- [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture).
- [Sparkle](https://github.com/sparkle-project/Sparkle).
- True Tone refers to [Shifty](https://github.com/thompsonate/Shifty).
- [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui).
- Key Light refers to [mac-brightnessctl](https://github.com/rakalex/mac-brightnessctl).
- [AIProxySwift](https://github.com/lzell/AIProxySwift).
- [ollama-swift](https://github.com/mattt/ollama-swift).
- [CodexKit](https://github.com/timazed/CodexKit).
- The Codex Usage experience was inspired by [CodexBar](https://github.com/steipete/CodexBar).

## License

OnlySwitch is available under the MIT License.
