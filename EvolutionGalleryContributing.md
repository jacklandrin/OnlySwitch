# How to contribute to Evolution Gallery

Since version 2.4.3, OnlySwitch supports contributing to Evolution Gallery. Everyone can share Evolutions on OnlySwitch.

## Note
Before contributing, please make sure these:
* The Evolution can normally run for everyone.
* The Evolution should better be in English.
* The Evolution actions aren't dependent on other Apps, except OnlySwitch.

The unqualified contributions will be rejected.

## Format
The shared Evolution are stored in a [JSON file](OnlySwitch/Resource/Evolution/EvolutionMarket.json), and the format is this:
```
{
        "id": "06CE3D9D-354B-4315-9EB2-FDB81720307E",
        "name": "Stage Manager",
        "icon_name": "squares.leading.rectangle",
        "type": "Switch",
        "description": "Toggle Stage Manager(Ventura or higher)",
        "author": "jacklandrin",
        "on_command": {
            "type": "shell",
            "command": "defaults write com.apple.WindowManager GloballyEnabled -bool true"
        },
        "off_command": {
            "type": "shell",
            "command": "defaults write com.apple.WindowManager GloballyEnabled -bool false"
        },
        "check_command": {
            "type": "shell",
            "command": "defaults read com.apple.windowManager GloballyEnabled",
            "true_condition": "1"
        }
    },
    {
        "id": "55B6E9FD-1FFE-4779-B0BE-D7BAF5EC5D2B",
        "name": "Update Software",
        "icon_name": "arrow.clockwise.circle",
        "type": "Button",
        "description": "Check and update software installed via AppStore",
        "author": "jacklandrin",
        "single_command": {
            "type": "shell",
            "command": "softwareupdate -i -a"
        }
    }
```
* id: Each Evolution needs an UUID as its unique identification
* name: Evolution's name
* icon_name: a SF symbol name
* type: "Switch" or "Button"
* description: describe the functionality of the Evolution
* author: contributor's name

If type is "Switch":
* on_command: the command to turn on the switch. type: "shell" or "applescript". **If the type is shell, you need to add extra escape character.** Same below fields,
* off_command: the command to turn off the switch.
* check_command: the command to check if the switch is on. true_condition is the output when switch is on.
If type is "Button":
* single_command: the command when press the button

## Contributing

New Evolution can be contributed by **pull request**. If the contributor isn't a Github user, OnlySwitch also accepts contributions from email.

### Pull Request on Github

1. Check if the Evlution is eligible.
2. Fork the repo
3. Checkout a new branch
4. Add the new Evolution information on `EvolutionMarket.json` following the rule.
5. Commit your modified json file
6. Push your branch
7. Create a pull request
8. Congratulations! You are done now, and your Evolution should be pulled in or otherwise noticed in a while. If a maintainer suggests some changes, just make them on your branch locally and push.

### By email

Contributors also can send email to jacklandrin@hotmail.com. Just you have to keep the json format above.
