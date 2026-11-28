---
title: "Physics"
summary: "Give shapes to the physics and it moves them: gravity, bouncing, pushing, and a paddle that follows the mouse."
weight: 41
---

The collision verbs say what touches. The physics goes further: it moves shapes the way things move, falling, bouncing off each other, sliding, coming to rest. The shapes are the same records you already draw and test, so you do not rewrite anything to use it: you give a shape to the physics and it takes over the shape's `pos`.

## A ball and a floor

```roci picture
ball = { pos: { 140, 40 }, radius: 24, vel: { 50, 0 }, bounce: 0.7 }
floor = { pos: { 0, 250 }, size: { 400, 40 } }
simulate ball
fixed floor

draw [
  circle at ball.pos radius ball.radius fill tomato
  rect at floor.pos size floor.size fill 120
]
```

`simulate ball` gives the circle to the physics. Every frame the physics moves the ball's own `pos` and `vel`, and your sketch just draws where the ball is now. `fixed floor` gives the physics a shape that is in the way and is never pushed. A shape with `pos` and `radius` is a circle, with `pos` and `size` a rectangle (turned by `angle`, about its middle), and with `from` and `to` a wall, a line that only `fixed` takes.

Units are the ones you draw in: pixels, degrees turning clockwise, and a second is a second. Things fall as if 50 pixels were a metre, so a ball fell from the top of a 400 pixel window lands in about three quarters of a second.

## How a shape feels

Three fields on a record say how it behaves, and all of them are optional:

| Field | What it does | Usual |
|---|---|---|
| `bounce` | how much of its speed a ball keeps when it hits (0 to 1) | 0 |
| `friction` | how much it grips what it slides along | 0.6 |
| `density` | how heavy it is for its size | 1 |

A record may also have `vel` (the speed in pixels a second), `angle` and `spin` (degrees, and degrees a second): the physics reads them to start and writes them back as the shape moves. A record that has none of them is moved all the same.

## Gravity and kicks

```roci
gravity { 0, 400 }
```

sets the pull in pixels a second each second, `{ 0, 400 }` being what a sketch has until it says otherwise. `gravity { 0, 0 }` is space, and `gravity { 300, 0 }` pulls to the right.

`kick ball { 0, -300 }` adds a speed to a shape, however heavy it is, so a kick throws a pebble and a boulder alike:

```roci picture
ball = { pos: { 200, 260 }, radius: 14, bounce: 0.6 }
floor = { pos: { 0, 280 }, size: { 400, 20 } }
simulate ball
fixed floor
on mouse down [ kick ball { 0, -300 } ]

draw [
  circle at ball.pos radius ball.radius fill gold
  rect at floor.pos size floor.size fill 120
]
```

## Changing a shape while it is simulated

What your sketch writes to a shape between frames, the physics takes in before the next step. Set `ball.vel` to throw it, `ball.pos` to put it somewhere, and the physics carries on from there. A shape you make `fixed` is the way to build something the player moves: it stays put until you change its `pos` or `angle`, then it moves there in that frame and pushes whatever is in its way:

```roci picture
ball = { pos: { 200, 40 }, radius: 12, bounce: 0.8 }
paddle = { pos: { 160, 250 }, size: { 80, 12 } }
simulate ball
fixed paddle

draw [
  paddle.pos = { clamp (mouse.x - 40) 0 320, 250 }
  circle at ball.pos radius ball.radius fill tomato
  rect at paddle.pos size paddle.size fill gold
]
```

## Many shapes

A shape has to be the same record frame after frame, because the physics moves its fields a little each frame. A record you make inside `draw` or `on mouse down` is made again each time, so the physics refuses it and says so. To give the physics shapes the sketch makes as it runs, put them in a list: what you `add` in a frame is copied into the list, and the list's own copy is the one to simulate.

```roci
balls = []

learn drop x [
  ball = { pos: { x, 20 }, radius: 9, bounce: 0.5 }
  add ball to balls
  simulate (item (count balls) of balls)
]

on mouse down [ drop mouse.x ]

draw [
  for each b in balls [ circle at b.pos radius b.radius ]
]
```

Taking a shape out of the list does not take it out of the physics, so say `no simulate b` first, as `examples/pachinko` does for balls that have fallen out of the bottom. The physics holds up to 20,000 shapes.

## From C

The same words are C functions (`roci_simulate_circle`, `roci_fixed_wall`, `roci_gravity`, `roci_kick`), and a body is a number: `roci_body_pos(ball)` says where it is now. See [rocinante from C](../40-rocinante-from-c/).

## What is not there yet

Polygons and shapes in space are not simulated. Joints (hinges, ropes, springs), sensors and motors are coming.
