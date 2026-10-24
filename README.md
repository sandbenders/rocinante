# rocinante

> _Y así, después de muchos nombres que formó, borró y quitó, añadió, deshizo y tornó a hacer en su memoria e imaginación, al fin le vino a llamar Rocinante: nombre, a su parecer, alto, sonoro y significativo de lo que había sido cuando fue rocín, antes de lo que ahora era, que era antes y primero de todos los rocines del mundo._
>
> Miguel de Cervantes, _El ingenioso hidalgo don Quijote de la Mancha_, Part I, Chapter 1 (1605)[^expanse]

```
circle 100 100 50
```

That line is a complete rocinante sketch. Run it and a window opens with a circle in it.

rocinante is an open-source creative coding framework with its own small and easy to learn, language. It comes out of years of working with [Processing](https://processing.org/), [openFrameworks](https://openframeworks.cc/) and [Cinder](https://libcinder.org/), and it borrows the turtle from [Logo](https://el.media.mit.edu/logo-foundation/). The goal is to make coding FUN AGAIN, especially for creative coders. You write a line and get a picture, mistakes come with a plain explanation, and when you save the file the running sketch updates.

Read [MANIFESTO.md](MANIFESTO.md) for why it exists.

## Status

Early design. Nothing runs yet. The project is in Phase 0: setting up the repository and testing the riskiest assumptions on every platform. The design and the plan live in [CLAUDE.md](CLAUDE.md) and [docs/design.md](docs/design.md), which are kept up to date as decisions are made.

## What it will look like

```
particles = []
repeat 200 [ add { pos: { random width, 0 }, vel: { 0, random 3 } } to particles ]

learn step p [ p.pos = p.pos + p.vel ]

draw [
  background 0
  for each p in particles [ step p  circle p.pos 3 ]
]
```

There are no semicolons and no setup function. Blocks use `[ ]`, `{ a, b }` is a vector, you teach new verbs with `learn`, and sliders, buttons and text boxes are ordinary words:

```
ui [ size = slider "size" 10 200 ]
draw [ circle 200 200 size ]
```

## How it works

The core is written in [Odin](https://odin-lang.org/) and draws through the GPU API of [SDL3](https://libsdl.org/), which uses [Vulkan](https://www.vulkan.org/), [Metal](https://developer.apple.com/metal/) or [Direct3D 12](https://learn.microsoft.com/en-us/windows/win32/direct3d12/directx-12-programming-guide) depending on the platform. There is no OpenGL anywhere.

You use one command, `roci`. `roci run` runs a sketch and reloads it whenever you save. It interprets the sketch, so it works without installing anything else. `roci package <target>` compiles the sketch to native code through Odin and turns it into an app. Packaging does need Odin plus your platform's usual build tools (Xcode, MSVC or clang), and `roci doctor` lists what's missing and how to install it.

The same sketch file runs on FreeBSD, Linux, macOS, Windows, iOS and Android.

## Roadmap

These are wanted, but not planned for the first stable release:

- **A rocinante shader dialect.** Shaders are written in HLSL for now. Later, a small shader language in rocinante's own style will compile to HLSL.
- **A web target**, so sketches can be shared in a browser.
- **Live coding on phones and tablets**: an app that runs the interpreter on iOS and Android, so sketches can be written and changed on the device itself.
- **3D physics** (gravity, joints and stacking in 3D). Collision detection works in 2D and 3D, and physics simulation in 2D.
- **Training models** inside rocinante. For now, trained models run locally but are trained elsewhere.

## Contributing

Issues and pull requests are welcome here on GitHub.

Day-to-day development happens in a self-hosted GitLab, and this repository is a mirror updated about twice a week. When a pull request is accepted, it is merged there and arrives here with the next update, so it may show as closed rather than merged. Your commits keep your name as author.

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

rocinante is designed and built by Fabrizio Poltronieri (sandbenders) [fabrizio@fabriziopoltronieri.com], with help from Claude, Anthropic's AI assistant.

[^expanse]: Four centuries later the name went to a ship. In _The Expanse_, the novel series by James S. A. Corey (the pen name of Daniel Abraham and Ty Franck) that began with _Leviathan Wakes_ in 2011, the Rocinante starts out as the _Tachi_, a Martian navy gunship. The survivors of the ice freighter _Canterbury_ take it over and rename it Rocinante, and it carries them through all nine novels and the television series (Syfy from 2015, then Amazon Prime Video). It is a small ship that keeps flying when it has no business doing so.
