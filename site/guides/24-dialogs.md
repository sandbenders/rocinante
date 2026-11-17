---
title: "Dialogs, the clipboard and opening things"
summary: "Let a player choose a file, a folder or a place to save, copy and paste text, and open a web address, without the sketch ever waiting."
weight: 24
---

Some things only the player can say: which picture to open, where to keep a result. `ask file` shows the computer's own dialog for it:

```roci
photo = load "ship.png"
path = "nothing chosen yet"

ui [
  if button "choose a picture" [
    ask file "png jpg" [
      photo = load chosen
      path = chosen
    ]
  ]
]
```

The sketch does not wait. The dialog opens, the sketch goes on drawing, and the block after it runs when the player has chosen, with `chosen` the whole path of their file. A player who closes the dialog without choosing runs nothing. The text names the kinds of file to show by their endings (`"png jpg"`), and may be left out to show everything.

Ask from a button or a key, not every frame: a sketch has a few dialogs open at most, and one asked while those are open is dropped.

## What a chosen path is for

`load` reads a chosen picture, `read` gives the text of any file, and `save` writes to a path:

```roci
notes = ""

ui [
  if button "open notes" [
    ask file "txt md" [ notes = read chosen ]
  ]
  if button "save notes" [
    ask save "notes.txt" [ save notes chosen ]
  ]
]
```

A sketch can read a file outside its own `assets` folder only when the player chose it in a dialog, so a downloaded sketch cannot look through someone's files. `read "notes.txt"` without a dialog reads a file of `assets`. `ask folder` gives a folder's path in the same way, for a sketch that works on a whole folder.

`ask save` takes the name the dialog starts with. Nothing is written until the block does it, so a player who changes their mind loses nothing.

## The clipboard

`copy to clipboard` puts text where the player can paste it in another program, and `clipboard` reads what they copied:

```roci
words = ""

ui [
  if button "copy a color" [ copy to clipboard "#ff8800" ]
  if button "paste" [ words = clipboard ]
]
```

`clipboard` is empty text when there is nothing copied, or when what is there is not text.

## Opening things

`open` hands a web address, an email address or a file to the program the computer keeps for it:

```roci
ui [
  if button "read more" [ open "https://rocinante-lang.org" ]
]
```

A text that is not an address is a file of the assets folder, or a path the player chose.

## In C

The same things are `roci_ask` and `roci_answer` (ask, then look each frame until there is an answer), `roci_clipboard`, `roci_set_clipboard` and `roci_open`. A sketch that is running with no window, as in a test, shows no dialog: its requests wait for an answer that never comes.
