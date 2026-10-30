---
title: "Getting started"
summary: "Installing rocinante, making a sketch folder, and running it."
weight: 1
---

A rocinante program is called a **sketch**. You write it in a plain text file, `sketch.roci`, and the `roci` program runs it in a window. While it runs, every time you save the file the window changes to match.

## Installing

For the alpha, rocinante is built from its source. You need two things first:

- **Odin**, the language rocinante is written in, at the version named in the `ODIN_VERSION` file of the repository. Its [releases](https://github.com/odin-lang/Odin/releases) cover Linux, macOS and Windows; on macOS, `brew install odin` gives it.
- **SDL3**, for windows and graphics: `brew install sdl3` on macOS, the `sdl3` package on Linux, `pkg install sdl3` on FreeBSD. On Windows, Odin brings its own copy.

Then get the source and build `roci`:

```
git clone https://github.com/sandbenders/rocinante
cd rocinante
odin build cli -out:roci -o:speed
```

That makes the program `roci` in the folder. Put it somewhere on your path, or run it as `./roci`.

## Your first sketch

```
roci new my-sketch
cd my-sketch
roci run
```

`roci new` makes a folder with a sketch in it, and `roci run` opens a window and draws it. The sketch is one line:

```roci
circle at 100 100 radius 50
```

Open `sketch.roci` in any text editor, put this line under the first one, and save:

```roci
circle at 100 100 radius 50
rect at 200 60 size 160 90 fill orange
```

The window changes straight away; you do not have to run it again. Leave `roci run` going while you work.

## When something is wrong

Make a mistake on purpose: change `circle` to `circel` and save. The window keeps the last good picture and shows, across the top, what went wrong, and the terminal says the same:

```
── I don't know the word `circel` ────────────────────── sketch.roci:1:1

1 │ circel at 100 100 radius 50
  │ ^^^^^^

A line starts with a verb, a keyword or a name, and I don't know `circel`. Check the spelling, or teach the word with `learn`.

Did you mean:  circle at 100 100 radius 50
```

Every message says where the problem is, what it is in plain words, and shows a line that would work. Put the word right, save, and the picture comes back. The [messages](../../messages/) page lists them all.

## Other things `roci` does

| Command | What it does |
|---|---|
| `roci run sketch.roci` | runs a sketch file, or a folder's `sketch.roci` |
| `roci check sketch.roci` | says what is wrong without opening a window |
| `roci fmt` | rewrites every sketch in the folder in the house style |
| `roci man circle` | shows how a word is written |
| `roci new name`, `roci init` | make a sketch folder, or one here |
| `roci add photo.png` | copies a file into the sketch's `assets` |

Ctrl+R (Cmd+R on a Mac) in the window starts the sketch again from its first line, and Ctrl+Q (Cmd+Q) closes it.
