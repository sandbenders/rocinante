---
title: "Windows"
summary: "Opening windows with settings, changing them while they run, several windows, sending values between them, and asking about the screens and the system."
weight: 10
---

## One window

A sketch that never opens a window gets one of 800 by 600. `window` opens one of your choice, with its settings as words:

```roci picture
window size 400 300 title "garden" resizable false
background navy
circle at 200 150 radius 60 fill gold
```

Other settings are `at` (where on the screen), `bordered`, `topmost`, `fullscreen`, `alpha` (how solid the whole window is), `smallest` and `largest` (size limits), `ratio`, `cursor none`, and more; the [window](../../reference/window/) page lists them all. `width` and `height` are the size of the window the code runs in.

## Changing a window that is open

A window is read as a record of its settings, and changed with `set` and the same words:

```roci
w = window size 400 300
on key "1" [ set w size 400 300 ]
on key "2" [ set w size 640 480 ]
on key "t" [ set w topmost (not w.topmost) ]
draw w [
  background 240
  circle at (w.width / 2) (w.height / 2) radius 40
]
```

Some settings are only a request on some systems: a window manager may decide where a window goes, for example.

## How often a window draws

A window draws a new frame each time its screen refreshes: 60 times a second on most screens, but 120 or 144 on many newer ones. A sketch that moves things by a step every frame, or waits a number of frames, then runs faster on a faster screen. `fps` keeps it at most at the rate you give, whatever the screen:

```roci
w = window size 720 1280 fps 60
x = 0
draw [
  background 20
  x = x + 4
  if x > width [ x = 0 ]
  circle at x 640 radius 30 fill gold
]
```

The dot crosses at the same speed on every screen. `set w fps 30` changes the rate while the sketch runs, `set w fps 0` takes the limit away, and `w.fps` is the limit the window asked for (0 for none). `fps` on its own is the rate the sketch is drawing at now. With several windows, the sketch draws at the lowest limit any of them asked for, since every window is drawn in each frame.

When the screen's refresh is not a whole multiple of the rate, such as 60 on a 144 Hz screen, frames come two and three refreshes apart in turn: the rate is right on average, but the movement is a little less smooth than on a 60 or 120 Hz screen. `roci run --stats` says so in its box. A run with no window (`roci run --frames`, `roci test`) takes one frame at the rate for each frame, or a sixtieth of a second when no rate was asked for.

## Several windows

Each window gets its own `draw` block, named after the window:

```roci
palette = window size 200 200 title "palette"
stage = window size 400 300 title "stage"
draw palette [ background tomato ]
draw stage [
  background 240
  circle at mouse radius 20
]
```

`on` can name a window too: `on stage key "space" [ ... ]` runs only for keys pressed in that window.

## Sending values between windows

`send` puts a value in another window's post, and `on window receive name` takes it, a frame later:

```roci
control = window size 200 150 title "control"
stage = window size 400 300 title "stage"
spot = { 200, 150 }
on control mouse down [ send stage { at: mouse * 2 } ]
on stage receive message [ spot = message.at ]
draw stage [
  background 30
  circle at spot radius 20 fill gold
]
```

A message is copied on the way, so the two windows never share a list or record.

## The screens and the system

`screens` is every screen that is plugged in, the main one first. Each is a record with its `name`, its `pos` on the desktop all the screens share (negative for one left of or above the main screen), its `width` and `height` in the units a window is sized in, its `density`, its `refresh` rate and `main`, true for the main screen:

```roci
main_screen = item 1 of screens
window size (main_screen.width / 2) (main_screen.height / 2) at 40 40
print (main_screen.name + " is " + main_screen.width + " by " + main_screen.height)
```

A window of a screen's `width` and `height` covers that screen. The real pixels are `width * density`: `density` is 2 on a Retina screen and 1 on most others. A screen plugged in or out shows at the next frame. A run with no screen to ask (`roci run --frames`, which has no window) has one of 1920 by 1080, so a sketch that sizes itself by the screen draws the same picture everywhere.

`platform` is the system the sketch is running on, as text: `"macos"`, `"windows"`, `"linux"`, `"freebsd"`, `"openbsd"`, `"ios"` or `"android"`. It is the system the sketch runs on, not the one it was written on, so a sketch can look after a phone differently:

```roci
if platform is "ios" or platform is "android" [
  print "a phone"
]
```

`examples/screens` draws every screen where it sits on the desk, and `examples/platform` draws a simple mark for the system it runs on (the arrow keys show the others).
