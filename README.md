# rocinante

```
circle 100 100 50
```

That line is a complete rocinante sketch. Run it and a window opens with a circle in it.

rocinante is an open-source creative coding framework with its own small language, in the tradition of Processing, openFrameworks and Cinder, and with Logo's turtle built in. It aims to make coding feel like play again: one line makes a picture, errors explain themselves, and saving the file updates the sketch while it runs.

Read [MANIFESTO.md](MANIFESTO.md) for why it exists.

## Status

Early design. Nothing runs yet. The project is in Phase 0: setting up the repository and testing the riskiest assumptions on every platform. The design and the plan live in [CLAUDE.md](CLAUDE.md), which is kept up to date as decisions are made.

## What it will look like

```
particles = []
repeat 200 [ add { pos: (vec (random width) 0), vel: (vec 0 (random 3)) } to particles ]

learn step p [ p.pos = p.pos + p.vel ]

draw [
  background 0
  for each p in particles [ step p  circle p.pos 3 ]
]
```

No semicolons, no braces, no setup function. Blocks use `[ ]`, new verbs are taught with `learn`, and sliders, buttons and text boxes are words like any other:

```
ui [ size = slider "size" 10 200 ]
draw [ circle 200 200 size ]
```

## How it works

- **The core** is written in [Odin](https://odin-lang.org/) on SDL3 and its GPU API (Vulkan, Metal, Direct3D 12). No OpenGL.
- **`roci`** is the one command you use: `roci run` to work on a sketch live, `roci package <target>` to turn it into an app.
- **While you work**, sketches are interpreted, so `roci run` needs nothing else installed.
- **When you ship**, sketches are compiled to native code through Odin. Packaging needs Odin and your platform's usual tools (Xcode, MSVC or clang), and `roci doctor` tells you exactly what's missing.
- **Platforms:** FreeBSD, Linux, macOS, Windows, iOS and Android, from the same sketch file.

## Contributing

Issues and pull requests are welcome here on GitHub.

Day-to-day development happens in a self-hosted GitLab, and this repository is a mirror updated about twice a week. When a pull request is accepted, it is merged there and arrives here with the next update, so it may show as closed rather than merged. Your commits and your authorship are kept.

The history is linear: branches are rebased onto `main` and merged fast-forward. Keep commits small, one idea each, with a short imperative message prefixed by the area it touches, for example `gfx: batch circles with instancing`. The name is always written in lowercase, rocinante, including at the start of a sentence.

After cloning, turn on the project's git hooks once:

```
git config core.hooksPath tools/hooks
```

Build instructions will appear here once there is something to build.

## Versions

Releases use calendar versioning, `YYYY.MINOR.MICRO`: `2026.1.0` is the first release of 2026 and `2026.1.1` its first fix. Releases before the first stable one are marked as previews.

## Licence

[Zero-Clause BSD](LICENSE) (0BSD). Use it for anything, with or without credit.

## Credits

rocinante is designed and built by Fabrizio (sandbenders), with help from Claude, Anthropic's AI assistant.
