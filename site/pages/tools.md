---
title: "Tools"
summary: "The roci program: run, check, format and test a sketch, look a word up, and make sketch folders and fetch libraries."
type: "tool"
---

Everything is done with one program, `roci`. Run it with no name to see this list in the terminal.

## Working on a sketch

| Command | What it does |
|---|---|
| `roci run [file]` | opens the sketch in a window and reloads it each time you save. With `--frames N` it runs without a window, and `--screenshot out.png` saves the picture. `--stats` times the frames: a box in the top left corner shows the frame and the frame rate, and the run adds a line to `artifacts/log.json`; `--no-vsync` lets the window go as fast as the computer can. `--compile` turns the sketch into a program for this computer and runs it, to see how fast it is when it is compiled (`--debug` builds it for a debugger); it needs Odin and the source of rocinante beside `roci`, and it says so when a sketch uses something it cannot compile yet. With `--target ios` or `--target android` it builds the sketch for a phone that is plugged in, installs it there with its `assets` and starts it ([compiling and phones](../guides/31-compiling-and-phones/)). |
| [`roci check`](../roci-check/) | reads a sketch and says every mistake in plain words, without a window. |
| [`roci fmt`](../roci-fmt/) | writes a sketch in the house style. |
| [`roci man`](../roci-man/) | shows how a word is written. |
| [`roci package`](../guides/32-packaging-a-mac-app/) | turns a sketch into an app to give to other people. On a Mac, `roci package macos` makes the app and a zip of it. |
| `roci doctor` | says which kinds of app this computer can build and which tools compiling a sketch lacks, with the line that gets each one. |
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

`roci package` makes Mac apps now; the other systems follow. For now `roci run --compile --target ios|android` puts a sketch on your own phone.
