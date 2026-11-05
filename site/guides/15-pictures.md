---
title: "Pictures"
summary: "Loading pictures from assets, drawing them at any size, tinting and filling with them, and saving the window as a PNG or a frame sequence."
weight: 15
---

A picture is a file in your sketch's `assets` folder. `load` finds it by its file name and gives you the picture, and `image` draws it with its top left at a point:

```roci picture
photo = load "landscape.png"
image photo at 40 50
```

`load` reads PNG, JPEG, BMP, TGA and QOI files, looks through everything in `assets` (so `landscape.png` is found in `assets/images`), and keeps the picture, so loading the same name again costs nothing. `roci add landscape.png` copies a file into the right folder of your sketch. A file that changes while the sketch runs is read again.

## How big

With nothing else, a picture is drawn at its own size. Give a `width` or a `height` and the other side follows, so the picture keeps its shape. Give a `size` and it is stretched to fit:

```roci picture
photo = load "landscape.png"
background 245
image photo at 10 10 width 180
image photo at 210 10 height 60
image photo at 10 130 size 100 150
image photo at 130 130 size { 120, 80 }
```

A picture knows how big it is: `photo.width` and `photo.height` are its size in pixels, which can be read and not changed. A picture is a value like a number, so it can be kept in a list or a record and given to a verb you teach.

## Where it goes

The point after `at` is the top left corner of the picture. `as center` makes it the middle, which is what you want for something that turns:

```roci picture
badge = load "sprite.png"
background 245
for i from 1 to 4 [
  push [
    move (60 + i * 70) 150
    turn (i * 25)
    image badge at 0 0 as center
  ]
]
```

Pictures are moved, turned and grown by `move`, `turn` and `grow` like everything else.

## Color and see-through

`tint` sets the color pictures are drawn through, from now on: each pixel's color is multiplied by it, so white leaves a picture alone, a color tints it, and a color with an alpha makes the whole picture see-through. As a word of one `image` it applies to that picture only, and so does `alpha`:

```roci picture
photo = load "landscape.png"
background 245
image photo at 10 10 width 180
image photo at 210 10 width 180 tint teal
image photo at 10 130 width 180 alpha 40
tint (rgb 255 220 220)
image photo at 210 130 width 180
```

A picture's own transparent pixels stay transparent, so a badge with clear corners shows what is behind it.

## Filling shapes with a picture

`fill` takes a picture as well as a color. Every shape drawn after it becomes a mask that the picture shows through, so a circle becomes a round window onto the picture. A picture is a value like any other, so it can go in a canvas or a record too:

```roci picture
photo = load "landscape.png"
background 245
fill photo
circle at 100 100 radius 70
ellipse at 290 100 size 160 100
triangle { 120, 240 } { 280, 240 } { 200, 120 }
```

How the picture sits in the shape is said with `as`:

- `cover` is the start: the picture is scaled to cover the shape and what overflows is cropped.
- `fit` scales it to show the whole picture, leaving the shape empty where the picture does not reach.
- `stretch` bends it to the shape's width and height.
- `tile` repeats it at its own size, or `size 64` wide with the height following.
- `center` keeps its own size, in the middle.

`at` moves the picture inside the shape, in pixels, for `tile` and `center`. The words go straight after the picture, so they belong to one shape:

```roci picture
photo = load "landscape.png"
badge = load "sprite.png"
background 245
rect at 10 10 size 180 100 fill photo as fit
rect at 210 10 size 180 100 fill photo as stretch
rect at 10 130 size 180 150 fill badge as tile size 30 at 8 8
rect at 210 130 size 180 150 fill photo as center
```

On a line of their own they last, like any style: `fill photo as fit` is the fill of every shape after it, and `with fill photo as fit [ ... ]` is the fill of the shapes in the block. The same goes for a gradient (`fill [ red teal ] as radial`).

An `as` after a plain color is still the shape's origin, so `circle at 10 10 radius 5 fill red as center` puts the middle of the circle at the point. After a picture or a gradient it is the way the paint sits.

A stroke is drawn over the picture, and `alpha` and `tint` apply to it as they do to a drawn picture. `fill red` puts the picture away.

## Pictures as text, outlines and backgrounds

The same words paint more than the inside of a shape. A text takes a picture for its `fill`, and its letters are cut out of the picture:

```roci picture
photo = load "landscape.png"
background 245
font "Inter Bold" size 96
text "photo" at 40 30 fill photo as cover
font "Inter" size 28
text "letters cut from a picture" at 40 170 fill photo as stretch
```

`stroke` takes a picture the same way, for the outline of any shape and for lines and points, and `background` fills the whole window behind everything:

```roci picture
photo = load "landscape.png"
badge = load "sprite.png"
background photo as cover
no fill
thickness 24
stroke badge as tile size 24
circle at 130 150 radius 70
stroke photo as cover
rect at 230 80 size 140 140
```

Each picture sits in the box of the thing it paints: the letters' box for a text, the shape's box for an outline. So `cover` fills that box, and a thick outline reaches a little outside it, where the picture's edge colors continue. Text takes its picture from a file only: a canvas keeps its pixels on the graphics card, so a text filled with one stays in its color. Emoji in such a text are cut from the picture too, as plain shapes.

## When a picture is not there

A name nothing answers draws nothing and says so once, and the sketch carries on:

```message
── I could not load a picture called `cat.png` ───────── sketch.roci:1:9

1 │ photo = load "cat.png"
  │         ^^^^^^^^^^^^^^

Pictures are found by their file name in your sketch's `assets` folder, and there is no file of that name there. `roci add` copies one in for you. The picture draws nothing, and the sketch carries on.

Load one that is there:  photo = load "cat.png"
```

A file that is not a picture, and two files with one name, are said the same way, with the folder to name in the second case.

## Saving a picture of the window

`save "shot.png"` writes a picture of the window as a PNG file. It is the finished frame the line ran in, without the error overlay, at the window's own sharpness (twice as many pixels on a high-density screen). A plain name goes in the sketch's `output` folder, which git leaves out, and any folders in the name are made; an absolute path is used as it is.

```roci
on key "s" [ save "shot.png" ]
```

A run of `#` in the name is the frame's number, so a `save` in `draw` records every frame, ready for a video tool:

```roci
draw [
  circle at (frame * 4) 150 radius 30
  save "frames/frame-####.png"
]
```

That writes `output/frames/frame-0000.png`, `frame-0001.png` and so on. `roci run sketch --frames 120` draws 120 frames with no window, which is the way to record a long sequence quickly. Only PNG is saved, so a name that does not end in `.png` is said and nothing is written; a file that cannot be written is said on the next frame. `examples/export` saves with `s` and records with `r`.
