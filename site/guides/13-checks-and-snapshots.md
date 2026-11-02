---
title: "Checks and snapshots"
summary: "Say what a verb is meant to do with check and expect, keep a picture that must not change, and run both with roci test."
weight: 13
---

Nothing here is required. A sketch runs the same without it. But two kinds of sketch are worth a test: a verb or a library other people will use, and a sketch that has to keep looking the same, such as an installation, a commission or a lesson. `roci test` covers both.

## Checks

A **check** sits right under the verb it tests, so it reads like an example of using it. `expect` says what has to be true:

```roci
learn double n [ give n * 2 ]

check "double" [
  expect double 21 is 42
  expect double -1 is -2
]
```

`roci run` skips a check, and so does a packaged sketch, so a check never changes what the sketch does. A check may go in any file of the sketch, including a library's, and the names it makes are its own: it sees the sketch's names and verbs but cannot disturb them.

`roci test` runs every check. If the second line had said `expect double 21 is 43` it would not hold, and `roci test` says what both sides were:

```message
── A check did not hold: double ──────────────────────── sketch.roci:4:3

4 │   expect double 21 is 43
  │   ^^^^^^^^^^^^^^^^^^^^^^

I expected `double 21` to be 43, but it is 42.
```

`expect` takes anything that is true or false: `is`, `is not`, `<`, `>` and the rest, joined with `and` and `or`. Numbers are compared exactly, so `expect (0.1 + 0.2) is 0.3` does not hold (decimals carry a tiny rounding), and the message says so. Compare whole numbers, or check that the difference is small:

```roci
check "close enough" [
  expect (abs ((0.1 + 0.2) - 0.3)) < 0.0001
]
```

## A picture that must not change

`roci test --accept` runs the sketch with no window, takes a picture of each window and stores it in the sketch's `tests/` folder, which you commit with the sketch. After that, `roci test` draws the sketch again and compares:

```
roci test --accept --frames 30    store the picture after 30 frames (1 by default)
roci test                         compare with it
```

The frames and the seed of the random numbers are stored beside the picture (`tests/snapshot.txt`), so the same sketch draws the same picture each time. When it differs, you are told how much and where, and the new picture is saved in `output/test/` so you can look at it:

```
window 1 is not the picture stored in tests/snapshot-1.png: 524 of 30000 pixels differ (1.7 percent), in the area from 59, 34 to 140, 115.
```

If the change is on purpose, run `roci test --accept` again. A few pixels along the edges of shapes may differ between computers, because graphics drivers draw edges a little differently, and `roci test` allows for that.

## Many sketches at once

`roci test` with no name tests the sketch in this folder, or every sketch in the folders inside it, and passes over the ones with nothing to test. `roci test examples` tests a whole folder of them. It exits with 0 when everything holds and 1 when it does not, so a script or a pipeline can use it.

`examples/checks` has verbs, their checks and a stored picture to look at.
