---
title: "Movies"
summary: "load a movie file and it is a picture that plays: draw it, fill shapes with it, and play, pause, rewind and set it."
weight: 30
---

A movie is a picture that changes as it plays. `load` finds the file by name in `assets/`, as it does for pictures and sounds, and gives something that goes wherever a picture goes: `image` draws it, `fill` paints a shape with it, `flip`, `resize` and the other picture verbs take the picture it shows at that moment.

```roci
clip = load "zoom.mpg"
loop clip
draw [
  image clip at 20 20
]
```

A loaded movie waits on its first picture until it is told to play.

## Which files

rocinante plays **MPEG-1** movies, files ending in `.mpg` or `.mpeg`, and only their picture: a movie has no sound yet. If you have a video in another format, ffmpeg turns it into one:

```
ffmpeg -i holiday.mp4 -an -c:v mpeg1video -b:v 2000k holiday.mpg
```

`roci add holiday.mpg` copies it into `assets/videos`. A bigger bit rate (`-b:v`) makes a sharper picture and a bigger file. Other formats, and the sound, come later.

A file that is not a movie says so, once, and the sketch carries on with a movie that draws nothing:

```message
── `broken.mpg` is not a movie I can read ────────────── sketch.roci:1:8

1 │ clip = load "broken.mpg"
  │        ^^^^^^^^^^^^^^^^^

I play MPEG-1 movies, `.mpg` files, and `broken.mpg` is another kind of file, or it is damaged. Only the picture is played for now, not the sound. The movie draws nothing, and the sketch carries on. ffmpeg can make one from any video: `ffmpeg -i in.mp4 -an -c:v mpeg1video out.mpg`.

Load one I can read:  clip = load "broken.mpg"
```

## Playing

The verbs are the ones sounds have:

- `play clip` plays it once, from where it is, or from its start when it had come to its end;
- `loop clip` plays it over and over;
- `pause clip` holds it on its picture, and `play` goes on from there;
- `rewind clip` puts it back at its start, and `rewind clip by 2` two seconds back; a movie that plays goes on playing;
- `forward clip by 2` puts it two seconds on;
- `set clip at 10 speed 2 loop true` puts it ten seconds in, plays it at twice the speed and makes it loop. `speed 1` is as filmed, and `speed 0` holds the picture without pausing.

`play clip speed 0.5` and `loop clip speed 2` take the speed too.

A movie reads `clip.playing`, `clip.at` (seconds from its start), `clip.length`, `clip.speed`, `clip.loop`, and `clip.width` and `clip.height` like any picture. These can be read and not changed: `set` and the verbs above are how a movie is moved.

```roci
clip = load "zoom.mpg"
loop clip
on key "space" [
  if clip.playing [ pause clip ] else [ play clip ]
]
on mouse down [ set clip at 0 ]
draw [
  image clip at 20 20
  fill gold
  rect at 20 340 size (360 * clip.at / clip.length) 10
]
```

## How it keeps time

A movie moves on by the time each frame took, so it plays at the right speed whatever the frame rate is. A headless run (`roci run --frames`, `roci test`) takes a sixtieth of a second a frame, so a picture of a movie is the same on every computer. A movie nobody draws is still decoded while it plays, and costs nothing else.

A movie value is the movie itself, not one of its pictures: `still = clip` is the movie too, and draws what the movie shows when `still` is drawn. A picture that must stay as it was is made with one of the picture verbs (`crop still at 0 0 size 160 96` keeps a copy as it is now, for example).
