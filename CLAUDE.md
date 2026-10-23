# CLAUDE.md: rocinante

This file is the single source of truth for rocinante's design, scope and plan. When a decision changes, update this file in place. Do not create parallel design documents, changelogs of decisions or "notes" files beside it. `MANIFESTO.md` is the public statement of intent; this file is how we build it.

Read `MANIFESTO.md` before starting any work. Every decision below serves it.

---

## 1. What rocinante is

An open-source creative coding framework and language.

- **rocinante (the language)**: a small, Logo-inspired language for sketches. No semicolons, no braces, one predictable shape. File extension `.roci`.
- **The core**: an engine written in **Odin** on SDL3 and its GPU API (Vulkan, Metal, Direct3D 12). It owns windows, rendering, UI, audio, input, I/O and packaging.
- **`roci` (the tool)**: one command-line program to run, watch, check and package sketches. Written in Odin.
- **A public Odin API, with a C ABI,** for power users who want to write sketches or extensions in Odin (or C) directly. Same verbs, same behaviour.

Execution: **interpreted while you work, compiled to native code when you ship** (§4.7). Users never choose or notice; `roci run` interprets, `roci package` compiles.

Target platforms, all first class from the start: FreeBSD, Linux, macOS, Windows, iOS, Android.

The smallest valid program:

```
circle 100 100 50
```

It opens a default window, draws the circle and keeps the window open. This must work forever, interpreted and compiled; it is the project's first regression test.

---

## 2. Non-negotiables

These override convenience. If a task seems to require breaking one, stop and raise it with Fabrizio.

1. **One line makes a picture.** No mandatory setup, imports, main function or config file.
2. **Nothing technical leaks.** Users never see shader formats, GPU backends, lifetimes, threads, types, compilers, linkers, build systems or signing unless they explicitly go looking. The one exception: `roci package` needs a user-installed toolchain (Odin, plus Xcode, MSVC or clang depending on the platform, §4.7). `roci run` never does, and `roci doctor` explains every missing piece in plain words with the exact install steps.
3. **The canvas never crashes.** Script errors keep the last good frame running and draw an error overlay. A crash in the core is a bug of the highest severity.
4. **Errors teach.** Every error says where (file, line, column, with the source line shown), what went wrong in plain language, and gives an example that would work. Model: Elm's error messages (see References).
5. **Live by default.** `roci run` watches the file and reloads on save, keeping state where possible.
6. **Fast.** Batching, instancing and retained geometry happen automatically. A sketch drawing 100,000 circles per frame should hold 60 fps on a mid-range laptop GPU. Released sketches are native code. Per-pixel and per-vertex work belongs in built-ins or shaders; when a user writes such a loop, the docs should show the fast built-in.
7. **One behaviour.** A sketch behaves identically interpreted and compiled. Any difference is a bug in one of the back ends, never a user problem.
8. **Everywhere.** Every commit on `main` builds and passes the full pipeline on Linux (§11). Before every release tag, the other five platforms (FreeBSD, macOS, Windows, iOS, Android) are checked locally against the release checklist and the results recorded (§11). Mobile targets are also smoke-tested at least once per phase.
9. **Modern dependencies.** No OpenGL anywhere. Use current stable versions of everything.
10. **UI is first class.** Buttons, sliders, text boxes, drop-downs and the rest are built-in verbs (§4.8, §5.8), available in every sketch with no add-on, import or setup, on every platform, including screen-reader support.

---

## 3. Working rules for Claude Code

- **Check official documentation before using any API, library, flag or tool.** Do not guess function signatures, command flags or behaviour. If docs are unclear, say so and ask rather than presenting a guess as fact. Cite the doc URL in commit messages or PR descriptions when a decision depends on it.
- **Odin.** The core and `roci` are written in Odin. Pin one Odin release per rocinante release (recorded here once Phase 0 picks it) and upgrade deliberately. Follow Odin's own style and idioms; no Rust or C++ habits.
- **Libraries: Odin `vendor:` first, latest upstream when vendor lags.** Use a library from Odin's `vendor:` collection when its version is current. When it lags behind the latest stable upstream release (SDL3 and its satellites especially), write or regenerate bindings for the latest version in the repository's own `vendor/` folder, and offer the update upstream to Odin. C and C++ libraries are used through Odin's foreign system; C++ only behind a C API.
- **Ask before adding a dependency.** State what it does, its licence, its platform support (including FreeBSD, iOS and Android) and why an existing dependency won't do.
- **Licence policy.** rocinante is 0BSD (§10). Dependencies must be under permissive licences (0BSD, MIT, MIT-0, Apache-2.0, BSD, ISC, zlib, public domain). MPL-2.0 only when there is no permissive alternative, with a source notice shipped by `roci package`. Never GPL or LGPL code in the core, in `roci`, or in packaged sketches. (A GPL/LGPL tool used only to build a dependency, such as a build system, is fine as long as nothing from it is shipped.)
- **The name is always lowercase**: rocinante, never "Rocinante", including at the start of a sentence, in titles, docs, UI text, package metadata and commit messages. The same applies to `roci`.
- Fabrizio's tools: `nvim` (never `nano`), `rg` (not `grep`), `eza` (not `ls`). Use these in any instructions, scripts or docs you write for him.
- For FreeBSD ports, build and test in one pass with `poudriere bulk -t`. Use `testport -i` only when debugging inside the jail.
- Work in small, reviewable steps. Each phase below lists exit criteria; a phase is done only when all of them pass.
- Never weaken a non-negotiable to make a task easier. Flag the conflict instead.
- When you finish something that changes the design, update this file in the same commit.
- **Git** follows §11: short feature branches rebased onto `main` and merged fast-forward, small frequent commits. **Never mention AI, Claude or any assistant in commit messages, branch names, tags or release notes, and never add `Co-Authored-By` trailers or session links.**
- Contribute fixes upstream (Odin, its vendor bindings, SDL, Dear ImGui, AccessKit) whenever we fix something there.

---

## 4. Architecture

### 4.1 Layers

```
 .roci sketch ──► lang: lexer → parser → checker + type inference → typed IR
                        │                                   │
              roci run  │ (interpreter)          roci package│ (code generator)
                        ▼                                   ▼
                  interpreter                  generated Odin source
                        │                                   │ odin build (user-installed),
                        │                                   │ together with the core
                        └──────────────┬────────────────────┘
                                       │ calls verbs (stable verb ABI)
 Odin/C sketch ────────────────────►  roci (public API: verbs, types, events)
                                       │
        ┌──────────────────────────────┼──────────────────┬───────────────┐
        ▼                              ▼                  ▼               ▼
   gfx + ui                        audio              io              platform
   (2D/3D, text, images,          (I/O, playback,    (files, data,   (SDL3: windows,
   shaders; Dear ImGui            synthesis, MIDI,   network,        input, events,
   + AccessKit bridge)            OSC, analysis)     serial, video)  camera, sensors)
        │
        ▼
   SDL3 GPU API ──► Vulkan / Metal / D3D12

 roci (cli): new, init, add, get, update, run, check, fmt, package <target>, doctor
```

### 4.2 Source layout (initial)

Odin has no package manager and no workspace file: a package is a directory, and every `.odin` file in it belongs to that package. The repository is one Odin collection.

```
rocinante/
  CLAUDE.md
  MANIFESTO.md
  README.md            what rocinante is, project status, how to contribute (§11)
  LICENSE              0BSD text (§10)
  roci/                public API, prelude, stable verb ABI (package roci)
    platform/          SDL3 wrapper: app loop, windows, input, events
    gfx/               renderer, batching, tessellation, text, images, shaders
    ui/                UI verbs on Dear ImGui, theme, custom widgets, AccessKit bridge
    audio/             audio graph, playback, synthesis, MIDI, OSC
    io/                files, data formats, network, serial, video, camera
    lang/              lexer, parser, checker, type inference, typed IR, interpreter
    codegen/           typed IR → Odin source for `roci package`
  cli/                 the `roci` binary (package main)
  vendor/              our own bindings where Odin's vendor: lags, plus C/C++ sources and
                       prebuilt libraries (Dear ImGui via dear_bindings, accesskit-c, …)
  build/               build script written in Odin (no Make, no CMake for contributors)
  shaders/             internal shaders (HLSL source), compiled at build time
  examples/            .roci and .odin examples, one per feature
  tests/               golden-image tests, language tests, back-end equivalence tests
  tools/hooks/         pre-push and commit-msg hooks (§11)
  docs/                release checklist and contributor docs
  ODIN_VERSION         the pinned Odin release, read by the build script and both pipelines
  .gitlab-ci.yml       GitLab pipeline (§11)
  .github/workflows/   GitHub pipeline (§11)
```

Package boundaries can change; record the change here.

### 4.3 Rendering model

- Immediate-mode verbs (`circle`, `line`, `box`) append to a per-window **command list**. The renderer turns the command list into batched, instanced GPU draws at the end of the frame. Users never see this.
- Geometry that does not change between frames is detected (hash of command + parameters) and cached on the GPU automatically.
- 2D and 3D share one window. A window has a default 2D orthographic projection; using any 3D verb (`box`, `camera`, `light`) switches that draw block to a perspective camera with sensible defaults, including mouse orbit, unless the user sets a camera.
- **SDL3**: Odin's `vendor:sdl3`, `vendor:sdl3/ttf` and `vendor:sdl3/image` exist; use them when current, otherwise our own bindings for the latest SDL3 release (§3).
- **Shaders**: internal shaders are written once in HLSL and compiled offline with SDL_shadercross to SPIR-V, MSL and DXIL, then embedded in the binary. SDL_shadercross takes SPIR-V or HLSL as input and outputs DXBC, DXIL, SPIR-V, MSL or HLSL, and offers both runtime translation and an offline command-line tool. User-written shaders: see Open Questions.
- **Text**: SDL3_ttf's GPU text engine (`TTF_CreateGPUTextEngine`, available since SDL_ttf 3.0.0) is the first candidate. Verify shaping, fallback fonts and atlas behaviour before committing.
- **Vector tessellation** (paths, thick strokes, curves): our own Odin implementation, or a permissively licensed C library. Decide in Phase 1.
- **Math**: Odin's built-in array programming, swizzles, matrices and quaternions, plus `core:math/linalg`. No external maths library.

### 4.4 Threads

Users never see threads. The core decides: rendering and windowing stay where SDL requires them (check SDL3 documentation for thread rules per subsystem; `TTF_CreateGPUTextEngine`, for example, must be called on the thread that created the GPU device). Audio runs on its own real-time thread. Asset loading is asynchronous by default; a sketch using an image before it has loaded draws nothing for that frame rather than blocking. Odin's implicit `context` (allocator, logger) is set up per thread by the core.

### 4.5 Multi-window and messaging

- `window w h` and `window w h at x y` return a window handle.
- Each window has its own `draw [ ... ]` block and command list.
- Windows communicate with `send <window> <value>` and `on <window> receive <name> [ ... ]`. Messages are values (numbers, text, lists, records), delivered on the next frame. Internally: channels, no shared mutable state exposed.
- On mobile, multiple windows become stacked or tabbed views. Decide the exact behaviour in Phase 8 and document it here.

### 4.6 Audio

- Device I/O through SDL3 audio, so one platform layer covers every target. Verify SDL3's audio backend on FreeBSD early.
- Decoding: miniaudio (public domain or MIT-0; in Odin's `vendor:`) has built-in decoders for WAV, FLAC and MP3. Vorbis comes from `stb_vorbis` (also in `vendor:`). AIFF, Opus and AAC: decide in Phase 5 (permissive C libraries or platform APIs).
- Synthesis and DSP: our own Odin DSP library (oscillators, filters, envelopes, effects, FFT), with simple user verbs. Bind a permissive C library only if writing our own proves unreasonable.
- MIDI: candidate `vendor:portmidi`. Verify its FreeBSD, iOS and Android support before Phase 5; fill gaps with our own backends if needed.
- OSC: our own Odin implementation (OSC is a small protocol).

### 4.7 Execution model (decided 2026-10-22, revised 2026-10-23)

**One front end, two back ends.**

- **Front end (shared).** Lexer, parser, checker and type inference produce a **typed IR**. All errors users see come from here, so they are identical in both modes.
- **Development back end: interpreter.** `roci run` executes the typed IR directly. It owns hot reload, state preservation across saves and the error overlay. It is part of the `roci` binary and needs no toolchain. The core is linked into `roci`, so `roci run` works on a machine with nothing else installed.
- **Release back end: Odin code generation.** `roci package` translates the typed IR into Odin source and builds it, together with the core's Odin source, using the user's installed Odin compiler (LLVM-based, so the whole program is optimised together), for the chosen target. Odin's Android and iOS subtargets cover mobile. No interpreter ships in released sketches. Generated Odin must be readable: one Odin procedure per verb, names derived from the sketch.
- **User-installed toolchain for packaging only** (decided 2026-10-23). rocinante does not bundle compilers or linkers. `roci package` needs:
  - **Odin**, at the version pinned by this rocinante release (§3); `roci` checks `odin version` and explains a mismatch;
  - **Windows**: MSVC and the Windows SDK from Visual Studio's "Desktop development with C++" component, which Odin requires;
  - **macOS**: the Xcode command-line tools; **iOS**: full Xcode and an Apple Developer Program account (§7);
  - **Linux and FreeBSD**: clang, which Odin uses for linking;
  - **Android**: the SDK and NDK, which `roci` fetches and manages on first use (§7).
  `roci doctor` checks all of this per target and prints the exact install steps for the user's OS. Packaging failures are reported in rocinante's plain style, never as raw compiler output; the raw log is saved to `output/` for the curious.
- **Stable verb ABI.** Generated code and the interpreter call core verbs through the same functions, so behaviour stays identical (non-negotiable 7).
- **No bytecode VM, no JIT.** A third back end would be one more thing to keep equivalent. Revisit only if the interpreter proves too slow for development use before Phase 7.
- **Source mapping.** Crashes and profiler output in packaged sketches must point at `.roci` lines. Investigate whether Odin can carry line information from generated code; otherwise keep a map from generated Odin lines to `.roci` lines and translate reports.
- **iOS.** Released sketches are ordinary native code, so App Store Review Guideline 2.5.2 (no downloading or executing code that changes the app's functionality) is not an issue for shipped sketches. Any future on-device live-coding app would embed the interpreter and needs its own review strategy (2.5.2 has a narrow carve-out for educational apps whose code is fully viewable and editable by the user).

### 4.8 User interface (decided 2026-10-23)

UI elements are first-class citizens: built-in verbs, drawn by Dear ImGui through SDL3, identical on every platform.

- **Immediate mode.** Widgets are verbs called every frame inside a `ui [ ]` block; they return their current value (or `true` on the frame a button is clicked). No callbacks, no widget objects, no syncing between UI state and sketch state. This matches the paradigm in §5.2: widgets are verbs, values are plain data.
- **Engine: Dear ImGui** (MIT). Its official backends `imgui_impl_sdl3` (input, platform) and `imgui_impl_sdlgpu3` (rendering through the SDL3 GPU API) mean no custom renderer integration. UI is drawn last in each window's render pass, so it is exported, recorded and golden-image tested like any other drawing. It always draws on top of the canvas and ignores canvas transforms, cameras and styles. Users only ever see rocinante verbs and rocinante's theme; Dear ImGui never appears in the language, docs or errors.
- **Odin bindings** come from **dear_bindings** (MIT), which generates a C API (`dcimgui.h`) and a JSON description from which we generate Odin bindings. The SDL3 backend is in dear_bindings' tested list; `imgui_impl_sdlgpu3` is not yet, so verify its conversion in Phase 0 and contribute fixes upstream. Generated bindings live in `vendor/`.
- **Accessibility: our own AccessKit bridge** (decided 2026-10-23). Dear ImGui has no screen-reader support, so we build it. Every widget goes through a rocinante verb, so the core always knows each widget's role, label, value, state and focus, even though Dear ImGui doesn't keep them. Each frame, `ui` builds an AccessKit tree from its own widget records plus Dear ImGui's item rectangles and IDs, sends updates only when something changed, and turns AccessKit action requests (focus, press, set value, increment, decrement) into the same changes a mouse or keyboard would make. AccessKit (Apache-2.0 OR MIT; Chromium-derived parts under a BSD-style licence) is used through its C bindings, accesskit-c, which publishes prebuilt releases; accesskit-c itself is built in Rust, so if prebuilt libraries for a target (Android and iOS are not mentioned in its README) are missing, we build them once per release as part of the core build, never on users' machines. AccessKit's adapters cover Windows (UI Automation), macOS (NSAccessibility), Unix (AT-SPI over D-Bus), Android and iOS. Whether the Unix adapter works on FreeBSD is unverified: confirm in Phase 3 and record it here. Offer the bridge upstream to Dear ImGui as a reusable piece.
- **Identity.** Each widget is identified by its label plus its position in the source (mapped to Dear ImGui IDs), so values survive hot reload and editing nearby code. Two widgets with the same label in the same block are a load-time error with a friendly message.
- **Memory.** Widget values persist across hot reload and are saved in `ui.toml` in the sketch folder, which is committed to git (§4.9). `forget ui` resets them.
- **Text input and IME** use SDL3's text input API through the SDL3 backend: `SDL_StartTextInput` enables text and IME editing events and, on some platforms, shows the on-screen keyboard; `SDL_StartTextInputWithProperties` requests number fields and multi-line input; the IME window is placed with `SDL_SetTextInputArea`. Verify the backend's IME handling against non-Latin input in Phase 0.
- **Input model.** Mouse, touch, pen and keyboard all work. Dear ImGui's keyboard navigation is enabled by default: Tab and Shift+Tab move focus, Enter activates, Escape cancels. Every widget is usable without a mouse. Touch arrives as mouse input in Dear ImGui; we enlarge hit targets on touch devices through the style scale and handle scrolling by drag ourselves.
- **HiDPI.** Everything scales with display density.
- **Theme.** One good default theme, light and dark, following the system setting, designed for rocinante rather than Dear ImGui's stock look. Customise with verbs (`ui theme dark`, `ui color accent #ff8800`, `ui font "Inter"`, `ui size 1.2`), never with style sheets; these map onto Dear ImGui's style settings internally.
- **Widgets Dear ImGui lacks** (`knob`, `xypad`, `range`, and a `colorpicker` in the form we want) are written with Dear ImGui's draw-list API inside `ui`, behaving exactly like the built-in ones: focus, keyboard, touch, theme and AccessKit roles included.
- **Version.** Pin one Dear ImGui version per rocinante release and upgrade deliberately, regenerating bindings each time.
- **Text in UI vs canvas.** Dear ImGui rasterises its own UI text; canvas text (`text "hello"`) uses SDL3_ttf (§4.3). Phase 3 must make both use the same default font so UI and canvas look like one system.

### 4.9 Sketch folders and assets (decided 2026-10-23)

A sketch that has files lives in a sketch folder. Everything it ships with is in `assets/`.

```
my-sketch/
  sketch.roci          # roci new starts it with: circle 100 100 50
  assets/
    images/  sounds/  fonts/  models/  shaders/  data/
  output/              # saved frames, recordings, exports, build logs; ignored by git
  libs/                # vendored libraries from `use` (§5.10); committed to git
  ui.toml              # remembered UI values; committed to git
  .gitignore
  .gitattributes       # only when Git LFS was chosen
```

- **A single file still works.** A lone `.roci` file with no folder runs (non-negotiable 1). `assets/` is where files go once a sketch has any, never a precondition.
- **Assets are found by name, not path.** `load "cat.png"`, `font "Inter"`, `sound "rain.wav"` search all of `assets/`, subfolders included. The subfolders are a tidy convention, not an address. If two files share a name, the checker says so and asks for the subfolder: `load "images/cat.png"`.
- **Bundled files come only from `assets/`.** A literal path outside it is a load-time error that teaches: "`/Users/…/cat.png` is outside your sketch, so it wouldn't travel with it. Copy it into `assets/`, or run `roci add /Users/…/cat.png` and I'll copy it for you." This is what makes sketches portable: a zip or a `git clone` runs anywhere, and iOS and Android (which can't read arbitrary paths) behave like the desktop.
- **Packaging bundles all of `assets/` and `libs/` (§5.10).** Computed names (`load "frame" + n + ".png"`) can't be traced, so nothing is dropped. `roci package` lists files that no literal in the sketch mentions, as a hint, without removing them.
- **Live assets.** While `roci run` is going, a changed asset (repainted image, re-exported model, edited shader) reloads in the running sketch.
- **Runtime files are the deliberate exception.** Files chosen while the sketch runs may come from anywhere the platform allows: `ask file`, `ask folder`, dropped files, `files in "~/Pictures"`. They are never bundled, because they belong to whoever is running the sketch. On iOS and Android these go through the system file pickers.
- **Output.** `save`, `record` and exports write to `output/` by default, so renders never clutter the repository. An explicit path is allowed for saving.
- **Remembered UI values** (§4.8) live in `ui.toml` at the top of the sketch folder, written in a readable, stable order so diffs are meaningful. It is committed to git, so a tuned performance travels with the repository. `forget ui` clears it. Packaged sketches start from the committed values.
- **Packaging details** (app name, icon, bundle id) are asked by `roci package` on first use and stored in the sketch folder then; there is no config file to write by hand.

**`roci new` and `roci init`.** `roci new <name>` creates the folder above; `roci init` does the same in an existing folder without overwriting anything. Both:

- write `sketch.roci` (formatted, with the circle), `assets/` and its subfolders (each with an empty `.keep` file so git keeps them), `output/` and `.gitignore` (ignoring `output/` and roci's local cache);
- if git is installed, run `git init` and make a first commit; without git, say so in one line and carry on;
- **offer Git LFS** for large binary assets. On yes, and if `git lfs` is installed, track common audio, video, 3D and large image types (`*.wav`, `*.aiff`, `*.flac`, `*.mp4`, `*.mov`, `*.glb`, `*.fbx`, `*.exr`, `*.psd`, list to be finalised in Phase 2) with `git lfs track`, which writes `.gitattributes`, and commit that file. If Git LFS isn't installed, explain in plain words how to get it and continue without it. Git LFS is a separate, user-installed tool; rocinante neither bundles nor depends on it (§3).

---

## 5. The language

### 5.1 Design principles

- One statement per line. No terminators.
- One shape: `verb argument argument ...`. Verbs have a fixed number of required arguments, so the parser always knows where a call ends (as in Logo). Parentheses are allowed anywhere for clarity: `circle (x + 10) y 50`.
- Optional arguments are introduced by small connecting words, never by position: `window 800 600 at 100 100`, `text "hi" at 20 20 size 32`, `image photo at 0 0 width 200`. The connecting words form a short, fixed list (start with: `at`, `size`, `width`, `height`, `from`, `to`, `by`, `in`, plus the style words in §5.9: `fill`, `stroke`, `thickness`, `alpha`, `font`, `style`). `to` is only ever a connecting word (`for i from 1 to 10`, `add x to particles`); verbs are defined with `learn` (§5.11).
- Blocks use `[ ]`, as in Logo. Newlines inside blocks are free. (Decided 2026-10-22: `[ ]`, not `end`.)
- **Indentation is free and never changes meaning** (decided 2026-10-23). `[ ]` alone defines blocks; tabs, spaces, pasted code and phone keyboards can never break a sketch. Consistency comes from tooling instead:
  - **`roci fmt`** rewrites a sketch in the house style: two spaces per block level, one space inside brackets, one statement per line. Editor plugins run it on save, `roci new` starts formatted, and all docs and examples are formatted with it. It has no options, so there is nothing to argue about.
  - **Indentation as an error hint.** The parser ignores indentation, but when brackets don't balance, the checker compares the brackets with the indentation to find where the mistake is. Example: "Line 7 is indented as if it belongs inside the `repeat` on line 4, but that block closed on line 6. Did you mean to move the `]`?" Never a generic "unexpected end of file".
- Few keywords. If a feature can be a verb, it is a verb.
- One number type (64-bit float) for users. The compiler may use narrower or integer representations internally when inference proves it safe and results are identical.
- **Case** (decided 2026-10-23). The language is case-sensitive, with two rules:
  - **Every keyword and built-in name is lowercase**: verbs (`circle`, `draw`, `repeat`), connecting words (`at`, `fill`), built-in values (`width`, `mouse`, `pi`, `tau`) and colour names (`red`). `Circle` or `REPEAT` is a load-time error that teaches: "rocinante's words are written in lowercase. Did you mean `circle`?"
  - **A name written in all capitals is a constant.** All capitals means letters, digits and underscores with at least one letter and no lowercase letters: `SPEED`, `MAX_PARTICLES`, `GRID_2`. It is assigned once and can never change. Assigning it again, or changing anything inside it (`add green to COLOURS`, `PALETTE.bg = black`), is a load-time error: "`SPEED` is written in capitals, so it's a constant and can't change. If it needs to change, write it in lowercase: `speed`." Constants are deeply immutable, so a constant list or record can be read but never modified.
  - Other user names are free (`size`, `myBall`, `big_circle`); `size` and `Size` are different names, but the checker warns when two names in a sketch differ only by case, since that is almost always a typo.
  - Constants help the compiler (their values can be folded into native code) and hot reload (§5.5).

### 5.2 Paradigm (decided 2026-10-22)

rocinante is **procedural and data-oriented**, in the spirit of Logo and of Odin. It is not object-oriented and not purely functional.

- **Verbs act on plain data.** Data is numbers, text, vectors, lists and records. Behaviour lives in verbs (built-in, or taught with `learn`), never inside data. Write `bounce ball`, not `ball.bounce()`. Reading and writing fields (`ball.x`) is fine.
- **No classes, methods, inheritance, interfaces or constructors.** Users learn one concept, verbs on data.
- **Many things = a list of records.** Particles, agents, boids: a list of records plus verbs that act on one record, used with `for each`. This is also the fast path internally: with inferred types, a list of same-shaped records compiles to a contiguous array (or Odin `#soa` layout where that helps).

Borrowed from Odin (see the Odin FAQ in References):

- **Array programming.** Vectors and colours support arithmetic directly: `pos = pos + vel`, `c = c * 0.5`. Swizzles: `p.xy`, `p.zyx`. These map one to one onto Odin's own array programming in generated code.
- **Explicit verb groups.** One verb name may accept several argument shapes (`circle 100 100 50` and `circle p 50`). The shapes are declared together in one place, in the core and in user code; the checker picks the shape by arity and argument kinds and reports ambiguity as a load-time error. Shapes with different numbers of arguments interact with comma-free parsing (where does `circle p 50 …` end?); the exact rule is open (§10).
- **Useful zero values.** A record field that was never set reads as 0 (or empty text, empty list). Reading it is never an error.
- **No exceptions.** A failing operation (missing file, bad URL) shows the error overlay, yields an empty value and lets the sketch continue. Users can test for emptiness (`if photo is empty [ … ]`); there is no try/catch.
- **Implicit context.** Style and transform state (fill, stroke, thickness, transform, font, blend) is an implicit context, reset at the start of every `draw` frame and scoped by `with [ ]` (style, §5.9) and `push [ ]` (style and transforms).

Deliberate differences from Odin:

- **Blocks capture variables.** `every 2 seconds [ grow size ]` sees `size`. Odin has only non-capturing procedures because capturing closures need automatic memory management; our runtime manages memory, so users never think about it. Generated Odin passes captured variables explicitly.
- **A light functional layer for lists**, as verbs that take a block: keep matching items, transform each item, fold, sort by. Names are open (see §10); `map` is reserved for the Processing-style number remapping verb.

### 5.3 Typing: inferred and static (decided 2026-10-22)

- **Users never write a type.** There is no type syntax in sketches.
- **The checker infers every type it can** from literals, verb signatures, field use and assignments: `x = 10` is a number, `p.pos` is a vector, `particles` is a list of records with fields `pos` and `vel`, both vectors.
- **Conflicts are load-time errors in plain words**, never type jargon. For example: "`size` holds a number on line 3 but text on line 12. A name keeps one kind of value; try a new name for the text."
- **Records are shaped by use.** A record literal fixes its fields; adding a field elsewhere extends the shape for all records built at that site. The exact rules are designed in Phase 2 with the error messages written first.
- **Fallback, not failure.** Where inference cannot decide (rare in sketches), the value becomes a general boxed value (an Odin tagged union in generated code): slower, still correct, identical behaviour in both back ends. `roci check --why-slow` (name provisional) lists those places so power users can see them; ordinary users never need to.
- Inference is what makes compiled sketches fast: known types become plain Odin structs, floats and arrays instead of runtime kind checks.

### 5.4 Core syntax (draft)

```
# comments start with a hash

x = 10                      # variables: just assign
name = "Ada"
SPEED = 4                   # all capitals: a constant, can never change
COLOURS = [ red orange teal ]   # constant list: readable, never modified
points = [ 1 2 3 ]          # lists
p = { x: 10, y: 20 }        # records; access with p.x

learn star size [           # teach a new verb, Logo style (§5.11)
  repeat 5 [ forward size  right 144 ]
]

learn double n [ give n * 2 ]   # `give` hands back a value

star 100                    # use it like any built-in
y = double 21

if mouse.x > width / 2 [ fill red ] else [ fill blue ]

repeat 10 [ circle (random width) (random height) 5 ]
for i from 1 to 10 [ line 0 (i * 10) width (i * 10) ]
for each p in points [ circle p 50 10 ]

draw [ ... ]                # runs every frame (default window)
draw w [ ... ]              # runs every frame for window w
on key "space" [ ... ]
on mouse down [ ... ]
on touch [ ... ]
on w receive msg [ ... ]
every 2 seconds [ ... ]

v = vec 3 4                 # vectors, with arithmetic and swizzles
u = v * 2 + (vec 1 1)
circle v.xy 10
```

A complete particle sketch in this style (lists of records, verbs, no objects):

```
particles = []
repeat 200 [ add { pos: (vec (random width) 0), vel: (vec 0 (random 3)) } to particles ]

learn step p [ p.pos = p.pos + p.vel ]

draw [
  background 0
  for each p in particles [ step p  circle p.pos 3 ]
]
```

### 5.5 Program model

- Top-level statements run once, in order. If the program has no `draw` block, the window shows the result and stays open.
- If a `draw` block exists, top-level statements act as setup and the block runs every frame.
- State survives hot reload (interpreter only): top-level variables keep their values unless the line defining them changed. Exact rules: decide in Phase 2 and record here.
- Constants (all-capital names, §5.1) never keep old state: on every reload they take the value written in the source, so editing `SPEED = 4` to `SPEED = 8` takes effect immediately while variables keep their running values.

### 5.6 Turtle

Logo's turtle is built in, in 2D and 3D: `forward`, `back`, `left`, `right`, `pen up`, `pen down`, `home`, plus `up`/`down`/`roll` in 3D. Each window has its own turtle.

### 5.7 Errors

Format, modelled on Elm:

```
── I don't know the word "circel" ──────────────── sketch.roci:3:1

3 │ circel 100 100 50
  │ ^^^^^^

Did you mean:  circle 100 100 50
```

Every error class needs an entry in `tests/errors/` with the source that triggers it and the expected message. Error messages are reviewed like features. Because all errors come from the shared front end (§4.7), `roci run` and `roci package` report exactly the same errors.

### 5.8 User interface verbs (draft)

Widgets live in `ui [ ]` blocks (default window) or `ui w [ ]` (window `w`). Each returns a value usable anywhere in the sketch.

```
ui [
  size   = slider "size" 10 200          # number in a range
  speed  = knob "speed" 0 1              # rotary, for audio-visual work
  trails = toggle "trails"               # true / false
  name   = textbox "title"               # one line of text
  notes  = textbox "notes" lines 4       # multi-line
  shape  = dropdown "shape" [ "circle" "square" "star" ]
  mode   = choice "mode" [ "draw" "erase" ]   # radio buttons
  tint   = colorpicker "tint"
  pos    = xypad "position"              # 2D pad, returns a vector
  count  = number "count" 1 1000         # numeric field with steppers
  if button "clear" [ particles = [] ]
  label "fps: " + fps
  progress loaded
]

draw [
  background 0
  fill tint
  circle pos.x pos.y size
]
```

Layout and grouping:

```
ui [
  panel "controls" [                     # titled, collapsible group
    row [ button "play"  button "stop" ]  # side by side
    size = slider "size" 10 200
  ]
  tabs [
    tab "shape" [ ... ]
    tab "colour" [ ... ]
  ]
  menu "file" [ if item "save" [ save "frame.png" ] ]
  tip "drag to move"                     # tooltip for the previous widget
]
```

- **Default layout:** widgets stack vertically in a floating panel at the top left of the window, sized to fit. `at x y` places a widget or panel explicitly; `width` sets its width.
- **Starting values:** `slider "size" 10 200 start 50`. Without `start`, numbers start at the minimum, toggles off, text empty, dropdowns on the first item.
- **Control windows:** a second window holding only a `ui` block is the standard way to build a control surface for a performance or installation; its values are readable from every window directly, no messaging needed.
- **Hiding:** `ui hide` / `ui show` (and a key, default `Tab` held with a modifier, to be decided) so performances can run clean.

Full widget set for the first stable release: `label`, `button`, `toggle`, `checkbox` (alias of toggle), `slider`, `range` (two-handle slider), `knob`, `number`, `textbox`, `dropdown`, `choice`, `colorpicker`, `xypad`, `progress`, `list` (selectable list), `panel`, `row`, `column`, `tabs`/`tab`, `menu`/`item`, `tip`, `separator`, `image button`. Additions go through this file first.

### 5.9 Style and colour (decided 2026-10-23)

The same style words work at three levels, so users learn one vocabulary.

**1. Set it and it sticks.** Style verbs change the current style until changed again. The style resets at the start of every `draw` frame, so one frame never leaks into the next.

```
fill orange
stroke white
thickness 3
font "Inter" size 24
circle 100 100 50
text "hello" at 20 20
```

**2. Style one element.** The same words as connecting words apply to that element only and leave the current style untouched:

```
circle 100 100 50 fill red stroke white thickness 3
text "title" at 20 20 font "Mono" size 32 fill gray
```

**3. Style a group.** `with` applies a style to everything in its block and restores the previous style afterwards:

```
with fill cyan thickness 2 [
  circle 100 100 50
  rect 200 80 40 40
]
```

**Named styles are records.** A style is plain data (§5.2), usable with `style` on one element or with `with` on a group. No style classes, no style sheets.

```
glow = { fill: cyan, stroke: white, thickness: 2 }
circle 100 100 50 style glow
with glow [ ... ]
```

Words:

- `fill`: colour of areas and text. `no fill` turns it off.
- `stroke`: colour of outlines and lines. `no stroke` turns it off.
- `thickness`: stroke width in pixels (not `strokeWeight`, and not `width`, which already means size).
- `alpha`: transparency, applied to fill and stroke.
- `font`: a font file in the sketch's `assets/` (§4.9) or a system font name; `size` sets text size in pixels; `weight` (`light`, `regular`, `bold`, or a number) is optional.
- `caps`, `joins`, `blend`: as in the parity map (§6).
- Precedence: per-element words override `with` blocks, which override the current style.

**Colours** are accepted anywhere a colour goes:

- Names: the CSS named colours (`red`, `orange`, `teal`, …).
- Hex: `#ff8800`, or `#ff880080` with alpha.
- One number for grey: `fill 0`, `background 30`.
- `rgb r g b`, `hsb h s b`, `oklch l c h`; any of them may be followed by `alpha a`.
- **Range: every colour channel is 0–255** (decided 2026-10-23), including grey, `rgb`, `hsb` and `alpha`: `fill red alpha 128` is half transparent. One rule, familiar to Processing users. The only exception is `oklch`, which follows its standard CSS notation (lightness 0–1, chroma, hue in degrees) because its whole point is matching that standard.
- Values outside 0–255 are clamped, with a gentle warning from the checker when it can see the value at load time.
- Colours are values: `c = rgb 255 136 0`, `mix c blue 0.5`, `c * 0.5` (§5.2 array programming).

**UI elements** accept the same words per widget (`button "stop" fill red`); theme-wide changes use the `ui` verbs in §4.8.

### 5.10 Files, libraries and names (decided 2026-10-23)

Creative coders shouldn't think about modules until they want to share something. What users need to know: "Put more files next to your sketch and they just work together. Write `use "name"` to bring in someone else's code; it's copied into your sketch, so it never breaks. Only when two words clash do you add the library name in front."

**Your own code: one folder, one program.** Every `.roci` file in the sketch folder (not in `assets/`, `libs/` or `output/`) belongs to the same program and sees every other file's verbs and constants, with no import line, no header files and no forward declarations. This follows Odin's model, where all files in a directory form one package. `sketch.roci` is where the program starts: its top-level statements run first, then those of the other files in alphabetical order, and only `sketch.roci` may hold top-level drawing statements in a sketch with no `draw` block. Splitting a sketch into `particles.roci` and `palette.roci` never changes what it does.

**Other people's code: `use`, vendored into the sketch.**

```
use "flocking"                             # short name from the index
use "github.com/someone/noise-tools"       # any git URL

draw [ flock birds ]
```

- `roci get <name or url>`, or the first `roci run` that meets a new `use` line, copies the library into `libs/<name>/` inside the sketch folder, with a small `source` file recording where it came from and which commit. `libs/` is committed to git. Vendoring follows Odin's stance against package managers: a sketch runs offline and keeps running years later, even if the original repository disappears.
- `roci update <name>` (or `roci update` for all) fetches a newer version, shows what changed, and replaces the copy. Nothing ever updates by itself.
- **The index** is a plain git repository mapping short names to git URLs, curated in the spirit of ofxAddons. No central server or registry is needed. Any git URL works without the index.
- **A library is a folder of `.roci` files**, optionally with its own `assets/` (found by name after the sketch's own assets, which always win) and a short `README`. Later (Phase 9) a library can also be an Odin or C extension using the stable verb ABI (§4.7); the `use` line is identical and users can't tell the difference.
- **Visibility.** Every verb a library teaches with `learn`, plus its constants, is available to the sketch. Helpers are kept inside with `hidden learn helper [ … ]`.
- Libraries may `use` other libraries; `roci get` vendors the whole set flat into `libs/`. Two libraries needing different versions of a third is a plain-language error at `roci get` time; `roci` never picks one silently.
- Packaging bundles `libs/` exactly like `assets/` (§4.9).

**Names: flat by default, qualified only on a clash.**

- After `use "flocking"`, its verbs are plain words: `flock birds`, never `flocking.flock birds`.
- **The sketch wins over libraries**, with a warning, so teaching your own `flock` is allowed and always announced.
- **Built-ins can't be redefined** by libraries or sketches: `learn circle [ … ]` is a load-time error suggesting another name.
- **Two libraries defining the same word** is a load-time error that teaches: "Both `physics` and `ui-kit` define `push`. Say which one you mean: `physics.push ball`." The qualified form `library.verb` exists only for this. The checker always knows whether a name is a library or a record, so `physics.push` and `p.x` can't be confused; a variable with the same name as a used library is itself a load-time error.
- `use` and `hidden` are keywords, lowercase like all others (§5.1).

### 5.11 Teaching verbs: `learn` (decided 2026-10-23)

Users extend the language by teaching it new verbs with `learn`, in the spirit of Papert's "teaching the turtle". A taught verb must look and feel exactly like a built-in one.

```
learn double n [
  give n * 2
]

learn star size with points 5 spin 0 [
  turn spin
  repeat points [ forward size  right 720 / points ]
]

x = double 21
star 100
star 100 points 7 spin 15
```

- **Signature.** `learn name param param … [ body ]`. Parameters are plain names; their kinds are inferred (§5.3), never written. The number of required parameters is fixed, so the parser always knows where a call ends (§5.1).
- **Why `learn` and not Logo's `to`:** it reads as teaching the computer a word, and it frees `to` to be only a connecting word (`for i from 1 to 10`, `add x to particles`), removing an ambiguity.
- **Optional parameters with defaults** follow `with` in the header: `with points 5 spin 0`. At the call site they work exactly like built-in connecting words (`star 100 points 7`), in any order, each optional. Inside a `learn` header `with` introduces defaults; as a statement it opens a style group (§5.9). The two never appear in the same position, so they can't be confused.
- **Results are explicit: `give`.** `give value` hands a value back and ends the verb. There is no implicit "last expression" result: adding a line at the end of a verb can never silently change what it gives back.
- **`stop`** ends a verb early without a value, as in Logo.
- **Two kinds of verb, checked at load time.**
  - A verb containing `give` can be used in expressions: `x = double 21`.
  - A verb without `give`, like `star`, is a statement. `x = star 100` is an error that teaches: "`star` draws but doesn't give back a value."
  - If some paths through a verb `give` and others reach the end without giving, that's an error naming the path: "When `n` is negative, `double` reaches its end without `give`. Add a `give` there too." No hidden zero values come out of verbs.
  - All `give`s in one verb must give the same kind of value (§5.3).
  - Calling a giving verb as a statement and dropping its result is a warning, since it's usually a mistake.
- **One value out.** Several results come back as a record: `give { min: a, max: b }`, then `r.min`. No tuples.
- **Recursion** is allowed (trees, fractals, L-systems, as in Logo).
- **Verbs see their parameters, their own local names, and the sketch's top-level names and constants.** Assigning a name inside a verb that doesn't exist at top level creates a local; assigning a top-level name changes it. The checker warns when a local name hides a top-level one.
- **Sharing (decided 2026-10-23).** Numbers, vectors, colours and text are copied when passed or assigned. Lists and records are shared: a verb that changes a record changes the caller's record, which is what makes `learn step p [ p.pos = p.pos + p.vel ]` work, and what Processing users expect from objects and arrays. `b = a` with a record also shares; `b = copy a` makes an independent copy. Passing a constant (§5.1) to a verb that changes it is a load-time error.
- `learn`, `give`, `stop` and `with` are keywords, lowercase like all others (§5.1).

### 5.12 Implementation notes

- Hand-written lexer and recursive-descent parser in Odin (for error quality), producing an AST with full source spans.
- Checker and type inference run before anything executes, producing the typed IR (§4.7). Spans are preserved into the IR so runtime errors, and the source map for generated Odin, point at `.roci` lines.
- The interpreter executes the typed IR directly (no separate AST walker). Keep it simple and correct; it is the reference implementation that the code generator is tested against.
- Use Odin's allocators deliberately: an arena per frame for temporary values, a long-lived allocator for sketch state, so hot reload can discard and rebuild cleanly.
- The interpreter must run on iOS without a JIT (for the possible on-device app; released sketches don't use it).

---

## 6. Feature parity map

Goal: everything the core and standard add-ons of Processing, openFrameworks (0.12.1) and Cinder do, in rocinante words. The rows below are a first pass from the official references. **Phase 0 includes verifying and completing this table against those references; update it here, in place.**

| Area | Processing | openFrameworks | Cinder | rocinante (draft verbs) | Phase |
|---|---|---|---|---|---|
| Window, app loop | `size`, `fullScreen`, `windowMove`, `windowTitle`, `windowResizable`, `frameRate`, `settings`, `loop`/`noLoop`, `redraw`, `exit` | `ofAppRunner`, `ofBaseApp`, `ofMainLoop`, multi-window via `ofCreateWindow` | App, Window | `window`, `title`, `fullscreen`, `fps`, `draw`, `pause`, `resume`, `quit` | 1 |
| Display | `displayWidth/Height`, `displayDensity`, `pixelDensity`, `cursor`, `noCursor`, `smooth` | screen size, `ofHideCursor` | Display | automatic HiDPI, `screen.width`, `cursor`, `smooth` (on by default) | 1 |
| 2D primitives | `arc`, `circle`, `ellipse`, `line`, `point`, `quad`, `rect`, `square`, `triangle` | ofGraphics draw functions | 2D Graphics | same names | 1 |
| Style | `fill`, `noFill`, `stroke`, `noStroke`, `strokeWeight`, `strokeCap`, `strokeJoin`, `ellipseMode`, `rectMode`, `push`/`pop` | `ofSetColor`, `ofFill`, `ofSetLineWidth` | gl::color | `fill`, `no fill`, `stroke`, `no stroke`, `thickness`, `alpha`, `caps`, `joins`; per-element style words; `with … [ ]` and `push [ ]` scopes; named styles as records (§5.9) | 1 |
| Color | `color`, `colorMode`, `lerpColor`, `red`/`green`/`blue`/`alpha`, `hue`/`saturation`/`brightness`, `background`, `clear` | `ofColor` | Color | CSS names (`red`), hex (`#ff8800`), grey number, `rgb`, `hsb`, `oklch`, `alpha`, `mix`, `background`, `clear`; channels 0–255 (§5.9) | 1 |
| Transform | `translate`, `rotate`, `rotateX/Y/Z`, `scale`, `shearX/Y`, `applyMatrix`, `pushMatrix`/`popMatrix`, `resetMatrix` | `ofTranslate`, `ofRotate`, `ofScale`, `ofNode` | gl::translate etc. | `move`, `turn`, `grow`, `shear`, block-scoped with `push [ ]` | 1 |
| Shapes and curves | `beginShape`/`vertex`/`endShape`, contours, `bezier`, `bezierVertex`, `curve`, `curveVertex`, `quadraticVertex`, detail/tightness, `PShape`, `createShape` | `ofPath`, `ofPolyline` | Path2d, Shape2d | `shape [ ]`, `vertex`, `bezier`, `curve`, `hole [ ]`, `path`, `polyline` with resample/smooth/simplify | 1 to 3 |
| Turtle | (none) | (none) | (none) | `forward`, `back`, `left`, `right`, `pen up/down`, `home`, 3D turtle | 2 |
| Math | `map`, `lerp`, `constrain`, `dist`, `mag`, `norm`, trig, `degrees`/`radians`, `PVector`, constants `PI`/`TAU` | ofMath, glm | Vec, Matrix | `map`, `mix`, `clamp`, `dist`, `vec`, trig, `pi`, `tau` | 1 |
| Randomness, noise | `random`, `randomGaussian`, `randomSeed`, `noise`, `noiseSeed`, `noiseDetail` | `ofRandom`, `ofNoise` | Rand, Perlin | `random`, `gaussian`, `seed`, `noise` (Perlin, simplex, 1 to 4D), `fbm` | 1 |
| Time, animation | `millis`, `second`…`year`, `frameCount`, `delay` | `ofGetElapsedTimef`, `ofGetFrameNum` | Timeline, Tween, easing | `time`, `frame`, `clock`, `tween`, `ease`, `every` | 2 |
| Input | mouse vars and callbacks, `pmouseX`, keyboard vars and callbacks, `mouseWheel` | mouse, key, touch, drag-and-drop events | Mouse/Key/Touch events | `mouse`, `pmouse`, `key`, `touches`, `wheel`, `on …`, dropped files | 1 to 2 |
| Events, messages | (none in core) | `ofEvent`, `ofSendMessage` | signals | `send`, `on … receive`, custom events | 2 |
| Typography | `text`, `createFont`, `loadFont`, `textFont`, `textSize`, `textAlign`, `textLeading`, `textWidth`, `textAscent`/`Descent` | `ofTrueTypeFont` | TextBox | `text`, `font`, `align`, `leading`, `measure`, text along a path, text to shapes | 3 |
| Images, pixels | `PImage`, `loadImage`, `requestImage`, `image`, `imageMode`, `tint`, `get`/`set`, `pixels[]`, `filter`, `mask`, `blend`, `copy` | `ofImage`, `ofPixels`, `ofTexture` | Surface, Channel, ImageIo | `image`, `load`, `tint`, `pixel`, `pixels`, `filter`, `mask`, `crop`, `resize` (GPU-side) | 3 |
| Offscreen, blending, clipping | `createGraphics`, `PGraphics`, `blendMode`, `clip`/`noClip` | `ofFbo` | gl::Fbo | `canvas`, `draw into c [ ]`, `blend`, `clip` | 3 |
| Shaders | `PShader`, `loadShader`, `shader`, `resetShader` | `ofShader` | GlslProg | `shader` (hot-reloaded), post effects (`blur`, `glow` …) as built-ins | 3 |
| 3D primitives, meshes | `box`, `sphere`, `sphereDetail` | `of3dPrimitive`, box/cone/cylinder/icosphere/plane/sphere, `ofMesh` | geom:: | `box`, `sphere`, `cone`, `cylinder`, `plane`, `icosphere`, `torus`, `mesh`, `wireframe` | 4 |
| Camera | `camera`, `perspective`, `ortho`, `frustum`, `beginCamera`, `screenX/Y/Z`, `modelX/Y/Z` | `ofCamera`, `ofEasyCam`, `ofNode` | CameraPersp, CameraUi | `camera`, `orbit` (default), `look at`, `ortho`, `to screen`, `to world` | 4 |
| Lights, materials | `lights`, `ambientLight`, `directionalLight`, `pointLight`, `spotLight`, falloff, specular, `ambient`, `emissive`, `shininess`, `specular` | `ofLight`, `ofMaterial` | gl lighting via shaders | `light` (ambient/sun/point/spot), `material` (PBR by default), `shadows` | 4 |
| Model and vector import | `loadShape` (SVG, OBJ) | ofxAssimpModelLoader, ofxSvg | ObjLoader | `model "x.glb"` (glTF first, `vendor:cgltf`), `svg` | 4 |
| Sound | (Sound library) | `ofSoundPlayer`, `ofSoundStream`, `ofSoundBuffer` | audio:: node graph | `sound`, `play`, `loop`, `volume`, `synth`, `listen` (mic), `fft`, `level`, effects | 5 |
| MIDI, OSC | (libraries) | ofxOsc (core add-on), ofxMidi (contributed) | (blocks) | `midi in/out`, `osc send/listen` | 5 |
| Files, data | `loadStrings`, `loadBytes`, `loadJSON*`, `loadTable`, `loadXML`, `save*`, `createWriter`, `selectInput`/`Output`/`Folder` | `ofFile`, `ofDirectory`, `ofJson`, `ofXml`, system dialogs | DataSource | `load`, `save` (format from extension), `ask file`, `ask folder`, `files in` | 6 |
| Network | (Net library) | ofxNetwork, URL loader | (blocks) | `fetch`, `udp`, `tcp`, `websocket` | 6 |
| Serial, hardware | (Serial library) | `ofSerial`, `ofArduino` (Firmata) | (blocks) | `serial`, `firmata` | 6 |
| Video, camera input | (Video library) | `ofVideoPlayer`, `ofVideoGrabber` | video:: | `movie`, `webcam` (SDL3 camera API) | 6 |
| UI, parameters | (contributed: controlP5 and others) | ofxGui, `ofParameter`, ofxImGui | params::, Cinder-ImGui | built-in `ui [ ]` blocks with `button`, `slider`, `range`, `knob`, `toggle`, `number`, `textbox`, `dropdown`, `choice`, `colorpicker`, `xypad`, `list`, `progress`, `label`, panels, rows, tabs, menus, tooltips; values remembered per sketch; screen-reader support (§4.8, §5.8) | 3 |
| Sensors, gamepads | (none) | iOS/Android add-ons | (platform) | `tilt`, `compass`, `gamepad` via SDL3 | 6 |
| Output, export | `save`, `saveFrame`, `beginRecord`/`beginRaw` (PDF, SVG) | screen grab, Cairo renderer | ImageIo | `save "x.png"`, `record` (frames/video), `export svg`/`pdf` | 3 and 6 |
| Computer vision, depth | (OpenCV library) | ofxOpenCv, ofxKinect | (blocks) | extension libraries, after the first stable release | 9 |

---

## 7. The `roci` tool

```
roci new <name>          create a sketch folder (§4.9) with git and an optional Git LFS setup
roci init                the same, inside an existing folder; never overwrites
roci add <path>          copy a file into the right assets/ subfolder
roci get <name|url>      vendor a library into libs/ (§5.10)
roci update [name]       fetch newer versions of vendored libraries, showing what changed
roci run [file]          interpret with live reload (default: sketch.roci); needs nothing installed
roci check [file]        parse, check and infer types without running
roci fmt [file]          format a sketch in the house style (§5.1); no options
roci package <target>    compile to native code and package; targets: linux, freebsd, macos, windows, android, ios
roci doctor              check what each package target needs on this machine and print install steps
```

Packaging notes:

- `roci package` always generates Odin and builds it with the user's toolchain (§4.7). The user never sees Odin code or compiler output unless they open the saved build log in `output/`; failures are reported in rocinante's plain style, with `roci doctor` as the next step.
- **Toolchain** (user-installed, §4.7): Odin at the pinned version everywhere; MSVC and the Windows SDK on Windows; the Xcode command-line tools on macOS; clang on Linux and FreeBSD.
- **iOS**: App Store distribution requires a Mac with full Xcode and an Apple Developer Program account. `roci package ios` drives Odin and Xcode's command-line tools on a Mac; from Linux or FreeBSD it must hand the build to a Mac (local network or CI). `roci doctor` explains this in plain words.
- **Android**: `roci` fetches and manages the SDK and NDK on first use and keeps the signing keystore out of the user's way.
- **FreeBSD**: Odin is available as the `lang/odin` port. Produce a package of the sketch; later, a port of `roci` itself (`poudriere bulk -t`).
- Every target bundles the compiled sketch, all of `assets/` and `libs/`, `ui.toml` and compiled shaders (§4.9). No network access needed at runtime.

---

## 8. Phases

Each phase ends with a demo sketch, passing CI on all desktop targets and an update to this file.

### Phase 0: Foundations
- Create the repository layout (§4.2), the Odin build script with its `ci` command, a `README.md` (kept current: status, contributing, and build instructions once there is something to build), a `LICENSE` file with the 0BSD text and `SPDX-License-Identifier: 0BSD` headers.
- Set up the Git workflow and both pipelines (§11): `tools/hooks/` (pre-push and commit-msg), the `ODIN_VERSION` file, `.gitlab-ci.yml` on ORION's runner, `.github/workflows/ci.yml`, the `github` remote, protection of `main` in GitLab, and the release checklist.
- Add a CI licence check: a script that reads every library in `vendor/` and every `vendor:` package we use, and fails on GPL/LGPL code that would ship (§3).
- Pick and record the pinned Odin release. Confirm Odin's supported targets for every platform we need (x86_64 and arm64 desktop on all four OSes, Android and iOS subtargets) and record gaps.
- Check the state of `vendor:sdl3` and its satellites against the latest SDL3 releases; decide per library whether to use `vendor:` or our own bindings (§3).
- Check and reserve names (`rocinante`, `roci`); confirm the name doesn't collide with an active creative-coding project.
- Verify every "candidate" dependency in this file against its official docs: platform support (FreeBSD, iOS and Android included), licence, maintenance. Record results here.
- Verify and complete the parity map (§6) against the Processing, openFrameworks and Cinder references.
- **Spike 1, desktop**: SDL3 GPU device + window + clear colour from Odin on every desktop target, including FreeBSD with Vulkan through Mesa (FreeBSD is not on SDL's official list for the Vulkan GPU backend).
- **Spike 2, mobile**: an Odin + SDL3 program drawing a circle on a real iPhone and a real Android phone. This is the riskiest assumption in the plan; if it fails, stop and rethink before Phase 1.
- **Spike 3, code generation**: a hand-written typed-IR fragment (the circle program and a small loop) turned into Odin source and built with the user-installed Odin on all four desktop OSes, with `roci doctor` detecting each toolchain.
- **Spike 4, UI**: Dear ImGui through dear_bindings, `imgui_impl_sdl3` and `imgui_impl_sdlgpu3` from Odin: a slider, button and text box, IME composition in the text box, and one AccessKit adapter exposing them to a screen reader via accesskit-c.
- **Exit**: green pipelines on GitLab (Arch) and GitHub (Ubuntu); the four spikes working on their platforms (checked locally where CI doesn't reach); parity map complete; Odin version and target coverage recorded.

### Phase 1: Window and 2D core (Odin API)
- App loop, `window` with optional position, multiple windows, HiDPI.
- Internal shader pipeline: HLSL → SDL_shadercross → embedded SPIR-V/MSL/DXIL.
- Command list, batching, instancing, geometry cache.
- 2D primitives, style, colour, transforms, basic shapes (including the tessellation decision, §4.3), math, random, noise, mouse and keyboard.
- First version of the stable verb ABI (§4.7), with its C ABI.
- Golden-image test harness (render offscreen, compare against reference PNGs with tolerance).
- Mobile: the Phase 1 examples running on an iOS device and an Android device.
- **Exit**: `examples/circle.odin` and a 100,000-circle benchmark at 60 fps; two windows exchanging a message; runs on iOS and Android.

### Phase 2: The language
- Lexer, parser, checker, type inference, typed IR, interpreter (§4.7, §5).
- Inference error messages written before the inference rules are final (§5.3).
- `circle 100 100 50` as a whole program.
- `roci run` with file watching, hot reload with state preservation, error overlay.
- Sketch folders (§4.9): `roci new`, `roci init`, `roci add`, git and optional Git LFS setup, asset lookup by name, the outside-`assets/` error, live asset reload.
- Error message catalogue with tests, including bracket mismatches located by indentation (§5.1) and every `learn`/`give`/`stop` rule (§5.11).
- `roci fmt`: formatting is idempotent (formatting twice changes nothing) and never changes behaviour (formatted and unformatted sketches produce identical frames).
- Turtle, events, timers, tweens, taught verbs (`learn`, `give`, `stop`, `with` defaults, sharing rules, §5.11), window messaging.
- Multi-file sketches and `.roci` libraries (§5.10): `use`, `hidden`, `roci get`, `roci update`, `libs/` vendoring, clash rules and their error messages. The public index starts small in Phase 9.
- **Exit**: every Phase 1 example rewritten in `.roci`; every example infers fully (no boxed fallbacks) or the fallback is justified here; a newcomer test (someone who has never seen rocinante makes a moving sketch in 15 minutes, observed and written up here).

### Phase 3: Text, UI, images, canvases, shaders
- Text with SDL3_ttf GPU engine (or the alternative chosen in Phase 0).
- `ui` with the full widget set (§5.8) on Dear ImGui: immediate-mode `ui [ ]` blocks, automatic layout, focus and keyboard navigation, text input with IME and on-screen keyboards, touch sizing, theme, value persistence, custom widgets.
- The AccessKit bridge (§4.8) on Windows, macOS, Linux, FreeBSD (verify), Android and iOS.
- Images and pixels, offscreen canvases, blend modes, clipping, masks.
- User shaders with hot reload; built-in post effects.
- Export: PNG, frame sequences, SVG/PDF.
- **Exit**: ports of ten classic Processing examples, pixel-compared where meaningful; a two-window sketch (control window with every widget, canvas window reacting live) working with mouse, touch, keyboard only, and a screen reader on at least macOS (VoiceOver), Windows (NVDA or Narrator) and Linux (Orca); text boxes accepting non-Latin input through an IME.

### Phase 4: 3D
- Primitives, meshes, camera with default orbit, nodes, lights, PBR materials, shadows.
- glTF import (`vendor:cgltf`), SVG import.
- 3D turtle.
- **Exit**: a 3D generative sketch with lights and an imported model running on all six platforms.

### Phase 5: Sound
- SDL3 audio out and in, playback and streaming (miniaudio decoders plus `stb_vorbis`, §4.6), our own synthesis and effects, FFT and level analysis.
- MIDI (`vendor:portmidi` or our own backends) and OSC (our own), including the FreeBSD MIDI decision.
- Audio-reactive visuals with zero setup (`level`, `fft` usable directly in `draw`).
- **Exit**: an audio-visual sketch controlled by a MIDI controller; latency measured and recorded here.

### Phase 6: The world outside
- Files and data formats, dialogs, network, serial and Firmata, webcam, video playback, sensors, gamepads, video recording.
- **Exit**: an installation-style sketch (camera in, OSC out, UI control window, runs for 24 hours without leaks).

### Phase 7: The compiler
- `codegen`: typed IR → readable Odin source, built with the user's Odin together with the core, on all four desktop OSes.
- Lists of same-shaped records as contiguous arrays (or `#soa`); vector maths as Odin array programming; boxed fallback as tagged unions.
- Source mapping from packaged sketches back to `.roci` lines (§4.7).
- `roci doctor` complete for desktop toolchains.
- Back-end equivalence suite (§9) running every example in both modes in the Linux pipeline, and locally on the other platforms before each release.
- **Exit**: every example produces identical frames interpreted and compiled; the particle benchmark (100,000 records updated and drawn per frame) holds 60 fps compiled on a mid-range laptop, with the interpreted figure recorded here for comparison.

### Phase 8: Packaging
- `roci package` for all six targets (generate, build, bundle, sign where needed); `roci doctor` for every target.
- Mobile behaviour for multiple windows, touch-first defaults, orientation.
- **Exit**: the same sketch file packaged and installed on all six platforms by someone other than Fabrizio, following only the docs, starting from a machine with nothing installed except what `roci doctor` asked for.

### Phase 9: Community and tooling
- Language server (diagnostics and inferred-type hovers reuse the checker), syntax highlighting for nvim, Helix, VS Code and Zed.
- Documentation site where every verb has a runnable example.
- Nature of Code and Generative Design example ports.
- Extension mechanism (Odin or C libraries that add verbs through the stable verb ABI, usable with the same `use` line, §5.10), then computer vision and depth cameras as extensions.
- The public library index (§5.10), with a handful of first libraries.
- **Exit**: the first stable release (§11).

---

## 9. Testing

- Language: parser, checker and inference unit tests; one test per error message in `tests/errors/`.
- Formatter: every example and test sketch is run through `roci fmt` twice; the second pass must change nothing, and the formatted sketch must parse to the same typed IR as the original.
- Rendering: golden-image tests per verb and per backend where CI allows.
- **Back-end equivalence**: every `.roci` example and test runs interpreted and compiled; frames are compared pixel for pixel (exact match, with a fixed random seed and fixed time step) and printed output byte for byte. Any mismatch fails the pipeline. From Phase 7 on, this is part of the full pipeline on `main`. Compiled runs use the pinned Odin release.
- UI: scripted input tests (simulated mouse, touch, keyboard and text input events) for every widget, checking returned values and rendered frames; keyboard-only navigation tests; AccessKit tree snapshots per widget and per action.
- Sketch folders: `roci new`/`init` tested with and without git and Git LFS installed; asset lookup, duplicate-name and outside-`assets/` errors; a packaged sketch run from a different machine path finds every asset.
- Libraries: multi-file sketches behave identically to the same code in one file; `use` with index names and git URLs; offline runs from vendored `libs/`; every clash rule produces its error message.
- Toolchain: `roci doctor` tested on machines (or CI images) with each toolchain piece missing, wrong version and present.
- Performance: benchmark sketches tracked in CI in both modes; a regression of more than 10% fails the build.
- Platforms: Linux in the pipeline on every commit to `main`; every other target through the release checklist before each tag, and at least once per phase (§11).
- Golden images run on Mesa's software Vulkan driver (lavapipe) in the pipeline, so results don't depend on the machine's GPU.

---

## 10. Decisions and open questions

### Decided

- **2026-10-22, Licence: Zero-Clause BSD (SPDX `0BSD`).** The most permissive OSI-approved licence: an unconditional grant to use, copy, modify and distribute for any purpose, plus a warranty disclaimer, with no attribution requirement. Applies to the core, the language, `roci`, the docs and all examples. Dependency rules are in §3.
- **2026-10-22, Blocks: `[ ]`**, as in Logo. Not `end`.
- **2026-10-22, Paradigm: procedural and data-oriented**, verbs on plain data, no objects; Odin-inspired array programming, verb groups, useful zero values, no exceptions, implicit style context; capturing blocks and a light functional layer for lists. Full text in §5.2.
- **2026-10-22, Typing: inferred static typing**, no type syntax for users, plain-language conflict errors, boxed fallback where inference cannot decide. Full text in §5.3.
- **2026-10-23, Implementation language: Odin** (replaces Rust). Core and `roci` in Odin; `vendor:` libraries first, our own bindings to the latest upstream when they lag; C and C++ libraries through Odin's foreign system; fixes contributed upstream. Full text in §3 and §4.
- **2026-10-23, Execution: interpreted in development, compiled ahead of time for release by generating Odin source** built with the user-installed Odin compiler (replaces the Cranelift plan). One shared front end and typed IR; no bytecode VM, no JIT. Full text in §4.7.
- **2026-10-23, Toolchain for packaging is user-installed**: Odin (pinned version), MSVC on Windows, Xcode on Apple platforms, clang on Linux and FreeBSD; `roci doctor` guides installation; `roci run` needs none of it. Android SDK/NDK stay managed by `roci`. Full text in §4.7; non-negotiable 2.
- **2026-10-23, UI is first class**: immediate-mode widget verbs in `ui [ ]` blocks, values remembered per sketch, keyboard, touch, IME and screen-reader support. Full text in §4.8 and §5.8; non-negotiable 10.
- **2026-10-23, UI engine: Dear ImGui** (replaces egui) with its official SDL3 and SDL_GPU backends, Odin bindings generated through dear_bindings. Full text in §4.8.
- **2026-10-23, Screen readers are required for the first stable release**, through our own AccessKit bridge for Dear ImGui built from rocinante's widget records, using accesskit-c. Full text in §4.8.
- **2026-10-23, Audio stack without Rust**: miniaudio decoders plus `stb_vorbis`, our own DSP and OSC, `vendor:portmidi` as the MIDI candidate. This also removes the MPL-2.0 dependency (Symphonia). Full text in §4.6.
- **2026-10-23, Name**: always lowercase, rocinante (§3).
- **2026-10-23, Indentation: free, never meaningful**; `roci fmt` keeps sketches tidy and the checker uses indentation only to explain bracket mistakes. Full text in §5.1.
- **2026-10-23, Style: one vocabulary at three levels** (sticky style verbs, per-element style words, `with [ ]` groups) plus named styles as records; `thickness` for stroke width. Full text in §5.9.
- **2026-10-23, Colour range: 0–255 for every channel** (grey, `rgb`, `hsb`, `alpha`); `oklch` alone follows its CSS notation. Full text in §5.9.
- **2026-10-23, Case: every keyword and built-in name is lowercase; all-capital user names are deeply immutable constants.** Case-sensitive, with a warning for names differing only by case. Full text in §5.1.
- **2026-10-23, Assets: one `assets/` folder, found by name**; only `assets/` is bundled; runtime-picked files are the exception; output goes to `output/`. Full text in §4.9.
- **2026-10-23, Scaffolding: `roci new` / `roci init`** create a git repository with the folder structure and offer Git LFS. Full text in §4.9.
- **2026-10-23, Remembered UI values are committed to git** in `ui.toml`. Full text in §4.9.
- **2026-10-23, Modules: one folder is one program** (no imports for your own files); other code through `use`, vendored into `libs/` and committed; flat names, qualified `library.verb` only on clashes; `hidden` for library helpers. Full text in §5.10.
- **2026-10-23, Verbs are taught with `learn`** (replaces Logo's `to`, which stays a connecting word): `learn name params [ ]`, optional parameters with `with` defaults, explicit `give` for results, `stop` for early exit; no implicit last-expression result; one value out (records for several). Full text in §5.11.
- **2026-10-23, Git: no `devel` branch**; short feature branches rebased and merged fast-forward into `main`; a local pre-push check stands in for staging. Full text in §11.
- **2026-10-23, Commits never mention AI**; Claude Code attribution off and a `commit-msg` hook as a safety net. Full text in §3 and §11.
- **2026-10-23, CI on Linux only**: GitLab on ORION (fast check on merge requests, full pipeline on `main`, release on tags) and GitHub (full pipeline on `main`, release on tags), pushed to GitHub by hand about twice a week; other platforms checked locally before each release. Full text in §11; non-negotiable 8.
- **2026-10-23, Versions: calendar-based `YYYY.MINOR.MICRO`** (replaces semantic versioning); tags `vYYYY.MINOR.MICRO`; the first stable release replaces the old "1.0" milestone. Full text in §11.
- **2026-10-23, Sharing: numbers, vectors, colours and text are copied; lists and records are shared**; `copy` makes an independent copy. Full text in §5.11.

### Open

Decide these with Fabrizio; move each to "Decided" with the date.

1. User shader language: HLSL (one language, compiled by SDL_shadercross), WGSL, or a tiny rocinante shader dialect compiled to HLSL.
2. Language name: is the language also "rocinante", or does it get its own name?
3. Web target: SDL3 GPU has no browser backend. Decide whether sharing sketches on the web matters for the first stable release.
4. Hot-reload state rules (§5.5).
5. Names for the list verbs in §5.2 (keep matching, transform each, fold, sort by). They must read naturally in a sentence and must not clash with Processing names users already know (`map`, `filter`).
6. Video playback backend: platform media APIs versus FFmpeg (FFmpeg's licensing conflicts with the §3 policy unless it is an optional, user-installed component).
7. Core delivery for `roci package`: ship the core as Odin source compiled together with each sketch (simplest, best optimisation, slower first build) or as prebuilt per-target libraries (faster builds, more release work). C/C++ dependencies (Dear ImGui, accesskit-c, SDL3) ship prebuilt per target either way.
8. Record-shape inference rules (§5.3): how fields added after creation, records from loaded JSON, and messages between windows get their shapes.
9. UI details: the hide/show key, and whether `ui` blocks may also appear inside `draw` for widgets attached to things on the canvas.
10. Library index (§5.10): where it is hosted, who curates it, and the rules for getting a library listed.
11. Odin/C extension libraries (§5.10, Phase 9): how they are distributed (source compiled at packaging time, or prebuilt per target) and how `roci run` loads them without a toolchain.
12. Verb groups with different argument counts (§5.2): the parsing rule that decides where a call like `circle p 50 …` ends without commas, using inferred kinds or requiring parentheses, and the error when it can't be decided. Settle before the parser is written in Phase 2.
13. accesskit-c on Android and iOS: whether prebuilt releases exist, and if not, how the core build produces them (§4.8).

---

## 11. Git workflow and CI (decided 2026-10-23)

**Branches.**

- `main` is the only long-lived branch and is always meant to work. There is no `devel` or staging branch.
- Work happens on short-lived branches named by kind: `feat/…`, `fix/…`, `docs/…`, `spike/…` (Phase 0 spikes), `refactor/…`.
- Before merging, rebase the branch onto `main`, then merge fast-forward only (`git merge --ff-only`, or a GitLab merge request with the project's merge method set to fast-forward). History stays linear and keeps every small commit. Delete the branch after merging.
- `main` is protected in GitLab: no force pushes.

**Commits.**

- Small and frequent. One idea per commit.
- Message: imperative, present tense, prefixed by the Odin package or area it touches: `gfx: batch circles with instancing`, `lang: explain missing give on some paths`, `docs: record odin version`. The name is lowercase everywhere (§3).
- **No mention of AI, Claude or any assistant**, in messages, branch names, tags or release notes; no `Co-Authored-By` trailers, no session links. Two layers make this reliable:
  - in Claude Code, `"attribution": { "commit": "", "pr": "" }` in `~/.claude/settings.json` on every machine used (the `attribution` key replaces the deprecated `includeCoAuthoredBy`);
  - a `commit-msg` hook in `tools/hooks/` that removes any `Co-Authored-By` trailer for an assistant address and any session-link line, since an empty `attribution.commit` has been reported not to remove the trailer in some versions.
- Hooks are enabled with `git config core.hooksPath tools/hooks` (done once per clone; `roci`'s contributor docs say so).

**Local check before pushing.**

- The Odin build script has a `ci` command that runs exactly what the pipelines run; nothing lives only in YAML.
- A `pre-push` hook in `tools/hooks/` runs the fast part of it (build, unit and language tests, error-message tests, `roci fmt` check, licence check). The full part (golden images, back-end equivalence, benchmarks) runs in the pipeline.

**Remotes.**

- `origin` is GitLab on ORION (Arch Linux), where all daily work goes.
- `github` is the public mirror. About twice a week: `git push github main --tags`. Pushed by hand, not by GitLab's push mirroring, so GitHub only receives snapshots Fabrizio chose to publish.
- Issues and pull requests from the community arrive on GitHub. A pull request is accepted by fetching its branch locally, merging it through the normal GitLab flow, and pushing to GitHub; the README explains this to contributors.

**Pipelines (Linux only).**

- Both pipelines are thin wrappers: install the pinned Odin (read from the `ODIN_VERSION` file), SDL3 and Mesa's software Vulkan, then call the build script's `ci` command. All logic is in the build script, so the two can't drift apart.
- **GitLab** (`.gitlab-ci.yml`, runner on ORION, Arch Linux):
  - **fast check** on merge requests only (`rules: - if: $CI_PIPELINE_SOURCE == "merge_request_event"`): build, unit and language tests, error-message tests, format and licence checks;
  - **full pipeline** on every commit to `main` (`rules: - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH`): everything in the fast check plus golden images, back-end equivalence and benchmarks;
  - **release** on tags matching `v*`: the full pipeline plus the Linux release artefact.
- **GitHub** (`.github/workflows/ci.yml`, Ubuntu runner): the full pipeline on push to `main`, and the release job on `v*` tags (`on: push: branches: [main]` and `tags: ['v*']`). No merge-request job. Because GitHub runs Ubuntu and ORION runs Arch, every snapshot is tested on two distributions.
- No GPU is needed: golden images render through lavapipe (§9).

**Releases.**

- **Versions are calendar-based: `YYYY.MINOR.MICRO`** (CalVer; the scheme JetBrains IDEs use). `YYYY` is the year of the release, `MINOR` counts feature releases within that year starting at 1, and `MICRO` counts fix releases of that feature release starting at 0. The first release of 2026 is `2026.1.0`, its first fix `2026.1.1`, the next feature release `2026.2.0`, and the first release of 2027 is `2027.1.0`, whatever the count reached in 2026.
- A release is an annotated tag `vYYYY.MINOR.MICRO` on `main` (for example `v2026.1.0`), so the `v*` tag rules of both pipelines apply unchanged.
- The version does not signal compatibility. Releases before the first stable release are marked as previews in their release notes. After it, any change that breaks existing sketches, the stable verb ABI or `ui.toml` is listed at the top of the release notes with the fix for each, and `roci check` explains it in plain words when it meets the old form.
- Before tagging, work through the release checklist (`docs/release-checklist.md`): build and run the examples, golden-image and equivalence suites on FreeBSD, macOS, Windows, iOS and Android, record the results in the checklist's table for that version, and build those platforms' artefacts locally. The Linux artefact comes from the tag pipeline.
- Release notes are written on the tag (GitLab and GitHub releases), not in a separate changelog file.
- Golden-image PNGs stay small and in plain git, not Git LFS, to stay within GitHub's LFS quotas.

---

## 12. References

- Odin FAQ (design rationale for §5.2; MSVC on Windows): https://odin-lang.org/docs/faq/
- Odin install guide (per-OS toolchain requirements): https://odin-lang.org/docs/install/
- Odin vendor library collection: https://pkg.odin-lang.org/vendor/
- Odin releases: https://github.com/odin-lang/Odin/releases
- FreeBSD port lang/odin: https://freshports.org/lang/odin
- SDL3 GPU API: https://wiki.libsdl.org/SDL3/CategoryGPU
- SDL_shadercross: https://github.com/libsdl-org/SDL_shadercross
- SDL3_ttf GPU text engine: https://wiki.libsdl.org/SDL3_ttf/TTF_CreateGPUTextEngine
- SDL3 text input: https://wiki.libsdl.org/SDL3/SDL_StartTextInput and https://wiki.libsdl.org/SDL3/SDL_StartTextInputWithProperties
- Dear ImGui SDL_GPU backend (`imgui_impl_sdlgpu3`): https://flutter.googlesource.com/third_party/imgui/+/refs/heads/master/backends/imgui_impl_sdlgpu3.cpp
- dear_bindings (C API and JSON metadata for Dear ImGui): https://github.com/dearimgui/dear_bindings
- AccessKit (platform adapters): https://github.com/AccessKit/accesskit
- accesskit-c (C bindings): https://github.com/AccessKit/accesskit-c
- Accessible immediate-mode GUIs (discussion of Dear ImGui and AccessKit): https://ziggit.dev/t/accessible-immediate-mode-guis/12210
- miniaudio (public domain or MIT-0; built-in decoders): https://github.com/mackron/miniaudio and https://miniaud.io/docs/manual/index.html
- Processing reference: https://processing.org/reference
- openFrameworks reference: https://openframeworks.cc/documentation/
- Cinder documentation: https://libcinder.org/docs/
- CSS Color 4, named colours (colour names in §5.9): https://www.w3.org/TR/css-color-4/#named-colors
- cargo new / cargo init (model for `roci new` / `roci init`): https://doc.rust-lang.org/cargo/commands/cargo-new.html
- Git LFS (`git lfs install`, `git lfs track`, `.gitattributes`): https://git-lfs.com/
- gofmt's style (model for `roci fmt`): https://go.dev/blog/gofmt
- Elm, Compiler Errors for Humans: https://elm-lang.org/news/compiler-errors-for-humans
- Apple App Review Guidelines (2.5.2): https://developer.apple.com/app-store/review/guidelines/
- nannou (prior art, built on Bevy): https://github.com/nannou-org/nannou
- Calendar Versioning (CalVer, segment names `YYYY`, `MINOR`, `MICRO`): https://calver.org/
- Zero-Clause BSD (OSI): https://opensource.org/license/0BSD
- GitLab CI job rules (`$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH`, merge request pipelines): https://docs.gitlab.com/ci/jobs/job_rules/
- GitHub Actions, events that trigger workflows (push to branches and tags): https://docs.github.com/en/actions/writing-workflows/choosing-when-your-workflow-runs/events-that-trigger-workflows
- Claude Code settings reference (`attribution`): https://code.claude.com/docs/en/settings-reference
- Report that an empty `attribution.commit` didn't remove the trailer: https://claudeissues.com/issue/45137-attribution-commit-does-not-disable-co-authored-by-trailer
