---
title: "Frequently asked questions"
summary: "Why another creative coding tool, why Logo, where the objects went, why a language in the age of AI, and what Odin has to do with it."
type: "faq"
---

## Why bother? We already have Processing, openFrameworks and Cinder!

We do, and they're wonderful. rocinante comes out of decades of making work with all three, and it borrows from each of them. Processing gave a generation of artists a way in, and openFrameworks and Cinder gave them speed.

What rocinante adds is a different set of trade-offs:

- **One language from the first line to the finished piece.** Processing is gentle and slower; openFrameworks and Cinder are fast and ask you to learn C++, its compilers and its build files. rocinante is gentle on top and fast underneath: you write a few friendly words, and a modern engine draws them on the GPU.
- **Change it and see it.** Save the file and the running sketch updates, keeping its values, so the particles keep flying while you change their color.
- **Mistakes teach.** An error never closes the window. It shows over the last good frame, points at the spot, says what went wrong in plain words and shows a line that works.
- **A modern engine.** rocinante draws through Vulkan, Metal and Direct3D 12, never OpenGL, which the graphics world has moved past.
- **Everywhere.** The same sketch runs on FreeBSD, Linux, macOS and Windows.

It's an alpha, so not all of this is there yet. Text, user interfaces, images, sound, 3D and packaging a sketch as an app for the desktop or a phone are on the way; the [README](https://github.com/sandbenders/rocinante#readme) says what's done.

## Logo? Is it not so 60s?

Logo was born in 1967, and its best ideas have aged better than most of what came after:

- **Words, not symbols.** `forward 100` reads as what it does.
- **A low floor.** Seymour Papert, one of Logo's makers, wanted a child to step onto it, and children did. One line of rocinante makes a picture.
- **Teaching the computer new words.** In Logo you teach the turtle with `to`; in rocinante with `learn`, and a taught verb works exactly like a built-in one.
- **The turtle.** It's still one of the best ways to think about drawing, and every rocinante window has one.

```roci
repeat 5 [
  forward 200
  right 144
]
```

What rocinante leaves behind are the parts of Logo that tripped people up, which the people who made Logo wrote about themselves: names that change meaning depending on who called you, colons in front of names, and lines whose meaning you could only work out by counting how many inputs each word takes. In rocinante, each input of a verb is one thing (a number, a name, or a calculation in round brackets), so you can always see where a call ends.

## Where are the objects?

There aren't any, on purpose. rocinante is procedural and data-oriented, like Logo and like Odin: there is plain data (numbers, text, vectors, colors, lists and records), and there are verbs that act on it. You write `fall p`, not `p.fall()`.

Many things on the screen are a list of records, and one verb that acts on one of them:

```roci
particles = []
repeat 200 [ add { pos: { random width, 0 }, vel: { 0, random from 1 to 3 } } to particles ]

learn fall p [
  p.pos = p.pos + p.vel
  if p.pos.y > height [ p.pos.y = 0 ]
]

draw [
  for each p in particles [
    fall p
    circle at p.pos radius 3
  ]
]
```

There are no classes, methods, inheritance or constructors to learn, only verbs on data. It's also what will make a shipped sketch fast: a list of records of the same shape can sit in memory in one piece, which is how a computer likes to read it.

## Why another language when AI can code anything?

Because making things with code is not only about getting code. It's about the playing: trying an idea, seeing it, changing a number and seeing it again. rocinante is built for that loop, and an AI can join it rather than replace it.

A small language helps the people and the AI alike:

- **You can read what was written.** rocinante has few words and one shape, so a sketch, whoever wrote it, can be read and changed by its author. Code you can't read is code you can't play with.
- **Mistakes are explained.** Every error says where, what and how to fix it, in words you can learn from, whether the mistake was yours or a machine's.
- **There is one way to write each thing.** The grammar is written down and `roci fmt` keeps every sketch in one style, which makes rocinante easy for tools, AI included, to write correctly.

rocinante itself was built with the help of AI, by someone who has researched creative AI for more than twenty years. The idea is a partnership, where people and machines make things together and people stay in charge of what's made.

## How has the almighty god Odin got involved in rocinante?

No ravens were harmed. This [Odin](https://odin-lang.org/) is a programming language, created by Ginger Bill, and the core of rocinante is written in it: the engine, the language and the `roci` program.

It was chosen because it thinks the way rocinante does. It is simple, compiles to fast native code, keeps data plain and in one piece, and does arithmetic on whole vectors, so `p.pos + p.vel` in a sketch is the same idea in the engine underneath. Its own collection of libraries brings SDL3, through which rocinante talks to the GPU on every system.

There is a second reason. When `roci package` arrives, it will turn a sketch into Odin and build it into a native program, so a sketch you ship runs as fast as one written in Odin by hand, while you only ever see rocinante.
