---
title: "Tools"
summary: "The roci program: run, check, format and test a sketch, look a word up, and make sketch folders and fetch libraries."
type: "tool"
---

Everything is done with one program, `roci`. Run it with no name to see this list in the terminal.

## Working on a sketch

| Command | What it does |
|---|---|
| `roci run [file]` | opens the sketch in a window and reloads it each time you save. With `--frames N` it runs without a window, and `--screenshot out.png` saves the picture. |
| [`roci check`](../roci-check/) | reads a sketch and says every mistake in plain words, without a window. |
| [`roci fmt`](../roci-fmt/) | writes a sketch in the house style. |
| [`roci man`](../roci-man/) | shows how a word is written. |
| [`roci test`](../roci-test/) | runs the checks you wrote and compares the sketch's picture with the one you kept. |

## Folders and libraries

| Command | What it does |
|---|---|
| `roci new name` | makes a sketch folder, with git set up when git is installed. |
| `roci init` | the same inside a folder you already have, without changing anything in it. |
| `roci add file` | copies a file into the right place in the sketch's `assets/` folder. |
| `roci get address` | copies a library from a git address into `libs/`. |
| `roci update [name]` | fetches newer copies of those libraries and shows what changed. |

[Getting started](../guides/01-getting-started/) shows the first of these in use, and [sketch folders and libraries](../guides/12-sketch-folders-and-libraries/) the rest.

## Coming

`roci package` will turn a sketch into an app for each platform, and `roci doctor` will say what a computer is missing to do it. They are not in the alpha.
