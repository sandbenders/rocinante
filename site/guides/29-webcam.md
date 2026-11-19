---
title: "The webcam"
summary: "webcam is a picture of what the computer's camera sees now: draw it, mirror it, fill shapes and text with it, and keep snapshots."
weight: 29
---

`webcam` is a picture of what the computer's camera sees right now. It is an ordinary picture, so it goes wherever a picture goes: `image`, `fill`, `flip`, `resize` and the rest. Nothing is set up first. The first time a sketch with a window reads `webcam`, the camera opens.

```roci
draw [
  image webcam at 20 20 width 360
]
```

## Opening the camera

On most systems the first use makes the system ask whether the sketch may use the camera. The sketch does not wait for the answer. Until the first frame has come, `webcam` is a dark gray picture, 640 pixels wide and 480 high, so a sketch can draw its whole picture from the first frame and the live view takes its place when it arrives.

When there is no camera, or the answer was no, `webcam` stays that gray picture, the sketch says so once at the line that read it, and goes on. A headless run (`roci run --frames`, `roci test`) opens no camera and always draws the gray picture, which keeps stored pictures exact.

## A mirror

A camera shows what it sees, so moving to the right moves to the left on the screen. `flip` turns the picture over the other way, as a mirror does:

```roci
draw [
  image (flip webcam) at 20 20 width 360
]
```

## Filling shapes and text

A picture is a fill, and so is the webcam. The shape acts as a mask, and its outline is drawn over it:

```roci
draw [
  background 20
  fill webcam
  circle at 200 150 radius 110
  text "live" at 120 120 size 64 fill webcam
]
```

A text filled with a picture is cut out of it on the CPU, again for each new frame, so a big text with the webcam in it costs more than a circle does.

## One picture a frame, and snapshots

`webcam` gives the same picture for the whole of a frame, wherever it is read, and the next frame it gives the newest one the camera has made. A picture kept in a variable stays as it was, so `webcam` read at a click is a snapshot:

```roci
shots = []

on mouse down [
  add webcam to shots
  if (count shots) > 5 [ remove (item 1 of shots) from shots ]
]

draw [
  image (flip webcam) at 20 20 width 240
  for i from 1 to count shots [
    image (item i of shots) at (20 + (i - 1) * 70) 220 width 64
  ]
]
```

The camera makes about 30 pictures a second, so a sketch drawing 60 frames a second sees the same picture for two frames in a row. A frame nothing has drawn or read for a second and a half is let go, so a camera left running does not fill the memory; a snapshot a sketch keeps and draws is kept.

## Size

`webcam.width` and `webcam.height` are the size of the picture. The camera is asked for a size near 640 by 480, and a device that cannot give it converts, so the size is whatever its nearest format is. Draw it with `width` or `height` to fit the window, and the other side follows.

## With C and Odin

C programs have `roci_webcam`, which gives a picture number to pass to `roci_image` and the other picture functions. In Odin, `webcam()` gives the picture.

## Testing

A headless run has no camera. A test of a sketch that reads the webcam gives it frames with the Odin API's `feed_webcam` (a width, a height and the red, green, blue and alpha bytes of each pixel), after `start_headless`, and `set_webcam_problem` makes the camera say it cannot be used.
