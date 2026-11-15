---
title: "Sound"
summary: "Sounds from files and instruments of your own, effects on them, a MIDI keyboard, OSC from other programs, and drawing with how loud and how high they are."
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

## Instruments of your own

`synth` makes an instrument, a sound the sketch makes itself from a wave: `sine` (soft and pure), `triangle` (a little brighter), `square` (hollow, like an old game), `saw` (buzzing, bright) or `noise` (a hiss, with no pitch). It is a sound like any other, so `play`, `pause`, `set`, `level` and `bands` all work on it, and what it plays are notes:

```roci
piano = synth triangle
play piano note 60 for 0.5
```

`note 60` is middle C, the number a MIDI keyboard sends for it: each step up is the next key of a piano, black keys included, so 62 is D, 64 E, 67 G and 72 the C above. A fraction is between two keys. `pitch 440` says the pitch in hertz instead, for sounds that slide. `for 0.5` plays it for half a second; without it the note is held until it is let go with `pause piano note 60`, and `pause piano` lets every note go. Notes played one after another sound together, so a chord is three of them:

```roci
piano = synth triangle
for each n in [ 60 64 67 ] [ play piano note n for 1 ]
```

`held` says whether a key is down, so a key can hold a note for as long as it is pressed:

```roci
organ = synth square
pressing = false
draw [
  if held "a" and not pressing [ play organ note 57 ]
  if pressing and not held "a" [ pause organ note 57 ]
  pressing = held "a"
]
```

`set organ pitch (mouse.x + 100)` slides the notes that sound, and a note played with no `note` or `pitch` takes the instrument's own pitch, which `set` changes. A note comes in and fades out over a few thousandths of a second, so starting and stopping never clicks. A sound from a file can be played at a note too: it is taken to be middle C, and plays faster and higher for a higher note.

## Recorded instruments: SoundFonts

A SoundFont (a `.sf2` file) is a bank of recorded instruments: a piano, strings, drums, each a set of recordings and the keys and strengths each one covers. Put one in `assets/` and `synth` makes an instrument of it, played exactly as the waves are:

```roci
piano = synth "upright.sf2"
play piano note 60 for 1
```

A file with many instruments, such as a General MIDI set, numbers them: `preset 0` is a piano, `preset 48` strings, `preset 56` a trumpet. `preset` also takes the instrument's name, `preset "Trumpet"`. Without it the first instrument plays, and a preset the file does not have says which ones it has. The instrument's volume picks the recordings made at that strength, so `volume midi.velocity` plays the keyboard's touch. The files can be large, a General MIDI set over a hundred megabytes; small ones of a single instrument are a few megabytes.

## Effects

`effect` with a sound first puts a sound effect on it: what a guitarist's pedals and a studio's rack do. The record after `by` gives its settings, and saying it again with new ones changes them while it plays, so a setting can follow the mouse:

```roci
guitar = synth saw
effect guitar "overdrive" by { drive: 60 }
effect guitar "delay" by { time: 0.3, feedback: 40, mix: 30 }
on mouse down [ play guitar note 52 for 0.4 ]
draw [ effect guitar "delay" by { time: mouse.x / width } ]
```

A sound goes through its effects in the order they were first put on it, and `no effect guitar "delay"` takes one off. `speakers` is the whole mix: its effects run over everything that plays, after each sound's own, `effect speakers "reverb"` for a shared room and `effect speakers "limiter"` to keep many sounds from crackling.

| effect | what it does | settings, and where they start |
|---|---|---|
| `overdrive` | warm, rounded grit | `drive` 50, `tone` 50, `level` 70 |
| `fuzz` | hard, buzzing clip | `drive` 70, `tone` 40, `level` 60 |
| `delay` | echoes | `time` 0.3, `feedback` 40, `mix` 30 |
| `reverb` | a room around it | `size` 60, `damping` 50, `mix` 25 |
| `chorus` | many voices at once | `rate` 0.8, `depth` 50, `mix` 50 |
| `flanger` | a jet's swoosh | `rate` 0.25, `depth` 70, `feedback` 50, `mix` 50 |
| `phaser` | a swirling sweep | `rate` 0.5, `depth` 70, `feedback` 40, `mix` 50 |
| `tremolo` | the volume pulsing | `rate` 5, `depth` 50 |
| `compressor` | loud parts held down | `threshold` 50, `ratio` 4, `attack` 0.01, `release` 0.2, `level` 100 |
| `eq` | more or less bass, middle, treble | `low` 0, `mid` 0, `high` 0 |
| `rotary` | a spinning speaker | `rate` 0.8, `depth` 60, `mix` 100 |
| `filter` | only the low, high or middle pitches | `cutoff` 1000, `resonance` 20, `kind` `"low"` (or `"high"`, `"band"`) |
| `bitcrush` | an old console's grit | `bits` 8, `rate` 11025, `mix` 100 |
| `ring` | metallic, robot voices | `pitch` 300, `mix` 100 |
| `wah` | a filter that follows how loud it is | `sensitivity` 50, `resonance` 60, `mix` 100 |
| `limiter` | never past a ceiling | `ceiling` 95, `release` 0.1 |

Amounts are 0 to 100, as volume is; `time`, `attack` and `release` are seconds; `rate` is times a second; `cutoff` and `pitch` are hertz; the `eq` bands go from -100 (12 decibels softer) to 100 (12 louder). An echo or a reverb goes on sounding after the sound has stopped, and `level` and `bands` hear a sound after its effects.

## A MIDI keyboard

A MIDI keyboard or controller plugged in (USB) is heard with no setup. `on midi down` runs when a key goes down, and inside it `midi` is that key: `midi.note` is its number, the same numbers `note` takes, and `midi.velocity` how hard it was struck, 0 to 100. `on midi up` runs when it comes up. So an instrument is played by a keyboard in three lines:

```roci
piano = synth triangle
on midi down [ play piano note midi.note volume midi.velocity ]
on midi up [ pause piano note midi.note ]
```

Knobs, faders and wheels send a controller's number and its value. `midi control 1` is the latest value of controller 1, the mod wheel, from 0 to 100, read anywhere, in `draw` too; a controller that has not moved yet reads 0. `on midi control` runs for each move, with `midi.control` and `midi.value`, which is also the way to find which number a knob sends:

```roci
on midi control [ print midi.control ]
draw [ circle at 200 150 radius (10 + midi control 1) ]
```

`midi.channel` says which of MIDI's 16 channels a message came on, for a controller that sends on more than one. Every device plugged in is heard, and one plugged in while the sketch runs is found within a second.

## OSC, from other programs

OSC (Open Sound Control) is how music software, phone controllers such as TouchOSC, and other sketches send each other numbers over a network, or just inside one computer. A message has an address, a path such as `/fader/1`, and numbers, text or true and false after it. `on osc` runs for each message that arrives, and inside it `osc` is that message: `osc.address`, `osc.value` (the first number it carries, with true as 1 and false as 0), `osc.text` (the first text), `osc.args` (everything it carries, in order: numbers, text, true and false, and a blob of bytes as a list of numbers) and `osc.from` (the computer that sent it):

```roci
on osc [ print osc.address ]
on osc "/fader/1" [ print osc.value ]
```

Name an address to wait for it alone. A `*` stands for any text and a `?` for any one character, `[1-3]` for one of those characters (`[!1-3]` for any other) and `{red,green}` for either word, all inside one part of the address, so `on osc "/fader/*"` hears `/fader/1` and `/fader/2` but not `/fader/1/x`, and `on osc "/{red,green}/[1-4]"` hears `/red/2`. The first `on osc` starts listening on port 9000, which is where most programs are told to send; `osc listen 8000` chooses another. If another program has the port, a message says so and the sketch goes on without listening.

A sketch can also ask for the latest number sent to an address, anywhere, in `draw` too: `osc value "/fader/1"` is 0 until one arrives. And `osc send` sends a message:

```roci
on mouse down [
  osc send "/click" [ mouse.x mouse.y "left" true ] to "localhost" port 9000
]
draw [ circle at 200 150 radius (10 + osc value "/click") ]
```

The list holds numbers, text, true or false, and lists of numbers, which go as a blob of bytes (each number rounded and kept from 0 to 255). `to` is the name or number of a computer (`"studio.local"`, `"192.168.0.7"`) and starts as this computer; `port` starts as 9000, so a sketch that sends to itself needs no more than `osc send "/click" [ 1 ]`. A whole number is sent as an integer and any other as a float, which every OSC program reads. Messages that belong together can go as one bundle, a list of lists that each start with an address, which the receiver reads as a group:

```roci
on mouse down [
  osc send [ [ "/pos" mouse.x mouse.y ] [ "/pressed" true ] ] to "studio.local" port 8000
]
```

Sending to `"255.255.255.255"` reaches every computer on the network at once. A timetag that arrives is left out, and said once at the `on osc` that heard it; a bundle is always taken as due now. Messages travel over UDP, which never says whether they arrived, so a lost one is lost.

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

Recording what plays, and sending MIDI out, come next.
