---
title: "Mouse, keys and fingers"
summary: "Reading the mouse and the keyboard, waiting for something to happen, the wheel and touch."
weight: 5
---

A sketch can ask how things are now, in `draw`, or wait for something to happen, with `on`.

## Asking

`mouse` is where the mouse is, `pmouse` where it was a frame ago, and `pressed` whether a button is down:

```roci
draw [
  if pressed [ line from pmouse to mouse thickness 4 ]
]
```

This one draws while the button is held, and never clears, so the lines stay.

`held` asks about a key, by its name (`"a"` to `"z"`, `"0"` to `"9"`, `"space"`, `"enter"`, `"left"`, `"right"`, `"up"`, `"down"`, `"shift"`, …), or about a mouse button with `"mouse left"`, `"mouse middle"` and `"mouse right"`:

```roci picture
x = 200
draw [
  background 240
  if held "left" [ x = x - 4 ]
  if held "right" [ x = x + 4 ]
  circle at x 150 radius 30
]
```

`wheel` is how far the mouse wheel turned since the last frame: `wheel.y` up and down, `wheel.x` sideways.

```roci picture
size = 40
draw [
  background 240
  size = clamp (size + wheel.y * 5) 5 140
  circle at 200 150 radius size
]
```

## Waiting for something

`on` runs a block when something happens:

```roci
dots = []
on mouse down [ add mouse to dots ]
on key "c" [ dots = [] ]
draw [
  background 30
  for each d in dots [ circle at d radius 10 fill gold ]
]
```

`on mouse down` and `on mouse up` can name a button: `left`, `middle`, `right`, or the side buttons `back` and `forward`. Without one, any button counts.

```roci
on mouse down right [ print "right" ]
on mouse down back [ print "back" ]
```

Other things to wait for are `on resize`, `on move` and `on focus`, for the window. `key` holds the name of the key pressed last.

## Fingers

On a touch screen, `on touch down` and `on touch up` run when a finger goes down or comes up, and inside them `finger` is that finger, a record with `pos` (where it is), `start` (where it went down), `id` (a number it keeps while it is down) and `pressure`. `touches` is every finger down now:

```roci
draw [
  background 30
  for each f in touches [
    line from f.start to f.pos stroke white
    circle at f.pos radius 40 fill skyblue
  ]
]
```

A finger also moves `mouse` and runs `on mouse down left`, and on a computer the left mouse button counts as one finger, so a sketch for a touch screen can be tried with a mouse.
