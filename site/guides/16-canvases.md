---
title: "Canvases"
summary: "Canvases: pictures you draw into, that keep what is drawn on them from frame to frame, for trails, painting and drawing something once."
weight: 16
---

A canvas is a picture that you draw. `canvas` makes one of a size, `draw into` runs a block whose drawing goes onto it instead of the window, and `image` shows it, as it shows any picture:

```roci picture
c = canvas 160 120
draw into c [
  background 30
  fill orange
  circle at (width / 2) (height / 2) radius 40
  stroke white
  thickness 3
  line from 0 0 to width height
]
background 245
image c at 20 20
image c at 200 20 width 180
image c at 20 160 size 100 100
```

Inside `draw into`, `width` and `height` are the canvas's size, and the drawing starts from the default style, so `fill` and `move` from outside do not reach in, and nothing set inside reaches out. Like a loaded picture, a canvas knows its `width` and `height`, and is a value that can be kept in a list or a record.

## It keeps its drawing

A window starts empty every frame, but a canvas does not: what you draw onto it stays, and the next frame draws on top. That is what makes trails, painting and accumulation easy. Painting a little of the background over it each frame makes the old drawing fade:

```roci
trails = canvas 400 300
draw into trails [ background 20 ]

draw [
  draw into trails [
    fill 20
    alpha 8
    rect at 0 0 size width height
    alpha 100
    fill white
    circle at (200 + cos (time * 90) * 120) (150 + sin (time * 90) * 90) radius 8
  ]
  image trails at 0 0
]
```

`background` and `clear` inside `draw into` start the canvas over: `background 20` fills it, and `clear` leaves it empty and see-through. (The sketch above uses `background` once, to start, and then only adds.)

## Make it once

A canvas is made by `canvas`, so make it once, at the top of the sketch, and draw into it each frame. A `canvas` inside `draw` would make a new, empty canvas every frame.

A canvas is as sharp as the window it is made in: a window drawn at twice the pixels gets a canvas with twice as many, so text and edges stay clean while `width` and `height` still say the size you asked for. When a sketch runs with no window, as the pictures of this documentation do, a canvas has twice the pixels.

## When it is drawn

Everything drawn into a canvas in a frame is put on it at the end of the frame, before the windows are drawn. So every `image` of a canvas in one frame shows the same, finished picture, however the lines are ordered, and a canvas drawn into after the window's own drawing is still up to date when the window shows it.

A canvas can show another canvas (`image other at 0 0` inside `draw into c`), and a canvas can show itself, which shows what it was last frame. A `draw into` cannot sit inside another, because there is one thing being drawn onto at a time:

```message
── I can only draw into a canvas ─────────────────────── sketch.roci:3:3

3 │   draw into c [ circle at 10 10 radius 5 ]
  │   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

A canvas is being drawn into already, and a `draw into` cannot sit inside another. Nothing is drawn, and the sketch carries on.

Make a canvas once, then draw into it:  c = canvas 300 200
```

A picture loaded from a file is not a canvas and cannot be drawn into, and says so the same way.
