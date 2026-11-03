---
title: "Pictures"
summary: "Loading pictures from assets, drawing them at any size, tinting them, filling shapes with them and making them see-through."
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

`at` moves the picture inside the shape, in pixels, for `tile` and `center`:

```roci picture
photo = load "landscape.png"
badge = load "sprite.png"
background 245
fill photo as fit
rect at 10 10 size 180 100
fill photo as stretch
rect at 210 10 size 180 100
fill badge as tile size 30 at 8 8
rect at 10 130 size 180 150
fill photo as center
rect at 210 130 size 180 150
```

A stroke is drawn over the picture, and `alpha` and `tint` apply to it as they do to a drawn picture. `fill red` puts the picture away. `fill` with a picture is for shapes: lines, outlines, backgrounds and text keep their colors for now.

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
