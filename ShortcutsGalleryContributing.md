# How to contribute for Shortcuts Gallery

Since version 2.1.1, OnlySwitch supports contributing for Shortcuts Gallery. Everyone can share macOS shortcuts on OnlySwitch.

## Note
Before contributing, please make sure these:
* The Shortcut can normally run for everyone.
* The Shortcut should better be in English.
* The Shortcut actions don't dependent on other Apps, except OnlySwitch.

The unqualified contributions will be rejected.

## Format
The shared Shortcuts are stored in a [JSON file](OnlySwitch/ShortcutsMarket/ShortcutsMarket.json), and the format is this:
```
{
    "name": "Toggle Scroll Direction",
    "link": "https://www.icloud.com/shortcuts/8d65c606d1924f098b22774de6dc08f8",
    "author": "jacklandrin",
    "description": "Toggle scroll direction of trackpad and mouse wheel"
}
```
* name: Shortcuts' name, it must be as same as in the macOS Shortcuts App. Don't rename it here.
* link: shared iCloud link
* author: author's name
* description: describe functions of the Shortcut.

## Contributing

New Shortcuts can be contribute by **pull request**. If contributor isn't a Github user, OnlySwitch also accepts contribution from email.

### Pull Request on Github

1. Check if the Shortcuts eligible.
2. Fork the repo
3. Checkout a new branch
4. Add the new Shortcuts information on `ShortcutsMarket.json` following the rule.
5. Commit your modified json file
6. Push your branch
7. Create a pull request
8. Congratulations! You are done now, and your Shortcuts should be pulled in or otherwise noticed in a while. If a maintainer suggests some changes, just make them on your branch locally and push.

### By email

Contributors also can send email to jacklandrin@hotmail.com. Just you have to keep the json format above.
