---
title: "Windows"
summary: "Opening windows with settings, changing them while they run, several windows, and sending values between them."
weight: 10
---

## One window

A sketch that never opens a window gets one of 800 by 600. `window` opens one of your choice, with its settings as words:

```roci
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

## Several windows

Each window gets its own `draw` block, named after the window:

```roci
palette = window size 200 200 title "palette"
canvas = window size 400 300 title "canvas"
draw palette [ background tomato ]
draw canvas [
  background 240
  circle at mouse radius 20
]
```

`on` can name a window too: `on canvas key "space" [ ... ]` runs only for keys pressed in that window.

## Sending values between windows

`send` puts a value in another window's post, and `on window receive name` takes it, a frame later:

```roci
control = window size 200 150 title "control"
canvas = window size 400 300 title "canvas"
spot = { 200, 150 }
on control mouse down [ send canvas { at: mouse * 2 } ]
on canvas receive message [ spot = message.at ]
draw canvas [
  background 30
  circle at spot radius 20 fill gold
]
```

A message is copied on the way, so the two windows never share a list or record.
