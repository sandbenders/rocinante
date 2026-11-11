---
title: "Widgets"
summary: "Buttons, sliders, text boxes and more in a ui block: what each gives, laying them out, placing them, the values they keep, hiding them and the keyboard."
weight: 18
---

Widgets are the buttons, sliders and boxes a person changes while the sketch runs. They live in a `ui` block, and each one gives back what the person did with it, so the sketch reads a slider as it reads any other number:

```roci picture
size = 60

ui [
  size = slider "size" 10 150 start 60
]

draw [
  background 30
  fill orange
  circle at 500 300 radius size
]
```

There is nothing else to set up: no callback, no widget to keep, no value to copy back. The `ui` block runs every frame after `draw`, and the widgets stack in a panel at the top left of the window. They are always drawn on top of the canvas, at the same size whatever the drawing does with `move` or `grow`.

A widget is known by its text, so the text is what a person reads and also how rocinante tells the widgets apart. Two widgets with the same text in one block would share one value, which is said once, and both still work:

```message
── Two widgets are both called `go` ──────────────────── sketch.roci:3:6

3 │   if button "go" [ print 2 ]
  │      ^^^^^^^^^^^

A widget is known by its text, so two with the same text would share one value and one place on the screen. Give one of them another text, and the sketch carries on with both.

Give each its own text:  ui [ a = slider "width" 10 200  b = slider "depth" 10 200 ]
```

## What each one gives

Numbers come from a `slider`, a `number` box (type a number, or press its minus and plus) and a `knob` (drag it up or right). Each takes the lowest and highest value, and `start` says where it begins; without `start` it begins at the lowest:

```roci picture
ui [
  a = slider "slider" 0 100 start 30
  b = number "number" 1 20 start 5
  c = knob "knob" 0 10 start 3
]
```

A `toggle` gives true or false, a `textbox` the text in it (`lines 4` makes it taller), and a `colorpicker` a color, which opens a picker when it is clicked:

```roci picture
ui [
  trails = toggle "trails" start true
  name = textbox "name" start "rocinante"
  tone = colorpicker "tone" start teal
]
```

Choices come from a list of texts, and each gives the text that is chosen: `dropdown` opens when clicked, `choice` shows radio buttons, and `list` a box of lines to pick from. `start` names the item to begin with; without it, the first:

```roci picture
ui [
  shape = dropdown "shape" [ "circle" "square" "star" ]
  mode = choice "mode" [ "draw" "erase" ] start "erase"
  word = list "word" [ "one" "two" "three" ]
]
```

Two numbers at once come from a `range`, two handles on one bar that never cross (a vector: `span.x` is the low end and `span.y` the high one), and from an `xypad`, a square that gives where it was pressed, from 0 to 1 across and down, starting in the middle:

```roci picture
span = { 20, 80 }
spot = { 0.5, 0.5 }

ui [
  span = range "sizes" 0 100 start 20 80
  spot = xypad "place"
]

draw [
  fill teal
  circle at (300 + spot.x * 400) (spot.y * 600) radius (span.y - span.x)
]
```

A `button` is true on the frame it is clicked, so it sits in an `if`. An `image button` shows a picture, with its text for the people who cannot see it. `label` shows words, `progress` a bar for a number from 0 to 1, `separator` a line between widgets, and `tip` words that show when the mouse rests on the widget before it:

```roci picture
clicks = 0
badge = load "sprite.png"

ui [
  if button "count" [ clicks = clicks + 1 ]
  tip "adds one"
  if image button badge "stamp" size 48 48 [ clicks = clicks + 10 ]
  separator
  label ("clicks: " + clicks)
  progress ((clicks % 100) / 100)
]
```

## Laying them out

Widgets stack from the top down. `row` puts the widgets of its block side by side, and `column` stacks them again inside a row. `panel` is a group with a header that folds it up, and `tabs` holds `tab`s, of which one shows at a time. A widget inside a panel or a tab is known by that path and its text, so a `size` in two tabs is two widgets with values of their own:

```roci picture
ui [
  panel "dot" [
    row [
      if button "play" [ print "play" ]
      if button "stop" [ print "stop" ]
    ]
    dot = slider "size" 10 120 start 50
  ]
  tabs [
    tab "shape" [ shape = slider "size" 1 9 start 3 ]
    tab "color" [ label "orange or teal" ]
  ]
]
```

`menu` makes a bar along the top of the window, and its `item`s are true on the frame one is chosen:

```roci
ui [
  menu "file" [
    if item "save" [ save "shot.png" ]
    if item "quit" [ quit ]
  ]
]
```

A folded panel, a tab that is not showing and a closed menu do not run their block, so the widgets inside keep the values they had.

## Placing them

`at` puts a widget somewhere else in the window, and `width` says how wide it is. A group takes them after its block:

```roci picture
dot = 40
ring = true

ui [
  dot = slider "size" 10 100 at 500 40 width 200 start 40
  panel "more" [
    ring = toggle "ring" start true
  ] at 40 400 width 160
]

draw [
  if ring [ stroke white  thickness 4 ]
  fill tomato
  circle at 400 260 radius dot
]
```

A `ui` block can also sit inside `draw`, and then `at` is a place on the canvas, moved and turned like the drawing around it. A slider in a loop that draws a dot follows its own dot, and each one made in the loop is a widget of its own:

```roci
dots = [
  { pos: { 100, 100 }, size: 20 }
  { pos: { 300, 200 }, size: 20 }
]

draw [
  for each d in dots [
    circle at d.pos radius d.size
    ui [ d.size = slider "size" 10 40 at (d.pos + { 28, 22 }) width 90 start 20 ]
  ]
]
```

## Values are kept

A widget holds its value from frame to frame, and the sketch cannot set it: a slider is where the hand left it. Saving the sketch reloads it and keeps every widget's value, and so does restarting it.

`roci run` of a sketch folder also remembers the values in `ui.toml`, beside `sketch.roci`, so a sketch opens the next day as it was left. The file is written when the sketch ends and after a second in which nothing moved, never on every move of a slider; commit it, and the tuned values travel with the sketch. `start` is only for a widget the file does not know.

`forget ui` puts every widget of the window back to its start, which is how a reset button is made:

```roci
ui [
  dot = slider "dot" 10 120 start 40
  if button "reset" [ forget ui ]
]

draw [ circle at 300 160 radius dot ]
```

## Hiding them

The backtick key (`` ` ``, the key left of 1) hides the widgets and shows them again, and so does a tap of three fingers on a touch screen. The sketch keeps reading their values while they are hidden. `ui key` gives the job to another key, and `ui hide` and `ui show` do it from the sketch, for a performance that starts clean:

```roci
ui key "f1"
ui hide
ui [ label "press f1" ]
```

## Keyboard and screen readers

Every widget works without a mouse. Tab moves to the next widget and Shift+Tab back, Space presses a button or a check box, and the arrow keys move the value of a slider, knob, range, pad or number box while it has the focus (right and up add). A box of text takes typing, in any script the computer's input method can write.

The widgets are also told to the computer's screen reader: VoiceOver on a Mac, and Orca on Linux, FreeBSD and OpenBSD. It reads each widget's text, its value and the `tip` for it, says a change as it happens, and can change a value itself, as a hand would.

## A window of controls

A second window with only a `ui` block is a control surface: its values are names like any other, so the other window reads them straight away, with no message in between:

```roci
main = window size 600 400 title "picture"
panel_window = window size 260 200 title "controls"
size = 60
tone = orange

ui panel_window [
  size = slider "size" 10 150 start 60
  tone = colorpicker "tone" start orange
]

draw main [
  background 30
  fill tone
  circle at 300 200 radius size
]
```
