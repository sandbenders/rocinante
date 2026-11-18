---
title: "Web sockets"
summary: "Open a web socket with websocket connect and send and hear messages, for chats, live feeds and anything a web server pushes."
weight: 28
---

A web socket is a connection to a web server that stays open and carries messages both ways, so the server can push something the moment it happens instead of waiting to be asked. Chats, live scores, game servers and sensor feeds use them. Its address begins with `ws://`, or with `wss://` for the secure kind, which is what most servers want and is checked against the system's trusted certificates.

## Opening one

`websocket connect` names the connection with a label and says where to:

```roci
status = "connecting..."
websocket connect "feed" to "wss://echo.websocket.org/"

on websocket open "feed" [ status = "open" ]
on websocket close "feed" [ status = "closed: " + received.text ]

draw [
  background 24
  fill white
  text status at 20 40 size 20
]
```

Nothing waits for the connection: the sketch goes on drawing, `on websocket open` runs when it is open, and `on websocket close` runs when it could not be opened, or when it closes later, with the reason in `received.text`. Saying `websocket connect` again with the same label to the same address changes nothing (which is what saving the file does), and to another address replaces the connection.

## Hearing and sending

`on websocket "feed"` runs for each message that arrives, and `received` is what happened, as it is for `tcp`:

| field | what it is |
|---|---|
| `text` | the message (a binary one comes as text too); for `on websocket close`, why it closed |
| `from` | the server, such as `"echo.websocket.org"` |

```roci
news = []
websocket connect "feed" to "wss://echo.websocket.org/"

on websocket "feed" [
  add received.text to news
  if (count news) > 6 [ remove (item 1 of news) from news ]
]
on mouse down [ websocket send "feed" ("click at " + (floor mouse.x) + "," + (floor mouse.y)) ]

draw [
  background 24
  fill white
  for i from 1 to count news [
    text (item i of news) at 20 (30 * i) size 16
  ]
]
```

`websocket send` sends a text message; a list of numbers from 0 to 255 goes as a binary one. `websocket close "feed"` closes the connection politely, and `on websocket close` runs when it is over. A sketch has at most eight web sockets open at once. When a mistake is made (an unknown label, an address that does not begin with `ws://` or `wss://`) it is said and the sketch goes on.

Only the client side is here: a sketch can open web sockets, not wait for others to open one to it (`tcp listen` is the way to wait for connections).

## With C and Odin

C programs have `roci_websocket_connect`, `roci_websocket_send` and `roci_websocket_close`, and `roci_on` with `"websocket open"`, `"websocket"` and `"websocket close"` and the label as its argument.

## Testing

A headless run opens nothing. The Odin API's `feed_websocket` gives a sketch what would have happened, and `websocket_sent_messages` and `websocket_asked_for` say what it sent and asked for.
