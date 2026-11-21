---
title: "Shapes and color"
summary: "The shapes, their labels, fill and stroke, styles that last or apply once, gradients, blending and clipping."
weight: 3
---

## Where things go

The window's top-left corner is `0 0`. The first number of a position is how far to the right, the second how far down, in pixels. A window opened without a size, like the one a sketch gets when it never calls `window`, is 800 by 600.

## The shapes

Every shape is written with labels that say what its numbers are:

```roci gallery
circle at 120 100 radius 50 fill gold
ellipse at 300 100 size 140 70 fill gold
rect at 60 200 size 120 80 fill gold
square at 240 200 size 80 fill gold
line from 380 40 to 520 160 stroke 0 thickness 3
point at 450 260 stroke 0 thickness 10
arc at 600 120 size 120 120 from 180 to 360 fill gold
```

A line and a point are drawn with the stroke, the color of outlines, and a new sketch starts with none, so these two give theirs: black, 3 and 10 pixels wide. Fill and stroke are below.

`at` takes two numbers or one vector, so a position kept in a name works the same:

```roci picture
fill gold
center = { 200, 150 }
circle at center radius 40
```

`triangle` and `quad` take their corners as vectors, in order around the shape:

```roci picture
fill gold
triangle { 100, 40 } { 180, 180 } { 20, 180 }
quad { 220, 40 } { 360, 60 } { 340, 180 } { 240, 160 }
```

`polygon` takes a list of any number of corners and fills the shape they make, joined in order and closed. A house, a wall in a city, a patch of land:

```roci picture
fill tomato
polygon [ { 60, 180 } { 60, 100 } { 120, 50 } { 180, 100 } { 180, 180 } ]
fill gold
polygon [ { 220, 180 } { 220, 60 } { 250, 60 } { 250, 90 } { 300, 90 } { 300, 180 } ]
```

A shape can have holes. Give `polygon` a list of lists: the first is the outline, and each list inside it is a hole cut out of it (and one inside a hole fills again):

```roci picture
wall = [ { 40, 30 } { 360, 30 } { 360, 170 } { 40, 170 } ]
hole = [ { 120, 60 } { 280, 60 } { 280, 140 } { 120, 140 } ]
island = [ { 170, 85 } { 230, 85 } { 230, 115 } { 170, 115 } ]
fill tomato
polygon [ wall hole island ]
```

A line that crosses itself does not make a hole: the shape is filled whole. Cut a hole with a second list.

Circles, ellipses and arcs are placed by their middle; rectangles and squares by their top-left corner. `as center` or `as corner` after a shape's numbers changes that for one shape:

```roci picture
fill gold
rect at 200 150 size 120 80 as center
```

`round` after a rectangle's or a square's numbers rounds its corners by that many pixels, for buttons, cards and icons. A number bigger than half the shorter side gives the roundest corners the shape can have, and `round 0` keeps them sharp. It takes a fill, a stroke, a gradient or a picture as any shape does:

```roci picture
fill gold
rect at 60 60 size 280 180 round 28
stroke 40
thickness 6
square at 200 150 size 100 round 50 as center
```

## Fill and stroke

`fill` colors the inside of shapes, `stroke` the line around them, and `thickness` how wide that line is. Each lasts until it is changed:

```roci picture
fill gold
stroke 40
thickness 6
circle at 100 100 radius 50
square at 200 60 size 80
no stroke
circle at 360 100 radius 50
```

`no fill` and `no stroke` turn one off. A new sketch fills in black, with no stroke.

## Colors

A color is a name from the CSS list (`tomato`, `gold`, `skyblue`, `navy`, …), a hex code (`#ff8800`), one number for a gray (`0` black to `255` white), or made from numbers:

```roci picture
fill (rgb 255 136 0)
circle at 60 100 radius 40
fill (hsb 160 200 230)
circle at 160 100 radius 40
fill (oklch 0.7 0.15 250)
circle at 260 100 radius 40
fill (mix red blue 0.5)
circle at 360 100 radius 40
```

`rgb`, `hsb` and the gray number count from 0 to 255; `oklch` follows its CSS form. `alpha` says how solid things are, from 0 (gone) to 100 (solid):

```roci picture
fill tomato
alpha 50
circle at 160 150 radius 80
circle at 240 150 radius 80
```

## Styling one shape, or a group

The style words also work at the end of a single shape, for that shape only:

```roci picture
background 60
circle at 100 100 radius 40 fill teal stroke white thickness 3
circle at 220 100 radius 40
```

`with` styles a block of shapes and puts the style back afterwards:

```roci picture
background 60
with fill gold stroke 30 thickness 4 [
  circle at 100 100 radius 40
  square at 180 60 size 80
]
circle at 340 100 radius 40
```

A style can be kept in a record and used again, with `style` on one shape or with `with` on a group:

```roci picture
background 60
glow = { fill: skyblue, stroke: white, thickness: 3 }
circle at 100 100 radius 40 style glow
with glow [ square at 180 60 size 80 ]
```

## Gradients

A list of colors where a color goes makes a gradient, spread across the shape:

```roci picture
rect at 20 20 size 360 80 fill [ navy purple orange ]
circle at 200 220 radius 70 fill (gradient [ white teal ] as radial)
background (gradient [ (rgb 20 20 60) black ] angle 90)
```

`angle` turns it (90 runs top to bottom), `as radial` and `as conic` make it round, and `stops` says where each color sits, in percent. Colors are mixed evenly by default; `in rgb` mixes them the older way.

```roci picture
// the same three colors: spread evenly, then with gold held back to 80 percent
rect at 20 20 size 360 50 fill [ navy gold teal ]
rect at 20 80 size 360 50 fill (gradient [ navy gold teal ] stops [ 0 80 100 ])
// a conic gradient sweeps round the middle
circle at 90 220 radius 60 fill (gradient [ navy gold navy ] as conic)
// blue to yellow mixed evenly, then the older way
rect at 180 170 size 200 40 fill [ blue yellow ]
rect at 180 220 size 200 40 fill (gradient [ blue yellow ] in rgb)
```

## Line ends and corners

`caps` says how lines end (`butt`, `round`, `square`), and `joins` how outlines turn corners (`miter`, `round`, `bevel`):

```roci picture
stroke 30
thickness 16
caps round
line from 40 60 to 360 60
joins round
no fill
triangle { 100, 260 } { 200, 120 } { 300, 260 }
```

## Blending

`blend` says how what you draw mixes with what is already there. The start is `normal`, which covers it by the shape's alpha. `add` and `screen` make light, `multiply` makes ink and shadow, `subtract` takes color away and `lighten` keeps the brighter of the two:

```roci picture
background 30
no stroke
blend add
fill red
circle at 140 130 radius 70
fill lime
circle at 220 130 radius 70
fill blue
circle at 180 190 radius 70
```

Like `fill`, a blend lasts until it is changed and starts again as `normal` in each frame. One shape can carry its own (`circle at 100 100 radius 50 blend add`), and a group can too (`with blend multiply [ ... ]`). Text and pictures blend the same way.

## Clipping

`clip` keeps what you draw inside a box. It takes the same words as `rect`, and it lasts until `no clip`:

```roci picture
clip at 120 60 size 160 180
fill gold
circle at 200 150 radius 110
fill tomato
rect at 100 170 size 200 30
no clip
no fill
stroke navy
rect at 120 60 size 160 180
```

The box is placed by the transform of the moment, so `move` before it and it moves too. A box that has been turned clips to the smallest upright box round it, because the window cuts along straight lines. A `push [ ]` or a `with [ ]` puts the clip back as it was when it ends. `examples/blend` shows that, and the next part.

A clip written while another is in force is inside it, and keeps only what is inside both. `no clip` goes back to the clip it was inside, one at a time, so a picture can be cut to a rounded square as a whole and have a part of it cut to a circle too:

```roci picture
clip square at 100 60 size 200 round 40
fill gold
circle at 200 150 radius 130
clip circle at 280 90 radius 70
fill tomato
circle at 200 150 radius 130
no clip
fill navy
rect at 100 200 size 200 30
no clip
```

The circle shows only where it is inside the square, the navy bar is cut by the square alone, and the last `no clip` ends the square. A sketch that wants one clip to replace another writes `no clip` between them.

A clip can be a shape instead of a box. `clip circle`, `clip ellipse`, `clip rect`, `clip square` and `clip polygon` take the words of the shapes they are named for, and `clip rect` and `clip square` take `round` as well:

```roci picture
clip circle at 200 150 radius 90
fill gold
circle at 200 150 radius 130
fill tomato
rect at 90 190 size 220 30
no clip
no fill
stroke navy
circle at 200 150 radius 90
```

A shape clip is worked out in the transform of the moment too, a turned one is turned, and `clip polygon [ ... ]` takes the corners of any shape, with a second list for a hole. The rest works as for the box: a clip inside it keeps only what is inside both, `no clip` takes it away, and `push [ ]` and `with [ ]` put the old one back.

