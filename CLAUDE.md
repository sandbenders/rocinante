# CLAUDE.md: rocinante

This file and `docs/design.md` (imported below) are together the single source of truth for rocinante's design, scope and plan. When a decision changes, update the file that holds the section, in place. Do not create other design documents, changelogs of decisions or "notes" files beside them. `MANIFESTO.md` is the public statement of intent; this file is how we build it.

Read `MANIFESTO.md` before starting any work. Every decision below serves it.

---

## 1. What rocinante is

An open-source creative coding framework and language.

- **rocinante (the language)**: a small, Logo-inspired language for sketches. The language, the framework and the project share the one name (decided 2026-10-24). No semicolons, no braces around blocks, one predictable shape. File extension `.roci`.
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
2. **Nothing technical leaks.** Users never see shader formats, GPU backends, lifetimes, threads, types, tensors, compilers, linkers, build systems or signing unless they explicitly go looking. Two exceptions, both outside `roci run`: `roci package` needs a platform toolchain (Xcode, MSVC or clang depending on the platform, which the user installs, plus Odin, which `roci` fetches itself, §4.7), and turning a PyTorch or JAX model into a model rocinante can run needs the official Python converters (§4.10). `roci run` never needs either, and `roci doctor` explains every missing piece in plain words with the exact install steps.
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
- **Odin.** The core and `roci` are written in Odin. Pin one Odin release per rocinante release, recorded in the `ODIN_VERSION` file (the one place the version lives), and upgrade deliberately. Follow Odin's own style and idioms; no Rust or C++ habits.
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
        ┌──────────────────┬───────────┼──────────┬──────────────┬──────────────┐
        ▼                  ▼           ▼          ▼              ▼              ▼
   gfx + ui              audio        io         ml           collide       platform
   (2D/3D, text,        (I/O,        (files,    (LiteRT:      (2D and 3D    (SDL3: windows,
   images, gradients,   playback,    data,      local         overlap,      input, gamepads,
   shaders; Dear ImGui  synthesis,   network,   inference)    contact,      joysticks, events,
   + AccessKit bridge)  MIDI, OSC)   serial,                  ray tests)    camera, sensors)
                                     video)
        │
        ▼
   SDL3 GPU API ──► Vulkan / Metal / D3D12

 roci (cli): new, init, add, get, update, run, check, fmt, package <target>, doctor
```

### 4.2 Source layout (initial)

Odin has no package manager and no workspace file: a package is a directory, and every `.odin` file in it belongs to that package. The repository is one Odin collection.

```
rocinante/
  CLAUDE.md            rules, plan, tool, testing, git and CI (this file)
  MANIFESTO.md
  README.md            what rocinante is, project status, how to contribute (§11)
  LICENSE              0BSD text (§10)
  roci/                public API, prelude, stable verb ABI (package roci)
    platform/          SDL3 wrapper: app loop, windows, input, gamepads, joysticks, events
    gfx/               renderer, batching, tessellation, text, images, shaders
    ui/                UI verbs on Dear ImGui, theme, custom widgets, AccessKit bridge
    audio/             audio graph, playback, synthesis, MIDI, OSC
    io/                files, data formats, network, serial, video (§4.11), camera
    ml/                machine-learning models on LiteRT: loading, inference, built-in tasks (§4.10)
    collide/           collision detection (2D on Box2D, 3D in Odin) and 2D physics on Box2D worlds (§5.13)
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
  docs/                design.md (architecture details, the language, parity map; imported by CLAUDE.md),
                       release checklist and contributor docs
  ODIN_VERSION         the pinned Odin release, read by the build script and both pipelines
  .gitlab-ci.yml       GitLab pipeline (§11)
  .github/workflows/   GitHub pipeline (§11)
```

Package boundaries can change; record the change here.

*§4.3 to §4.11 (rendering, threads, messaging, audio, execution model, user interface, sketch folders, machine learning, video), §5 (the language) and §6 (the feature parity map) live in `docs/design.md`, imported here:*

@docs/design.md

---

## 7. The `roci` tool

```
roci new <name>          create a sketch folder (§4.9) with git and an optional Git LFS setup
roci init                the same, inside an existing folder; never overwrites
roci add <path>          copy a file into the right assets/ subfolder; converts PyTorch and JAX models (§4.10)
roci get <name|url>      vendor a library into libs/ (§5.10)
roci update [name]       fetch newer versions of vendored libraries, showing what changed
roci run [file]          interpret with live reload (default: sketch.roci); needs nothing installed
roci check [file]        parse, check and infer types without running
roci fmt [file]          format a sketch in the house style (§5.1); no options
roci package <target>    compile to native code and package; targets: linux, freebsd, macos, windows, android, ios
roci doctor              check what each package target needs on this machine and print install steps;
                         `roci doctor ml` checks the PyTorch and JAX model converters
```

Packaging notes:

- `roci package` always generates Odin and builds it with the pinned Odin and the user's platform toolchain (§4.7). The user never sees Odin code or compiler output unless they open the saved build log in `output/`; failures are reported in rocinante's plain style, with `roci doctor` as the next step.
- **Toolchain** (§4.7): Odin at the pinned version everywhere, fetched into `roci`'s own cache on first use; MSVC and the Windows SDK on Windows; the Xcode command-line tools on macOS; clang on Linux and FreeBSD.
- **iOS**: App Store distribution requires a Mac with full Xcode and an Apple Developer Program account. `roci package ios` drives Odin and Xcode's command-line tools on a Mac; from Linux or FreeBSD it must hand the build to a Mac (local network or CI). `roci doctor` explains this in plain words.
- **Android**: `roci` fetches and manages the SDK and NDK on first use and keeps the signing keystore out of the user's way.
- **FreeBSD**: Odin is available as the `lang/odin` port. Produce a package of the sketch; later, a port of `roci` itself (`poudriere bulk -t`).
- **Signing and trust** (decided 2026-10-24). macOS packages are signed with a Developer ID and notarised, and Windows packages are signed where the user has a certificate; `roci package` says plainly what SmartScreen or Gatekeeper will still show when they have none. `roci` shows the Android SDK licence and asks for acceptance before fetching it.
- Every target bundles the compiled sketch, all of `assets/` and `libs/`, `ui.toml` and compiled shaders (§4.9). No network access needed at runtime.

---

## 8. Phases

Each phase ends with a demo sketch, a green Linux pipeline (§11), the release-checklist run on the other platforms that the phase touches, and an update to this file.

### Phase 0: Foundations
- Create the repository layout (§4.2), the Odin build script with its `ci` command, a `README.md` (kept current: status, contributing, and build instructions once there is something to build), a `LICENSE` file with the 0BSD text and `SPDX-License-Identifier: 0BSD` headers.
- Set up the Git workflow and both pipelines (§11): `tools/hooks/` (pre-push and commit-msg), the `ODIN_VERSION` file, `.gitlab-ci.yml` on ORION's runner, `.github/workflows/ci.yml`, the `github` remote, protection of `main` in GitLab, and the release checklist.
- Add a CI licence check: a script that reads every library in `vendor/` and every `vendor:` package we use, and fails on GPL/LGPL code that would ship (§3).
- Pick and record the pinned Odin release (`dev-2026-10`, recorded in `ODIN_VERSION` on 2026-10-24). Confirm Odin's supported targets for every platform we need (x86_64 and arm64 desktop on all four OSes, Android and iOS subtargets) and record gaps.
- Check the state of `vendor:sdl3` and its satellites against the latest SDL3 releases; decide per library whether to use `vendor:` or our own bindings (§3).
- Check and reserve names (`rocinante`, `roci`); confirm the name doesn't collide with an active creative-coding project.
- Verify every "candidate" dependency in this file against its official docs: platform support (FreeBSD, iOS and Android included), licence, maintenance. Record results here.
- Verify the parity map (§6) against the Processing, openFrameworks and Cinder references and fix what is wrong; completing the rows is done phase by phase, before each phase starts.
- The LiteRT spike (§4.10: C API from Odin on the four desktop OSes, one iOS and one Android device, a FreeBSD build or the ONNX Runtime decision, PyTorch and JAX conversion with one small model each) moves to the start of Phase 6, because it de-risks only that phase.
- **Spike 1, desktop**: SDL3 GPU device + window + clear colour from Odin on every desktop target, including FreeBSD with Vulkan through Mesa (FreeBSD is not on SDL's official list for the Vulkan GPU backend).
- **Spike 2, mobile**: an Odin + SDL3 program drawing a circle on a real iPhone and a real Android phone. This is the riskiest assumption in the plan; if it fails, stop and rethink before Phase 1.
- **Spike 3, code generation**: a hand-written typed-IR fragment (the circle program and a small loop) turned into Odin source and built with the pinned Odin on all four desktop OSes, with `roci doctor` detecting each toolchain.
- **Spike 4, UI**: Dear ImGui through dear_bindings, `imgui_impl_sdl3` and `imgui_impl_sdlgpu3` from Odin: a slider, button and text box, IME composition in the text box, and one AccessKit adapter exposing them to a screen reader via accesskit-c.
- **Exit**: green pipelines on GitLab (Arch) and GitHub (Ubuntu); the four spikes working on their platforms (checked locally where CI doesn't reach); parity map verified; Odin version and target coverage recorded.

**Phase 0 results so far** (recorded 2026-10-24):

- **Odin:** pinned to `dev-2026-10`. Official archives cover Linux amd64 and arm64, macOS arm64 and Windows amd64 only (§4.7). Homebrew's `dev-2026-07` built against LLVM 23 failed to compile any program; Homebrew's `dev-2026-10` (LLVM 22.1.8) works.
- **`vendor:sdl3`:** its bindings are for SDL 3.4.2, while the latest SDL3 release is 3.4.18 (2026-10-02). Patch releases keep the ABI, so the bindings load the newer library, but functions added after 3.4.2 are missing; the decision between `vendor:` and our own bindings stays open until Phase 1 needs one.
- **Spike 1, macOS arm64:** an SDL3 window and GPU device cleared to a colour from Odin, 181 frames in 3 seconds on the Metal driver, with Homebrew's SDL 3.4.18 library and the 3.4.2 bindings (`spikes/desktop`). FreeBSD 15.1-RELEASE-p5 (Intel Xeon X5675, AMD Radeon RX 580): passes on the Vulkan driver through Mesa, 187 frames in 3 seconds, with SDL 3.4.16 as the library, so Vulkan GPU rendering works on FreeBSD even though SDL doesn't list it. Linux and Windows are still to check.

### Phase 1: Window and 2D core (Odin API)
- App loop, `window` with optional position, multiple windows, HiDPI.
- A minimal text path for the error overlay and debug output (a built-in bitmap or SDF font), so Phase 2 can show errors before Phase 3 brings real text (§4.3).
- Internal shader pipeline: HLSL → SDL_shadercross → embedded SPIR-V/MSL/DXIL.
- Command list, batching, instancing, geometry cache.
- 2D primitives, style, colour, gradients (§5.9), transforms, basic shapes (including the tessellation decision, §4.3), math, random, noise, mouse and keyboard.
- First version of the stable verb ABI (§4.7), with its C ABI.
- Golden-image test harness (render offscreen, compare against reference PNGs with tolerance).
- Mobile: the Phase 1 examples running on an iOS device and an Android device.
- **Exit**: `examples/circle.odin` and a 100,000-circle benchmark at 60 fps; two windows exchanging a message; runs on iOS and Android.

### Phase 2: The language
- Lexer, parser, checker, type inference, typed IR, interpreter (§4.7, §5).
- Inference error messages written before the inference rules are final (§5.3).
- `circle 100 100 50` as a whole program.
- `roci run` with file watching, hot reload with the state rules of §5.5, `Ctrl+R` restart, error overlay.
- Sketch folders (§4.9): `roci new`, `roci init`, `roci add`, git and optional Git LFS setup, asset lookup by name, the outside-`assets/` error, live asset reload.
- Error message catalogue with tests, including bracket mismatches located by indentation (§5.1), missing argument brackets (§5.1, §5.7) and every `learn`/`give`/`stop` rule (§5.11).
- `roci fmt`: formatting is idempotent (formatting twice changes nothing) and never changes behaviour (formatted and unformatted sketches produce identical frames).
- List verbs (`keep`, `skip`, `collect`, `combine`, `find`, `sort … by`, §5.2).
- Turtle, events, timers, tweens, taught verbs (`learn`, `give`, `stop`, `with` defaults, sharing rules, §5.11), window messaging.
- 2D collision detection (§5.13) with its broad phase.
- Multi-file sketches and `.roci` libraries (§5.10): `use`, `hidden`, `roci get`, `roci update`, `libs/` vendoring, clash rules and their error messages. The public index starts small in Phase 9.
- **Exit**: every Phase 1 example rewritten in `.roci`; every example infers fully (no boxed fallbacks) or the fallback is justified here; a newcomer test (someone who has never seen rocinante makes a moving sketch in 15 minutes, observed and written up here), run with two groups that see the same sketches written with one thing per argument and in bare Logo nesting, with the comparison recorded here (§5.1).

### Phase 3: Text, UI, images, canvases, shaders
- Text with SDL3_ttf GPU engine (or the alternative chosen in Phase 0), including copying system fonts into the sketch with the licence check (§4.9).
- `ui` with the full widget set (§5.8) on Dear ImGui: immediate-mode `ui [ ]` blocks, automatic layout, focus and keyboard navigation, text input with IME and on-screen keyboards, touch sizing, theme, value persistence, custom widgets.
- The AccessKit bridge (§4.8) on Windows, macOS, Linux, FreeBSD (verify), Android and iOS.
- Images and pixels, offscreen canvases, blend modes, clipping, masks, image and video fills (§5.9).
- User shaders with hot reload; built-in post effects.
- Export: PNG, frame sequences, SVG/PDF.
- **Exit**: ports of ten classic Processing examples, pixel-compared where meaningful; a two-window sketch (control window with every widget, canvas window reacting live) working with mouse, touch, keyboard only, and a screen reader on at least macOS (VoiceOver), Windows (NVDA or Narrator) and Linux (Orca); text boxes accepting non-Latin input through an IME.

### Phase 4: 3D
- Primitives, meshes, camera with default orbit, nodes, lights, PBR materials, shadows.
- glTF import (`vendor:cgltf`), SVG import.
- 3D collision detection (§5.13).
- 3D turtle.
- **Exit**: a 3D generative sketch with lights and an imported model running on all six platforms.

### Phase 5: Sound
- SDL3 audio out and in, playback and streaming (miniaudio decoders plus `stb_vorbis`, §4.6), our own synthesis and effects, FFT and level analysis.
- MIDI (`vendor:portmidi` or our own backends) and OSC (our own), including the FreeBSD MIDI decision.
- Audio-reactive visuals with zero setup (`level`, `fft` usable directly in `draw`).
- **Exit**: an audio-visual sketch controlled by a MIDI controller; latency measured and recorded here.

### Phase 6: The world outside
- Files and data formats, dialogs, network, serial and Firmata, webcam, video playback and recording (§4.11), sensors, gamepads, joysticks, actions and the `controls` widget (§5.12), video recording.
- 2D physics on Box2D v3 worlds (§5.13).
- Machine learning (§4.10): LiteRT bindings, `predict`, the built-in tasks and their chosen models, `roci add` conversion, `roci doctor ml`.
- **Exit**: an installation-style sketch (camera in, OSC out, UI control window, runs for 24 hours without leaks); a webcam sketch driven by `hands` at full frame rate on all six platforms; a game-style sketch played with two different gamepads, remapped by a player through `controls`.

### Phase 7: The compiler
- `codegen`: typed IR → readable Odin source, built with the user's Odin together with the core, on all four desktop OSes.
- Lists of same-shaped records as contiguous arrays (or `#soa`); vector maths as Odin array programming; boxed fallback as tagged unions.
- Source mapping from packaged sketches back to `.roci` lines (§4.7).
- `roci doctor` complete for desktop toolchains.
- Packaging build time measured on each desktop OS, since the core is compiled with every sketch (§4.7); record it here.
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
- Formatter: every example and test sketch is run through `roci fmt` twice; the second pass must change nothing, and the formatted sketch must parse to the same typed IR as the original. Sketches with bare nested calls are formatted into the bracketed form and checked for identical IR.
- Rendering: golden-image tests per verb and per backend where CI allows.
- **Back-end equivalence**: every `.roci` example and test runs interpreted and compiled; frames are compared pixel for pixel (exact match, with a fixed random seed and fixed time step) and printed output byte for byte. Any mismatch fails the pipeline. From Phase 7 on, this is part of the full pipeline on `main`. Compiled runs use the pinned Odin release.
- UI: scripted input tests (simulated mouse, touch, keyboard and text input events) for every widget, checking returned values and rendered frames; keyboard-only navigation tests; AccessKit tree snapshots per widget and per action.
- Controllers: scripted gamepad and joystick events for every binding kind, remapping through `controls`, and hot-plugging.
- Collision: every shape pair against reference results, including touching edges and zero-size shapes; broad-phase results identical to brute force.
- Machine learning: each built-in task and `predict` on fixed images, run on the CPU with a fixed thread count; outputs compared exactly between interpreted and compiled runs and against stored results.
- Hot reload: every rule in §5.5 (unchanged line keeps its value, changed line re-runs, shape gains and loses fields, constants, a save with an error, `Ctrl+R`).
- Records: shapes taken from JSON files in `assets/`, structural verbs used with several shapes, messages typed from `send` lines.
- Fonts: copying with free, restrictive and unreadable licences; `roci package` refusing a restrictive font.
- Sketch folders: `roci new`/`init` tested with and without git and Git LFS installed; asset lookup, duplicate-name and outside-`assets/` errors; a packaged sketch run from a different machine path finds every asset.
- Libraries: multi-file sketches behave identically to the same code in one file; `use` with index names and git URLs; offline runs from vendored `libs/`; every clash rule produces its error message.
- Toolchain: `roci doctor` tested on machines (or CI images) with each toolchain piece missing, wrong version and present.
- Performance: benchmark sketches tracked in both modes. Timing is gated only on ORION, whose hardware is fixed (lavapipe and shared GitHub runners are too noisy); elsewhere the pipeline compares work counts (draw calls, batches, allocations), which are exact. A timing regression of more than 10% on ORION fails the build.
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
- **2026-10-23, Execution: interpreted in development, compiled ahead of time for release by generating Odin source** built with the pinned Odin compiler that `roci` fetches (replaces the Cranelift plan). One shared front end and typed IR; no bytecode VM, no JIT. Full text in §4.7.
- **2026-10-23, Toolchain for packaging is user-installed, except Odin** (revised 2026-10-24: `roci` fetches the pinned Odin into its own cache, checks its checksum, and on FreeBSD uses the `lang/odin` port when the version matches): MSVC on Windows, Xcode on Apple platforms, clang on Linux and FreeBSD; `roci doctor` guides installation; `roci run` needs none of it. Android SDK/NDK stay managed by `roci`. Full text in §4.7; non-negotiable 2.
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
- **2026-10-23, One thing per argument**: each verb argument is a single item (number, text, name, field, literal or bracketed group); full expressions after `=`, `give`, in conditions and between literal commas; `roci fmt` adds missing brackets; no pipes, dot calls or argument commas. Vectors are `{ a, b }` literals (the `vec` verb is gone); `random from … to …`, `anywhere` and `pick` cover common random cases. Verb-group shapes are chosen by count, then kinds. Full text in §5.1 and §5.2.
- **2026-10-24, Machine learning out of the box**: local inference on LiteRT (Apache-2.0) through its C API; `.tflite` and `.litertlm` run directly, PyTorch and JAX models through the official converters at `roci add` time; built-in tasks (`poses`, `hands`, `faces`, `objects`, `labels`, `cutout`) and `predict`; never blocks a frame; no OpenGL path; inference only. Full text in §4.10; non-negotiable 2.
- **2026-10-24, Asset folders**: `3d-models/` and `ml-models/` replace `models/`, plus `videos/`; folder names lowercase. Full text in §4.9.
- **2026-10-24, System fonts are copied into `assets/fonts/`** when their licence allows; otherwise used locally with a teaching message, and never packaged. Full text in §4.9.
- **2026-10-24, Game controllers**: gamepads, joysticks, actions with `bind`, player remapping through the `controls` widget saved in `ui.toml`. Full text in §5.12.
- **2026-10-24, Gradients**: a list of colours in `fill`, `stroke` or `background`, with `angle`, `stops`, `as linear`/`radial`/`conic` and `in rgb`/`oklch`; Oklab mixing by default; `gradient` makes a gradient value. Full text in §5.9.
- **2026-10-24, Image fills**: images, video, canvases and the webcam fill any shape, which acts as a mask; modes `as cover` (default), `fit`, `stretch`, `tile`, `center`. Full text in §5.9.
- **2026-10-24, Collision detection built in**: shapes as records, `touching`, `contact`, `hits`, `inside`, `cast`; Box2D v3 collision functions for 2D, our own Odin tests for 3D. Full text in §5.13.
- **2026-10-24, User shaders are HLSL**, translated at run time by SDL_shadercross for hot reload and compiled offline for packaging; a rocinante shader dialect is on the roadmap. Full text in §4.3.
- **2026-10-24, The language is called rocinante too.** Full text in §1.
- **2026-10-24, No web target for now**; it is on the roadmap (README.md).
- **2026-10-24, The core ships as Odin source**, compiled with each sketch by `roci package`; C and C++ dependencies ship prebuilt per target. Full text in §4.7.
- **2026-10-24, UI hiding and placement**: the backtick key hides and shows the UI (three-finger tap on touch devices; `ui key` changes it), and `Tab` only moves focus, so no key has two jobs (revised the same day from a shared Tab); `ui` blocks may sit inside `draw`, positioned in canvas coordinates. Full text in §5.8.
- **2026-10-24, Library index**: a git repository on GitHub, curated by Fabrizio at first. Listing rules are in the entry below. Full text in §5.10.
- **2026-10-24, accesskit-c on mobile**: its releases include iOS and Android libraries; we build FreeBSD and arm64 Linux ourselves once per release. Full text in §4.8.
- **2026-10-24, Gamepad names**: friendlier rocinante names (`bottom`, `leftstick`, `lefttrigger`, `dpad`, …) mapped onto SDL3's positional buttons. Full text in §5.12.
- **2026-10-24, Hot reload rules**: check first and keep the old code on errors; unchanged definitions keep their values, changed ones re-run; shapes may gain fields; constants always reload; `Ctrl+R` restarts. Full text in §5.5.
- **2026-10-24, List verbs**: `keep`, `skip`, `collect`, `combine … from`, `find`, `sort … by`, with `it` and `result`; no pipe. Full text in §5.2.
- **2026-10-24, Video without FFmpeg**: platform media frameworks plus dav1d, libvpx and pl_mpeg; FFmpeg only as an optional user install. Full text in §4.11.
- **2026-10-24, Record shapes**: one shape per creation site, structural verbs, shapes of JSON assets read at check time, messages typed from `send`. Full text in §5.3.
- **2026-10-24, Library index rules** for listing and removal. Full text in §5.10.
- **2026-10-24, Extensions** ship as Odin source for packaging and as prebuilt desktop libraries for `roci run`. Full text in §5.10.
- **2026-10-24, 2D physics** on Box2D v3 worlds; 3D physics on the roadmap. Full text in §5.13.
- **2026-10-24, Connecting words are positional**: a word is a connecting word only once the call's required arguments are filled, so `width`, `height` and `size` stay usable as values; multi-word verbs are a fixed table matched longest-first; `[ ]` is a block or a list by the parameter's kind. Full text in §5.1 and §5.14.
- **2026-10-24, CLAUDE.md is split**: this file keeps the rules and plan; `docs/design.md` holds §4.3 to §6 and is imported here. Section numbers are global.
- **2026-10-24, Language details** (operators, lists, maps, text, `print` and `log`, scope, conventions, defaults, reserved names, `copy`, spelling, runtime failures, mixed 2D and 3D). Full text in §5.15.
- **2026-10-24, `roci` fetches the pinned Odin** into its own cache. Full text in §4.7.
- **2026-10-24, Top-level `load` waits; loads inside `draw` and events are asynchronous.** Full text in §4.4.
- **2026-10-24, UI identity is label, panel and tab path, and loop index; `ui.toml` is keyed by it and written on exit and after pauses; rocinante writes its own `toml` package** (neither `core:` nor `vendor:` has one). Full text in §4.8 and §4.9.
- **2026-10-24, Files other than `sketch.roci` hold definitions only**, evaluated in dependency order before it. Full text in §5.5 and §5.10.
- **2026-10-24, Trust and signing**: `roci get` and `roci run` ask once before loading a native extension from a git URL; `roci package` covers macOS notarisation (Developer ID) and Windows SmartScreen and says what is left for the user; `roci` shows the Android SDK licence for acceptance; built-in ML models record their source URL and a checksum, and `roci run` needs the network once to fetch them. Written into §4.10, §5.10 and §7.
- **2026-10-24, Physical key positions**: `keys w a s d` binds by SDL scancode, so AZERTY works (§5.12). Dear ImGui does not shape complex scripts (Arabic, Devanagari): Phase 3 states which scripts the UI supports and tests them with an IME.
- **2026-10-23, Sharing: numbers, vectors, colours and text are copied; lists and records are shared**; `copy` makes an independent copy. Full text in §5.11.

### Later

Ideas that are wanted but not planned for the first stable release live in the Roadmap section of `README.md`, so contributors can see them. When one is taken up, it moves here and into §8.

### Open

Decide these with Fabrizio; move each to "Decided" with the date.

1. Machine learning on FreeBSD: LiteRT's C runtime built there, or ONNX Runtime as the FreeBSD fallback (§4.10). Settled by the LiteRT spike at the start of Phase 6.
2. ExecuTorch as a second runtime for PyTorch's own `.pte` files, so PyTorch models skip conversion. It is C++ only, so it would need our own C wrapper, and a second runtime is a second behaviour to keep equal (§4.10).
3. Choices inherited from the sections they point to: vector tessellation (§4.3, Phase 1); text engine (§4.3, Phase 0); AIFF, Opus and AAC decoding (§4.6, Phase 5); MIDI on FreeBSD, iOS and Android (§4.6, Phase 5); mobile multi-window behaviour (§4.5, Phase 8); video encoder libraries (§4.11, Phase 6); the Git LFS type list (§4.9, Phase 2); the name of `roci check --why-slow` (§5.3, Phase 2); Box3D for 3D collision (§5.13, Phase 4); AccessKit on FreeBSD (§4.8, Phase 3).
4. What to do about the platforms Odin's official archives do not cover: FreeBSD, Windows arm64 and macOS Intel (§4.7). Settled in Phase 0.

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
- Brian Harvey, Computer Science Logo Style vol. 1 ch. 2 (fixed arity, optional parentheses for readability): https://people.eecs.berkeley.edu/~bh/v1ch2/proced.html
- NetLogo Programming Guide (reporters bind tighter than arithmetic): https://docs.netlogo.org/programming.html
- Rebol, math precedence (operators before functions, "a source of programming errors"): https://www.rebol.com/r3/docs/concepts/math-precedence.html
- Inform 7, "a random number from 2 to 5" (range phrase closed by connecting words): https://ganelson.github.io/inform-website/book/WI_8_18.html
- Stefik & Siebert (2013), An Empirical Investigation into Programming Language Syntax: https://www.vidarholen.net/~vidar/An_Empirical_Investigation_into_Programming_Language_Syntax.pdf
- Elm, Compiler Errors for Humans: https://elm-lang.org/news/compiler-errors-for-humans
- Apple App Review Guidelines (2.5.2): https://developer.apple.com/app-store/review/guidelines/
- nannou (prior art, built on Bevy): https://github.com/nannou-org/nannou
- LiteRT (runtime, platforms, accelerators, LiteRT Torch converter): https://github.com/google-ai-edge/LiteRT
- LiteRT C API (`tensorflow/lite/c/c_api.h`): https://developers.google.com/edge/litert/android/native
- LiteRT, JAX models (`jax2tf`, then the TFLite converter): https://developers.google.com/edge/litert/conversion/jax/overview
- ONNX Runtime FreeBSD port (fallback candidate): https://www.freshports.org/misc/onnxruntime/
- ExecuTorch desktop platforms (open question 2): https://docs.pytorch.org/executorch/1.1/desktop-section.html
- ml5.js (model for the built-in ML tasks): https://docs.ml5js.org/
- SDL3 gamepad API (mappings, positional buttons, labels, rumble): https://wiki.libsdl.org/SDL3/CategoryGamepad
- SDL3 gamepad buttons (`SDL_GamepadButton`, names mapped in §5.12): https://wiki.libsdl.org/SDL3/SDL_GamepadButton
- accesskit-c release workflow (published targets): https://github.com/AccessKit/accesskit-c/blob/main/.github/workflows/publish.yml
- Box3D (3D sibling of Box2D, MIT; 3D physics on the roadmap): https://github.com/erincatto/box3d
- F# type providers (model for JSON shapes in §5.3): https://learn.microsoft.com/en-us/dotnet/fsharp/tutorials/type-providers/
- dav1d (AV1 decoder, BSD-2-Clause): https://code.videolan.org/videolan/dav1d
- libvpx (VP8/VP9, BSD-3-Clause): https://github.com/webmproject/libvpx
- pl_mpeg (MPEG-1, MIT): https://github.com/phoboslab/pl_mpeg
- OpenType `OS/2` table, `fsType` embedding bits (font licence check in §4.9): https://learn.microsoft.com/en-us/typography/opentype/spec/os2#fstype
- Calendar Versioning (CalVer, segment names `YYYY`, `MINOR`, `MICRO`): https://calver.org/
- Zero-Clause BSD (OSI): https://opensource.org/license/0BSD
- GitLab CI job rules (`$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH`, merge request pipelines): https://docs.gitlab.com/ci/jobs/job_rules/
- GitHub Actions, events that trigger workflows (push to branches and tags): https://docs.github.com/en/actions/writing-workflows/choosing-when-your-workflow-runs/events-that-trigger-workflows
- Claude Code settings reference (`attribution`): https://code.claude.com/docs/en/settings-reference
- Report that an empty `attribution.commit` didn't remove the trailer: https://claudeissues.com/issue/45137-attribution-commit-does-not-disable-co-authored-by-trailer
