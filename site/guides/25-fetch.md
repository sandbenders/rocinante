---
title: "Fetching from the web"
summary: "Get a text or a picture from a web address with fetch, send a text with post, and let the sketch keep drawing while the answer is on its way."
weight: 25
---

A web address takes a moment to answer, and a sketch that waited for it would stop drawing. `fetch` asks and goes on. Its block runs when the answer has come, and `reply` is the answer inside it:

```roci
message = "asking..."

fetch "https://rocinante-lang.org/" [
  if reply.ok [
    message = "the page has " + (count reply.text) + " letters"
  ] else [
    message = "nothing came: " + reply.problem
  ]
]

draw [
  background 245
  fill 40
  text message at 20 60 size 18
]
```

`reply` has five fields:

| field | what it is |
|---|---|
| `status` | the number the server answered with: 200 for a good answer, 404 for a page that is not there. 0 when nothing came at all |
| `ok` | true for a status from 200 to 299 |
| `text` | what came, as text |
| `problem` | when nothing came, why, in words; otherwise empty |
| `picture` | what came as a picture, for `fetch picture` |

A fetch is a failure, with `status` 0 and a `problem`, when the computer is offline, the address does not exist, the answer is over 64 megabytes, or thirty seconds pass. Only `http` and `https` addresses are fetched, and the secure ones are checked against the computer's own list of trusted sites.

## Pictures

`fetch picture` reads what comes as a picture: a PNG, JPEG, BMP, TGA or QOI file. Start with a stand-in so there is something to draw until it arrives:

```roci
logo = picture from [ #cccccc ] size 1 1

fetch picture "https://rocinante-lang.org/logo.png" [
  if reply.ok [ logo = reply.picture ]
]

draw [
  background 245
  image logo at 20 20 size 120 120
]
```

## Sending a text

`post` sends a text to an address and runs its block with the answer, as `fetch` does. A `header` after the block says what the text is, or who is sending it:

```roci
post "https://example.org/scores" "ada 120" [
  print reply.status
] header "Content-Type: text/plain"
```

## What to know

- A sketch has at most eight fetches open at once, so one that fetches every frame is given eight at a time.
- Nothing is cached: the same address fetched twice is asked twice.
- A headless run (`roci run --frames`, `roci test`) fetches nothing, so a sketch draws the same frames each time. Its blocks do not run there.
- Reading JSON from `reply.text` into a record is not built yet; `reply.text` is the text as it came.
