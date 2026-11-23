---
title: "Making an iPhone app"
summary: "Turn a sketch into a signed iPhone app and .ipa with roci package ios: name, id, icon, launch colour, version, orientation, and what the signature allows."
weight: 38
---

Only a Mac can make an iPhone app, because Apple's tools run only there. You need Xcode, with your Apple ID added in Xcode's Settings, Accounts (a free account works), and the phone's libraries, which `roci` builds the first time (a couple of minutes). Then:

```
roci package ios
```

It asks the name, id and version once and keeps them in `sketch.toml`, then makes `output/package/ios/` with the app (`build/app/<name>.app`) and `<name>-<version>-ios.ipa`. The build number rises by one each time an app was made.

## What the sketch says

- **Name, id, version**: as for every system. An iPhone id holds letters, digits and hyphens with dots between the parts.
- **Icon**: `icons/icon.svg` or `icons/icon.png`, as in [app icons](../34-app-icons/). The iPhone's is the opaque square.
- **Orientation**: `orientation = "portrait"`, `"landscape"` or `"any"` in `sketch.toml`.
- **Launch colour**: `launch-colour = "#101820"` is the colour the phone shows while the app starts, so make it your `background`. It is light gray when you say nothing.
- **Microphone and camera**: the app asks for them only when the sketch uses `mic` or `webcam`.

## Installing it

Plug the phone in, unlock it and trust the Mac, find its id with `xcrun devicectl list devices`, and run the `xcrun devicectl device install app` line that `roci package` prints. The first time, trust your Apple ID on the phone (Settings, General, VPN & Device Management). If Xcode knows more than one team, name it with `--team`.

## What the signature allows

The app is signed with your development team, so it runs only on phones that signature knows, and a free account's signature lasts seven days. The App Store needs a distribution signature and an Apple Developer Program account; that comes later.
