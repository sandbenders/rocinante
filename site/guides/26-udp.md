---
title: "Talking over UDP"
summary: "Send and hear datagrams with udp send and on udp, so a sketch can talk to another program, another computer or another copy of itself."
weight: 26
---

UDP is the plainest way for programs on a network to talk: one program sends a small packet, called a datagram, to a computer and a port, and whoever listens on that port gets it. Nothing sets up a connection first, and nothing is promised: a datagram can be lost, and nothing answers. That suits a game that sends where a player is sixty times a second, a sensor, or two sketches that show each other something.

## Hearing

`on udp` names the port to listen on, and its block runs for each datagram that arrives there. `packet` is the datagram:

```roci
news = []
on udp 9200 [
  add (packet.text + " from " + packet.from) to news
  if (count news) > 6 [ remove (item 1 of news) from news ]
]

draw [
  background 24
  fill white
  for i from 1 to count news [
    text (item i of news) at 20 (30 * i) size 16
  ]
]
```

`packet` has four fields:

| field | what it is |
|---|---|
| `text` | what the datagram carries, read as text |
| `bytes` | the same, as a list of numbers from 0 to 255 |
| `from` | who sent it, such as `"192.168.0.7"` |
| `port` | the port it was sent from |

The sketch starts listening on the port when it starts. One port can have several blocks, and a sketch can listen on up to sixteen ports. Only one program can listen on a port at a time: when another program has it, the sketch says so and goes on without listening.

## Sending

`udp send` sends a text or a list of bytes. `port` is needed, and `to` is a computer's name or number and starts as this computer:

```roci
on mouse down [
  udp send ("here " + (floor mouse.x) + " " + (floor mouse.y)) to "localhost" port 9200
]

udp send [ 1 2 255 ] to "192.168.0.7" port 9300
```

A datagram holds up to 65507 bytes. Nothing waits: `udp send` goes on at once, and a computer that is not there is not an error, because UDP never asks. A name that cannot be found at all is said.

## With C and Odin

C programs have `roci_udp_send`, `roci_udp_listen` and, for what arrives, `roci_on` with `"udp"` and the port as its argument, whose event holds the datagram.

## Testing

A headless run (`roci run --frames`, `roci test`) listens to nothing and sends nothing; the Odin API's `feed_udp` gives a sketch datagrams as the network would, and `udp_sent_messages` says what it sent.
