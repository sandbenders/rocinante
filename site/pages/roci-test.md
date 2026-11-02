---
title: "roci test"
summary: "Run the checks you wrote with check and expect, and compare a sketch's picture with the one you kept. Optional, and never part of running."
type: "tool"
---

`roci test` runs the checks you have written and compares a sketch's picture with the one you stored. Nothing about it is required: `roci run` never runs a check, and a sketch with none has nothing to test.

```
roci test                    the sketch in this folder, or every sketch in the folders inside it
roci test sketch.roci        one sketch
roci test examples           a whole folder of sketches
```

It prints which checks held, says what both sides were for each that did not, and then compares the picture. It exits with 0 when everything holds, 1 when a check failed, a picture changed or a sketch would not run, and 2 when the words were wrong or a file was missing.

## Checks

A check sits under the verb it tests, and `expect` says what has to be true:

```roci
learn double n [ give n * 2 ]

check "double" [
  expect double 21 is 42
]
```

## A picture that must not change

```
roci test --accept                  store the picture the sketch draws now
roci test --accept --frames 30      take it after 30 frames (1 by default)
roci test --accept --seed 7         with this seed for the random numbers (1 by default)
```

The picture, the frames and the seed go in the sketch's `tests/` folder, which you commit. A plain `roci test` then draws the sketch the same way and says, in words, how much of the picture changed and where, saving the new picture in `output/test/`. If the change is on purpose, `--accept` stores it.

[Checks and snapshots](../guides/13-checks-and-snapshots/) is the whole story, with examples.
