---
title: "Text"
summary: "Words on the window: text, font, size and align, wrapping, measuring a text, fonts of your own, and other scripts."
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

## Measuring

`measure` gives the size of a text in the current font, as a vector of its width and height. That is how to draw a box that fits it, or put one thing after another:

```roci picture
background 250
font "Inter Bold" size 32
box = measure "fits"
fill gold
rect at 40 60 size box
fill 30
text "fits" at 40 60
text "next to it" at (40 + box.x + 16) 60 size 32 font "Inter"
```

A text with nothing in it measures 0 by 0. `measure` follows `font`, `size` and `align`, so set them first.

## Other fonts

A font file in `assets/fonts` is a font of the sketch. Use it by its file name, with or without the extension:

```
font "Mono.ttf"
font "Mono"
```

A font that is not there is said once and the text is drawn in the font before it:

```message
── I do not know a font called `Papyrus` ─────────────── sketch.roci:1:1

1 │ font "Papyrus" size 30
  │ ^^^^^^^^^^^^^^^^^^^^^^

The fonts a sketch has are Inter and Inter Bold, and any font file in its `assets/fonts` folder under its own name. The text is drawn in the font before it, and the sketch carries on.

Use one that is there:  font "Inter"
```

## Other scripts and emoji

Inter covers the Latin alphabets, Greek and Cyrillic. For other scripts and emoji, rocinante looks for a font on the computer (Hiragino and Apple Color Emoji on a Mac, Noto or Segoe UI elsewhere), and shapes the text properly: Arabic joins and runs right to left, Devanagari gathers its marks. Those fonts belong to the computer, so they are never copied into your sketch: where there is none, a missing character shows as an empty box. To be sure a script looks the same everywhere, put a font that has it in `assets/fonts` and name it.
