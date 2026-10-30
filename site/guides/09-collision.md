---
title: "Collision"
summary: "Shapes as records, and the five verbs that say whether, where and what they touch."
weight: 9
---

rocinante can tell whether shapes touch. The shapes are plain records, recognized by their fields, so the same record is drawn and tested:

| Fields | Shape |
|---|---|
| a vector, `{ 10, 20 }` | a point |
| `pos` and `radius` | a circle |
| `pos` and `size`, and `angle` if it is turned | a rectangle, from its top-left corner |
| `from` and `to` | a line |
| `points` | a polygon |

A record is the shape its own curly brackets say, so a list can hold lines and circles together.

## touching and inside

```roci picture
ball = { pos: { 200, 150 }, radius: 40 }
wall = { pos: { 220, 60 }, size: { 140, 30 } }
if touching ball wall [ fill tomato ] else [ fill teal ]
circle at ball.pos radius ball.radius
rect at wall.pos size wall.size fill 120
```

`touching a b` counts edges that only meet. `inside point shape` asks whether a point is in a shape, edges included:

```roci picture
box = { pos: { 100, 75 }, size: { 200, 150 } }
draw [
  background 240
  if inside mouse box [ fill gold ] else [ fill 200 ]
  rect at box.pos size box.size
]
```

## contact: which way to bounce

`contact a b` says where two shapes meet: `normal` is the way to move the first one out of the second, and `depth` how far. Moving it that far, then turning its speed back along the normal, is a bounce:

```roci picture
ball = { pos: { 200, 60 }, radius: 16, vel: { 2, 3 } }
floor_box = { pos: { 0, 260 }, size: { 400, 40 } }
draw [
  background 240
  ball.pos = ball.pos + ball.vel
  if touching ball floor_box [
    c = contact ball floor_box
    ball.pos = ball.pos + c.normal * c.depth
    ball.vel.y = -ball.vel.y
  ]
  rect at floor_box.pos size floor_box.size fill 120
  circle at ball.pos radius ball.radius fill tomato
]
```

When the shapes do not touch, every field of the answer is 0.

## hits: everything in a list

`hits shape list` gives every item of a list that touches a shape, in the list's order, which is how a ball breaks bricks:

```roci picture
bricks = []
for i from 0 to 7 [ add { pos: { i * 50, 40 }, size: { 46, 20 } } to bricks ]
ball = { pos: { 160, 52 }, radius: 30 }
for each b in (hits ball bricks) [ remove b from bricks ]
for each b in bricks [ rect at b.pos size b.size fill gold ]
circle at ball.pos radius ball.radius
```

## cast: what a line meets first

`cast line list` follows a line from its `from` to its `to` and gives the first item it meets: the `item`, the `point`, the `normal` there and the `distance`:

```roci picture
walls = [ { pos: { 300, 100 }, size: { 40, 100 } } { pos: { 180, 150 }, radius: 30 } ]
ray = { from: { 20, 150 }, to: { 380, 150 } }
h = cast ray walls
line from ray.from to h.point stroke tomato thickness 3
circle at 180 150 radius 30
rect at 300 100 size 40 100
```

Asked about a long list many times, `hits` and `cast` keep a tree of where the shapes are, so a thousand shapes stay quick.
