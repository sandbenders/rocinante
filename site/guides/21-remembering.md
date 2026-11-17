---
title: "Remembering between runs"
summary: "Keep a high score, a setting or a count in a file beside the sketch with remember, recall and forget, so the next run starts where this one ended."
weight: 21
---

A sketch forgets everything when it closes. Three verbs keep what you want: `remember` writes a value under a name, `recall` reads it back, and `forget` takes it away. The values go into a file called `memory.toml` beside `sketch.roci`.

```roci
best = recall "best score" start 0
score = 0

on key "space" [
  score = score + 10
  if score > best [
    best = score
    remember "best score" best
  ]
]

draw [
  background 20
  fill white
  text "score {score}" at 20 40
  text "best {best}" at 20 70
]
```

`start` is what `recall` gives before anything is kept, such as the very first time the sketch runs. Without it `recall` gives the empty value of the kind: 0, empty text, or an empty list.

## What can be kept

Numbers, text, true or false, vectors, colors, and lists and records of those. A window, a picture, a sound or a gradient is made while the sketch runs, so it cannot be written down. `memory.toml` is plain text you can open and read:

```toml
# What sketch.roci remembers. Edit it freely while the sketch isn't running.

"best score" = 1280
visits = 42
palette = ["#ff8800", "#336699"]
```

A color is written as `"#rrggbb"` with the alpha after it, and a vector as a list of numbers.

## One name, one kind

The name is written as text in the sketch itself, not worked out while it runs, because rocinante reads the whole sketch before it runs and matches every `remember` with every `recall` of the same name. That is how `recall "visits"` knows it gives a number. A name keeps one kind of value, and a `recall` of a name that nothing keeps, and that has no `start`, says so and suggests the name you may have meant:

```message
── Nothing keeps a value under `best scor` ──────────── sketch.roci:2:15

2 │ best = recall "best scor"
  │               ^^^^^^^^^^^

`recall` gives the kind of value that `remember` keeps under the same name, so the sketch needs a `remember` line for it, or a `start` that says what kind it is. Did you mean "best score"?

Say what it is with a start:  best = recall "best scor" start 0
```

A file edited by hand can hold another kind of value than the sketch uses. The sketch does not stop: `recall` gives the `start` value and the screen shows a message about the line.

## Forgetting

`forget "visits"` takes one value away, and `forget memory` takes every one away. The next `recall` gives its `start` again.

## When the file is written

`remember` only changes the value in memory, so it costs nothing to call every frame. The file is written after a pause of a second in the changes, and when the sketch closes or goes to the background on a phone. Hot reload and `Ctrl+R` keep what is remembered. A sketch run with `--frames` or by `roci test` reads the file and never writes it, so a test is repeatable.

`roci new` makes `.gitignore` leave `memory.toml` out, because a high score is not source. Commit it on purpose when you want to ship a starting state. It is for a sketch's state, not for data sets: a file past a few hundred kilobytes is said once, and a long list of results is better written with `save "log.csv"`.

See `examples/memory` for a sketch that keeps its best score and the number of times it has run.
