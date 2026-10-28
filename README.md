# rocinante

> _Y así, después de muchos nombres que formó, borró y quitó, añadió, deshizo y tornó a hacer en su memoria e imaginación, al fin le vino a llamar Rocinante: nombre, a su parecer, alto, sonoro y significativo de lo que había sido cuando fue rocín, antes de lo que ahora era, que era antes y primero de todos los rocines del mundo._
>
> Miguel de Cervantes, _El ingenioso hidalgo don Quijote de la Mancha_, Part I, Chapter 1 (1605)[^expanse]

```
circle at 100 100 radius 50
```

That line is a complete rocinante sketch. Run it and a window opens with a circle in it.

rocinante is an open-source creative coding framework with its own small and easy to learn, language. It comes out of years of working with [Processing](https://processing.org/), [openFrameworks](https://openframeworks.cc/) and [Cinder](https://libcinder.org/), and it borrows the turtle from [Logo](https://el.media.mit.edu/logo-foundation/). The goal is to make coding FUN AGAIN, especially for creative coders. You write a line and get a picture, mistakes come with a plain explanation, and when you save the file the running sketch updates.

Read [MANIFESTO.md](MANIFESTO.md) for why it exists.

## Status

Early. The language exists in pieces: `roci check` reads and checks a `.roci` sketch, and `roci run` runs one, but only the drawing, the verbs, lists and records, and taught verbs so far (it reacts to keys and the mouse, `every` and messages between windows, reloads when you save the file, and shows mistakes over the picture while the last good version keeps running; Ctrl+R or Cmd+R starts it again). Under it is the engine, which also has an Odin API (and a C API): windows on a GPU device, 2D shapes with styles, gradients, transforms, colour, random numbers and noise, mouse and keyboard, several windows that send each other messages, and a small text path for debugging. It draws on macOS (Metal), Linux and FreeBSD (Vulkan), Windows (Direct3D 12), and on an iPhone and an Android phone, and 100,000 circles a frame hold about 60 frames a second on the computers tried so far.

Phase 0 (2026-10-27) tested the riskiest parts with four spikes: a window and GPU device on every desktop system, a shader-drawn circle on a real iPhone and a real Android phone, generating Odin from a typed IR, and Dear ImGui with a screen reader. Phase 1, the window and the 2D core, is built and measured on all of them. Phase 2, the language itself, has its parser, checker and interpreter; `roci fmt`, sketch folders and the rest of the language come next. The design and the plan live in [CLAUDE.md](CLAUDE.md) and [docs/design.md](docs/design.md), which are kept up to date as decisions are made.

## What it will look like

```
particles = []
repeat 200 [ add { pos: { random width, 0 }, vel: { 0, random 3 } } to particles ]

learn step p [ p.pos = p.pos + p.vel ]

draw [
  background 0
  for each p in particles [ step p  circle at p.pos radius 3 ]
]
```

There are no semicolons and no setup function. Blocks use `[ ]`, `{ a, b }` is a vector, you teach new verbs with `learn`, and sliders, buttons and text boxes are ordinary words:

```
ui [ size = slider "size" 10 200 ]
draw [ circle at 200 200 radius size ]
```

## How it works

The core is written in [Odin](https://odin-lang.org/) and draws through the GPU API of [SDL3](https://libsdl.org/), which uses [Vulkan](https://www.vulkan.org/), [Metal](https://developer.apple.com/metal/) or [Direct3D 12](https://learn.microsoft.com/en-us/windows/win32/direct3d12/directx-12-programming-guide) depending on the platform. There is no OpenGL anywhere.

You use one command, `roci`. `roci run` runs a sketch and reloads it whenever you save. It interprets the sketch, so it works without installing anything else. `roci package <target>` compiles the sketch to native code through Odin and turns it into an app. Packaging fetches the right version of Odin for you and needs your platform's usual build tools (Xcode, MSVC or clang), and `roci doctor` lists what's missing and how to install it.

The same sketch file runs on FreeBSD, Linux, macOS, Windows, iOS and Android. You write, run and package sketches on a FreeBSD, Linux, macOS or Windows computer; iOS and Android are targets only, where the packaged app runs. Not every computer can package every target (an iOS app can only be built on a Mac), and `roci doctor` tells you which ones yours can.

## Roadmap

These are wanted, but not planned for the first stable release:

- **A rocinante shader dialect.** Shaders are written in HLSL for now. Later, a small shader language in rocinante's own style will compile to HLSL.
- **A web target**, so sketches can be shared in a browser.
- **More processors on the desktop.** The first stable release runs on x86-64 computers with FreeBSD, Linux or Windows, and on Macs with Apple silicon. Later: arm64 FreeBSD, Linux and Windows computers, and Intel Macs.
- **3D physics** (gravity, joints and stacking in 3D). Collision detection works in 2D and 3D, and physics simulation in 2D.
- **Training models** inside rocinante. For now, trained models run locally but are trained elsewhere.
- **Help for writing sketches with AI assistants**: a sketch-writing skill and an MCP server built on `roci`'s checker and headless run.
- **Editor tools in the source**: inline sliders and colour pickers that edit the number in your file, and a frame scrubber that steps backwards through a running sketch.
- **Turtle export** to plotter and embroidery formats.
- **Translated keywords and error messages.**

## Contributing

Issues and pull requests are welcome here on GitHub.

Day-to-day development happens in a self-hosted GitLab, and this repository is a mirror updated about twice a week. When a pull request is accepted, it is merged there and arrives here with the next update, so it may show as closed rather than merged. Your commits keep your name as author.

The history is linear: branches are rebased onto `main` and merged fast-forward. Keep commits small, one idea each, with a short imperative message prefixed by the area it touches, for example `gfx: batch circles with instancing`. The name is always written in lowercase, rocinante, including at the start of a sentence.

After cloning, turn on the project's git hooks once:

```
git config core.hooksPath tools/hooks
```

## Building

Install the Odin release named in `ODIN_VERSION`: `brew install odin` gives the right one on macOS at the time of writing, and the [official releases](https://github.com/odin-lang/Odin/releases) cover Linux, macOS and Windows. (An older Odin, `dev-2026-07` built against LLVM 23, failed to compile even a hello world, so check that `odin version` matches the file.) You also need SDL3, which the engine's tests link: `brew install sdl3` on macOS, `sdl3` from your package manager on Arch, `pkg install sdl3` on FreeBSD, and on Windows Odin ships `SDL3.lib` and you copy its `SDL3.dll` next to the programs (`cp "$(odin root)/vendor/sdl3/SDL3.dll" .`). Then, from the repository root:

```
odin run build -- ci          # what the pipelines run
odin run build -- ci --fast   # what the pre-push hook runs
odin run build -- licences    # dependency licence check
```

The full `ci` also draws the golden images on Mesa's software Vulkan driver (lavapipe) when it is installed, and says so when it is not.

## Trying the engine

The examples use the Odin API and open real windows:

```
odin run examples/circle              # the smallest sketch: one circle
odin run examples/garden              # the Phase 1 demo: a palette window and a garden
odin run examples/two_windows         # two windows that send each other messages
odin run examples/shapes              # every shape, a circle follows the mouse
odin run examples/benchmark -o:speed  # 100,000 circles a frame, with frame rate and timings
```

Add `-- 3` to any of the examples to close the window after three seconds. `examples/c/circle.c` is the same circle through the C API (`include/roci.h`, checked by `tools/abi-check.sh`).

The language is being built front first. `roci check` reads a sketch and reports every mistake in it, and `roci run` runs it (the examples are written in the language as `sketch.roci` files):

```
odin run cli -- check sketch.roci [--tree]
odin run cli -- man rect                               # how a verb is written (no word: every verb)
odin run cli -- fmt                                    # writes every .roci file here in the house style
odin run cli -- run examples/garden/sketch.roci        # opens the windows
odin run cli -- run sketch.roci --frames 60 --screenshot out.png   # headless, saves the last frame
```

## Versions

Releases use calendar versioning, `YYYY.MINOR.MICRO`: `2026.1.0` is the first release of 2026 and `2026.1.1` its first fix. Releases before the first stable one are marked as previews.

## Licence

[Zero-Clause BSD](LICENSE) (0BSD). Use it for anything, with or without credit.

## Credits

rocinante is designed and built by Fabrizio Poltronieri (sandbenders) [fabrizio@fabriziopoltronieri.com], with help from Claude, Anthropic's AI assistant.

[^expanse]: Four centuries later the name went to a ship. In _The Expanse_, the novel series by James S. A. Corey (the pen name of Daniel Abraham and Ty Franck) that began with _Leviathan Wakes_ in 2011, the Rocinante starts out as the _Tachi_, a Martian navy gunship. The survivors of the ice freighter _Canterbury_ take it over and rename it Rocinante, and it carries them through all nine novels and the television series (Syfy from 2015, then Amazon Prime Video). It is a small ship that keeps flying when it has no business doing so.
