---
title: "roci fmt"
summary: "Write a sketch in the house style: two spaces a level, one statement a line, missing brackets added, and nothing to configure."
type: "tool"
---

`roci fmt` rewrites sketches in the house style, so every sketch looks the same and you never argue about layout. It has no options.

```
roci fmt                 every .roci file in this folder and the folders inside it
roci fmt sketch.roci     one file
roci fmt examples        the files in one folder
```

With no name it leaves out `assets`, `libs`, `output` and hidden folders, which are not your own code. Files are rewritten where they are, so use git to see what changed.

## What it does

It keeps what you meant and changes how it is laid out:

- two spaces for each level of brackets, one space inside the brackets, one statement on a line;
- a short block you wrote on one line stays on one line, and a long one is broken up;
- the words of a call in their usual order, so `circle radius 50 at 100 100` becomes `circle at 100 100 radius 50`;
- round brackets added where a call or a calculation sits inside another call, so `circle at random width random height radius 5` becomes `circle at (random width) (random height) radius 5`;
- comments and single blank lines kept, and comments written as `// text`.

Formatting a formatted sketch changes nothing, and the formatted sketch does exactly what the original did.

## When it cannot

A sketch with a mistake that `roci fmt` cannot guess a fix for is left as it is, and the mistake is said, as `roci check` would say it. The missing brackets above are the one mistake it fixes for you.

Most editors can run `roci fmt` when you save.

See also [`roci check`](../roci-check/), and [the language](../guides/02-the-language/) for the rules of the style.
