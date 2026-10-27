# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

This file and `docs/design.md` (imported below) are together the single source of truth for rocinante's design, scope and plan. When a decision changes, update the file that holds the section, in place. Do not create other design documents, changelogs of decisions or "notes" files beside them. `MANIFESTO.md` is the public statement of intent; this file is how we build it.

Read `MANIFESTO.md` before starting any work. Every decision below serves it.

## Commands

Everything is driven by the build script in `build/`, written in Odin; there is no Makefile or CMake for contributors. Run it from the repository root with the Odin release named in `ODIN_VERSION` (`odin version` must match it; the build script warns locally and fails in the pipelines when it does not).

```
odin run build -- ci            # exactly what both pipelines run
odin run build -- ci --fast     # the pre-push subset (git config core.hooksPath tools/hooks)
odin run build -- licences      # dependency licence check against tools/licences.txt
odin run build -- odin          # check the installed Odin against ODIN_VERSION
odin check <dir> -vet -strict-style           # type-check one package
odin test <dir>                               # run its @(test) procedures (core:testing)
odin test <dir> -define:ODIN_TEST_NAMES=package.test_name   # run a single test
odin test <dir> -out:output/tests/<name>.exe  # on Windows: keep the test program out of the repository root, as ci does
```

`ci` runs `odin test` on every package listed in `TEST_PACKAGES` in `build/main.odin` (add a package there as soon as it has tests), and a failing test makes `ci` exit with 1. Tests run from the repository root, in parallel threads, and some make fixtures under `output/`. A test file that builds maps or dynamic arrays from literals needs `#+feature dynamic-literals` at the top.

The Phase 0 spikes, each run from the repository root:

```
cp "$(odin root)/vendor/sdl3/SDL3.dll" .      # Windows, once before examples/window and Spike 4: they need SDL3.dll beside them (ignored by git)
odin run examples/shapes [-- seconds]        # roci/gfx by hand: every shape through the renderer, a circle follows the mouse
odin run tests/golden [-- update | scene]     # golden images: draw the scenes offscreen and compare with tests/golden/*.png (SDL_VIDEODRIVER=offscreen with no display)
shaders/compile.sh                            # HLSL to SPIR-V and Metal (glslang, spirv-cross); shaders/compile-dxil.sh makes DXIL on Windows
odin run examples/window [-- seconds]        # roci/platform by hand: windows on a GPU device, events, N / F / V keys (replaces Spike 1)
odin run spikes/codegen -- check              # Spike 3: interpret, generate Odin, build it, compare output
odin run spikes/codegen -- doctor [host]      # which targets this computer can build, and the toolchain
odin run spikes/mobile/macos                  # the shared circle spike on the desktop, 5 seconds
spikes/mobile/android/build.sh --install      # Spike 2, Android; needs SDL_ANDROID_LIB and SDL_ANDROID_JAVA
spikes/mobile/ios/build.sh --install          # Spike 2, iOS; needs SDL_IOS_LIB, TEAM_ID and DEVICE
spikes/mobile/shared/shaders/compile.sh       # GLSL to SPIR-V (glslc) and Metal (spirv-cross); outputs are committed
spikes/ui/setup.sh                            # Spike 4, once: fetch Dear ImGui, dear_bindings and accesskit-c into .cache/ui, generate and build them
spikes/ui/setup-windows.sh                    # the same on Windows, with MSVC (cl and lib on the PATH, see the Windows gotcha below); no accesskit-c yet
odin run spikes/ui [-- interactive]           # Spike 4: slider, button and text box, and the screen-reader bridge on macOS
```

The Android and iOS scripts need SDL 3.4.18 built for the phone, which is not in the repository (the recipe is in the Phase 0 results in §8).

**What `ci` does not cover.** `ci` type-checks and tests the build script, `tools/term` and Spike 3, and type-checks `examples/window`, `examples/shapes`, `tests/golden` and Spike 2's shared code. It does not build or run anything that needs a window, a GPU, a phone, or the libraries `spikes/ui/setup.sh` builds: the runs of `examples/window` and `examples/shapes`, the golden-image run, the Android and iOS spikes, Spike 4 and the SDL window code are checked by hand, and a change to them needs a hand run on the affected systems before it is called done.

**Terminal output** is coloured through `tools/term` (decided 2026-10-25): every command that prints for people, including `doctor`, paints headings, results and errors with it and marks results with ✅, 🚫 and ❌ (`term.out_icon`). Colour is on only when the stream is a terminal and `NO_COLOR` is unset, the words are identical with or without it, and piped output and the pipelines stay plain. New commands use `term.out` and `term.err`, never raw escape codes.

**Where things are.** This file holds the rules, the plan and the decisions; `docs/design.md`, imported below, holds the architecture details, the language and the parity map; section numbers are global, so `§5.9` is in `design.md` and `§8` is here. Phase 0 is closed (§8) and the work is now in Phase 1. `spikes/` is throwaway Phase 0 code, not the planned packages. The real ones in §4.2 are being created in Phase 1: `roci/maths`, `roci/registry`, `roci/platform`, `roci/geom` and `roci/gfx` exist (in `TEST_PACKAGES`), and `roci` follows; `cli/`, `vendor/`, `shaders/` and `tests/` come later. Each new package updates this paragraph and the code map below in the same commit, joins `TEST_PACKAGES` and says which spike it replaces; `roci/platform` replaced Spike 1, and Spike 2's shared code goes when `roci/gfx` lands. `output/` and `.cache/` are generated and ignored by git.

**The code that exists so far:**
- `build/main.odin`: `ci` is a list of `step` calls in `check_packages` (each runs one command and prints its output only when it fails), so a new package or spike joins the pipelines there, and `TEST_PACKAGES` lists what `odin test` runs. `build/licences.odin` is the licence check (§3).
- `spikes/codegen` (Spike 3) is the language pipeline in miniature: `ir.odin` holds a hand-written typed IR (§4.7), `check.odin` is a stand-in checker, and the two back ends, `interp.odin` and `codegen.odin`, both call the same `verbs` package, which is non-negotiable 7 in small. The interpreter's output is captured through the thread-local `verbs.sink`; `main.odin` (`check`) writes each generated program to `output/codegen/<name>/` beside a copy of `verbs`, builds it with Odin and compares the two outputs. A new test program goes in `programs.odin` and in the list in `run_check`, with an exact `generate` test. `doctor.odin` is the stand-in `roci doctor` and holds §7's host and target table.
- `spikes/ui` (Spike 4) is not in `ci`: it links the library its setup script builds in `.cache/ui`, so the pipelines neither check nor test it, and it is run by hand like the mobile spikes. `imgui.odin` hand-declares the few Dear ImGui calls used and links `.cache/ui/libroci_ui.a` (`roci_ui.lib` on Windows); `accesskit.odin` holds the accesskit-c bindings, whose layouts were read from a compiled C probe; `access_state.odin` builds the accessibility tree from the spike's own widget records and queues screen-reader actions, which `main.odin` applies between frames. The macOS adapter is `access.odin` (`#+build darwin`), and `access_other.odin` holds do-nothing stand-ins for every other system, which a new adapter replaces for its system.
- `roci/maths` (package `maths`): colours (`rgb`, `hsb`, `oklch`, hex, the 141 CSS names, `mix` in Oklab, Rgb or Oklch), the one random generator (`Rng`, SplittableRandom: `rng_split`, `rng_derive`, `rng_range`, `rng_int`, `rng_gaussian`) and noise: Perlin in 1 to 4 dimensions (`noise1`-`noise4`), simplex in 1 to 4 (`simplex1`-`simplex4`, Gustavson's reference constants so results match other simplex noise, which leaves steps of about 0.001 in 3D and 4D) and layered `noise_fbm` (Perlin, up to 3D). Everything is `core:math` plus our own code, and both back ends call it (§4.7).
- `roci/registry` (package `registry`): the verb table (`VERBS`: name, shapes of `params`, `options` and `gives`, doc), the closed lists of connecting words, keywords and values, and the questions asked of them: `find_verb`, `match_phrase` (multi-word verbs, longest first), `shape_for` (count, then kinds), `suggest` ("did you mean"), `is_reserved`, `reserved_words`, and `validate`, which a test runs on the real table. A new verb is a row in `verbs.odin`; the procedure that does it joins package `roci`, which does not exist yet.
- `roci/platform` (package `platform`): SDL3 and the GPU device. `App` holds the one device and the windows; `init`, `create_window` (title, size, position, resizable; high pixel density always requested), `destroy_window`, `set_title`, `set_fullscreen`, `set_vsync` (immediate, then mailbox, else vsync, since only vsync is promised everywhere), `window_metrics` (logical size, device pixels, density, display scale) and `poll_events`. `translate` turns SDL's event union into our `Event` union (resize, pixel size, scale, move, focus, close request, quit, mouse, wheel with natural scrolling turned back, keys by scancode with modifiers); it and the size and vsync sums are pure and tested, while the calls into SDL are checked by hand with `examples/window`. The GPU device always has clip distances off (Spike 2).
- `roci/geom` (package `geom`): the plane geometry under paths, pure `f64` maths with no GPU, written for the mesh pipeline of Phase 1 (decided 2026-10-27: our own tessellation, no library, §4.3). `flatten_cubic`, `flatten_quadratic`, `flatten_curve` (Catmull-Rom with tightness, as Processing's `curve`) and `arc_points` (clockwise on screen, a stop before the start goes the long way) turn curves into polylines within a tolerance (default a tenth of a pixel; recursion bounded by `MAX_DEPTH`); `triangulate` cuts outlines with holes into triangles by ear clipping with Eberly bridges, treating nested contours by even-odd depth (spikes and collinear points are cleaned away first, a self-crossing outline gets a best-effort answer and never loops); `stroke_polyline` makes a stroke's triangles with butt, round or square caps and miter, round or bevel joins (miter limit default 4), joining the inside of a corner at the point where the edges cross so a translucent stroke does not darken there. Triangles have positive shoelace area. `Triangulation` is a points array and an index array, appended to so several shapes can share one mesh.
- `roci/gfx` (package `gfx`): the drawing model, with no GPU in it. `Command_List` (one per window) records `Command`s (kind, the verb's numbers, origin, the `Transform` and `Style` current at the time, a `Span` the interpreter will fill) and holds the state that `fill`, `move` and the rest change; `begin_frame` resets it all (section 5.15 defaults: white fill, no stroke, thickness 1, background 230). Non-finite numbers drop the command (non-negotiable 3), negative sizes are made positive, `push` has two scopes (`.Style` for `with`, `.Style_And_Transform` for `push`). `describe` gives a command's box and colour for screen readers; `command_hash` (FNV-1a, spans excluded) lets an unchanged batch reuse its GPU buffer. `Batcher.build` turns a list into `Instance`s (104 bytes: a 2x3 transform, half size, shape numbers, fill, stroke, thickness, kind, flags) for one signed-distance "shapes" pipeline, so any number of circles, ellipses, rects, lines, points and triangles in a row is one draw; quads and arcs go to `Paths` batches until the tessellator exists. Origin defaults (`is_centred`): circles, ellipses and arcs are centred, as in Processing; rect and square start at their corner (decided 2026-10-27, section 5.9).
- `roci/gfx/mesh.odin`: `needs_mesh` says which commands the distance shader cannot draw as styled; `mesh_add_command` cuts one into `Mesh_Vertex` triangles (24 bytes: position, colour) with package geom, in the shape's own space and moved onto the canvas at the end, so an outline's width follows the transform. A filled arc is a pie slice and its outline follows the curve only. `Style` has `cap` and `join` (`set_caps`, `set_joins`).
- `roci/gfx/renderer.odin` and `png.odin` (package `gfx`, SDL GPU): `Renderer` makes the pipelines (`.Shapes`, `.Mesh`) on first use for the target's format and sample count (a failure is recorded once, never retried per frame), draws into a 4x multisampled texture it keeps per target size and resolves onto the target (one sample where the GPU cannot), keeps buffers that grow by doubling, skips each upload when that pipeline's batch hashes equal last frame's, and draws each `Shapes` batch as one instanced draw (`first_instance` = the batch's first instance) and each `Paths` batch as one indexed draw of the shared mesh. `render_window` draws a window's frame; `render_offscreen` draws to a texture and reads it back as an `Image` (RGBA). Blending is premultiplied (ONE, ONE_MINUS_SRC_ALPHA) and colours go out as written. `png_encode` is our own writer (Odin's `core:image/png` only reads), tested by reading its files back; `image_diff` and `image_matches` compare pictures with a tolerance. `shaders/shapes.hlsl` is the shapes shader (signed distances for circle, ellipse, rect, line and triangle; instance attributes at TEXCOORD0 to 8; the vertex uniform buffer at b0, space1) and `shaders/compiled/` holds its SPIR-V and Metal outputs; DXIL is missing until `compile-dxil.sh` is run on Windows, and Direct3D 12 says so plainly until then.
- `examples/shapes` and `tests/golden`: the hand check and the golden-image program (above); `ci` type-checks both, and `tests/golden/scenes.odin` is where a new scene goes.
- `tools/ci/install-odin.sh` installs the release in `ODIN_VERSION` for both pipelines (`.gitlab-ci.yml` and `.github/workflows/ci.yml` call it), so a change to how the pipelines get Odin goes there. `tools/ci/install-sdl3.sh` builds the latest stable SDL3 from source (`--latest` prints its tag) for the GitHub workflow; GitLab's Arch image has `sdl3` and `vulkan-swrast` as packages, to be added to its `pacman` line when code needs them.
- `tools/term`: `out` and `err` paint text for stdout and stderr (`.Bold_Cyan` headings, `.Green` results, `.Bold_Red` errors), `out_icon` and `err_icon` give the result marks, and `setup` is called first in every `main`.

**Shell and tool gotchas** (these have all cost time):
- Fabrizio's `ls` is an alias for `eza` and adds colour codes, so scripts and anything piped must use `command ls`. Use `rg`, not `grep`, in anything written for him; portable scripts that contributors run (hooks, CI) use POSIX tools.
- macOS has no `timeout`, and BSD `sed` needs `-i ''`.
- Odin: write `-target` before `-subtarget`; a literal `{` in an `fmt` format string means something, so pass it as an argument; a procedure cannot return a slice literal (copy it to the heap); a global cannot call a procedure that needs `context`.
- Odin on Apple Silicon guesses the wrong NDK folder, so set `ODIN_ANDROID_NDK_TOOLCHAIN` (to the `darwin-x86_64` toolchain) when building for Android.
- Never test a mobile app on a sleeping or locked phone: Android draws nothing, iOS refuses to launch.
- Odin `dev-2026-10`: `for x in m[key]` crashes when `key` is missing from the map, so copy the value to a local first (`list := m[key]`, then `for x in list`); found in Spike 3, worth reporting upstream.
- Windows: an `-out:` path must end in `.exe`, and a running program's file is locked, so nothing may write `build.exe` while `odin run build` runs (`ci` puts test programs in `output/tests/`). A program that needs `SDL3.dll` finds it only next to itself or on `PATH`. To get MSVC's `cl` and `lib` into Git Bash, run `call "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat"` in a plain `cmd`, then `"C:\Program Files\Git\bin\bash.exe" --login -i` in the same window (the Start menu's Native Tools prompt did not set them up on Fabrizio's machine, which has both Build Tools and Community installed). C and C++ code linked into an Odin program is built with `-MT`, because Odin links the static C runtime.
- Python is not a rocinante dependency until the Phase 6 model converters (§4.10), so the repository's scripts use Odin or POSIX tools even on computers that have it. Windows: in Git Bash, a heredoc whose text holds backticks and quotes can fail to parse; write such files with the editor's write tool instead. Line endings are LF everywhere: `.gitattributes` (`* text=auto eol=lf`) overrides `core.autocrlf`, so shell scripts keep working when a Windows clone is used from WSL or copied to a Mac.
- Odin: package-level state shared by tests is a data race (the tests run in parallel), so use `@(thread_local)`; and a constant slice of structs that hold slices is rebuilt on the stack at each use, so keep such tables in a package-level variable (both were found by the first unit tests).

---

## 1. What rocinante is

An open-source creative coding framework and language.

- **rocinante (the language)**: a small, Logo-inspired language for sketches. The language, the framework and the project share the one name (decided 2026-10-24). No semicolons, no braces around blocks, one predictable shape. File extension `.roci`.
- **The core**: an engine written in **Odin** on SDL3 and its GPU API (Vulkan, Metal, Direct3D 12). It owns windows, rendering, UI, audio, input, I/O and packaging.
- **`roci` (the tool)**: one command-line program to run, watch, check and package sketches. Written in Odin.
- **A public Odin API, with a C ABI,** for power users who want to write sketches or extensions in Odin (or C) directly. Same verbs, same behaviour.

Execution: **interpreted while you work, compiled to native code when you ship** (§4.7). Users never choose or notice; `roci run` interprets, `roci package` compiles.

Target platforms, all first class from the start: FreeBSD, Linux, macOS, Windows, iOS, Android. Four of them are also **host** platforms, where sketches are written, run (`roci run`) and packaged: FreeBSD, Linux, macOS and Windows. **iOS and Android are targets only** (decided 2026-10-25): `roci` does not run on them, nothing is developed on them, and a sketch gets there as a packaged app. Which hosts can package which targets is in §7. On the desktop, the first stable release covers x86-64 FreeBSD, Linux and Windows and Apple silicon Macs; other processors are on the roadmap (decided 2026-10-26).

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
- **All code needs the best possible unit-test coverage** (decided 2026-10-25). Every package ships with `@(test)` procedures (run with `odin test`, §9) written with the code, not after it: every procedure, every branch and every error path, including the edge cases (empty input, zero, the largest and smallest values, malformed text). A change that adds code without tests for it is not finished; if something truly cannot be tested, say why in the commit. Odin has no coverage tool, so coverage is kept by discipline and by review: list the branches of what you wrote and check that each has a test.
- Work in small, reviewable steps. Each phase below lists exit criteria; a phase is done only when all of them pass.
- Never weaken a non-negotiable to make a task easier. Flag the conflict instead.
- When you finish something that changes the design, update this file in the same commit.
- **Never push automatically** (decided 2026-10-25). Claude Code does not push to `origin`, `github` or any other remote unless Fabrizio asks for a push in that very message; an earlier "yes" does not carry over. After committing, it says what to run (`git push origin <branch>`), and Fabrizio pushes, opens the merge request and merges it himself. It also never merges into `main` or deletes remote branches on its own; it deletes merged local branches only when asked.
- **Never commit on `main`** (decided 2026-10-26). Before the first commit of any change, create a branch named by kind (`feat/…`, `fix/…`, `docs/…`, `spike/…`, `refactor/…`, §11) and commit there; `main` changes only through a tested GitLab merge request that Fabrizio merges. After he merges, fast-forward the local `main` to `origin/main`, delete the branch with `git branch -d` when he asks, and run `git fetch --prune` (GitLab deletes merged branches itself). When `main` moved while a branch waited, rebase the branch onto `origin/main` and tell him to push it with `git push --force-with-lease origin <branch>`.
- **Git** follows §11: short feature branches rebased onto `main` and merged fast-forward, small frequent commits. **Never mention AI, Claude or any assistant in commit messages, branch names, tags or release notes, and never add `Co-Authored-By` trailers or session links.**
- Contribute fixes upstream (Odin, its vendor bindings, SDL, Dear ImGui, AccessKit) whenever we fix something there. **SDL's projects forbid AI-generated contributions** (SDL_shadercross's `AGENTS.md`: generative AI "should not be used in any way when contributing to SDL", checked 2026-10-27), so Claude Code never writes a patch, issue or comment for SDL or its satellites; it describes the problem and Fabrizio writes the contribution himself.

---

## 4. Architecture

### 4.1 Layers

```
 .roci sketch ──► lang: lexer → parser → checker + type inference → typed IR
                        │                                   │
              roci run  │ (interpreter)          roci package│ (code generator)
                        ▼                                   ▼
                  interpreter                  generated Odin source
                        │                                   │ odin build (pinned, fetched),
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
  CONTRIBUTING.md      a pointer to README's Contributing section, for GitHub and GitLab to show
  CHANGELOG.md         a pointer to the releases page; release notes live on the tags (§11)
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
  examples/            .roci and .odin examples, one per feature; each .roci example has a one-line task
                       description and a reference PNG checked by the golden-image harness (§9)
  tests/               golden-image tests, language tests, back-end equivalence tests
  tools/hooks/         pre-push and commit-msg hooks (§11)
  docs/                design.md (architecture details, the language, parity map; imported by CLAUDE.md),
                       grammar.ebnf (the language's grammar, written in Phase 2, §5.14),
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
roci run [file]          interpret with live reload (default: sketch.roci); needs nothing installed.
                         `--frames N --screenshot out.png --errors json` runs headless: N frames, a picture,
                         and errors as data (line, column, message ID, nearest known verb); the tests use it
roci check [file]        parse, check and infer types without running
roci fmt [file]          format a sketch in the house style (§5.1); no options
roci package <target>    compile to native code and package; targets: linux, freebsd, macos, windows, android, ios
roci doctor              for each package target, say whether this computer can build it, and if so what is
                         missing, with install steps; `roci doctor ml` checks the PyTorch and JAX converters
```

Packaging notes:

- `roci package` always generates Odin and builds it with the pinned Odin and the user's platform toolchain (§4.7). The user never sees Odin code or compiler output unless they open the saved build log in `output/`; failures are reported in rocinante's plain style, with `roci doctor` as the next step.
- **Toolchain** (§4.7): Odin at the pinned version everywhere, fetched into `roci`'s own cache on first use; MSVC and the Windows SDK on Windows; the Xcode command-line tools on macOS; clang on Linux and FreeBSD.
- **iOS**: App Store distribution requires a Mac with full Xcode and an Apple Developer Program account. `roci package ios` drives Odin and Xcode's command-line tools, and runs on macOS only; there is no hand-off to another machine.
- **Android**: `roci` fetches and manages the SDK, the NDK and a JDK (Temurin 21) on first use and keeps the signing keystore out of the user's way. It can package from macOS, Linux x86-64 and Windows hosts only, because Google's NDK has no other hosts (§4.7).
- **FreeBSD**: Odin is available as the `lang/odin` port. Produce a package of the sketch; later, a port of `roci` itself (named `roci`, because `sysutils/rocinante` is another project's port) (`poudriere bulk -t`).
- **Hosts and targets** (decided 2026-10-25). Sketches are written, run and packaged on FreeBSD, Linux, macOS and Windows computers; iOS and Android are targets only. A target can be packaged only on the hosts below. **There is no cross-compilation between desktop systems** (decided 2026-10-25): each desktop system packages for itself. Odin on macOS can cross-build for Intel Macs, can cross-link Windows only with a Windows SDK root and `lld`, and does not link Linux or FreeBSD at all (checked with `dev-2026-10`), and building for macOS needs Apple's SDK and tools on a Mac. The more useful route to artefacts for systems you do not own is to run `roci package` on a machine of that system, such as a CI runner.

  | Target | Can be packaged on | Why |
  |---|---|---|
  | `linux` | Linux | built with the host's clang and linker (§4.7) |
  | `freebsd` | FreeBSD | the same |
  | `macos` | macOS | Xcode command-line tools |
  | `windows` | Windows | MSVC and the Windows SDK |
  | `android` | macOS, Linux x86-64, Windows | Google's NDK has no other hosts (§4.7) |
  | `ios` | macOS | Apple's tools run only on a Mac |

  When this computer cannot build a target, `roci doctor` says so first, in plain words, before looking for tools, and names the computers that can: for example, "iOS apps can only be built on a Mac, because Apple's tools only run there." (The line above it already says what this computer is, so the message does not repeat it.) `roci package <target>` refuses with the same message instead of failing halfway through, and `roci doctor` marks each of the six targets as ready, missing something (with the install steps), or not buildable here. Phase 8 tests this for every host and target pair (§9).
- **Signing and trust** (decided 2026-10-24). macOS packages are signed with a Developer ID and notarised, and Windows packages are signed where the user has a certificate; `roci package` says plainly what SmartScreen or Gatekeeper will still show when they have none. `roci` shows the Android SDK licence and asks for acceptance before fetching it.
- Every target bundles the compiled sketch, all of `assets/` and `libs/`, `ui.toml` and compiled shaders (§4.9), under the name, id, icon and version in `sketch.toml`, whose build number `roci package` raises by one each time. No network access needed at runtime.

---

## 8. Phases

Each phase ends with a demo sketch, a green Linux pipeline (§11), the release-checklist run on the other platforms that the phase touches, and an update to this file.

### Phase 0: Foundations (done 2026-10-27)

Phase 0 built the repository, the build script with its `ci` command, the hooks, both pipelines, the licence check and the unit-test setup (§9, §11), and tested the riskiest assumptions with four throwaway spikes in `spikes/`:

1. **Desktop:** an SDL3 window and GPU device cleared to a colour, on every desktop system, including FreeBSD on Vulkan through Mesa.
2. **Mobile:** an Odin and SDL3 program drawing a shader circle on a real iPhone and a real Android phone.
3. **Code generation:** a hand-written typed IR (the circle, a loop, a list of records) run by an interpreter and turned into Odin, with a stand-in `roci doctor`.
4. **UI:** Dear ImGui through dear_bindings and the SDL3 and SDL_GPU backends, a text box with IME, and an AccessKit adapter read by a screen reader.

It also checked every dependency, the name, the parity map (§6) and Odin's target coverage. The record below keeps what later phases need; per-platform frame counts and run details are in git history.

**Phase 0 results** (recorded 2026-10-24 to 2026-10-27):

- **Odin:** pinned to `dev-2026-10`. Official archives cover Linux amd64 and arm64, macOS arm64 and Windows amd64 only (§4.7). Homebrew's `dev-2026-07` built against LLVM 23 failed to compile any program; its `dev-2026-10` (LLVM 22.1.8) works. On FreeBSD (15.1) the pinned release builds from source in about 2 minutes with `LLVM_CONFIG=llvm-config19 gmake release-native` (one core, so `-j` does not help; it needs `gmake`, git and the ports package `llvm19`, because the base system's clang has no `llvm-config`, so `roci` must find `llvm-config` under its versioned name). The result reports `dev-2026-10:84bc3fc`, the same commit as the official archives.
- **`vendor:sdl3`:** its bindings are for SDL 3.4.2, while the latest SDL3 release is 3.4.18 (2026-10-02). Patch releases keep the ABI, so the bindings load the newer library, but functions added after 3.4.2 are missing; the choice between `vendor:` and our own bindings is made in Phase 1 when one is needed. The spikes ran with SDL 3.4.2, 3.4.16 and 3.4.18 libraries, and the patch-release differences are accepted (decided 2026-10-26).
- **Name check** (2026-10-24; registries and GitHub queried directly, no legal or trademark search):
  - **FreeBSD:** a port `sysutils/rocinante` already exists (BastilleBSD's configuration-management tool, command `rocinante`, 79 stars, in ports). Our command is `roci`, so no file clashes, but a port or package of ours cannot be called `rocinante`: name it `roci`.
  - **`roci`:** free as a command on Homebrew, Arch's AUR and Repology. The name exists as a small crates.io library (Elodin's flight software framework, 2,384 downloads), a tiny npm package ("Roci common build setup") and a dormant PyPI package. None is a creative-coding tool.
  - **`rocinante`:** npm and PyPI names are taken by unrelated web frameworks; crates.io and Homebrew are free. We publish to none of them. The GitHub organisation name `Rocinante` is taken (an organisation with one repository), so the public mirror lives at `github.com/sandbenders/rocinante` instead.
  - **Creative coding:** GitHub text searches for creative-coding, game-engine, graphics and language projects named rocinante or roci found nothing; four more searches were rate-limited and a web search was blocked by a bot check, so this is not exhaustive. The Expanse ship name and Cervantes' horse are the other uses, as the README says.
  - **Domains** (DNS only): `rocinante.dev`, `.org`, `.io`, `.run` and `roci.dev` resolve, so they are taken or parked; `rocinante.art`, `.studio`, `.codes` and `roci.sh` did not resolve and may be free.
  - **Still to do by hand:** a trademark search for software classes (EUIPO, WIPO, USPTO), and a manual web search.
- **Dependency checks** (2026-10-24, from each project's own repository, releases and licence files; the GitHub API gave the dates):

  | Dependency | Licence | Latest release | Finding |
  |---|---|---|---|
  | SDL3 | Zlib | 3.4.18 (2026-10-02) | `vendor:sdl3` bindings are 3.4.2 (see above) |
  | SDL_ttf | Zlib | 3.2.2 (2025-03-31) | `TTF_CreateGPUTextEngine` exists since 3.0.0 and must run on the device's thread; the last release is 19 months old, though commits continue (2026-10-17) |
  | SDL_shadercross | Zlib | none (no tags or releases) | takes HLSL or SPIR-V; needs SPIRV-Cross (Apache-2.0) and, for DXIL, DXC (LLVM Release Licence, permissive) shipped beside it; DXBC needs vkd3d off Windows, which we don't need. No release means pinning a commit |
  | Dear ImGui | MIT | 1.93.0 (2026-10-14) | active |
  | dear_bindings | MIT | 0.26 for ImGui 1.93.0 (2026-10-18) | its tested list has SDL3 but not `imgui_impl_sdlgpu3` (it has an `example_sdl3_sdlgpu3`); Spike 4 verifies it |
  | accesskit-c | Apache-2.0 or MIT (BSD parts from Chromium) | 0.23.1 (2026-09-26) | active; its README lists no platforms, so the release-workflow list in §4.8 still stands as the source |
  | LiteRT | Apache-2.0 | 2.3.0 (2026-10-07) | two C APIs (§4.10); Google's docs list Android, iOS, macOS, Linux, Windows, web and embedded, not FreeBSD |
  | ONNX Runtime (FreeBSD fallback) | MIT | 1.31.0 (2026-10-09) | active |
  | Box2D | MIT | 3.2.0 (2026-10-19) | active |
  | Box3D | MIT | 0.1.0 (2026-06-30) | still pre-release, as §5.13 assumed |
  | miniaudio | public domain or MIT-0 | 0.11.25 (2026-03-03) | confirmed from its README |
  | stb (incl. `stb_vorbis` 1.22) | public domain or MIT | no releases | confirmed from file headers |
  | PortMidi | MIT-style | 2.0.7 (2025-10-25) | no iOS or Android; FreeBSD only through minimal sndio (§4.6) |
  | cgltf | MIT | 1.15 (2025-02-09) | the least active of the lot (last push 2026-02-02), but small and stable |
  | dav1d | BSD-2-Clause | not checked | licence confirmed from `COPYING` |
  | libvpx | BSD-3-Clause | no releases listed on GitHub | licence confirmed |
  | pl_mpeg | MIT | none | its README says MIT (GitHub shows no licence file); last push 2025-12-30 |

  Still unchecked: the exact platform lists of dav1d, libvpx and AccessKit's FreeBSD adapter (Phase 3), and every library's behaviour on iOS and Android, which the mobile spike covers.
- **Spike 1, desktop** (`spikes/desktop`, replaced by `roci/platform` and `examples/window` on 2026-10-27, see git history): passes on macOS (Metal), FreeBSD 15.1 and CachyOS Linux (Vulkan; FreeBSD with Odin `dev-2026-09` and the source-built pin) and Windows 11 on bare metal (Direct3D 12, with the `SDL3.dll` 3.4.2 that Odin ships in `vendor/sdl3` copied next to the program, because Windows looks for DLLs there). So Vulkan GPU rendering works on FreeBSD even though SDL does not list it. The spike presents with vsync, so frame counts follow the display (about 300 in 3 seconds at 99 Hz).
- **Spike 3, code generation** (`spikes/codegen`): passes on macOS, FreeBSD, Linux and Windows; the interpreter and the generated Odin (built with `-vet -strict-style`) print identical output for the circle, a loop and a list of records, and both call the same `verbs` procedures, as §4.7 requires. The generated code names variables after the sketch, comments each statement with its `.roci` line and declares every assigned name once at the top, which is how the §5.15 scope rule maps onto Odin. Each record shape becomes a plain Odin struct, the list a `[dynamic]` array and `for each` a `for &p in` loop by reference (the layout §5.2 promises); the stand-in checker rejects unknown shapes and fields, wrong field counts and changing a list while `for each` walks it (§5.15). The stand-in `doctor` finds Odin and the toolchain on all four systems and says plainly which targets the computer cannot build. Found: Odin rejects returning slice literals from procedures; `{` in an `fmt` format string needs care in generated text; `make_directory_all` reports `.Exist` for an existing folder; on Windows the generated program's `-out:` path must end in `.exe`, and without the Visual Studio C++ workload Odin stops with "VS library path not found" (Build Tools via `winget install --id Microsoft.VisualStudio.BuildTools` with the `Microsoft.VisualStudio.Workload.VCTools` workload; `doctor` finds them through `vswhere`).
- **Spike 4, UI** (`spikes/ui`, approved dependencies Dear ImGui v1.93.0, dear_bindings v0.26 and accesskit-c 0.23.1; `setup.sh` and `setup-windows.sh` fetch and build them into `.cache/ui`, nothing is committed): dear_bindings generated the C API for `imgui.h` and for **both `imgui_impl_sdl3` and `imgui_impl_sdlgpu3`**, so it handles the SDL_GPU backend, which its tested list did not name (§4.8). From Odin (hand-declared bindings for the few calls used), a panel with a slider, a button and a text box draws through the two backends, with keyboard navigation, and passes by hand on macOS (Metal), Linux, FreeBSD (Vulkan) and Windows (Direct3D 12). accesskit-c builds from source (CMake and cargo) into a static library; on macOS its subclassing adapter attaches to SDL's `SDL3Window`, the tree of window, slider, button and text input is built from rocinante's own records and sent only when something changes, and screen-reader requests (click, increment, decrement, focus) are queued and applied between frames. **Checked by hand (Fabrizio, 2026-10-26):** VoiceOver reads and drives the three widgets, IME composition works on macOS and with the Microsoft Japanese IME on Windows (composing `nihon` gave 日本; Dear ImGui's default font has no Japanese glyphs, so the panel shows placeholder boxes until Phase 3 brings real fonts). Found: dear_bindings needs Python and `ply` only to generate (a throwaway virtual environment, so Python stays out of the build until Phase 6 decides it, §4.10); `imgui_demo.cpp` must be compiled because `dcimgui.cpp` wraps its functions; accesskit-c's enumerators are one byte wide and its struct layouts differ from a guess, so the real bindings must be generated from `accesskit.h` (the spike read them by compiling a C probe), and its SDL example is for SDL2, so SDL3 needs `SDL_PROP_WINDOW_COCOA_WINDOW_POINTER`; on Windows Odin links the static C runtime (`core:c/libc` imports `libucrt.lib`), so the C++ library must be built with `-MT` (with `-MD` the link fails on `__imp_` symbols), and dear_bindings runs under Windows Python, which needs Windows paths (`cygpath -m`); Dear ImGui keeps the panel's position and folded state in `imgui.ini` in the working folder (ignored by git), so delete it to reset a folded panel. **Not verified:** the screen-reader adapters on Windows (UI Automation), Linux and FreeBSD (AT-SPI), which are not wired into the spike, and IME on Linux and FreeBSD; FreeBSD's screen-reader support stays the open question of §4.8.
- **Spike 2, Android** (`spikes/mobile/android`, 2026-10-25, Google Pixel 9, Android 16, Mali-G715, arm64): passes for the window and GPU half. An Odin shared library inside SDL's Java activity opened an SDL3 window and GPU device on the Vulkan driver and cleared the screen to a changing colour, 1205 frames in 20 seconds (60 fps); two screenshots a few seconds apart showed different colours. **Circle:** a fragment shader (GLSL, compiled to SPIR-V with `glslc`) draws a smooth circle that drifts around the screen, driven by a uniform buffer, on a full-screen triangle with no vertex buffer; two screenshots a few seconds apart show the circle in two different places, at 60 fps, with the pipeline created through `SDL_CreateGPUGraphicsPipeline`. How it is built, all with tools already on the Mac: SDL 3.4.18 compiled for arm64-v8a with the NDK's CMake toolchain; Odin builds `libmain.so` with `-target:linux_arm64 -subtarget:android -build-mode:shared`; SDL's Java sources are compiled with `javac` and `d8`; the APK is assembled with `aapt`, `zipalign` and `apksigner`, because `odin bundle android` cannot add Java code. Findings that shape the core and `roci package android`:
  - **GPU device options:** SDL's Vulkan backend requires `shaderClipDistance` by default, and the Mali-G715 reports it as unsupported, so SDL says "No supported SDL_GPU backend found". Creating the device with `SDL_PROP_GPU_DEVICE_CREATE_FEATURE_CLIP_DISTANCE_BOOLEAN` off fixes it (the core must always do this, so its shaders may not use clip distances). The phone's Vulkan features can be read with `adb shell cmd gpu vkjson`.
  - **Entry point:** `vendor:sdl3` declares `SDL_main` as an import, so an Odin library cannot export that name. The core exports its own name (`rocinante_main` here) and the Java activity overrides `getMainFunction()`; worth offering upstream.
  - **`android_main`:** Odin always links the NDK's `native_app_glue` into an Android library, and that glue needs an `android_main`; a do-nothing exported stub lets the library load under SDL's activity.
  - **Apple Silicon:** the NDK ships only `darwin-x86_64` toolchains, and Odin guesses `darwin-arm64`, so `ODIN_ANDROID_NDK_TOOLCHAIN` must be set (it runs under Rosetta).
  - **Signing:** a new debug key on each build makes the phone refuse the update (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`); the key must be kept.
  - **Java is needed to package:** `javac`, `d8` and `apksigner` all need a JDK, which `roci` fetches (decided 2026-10-25, §4.7).
  - **Debugging:** the activity starts on a locked or sleeping phone and then fails with `VK_ERROR_SURFACE_LOST_KHR` or draws nothing; test with the screen on.
- **Spike 2, iOS** (`spikes/mobile/ios`, 2026-10-25, iPhone 13 Pro, iOS 26.6.2, Xcode 27.1, a free Apple ID): passes for the window and GPU half. An Odin executable for the iPhone, started through SDL's UIKit loop, opened an SDL3 window and GPU device on the Metal driver (swapchain 1170 × 2532) and cleared the screen to a changing colour at 60 fps (3,300 frames in 55 seconds, then the user closed it). **Circle:** the same shader, converted from SPIR-V to Metal's shading language with `spirv-cross` (entry point renamed `main0` by it, uniform in `[[buffer(0)]]`), runs on the iPhone with the pipeline created without errors and 60 fps, and the user confirmed by eye that the circle shows and moves. The shared shader sources and their compiled outputs are in `spikes/mobile/shared/shaders` (committed, so building needs neither tool). How it is built, with no Xcode GUI: SDL 3.4.18 compiled as a static `libSDL3.a` for the iPhone with CMake; Odin builds the sketch code with `-target:darwin_arm64 -subtarget:iphone -build-mode:lib`; `clang` links it with SDL and the system frameworks; a tiny generated Xcode project only wraps the executable and signs it, and `xcodebuild -allowProvisioningUpdates` created the development certificate and provisioning profile; `xcrun devicectl` installs and launches it and streams the log. Findings:
  - **Link it yourself:** Odin's own link step puts Homebrew's macOS `libSDL3.dylib` ahead of the iPhone library (`-L/opt/homebrew/lib` comes first) and fails with "building for iOS, but linking in dylib built for macOS", so the core builds a static library and the final link is done separately.
  - **Signing:** `codesign` refused the bundle until its extended attributes were stripped (`xattr -cr`). A free Apple ID's apps stay untrusted until the user taps Trust in Settings, General, VPN & Device Management, and the signature lasts 7 days.
  - **Prerequisites on the phone:** Developer Mode on, unlocked and trusted for the Mac.
  - **Quitting:** an iOS app does not quit itself; if `main` returns, the app stays open and blank. The core must run until the system asks it to quit and offer no "quit" verb on iOS.
  - **Entry:** `sdl.RunApp(0, nil, main_func, nil)` from Odin's `main` starts UIKit and calls the sketch's main on SDL's thread.

**Phase 0 exit** (2026-10-27). Every exit criterion is met:

- **Pipelines:** green on GitLab (Arch, ORION's runner) and on GitHub (Ubuntu 24.04, pinned) from the same `main`, which the first GitHub push published on 2026-10-27; both run `odin run build -- ci`, which includes 136 unit tests (49 in `build/`, 78 in `spikes/codegen`, 9 in `tools/term`) and the licence check.
- **Spikes:** 1 (SDL3 window and GPU device) passes on macOS, FreeBSD, Linux and Windows; 2 (a shader-drawn circle) passes on a Pixel 9 and an iPhone 13 Pro; 3 (code generation, `doctor`) passes on all four desktop systems, with lists of records; 4 (Dear ImGui, IME, a screen-reader adapter) passes on all four desktop systems for rendering and input, with IME checked on macOS and Windows and VoiceOver on macOS.
- **Parity map** verified against the three references (2026-10-24). **Odin** pinned to `dev-2026-10` with the target coverage and gaps recorded (§4.7). Hosts and targets are decided (§7).

**Carried into later phases** (found open when Phase 0 closed, none blocks Phase 1):

- **Text engine** (§4.3): SDL3_ttf's GPU engine was not tried in Phase 0, so the choice is made at the start of Phase 3; Phase 1's error overlay uses its own minimal font.
- **`vendor:sdl3` or our own bindings:** decided in Phase 1, the first time a function added after SDL 3.4.2 is needed.
- **Screen readers and IME:** the AccessKit adapters for Windows (UI Automation), Linux and FreeBSD (AT-SPI) are not written, and IME on Linux and FreeBSD is untried; Phase 3. The spike's hand-declared Dear ImGui and accesskit-c bindings are replaced by generated ones (accesskit-c's layouts must come from `accesskit.h`, not from a guess).
- **Name:** the trademark search for software classes and a manual web search of the name are still to do by hand (see the name check above).
- **Unchecked dependencies:** the platform lists of dav1d, libvpx and AccessKit's FreeBSD adapter (Phase 3 and Phase 6).
- **Offers to make upstream:** Odin's `for x in m[key]` crash on a missing key, `SDL_main` declared as an import in `vendor:sdl3` (§8, Spike 2), and the bindings gaps above.
- **`spikes/` is throwaway:** the packages in §4.2 (`roci/`, `cli/`, `vendor/`, `shaders/`, `tests/`) are created in Phase 1.

### Phase 1: Window and 2D core (Odin API)
- App loop, `window` with optional position, multiple windows, HiDPI.
- A minimal text path for the error overlay and debug output (a built-in bitmap or SDF font), so Phase 2 can show errors before Phase 3 brings real text (§4.3).
- Internal shader pipeline: HLSL → SDL_shadercross → embedded SPIR-V/MSL/DXIL.
- Command list, batching, instancing, geometry cache.
- 2D primitives, style, colour, gradients (§5.9), transforms, basic shapes (including the tessellation decision, §4.3), math, random, noise, mouse and keyboard.
- First version of the stable verb ABI (§4.7), with its C ABI, and the verb registry it is generated with (name, parameters, connecting words, description).
- Commands that describe themselves (kind, position, size, colour, an empty source-span slot, §4.3), lazy pipeline creation with a fallback, one seed per run with the single random and noise implementation (§4.7).
- Headless rendering: the golden-image harness renders N frames offscreen to PNG, which Phase 2 exposes as `roci run --frames`.
- Golden-image test harness (render offscreen, compare against reference PNGs with tolerance).
- Mobile: the Phase 1 examples running on an iOS device and an Android device.
- **Exit**: `examples/circle.odin` and a 100,000-circle benchmark at 60 fps; two windows exchanging a message; runs on iOS and Android.

**Phase 1 dependency checks** (2026-10-27, from the projects' own repositories and Odin's installed source):

- **SDL_shadercross** (Zlib): no tags or releases; pinned at `1ff05bec573988a98ef9e0260b4da44f512b8367` (2026-09-03) in `SHADERCROSS_COMMIT`. It needs SPIRV-Cross (Apache-2.0) for SPIR-V and Metal output and DXC (LLVM Release Licence) for HLSL input and DXIL; its README lists no host platforms, and its own `AGENTS.md` forbids AI-generated contributions (§3). **Microsoft ships DXC only for Windows and x86-64 Linux, so shadercross's HLSL path cannot be built on a Mac** (checked 2026-10-27), and DXIL is made only where DXC's signing library exists (Windows). Decided 2026-10-27: `shaders/compile.sh` runs the same steps by hand on a Mac or Linux computer (HLSL to SPIR-V with glslang, SPIR-V to Metal with SPIRV-Cross) and `shaders/compile-dxil.sh` makes DXIL with `dxc` on Windows; both write the committed `shaders/compiled/`. shadercross can replace them where DXC exists. Used only as build tools, so nothing is shipped.
- **PNG output:** Odin's `core:image/png` only reads PNG; the image packages that write are `bmp`, `tga`, `qoi` and `netpbm`. The golden-image harness therefore writes PNG with a small writer of our own (stored deflate blocks, `core:hash` CRC-32 and Adler-32), tested by reading its files back with `core:image/png`.
- **C ABI exports:** `@(export, link_name = "...")` on a `proc "c"` works, as Spike 2's `rocinante_main` shows; the Odin overview does not describe it, so the C ABI step tests it with a C program before the header is generated.

**Phase 1 results** (hand runs, kept short; counts and timings are in git history):

- **`roci/gfx` renderer** (2026-10-27, macOS only so far): `examples/shapes` and the ten golden scenes draw correctly through Metal (circles, ellipses, rects, triangles, lines, points, outlines, transparency, transforms, origins), and the golden comparison is exact against itself. The references in `tests/golden` were made on Metal, so they must be remade on Mesa's software Vulkan (lavapipe, the policy in §9) before the golden run joins the pipelines. **FreeBSD (Vulkan, invictus, 2026-10-27):** `examples/shapes` runs, and the golden scenes drawn there agree with the Metal references to within a few dozen edge pixels (worst channel 25 to 58 on smoothed edges); nine of ten are inside the tolerance and `lines_and_points` is not (61 pixels differ by more than 12, worst channel 42, against 40 allowed). That is drivers smoothing edges differently, not a drawing fault, and it is why the references are to be remade on lavapipe and the pipelines compare lavapipe with lavapipe. Not yet done: Linux, Direct3D 12 (needs the DXIL files from Windows) and the pipelines' SDL3 install (Ubuntu 24.04 has no SDL3 package). An outline's width follows the transform, as in Processing. **Mesh step** (2026-10-27, macOS): quads, arcs, and rectangles, triangles, lines and points whose style needs mitred or bevelled corners or butt or square ends (`needs_mesh`) are cut into triangles by package geom and drawn by `shaders/mesh.hlsl`; both pipelines draw into a 4x multisampled target resolved onto the window, which smooths mesh edges (decided 2026-10-27: multisampling instead of a hand-built edge fringe). Mitre is the default join and round the default cap, as in Processing. The thirteen golden scenes were redrawn and checked by eye on Metal; the Vulkan references and DXIL are still to come.
- **`roci/platform`, `examples/window`** (2026-10-27): runs on macOS (Metal; 3 seconds, 228 frames, no errors, pixel density 1, so that display may not be Retina and a Retina check is still to do) and on FreeBSD (invictus, Vulkan; Fabrizio confirmed it works). Still to run: Linux and Windows.

### Phase 2: The language
- Lexer, parser, checker, type inference, typed IR, interpreter (§4.7, §5).
- Inference error messages written before the inference rules are final (§5.3).
- `circle 100 100 50` as a whole program.
- `docs/grammar.ebnf` and source spans on every node, literal and runtime command (§5.14); an error-tolerant parser that resynchronises at `[ ]` and reports every error in one pass (§5.7).
- `roci run` with file watching, hot reload with the state rules of §5.5 (saying whether it reloaded or restarted), `Ctrl+R` restart, error overlay, and the headless options `--frames`, `--screenshot` and `--errors json` (§7).
- The verified example corpus: each example in `examples/` has a task description and a reference PNG, so it doubles as a golden test and as documentation (§9).
- Sketch folders (§4.9): `roci new`, `roci init`, `roci add`, git and optional Git LFS setup, asset lookup by name, the outside-`assets/` error, live asset reload.
- Error message catalogue with tests, including bracket mismatches located by indentation (§5.1), missing argument brackets (§5.1, §5.7) and every `learn`/`give`/`stop` rule (§5.11).
- `roci fmt`: formatting is idempotent (formatting twice changes nothing) and never changes behaviour (formatted and unformatted sketches produce identical frames).
- List verbs (`keep`, `skip`, `collect`, `combine`, `find`, `sort … by`, §5.2).
- Turtle, events, timers, tweens, taught verbs (`learn`, `give`, `stop`, `with` defaults, sharing rules, §5.11), window messaging.
- 2D collision detection (§5.13) with its broad phase.
- Multi-file sketches and `.roci` libraries (§5.10): `use`, `hidden`, `roci get`, `roci update`, `libs/` vendoring, clash rules and their error messages. The public index starts small in Phase 9.
- **Exit**: every Phase 1 example rewritten in `.roci`; every example infers fully (no boxed fallbacks) or the fallback is justified here; a newcomer test (someone who has never seen rocinante makes a moving sketch in 15 minutes, observed and written up here), run with two groups that see the same sketches written with one thing per argument and in bare Logo nesting, with the comparison recorded here (§5.1). The test also watches for three traps from Logo's history: `[ 1 2 ]` against `{ 1, 2 }`, a list used where a block belongs, and `b = a` sharing a list or record (§5.1, §5.11).

### Phase 3: Text, UI, images, canvases, shaders
- Text with SDL3_ttf GPU engine (or the alternative chosen at the start of this phase), including copying system fonts into the sketch with the licence check (§4.9).
- `ui` with the full widget set (§5.8) on Dear ImGui: immediate-mode `ui [ ]` blocks, automatic layout, focus and keyboard navigation, text input with IME and on-screen keyboards, touch sizing, theme, value persistence in `ui.toml` (with the `toml` package written for it, §4.9), custom widgets.
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
- `sketch.toml` (§4.9): the packaging questions, the version schemes checked against each store's limits, and the build number. Apple's version rules are read from its documentation first.
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

- **Unit tests come first** (decided 2026-10-25): every package is written with `@(test)` procedures from its first commit, aiming for the best possible coverage (§3). `odin test <dir>` runs them, `-define:ODIN_TEST_NAMES=package.test_name` runs one, and `ci` runs every package's tests, so a failing or missing test fails the pipeline. The kinds of test below are in addition to unit tests, not instead of them.
- Language: parser, checker and inference unit tests; one test per error message in `tests/errors/`.
- Formatter: every example and test sketch is run through `roci fmt` twice; the second pass must change nothing, and the formatted sketch must parse to the same typed IR as the original. Sketches with bare nested calls are formatted into the bracketed form and checked for identical IR.
- Rendering: golden-image tests per verb and per backend where CI allows. Every `.roci` example in `examples/` is also a golden test: its reference PNG is rendered headless with a fixed seed (§4.7).
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
- Versions: `sketch.toml` read and written (missing file, hand-edited invalid values), each version scheme checked against every target's limit, and the build number never decreasing (§4.9).
- Toolchain: `roci doctor` tested on machines (or CI images) with each toolchain piece missing, wrong version and present. For every host and target pair, `roci doctor` and `roci package` give the "cannot be built on this computer" message exactly when §7's table says so.
- Performance: benchmark sketches tracked in both modes. Timing is gated only on ORION, whose hardware is fixed (lavapipe and shared GitHub runners are too noisy); elsewhere the pipeline compares work counts (draw calls, batches, allocations), which are exact. A timing regression of more than 10% on ORION fails the build.
- Platforms: Linux in the pipeline on every commit to `main`; every other target through the release checklist before each tag, and at least once per phase (§11).
- Golden images run on Mesa's software Vulkan driver (lavapipe) in the pipeline, so results don't depend on the machine's GPU. `tests/golden` draws every scene in `scenes.odin` offscreen through the real renderer at 2x and compares with the reference picture (a few pixels of difference allowed, `TOLERANCE` per channel); it is a program rather than `odin test` because SDL's video system must start on a Mac's main thread.

---

## 10. Decisions and open questions

### Decided

- **2026-10-22, Licence: Zero-Clause BSD (SPDX `0BSD`).** The most permissive OSI-approved licence: an unconditional grant to use, copy, modify and distribute for any purpose, plus a warranty disclaimer, with no attribution requirement. Applies to the core, the language, `roci`, the docs and all examples. Dependency rules are in §3.
- **2026-10-22, Blocks: `[ ]`**, as in Logo. Not `end`.
- **2026-10-22, Paradigm: procedural and data-oriented**, verbs on plain data, no objects; Odin-inspired array programming, verb groups, useful zero values, no exceptions, implicit style context; capturing blocks and a light functional layer for lists. Full text in §5.2.
- **2026-10-22, Typing: inferred static typing**, no type syntax for users, plain-language conflict errors, boxed fallback where inference cannot decide. Full text in §5.3.
- **2026-10-23, Implementation language: Odin** (replaces Rust). Core and `roci` in Odin; `vendor:` libraries first, our own bindings to the latest upstream when they lag; C and C++ libraries through Odin's foreign system; fixes contributed upstream. Full text in §3 and §4.
- **2026-10-23, Execution: interpreted in development, compiled ahead of time for release by generating Odin source** built with the pinned Odin compiler that `roci` fetches (replaces the Cranelift plan). One shared front end and typed IR; no bytecode VM, no JIT. Full text in §4.7.
- **2026-10-23, Toolchain for packaging is user-installed, except Odin** (revised 2026-10-24: `roci` fetches the pinned Odin into its own cache, checks its checksum, and on FreeBSD builds it from source; revised 2026-10-25: Android also needs a JDK, fetched the same way): MSVC on Windows, Xcode on Apple platforms, clang on Linux and FreeBSD; `roci doctor` guides installation; `roci run` needs none of it. Android SDK, NDK and JDK are managed by `roci`. Full text in §4.7; non-negotiable 2.
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
- **2026-10-24, `roci` fetches the pinned Odin** into its own cache, and on FreeBSD, where Odin has no official archive, builds it from the source tag. Full text in §4.7.
- **2026-10-24, Top-level `load` waits; loads inside `draw` and events are asynchronous.** Full text in §4.4.
- **2026-10-24, UI identity is label, panel and tab path, and loop index; `ui.toml` is keyed by it and written on exit and after pauses; rocinante writes its own `toml` package** (neither `core:` nor `vendor:` has one). Full text in §4.8 and §4.9.
- **2026-10-24, Files other than `sketch.roci` hold definitions only**, evaluated in dependency order before it. Full text in §5.5 and §5.10.
- **2026-10-24, Trust and signing**: `roci get` and `roci run` ask once before loading a native extension from a git URL; `roci package` covers macOS notarisation (Developer ID) and Windows SmartScreen and says what is left for the user; `roci` shows the Android SDK licence for acceptance; built-in ML models record their source URL and a checksum, and `roci run` needs the network once to fetch them. Written into §4.10, §5.10 and §7.
- **2026-10-24, Physical key positions**: `keys w a s d` binds by SDL scancode, so AZERTY works (§5.12). Dear ImGui does not shape complex scripts (Arabic, Devanagari): Phase 3 states which scripts the UI supports and tests them with an IME.
- **2026-10-24, Origin words**: `as center` and `as corner` (default) say what a shape's or image's position means, per element, replacing Processing's four `*Mode` verbs; an `as` straight after a shape's required arguments is its origin, an `as` after a `fill` or `stroke` value belongs to the value. Full text in §5.9.
- **2026-10-24, Escape does not quit a sketch by default**; Escape leaves the widgets (§4.8), and Cmd+Q, Ctrl+Q and the window's close button quit.
- **2026-10-25, no cross-compilation between desktop systems**: FreeBSD, Linux, macOS and Windows each package for themselves; iOS needs a Mac, Android needs macOS, Linux x86-64 or Windows (§7).
- **2026-10-25, Claude Code never pushes automatically**: only when Fabrizio asks for it in that message. Full text in §3.
- **2026-10-25, all code needs the best possible unit-test coverage**, written with the code; `odin test` runs in `ci`; Phase 0 gets tests for the code it already has. Full text in §3 and §9.
- **2026-10-25, iOS and Android are targets only**: sketches are written, run and packaged on FreeBSD, Linux, macOS and Windows; `roci` does not run on phones, and the on-device live-coding idea is dropped from the roadmap. `roci doctor` says plainly when this computer cannot build a target (iOS only on macOS, Android on macOS, Linux x86-64 and Windows). Full text in §7.
- **2026-10-25, `roci` fetches a JDK (Temurin 21) for Android packaging**, like Odin and the NDK; Android packaging therefore runs on macOS, Linux x86-64 and Windows hosts only (the NDK has no other hosts). Full text in §4.7.
- **2026-10-26, Desktop processors for the first stable release**: x86-64 on FreeBSD, Linux and Windows, and arm64 (Apple silicon) on macOS; "every desktop target" in §8 means these four systems. arm64 FreeBSD, Linux and Windows and Intel Macs are on the roadmap (README.md), which settles the old open question about Windows arm64 and macOS Intel, where Odin publishes no archive (§4.7).
- **2026-10-26, Never commit on `main`**: every change starts on its own branch and reaches `main` only through a GitLab merge request. Full text in §3.
- **2026-10-26, LF line endings in every clone**, set by `.gitattributes`. Full text in the shell and tool gotchas.
- **2026-10-26, SDL patch releases**: results from SDL 3.4.2, 3.4.16 and 3.4.18 libraries count as the same SDL; differences between patch releases are accepted (§8, Phase 0 results).
- **2026-10-26, `CHANGELOG.md` and `CONTRIBUTING.md` are pointers**: the first to the releases page (release notes stay on the tags), the second to README's Contributing section, so neither duplicates what lives elsewhere. Full text in §4.2 and §11.
- **2026-10-27, Plain words, not English sentences**: the goal of reading close to English is dropped for good; every construct has one canonical form with a fixed word order. Full text in §5.1.
- **2026-10-27, `sketch.toml`**: an optional file beside `sketch.roci` for packaging details and the version (any scheme, `1.0.1` or a date); `roci` owns the build number and checks the version against each store's limits. Full text in §4.9.
- **2026-10-27, Research notes folded in** (Logo's history, language trends): `[ ]` stays a block and a list, with teaching errors for the wrong one; sharing stays, with a hint (§5.1, §5.11). Not adopted: parenthesised calls such as `window(800, 600)` (no call parentheses, §5.1), value semantics (sharing stays), a `learn shader` subset (HLSL is decided, §4.3), quantity suffixes such as `90 degrees` (angles are degrees, §5.15), user-visible effect handlers, and live coding on phones (§7). The file extension is `.roci`.
- **2026-10-23, Sharing: numbers, vectors, colours and text are copied; lists and records are shared**; `copy` makes an independent copy. Full text in §5.11.

### Later

Ideas that are wanted but not planned for the first stable release live in the Roadmap section of `README.md`, so contributors can see them. When one is taken up, it moves here and into §8.

### Open

Decide these with Fabrizio; move each to "Decided" with the date.

1. Machine learning on FreeBSD: LiteRT's C runtime built there, or ONNX Runtime as the FreeBSD fallback (§4.10). Settled by the LiteRT spike at the start of Phase 6.
2. ExecuTorch as a second runtime for PyTorch's own `.pte` files, so PyTorch models skip conversion. It is C++ only, so it would need our own C wrapper, and a second runtime is a second behaviour to keep equal (§4.10).
3. Choices inherited from the sections they point to: vector tessellation (§4.3, Phase 1); text engine (§4.3, start of Phase 3); AIFF, Opus and AAC decoding (§4.6, Phase 5); MIDI on FreeBSD, iOS and Android (§4.6, Phase 5); mobile multi-window behaviour (§4.5, Phase 8); video encoder libraries (§4.11, Phase 6); the Git LFS type list (§4.9, Phase 2); the name of `roci check --why-slow` (§5.3, Phase 2); Box3D for 3D collision (§5.13, Phase 4); AccessKit on FreeBSD (§4.8, Phase 3).
4. Time in verbs (Phase 2, before the interpreter is designed): whether a taught verb can `wait` (a strand on a logical clock, as in ChucK and Sonic Pi) beyond `every`, timers and tweens (§6). If yes, a loop that never waits is a teaching error, not a hang (Sonic Pi's rule, §12), and compiled code needs fibers or a state-machine transform of suspending verbs.
5. Interpreter shape (Phase 2): it walks the typed IR (§4.7, no bytecode VM). The trigger for revisiting is a measured one, when the interpreter proves too slow for development use; the candidate is a register bytecode on Odin's `#must_tail` with the `"preserve/none"` calling convention (Odin newsletter 2026 Q1, §12; check its docs first), benchmarked against a switch fallback on every Odin upgrade.
6. `roci explain` (name provisional, Phase 2): describe a line or block in plain words from the typed IR, for learners and for tools.
7. The accessible canvas (Phase 3): scene descriptions built from the command records (§4.3), a `describe "…"` verb, a live region that updates only when the scene changes, and colour-contrast checks, extending §4.8 from widgets to the canvas (p5.js does this with `describe` and `textOutput`, §12).
8. Libraries and `sketch.toml` (Phase 9): whether a library keeps its version in the same file, so `roci update` can say "flocking 1.2.0 to 1.3.0" (§4.9).
9. Teaching profiles (Phase 9): lint settings over one stable language, not Hedy-style levels where commands change.

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

- `origin` is GitLab on ORION (Arch Linux), where all daily work goes. Fabrizio pushes it; Claude Code does not push unless asked in that message (§3).
- `github` is the public mirror, `https://github.com/sandbenders/rocinante` (decided 2026-10-24, because the `Rocinante` organisation name is taken). About twice a week: `git push github main --tags`. Pushed by hand, not by GitLab's push mirroring, so GitHub only receives snapshots Fabrizio chose to publish.
- Issues and pull requests from the community arrive on GitHub. A pull request is accepted by fetching its branch locally, merging it through the normal GitLab flow, and pushing to GitHub; the README explains this to contributors.

**Pipelines (Linux only).**

- Both pipelines are thin wrappers: install the pinned Odin (read from the `ODIN_VERSION` file), SDL3 and Mesa's software Vulkan, then call the build script's `ci` command. All logic is in the build script, so the two can't drift apart.
- **GitLab** (`.gitlab-ci.yml`, runner on ORION, Arch Linux):
  - **fast check** on merge requests only (`rules: - if: $CI_PIPELINE_SOURCE == "merge_request_event"`): build, unit and language tests, error-message tests, format and licence checks;
  - **full pipeline** on every commit to `main` (`rules: - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH`): everything in the fast check plus golden images, back-end equivalence and benchmarks;
  - **release** on tags matching `v*`: the full pipeline plus the Linux release artefact.
- **GitHub** (`.github/workflows/ci.yml`, Ubuntu 24.04 runner, pinned so GitHub's `ubuntu-latest` move to 26.04 never changes what we test; we move it on purpose): the full pipeline on push to `main`, and the release job on `v*` tags (`on: push: branches: [main]` and `tags: ['v*']`). No merge-request job. Because GitHub runs Ubuntu and ORION runs Arch, every snapshot is tested on two distributions. SDL3 has no package on Ubuntu 24.04, so the workflow builds the latest stable SDL3 release from source with `tools/ci/install-sdl3.sh` and caches it under a key that holds the release's tag (decided 2026-10-27): a new SDL release rebuilds, an unchanged one is restored from the cache. The same job installs Mesa's software Vulkan for the golden images.
- No GPU is needed: golden images render through lavapipe (§9).

**Releases.**

- **Versions are calendar-based: `YYYY.MINOR.MICRO`** (CalVer; the scheme JetBrains IDEs use). `YYYY` is the year of the release, `MINOR` counts feature releases within that year starting at 1, and `MICRO` counts fix releases of that feature release starting at 0. The first release of 2026 is `2026.1.0`, its first fix `2026.1.1`, the next feature release `2026.2.0`, and the first release of 2027 is `2027.1.0`, whatever the count reached in 2026.
- A release is an annotated tag `vYYYY.MINOR.MICRO` on `main` (for example `v2026.1.0`), so the `v*` tag rules of both pipelines apply unchanged.
- The version does not signal compatibility. Releases before the first stable release are marked as previews in their release notes. After it, any change that breaks existing sketches, the stable verb ABI or `ui.toml` is listed at the top of the release notes with the fix for each, and `roci check` explains it in plain words when it meets the old form.
- Before tagging, work through the release checklist (`docs/release-checklist.md`): build and run the examples, golden-image and equivalence suites on FreeBSD, macOS, Windows, iOS and Android, record the results in the checklist's table for that version, and build those platforms' artefacts locally. The Linux artefact comes from the tag pipeline.
- Release notes are written on the tag (GitLab and GitHub releases), not in a separate changelog file. `CHANGELOG.md` only points to the releases page and keeps no history (decided 2026-10-26).
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
- Cook, "AppleScript" (HOPL III, 2007; why naturalistic syntax is hard to write and diagnose): https://pdos.csail.mit.edu/6.828/2007/readings/applescript.pdf
- Solomon, Harvey, Kahn et al., "History of Logo" (HOPL IV, 2020; Logo's parsing, scope and sigil traps): https://people.eecs.berkeley.edu/~bh/HOPL.pdf
- Victor, "Learnable Programming" (hidden state in Processing, the turtle): https://worrydream.com/LearnableProgramming/
- Hermans, "Gradual Programming in Hedy: A First User Study" (2021; errors read aloud): https://www.hedy.org/research/Gradual_Programming_in_Hedy_A_First_User_Study_2021.pdf
- Swidan and Hermans, "A Framework for the Localization of Programming Languages" (SPLASH-E 2023): https://www.hedy.org/research/A_Framework_for_the_Localization_of_Programming_Languages_2023.pdf
- Becker et al., compiler error messages considered unhelpful (summary): https://neverworkintheory.org/2021/09/02/compiler-error-messages-considered-unhelpful.html
- Sam Aaron, live coding in education (Sonic Pi: a loop that never waits is an error): https://sonic-pi.net/files/articles/Live-Coding-Education.pdf
- Schanzer, Bahram and Krishnamurthi, accessible AST-based programming: https://cs.brown.edu/~sk/Publications/Papers/Published/sbk-accessible-ast-blocks/paper.pdf
- p5.js web accessibility (`describe`, `textOutput`): https://p5js.org/contribute/web_accessibility/
- Odin newsletter 2026 Q1 (`#must_tail`, `"preserve/none"`): https://odin-lang.org/news/newsletter-2026-q1/
- Android app versioning (`versionCode`, `versionName`): https://developer.android.com/studio/publish/versioning
- Windows VERSIONINFO resource: https://learn.microsoft.com/en-us/windows/win32/menurc/versioninfo-resource
- Apple App Review Guidelines (2.5.2): https://developer.apple.com/app-store/review/guidelines/
- nannou (prior art, built on Bevy): https://github.com/nannou-org/nannou
- LiteRT (runtime, platforms, accelerators, LiteRT Torch converter): https://github.com/google-ai-edge/LiteRT
- LiteRT C APIs (`tflite/c/c_api.h` classic, `litert/c/` newer; the old `tensorflow/lite/c/` path is gone): https://github.com/google-ai-edge/LiteRT
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
