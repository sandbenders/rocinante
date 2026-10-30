---
title: "Sketch folders and libraries"
summary: "What is in a sketch folder, assets, splitting a sketch into files, and using other people's verbs."
weight: 12
---

## A sketch folder

`roci new name` makes a folder like this, and `roci init` does the same in a folder you already have, without changing anything in it:

```
my-sketch/
  sketch.roci     the sketch: what runs
  assets/         images, sounds, fonts and data the sketch uses
  libs/           other people's verbs, copied in by roci get
  output/         what the sketch saves; git ignores it
```

When git is installed, the folder starts as a git repository with a first commit, so your work has a history from the start.

## Assets

Everything a sketch uses goes in `assets/`, and is found by its name wherever it is in there. `roci add` copies a file into the right part of `assets/`:

```
roci add ~/Pictures/cat.png
```

(The verbs that load images, sounds and fonts arrive in the next phases of rocinante.)

## Several files

Every `.roci` file in a sketch's folder is part of the same sketch. The other files hold verbs, taught with `learn`, and constants; what runs is written in `sketch.roci`. A file called `palette.roci` beside it:

```roci
SKY = navy
GLOW = gold

learn star x y size [ circle at x y radius size fill GLOW ]
```

and `sketch.roci` uses them with no import line:

```roci
SKY = navy
GLOW = gold

learn star x y size [ circle at x y radius size fill GLOW ]

background SKY
repeat 40 [ star (random 400) (random 300) (1 + random 3) ]
```

(Here both are written in one block, so the example runs on its own; in a folder, the first three lines live in `palette.roci`.) A message about another file names it: `palette.roci:4:2`.

## Libraries

A library is a folder of `.roci` files someone has shared in a git repository. `roci get` copies it into the sketch's `libs/` folder, where it stays, so the sketch keeps working even if the library changes or disappears:

```
roci get https://github.com/someone/flocking
```

Then `use` brings its verbs in, by the library's name:

```
use "flocking"
```

`roci update` fetches newer copies and says what changed; nothing updates by itself. A verb that two libraries both teach is written with the library's name in front, `physics.bounce`, and rocinante says when that is needed. A library's own helpers, taught with `hidden learn`, stay inside it.
