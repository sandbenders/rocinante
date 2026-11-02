---
title: "roci man"
summary: "Show how a word of the language is written, in the terminal, made from the same data as the reference on this site."
type: "tool"
---

`roci man` shows how a word is written, without leaving the terminal. It reads the same data as [the reference](../reference/), so the two always agree.

```
roci man                 every word, one line each
roci man circle          how circle is written, with an example for each form
roci man for each        a word of two parts
```

A word is a verb (`circle`), a statement (`repeat`, `check`) or a built-in value (`mouse`, `turtle`). For a verb it shows each form it can be written in, which parts are optional, and an example:

```
circle
  Draws a circle around a point.

  circle at x y radius radius [fill color] [stroke color] [thickness number] ...
      for example circle at 100 100 radius 50
```

A word in square brackets is a connecting word you may leave out. A word that does not exist gets the nearest one, as it does in a sketch.

The reference on this site adds a picture for every word, and the guides teach the words in order. `roci man` is for the moment you only need to remember the order of the parts.
