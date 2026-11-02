---
title: "roci check"
summary: "Read a sketch and say every mistake in it, in plain words, without opening a window."
type: "tool"
---

`roci check` reads a sketch and says what is wrong with it, without running it or opening a window. It says every mistake it finds in one go, not only the first, each with the line, what went wrong in plain words and a line that would work.

```
roci check                  the sketch in this folder
roci check sketch.roci      one file
roci check my-sketch        a folder: every .roci file in it, read as one program
```

If all is well it says so, and it exits with 0. If something is wrong it exits with 1, and with 2 when a file could not be read, so a script or a pipeline can use it.

## Options

```
roci check --types          also say what each name in the sketch holds
roci check --errors json    print every message as a line of JSON, for editors and other tools
roci check --tree           also print the syntax tree, for people working on the language
```

`--types` is a good way to see what rocinante worked out for you: a number, text, a list of records with these fields. Nobody writes types in rocinante, but they are there, and a mistake such as using a number where text is wanted is found from them.

## What it is for

`roci run` finds the same mistakes, and when you save a sketch that has one the window keeps running the last good version under an error band. `roci check` is for when you want the answer without a window: in an editor, in a script, or on a computer with no screen.

Every message is listed on [the messages page](../messages/).

See also [`roci test`](../roci-test/), which runs the checks you write, and [`roci fmt`](../roci-fmt/).
