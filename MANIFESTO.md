# The rocinante manifesto

## Before the manifesto

I always thought that Manifestos are somehow dated, things that made sense in the modern era, and suited art movements like [Dadaism](https://391.org/manifestos/1918-dada-manifesto-tristan-tzara/) very well (DADA DOES NOT MEAN ANYTHING). Do we still need Manifestos, something that breaks with the past, in an era where computers, digital technologies, and AI act as a semiotic funnel, blurring the line between what is what? And here I am, writing a Manifesto!

I am multiple things: A mathematician, a PhD in semiotics, an [artist](https://collections.vam.ac.uk/search/?id_person=AUTH346833&page=1&page_size=15), a graphic designer, a computer scientist, an academic researcher, a book writer, and the CTO of a [Creative AI company](https://big-c.ai). More than that, my life changed because of an event when I was 9 years old and lived in Porto Alegre, in the south of Brazil. That day, my father came home with a mysterious-looking box whose contents would change my perception of the world and how I interact with it for the rest of my life.

Inside that box was a [Brazilian clone](https://en.wikipedia.org/wiki/TK90X) of a [ZX Spectrum](https://www.retrocompute.co.uk/systems/zx-spectrum/), a classic British microcomputer. Nowadays, it is increasingly common to see children, even under 9, programming their Raspberry Pis in Python. In Porto Alegre, I believe I was one of the few people at that time, especially for my age, to have a microcomputer. If you didn’t know how to program back then, a computer’s usefulness was quite limited. So, practically every day since that box turned up at home, I've dedicated some time to programming.

It’s interesting to note that I have always seen programming as an extremely playful and creative activity, not just technical work. For me, programming has always been an experimental activity, where computers are playgrounds that have always given my creativity wings. After earning degrees in mathematics and graphic design, I realised art could be fertile ground for combining the two disciplines. I continued my academic education by completing my PhD in Semiotics, with a thesis on the role of chance in computational art, and three Postdocs on the same theme, two in England and one in Germany.

Two elements have always been essential to me: the idea that artists who work with computers should know how to program, and the influence of philosophical concepts on my aesthetic proposals, especially those from semiotics and logic. It always felt natural to me to design a computer language to teach my students creative coding. Of course, this was a huge technical effort I couldn’t have completed without AI’s help.

I have been researching AI for more than 2 decades, and I was lucky enough to curate an exhibition called [Primary Codes](https://www.youtube.com/watch?v=dXybZ9dePqQ) in Rio de Janeiro, Brazil, in 2015 with 4 pioneers of Creative AI: [Frieder Nake](https://en.wikipedia.org/wiki/Frieder_Nake), [Paul Brown](https://paul-brown.art/), Ernest Edmonds, and [Harold Cohen](https://www.youtube.com/watch?v=EZPrsHanGpw). In my co-edited book “[The Language of Creative AI](https://link.springer.com/book/10.1007/978-3-031-10960-7)” (2022), I coined the term “Symbiotic Future” to describe my vision of an increasingly symbiotic future, where AI and humans collaborate in real time, share transparent processes and decisions, and treat collaboration as a critical concept. The main objective is to challenge and enhance human creativity and computer creativity. I do not think computers will replace human creativity, but I do believe they will collaborate even more to enhance our creative processes.

And I also believe that computer coding should be **A FUN ACTIVITY** first and foremost.

## The Manifesto

```
circle 100 100 50
```

That is a complete rocinante program. Run it and a window opens with a circle in it. No setup function, no imports, no build file, no semicolon. If you understand that line, you can start.

## Why this exists

I have spent decades making work with [Processing](https://processing.org/), [openFrameworks](https://openframeworks.cc/) and [Cinder](https://libcinder.org/). They gave a generation of artists a way in, and I owe them a lot. But every year the distance grows between the idea in my head and the thing on the screen. Toolchains break. Graphics APIs age underneath the frameworks. Getting a sketch onto a phone takes a weekend of signing certificates and build scripts. The joy leaks out.

Coding has become bureaucracy. Most of what we type is ceremony that serves the machine and the toolchain, not the idea. rocinante is an attempt to give that time back.

## What we believe

**Joy is a feature.** If something makes coding feel like paperwork, that's a bug, and we fix it like one.

**One line should make a picture.** [Seymour Papert](https://en.wikipedia.org/wiki/Seymour_Papert), the co-inventor of Logo, called it low floor, high ceiling, and Logo showed that a child could step onto that floor. We want the same floor, with a ceiling high enough for an installation that runs for a year.

**The machine does the bookkeeping.** [Shader compilation](https://www.howtogeek.com/846514/what-is-shader-compilation-and-why-does-it-make-pc-games-stutter/), GPU backends, memory, [threads](<https://en.wikipedia.org/wiki/Thread_(computing)>), packaging, code signing. That's our problem, not the artist's. Nobody should have to learn what a [swapchain](https://en.wikipedia.org/wiki/Swap_chain) is to draw a circle.

**Fast underneath, gentle on top.** The core is written in [Odin](https://odin-lang.org/), a wonderful computer language that inspired many of rocinante's design choices, and talks directly to [Vulkan](https://www.vulkan.org/), [Metal](https://developer.apple.com/metal/) and [Direct3D 12](https://learn.microsoft.com/en-us/windows/win32/direct3d) through [SDL3](https://libsdl.org/). Your sketch is a few friendly words; what runs is native code on a modern GPU. Being friendly should never cost you speed you can feel.

**The canvas never crashes.** When you make a mistake, the last good frame keeps running and the error appears on top of it, in plain words, pointing at the exact spot, with an example of what probably works. An error should teach you something.

**Change it and see it.** Save the file and the sketch updates while it runs, keeping its state. The particles keep flying while you change their colour.

**Small and predictable beats clever.** rocinante has few words and one shape (a verb, then what it acts on), so once you've guessed the pattern you can guess the rest. No semicolons, no braces around blocks, no punctuation that exists only for the parser.

**Everywhere, from one sketch.** FreeBSD, Linux, macOS, Windows, iOS and Android. The same file runs on all of them, and `roci package ios` turns it into something you can ship. Where a platform owner imposes rules we can't remove ([Apple's signing](https://support.apple.com/en-euro/guide/security/sec7c917bf14/web), for one), we make them as painless as we can and tell you plainly what's left.

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

[rocinante](https://en.wikipedia.org/wiki/Rocinante) was [Don Quixote's](https://en.wikipedia.org/wiki/Don_Quixote) horse: thin, unlikely, carrying a dreamer toward windmills everyone else said were giants. Centuries later the name went to a small ship in _[The Expanse](<https://en.wikipedia.org/wiki/The_Expanse_(novel_series)>)_ that kept flying when it had no business doing so. A tool for people who tilt at things seemed to deserve it.

---

_Fabrizio Poltronieri (sandbenders), <fabrizio@fabriziopoltronieri.com>, Berlin, 2026_
