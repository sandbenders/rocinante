---
title: "Pictures"
summary: "Loading pictures, drawing them, painting with them, reading pixels, drawing SVG files, saving the window as PNG, SVG or PDF, and recording movies."
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

## Reading and changing pixels

A picture never changes. `pixel` reads one of its colors, and `crop`, `resize`, `filter` and `mask` each give a new picture made from it. `pixel photo at 10 20` counts from the top left, and a place outside the picture is clear black:

```roci picture
photo = load "landscape.png"
image photo at 20 20
sky = pixel photo at 100 10
sun = pixel photo at 220 100
fill sky
no stroke
rect at 20 200 size 120 60
fill sun
rect at 160 200 size 120 60
```

`pixels photo` gives every color as a list, left to right and top to bottom, for a picture of up to a million pixels (`resize` a bigger one first). `picture from colors size 3 2` goes the other way and makes a picture from a list of colors:

```roci picture
colors = [ red orange gold teal navy purple ]
small = picture from colors size 3 2
image small at 20 20 size 240 160
```

`crop` keeps the part inside a box, and `resize` scales. A smaller picture takes the average of the pixels it stands for, and `as nearest` keeps hard edges, so a few pixels become big squares. A side given as 0 follows the picture's shape:

```roci picture
photo = load "landscape.png"
part = crop photo at 150 60 size 40 30
image (resize part size 190 0) at 10 10
image (resize part size 190 0 as nearest) at 210 10
```

`filter` takes one of `gray`, `invert`, `threshold`, `posterize`, `blur`, `edges` and `pixelate`, and `by` says how much: a brightness for `threshold` (0 to 255, the start 128), a number of steps for `posterize` (4), a radius in pixels for `blur` (2) and a block size in pixels for `pixelate` (8). `mask photo by shape` shows the picture only where the shape picture is white and solid, stretching the shape over it, so a canvas you drew a white circle on makes a round window.

```roci picture
photo = load "landscape.png"
background 245
image photo at 10 10 width 120
image (filter photo as gray) at 140 10 width 120
image (filter photo as blur by 5) at 270 10 width 120
image (filter photo as edges) at 10 100 width 120
image (filter photo as posterize by 3) at 140 100 width 120
image (filter photo as pixelate by 6) at 270 100 width 120
```

These work on a canvas too, but a canvas keeps its pixels on the graphics card, so reading one copies them back first and stalls the frame. Do it once and keep the answer, not for every pixel of every frame. A made picture is remembered by what made it, so asking for the same crop or filter of the same picture each frame costs nothing after the first time, and the pictures the sketch made and has not used for a long while are let go if there are very many. Per-pixel loops in a sketch are slow; `filter`, `resize` and `mask` do the whole picture in one step, so reach for them first (`examples/pixels` shows a magnifier made of `crop` and `resize`).

## Drawings from SVG files

A picture is made of pixels, so it blurs when it is made big. A drawing made of shapes does not. `svg` draws an SVG file from `assets/` (any folder in it, found by name, as a picture is) as shapes:

```roci
draw [
  svg "badge.svg" at 20 20
  svg "badge.svg" at 260 20 size 100 100
]
```

It takes the same two forms of place and size as `image`: `at` a point, and `size` for a width and a height (stretched, so write the sides in the file's own proportion to keep it true). It is drawn under the current transform, so `move`, `turn` and `grow` work on it, and it keeps its own colors: the style you have set is not used and is not changed.

What it reads: paths with every command (lines, curves and arcs), rectangles with rounded corners, circles, ellipses, lines, polylines and polygons, in groups and `use`s, under any `transform`, with their fill, stroke, widths, caps, joins and opacity, whether they are written as attributes, in a `style` or in the rules of a `<style>` (`tag`, `.class` and `#id`). A shape with a hole in it, such as a ring written as two contours, has the hole. Fills are even-odd, whatever the file says.

What it leaves out, and says once, so the rest is still drawn: text (the font is the viewer's, and rocinante's `text` is the way to write words), embedded pictures (use `image`), clip paths, masks, filters, patterns and markers. A gradient is drawn in the first color of its stops. If you export from Inkscape or Illustrator, turn text into outlines first and the file will draw whole.

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

That writes `output/frames/frame-0000.png`, `frame-0001.png` and so on. `roci run sketch --frames 120` draws 120 frames with no window, which is the way to record a long sequence quickly. A name that does not end in `.png`, `.svg` or `.pdf` is said and nothing is written; a file that cannot be written is said on the next frame. `examples/export` saves a PNG with `s`, an SVG with `v`, a PDF with `p` and records with `r`.

### As a vector drawing

A name ending in `.svg` or `.pdf` saves the shapes instead of the pixels: `save "shot.svg"` writes an SVG file and `save "page.pdf"` a one-page PDF as big as the window (a pixel is a point), both sharp at any size. They open in a browser, Inkscape or Illustrator, and go to a printer, a plotter or a laser cutter. Every circle, rectangle, line, arc, triangle, quad and text is an element of its own, drawn in the same colors, outline widths, caps, joins and transform, with gradients, clips and blends kept, and pictures put in the file. In an SVG, text is written as text in the font by name, so the viewer needs that font (Inter is the one that comes with rocinante; install it, or turn the text into outlines in your drawing program). In a PDF, text is the outlines of its letters, so it looks the same on any computer and cannot be selected or searched; fonts with outlines of the CFF kind (some `.otf` files) cannot be read, and kerning is left out.

A vector file cannot hold everything a window shows, so some things are drawn as the nearest thing or left out, and the sketch says which, once, as a warning: a conic gradient (drawn in its middle color), a shader or picture fill (drawn in the fill's color), the picture of a canvas, a picture behind everything, a tint on a picture, the `subtract` blend (and the `add` blend in a PDF), characters a font does not have (a PDF) and the effects over the window. For those, save a PNG.

## Recording a movie

`record "clip.apng"` starts recording the window: every frame the sketch draws from then on is a frame of the movie, until `no record` (or until the window closes). It writes an animated PNG, which needs nothing installed and plays in browsers and most picture viewers.

```roci
on key "r" [ record "clip.apng" ]
on key "e" [ no record ]
```

For a video, give the name a video ending (`.mp4`, `.mov`, `.webm`, `.mkv` or `.gif`) and rocinante hands the frames to `ffmpeg`, the free program most people who make videos already have. It is not part of rocinante, so when it is not installed `record` says so and how to get it, and the sketch carries on:

```roci
record "clip.mp4"
```

The movie plays at 60 frames a second, one frame of the sketch to each frame of the movie, so a sketch that keeps up with 60 frames a second records in real time, and `roci run sketch --frames 600` draws ten seconds with no window, as fast as the computer can. A plain name goes in the sketch's `output` folder, folders in the name are made, and a window that changes size while it is recorded leaves out the frames of the other size. An animation is kept in memory until it is written, so it stops by itself after about half a gigabyte and writes what it has; a video made with `ffmpeg` has no such limit. If `ffmpeg` fails, the message says what it said, and its log is kept beside the file. `examples/export` records a video with `m` and an animation with `a`.
