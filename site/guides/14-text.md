---
title: "Text"
summary: "Words on the window: text, font, size, align and leading, wrapping, measuring a text, fonts of your own, and other scripts."
weight: 14
---

`text` draws words. The point after `at` is where the top of the text goes:

```roci picture
background 250
fill 30
text "Hello" at 30 40
```

The words are in Inter, which comes with rocinante, so a sketch looks the same on every computer. `text` takes the same style words as a shape (`fill`, `alpha`, and so on), and `size` and `font` as well:

```roci picture
background 250
fill 30
text "Hello" at 30 30 size 60
fill teal
text "in teal, and bold" at 30 120 size 24 font "Inter Bold"
```

## Setting the font

`font` and `size` set the font for the text that follows, as `fill` sets the color. Like every style, they start again at each frame:

```roci picture
background 250
fill 30
font "Inter Bold" size 40
text "Bold" at 30 30
font "Inter" size 40
text "Regular" at 30 100
```

The two fonts built in are `Inter` and `Inter Bold`.

## Lines against a point

`align` says where each line sits against its x: `left` (the default), `center` or `right`. A line break in the text (`\n`) starts a new line, and `width` makes a long text wrap, so no line is wider than that:

```roci picture
background 250
stroke gray
line from 200 20 to 200 280
no stroke
fill 30
font "Inter" size 22
align left
text "left" at 200 40
align center
text "center" at 200 90
align right
text "right" at 200 140
align left
text "A longer text breaks into lines by itself when it has a width." at 20 190 width 360 size 18
```

## Space between lines

`leading` sets how far apart the lines of a text are, as a multiple of the size: `1.5` puts the baselines one and a half sizes apart, `1` packs them closer, and `0` (the start) is the font's own spacing. Like `font` and `align`, it can be a line of its own, lasting until changed, or a word of one `text`:

```roci picture
background 250
fill 30
font "Inter" size 20
text "The font's own spacing,\nbetween these lines." at 30 30
leading 1.8
text "Leading 1.8 opens\nthe lines out." at 230 30
text "Or a word of one text,\nleading 1." at 30 160 leading 1
```

## Measuring

`measure` gives the size of a text in the current font, as a vector of its width and height. That is how to draw a box that fits it, or put one thing after another:

```roci picture
background 250
font "Inter Bold" size 32
area = measure "fits"
fill gold
rect at 40 60 size area
fill 30
text "fits" at 40 60
text "next to it" at (40 + area.x + 16) 60 size 32 font "Inter"
```

A text with nothing in it measures 0 by 0. `measure` follows `font`, `size`, `align` and `leading`, so set them first.

## Other fonts

A font file in `assets/fonts` is a font of the sketch. Use it by its file name, with or without the extension (`.ttf`, `.otf`, `.ttc` or `.otc`):

```
font "Mono.ttf"
font "Mono"
```

A font that is not there is said once and the text is drawn in the font before it:

```message
── I do not know a font called `Papyrus` ─────────────── sketch.roci:1:1

1 │ font "Papyrus" size 30
  │ ^^^^^^^^^^^^^^^^^^^^^^

The fonts a sketch has are Inter and Inter Bold, and any font file in its `assets/fonts` folder under its own name, or one face of a font collection by that face's own name. The text is drawn in the font before it, and the sketch carries on.

Use one that is there:  font "Inter"
```

## Fonts installed on your computer

Name a font that is installed on your computer and rocinante finds it: `font "Helvetica Neue"` looks for a file of that name in the computer's fonts when your sketch has none. The first time, the font is copied into `assets/fonts` and one line says so, so your sketch looks the same on every computer and travels with its font. If the font's own licence does not name a free one (the SIL Open Font License, Apache, Ubuntu, MIT or public domain), you get a warning too. It is only a reminder: the sketch carries on, and whether you may share the font is for you to check.

Many fonts are collections: one file, `Helvetica Neue.ttc`, holds Regular, Bold, Condensed Black and the rest. Name the face you want by its own name, as the font lists it (`font "Helvetica Neue Condensed Black"`, or `font "Helvetica Neue Bold"`), and rocinante opens that face. The collection is copied into `assets/fonts` once, under the name you asked for, and the faces in it are found there by their names afterwards. A name with the family alone (`font "Helvetica Neue"`) is the regular face. A PDF made with `save` has the letters of that face too, because they are drawn as outlines; an SVG names the font, so the viewer needs it.

```message
── Warning: Check the licence of `Locked Sans` before you share your sketch ─── sketch.roci:1:1

1 │ font "Locked Sans" size 30
  │ ^^^^^^^^^^^^^^^^^^^^^^^^^^

`Locked Sans` is a font installed on this computer, and its licence says it may not be shared. It works here. If the font goes out with your sketch, in `assets/fonts` or any other way, make sure its licence lets you.

A font that is free to share:  font "Inter"
```

Emoji are drawn at the size of the text around them, one em wide, and measured the same way, so `measure` and a box around a line with an emoji in it fit.

## Other scripts and emoji

Inter covers the Latin alphabets, Greek and Cyrillic. For other scripts and emoji, rocinante looks for a font on the computer (Hiragino and Apple Color Emoji on a Mac, Noto or Segoe UI elsewhere), and shapes the text properly: Arabic joins and runs right to left, Devanagari gathers its marks. Those fonts belong to the computer, so they are never copied into your sketch: where there is none, a missing character shows as an empty box. To be sure a script looks the same everywhere, put a font that has it in `assets/fonts` and name it.

## Putting it together

A whole sketch of words: two weights, a line aligned against its x, a paragraph that wraps, and labels whose boxes are made from `measure`. It is `examples/text`, and runs with `roci run examples/text`.

```roci picture
// Words in Inter, in two weights and many sizes. A line is aligned against its x, a long
// one wraps at a width with the lines as far apart as leading says, and measure says how big a text is, so a caption can have a
// box that fits it exactly.
window size 640 420 title "text"

learn caption words spot with hue 160 [
  size = measure words
  fill (hsb hue 60 240)
  rect at (spot.x - 10) (spot.y - 6) size (size.x + 20) (size.y + 12)
  fill 30
  text words at spot
]

draw [
  background 248
  fill 30
  font "Inter Bold" size 56
  text "Words" at 32 24
  font "Inter" size 20
  fill gray
  text "set in Inter, shaped and drawn by the GPU" at 36 92

  stroke 200
  line from 480 140 to 480 290
  no stroke
  fill crimson
  font "Inter Bold" size 18
  align left
  text "left" at 480 150
  align center
  text "center" at 480 190
  align right
  text "right" at 480 230
  align left

  fill 30
  font "Inter" size 17
  text "A longer paragraph wraps inside the width it is given, and keeps going onto as many lines as it needs. Line breaks in the text work too." at 36 140 width 380 leading 1.5

  font "Inter Bold" size 18
  caption "boxes that fit" { 36, 320 } hue 20
  caption "any text" { 220, 320 } hue 120
  font "Inter Bold" size 26
  caption "at any size" { 330, 316 } hue 210
]
```
