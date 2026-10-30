---
title: "Shapes and colour"
summary: "The shapes, their labels, fill and stroke, styles that last or apply once, gradients."
weight: 3
---

## Where things go

The window's top-left corner is `0 0`. The first number of a position is how far to the right, the second how far down, in pixels. A window opened without a size, like the one a sketch gets when it never calls `window`, is 800 by 600.

## The shapes

Every shape is written with labels that say what its numbers are:

```roci gallery
circle at 120 100 radius 50
ellipse at 300 100 size 140 70
rect at 60 200 size 120 80
square at 240 200 size 80
line from 380 40 to 520 160 stroke 0 thickness 3
point at 450 260 stroke 0 thickness 10
arc at 600 120 size 120 120 from 180 to 360
```

A line and a point are drawn with the stroke, the colour of outlines, and a new sketch starts with none, so these two give theirs: black, 3 and 10 pixels wide. Fill and stroke are below.

`at` takes two numbers or one vector, so a position kept in a name works the same:

```roci picture
centre = { 200, 150 }
circle at centre radius 40
```

`triangle` and `quad` take their corners as vectors, in order around the shape:

```roci picture
triangle { 100, 40 } { 180, 180 } { 20, 180 }
quad { 220, 40 } { 360, 60 } { 340, 180 } { 240, 160 }
```

Circles, ellipses and arcs are placed by their middle; rectangles and squares by their top-left corner. `as center` or `as corner` after a shape's numbers changes that for one shape:

```roci picture
rect at 200 150 size 120 80 as center
```

## Fill and stroke

`fill` colours the inside of shapes, `stroke` the line around them, and `thickness` how wide that line is. Each lasts until it is changed:

```roci picture
fill gold
stroke 40
thickness 6
circle at 100 100 radius 50
square at 200 60 size 80
no stroke
circle at 360 100 radius 50
```

`no fill` and `no stroke` turn one off. A new sketch fills in white, with no stroke.

## Colours

A colour is a name from the CSS list (`tomato`, `gold`, `skyblue`, `navy`, …), a hex code (`#ff8800`), one number for a grey (`0` black to `255` white), or made from numbers:

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

`rgb`, `hsb` and the grey number count from 0 to 255; `oklch` follows its CSS form. `alpha` says how solid things are, from 0 (gone) to 100 (solid):

```roci picture
fill tomato
alpha 50
circle at 160 150 radius 80
circle at 240 150 radius 80
```

## Styling one shape, or a group

The style words also work at the end of a single shape, for that shape only:

```roci picture
circle at 100 100 radius 40 fill teal stroke white thickness 3
circle at 220 100 radius 40
```

`with` styles a block of shapes and puts the style back afterwards:

```roci picture
with fill gold stroke 30 thickness 4 [
  circle at 100 100 radius 40
  square at 180 60 size 80
]
circle at 340 100 radius 40
```

A style can be kept in a record and used again, with `style` on one shape or with `with` on a group:

```roci picture
glow = { fill: skyblue, stroke: white, thickness: 3 }
circle at 100 100 radius 40 style glow
with glow [ square at 180 60 size 80 ]
```

## Gradients

A list of colours where a colour goes makes a gradient, spread across the shape:

```roci picture
rect at 20 20 size 360 80 fill [ navy purple orange ]
circle at 200 220 radius 70 fill (gradient [ white teal ] as radial)
background (gradient [ (rgb 20 20 60) black ] angle 90)
```

`angle` turns it (90 runs top to bottom), `as radial` and `as conic` make it round, and `stops` says where each colour sits, in percent. Colours are mixed evenly by default; `in rgb` mixes them the older way.

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
