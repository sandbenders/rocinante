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

`load "cat.png"` gives a picture and `load "rain.wav"` a sound, and `font "Name"` finds a font file there.

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

Constants (names in capitals) exist for every file from the start, whatever the order of the files' names, and a constant can use another constant of any file: `GLOW = SKY` works wherever each is written. A name in small letters is a variable, which gets its value when the line that gives it runs, and files are read in the order of their names, so a variable of a later file has no value yet for a line of an earlier one. Constants made from a variable, or from `random` and the other words that differ from one run to the next, are made where they are written.

## One file for several sketches

A project can have more than one program: a game, a tool that makes its icon, a folder of tests. Each is a sketch folder with its own `sketch.roci`, and a folder that holds a `sketch.roci` is never part of the sketch around it. What they share goes in a file of its own, outside both, and each names it with `use` and a path:

```
project/
  look.roci          colors and the ship, taught once
  game/sketch.roci   use "../look.roci"
  icon/sketch.roci   use "../look.roci"
```

The path starts in the folder of the file that says `use`, with `..` for the folder above. A file named this way is one more file of the program, as if it stood in the folder, so the same rules hold: it holds verbs and constants, not drawing, and it may name other files, or libraries, in turn. Name a file twice and it is read once. If it is not there, the message says where it looked. `roci run` watches the shared file as it watches the files of the sketch's own folder, so saving it reloads the sketch. `examples/project` is a small one.

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
