# The rocinante Manifesto

```
circle 100 100 50
```

That is a complete rocinante program. Run it and a window opens with a circle in it. No setup function, no imports, no build file, no semicolon. If you understand that line, you can start.

## Why this exists

I have spent decades making work with Processing, openFrameworks and Cinder. They gave a generation of artists a way in, and I owe them a lot. But every year the distance grows between the idea in my head and the thing on the screen. Toolchains break. Graphics APIs age underneath the frameworks. Getting a sketch onto a phone takes a weekend of signing certificates and build scripts. The joy leaks out.

Coding has become bureaucracy. Most of what we type is ceremony that serves the machine and the toolchain, not the idea. rocinante is an attempt to give that time back.

## What we believe

**Joy is a feature.** If something makes coding feel like paperwork, that's a bug, and we fix it like one.

**One line should make a picture.** Papert called it low floor, high ceiling, and Logo showed that a child could step onto that floor. We want the same floor, with a ceiling high enough for an installation that runs for a year.

**The machine does the bookkeeping.** Shader compilation, GPU backends, memory, threads, packaging, code signing. That's our problem, not the artist's. Nobody should have to learn what a swapchain is to draw a circle.

**Fast underneath, gentle on top.** The core is written in Odin and talks directly to Vulkan, Metal and Direct3D 12 through SDL3. Your sketch is a few friendly words; what runs is native code on a modern GPU. Being friendly should never cost you speed you can feel.

**The canvas never crashes.** When you make a mistake, the last good frame keeps running and the error appears on top of it, in plain words, pointing at the exact spot, with an example of what probably works. An error should teach you something.

**Change it and see it.** Save the file and the sketch updates while it runs, keeping its state. The particles keep flying while you change their colour.

**Small and predictable beats clever.** rocinante reads close to English, but it isn't English. It has few words and one shape (a verb, then what it acts on), so once you've guessed the pattern you can guess the rest. No semicolons, no braces, no punctuation that exists only for the parser.

**Everywhere, from one sketch.** FreeBSD, Linux, macOS, Windows, iOS and Android. The same file runs on all of them, and `roci package ios` turns it into something you can ship. Where a platform owner imposes rules we can't remove (Apple's signing, for one), we make them as painless as we can and tell you plainly what's left.

**Batteries included.** 2D, 3D, text, images, sound, MIDI, OSC, cameras, video, files, networks, sensors, multiple windows that talk to each other. Everything the classic frameworks do, built on current libraries instead of ones the graphics world has moved past.

**Interfaces are part of the work.** Buttons, sliders, text boxes, drop-downs, knobs: in other frameworks these are add-ons you hunt for and wire up. In rocinante they are words like any other. `size = slider "size" 10 200` is a slider, already on screen, already remembering its value.

**Open, forever.** rocinante is open source. It belongs to the people who make things with it.

## What it feels like

```
w  = window 800 600
w2 = window 400 400 at 900 100

draw w [
  background 0
  repeat 36 [ forward 100  right 170 ]
  text "hello" at 20 20
  send w2 mouse
]

on w2 receive m [ circle m.x m.y 20 ]
```

Two windows. One draws a star with a turtle and passes the mouse to the other, which follows it with a circle. Every line in it is about the picture.

## The name

rocinante was Don Quixote's horse: thin, unlikely, carrying a dreamer toward windmills everyone else said were giants. Centuries later the name went to a small ship in *The Expanse* that kept flying when it had no business doing so. A tool for people who tilt at things seemed to deserve it.

---

*Fabrizio (sandbenders), Berlin, 2026*
