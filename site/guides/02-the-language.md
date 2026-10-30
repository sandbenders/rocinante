---
title: "The language in one sitting"
summary: "Names, numbers, text, colors, vectors, records and lists, and the one rule about brackets."
weight: 2
---

rocinante has few rules. This page goes through all of them once; the guides after it go deeper into each part.

## One line, one thing

Each line is one statement: a **verb**, then what it works on.

```roci picture
background 30
circle at 200 150 radius 80
```

Verbs that draw take **labels** that say what each number is: `at` for a position, `radius`, `size`, `from` and `to`. The labels can come in any order, so `circle radius 80 at 200 150` is the same circle.

## Names

A name holds a value. Give it one with `=`, and use it anywhere a value goes:

```roci picture
size = 40
circle at 100 100 radius size
size = size * 2
circle at 260 100 radius size
```

A name written in capitals, like `SPEED`, is a **constant**: it gets its value once and can never change. Use one for a value the whole sketch shares.

```roci
SPEED = 4
x = 0
x = x + SPEED
```

## Kinds of value

| Kind | Written | |
|---|---|---|
| number | `3`, `0.5`, `-10` | every number is one kind; no difference between whole and not |
| text | `"hello"` | `+` joins text: `"score: " + 3` |
| true or false | `true`, `false` | what a comparison gives |
| color | `red`, `#ff8800`,<br>`rgb 255 136 0` | 0 to 255 for each channel, a name from the CSS list |
| vector | `{ 100, 50 }` | two numbers, a position or a size; `v.x`, `v.y` |
| record | `{ pos: { 10, 20 },`<br>`life: 1 }` | named fields; `ball.pos`, `ball.life` |
| list | `[ 1 2 3 ]`,<br>`[ red gold teal ]` | many values in order, no commas between them |

A vector has commas and curly brackets; a list has square brackets and no commas. They look alike, and mixing them up is the commonest early mistake.

```roci picture
p = { 120, 80 }
circle at p radius 20
ball = { pos: { 200, 150 }, radius: 30 }
circle at ball.pos radius ball.radius
COLORS = [ tomato gold teal ]
fill (item 2 of COLORS)
circle at 300 220 radius 30
```

## Arithmetic

`+ - * /` work as you expect, `%` gives what is left after dividing, and they work on vectors and colors too:

```roci picture
pos = { 100, 100 }
vel = { 3, 1 }
pos = pos + vel * 10
circle at pos radius 10
```

Comparisons are `<`, `<=`, `>`, `>=`, `is` and `is not` (a single `=` gives a name a value, it never compares). `and`, `or` and `not` join them.

## The one rule about round brackets

A verb's value is always **one thing**: a number, a name, a field, something in brackets. When a value is a calculation or another verb's answer, put it in round brackets:

```roci picture
circle at (random 400) (random 300) radius 10
rect at 20 20 size (40 * 2) 40
```

Without the brackets rocinante cannot tell where one value ends and the next begins, so it says so and shows the line with them added. `roci fmt` adds them for you where it can. On the right of `=`, a whole calculation needs none:

```roci
x = random 400 + 20
```

## Blocks

Square brackets around lines make a **block**: lines that run later, or again, or only sometimes.

```roci picture
repeat 3 [
  circle at (random 400) (random 300) radius 20
]
if 2 > 1 [ fill tomato ] else [ fill teal ]
```

A short block can sit on one line, with two spaces between its statements: `[ fill red  circle at 10 10 radius 5 ]`. Indentation never changes what a sketch does; `roci fmt` keeps it tidy.

## Comments

Two slashes start a comment, which runs to the end of the line. `#` is only for colors.

```roci picture
// a dark sky
background (rgb 10 10 40)
```
