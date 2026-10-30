---
title: "Making things move"
summary: "draw, time and frames, moving and turning, tweens and easing, every."
weight: 4
---

## draw

Lines at the top of a sketch run once. Lines inside `draw [ ]` run again for every frame, about sixty times a second. Change a value a little each time and things move:

```roci picture
x = 0
draw [
  background 240
  x = x + 3
  circle at x 150 radius 30
]
```

`background` at the start of `draw` paints over the last frame; without it, every frame draws on top of the ones before, which leaves trails.

Names given a value inside `draw` keep it from one frame to the next, so `x` above keeps growing.

## time and frame

`time` is the seconds since the sketch started, and `frame` how many frames it has drawn. Anything worked out from them moves by itself:

```roci picture
draw [
  background 240
  y = 150 + (sin (time * 90)) * 100
  circle at 200 y radius 30
]
```

Angles are in degrees everywhere, so `sin (time * 90)` goes up and down once every four seconds.

## Moving and turning the drawing

`move`, `turn` and `grow` move, turn and scale everything drawn after them. `push [ ]` keeps them to a block:

```roci picture
draw [
  background 240
  push [
    move 200 150
    turn (time * 60)
    rect at 0 0 size 160 20 as center fill teal
  ]
  circle at 60 60 radius 20
]
```

Without the `push`, the circle would turn too. Every frame starts with no moving or turning at all.

## Tweens

A **tween** moves a name or a field from where it is to a new value, a little each frame, and stops exactly there:

```roci picture
ball = { pos: { 60, 150 } }
on mouse down [ tween ball.pos to mouse over 0.8 as elastic ]
draw [
  background 240
  circle at ball.pos radius 24 fill tomato
]
```

`over` is the seconds it takes, and `as` the way it moves: `smooth` (slow, fast, slow; the usual one), `linear`, `in`, `out`, `back`, `elastic` or `bounce`. Numbers, vectors and colors can all be tweened.

`ease` is the same curve as a plain verb, for sketches that work out their own time: it takes a number from 0 to 1 and gives how far along the movement is:

```roci picture
draw [
  background 240
  t = (time % 2) / 2
  x = 40 + (ease t as bounce) * 320
  circle at x 150 radius 20
]
```

## every

`every` runs a block again and again, every so many seconds or frames:

```roci picture
dots = []
every 1 second [ add anywhere to dots ]
draw [
  background 30
  for each d in dots [ circle at d radius 8 fill gold ]
]
```
