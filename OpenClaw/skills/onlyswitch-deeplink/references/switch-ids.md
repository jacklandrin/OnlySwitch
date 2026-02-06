# OnlySwitch built-in switch IDs

Deeplink format: `onlyswitch://run?type=builtIn&id=<id>`

Match user intent (e.g. "empty trash", "toggle keep awake") to one row below, then use the **id** in the URL.

| id | Title / primary name | Aliases / phrases that map here |
|----|----------------------|----------------------------------|
| 1 | Hide Desktop | hide desktop, desktop icons |
| 2 | Dark Mode | dark mode, dark theme |
| 4 | Hide Notch | notch, top notch, hide notch |
| 8 | Mute | mute, mute sound, unmute |
| 16 | Keep Awake | keep awake, prevent sleep, caffeinate, stay awake |
| 32 | Screen Saver | screen saver, start screensaver |
| 64 | Night Shift | night shift |
| 128 | Autohide Dock | autohide dock, hide dock |
| 256 | Autohide Menu Bar | autohide menu bar, hide menu bar |
| 512 | AirPods | airpods |
| 1024 | Bluetooth | bluetooth |
| 2048 | Xcode Derived Data | xcode cache, derived data, clear xcode cache |
| 4096 | Show Hidden Files | hidden files, show hidden files |
| 8192 | Radio Player | radio, radio station |
| 16384 | Empty Trash | empty trash, trash |
| 32768 | Empty Pasteboard | empty pasteboard, clear clipboard, pasteboard |
| 65536 | Show User Library | user library, show library |
| 131072 | Show Extension Name | extension name, file extensions |
| 262144 | Pomodoro Timer | pomodoro, timer |
| 524288 | Small Launchpad Icon | small launchpad, launchpad icon |
| 1048576 | Low Power Mode | low power, low power mode |
| 2097152 | Mute Mic | mute mic, mute microphone, microphone |
| 4194304 | Show Finder Path Bar | finder path bar, path bar |
| 8388608 | Recent Apps in Dock | recent apps, dock recent |
| 16777216 | Spotify | spotify |
| 33554432 | Apple Music | apple music, music |
| 67108864 | Screen Test | screen test |
| 134217728 | Hide Menu Bar Icons | hide menu bar icons, menubar icons |
| 268435456 | FKey | fkey, function key |
| 536870912 | Back Noises | back noises, background noise |
| 1073741824 | Dim Screen | dim screen |
| 2147483648 | Eject Discs | eject discs, eject |
| 4294967296 | Hide Windows | hide windows |
| 8589934592 | True Tone | true tone |
| 17179869184 | Top Sticker | top sticker, sticker |
| 34359738368 | Key Light | key light |
| 68719476736 | Only Agent | only agent, ai commander, ai commender |
| 137438953472 | Authenticator | authenticator |

When the user's request doesn't exactly match a title, use the **Aliases** column (and the title) to pick the correct id.
