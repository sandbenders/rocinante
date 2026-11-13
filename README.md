<h1 align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/logo/rocinante-wordmark-dark.svg">
    <img src="docs/logo/rocinante-wordmark.svg" alt="rocinante" width="360">
  </picture>
</h1>

> _Y así, después de muchos nombres que formó, borró y quitó, añadió, deshizo y tornó a hacer en su memoria e imaginación, al fin le vino a llamar Rocinante: nombre, a su parecer, alto, sonoro y significativo de lo que había sido cuando fue rocín, antes de lo que ahora era, que era antes y primero de todos los rocines del mundo._
>
> Miguel de Cervantes, _El ingenioso hidalgo don Quijote de la Mancha_, Part I, Chapter 1 (1605)[^expanse]

```
circle at 100 100 radius 50
```

That line is a complete rocinante sketch. Run it and a window opens with a circle in it.

rocinante is an open-source creative coding framework with its own easy to learn and powerful language. It comes out of years of working with [Processing](https://processing.org/), [openFrameworks](https://openframeworks.cc/) and [Cinder](https://libcinder.org/), and it borrows the turtle, ideas and also some syntax from [Logo](https://el.media.mit.edu/logo-foundation/). You write a line and get a picture, mistakes come with a plain explanation, and when you save the file the running sketch updates.

Read [MANIFESTO.md](MANIFESTO.md) for why it exists, and the [FAQ](https://rocinante-lang.org/faq/) for the questions people ask: why not Processing, Python or OpenGL, why Logo, where the objects are, and who is behind it.

## Status

Early, but you can write and run sketches today. The language exists and the `roci` command works:

- **`roci run`** runs a sketch (or a folder, through its `sketch.roci`). Save the file and the running sketch updates, keeping its values where it can; a mistake is shown over the picture while the last good version keeps running, and it recovers when you fix the file. Ctrl+R or Cmd+R starts it again from the first line, and Ctrl+Q or Cmd+Q quits.
- **`roci check`** reads a sketch and says what is wrong, in plain words with your own line fixed (`--errors json` gives the messages as data). **`roci fmt`** writes sketches in one house style. **`roci man rect`** shows how a verb is written. **`roci test`** runs the checks a sketch or library carries (`check "double" [ expect double 21 is 42 ]`) and compares the sketch's picture with one you stored (`roci test --accept`); both are optional.
- **`roci new`, `roci init` and `roci add`** make a sketch folder (with git, and Git LFS if you want it) and copy files into its `assets/`. **`roci get`** copies a library from a git address into `libs/`, and **`roci update`** fetches a newer copy and says what changed.
- **A sketch can be several files.** Every `.roci` file in a sketch folder is part of the same program: put verbs and constants in `palette.roci`, use them in `sketch.roci`, and messages name the right file. Save any of them and the sketch reloads (see `examples/starfield`). Libraries are folders in `libs/` brought in with `use "name"` (see `examples/constellation`), copied there from a git address by `roci get`.
- The language so far has drawing, style and color, gradients, transforms, random numbers and noise, lists and records, verbs you teach with `learn`, `if`, `repeat`, `for`, `while`, the list verbs (`keep`, `collect`, `sort`, `shuffle` and more), keys, the mouse and fingers (`on key`, `on mouse down right`, `on touch down`, `pressed`, `held "space"`, `wheel`, `touches`), `floor`, `round` and `ceil`, `atan`, `normalize` and `limit` (angles and vectors), `every`, tweens and easing, tables, the turtle (read as `turtle`, drawn with `show turtle`), 2D collision (`touching`, `contact`, `hits`, `inside`, `cast`, and `outline` for the solid part of a picture), `save` (the window as a PNG, or as an SVG or PDF drawing, or a frame sequence), `record` (a movie: an animated PNG, or a video through ffmpeg when it is installed), `blend` and `clip`, the pixels of a picture (`pixel`, `crop`, `resize`, `filter`, `mask`), pictures (`load`, `image`, `tint`: PNG, JPEG, BMP, TGA and QOI from `assets/`) canvases (`canvas`, `draw into`: pictures you draw into that keep their drawing), shaders (`effect "glow"` and your own HLSL files over the window or a canvas, `shade` as the fill of shapes; hot reloaded), picture fills (`fill photo as tile`: shapes become masks a picture shows through), a user interface (`ui [ ]` blocks with `label`, `button`, `toggle`, `slider`, `number`, `textbox` (any script, with an input method), `dropdown`, `choice`, `list`, `progress`, `separator`, `tip`, `colorpicker`, `knob`, `range`, `xypad`, `image button`, `ui hide`, `ui show`, `ui key`, `ui theme` (light, dark or the computer's own colors), `forget ui` to start them over (what they hold is remembered between runs in the sketch folder's `ui.toml`), and `panel`, `row`, `column`, `tabs` and `menu` to lay them out, `at` and `width` to place and size any of them, also in a `ui` block inside `draw` where `at` is a place on the canvas so a widget follows what it sits by (see `examples/follow`), drawn over the window and usable with the keyboard, the mouse and touch; see `examples/ui`), text (`text`, `font`, `align`, `leading`, `measure`: Inter built in, fonts of your own or installed ones, other scripts and emoji at the text size), messages between windows, and windows you can size, fix, move, make borderless or keep on top, read from (`main_window.width`) and change with `set`. A screen reader can read and drive the widgets: VoiceOver on macOS works, and so do Orca on Linux, FreeBSD and OpenBSD and Narrator and NVDA on Windows. The arrow keys change the value of the slider, knob, range, pad or number box that has focus, as in any other program. The first 3D shapes are there (`box`, `sphere`, `plane`, `cone`, `cylinder`, `capsule`, `torus` and `icosphere`, with `grid`, `axes` and `arrow` to see where things are, a camera you place with `camera`, `look at`, `ortho`, `screen point` and `world point`, lights, materials and shadows (`light`, `material`, `shadows`), glTF and OBJ models with their pictures (`model`), the turtle in space (`turtle space`, `up`, `down`, `roll`), collision in space (`touching`, `hits`, `contact` and `cast` with three numbers: spheres, turned boxes, segments and meshes, `triangles` of a model, `ray` through a pixel; see `examples/collide3d`), with a depth buffer, a light, and a camera the mouse turns; see `examples/solids`, `examples/shapes3d`, `examples/stage`, `examples/lights`, `examples/shadows`, `examples/model` and `examples/turtle3d`); lights, materials, models and the rest of 3D come in Phase 4, and sound in a later one.

Under it is the engine, which also has an Odin API (and a C API). It draws on macOS (Metal), Linux, FreeBSD and OpenBSD (Vulkan), Windows (Direct3D 12), and on an iPhone and an Android phone, and 100,000 circles a frame hold about 60 frames a second on the computers tried so far. Packaging a sketch into an app (`roci package`) is not written yet.

Phase 0 (2026-10-27) tested the riskiest parts with four spikes: a window and GPU device on every desktop system, a shader-drawn circle on a real iPhone and a real Android phone, generating Odin from a typed IR, and Dear ImGui with a screen reader. Phase 1, the window and the 2D core, is built and measured on all of them. Phase 2, the language itself, was closed on 2026-10-30, after a test with newcomers confirmed its design; Phase 3 has built text, pictures, pixels, canvases, blend and clip, shaders, export and the user interface widgets, with screen readers checked on every desktop system; what remains of it is its closing test (ten classic Processing examples are ported and the two-window sketch `examples/studio` is built; left are trying it by hand with mouse, touch, keyboard and screen reader, and typing through an input method). Phase 4, 3D, has begun: the solids so far with a depth buffer, one light and an orbiting camera. The design and the plan live in [CLAUDE.md](CLAUDE.md) and [docs/design.md](docs/design.md), which are kept up to date as decisions are made.

## What it looks like

```
particles = []
repeat 200 [ add { pos: { random width, 0 }, vel: { 0, random 3 } } to particles ]

learn step p [ p.pos = p.pos + p.vel ]

draw [
  background 0
  for each p in particles [ step p  circle at p.pos radius 3 ]
]
```

The first part runs today (it is a falling shower of circles). There are no semicolons and no setup function. Comments start with `//`, blocks use `[ ]`, `{ a, b }` is a vector, you teach new verbs with `learn`, and sliders, buttons and check boxes are ordinary words, which a screen reader can read and drive:

```
ui [ size = slider "size" 10 200 ]
draw [ circle at 200 200 radius size ]
```

## How it works

The core is written in [Odin](https://odin-lang.org/) and draws through the GPU API of [SDL3](https://libsdl.org/), which uses [Vulkan](https://www.vulkan.org/), [Metal](https://developer.apple.com/metal/) or [Direct3D 12](https://learn.microsoft.com/en-us/windows/win32/direct3d12/directx-12-programming-guide) depending on the platform. There is no OpenGL anywhere.

You use one command, `roci`. `roci run` runs a sketch and reloads it whenever you save. It interprets the sketch, so it works without installing anything else. `roci package <target>` compiles the sketch to native code through Odin and turns it into an app. Packaging fetches the right version of Odin for you and needs your platform's usual build tools (Xcode, MSVC or clang), and `roci doctor` lists what's missing and how to install it.

The same sketch file runs on FreeBSD, Linux, macOS, OpenBSD, Windows, iOS and Android. You write, run and package sketches on a FreeBSD, Linux, macOS, OpenBSD or Windows computer; iOS and Android are targets only, where the packaged app runs. Not every computer can package every target (an iOS app can only be built on a Mac), and `roci doctor` tells you which ones yours can.

## Roadmap

These are wanted, but not planned for the first stable release:

- **A rocinante shader dialect.** Shaders are written in HLSL for now. Later, a small shader language in rocinante's own style will compile to HLSL.
- **A web target**, so sketches can be shared in a browser.
- **More processors on the desktop.** The first stable release runs on x86-64 computers with FreeBSD, Linux, OpenBSD or Windows, and on Macs with Apple silicon. Later: arm64 FreeBSD, Linux, OpenBSD and Windows computers, and Intel Macs.
- **3D physics** (gravity, joints and stacking in 3D). Collision detection works in 2D and 3D, and physics simulation in 2D.
- **Training models** inside rocinante. For now, trained models run locally but are trained elsewhere.
- **Help for writing sketches with AI assistants**: a sketch-writing skill and an MCP server built on `roci`'s checker and headless run.
- **Editor tools in the source**: inline sliders and color pickers that edit the number in your file, and a frame scrubber that steps backwards through a running sketch.
- **Turtle export** to plotter and embroidery formats.
- **Translated keywords and error messages.**

## Contributing

Issues and pull requests are welcome here on GitHub. Everyone taking part is asked to follow the [code of conduct](CODE_OF_CONDUCT.md).

Day-to-day development happens in a self-hosted GitLab, and this repository is a mirror, updated each time a change there passes the full pipeline. When a pull request is accepted, it is merged there and arrives here with the next update, so it may show as closed rather than merged. Your commits keep your name as author.

The history is linear: branches are rebased onto `main` and merged fast-forward. Keep commits small, one idea each, with a short imperative message prefixed by the area it touches, for example `gfx: batch circles with instancing`. The name is always written in lowercase, rocinante, including at the start of a sentence.

After cloning, turn on the project's git hooks once:

```
git config core.hooksPath tools/hooks
```

## Building

You need git, the Odin release named in `ODIN_VERSION` (check it with `odin version`) and SDL3, which the engine's tests link:

| System                    | Odin                                                                                                                                                    | SDL3 and the rest                                                                                                                                                                                    |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Windows                   | the `windows-amd64` archive from Odin's [releases](https://github.com/odin-lang/Odin/releases), and Build Tools for Visual Studio with the C++ workload | comes with Odin: copy its `SDL3.dll` and `SDL3_ttf.dll` next to the programs (`cp "$(odin root)/vendor/sdl3/SDL3.dll" "$(odin root)/vendor/sdl3/ttf/SDL3_ttf.dll" .`), again after each Odin upgrade |
| Arch, CachyOS, Manjaro    | `sudo pacman -S odin`                                                                                                                                   | `sudo pacman -S git clang sdl3`                                                                                                                                                                      |
| Debian 13+, Ubuntu 25.04+ | the `linux-amd64` or `linux-arm64` archive (their `odin` package is another program)                                                                    | `sudo apt install git clang libsdl3-dev`                                                                                                                                                             |
| Fedora 43+                | the `linux-amd64` or `linux-arm64` archive                                                                                                              | `sudo dnf install git clang SDL3-devel`                                                                                                                                                              |
| FreeBSD                   | `sudo pkg install odin-lang`                                                                                                                            | `sudo pkg install git sdl3`                                                                                                                                                                          |
| OpenBSD                   | built from source: `doas pkg_add gmake llvm%19`, then `gmake release-native` in Odin's repository (the guide has the steps)                             | `doas pkg_add git sdl3`                                                                                                                                                                              |
| macOS                     | `brew install odin`, or the `macos-arm64` archive                                                                                                       | `xcode-select --install`, then `brew install sdl3 sdl3_ttf`                                                                                                                                          |

A system's own Odin package can trail the release in `ODIN_VERSION` (Arch's did in November 2026): when `odin version` says another release, install the pinned one beside it with `sh tools/ci/install-odin.sh ~/.local/share/odin/<release>` and put that folder first on your `PATH`.

Text is drawn with SDL3_ttf, so it needs that library too: `sudo pacman -S sdl3_ttf` on Arch, `brew install sdl3_ttf` on macOS, the system's SDL3_ttf package on the others (the package names on FreeBSD, Debian and Ubuntu are still being confirmed), and on Windows it comes with Odin, as above. OpenBSD has no SDL3_ttf package, so build it from source:

```
doas pkg_add cmake ninja sdl3 harfbuzz git
git clone --branch release-3.2.2 https://github.com/libsdl-org/SDL_ttf.git
cd SDL_ttf
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local \
  -DCMAKE_PREFIX_PATH="/usr/local;/usr/X11R6" -DSDLTTF_VENDORED=OFF -DSDLTTF_HARFBUZZ=ON -DSDLTTF_PLUTOSVG=OFF
cmake --build build
doas cmake --install build
cd /usr/local/lib && doas ln -s libSDL3_ttf.so.0.2.2 libSDL3_ttf.so.0.2 && doas ldconfig -m /usr/local/lib
```

FreeType comes with the base system (`/usr/X11R6`). OpenBSD's linker has no unversioned `.so` names and does not search `/usr/local/lib` by itself, hence the two-number symlink and `ldconfig -m`; when Odin still cannot find `-lSDL3_ttf`, add `-extra-linker-flags:"-L/usr/local/lib"`. Color emoji need PlutoSVG: build `plutovg` (v1.3.1) and `plutosvg` (v0.0.8, `-Dfreetype=enabled`) with `meson` the same way, then configure SDL_ttf with `-DSDLTTF_PLUTOSVG=ON`. On a Wayland session OpenBSD's Mesa cannot show Vulkan windows, so rocinante falls back to X11 through XWayland by itself. `tools/ci/install-sdl3.sh` builds SDL3 and SDL3_ttf together, with FreeType and HarfBuzz from the system.

A sketch's own shaders (`effect`) are translated while it runs by [shaderc](https://github.com/google/shaderc) and [SPIRV-Cross](https://github.com/KhronosGroup/SPIRV-Cross), which the engine links: `sudo pacman -S shaderc spirv-cross` on Arch, `brew install shaderc spirv-cross` on macOS, `sudo apt install libshaderc-dev` on Debian and Ubuntu, where SPIRV-Cross is too old (it lacks the functions the Metal translation calls) and is built with `tools/ci/install-spirv-cross.sh <folder>`, then put `<folder>/lib` on `LIBRARY_PATH` and `LD_LIBRARY_PATH` (the package names on Fedora, FreeBSD and OpenBSD are still being confirmed). Windows needs neither: it draws with Direct3D 12 only, and a sketch's shaders are compiled there by the shader compiler that is part of Windows, so nothing has to be installed for them.

The user interface (work in progress) is drawn by [Dear ImGui](https://github.com/ocornut/imgui), which is C++ and is built from source once: `sh tools/ui-libs.sh` (or `odin run build -- ui-libs`) fetches it at its pinned version and compiles it into `.cache/ui` with `git` and a C++ compiler. Every program that opens a window links it, so run that once before `odin run examples/circle` or any build (`odin run build -- ci` does it for you when it is missing). On Windows it is compiled with MSVC, so run these commands from Git Bash started in a window where the Build Tools' `vcvars64.bat` has run (`call "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat"` in a plain `cmd`, then `"C:\Program Files\Git\bin\bash.exe" --login -i` in the same window).

The screen-reader bridge uses [accesskit-c](https://github.com/AccessKit/accesskit-c), which is Rust: `sh tools/ui-libs.sh accesskit` downloads its release library (macOS, Linux x86-64 and Windows x86-64, the checksum is pinned in the script; needs `curl` and `unzip`, or PowerShell on Windows) into `.cache/ui/accesskit`, and builds it from source with `git`, `cmake` and `cargo` where no library is published (FreeBSD, OpenBSD, arm64 Linux). Without it everything still builds and runs, with no screen-reader support, and `odin run build -- ci` fetches it when it can. It has been checked with a screen reader on every desktop system: macOS (VoiceOver), Linux, FreeBSD and OpenBSD (Orca) and Windows (Narrator and NVDA).

Systems with no SDL3 package (Ubuntu 24.04, Debian 12) can build it with `tools/ci/install-sdl3.sh`, as the GitHub pipeline does. The [getting started guide](https://rocinante-lang.org/guides/01-getting-started/) has every step. (An older Odin, `dev-2026-07` built against LLVM 23, failed to compile even a hello world, so check that `odin version` matches the file.) Then, from the repository root:

```
odin run build -- ci          # what the pipelines run
odin run build -- ci --fast   # what the pre-push hook runs
odin run build -- licences    # dependency license check
```

The full `ci` also draws the golden images on Mesa's software Vulkan driver (lavapipe) when it is installed, and says so when it is not. Windows has no lavapipe, so there `odin run tests/golden` draws them on the graphics card through Direct3D 12, where a few edge pixels differ from the references.

## Trying it

The documentation (guides, a reference of every word with an example and the picture it draws, every message rocinante can give, and a FAQ) is at <https://rocinante-lang.org/>, built from this repository: `odin run build -- docs` makes it locally, with [Hugo](https://gohugo.io) at the version in `HUGO_VERSION`.

Run a sketch (the examples are written in the language as `sketch.roci` files):

```
odin run cli -- run examples/garden/sketch.roci        # two windows: click, press 1 2 3, space and c
odin run cli -- run examples/two_windows/sketch.roci
odin run cli -- run examples/starfield                    # a sketch of two files: sketch.roci and palette.roci
odin run cli -- run examples/checks                       # verbs with their checks beside them (shapes.roci), drawn as a flower of rings
odin run cli -- run examples/canvas                       # a canvas that keeps its drawing: fading trails, painting with the mouse
odin run cli -- run examples/fills                        # shapes filled with a picture: cover, fit, stretch, tile and center
odin run cli -- run examples/images                       # pictures: loaded by name, drawn at a size, tinted, see-through and turning
odin run cli -- run examples/text                         # words in Inter: two weights, aligned, wrapped and measured
odin run cli -- run examples/neon                         # the built-in effects: glow, split, grain and vignette over bright rings
odin run cli -- run examples/tunnel                       # a raymarched tunnel made by one shader, with a lens effect on top
odin run cli -- run examples/export                       # s, v, p save a PNG, SVG and PDF; m records an mp4 (needs ffmpeg), a an animated PNG
odin run cli -- run examples/ui                           # widgets in panels and tabs, for a hand, a keyboard or a screen reader; its file menu picks light or dark colors
odin run cli -- run examples/flocking                     # ports of Processing classics: also bounce, sinewave, rope, life, koch, mandelbrot, noisewave, recursion, colorwheel
odin run cli -- run examples/studio                       # two windows: a control surface with every widget, and a stage of circling dots they steer
odin run cli -- run sketch.roci --frames 60 --screenshot out.png   # headless, saves the last frame
```

The other commands:

```
odin run cli -- new mysketch                           # a sketch folder, with git; roci init does it in this folder
odin run cli -- add cat.png                            # copy a file into the right folder of assets/
odin run cli -- get github.com/someone/flocking          # copy a library into libs/ (then  use "flocking" ); roci update fetches newer copies
odin run cli -- check sketch.roci                      # say what is wrong, with the fix
odin run cli -- fmt                                    # write every .roci file here in the house style
odin run cli -- man rect                               # how a verb is written (no word: every verb)
odin run cli -- test examples/checks                   # run the checks of a sketch and compare its picture with the stored one; --accept stores a new picture
```

Build the binary once with `odin build cli -out:output/roci -o:speed` and use `output/roci run sketch.roci` for a quick start.

The engine's own examples use the Odin API and open real windows:

```
odin run examples/circle              # the smallest sketch: one circle
odin run examples/garden              # the Phase 1 demo: a palette window and a garden
odin run examples/two_windows         # two windows that send each other messages
odin run examples/shapes              # every shape, a circle follows the mouse
odin run examples/benchmark -o:speed  # 100,000 circles a frame, with frame rate and timings
```

Add `-- 3` to any of these to close the window after three seconds. `examples/c/circle.c` is the same circle through the C API (`include/roci.h`, checked by `tools/abi-check.sh`).

## Versions

Releases use calendar versioning, `YYYY.MINOR.MICRO`: the year of the release, the feature release within that year counted from 1, and its fixes counted from 0. Releases before the first stable one are previews and carry their stage: `2026.1.0-alpha` is the first alpha, `2026.1.1-alpha` its first fix and `2026.2.0-alpha` the next. The first stable release is the first version without one.

## License

[Zero-Clause BSD](LICENSE) (0BSD). Use it for anything, with or without credit.

## Credits

rocinante is designed and built by Fabrizio Poltronieri (sandbenders) [fabrizio@fabriziopoltronieri.com], with help from Claude, Anthropic's AI assistant.

[^expanse]: Four centuries later the name went to a ship. In _The Expanse_, the novel series by James S. A. Corey (the pen name of Daniel Abraham and Ty Franck) that began with _Leviathan Wakes_ in 2011, the Rocinante starts out as the _Tachi_, a Martian navy gunship. The survivors of the ice freighter _Canterbury_ take it over and rename it Rocinante, and it carries them through all nine novels and the television series (Syfy from 2015, then Amazon Prime Video). It is a small ship that keeps flying when it has no business doing so.
