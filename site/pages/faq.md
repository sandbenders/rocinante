---
title: "Frequently asked questions"
summary: "Why another creative coding tool, why Logo, where the objects are, what runs where, what happens when a sketch fails, the license, and who is behind it."
type: "faq"
---

## Why bother? We already have Processing, openFrameworks and Cinder!

We do, and they're wonderful. rocinante comes out of decades of making work with all three, and it borrows from each of them. Processing gave a generation of artists a way in, and openFrameworks and Cinder gave them speed.

My main problems with them relate to the syntax of the languages they are built in, and their reliance on technologies that are either deprecated on some platforms or have better modern alternatives. I have spent decades working with different object-oriented languages, and I think creative coding can be simpler and more elegant, with interpreters and compilers that use updated libraries and technologies, making their use transparent to the users.

Another problem is packaging. It is still hard to package the final piece and distribute it to the whole modern ecosystem, including different platforms and mobile devices.

rocinante provides one simple language that I have been crafting for years, both for my personal use and for use in classrooms, that doesn't require learning Java, Python, or C++. Even so, it is expressive, powerful, and complete enough to build full multiplatform applications, including a light unit test system. You write a few friendly words and its engine draws them on the GPU. With one command, you can package it, without having to deal with build files.

The language ships with an interpreter, allowing hot reload. You change it and see it. Save the file in your favorite editor and the running sketch updates, keeping its values so particles keep flying while you change their color. When you feel the work is done, a simple command compiles your sketch into executable machine code that runs at native compiled speed. You don't need to worry about Metal, Vulkan, or Direct3D. rocinante takes care of all of that.

Because rocinante is meant for professional work, teaching, and debugging, a mistake in the code never closes the window. rocinante shows the mistake over the last good frame, pointing clearly to the line and the error, saying in plain words what is wrong and, in most cases, showing the fix. No cryptic compiler or linker errors.

It's still an alpha, so not all of this is there yet. Text, user interfaces, images, sound, 3D, and packaging a sketch as a desktop or phone app are on the way. The README and this page say what's done.

## Why not Python, or JavaScript like p5.js?

Both are fine languages, and p5.js is a lovely way to make things in a browser. They were made for everything, though, and creative coding is one thing among many: a sketch starts with imports and setup, a mistake comes back as a stack trace, and the speed is the speed of the language.

rocinante is made for one job, so it can do that job with less in the way:

- **No setup.** `circle at 100 100 radius 50` is a whole program.
- **Mistakes in plain words.** The language is small enough for every error to say where, what, and what would work.
- **Native speed, native places.** A sketch draws through the GPU's own interface, and a shipped one will be native code: an installation that runs for a year, a phone app, a sketch with a hundred thousand shapes.

A web version is on the [roadmap](https://github.com/sandbenders/rocinante#roadmap), so sketches can be shared in a browser too.

## I love OpenGL and have been using it for decades! Why not support it?

So have we, and much of what rocinante knows about drawing was learned with it. But OpenGL is standing still while the systems under it move on:

- **Apple has left it behind.** macOS stopped at OpenGL 4.1, from 2010, and Apple deprecated it in 2018, on the Mac and on the iPhone. A sketch on OpenGL would run on Apple's computers only as long as Apple keeps the old code around.
- **Its successors are where the work goes.** The group that made OpenGL now puts its effort into Vulkan, and the drivers, the tools and the fixes follow.
- **One engine means one behavior.** Supporting OpenGL beside Vulkan, Metal and Direct3D 12 would mean a second engine, with its own bugs and its own idea of how a picture looks, and a sketch must look the same everywhere.

So rocinante draws through Vulkan on FreeBSD, Linux and Android, Metal on macOS and iOS, and Direct3D 12 on Windows, each the system's own modern interface, through SDL3. You never see which one: a sketch is the same file on all of them.

The cost is that a computer whose graphics card has none of the three can't run rocinante. Most cards from the last ten years have at least one.

If what you love is writing shaders, you will be able to: your own shaders arrive in a later release, written in HLSL, which a GLSL hand reads easily, and they reload as you save.

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

## What happens if my sketch fails in the middle of a performance?

The window stays open, and the last good frame keeps running. rocinante never lets a mistake close the canvas:

- **A mistake in the code you save** (a misspelled word, a missing bracket) is caught before it runs. The old code keeps going, with the message drawn over it, and the next save that fixes it takes over.
- **A mistake while it runs** (an item that is not in a list, a division by zero) gives an empty value or 0 and a message, once for each place, and the sketch carries on.
- **A block that never ends** is stopped after two seconds, with a message saying which one.
- **Escape does not quit**, so a stray key can't end a show. Ctrl+Q (Cmd+Q on a Mac) or the window's close button do, and Ctrl+R (Cmd+R) starts the sketch again from its first line.

A crash of rocinante itself is treated as a bug of the highest priority. If you meet one, please [report it](https://github.com/sandbenders/rocinante/issues).

## Which computers does it run on? Can I make phone apps?

You write and run sketches on **FreeBSD, Linux, macOS and Windows**: x86-64 computers, and Macs with Apple silicon. The same sketch file runs on all four.

**iPhones and Android phones** are places a sketch goes, not places you write it. `roci package ios` and `roci package android` will turn a sketch into an app you install or publish; they are on the way and not in the alpha yet. An iPhone app can only be built on a Mac, because Apple's tools run only there, and an Android app on macOS, Linux or Windows.

## Is it free? Can I sell what I make with it?

Yes, and yes. rocinante is open source under the [Zero-Clause BSD license](https://opensource.org/license/0BSD), one of the most permissive there is: use it, change it, share it and sell what you make, for any purpose, with no conditions, not even a credit line (though a mention is always welcome).

What you make is yours. Your sketches, the pictures they draw and the apps you build from them belong to you, under whatever license you choose.

## Who is behind rocinante, and how can I help?

rocinante was started by [Fabrizio Poltronieri](https://github.com/sandbenders), an artist, researcher and educator who has made work with code for decades; the [manifesto](https://github.com/sandbenders/rocinante/blob/main/MANIFESTO.md) tells why. It is open source and meant to stay that way, belonging to the people who make things with it, and the hope is to give it a home in a foundation as it grows.

There are many ways to help, and most need no programming:

- **Make things with it** and show them. Nothing helps more than sketches people want to copy.
- **Tell us where it got in your way.** A message that confused you, a guide that lost you, a word you expected and didn't find: [report it](https://github.com/sandbenders/rocinante/issues). These are bugs, and they get fixed like bugs.
- **Teach with it**, and say what your students tripped on.
- **Write code.** Issues and pull requests are welcome on [GitHub](https://github.com/sandbenders/rocinante); the [README](https://github.com/sandbenders/rocinante#contributing) explains how a contribution reaches the project.
