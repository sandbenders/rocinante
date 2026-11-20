---
title: "Compiling a sketch, and putting it on a phone"
summary: "Turn a sketch into a native program with roci run --compile, see how fast it is, and install it on an iPhone or an Android phone that is plugged in."
weight: 31
---

`roci run` reads your sketch and runs it as you write it, which is what you want while you work. When a sketch is ready, or when you want to know how fast it can go, `--compile` turns it into a native program and runs that instead:

```
roci run --compile
roci run --compile --stats
```

The program does exactly what the sketch did, picture for picture. It is made in the `artifacts` folder of the sketch's folder, and it does not reload when you save. `--stats` shows the frame and the frame rate in a box and says how fast the run was; the sketch that draws a hundred thousand records a frame takes about a quarter of the time compiled.

It needs the version of Odin that rocinante was made for and the source of rocinante next to `roci`. `roci doctor` says what is missing on your computer, and how to get it:

```
roci doctor
```

It also says which kinds of app this computer could build one day: an iPhone app only on a Mac, an Android app on a Mac, a Linux x86-64 computer or Windows.

When a sketch uses something the compiler cannot do yet, `roci run --compile` says so, file by file and line by line, and does nothing: a sketch that runs differently when compiled would be a mistake in rocinante, not in your sketch. Run it without `--compile` and it works.

## On an iPhone

Plug the phone in, unlock it, and run:

```
roci run --compile --target ios
```

`roci` builds the sketch for the phone, signs it with your Apple development team, copies it and its `assets` folder to the phone and starts it there. A free Apple ID is enough (Xcode, Settings, Accounts). The first time, the phone asks you to trust the developer: Settings, General, VPN & Device Management. Each run replaces the last sketch, and a free account's signature lasts seven days.

If you have more than one iPhone, or Xcode knows more than one team, say which: `--device` takes the phone's identifier from `xcrun devicectl list devices`, and `--team` the team's.

## On an Android phone

Turn on USB debugging (Settings, Developer options), plug the phone in, unlock it, accept the computer, and run:

```
roci run --compile --target android
```

The sketch's `assets` go into the app's own folder on the phone, and the app starts. Keep the screen on and unlocked: Android draws nothing for a sleeping phone. With more than one phone connected, set `ANDROID_SERIAL` to the one you mean (`adb devices` lists them).

## Without an Android phone

Android's emulator runs a sketch on a screen of another shape, so a layout can be looked at without owning the phone:

```
roci run --compile --target android-emulator
```

It starts the emulator when none is running (`--device` picks a virtual device by name; `emulator -list-avds` lists them), installs the sketch with its `assets` and starts it. It needs an arm64 virtual device, which Android Studio's Device Manager makes. A picture of what is on the screen, for a script to read, is `adb exec-out screencap -p > shot.png`. It is for layout only: the speed of a sketch there says nothing about a phone, and the emulator has no real camera, microphone or sensors.

There is no such target for the iPhone. Apple's iOS Simulator has a graphics device that is too small for the one rocinante draws with, so a sketch cannot open its window there; an iPhone has to be a real one.

## What the phone needs once

The phone's copy of rocinante's libraries is built once on your computer, from source. For an iPhone, `tools/mobile-sdl.sh ios` builds SDL and `spikes/mobile/ios/libs.sh` the rest; for Android, `tools/mobile-sdl.sh android` and `spikes/mobile/android/libs.sh`. Both need `cmake` and `ninja`, an iPhone needs Xcode, and Android needs the Android SDK and NDK from Android Studio. `roci` tells you which of them is missing, and the line to run, when it needs one.

## What is different on a phone

A finger is the mouse, so `on mouse down`, `mouse` and `touches` all work. There is no keyboard unless the phone shows one, and no window to resize. Sound, pictures, 3D, widgets and the network work; MIDI, the microphone and recording, and screen readers on the phones, are not checked yet. Only what is in `assets` is carried to the phone, so a sketch that reads a file by name finds it there as it does on the computer.

A phone keeps strips of the screen for itself: the clock and the camera at the top, the home bar at the bottom, the rounded corners. `safe` says how wide each strip is, in the window's units: `safe.top`, `safe.bottom`, `safe.left` and `safe.right`, all 0 on a computer. A sketch draws edge to edge on both phones, behind the clock, the camera and the navigation bar, so a background fills the whole screen and only what must be seen needs to stay inside the strips. The numbers change by themselves when the phone turns:

```
text "score" at (safe.left + 20) (safe.top + 40)
```

`vibrate` makes a phone buzz, for a fifth of a second or for the seconds you give (at most five): `on touch down [ vibrate 0.1 ]`. An iPhone buzzes for as long as the system chooses, and a computer does nothing.

When the app goes to the background the sketch stops: nothing is drawn, the clock (`time`, `every`, tweens) stands still, and what the sketch remembers is saved. When it comes back it goes on from where it was, as if no time had passed.
