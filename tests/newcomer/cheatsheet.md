# rocinante on one page

Write in `sketch.roci`, save, and the window changes. Lines that start with `//` are notes for people.

## Shapes

```roci
circle at 300 200 radius 50
rect at 20 20 size 100 60
ellipse at 450 100 size 120 60
line from 0 0 to 600 400
```

## Colour

```roci
background 30
fill orange
stroke white
thickness 4
circle at 300 200 radius 50
no stroke
fill (rgb 255 128 0)
circle at 100 100 radius 20 fill skyblue
```

Colours have names (`red`, `orange`, `skyblue`, `gold`, ...), or are made with `rgb red green blue`, each 0 to 255.

## Making things move

Everything inside `draw [ ]` runs again, many times a second.

```roci
x = 0
draw [
  background 30
  x = x + 2
  circle at x 200 radius 20
]
```

Values you can use anywhere: `mouse` (where the mouse is; `mouse.x` and `mouse.y` are its parts), `width` and `height` (the window's size), `time` (seconds since the start).

```roci
draw [
  background 30
  circle at mouse radius 20
  pulse = 50 + (sin (time * 90)) * 30
  circle at (width / 2) (height / 2) radius pulse
]
```

## Random

```roci
x = random 100
y = random from 50 to 80
repeat 20 [ circle at (random width) (random height) radius 5 ]
```

`random 100` is a number from 0 up to 100.

## Repeating and deciding

```roci
for i from 1 to 10 [ circle at (i * 50) 200 radius i ]
draw [
  if mouse.x > 300 [ fill red ] else [ fill blue ]
  circle at 300 200 radius 40
]
```

## When something happens

```roci
size = 20
on mouse down [ size = size + 10 ]
on key "space" [ size = 20 ]
draw [
  background 30
  circle at mouse radius size
]
```

## The one rule about round brackets

A calculation or a call used as one value goes in round brackets:

```roci
circle at (random width) (height / 2) radius 10
```

Without them, rocinante cannot tell where one value ends and the next begins, and it will show you the line with the brackets added.
