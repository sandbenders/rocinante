---
title: "Sound"
summary: "Sounds from files that play, loop, pause and move, louder or softer and from either side, and how loud and how high what plays is."
weight: 20
---

A sound comes from a file in the sketch's `assets` folder, a WAV, FLAC, MP3 or Ogg Vorbis file, found by its name like a picture. `load` gives a sound when the name ends in one of those, and `play` plays it:

```roci
click = load "click.wav"
on mouse down [ play click ]
```

Nothing needs to be set up: the first sound that plays opens the computer's speakers.

## One sound, one player

A sound is where it is, playing or not, like a track in a music player. `play` plays it once from where it is, and from its start again when it had come to its end. `loop` plays it over and over. `pause` holds it where it is, and `play` or `loop` goes on from there:

```roci
rain = load "rain.ogg"
loop rain
on key "space" [
  if rain.playing [ pause rain ] else [ loop rain ]
]
```

`rewind` puts it back to its start, or some seconds back with `by`, and `forward` with a sound moves it ahead, the way it walks the turtle with a number:

```roci
rain = load "rain.ogg"
loop rain
on key "left" [ rewind rain by 5 ]
on key "right" [ forward rain by 5 ]
on key "home" [ rewind rain ]
```

A sound that plays goes on playing from where it was moved to. Past its end, a sound that loops goes on from its start and one that does not has ended.

## Louder, softer, faster

`play` and `loop` take three settings. `volume` is how loud, from 0 (silent) to 100 (as recorded). `pan` is where it is between the speakers, from -100 (all left) to 100 (all right): in the middle both play it, and towards one side the other fades. `speed` is how fast: 2 is twice as fast and an octave higher, as on a record player, and 0.5 half as fast and an octave lower.

```roci
hum = load "rain.ogg"
loop hum volume 30 pan -60 speed 0.8
```

`set` changes them while it plays, with the same words, and `at` puts it some seconds from its start. `loop false` lets a looping sound finish where it is:

```roci
rain = load "rain.ogg"
loop rain
draw [
  set rain volume (100 - mouse.y / height * 100) pan (mouse.x / width * 200 - 100)
]
on key "s" [ set rain at 0 loop false ]
```

The names `volume`, `pan` and `speed` stay yours: a sketch can have a `speed` of its own and write `play click speed speed`.

## What a sound says

A sound reads like a record: `playing` is true while it plays, `at` is where it is and `length` how long it is, both in seconds, and `volume`, `pan`, `speed` and `loop` are its settings. They can be read and not assigned, since `set` changes them:

```roci
rain = load "rain.ogg"
loop rain
draw [
  background 20
  fill (rgb 90 150 230)
  rect at 0 (height - 10) size (rain.at / rain.length * width) 10
]
```

## Drawing with sound

`level` is how loud everything that plays is now, from 0 (silent) to 100 (a full-volume tone), and `bands` is how much of each pitch it holds: a list of numbers 0 to 100, the lowest pitches first, 16 of them unless you ask for another number (`bands 32`, up to 256). Both are read in `draw`, every frame:

```roci
tune = load "rain.ogg"
loop tune
draw [
  background 20
  circle at 200 150 radius (10 + level * 2)
  heard = bands 16
  for i from 1 to 16 [
    high = (item i of heard) * 2
    rect at (i * 23) (300 - high) size 18 high fill (hsb (i * 14) 170 240)
  ]
]
```

The bands are equal steps of pitch, as a piano's keys are, from the lowest note of a bass guitar on the left to the highest a person hears on the right. Given a sound, they listen to it alone: `level rain`, `bands rain 8`.

`level` alone, as the value of a call, is written in brackets, `round (level)`, since it can also take a sound. `roci fmt` adds them for you.

## The microphone

`mic` is the computer's microphone as a sound to listen to. `level mic` is how loud it hears and `bands mic` its pitches. The first time a sketch reads it the microphone opens, and the system may ask whether the sketch may use it. What it hears is not played through the speakers:

```roci
draw [
  background 20
  fill (rgb 255 200 80)
  circle at 200 150 radius (10 + (level mic) * 3)
]
```

## Saving the file again

While `roci run` is going, a sound file saved again is read again into the same sound, which goes on playing where it was, louder or softer as it was set, so a sound can be edited while the sketch listens to it. Saving the sketch keeps the sounds playing too: a sound loaded by a line that did not change is the same sound.

## Not yet

Synthesis, effects, recording what plays, MIDI and OSC come next.
