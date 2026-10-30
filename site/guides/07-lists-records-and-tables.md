---
title: "Lists, records and tables"
summary: "Keeping many things: lists and their verbs, records with fields, sharing and copy, tables of names."
weight: 7
---

## Lists

A list holds values in order, written in square brackets with no commas:

```roci
sizes = [ 10 25 40 ]
add 55 to sizes
remove 10 from sizes
print (count sizes)
print (item 1 of sizes)
```

Items are counted from 1. Asking for an item that is not there gives an empty value (0 for numbers) and says so, without stopping the sketch.

## Records

A record holds named fields, in curly brackets:

```roci
ball = { pos: { 200, 150 }, vel: { 3, 2 }, radius: 20 }
ball.pos = ball.pos + ball.vel
circle at ball.pos radius ball.radius
```

A field that is given a value anywhere in the sketch belongs to every record made in the same place, and reads 0 until it is set. A field nothing ever sets is a typo, and rocinante says which fields there are.

## Many things: a list of records

Particles, balls, birds: a list of records, and a verb that moves one.

```roci
balls = []
repeat 20 [ add { pos: anywhere, vel: { (random from -3 to 3), (random from -3 to 3) } } to balls ]
draw [
  background 30
  for each b in balls [
    b.pos = b.pos + b.vel
    circle at b.pos radius 8 fill gold
  ]
]
```

## The list verbs

Each of these gives a new list or value and leaves the old one alone. Inside their block, `it` is the item:

```roci
ages = [ 12 17 21 30 8 ]
adults = keep ages [ it >= 18 ]
children = skip ages [ it >= 18 ]
doubled = collect ages [ it * 2 ]
total = combine ages from 0 [ result + it ]
first_adult = find ages [ it >= 18 ]
youngest_first = sort ages by [ it ]
mixed = shuffle ages
print adults
```

In `combine`, `result` is the value so far.

## Shared, or copied

Numbers, text, vectors and colours are copied when they are given to a new name. Lists and records are **shared**: `b = a` makes `b` another name for the same list, and changing one changes the other.

```roci
a = [ 1 2 ]
b = a
add 3 to b
print (count a)
```

This prints 3, and rocinante adds a hint on the `add` line, because changing a list through a second name is usually a surprise. `copy` makes a separate one:

```roci
a = [ 1 2 ]
b = copy a
add 3 to b
print (count a)
```

Sharing is what lets a verb change a record it is given, which the [teaching verbs](../08-teaching-verbs/) guide uses.

## Tables

A table holds text names, each with a value, kept in the order they were put:

```roci
counts = table
put counts "cat" 2
put counts "owl" 1
put counts "cat" 3
print (get counts "cat")
for each name in (keys counts) [ print name ]
remove "owl" from counts
print counts
```

A name that is not there reads as an empty value. `count counts` says how many names there are.
