---
title: "Making a Mac app"
summary: "Turn a sketch into a Mac app with roci package macos: the name, id and version it asks once, what goes inside, and what a Mac says when it is opened."
weight: 32
---

When a sketch is ready to give to someone, `roci package` makes an app of it. On a Mac:

```
roci package macos
```

It works in the sketch's folder (or give it a folder: `roci package macos mysketch`). It refuses a sketch that has errors, as `roci check` would. The first time it asks three things the sketch does not say, and keeps the answers in a file called `sketch.toml` beside `sketch.roci`, so it never asks again:

```
What is the app called? [wildvex]
Its id (a domain you own, backwards, like org.example.wildvex)? [local.wildvex]
Its version (up to three numbers, or date)? [1.0.0]
```

The id is what the Mac knows the app by; use a domain you own, backwards. The version is what people see: up to three numbers, like `1.0.1` or `2026.11.20`, or `date`, which stamps the day you package. `roci` also keeps a build number in the file, one more each time you package, and you never have to look at it. The file is plain text and you may write it yourself:

```
name = "Wildvex"
id = "org.example.wildvex"
version = "1.0.1"
build = 7
```

The icon is made from a square SVG drawing or a PNG of 1024 by 1024 pixels or more in the sketch's `icons` folder (`icons/icon.svg` or `icons/icon.png`, or give it once with `--icon`): `roci package` makes the Mac's ten sizes in Apple's rounded square, and every other system's icons with them, as [App icons](../34-app-icons/) explains. Without one the app wears the rocinante logo.

## What you get

In the sketch's `output/package/macos` folder: the app (`Wildvex.app`) and a zip of it, ready to send. Inside the app are the compiled sketch, everything in `assets/` and `libs/`, and the two libraries it needs (SDL3 and SDL3_ttf), so it runs on a Mac that has nothing of rocinante installed. It is built for the processor of the Mac that made it, and runs on that Mac's macOS or newer.

The app finds its pictures, sounds and fonts inside itself. What it writes (`save` and `record` go to its `output` folder, and what it `remember`s, its vault and its widgets' values) goes in its own folder, `~/Library/Application Support/<its id>`, because an app is not allowed to change itself. A `memory.toml`, `ui.toml`, `vault.bin` or `vault.key` in your sketch folder is copied there the first time the app runs, as its starting point.

The first time it asks for the microphone or the camera, macOS shows a sentence saying the sketch may do so. Only a sketch that uses them asks: `roci package` gives the app the microphone only when the sketch reads `mic` (or records it) and the camera only when it uses `webcam`, and a sketch that uses neither gives macOS nothing to ask about.

## What a Mac says when someone opens it

An app that has no Developer ID cannot be checked by macOS, so on another Mac it says so the first time. The person opening it should Control-click the app, choose Open, and confirm once. To remove that, sign the app with a Developer ID (a certificate from an Apple developer account) and have Apple notarise it. `roci package` signs with a `Developer ID Application` identity it finds in your keychain, or the one you name:

```
roci package macos --sign "Developer ID Application: Your Name (TEAMID)"
roci package macos --sign "Developer ID Application: Your Name (TEAMID)" --notarize my-profile
```

`my-profile` is the name `xcrun notarytool store-credentials` gave your Apple credentials in the keychain. Both can also live in `sketch.toml`, in a `[macos]` part:

```
[macos]
identity = "Developer ID Application: Your Name (TEAMID)"
notary-profile = "my-profile"
```

`roci package` says at the end which of the three cases the app is in.

## What it needs

`roci doctor` lists it. Besides what compiling a sketch needs (Odin, Xcode's command-line tools), the first package builds the libraries the app carries, which takes a minute and needs `cmake` and `ninja` (`brew install cmake ninja`). Homebrew's own SDL3_ttf is not used, because it brings in a library whose licence a shared app may not carry.
