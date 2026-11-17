---
title: "Scenes"
summary: "Split a sketch into its parts, such as a title, the play, a pause and the end, with scene, and move between them with go, visit and return."
weight: 22
---

A game has phases: a title, the play, a pause, the end. Keeping them in a `mode` text and a `paused` flag that every handler checks works until a typo (`mode is "plya"`) never matches and nothing says so. A **scene** is a named part of the sketch that holds its own `draw`, `on`, `every` and `ui` blocks, and `go` moves between them.

```roci
// what every scene has
draw [ background 20 ]

scene "title" [
  draw [
    fill white
    text "press space" at 20 40
  ]
  on key "space" [ go "play" ]
]

scene "play" [
  on enter [ print "off we go" ]
  draw [
    fill gold
    circle at (100 + 50 * sin (scene.frame * 3)) 100 radius 30
  ]
  on key "space" [ go "title" ]
]
```

A `draw` or an `on` written outside every scene runs in all of them, first. The first scene starts by itself once the lines above the scenes have run, unless one of them says `go "play"`. A sketch with no scenes runs as it always did.

## Changing scene

`go "play"` changes the scene **when the frame ends**, so nothing changes halfway through one and the lines after the `go` still run. The scene it leaves runs its `on leave`, the new one runs its `on enter`, and the new scene's first frame comes next. If two changes are asked for in one frame, the first one counts. A `go` inside an `on leave` is an error, since it would start another ending. Everything a scene started, its timers and its tweens, ends with it.

The name is written as text, and a name that no scene has is found before the sketch runs, with the nearest one suggested:

```message
── The sketch has no scene called `plya` ────────────── sketch.roci:2:21

2 │ on key "space" [ go "plya" ]
  │                     ^^^^^^

Did you mean "play"? The name after `go` or `visit` is written as text, and has to be the name of a `scene` somewhere in the sketch, so a slip is found before it runs.

Use the name of one of the scenes:  on key "space" [ go "play" ]
```

## Pausing

`visit "paused"` puts a scene on top of the one that is running, and `return` goes back to it. The scene underneath stops: its events, timers and tweens wait, its clock does not run, and it stays on the screen as it was, so a pause or a menu draws over the game it paused. Coming back does not run its `on enter` again.

```roci
scene "play" [
  draw [
    fill gold
    circle at (100 + 50 * sin (frame * 3)) 100 radius 30
  ]
  on key "p" [ visit "paused" ]
]

scene "paused" [
  draw [
    fill white
    text "paused: press p" at 20 40
  ]
  on key "p" [ return ]
]
```

## What a scene knows

`scene.name` is the name of the scene that is running, `scene.time` the seconds since it began and `scene.frame` the frames since, which makes a banner for the first two seconds of a stage or a delay before a button works one `if`: `if scene.time < 2 [ ... ]`.

## Where scenes belong

Levels are data, not scenes: stage 3 is the play scene with `stage = 3`. A scene is a part of how the sketch behaves, a title, a play, an end. Scenes may be written in files of their own beside `sketch.roci`, such as `title.roci` and `play.roci`, because a scene is only a definition until something enters it. Reloading a sketch keeps the scenes it was in, even when others were added or moved, and `Ctrl+R` starts again in the first one.

`examples/swarm` is written with scenes: a title, play, paused and over, where its `mode` and `paused` variables used to be.
