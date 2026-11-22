---
title: "App icons"
summary: "One picture, every icon: roci package makes each system's icons, in its shape, from a square SVG or a large PNG, and keeps the ones you draw yourself."
weight: 34
---

An app needs its icon many times over: ten sizes for the Mac, one for the iPhone, ten for Windows, eleven for Linux, and more than twenty for Android, each in the shape that system expects. You draw it once. Put a square picture in the sketch's `icons` folder, and `roci package` makes all of them:

```
icons/icon.svg
```

or

```
icons/icon.png
```

`roci new` and `roci init` make the `icons` folder. You can also hand the picture to `roci package`, which copies it there for next time:

```
roci package macos --icon logo.svg
```

## The picture

**An SVG drawing is best.** It is painted afresh at every size, so even the 16-pixel icons are sharp. Its view box must be square, such as `viewBox="0 0 1024 1024"`. Shapes, paths, strokes, gradients, clip paths, groups, `use` and transforms are all painted; text, pictures inside the drawing, masks, filters and patterns are left out, and `roci package` says which it found. Turn text into paths in your drawing program before saving.

**A PNG must be square and at least 1024 by 1024 pixels**, because the largest icons (the Mac's and the iPhone's) are 1024 pixels. It is scaled down for each size.

A picture that is not square, or a PNG that is too small, stops the packaging before anything is compiled, with a message that says its size and what it should be.

Draw the picture edge to edge, as a square: `roci package` gives each system its own shape.

## What each system gets

| System | Where | Shape |
|---|---|---|
| Mac | `icons/macos/<name>.iconset/` (ten sizes) | Apple's rounded square, 824 of 1024 pixels in the middle, as Apple's template has it (macOS shows any other shape in a gray frame) |
| iPhone | `icons/ios/AppIcon-1024.png` | the picture as it is, over white so nothing is see-through; the iPhone rounds it itself |
| Windows | `icons/windows/<name>-16.png` to `-256.png` and `<name>.ico` | the picture as it is |
| Linux and the BSDs | `icons/freedesktop/hicolor/<size>/apps/<name>.png` (16 to 512 pixels) and, from a drawing, `scalable/apps/<name>.svg` | the picture as it is |
| Android | `icons/android/res/mipmap-*/` and `play-store-512.png` | a rounded square, a circle, and the two layers of an adaptive icon (the picture in the middle, its edges carried out to the border, so any mask the phone uses shows it whole) |

`<name>` is the app's name in small letters, as its files are named: `wildvex`.

The Mac and Linux packages use these today; the other systems' packages will use theirs when `roci package` makes them.

## Your own icons

The icons stay in `icons/`, and are meant to be committed with the sketch. If you draw a size yourself, for instance a simpler 16-pixel icon where the details would blur, put your file in its place: `roci package` uses it as it is and never writes over it.

It knows which files it made because it keeps their fingerprints in `icons/.made`. When you change the picture, it makes again the icons it made from the old one, and leaves alone every file you put there or changed. To have one of yours made again from the picture, delete it.

A folder of icons you drew entirely by hand works too, with no `icon.svg` or `icon.png`: the files are used as they are. Any that are missing get rocinante's logo in that package only, and `roci package` says so.

## No picture

Without a picture, the app wears rocinante's logo, made where the package is made, never in your folder. `roci package` says so at the end, with where to put a picture.
