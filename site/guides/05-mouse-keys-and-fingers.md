---
title: "Mouse, keys and fingers"
summary: "Reading the mouse and the keyboard, waiting for something to happen, the wheel, touch, gamepads and joysticks, and actions that any of them can do."
weight: 5
---

A sketch can ask how things are now, in `draw`, or wait for something to happen, with `on`.

## Asking

`mouse` is where the mouse is, `pmouse` where it was a frame ago, and `pressed` whether a button is down:

```roci picture
strokes = []
draw [
  if pressed [ add { from: pmouse, to: mouse } to strokes ]
  for each s in strokes [ line from s.from to s.to stroke tomato thickness 4 ]
]
```

This one draws while the button is held. Every frame starts empty, so a drawing that stays is kept in a list: a piece of line for every frame the button is down, from where the mouse was to where it is.

`held` asks about a key, by its name (`"a"` to `"z"`, `"0"` to `"9"`, `"space"`, `"enter"`, `"left"`, `"right"`, `"up"`, `"down"`, `"shift"`, …), or about a mouse button with `"mouse left"`, `"mouse middle"` and `"mouse right"`:

```roci picture
x = 200
draw [
  background 240
  if held "left" [ x = x - 4 ]
  if held "right" [ x = x + 4 ]
  circle at x 150 radius 30 fill gold
]
```

`wheel` is how far the mouse wheel turned since the last frame: `wheel.y` up and down, `wheel.x` sideways.

```roci picture
size = 40
draw [
  background 240
  size = clamp (size + wheel.y * 5) 5 140
  circle at 200 150 radius size fill gold
]
```

## Waiting for something

`on` runs a block when something happens:

```roci picture
dots = []
on mouse down [ add mouse to dots ]
on key "c" [ dots = [] ]
draw [
  background 30
  for each d in dots [ circle at d radius 10 fill gold ]
]
```

`on mouse down` and `on mouse up` can name a button: `left`, `middle`, `right`, or the side buttons `back` and `forward`. Without one, any button counts.

```roci
on mouse down right [ print "right" ]
on mouse down back [ print "back" ]
```

Other things to wait for are `on resize`, `on move` and `on focus`, for the window. `key` holds the name of the key pressed last.

## Fingers

On a touch screen, `on touch down` and `on touch up` run when a finger goes down or comes up, and inside them `finger` is that finger, a record with `pos` (where it is), `start` (where it went down), `id` (a number it keeps while it is down) and `pressure`. `touches` is every finger down now:

```roci picture
draw [
  background 30
  for each f in touches [
    line from f.start to f.pos stroke white
    circle at f.pos radius 40 fill skyblue
  ]
]
```

A finger also moves `mouse` and runs `on mouse down left`, and on a computer the left mouse button counts as one finger, so a sketch for a touch screen can be tried with a mouse.

## Gamepads and joysticks

`gamepad` is the first gamepad that is plugged in, and `gamepads` is every one of them, the first first. A pad plugged in or out while the sketch runs is found at once, and with none plugged in `gamepad` is a pad at rest whose `connected` is false, so a sketch needs no check before it reads one.

```roci picture
pos = { 200, 150 }
draw [
  background 20
  pos = pos + gamepad.leftstick * 4
  fill white
  if gamepad.bottom [ fill gold ]
  circle at pos radius (20 + gamepad.righttrigger * 30)
  fill white
  if not gamepad.connected [ text "plug in a gamepad" at 20 20 ]
]
```

The buttons are named by where they are on the pad, not by the letter printed on them, because the same place says A on one pad and a cross on another: `bottom`, `right`, `left` and `top` are the four on the right hand, `leftshoulder` and `rightshoulder` the ones on top, `start`, `back` and `home` the ones in the middle, and `leftstickpress` and `rightstickpress` what pressing a stick in does. Each is true while it is held. The two sticks and the `dpad` are vectors, each of `x` and `y` from -1 to 1, with up negative as on the screen, so `pos + gamepad.leftstick * 4` moves a shape the way the stick leans. A stick at rest is exactly 0. `lefttrigger` and `righttrigger` go from 0 to 1, and `extra` is a list of the other buttons a pad may have (paddles, the touchpad press).

Most pads are known by name. A device that is not a gamepad (a flight stick, a wheel, an arcade panel) is in `joysticks` instead, each with its `name`, `axes`, a list of numbers from -1 to 1, and `buttons`, a list of true and false, with four more after the real ones for each hat on it: up, right, down and left.

```roci
for each stick in joysticks [
  print stick.name
  print (item 1 of stick.axes)
]
```

`rumble` shakes a gamepad: `rumble 80 for 0.5` is 80 out of 100 for half a second, and `player 2` after it shakes the second pad instead of the first. It does nothing, and says nothing, for a pad that cannot shake or when there is no pad.

```roci
on key "space" [ rumble 80 for 0.4 ]
on key "2" [ rumble 80 for 0.4 player 2 ]
```

What shakes depends on the pad and on the system. On a Mac the PlayStation 4 and 5 pads shake, the Logitech Dual Action has no motors, and the Xbox Series X pad did not shake when this was tried (it is not known yet whether it does on the other systems).

## Actions

A game that asks `held "space"` works with a keyboard and no other way. `bind` names what the player does and says which inputs do it, so the rest of the sketch asks only for the name:

```roci picture
bind "jump" to "key space"
bind "jump" to "pad bottom"
y = 200

on press "jump" [ y = 80 ]

draw [
  background 20
  y = clamp (y + 4) 0 200
  fill white
  if held "jump" [ fill gold ]
  circle at 200 y radius 20
]
```

An input is text: `"key space"` (a key, by the names `on key` uses), `"mouse left"`, `"pad bottom"` (any button, trigger, stick or the d-pad of a gamepad, on whichever pad has it, and `"pad 2 bottom"` only on the second), `"keys w a s d"` (four keys that make a vector, in the order up, left, down, right) and `"joystick 1 button 3"` or `"joystick 1 axis 2"` for a device that is not a gamepad. An action can have as many inputs as you like, and `held` says whether any of them is held. A trigger counts as held when it is more than half way, and so does a stick that is more than half way out.

`on press` runs once each time an action goes down, whichever input did it, and `on release` once when the last input that held it comes up, so pressing the key while the pad's button is still held is not a second press. `direction` is where an action points, a vector with x and y from -1 to 1 and up negative: the sticks, the d-pad, the four-key inputs and the axes bound to it, added together and kept to a length of 1, so a diagonal is no faster than a straight line:

```roci picture
bind "move" to "keys w a s d"
bind "move" to "pad leftstick"
bind "move" to "pad dpad"
pos = { 200, 150 }

draw [
  background 20
  pos = pos + direction "move" * 4
  fill white
  circle at pos radius 20
]
```

A name `held` is given is an action when something was bound to it, and otherwise a key, as before. An input that is not one (`"pad bottm"`) is said once with the nearest names, and the sketch goes on without it. `examples/actions` is a ship that moves and fires with all of this.

## Letting the player choose

Players have their own keyboards and pads, so a game can let them choose. `controls` in a `ui` block lists every action with a button for each input that does it:

```roci
bind "jump" to "key space"
bind "jump" to "pad bottom"
bind "move" to "keys w a s d"

ui [ panel "controls" [ controls ] ]
```

A player presses the button of an input, and the next key, gamepad button, trigger or stick they use takes its place (an input of four keys asks for four, one after the other). The `+` button adds another way to do the action, Backspace while a button is waiting takes that input away, and Escape gives up. While a button is waiting, what the player presses only chooses: it does not do the action. `reset controls` gives back the inputs your `bind` lines made.

What a player chooses is kept in `ui.toml`, next to the values of the other widgets, and wins over your `bind` lines the next time the sketch runs; `forget ui` puts the sketch's own inputs back. The sketch itself changes nothing: it still asks `held "jump"`, and works with whatever the player chose.
