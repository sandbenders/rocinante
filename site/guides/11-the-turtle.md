---
title: "The turtle"
summary: "Drawing by walking and turning, as in Logo: forward, right, the pen, push, and trees."
weight: 11
---

Each window has a **turtle**: a pen that starts in the middle of the window, facing up. It draws as it walks.

```roci
repeat 4 [
  forward 100
  right 90
]
```

`forward` and `back` walk, `left` and `right` turn by degrees (`right` turns clockwise), and `home` goes back to the middle, facing up, without drawing. `pen up` stops it drawing and `pen down` starts again:

```roci
repeat 12 [
  forward 20
  pen up
  forward 20
  pen down
]
```

The turtle draws its lines in the stroke colour and thickness, so set them first. With the stroke off, as in a new sketch, it draws in black.

```roci
stroke tomato
thickness 4
repeat 5 [
  forward 150
  right 144
]
```

## The turtle in draw

Like the style, the turtle starts again at home every frame, and `push [ ]` puts it back where it was afterwards. Together with a verb that uses itself, that draws trees:

```roci
learn branch size [
  if size < 8 [ stop ]
  thickness (size / 10)
  forward size
  push [
    left 20
    branch (size * 0.7)
  ]
  push [
    right 30
    branch (size * 0.7)
  ]
]
draw [
  background 240
  stroke (rgb 70 50 40)
  pen up
  back 140
  pen down
  branch 80
]
```

Logo's short words (`fd`, `rt`, `pu`) are not words of rocinante, but writing one gets you a message naming the whole word.
