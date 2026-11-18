---
title: "Talking over TCP"
summary: "Make and accept connections with tcp connect and tcp listen, and send and hear lines of text, to chat with another program or a server."
weight: 27
---

TCP is a connection between two programs: once it is made, what one sends the other receives, in order, and each knows when the other has gone. UDP (the guide before this) sends single datagrams that may be lost; TCP is for talking, for chat, for a score server, for a sensor that sends a line a second. What goes over a connection here is **lines of text**: a message is some text ended by a newline.

## Making a connection

`tcp connect` names the connection with a label and says where to:

```roci
status = "connecting..."
tcp connect "chat" to "localhost" port 9400

on tcp open "chat" [ status = "connected" ]
on tcp close "chat" [ status = "closed: " + received.text ]

draw [
  background 24
  fill white
  text status at 20 40 size 20
]
```

Nothing waits for the connection: the sketch goes on drawing, `on tcp open` runs when it is made, and `on tcp close` runs when it could not be made, or when it ends later, with the reason in `received.text`. The label names the connection from then on. Saying `tcp connect` again with the same label to the same place changes nothing (which is what saving the file does), and to another place replaces the connection.

## Hearing and sending

`on tcp "chat"` runs for each line that arrives, and `received` is what happened:

| field | what it is |
|---|---|
| `text` | the line that arrived, without its newline (for `on tcp close`, why the connection ended) |
| `from` | who is at the other end, such as `"192.168.0.7"` |
| `client` | for a server, which client it was (1, 2, ...); 1 for a connection you made |

```roci
news = []
tcp connect "chat" to "localhost" port 9400

on tcp "chat" [
  add received.text to news
  if (count news) > 6 [ remove (item 1 of news) from news ]
]
on mouse down [ tcp send "chat" ("click at " + (floor mouse.x) + "," + (floor mouse.y)) ]

draw [
  background 24
  fill white
  for i from 1 to count news [
    text (item i of news) at 20 (30 * i) size 16
  ]
]
```

`tcp send` sends a text as a line, with the newline put after it. A list of numbers from 0 to 255 goes as exactly those bytes, for the programs that want them. `tcp close "chat"` ends the connection.

## Waiting for others

`tcp listen` makes the sketch a server. Each program that connects runs `on tcp open`, with `received.client` its number, and each line it sends runs `on tcp`. Answers go to everyone, or to one with `to`:

```roci
tcp listen "server" port 9400
clients = 0

on tcp open "server" [ clients = clients + 1 ]
on tcp close "server" [ clients = clients - 1 ]
on tcp "server" [
  tcp send "server" (received.text) to received.client
]

draw [
  background 24
  fill white
  text ("clients: " + clients) at 20 40 size 20
]
```

Only one program can listen on a port. A server keeps up to sixteen clients, and a sketch has at most eight connections and listeners open at once. When a mistake is made (an unknown label, a port that is not a number from 1 to 65535, a computer that cannot be found) it is said and the sketch goes on.

## With C and Odin

C programs have `roci_tcp_connect`, `roci_tcp_listen`, `roci_tcp_send` and `roci_tcp_close`, and `roci_on` with `"tcp open"`, `"tcp"` and `"tcp close"` and the label as its argument, whose event holds what happened.

## Testing

A headless run listens to nothing and connects to nothing. The Odin API's `feed_tcp` gives a sketch what would have happened, and `tcp_sent_messages` and `tcp_asked_for` say what it sent and asked for.
