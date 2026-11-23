---
title: "Making an Android app"
summary: "Turn a sketch into a signed APK with roci package android: its name, id, icon, version and orientation, what goes inside, and the key you must keep."
weight: 37
---

On a Mac (a Linux x86-64 or a Windows computer can run it too, by design, but only a Mac has been tried), `roci package android` makes an app of a sketch that a phone can install:

```
roci package android
```

It works in the sketch's folder (or give it a folder), refuses a sketch that has errors as `roci check` does, and asks the name, the id and the version the first time, as the [Mac guide](../32-packaging-a-mac-app/) describes: the answers are kept in `sketch.toml`. Unlike `roci run --compile --target android`, which puts a test build on a phone that is plugged in, this makes an app with a name, an id, an icon and a version of its own, signed with a key of its own, that you can give to someone. The phone's tools have to be set up once, as the [compiling and phones guide](../31-compiling-and-phones/) says (the Android SDK and NDK from Android Studio, and `tools/mobile-sdl.sh android`).

The result is `name-1.0.0-android-arm64.apk` in `output/package/android` of the sketch's folder. To put it on a phone that is plugged in, with USB debugging on, run `adb install -r` with its path (the line `roci package` prints says it); or copy it to the phone and open it there, which makes the phone ask to allow installing from that app. It runs on Android 9 and later, on a phone with a 64-bit ARM processor and Vulkan.

## What the sketch says

| In `sketch.toml` | What it does on Android |
|---|---|
| `name` | the label under the icon |
| `id` | the app's id, which Android knows it by; two apps with the same id replace each other |
| `version` | the version people see |
| `build` | the version number Android tells an update apart by, which `roci package` raises by one each time an app was made |
| `orientation = "portrait"` | how the phone holds it: `portrait`, `landscape` or `any` (the default, the phone decides) |
| `category = "game"` in `[android]` | the kind of app Android files it under: `game`, `audio`, `video`, `image`, `social`, `news`, `maps`, `productivity` or `accessibility` |

Android's ids are written with dots between parts that start with a letter and hold only letters, digits and underscores. A hyphen, which an id made from a title often has, is turned into an underscore, and the line `roci package` prints at the end says so; any other trouble stops the packaging before anything is built, with what to change. Set `category = "game"` for a game: from Android 17 a phone ignores an app's orientation on a large screen, except for games.

The icon is made from the square SVG drawing or the large PNG in the sketch's `icons` folder, as [App icons](../34-app-icons/) explains: Android's adaptive icon (the shape the phone's own launcher cuts) and the round one. The app declares the microphone and the camera permissions only when the sketch uses them (`mic`, `webcam`), as a Mac app is given them; the microphone and the camera on a phone have not been tried yet.

## What goes inside

The program, rocinante's libraries for the phone, and the sketch's `assets` and `libs` and the files it starts from (`ui.toml`, `memory.toml`, the vault), all inside the APK. The program reads them as files in the app's own folder, so the first time the app starts after an install or an update, it copies them there, which takes a moment for a sketch with a lot of pictures or sounds. What the sketch writes (what it remembers, `output/`) is in that folder too, and an update keeps it: a starting file is copied only when the app has no file of that name yet.

## The key

An APK has to be signed, and an update can replace an installed app only if it is signed with the same key. `roci package` makes a key for the app's id the first time, and keeps it, with its password in a file beside it, in rocinante's own folder, outside the sketch's (`~/Library/Application Support/rocinante/android` on a Mac, `~/.local/share/rocinante/android` on Linux): a key in the sketch's folder would go to git with it. It says so when it makes one. **Keep a copy of the key and its password file somewhere safe.** If they are lost, a new version cannot replace the old one on a phone: whoever has the app installed would have to remove it first, and lose what it remembered.

## What it does not do yet

Google Play asks for an Android App Bundle, which comes later; the APK is for installing. A key of your own, chosen for the app, is not read yet either, nor an icon in the phone's theme colours (Android's monochrome icon).
