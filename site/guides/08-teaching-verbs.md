---
title: "Teaching verbs"
summary: "Making verbs of your own with learn: values in, give a value back, stop, defaults, recursion."
weight: 8
---

## learn

`learn` teaches rocinante a new verb: its name, the names of what it takes, and a block of what it does. After that it is used like any other verb:

```roci picture
learn flower x y [
  push [
    move x y
    repeat 6 [
      turn 60
      ellipse at 0 -30 size 20 50 fill pink
    ]
    circle at 0 0 radius 10 fill gold
  ]
]
flower 100 150
flower 300 150
```

A verb can be used above the line that teaches it, and from any file of the sketch.

## give

A verb that works out a value hands it back with `give`, which also ends it:

```roci
learn double n [ give n * 2 ]
print (double 21)
```

Every way through a verb that gives a value must reach a `give`; rocinante says which way does not. A verb without `give` is a statement and cannot be used as a value.

## stop

`stop` ends a verb early, without a value:

```roci
learn greet name [
  if name is "" [ stop ]
  print ("hello " + name)
]
greet "ada"
```

## Words with defaults

Words after `with` are optional, each with the value it has when the call leaves it out. They are written like a verb's own words:

```roci picture
learn star size with points 5 [
  repeat points [
    forward size
    right (720 / points)
  ]
]
star 100
star 60 points 7
```

## Changing what a verb is given

Records and lists are shared, so a verb can change one it is given:

```roci picture
learn step p [ p.pos = p.pos + p.vel ]
ball = { pos: { 20, 150 }, vel: { 4, 0 } }
draw [
  background 240
  step ball
  circle at ball.pos radius 20 fill gold
]
```

Names given a value inside a verb belong to the verb; names of the sketch it can read and change.

## A verb that uses itself

A verb may call itself, which is how trees and fractals are drawn. It needs a way to stop:

```roci picture
learn branch size [
  if size < 6 [ stop ]
  forward size
  push [
    left 25
    branch (size * 0.7)
  ]
  push [
    right 25
    branch (size * 0.7)
  ]
]
pen up
back 140
pen down
branch 70
```
