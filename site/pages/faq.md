---
title: "Frequently asked questions"
summary: "Why another creative coding tool, why Logo, where the objects are, what runs where, what happens when a sketch fails, the license, and who is behind it."
type: "faq"
---

## Why bother? We already have Processing, openFrameworks and Cinder

We do, and they're wonderful. rocinante comes out of decades of making work with all three, and it borrows from each of them. Processing gave a generation of artists a way in, and openFrameworks and Cinder gave them speed.

My main problems with them relate to the syntax of the languages they are built on, and their reliance on technologies that are either deprecated on some platforms or have better modern alternatives. I have spent decades working with different object-oriented languages, and I think creative coding can be simpler and more elegant, with interpreters and compilers that use updated libraries and technologies, making their use transparent to the users.

Another problem is packaging. It is still hard to package the final piece and distribute it to the whole modern ecosystem, including different platforms and mobile devices.

rocinante provides one simple language I have been crafting for years, both for my personal use and for use in classrooms, that doesn't require learning Java, Python, or C++. Even so, it is expressive, powerful, and complete enough to build full multiplatform applications, including a light unit test system. You write a few friendly words and its engine draws them on the GPU. With one command, you can package it, without having to deal with build files.

The language ships with an interpreter, allowing hot reload. Change it and see it. Save the file in your favorite editor and the running sketch updates, keeping its values, so particles keep flying while you change their color. When you feel the work is done, a simple command compiles your sketch into executable machine code that runs at native compiled speed. You don't need to worry about Metal, Vulkan, or Direct3D. rocinante takes care of all of that.

Because rocinante is meant for professional work, teaching, and debugging, a mistake in the code never closes the window. rocinante shows the mistake over the last good frame, pointing clearly to the line and the error, saying in plain words what is wrong and, in most cases, showing the fix. No cryptic compiler or linker errors.

It's still an alpha, so not all of this is there yet. Text, user interfaces, images, sound, 3D, and packaging a sketch as a desktop or phone app are on the way. The README and this page say what's done.

## Why not Python, or JavaScript like p5.js?

Both are fine languages, and p5.js is a lovely way to make things in a browser, although I must confess I dislike JavaScript. For many years I taught an MA class called "Creative Coding for Artists", using Python as the main language, with an early version of rocinante as a library. The trouble is that both languages were made for everything, and creative coding is one thing among many. So a sketch starts with imports and setup, a mistake comes back as a stack trace, and the speed is the speed of the language. I felt my students' pain, and that of my fellow artists, too.

rocinante is made for one job, so it can do it with less in the way: there is no setup, a mistake is explained in plain words, and a shipped sketch runs as native code.

A web version is on the [roadmap](https://github.com/sandbenders/rocinante#roadmap), so you will be able to share sketches in a browser too.

## I love OpenGL and have been using it for decades! Why not support it?

I wouldn't say I love OpenGL, Vulkan, Metal or Direct3D. I don't enjoy spending days writing code just to open a window with a red triangle in it, but I admit OpenGL is the friendliest of them, and perhaps still the most popular. Much of how rocinante draws comes from my experience with OpenGL. But OpenGL is standing still while the systems under it move on.

Apple left it behind long ago: macOS stopped at OpenGL 4.1, a version from 2010, and Apple deprecated it in 2018, on the Mac and on iOS. A sketch using OpenGL would run on Apple's computers only as long as Apple keeps the old code around, and we all know Apple is very good at dropping established technologies. Recently, Apple has been making macOS and iOS friendlier for game development, and that effort is built on Metal.

The Khronos Group, which maintains OpenGL, now focuses on Vulkan, and the drivers, tools and fixes follow.

SDL3 has a solid GPU interface, which translates its calls into Vulkan, Metal and Direct3D 12. Adding OpenGL alongside them would mean a second engine, with its own bugs and its own idea of how a picture looks, and a sketch must look the same everywhere.

So rocinante draws through Vulkan on FreeBSD, OpenBSD, Linux and Android, Metal on macOS and iOS, and Direct3D 12 on Windows, each the system's own modern interface, through SDL3. You never need to know which one is used: a rocinante sketch is the same file on all of them.

The cost is that a computer whose graphics card has none of the three can't run rocinante. Most cards from the last ten years have at least one.

If what you love is writing shaders, you will be able to: your own shaders arrive in a later release, written in HLSL, which anyone who writes GLSL reads easily, and they reload as you save.

## Logo? Is it not so 60s?

Logo was born in 1967, and in my opinion, as a semioticist, mathematician and artist, its best ideas have aged better than most of what came after. Logo uses words, not symbols, so `forward 100` reads as what it does.

Logo also has a low floor: Seymour Papert, one of its makers, wanted a child to be able to step onto it, and children did. Logo has a long and successful history in schools; see, for example, [what happened in Costa Rica](https://www.microworlds.com/support/logo-philosophy-costa-rica.html).

In Logo you teach the computer new words with `to`; in rocinante you do it with `learn`, and a word you teach works exactly like a built-in one.

And the turtle is still one of the best ways to think about drawing, and every rocinante window has one:

```roci
repeat 5 [
  forward 200
  right 144
]
```

What rocinante leaves behind are the parts of Logo that tripped people up, which Logo's makers wrote about themselves: names that change meaning depending on who called you, colons in front of names, and lines whose meaning you could only work out by counting how many inputs each word takes. In rocinante, each input of a verb is one thing, a number, a name or a calculation in round brackets, so you can always see where a call ends.

## Where are the objects?

There aren't any, on purpose. rocinante is procedural and data-oriented, like Logo and Odin: there is plain data (numbers, text, vectors, colors, lists and records) and there are verbs that act on it. You write `fall p`, not `p.fall()`.

After decades of working almost exclusively with object-oriented languages, I got fed up with them. I now enjoy the simplicity of procedural languages such as C, and I don't think creative coders need to adopt an object-oriented paradigm.

In rocinante, many things on the screen are a list of records, and one verb that acts on one of them:

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

There are no classes, methods, inheritance or constructors to learn, only verbs on data. That's also what will make a shipped sketch fast: a list of records of the same shape can sit in memory in one piece, which is how a computer likes to read it.

## Why another language when AI can code anything?

Because making things with code is not only about getting code done. It's about the play, the fun, the challenge. Creative coding is about trying an idea, seeing it, changing a number and seeing it again. Failing and trying again. Discovering the wonder of a mistake that turns into a surprising image, an amazing sound, an astonishing piece of interaction. rocinante is built for that loop, and an AI can join it rather than replace it.

This is exactly what I call the "Symbiotic Future", a concept I coined and have been writing and talking about for years. Over the decades, culture has helped build a dark picture of AI's role. In the dystopian societies of films such as *Metropolis* (1927) and *2001: A Space Odyssey* (1968), machines take over and replace humans. More recently, the idea of the singularity has reawakened the fear that ordinary humans will someday be overtaken by artificially intelligent machines, cognitively enhanced biological intelligence, or both.

While such stories are compelling as entertainment, my vision as an artist and researcher who has worked with creative AI for over two decades is very different. I believe in an increasingly symbiotic future, where AI and humans play together in real time, sharing transparent processes and decisions, with collaboration as a critical concept. The main objective is to challenge and enhance both human and computer creativity. I do not think computers will replace human creativity, but I believe they will collaborate ever more closely to enhance our perceptions of, and through, creative acts. For more, see [*The Language of Creative AI*](https://link.springer.com/book/10.1007/978-3-031-10960-7), a book I co-edited.

A small language like rocinante also helps people and AI alike. rocinante has few words and one shape, so a sketch can be read and changed by you, whoever wrote it. Code you can't read is code you can't play with. rocinante's grammar is written down, and `roci fmt` keeps every sketch in one style, which makes it easy for tools, AI included, to write rocinante correctly.

I built rocinante with the help of AI, putting the Symbiotic Future into practice once more.

## How has the almighty god Odin got involved in rocinante?

No ravens were harmed. This [Odin](https://odin-lang.org/) is a programming language, created by Ginger Bill, and the core of rocinante is written in it, including the engine, the language and the `roci` program.

I chose it because it thinks the way rocinante does. It is simple, compiles to fast native code, keeps data plain and in one piece, and does arithmetic on whole vectors, so `p.pos + p.vel` in a sketch is the same idea in the engine underneath. Odin also shaped rocinante itself: its verbs on plain data, its vectors in braces and its useful zero values all come from there. Its own collection of libraries brings SDL3, through which rocinante talks to the GPU on every system.

There is a second reason. When `roci package` arrives, it will turn a sketch into Odin and build it into a native program, so a sketch you ship will run as fast as one written in Odin by hand, while you only ever see rocinante.

## What happens if my sketch fails mid-performance?

That's one of the most terrifying experiences: you are performing in front of an audience and suddenly… the software crashes. rocinante, like any other software, isn't completely bulletproof, but I designed it around the idea that errors and bugs should be recoverable. So when something goes wrong, rocinante's window stays open and the last good frame keeps running. rocinante never lets a mistake close the canvas.

While you work with `roci run`, a mistake in the code you save (a misspelled word, a missing bracket) is caught before it runs. The old code keeps going with the message drawn over it, and the next save that fixes it takes over.

A mistake while the sketch runs (an item that is not in a list, a division by zero) gives an empty value or 0, and the sketch carries on. `roci run` shows a message, once for each place; a shipped sketch will write it to its log instead, so the audience never sees it.

Under `roci run`, a block that never ends is stopped after two seconds, with a message saying which one.

And Escape does not quit, so a stray key can't end your performance by mistake. Ctrl+Q (Cmd+Q on a Mac) or the window's close button does, and under `roci run`, Ctrl+R (Cmd+R) starts the sketch again from its first line.

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
