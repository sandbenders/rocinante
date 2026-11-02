---
title: "The turtle"
summary: "Drawing by walking and turning, as in Logo: forward, right, the pen, push, trees, and reading where it is."
weight: 11
---

Each window has a **turtle**: a pen that starts in the middle of the window, facing up. It draws as it walks.

```roci picture
repeat 4 [
  forward 100
  right 90
]
```

`forward` and `back` walk, `left` and `right` turn by degrees (`right` turns clockwise), and `home` goes back to the middle, facing up, without drawing. `pen up` stops it drawing and `pen down` starts again:

```roci picture
repeat 12 [
  forward 20
  pen up
  forward 20
  pen down
]
```

The turtle draws its lines in the stroke color and thickness, so set them first. With the stroke off, as in a new sketch, it draws in black.

```roci picture
stroke tomato
thickness 4
repeat 5 [
  forward 150
  right 144
]
```

## The turtle in draw

Like the style, the turtle starts again at home every frame, and `push [ ]` puts it back where it was afterwards. Together with a verb that uses itself, that draws trees:

```roci picture
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


## Where is the turtle?

`turtle` is a value you can read. It is a record with three fields: `pos`, where the turtle is; `angle`, the way it faces in degrees turning clockwise from up (always from 0 up to 360); and `down`, true while its pen is down. A turtle that has turned a whole four right angles reads 0 again.

`show turtle` draws the turtle itself where it is: a small triangle pointing the way it faces. It is solid while the pen is down and only an outline while the pen is up. It uses the stroke color (black when there is no stroke) and leaves the style as it was.

```roci picture
draw [
  background 240
  stroke teal
  thickness 3
  for i from 1 to 40 [
    forward (i * 1.2)
    right 25
    circle at turtle.pos radius 3 fill (hsb turtle.angle 180 220)
  ]
  show turtle
]
```

Logo's short words (`fd`, `rt`, `pu`) are not words of rocinante, but writing one gets you a message naming the whole word.
