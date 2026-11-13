# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

This file and `docs/design.md` (imported below) are together the single source of truth for rocinante's design, scope and plan. When a decision changes, update the file that holds the section, in place. Do not create other design documents, changelogs of decisions or "notes" files beside them. `docs/phases.md` is the one exception, and holds no decisions: the history of the closed phases (what they built, measured and found), kept out of this file so it stays short. `MANIFESTO.md` is the public statement of intent; this file is how we build it.

Read `MANIFESTO.md` before starting any work. Every decision below serves it.

## Start here

- `main` moves between sessions and other work lands without this file being re-read: run `git fetch` and read `git log --oneline origin/main -20` before trusting anything below.
- Branch first, never commit on `main`, never push (§3). Fabrizio pushes, opens the merge request and merges. When he says a branch is merged, check `git rev-list --count origin/main..<branch>` is 0, fast-forward `main` and delete every merged local branch with `git branch -d`, without waiting to be asked (decided 2026-10-28).
- Run `odin run build -- ci` before handing a branch over.
- Phases 0, 1 and 2 are closed (§8; Phase 2 on 2026-10-30): the language exists end to end (front end, checker, interpreter, `roci run`/`check`/`fmt`/`man`/`test`, libraries, input, the turtle, collision, tables, tweens); the code map below says what each piece does. Phase 3 has built text (§4.3), pictures, pixels, canvases, picture fills, `blend` and `clip`, user and built-in shaders (`effect`, `shade`, also on canvases) and export (`save` to PNG, SVG and PDF, `record` to APNG or, through the user's ffmpeg, video); Odin is `dev-2026-11`. The UI (Dear ImGui and AccessKit, §4.8) is being built in slices: the core (`roci/ui`) and the widgets so far in the language (`ui [ ]`, `label`, `button`, `toggle`, `slider`, `number`, `textbox`, `dropdown`, `choice`, `progress`, `separator`, `tip`, `panel`, `row`, `column`, `tabs`, `tab`, `menu`, `list`, `colorpicker`, `knob`, `range`, `xypad`, `image button`, `ui hide`, `ui show`, `ui key`, `ui theme`, `forget ui`, with `at` and `width` and `ui` inside `draw`) are done; `ui.toml` (the values the widgets keep, remembered by `roci run` in the sketch folder) is done; the screen-reader bridge works on macOS (VoiceOver) and on Linux, FreeBSD and OpenBSD (Orca), checked by hand on 2026-11-09 and 2026-11-10 (Linux: CachyOS under niri, Wayland), and on Windows (Narrator and NVDA, on Direct3D 12), checked by hand on 2026-11-11 with `examples/ui`. Ten classic Processing examples are ported (`bounce`, `sinewave`, `rope`, `life`, `flocking`, `koch`, `mandelbrot`, `noisewave`, `recursion`, `colorwheel`); the two-window sketch is built (`examples/studio`, checked by tests with a screen reader's requests, the keyboard and the mouse, and to be tried by hand with VoiceOver, Narrator or NVDA and Orca, and with a finger); what is left of the exit criteria is that hand check and the input method.

## Commands

Everything is driven by the build script in `build/`, written in Odin; there is no Makefile or CMake for contributors. Run it from the repository root with the Odin release named in `ODIN_VERSION` (`odin version` must match it; the build script warns locally and fails in the pipelines when it does not).

```
odin run build -- ci            # exactly what both pipelines run
odin run build -- ci --fast     # the pre-push subset (git config core.hooksPath tools/hooks)
odin run build -- licences      # dependency licence check against tools/licences.txt
odin run build -- ui-libs       # build Dear ImGui into .cache/ui (git and a C++ compiler; on Windows MSVC's cl and lib, from Git Bash started inside vcvars64.bat); `ui-libs regenerate` also remakes vendor/imgui (needs python3, only for dear_bindings)
odin run build -- odin          # check the installed Odin against ODIN_VERSION
odin run build -- docs          # the documentation site into output/site/public (Hugo, HUGO_VERSION)
odin run build -- docs serve    # preview it with Hugo, rewriting each file of site/ as it is saved (pictures drawn once)
VK_DRIVER_FILES=$(command ls /usr/share/vulkan/icd.d/lvp_icd*.json | tr '\n' ':') SDL_VIDEODRIVER=offscreen odin run build -- docs   # the same with no screen (off, locked, a server): drawn on lavapipe
odin check <dir> -vet -strict-style           # type-check one package
odin test <dir>                               # run its @(test) procedures (core:testing)
odin test <dir> -define:ODIN_TEST_NAMES=package.test_name   # run a single test
odin test cli -out:output/tests/cli -define:ODIN_TEST_NAMES=main.test_name   # the cli package is `main`; the name is package.test_name for every package, so check the package line of the test file
odin test <dir> -out:output/tests/<name>.exe  # on Windows: keep the test program out of the repository root, as ci does
```

**SDL3 and SDL3_ttf must be installed to run `ci`** (SDL3_ttf: Arch `sdl3_ttf`, macOS `brew install sdl3_ttf`, the pipelines build it with `tools/ci/install-sdl3.sh`, on Windows Odin ships `SDL3_ttf.lib` and `SDL3_ttf.dll` in `vendor/sdl3/ttf`, checked 2026-11-05; OpenBSD has no package: build it from source, the steps are in README.md; the FreeBSD package is unchecked): the unit tests of `roci` link them, because the API can start a window even though the tests run headless. Arch has `sdl3`, FreeBSD `pkg install sdl3`, OpenBSD `pkg_add sdl3`, macOS `brew install sdl3`, the GitHub pipeline builds it (§11), and on Windows Odin ships `SDL3.lib` (and `SDL3.dll` and `SDL3_ttf.dll`, which must sit beside any program that opens a window: `cp "$(odin root)/vendor/sdl3/SDL3.dll" "$(odin root)/vendor/sdl3/ttf/SDL3_ttf.dll" .`, both ignored by git). `ci` runs `odin test` on every package listed in `TEST_PACKAGES` in `build/main.odin` (add a package there as soon as it has tests), and a failing test makes `ci` exit with 1. Tests run from the repository root, in parallel threads, and some make fixtures under `output/`. A test file that builds maps or dynamic arrays from literals needs `#+feature dynamic-literals` at the top.

Hand runs, each from the repository root (`-- seconds` closes a window after that long, for scripts):

```
odin run examples/circle [-- seconds]         # the smallest sketch
odin run examples/garden [-- seconds]         # the Phase 1 demo: two windows, every Phase 1 feature through the public API
odin run examples/two_windows [-- seconds]    # two windows that send each other messages
odin run examples/shapes [-- seconds]         # roci/gfx by hand: every shape through the renderer
odin run examples/window [-- seconds]         # roci/platform by hand: windows, events, N / F / V keys
odin run examples/benchmark -o:speed -- [seconds] [count] [novsync] [headless]   # 100,000 circles a frame; frame rate and where the time goes
odin build cli -o:speed -out:output/roci && output/roci run examples/benchmark   # the same through the interpreter, its frame rate printed each second
odin run cli -- run examples/garden/sketch.roci [--frames N --screenshot out.png --window 2 --seed N --errors json]   # run a sketch in the language (a folder runs its sketch.roci); with --frames, headless
odin run cli -- check <file or folder> [--types --tree --errors json]   # parse and check, and say every mistake
odin run cli -- fmt [file or folder]          # write sketches in the house style; no name means every .roci file here
odin run cli -- man [word]                    # how a verb or statement is written, made from the registry
odin run cli -- test [folder or file] [--accept [--frames N] [--seed N]]   # run the checks of a sketch and compare its picture with tests/snapshot-1.png; --accept stores the picture
odin run cli -- new <name> | init | add <file>   # a sketch folder, its files in this folder, a file into assets/
odin run cli -- get <git address> [--as name] | update [name]   # copy a library into libs/ from git, and fetch newer copies (run in a sketch folder)
ROCI_UPDATE_TREES=1 odin test roci/interp      # write tests/ui-tree/*.txt again: the screen-reader trees of the examples that have widgets (review them like code)
ROCI_UPDATE_ERRORS=1 odin test roci/lang      # write tests/errors/**/*.txt, tests/check/*.types and examples/*/sketch.types again (review them like code); roci/interp does the same for tests/errors/runtime (run both after a message changes, as a runtime message such as `Expect_Failed` is rendered by interp)
ROCI_GPU_DEBUG=1 odin run examples/shapes     # any program with GPU validation on (off by default)
ROCI_PASSES=off output/roci run <sketch>      # the interpreter with no optimisation pass: the reference the passes are compared with
odin run tests/golden [-- update | scene]     # golden images: scenes drawn offscreen, compared with tests/golden/*.png
odin run tools/header -- include/roci.h       # regenerate the C header from the registry (a test fails when it is stale)
odin run tools/site -- --logo                 # write the README's wordmark pictures and the logo's 192-pixel PNGs again from docs/logo/rocinante-logo.svg (a test fails when they are stale)
tools/abi-check.sh [--run]                    # build roci as a shared library, check its exports match the header, build examples/c/circle.c
shaders/compile.sh                            # HLSL to SPIR-V and Metal (glslang, spirv-cross); shaders/compile-dxil.sh makes DXIL on Windows
odin run spikes/codegen -- check              # Spike 3: interpret, generate Odin, build it, compare output
odin run spikes/codegen -- doctor [host]      # which targets this computer can build, and the toolchain
odin run spikes/mobile/macos                  # the phones' sketch on the desktop, 5 seconds
spikes/mobile/android/build.sh --install      # needs SDL_ANDROID_LIB and SDL_ANDROID_JAVA
spikes/mobile/ios/build.sh --install          # needs SDL_IOS_LIB, TEAM_ID and DEVICE
sh tools/ui-libs.sh accesskit                 # fetch accesskit-c into .cache/ui/accesskit (curl and unzip; cargo and cmake where no release library exists); odin run tools/accesskit writes vendor/accesskit again
spikes/ui/setup.sh                            # Spike 4, once: Dear ImGui, dear_bindings and accesskit-c into .cache/ui (setup-windows.sh with MSVC)
odin run spikes/ui [-- interactive]           # Spike 4: slider, button, text box, and the screen-reader bridge on macOS
```

The phone scripts need SDL 3.4.18 built for the phone, which is not in the repository (the recipe is in the Phase 0 results in `docs/phases.md`).

**What `ci` does not cover.** `ci` type-checks and tests the build script, `tools/term`, Spike 3 and every package under `roci/`. The full `ci` (not `--fast`) also runs every package's tests a second time built with `-o:speed`, so the optimiser can never change a result unnoticed (non-negotiable 7), and runs the golden images and `roci test examples/checks` on lavapipe (`build/golden.odin`), skipping them with a note where lavapipe is missing and failing instead when `ROCI_REQUIRE_LAVAPIPE` is set, as both pipelines do. It type-checks the examples, `tests/golden` and the phones' sketch. It does not run anything else that needs a window, a GPU, a phone, or the libraries `spikes/ui/setup.sh` builds: example runs, golden images on real GPUs, the phone spikes, Spike 4 and the SDL window code are checked by hand, and a change to them needs a hand run on the affected systems before it is called done.

**On Windows** (Direct3D 12 only; no Vulkan SDK, shaderc or SPIRV-Cross is ever installed there): run `ci` and `ui-libs` from Git Bash started inside `vcvars64.bat` (the recipe is in the Windows gotcha below), because `ci` builds `.cache/ui/roci_ui.lib` with MSVC when it is missing and a plain `cmd` has no `sh`. After an Odin upgrade copy its `vendor/sdl3/SDL3.dll` into the repository root again (and beside `output/roci.exe` to run that). Lavapipe does not exist there, so `ci` skips the golden step and `roci test examples/checks` with a note; `odin run tests/golden` by hand draws on Direct3D 12 against the looser limits for a real GPU, and a few dozen edge pixels off in a dozen or so pictures (and thousands in `example_rays_1`, whose hairlines make a moiré) is the GPU, not a fault; read the scenes that matter for the change (`effects`, `shader_fills`) and check its first line says `direct3d12`.

**Terminal output** is coloured through `tools/term`: every command that prints for people, including `doctor`, paints headings, results and errors with it and marks results with ✅, 🚫 and ❌ (`term.out_icon`). Colour is on only when the stream is a terminal and `NO_COLOR` is unset, the words are identical with or without it, and piped output and the pipelines stay plain. New commands use `term.out` and `term.err`, never raw escape codes.

**Where things are.** This file holds the rules, the plan and the decisions; `docs/design.md`, imported below, holds the architecture details, the language and the parity map; section numbers are global, so `§5.9` is in `design.md` and `§8` is here. `spikes/` is throwaway Phase 0 code, not the planned packages. The real packages (§4.2) are created as their phase needs them: `roci` (the public API), `roci/maths`, `roci/registry`, `roci/platform`, `roci/geom`, `roci/gfx`, `roci/lang` (the language front end, started in Phase 2), `roci/interp` (the interpreter), `roci/collide` (2D collision detection), `roci/folder` (sketch folders and their assets) and `cli` (the `roci` binary) exist, all in `TEST_PACKAGES`; `vendor/` holds sancho (above); the rest of the language packages come later. Each new package updates this paragraph and the code map below in the same commit, joins `TEST_PACKAGES` and says which spike it replaces. `output/` and `.cache/` are generated and ignored by git.

**The code that exists so far** (only what the code does not say itself: invariants, traps and why. Keep each entry to a few lines when you add one; the code and its tests hold the rest, and this file is loaded every session):
- `build/`: `ci` is a list of `step` calls in `check_packages`, so a new package or spike joins the pipelines there and in `TEST_PACKAGES`; `check_optimised_tests` repeats every test with `-o:speed`; `check_tracked_fonts` fails when git tracks a font rocinante does not ship. `build/golden.odin` runs `tests/golden` on lavapipe only (the loader gets just the `lvp_icd*.json` manifests, and it fails unless the device says llvmpipe).
- `spikes/` is throwaway Phase 0 code (`spikes/codegen` is the pipeline in miniature, `spikes/ui` is not in `ci`).
- `roci` (the public Odin API): the verbs over one thread-local sketch, `the`. Verbs act on the *current window*: the default window while setting up (made by the first verb), the window whose `draw` runs during a frame, otherwise the window the last `window` call made. `step(events, dt)` is one frame and drives a **headless** sketch (`start_headless`, no SDL); it runs the frame in memory of its own (`context.temp_allocator` inside the frame) and frees it when the frame ends, headless or not, writing `0xDD` over it first in tests (`poison_frames`), so a pointer from long-lived data into frame memory fails in a test; what the caller made with its own temporary allocator is left alone. `api_table.odin` says which Odin procedure answers each registry verb (a test fails when one is missing). Ctrl/Cmd+Q quit; Escape does not.
  - Mouse buttons and fingers are held **per window** (`Win.buttons`, `Win.fingers`); fingers are numbered from `next_finger` and never reused in a run; losing focus releases every key and button. `events.odin` keeps the frame's log; `set_frame_hook` runs the interpreter's `on`, `every` and messages before the window's `draw`. `overlay.odin` draws the error band after the frame is built and takes it off the list again (`gfx.mark`, `gfx.rewind`). `begin_restart`/`end_restart` hand the open windows to a restarted sketch in order.
  - `window_settings.odin` holds every window setting (remembered on the `Win` so headless can answer, handed to SDL when there is a window, put back by a restart); the language's view is `registry.WINDOW_PROPERTIES`.
  - **Canvases** (`canvases.odin`): while `draw into` is on, `current_list`, `width` and `height` are the canvas's; `flush_canvases` runs at the start of every `show_frame` (with `nil` when headless, where rounds wait until `picture` flushes them on its own device, so `picture` of a window with canvases needs a GPU).
  - **Pictures and pixels**: `draw.odin` holds `fill_image` (`Paint` is a colour, gradient or `Image_Fill`; `stroke` and `background` take a picture, text fills compose on the CPU); `WORD_CHOICES` keeps the picture shape's word list under `"fill picture"`. `gfx/picture_ops.odin` is pure CPU work on RGBA bytes with alpha multiplied in first; `pixels.odin` remembers made pictures in `the.derived` by a hash of what made them and `evict_derived` lets go of the longest unused when the made pictures pass `DERIVED_BUDGET_BYTES` (each counted twice, pixels and texture) or `MAX_DERIVED_PICTURES`, down to 90% of it, and costs two comparisons in a frame within the limits (a let-go picture is nil in `image_data`). A picture's number is its store slot plus a generation (`Image_Id`, under 2^24 because commands carry it as a float): a slot let go is reused only after 256 others wait, and a stale number names nothing; `released_images` is cut once every renderer has read it (`image_reader_add`); a canvas is read back by `gfx.canvas_read` (stalls the frame). `set_graphics_refused` is the test knob for that message.
  - **Effects and shaders** (`effects.odin`): `add_shader` translates at once so a mistake is known; `effect` runs a shader over the finished frame or over the canvas being drawn into; `interp/effects.odin` matches a record's fields to the shader's globals by name and retranslates when the file's modification time changes. `outline.odin` makes the solid mask of a picture for `outline` (a canvas gives nothing).
  - **`save` and `record`** (`save.odin`, `record.odin`): `save` queues paths on the window and `show_frame` writes them after the frame is built and before the overlay (so a saved picture never shows an error band); `.svg` and `.pdf` come from the command list with no GPU, and what they leave out is a `Save_Problem` with `approximate` (said as `Save_Approximate`). `record` hands every finished frame to `record_frame`; an `.apng` is kept in memory (512 MB) and written at the end, a video is piped to the user's `ffmpeg` (`find_ffmpeg`, test knob `set_ffmpeg`). `write_all` retries when Odin's `write` gives up on a signal, and `ignore_broken_pipes` stops SIGPIPE ending the sketch. Tests get frames from `set_frame_source` (a real draw would start SDL on a test thread); tests that start the stand-in ffmpeg are the package `roci/movies`, because forking among roci's many test threads killed the child about a run in three on macOS.
  - `touch.odin` sets `SDL_HINT_MOUSE_TOUCH_EVENTS` so the left button is a finger on the desktop; `turtle.odin` keeps the turtle on the list beside the transform (home is the middle of the current window, worked out at each move).
- `roci/abi.odin`, `include/roci.h`, `examples/c/circle.c`: the C ABI, one plain `roci_<verb>` function per shape (colours four floats 0 to 255, `roci_window_id` because `roci_window` is the function). `ABI_TABLE` lists every function; `ABI_NOT_IN_C` lists shapes with no C form and why. Tests fail when a registry shape has neither, a parameter type differs, or the header is stale (`odin run tools/header -- include/roci.h`). `tools/abi-check.sh` exit 3 means it cannot run here (`ci` fails instead when `ROCI_REQUIRE_SDL3` is set).
- `roci/maths`: colours, the one random generator (SplittableRandom), noise, and `sin_deg`/`cos_deg` (exact at right angles, never -0, the same on every system); both back ends call all of it. `ease.odin`: `EASE_NAMES` is kept equal to the registry's words by a test.
- `roci/registry`: the data the language is made from: `VERBS` (Odin API and C header) and `LANGUAGE_VERBS` (interpreter only) make `ALL_VERBS`, built once at start because lookups return pointers into it. `labels.odin` holds the label forms (`circle at 100 100 radius 50` is the shape `x y radius`); `WINDOW_PROPERTIES`; `manual.odin`; `VERB_SYNONYMS` (Logo's `fd` suggests `forward`); `words.odin` `WORD_CHOICES` (a test fails when a word argument has no list). A new verb is a row in `verbs.odin`, its procedure in `roci`, an `api_table.odin` entry and a C entry or `ABI_NOT_IN_C` reason.
- `roci/lang` (grammar in `docs/grammar.ebnf`; no GPU): lexer, `prescan` (reads `learn` headers first), error-tolerant parser (one pass reports every error), checker, typed IR, error catalogue, `report.odin`, `json.odin`, `format.odin`, `highlight.odin`. The files of a sketch folder are **joined into one `Source`** (`join_sources`; only `place_of` knows file and line); `order_files`: library files, other files by name, `sketch.roci` last; only `sketch.roci` may hold statements that run. Every message id needs a sketch in `tests/errors/<id>/` (runtime ones in `tests/errors/runtime/`, run by `roci/interp`); `ROCI_UPDATE_ERRORS=1 odin test roci/lang` rewrites them, review like code. A message's words never hold a bare bracket; `GRAMMAR_RULES` in `parser.odin` is compared with the grammar file by a test.
  - **Parsing traps**: `Label_Form.lead` values are written by position before the label words (`text "hello" at 20 20`). A call ends at its largest shape's argument count, at the end of the line, at a closing bracket, and in a one-line block at two spaces. A connecting word starts an option only once the required arguments are filled (so `width` is a value in `rect 0 0 width height`); a connecting word the call does not take, where a value is still needed, is `Reserved_Name`. Where a verb takes a word (`caps round`), the parser takes it as written even if it is also a verb. After a per-element `fill`/`stroke` value, `parse_paint_words` takes `as`, `size`, `at`, `in`, `angle`, `stops` as that paint's by position alone (`as corner`, and `as center` after a plain color, stay the shape's origin).
  - **Teaching errors the parser builds from the writer's line**: `Needs_Brackets`, `Word_Outside_Brackets`, `Index_Brackets`, `Unknown_Option`, `Hash_Comment`, `Colours_Expected`, `Title_Of_Window`, `Labels_Needed`, `Comma_In_Call`; the lexer says `Habit_Operator` for `==`, `!=`, `&&`, `||` and `!` and emits the `Habit_*` token that stands for the word (`is`, `is not`, `and`, `or`, `not`), so nothing cascades; the checker builds `Set_Window`.
  - **The checker** runs twice (the first pass settles record shapes, merged by `unify`); every name assigned anywhere is sketch-wide from the start, capitals mean constant, an `Error` type fits everything so one mistake gives one message. The loop name of `for each` and `for` is the loop's own: `collect_assignments` does not make a sketch-wide name of it where the body assigns it (that is a write-back to the item), and `Symbol.mutated` on it makes `for each` over a constant list `Constant_Changed_By_Verb`. A `learn` is checked once per distinct tuple of argument types (`IR_Instance`, cached before its body is checked, which is how recursion ends; a verb that calls itself with a bigger value each time, `learn f x [ f [ x ] ]`, would never end that way, so past `MAX_OPEN_INSTANCES` versions inside one another the arguments are taken as mixed values). `check`/`expect` are `IR_Check`/`IR_Expect` (a check is a definition any file may hold; its names are its own). Collision shapes get a `Shape_Class` from the literal's field names (`check_collide.odin`).
  - **The formatter** formats the tree and keeps literals as written; where the style leaves a choice the sketch's choice stands, so formatting twice changes nothing. A test formats every example and `tests/check` sketch and compares trees.
- `roci/interp`: a tree walker over the typed IR calling the same `roci` procedures an Odin sketch calls; `load` runs `lang.optimise` (passes shared with the future code generator; `ROCI_PASSES=off` is the reference, and a test compares every example both ways). A number-typed value can hold the empty value, so only a `Sure_Number` is stored or passed as a plain number. **Memory**: sketch set-up values live in the `values` arena, block values in the temporary allocator freed each frame; `promote` deep-copies into the arena when stored in a sketch-wide name or long list; `collect.odin` copies live values into the other arena between frames. Every walk over a value (`promote`, `deep_copy`, the collector, reload's `convert`, `equal`) uses a list of work and no recursion, so a chain of 100,000 records is safe, and the copies copy each list, record and table once, so sharing and self-holding values survive; a new walk must do the same. **Runtime failures never stop a sketch** (empty value or 0 plus a `Runtime_Error`, said once per place; recursion 100 deep and a block over its 2-second budget too). Verbs are a switch on `Verb_Code` (`codes.odin`; switching on names cost a fifth of a busy frame), and a field is read, made and set by its place in the shape when the `Field_Slots` pass found it (`IR_Field.at`, guarded by the record's shape, by name otherwise); a test fails when the registry gains a verb with no code. `send` copies the value into one of two message arenas. `give` and `stop` are a `Flow` status, never an exception.
  - **Reload** (`reload.odin`): a reload makes a **new `Interp`**, retires the old one next frame, and carries values (top-level statements matched by their text; `convert`/`compatible`); a changed statement that opens a window or draws while setting up (`is_effect`) restarts the sketch instead. `watch` of a `sketch.roci` watches every file of its folder.
  - **Soak and fuzz** (`soak_test.odin`): a sketch that makes a picture every frame runs 10,000 frames with the pictures held bounded, and every example, changed by typing mistakes from a generator with a fixed seed, is read, checked and run three frames; a message is the answer, a crash or a leak fails the run (the bounds of `maths.rng_int` are both included, and the examples are taken in sorted order, because a folder's own order differs between systems and so did the changes: the first Linux run found what the Mac's had not). A long run for a new kind of change is worth doing by hand once (400 changes for each example is about a minute).
  - **Checks** (`checks.odin`): `run_checks` is what `roci test` calls; `p.events` counts every `fail` call even when left out as already said; `Runtime_Error.in_check` keeps what a check ran into off the overlay.
  - **Libraries**: `use "name"` joins `libs/name/`; verbs are found by `library/name` (`learn_key`); a call in a library finds that library's own verb first, then the sketch's, then a library's.
  - **Collision** (`collide.odin`): `tree_for` keeps a box tree for a list asked about twice unchanged (`Interp.writes`/`next_write` stamps); answers must equal checking every shape in list order. Empty `contact` and `cast` results are records of zeros.
  - **Fonts** (`fonts.odin`): `font "Mine"` finds Inter's faces, then `assets/` (`folder.find_asset`), then an installed font (`folder.find_system_font`, test knob `folder.system_font_dirs`), or one face of a collection by its full, PostScript or family-and-style name (`folder.face_named`; the face number goes to SDL_ttf as a property and to the PDF reader). The font is copied into `assets/fonts/` with a notice; one not known to be free gets `Font_Licence` (sharing is the writer's problem). **Tests must never call `fonts_stop`** (it ends SDL_ttf for every thread), and a thread keeps the fonts it added, so use unique font names or PostScript names. `roci/gfx/emoji.odin` draws emoji apart from the text.
  - **Pictures** (`images.odin`): `Interp.pictures` remembers each name so a draw loop costs one `stat` a frame; the thread-local `decoded_files` lets a reload find what the old interpreter decoded. Failures are `Image_Missing` and `Image_Unreadable`. **Tweens** keep their path to the place on the heap and run in the frame hook before any handler; a new interpreter starts with none. **Tables** keep names in insertion order.
- `roci/folder`: sketch folders (`read_program` reads every `.roci` file in joining order, not `assets`, `libs`, `output` or hidden folders), `new_sketch`/`init_sketch` (never overwrite), `add_asset`, `find_asset` (two files of a name are `Ambiguous`), libraries (`get_library`, `update_library`; git is the user's tool and no test uses the network), system fonts. `make_directory_all` reports `.Exist` for a folder that is there, so use `ensure_directory`.
- `cli` (the `roci` binary): `run`/`check` take a file or a folder; `run --frames N` is headless and can `--screenshot`; `run --errors json` in a window writes each `print` as a line `{"event":"print","text":...}` on stdout and keeps none of them (`Interp.print_json`; `printed` is only for tests and headless runs, because a sketch printing every frame would otherwise fill memory); `test` unit tests must not draw (starting the graphics device starts SDL's video system, which among the other tests' threads hung a pre-push run and crashed another, 2026-11-11), so they refuse graphics (`roci.set_graphics_refused`), and the full `ci` runs `roci test examples/checks` as a program of its own on lavapipe (`check_stored_pictures` in `build/golden.odin`), which has to draw and match its stored picture; storing a changed picture is checked by hand (`roci test --accept`, change the sketch, `roci test`).
- `site/` and `tools/site`: the documentation, built by Hugo from the registry, the examples and `site/guides/*.md` (design.md §4.12). Tests fail when a word has no example, an example does not check or a guide has no `summary:`. Every sketch of `examples/` is on the site (`SHOWCASE` in `tools/site/showcase.odin`) or left out with a reason, and the comment at its top is the text of its page, so write it for a reader; the search and the menu are `site/hugo/assets/js/site.js` (design.md §4.12).
- `tools/term`: `out`, `err`, `message`, `out_icon`; colour only on a terminal with `NO_COLOR` unset. `setup` is called first in every `main`.
- `roci/platform`: SDL3 and the GPU device. On Windows the device is asked for as `direct3d12` by name with only DXIL and DXBC offered, so SDL never falls back to Vulkan; elsewhere SPIR-V and MSL are offered and SDL picks. On Wayland it asks SDL for `wayland,x11` unless `SDL_VIDEO_DRIVER` is set. SDL is shared by every `App`, so only the last `shutdown` calls `SDL_Quit` (others `SDL_QuitSubSystem`), and **a test build never calls `SDL_Quit`** (`when ODIN_TEST`; it hung one test run in twelve). On Android SDL counts window sizes in pixels (`WINDOW_IS_IN_PIXELS`). The device has clip distances off and SDL's debug mode off unless `ROCI_GPU_DEBUG` is set. The SDL calls are checked by hand with `examples/window`.
- `roci/collide`: 2D collision in pure `f64`; shapes become convex pieces of at most four corners plus a radius; `Tree` must answer exactly what checking every shape answers (a test compares them on random shapes).
- `roci/geom`: plane geometry in pure `f64`, our own tessellation (curves, ear clipping with bridges, `stroke_polyline`, `trace_outline`).
- `roci/gfx`: the drawing model, no GPU. A `Command_List` per window stores 64-byte `Recorded` commands pointing into `looks`; style and transform change only through setters (`look_changed`). Non-finite numbers drop the command, negative sizes are made positive. `Batcher.build` makes instances for one signed-distance "shapes" pipeline; what it cannot draw as styled (`needs_mesh`) is cut into triangles by geom. `command_hash` lets an unchanged batch reuse its GPU buffer.
  - **Text, pictures, fills** all go through the **typeset pipeline** (`typeset.hlsl`, `Typeset_Item`; the shader's `coloured` is a set of flags added to 2: 1 premultiplied, 2 clip what the picture does not reach, 4 repeat). Text is measured when recorded (`measure_typeset`, no GPU) and cached by characters, face, size, alignment and wrap for 120 frames. Faces and fonts live in a thread-local set on the heap allocator; fallback fonts must be the size of the font they serve. A computer without the compiled typeset shader draws everything but text and pictures (`can_typeset`); its DXIL needs `shaders/compile-dxil.sh` after a change to `typeset.hlsl`. Pictures are decoded once by `core:image` into a thread-local store (`images_stop` raises `images_epoch`); a canvas has no CPU pixels, so it cannot fill a text or feed `outline`.
  - **Canvases** (`canvas.odin`, `renderer_canvas.odin`): two textures each, because a multisampled pass cannot add to the texture it resolves into; a round with `background_set` lets earlier rounds go; a canvas texture is premultiplied (typeset mode 3). Density is the window's or `HEADLESS_CANVAS_DENSITY` (2).
  - **Effects** (`translate.odin` shared; `translate_spirv.odin` everywhere but Windows, the only importer of `vendor/shaderc` and `vendor/spirvcross`; `translate_d3d.odin` on Windows; `shaders.odin`, `renderer_effect.odin`): each half gives `translate_fragment`, `user_shader_code` and `can_run_effects`, and `Shader_Data.code` is the system's own form. SPIR-V half: shaderc (HLSL to SPIR-V), SPIRV-Cross to Vulkan GLSL (joins textures to samplers), shaderc again, Metal from that SPIR-V; `place_uniform_blocks` puts `Rocinante` on set 3 binding 0 and the file's globals on binding 1, and numbers Metal buffers itself. Windows half: FXC (`d3dcompiler_47.dll`) makes DXBC 5.1; FXC puts globals on `b0, space0`, where SDL binds nothing, so a shader with globals is compiled twice (`reflect_block`, then `move_globals` blanks the declarations, keeping line numbers, and declares them in `rocinante_values_` on `b1, space3`); messages are rewritten in shaderc's form, but the words differ, so `tests/errors/runtime/shader_broken` has a `.windows.txt`. Built-in effects are HLSL files in `effects/` listed in `BUILTIN_EFFECTS` (a new one is a file, a table row and a guide line); a hash in one must use whole-pixel coordinates so every GPU agrees. `shade` fills use `Style.fill_shader` and `draw_shader_fill`; `interp` keeps a file used both ways as two entries.
  - **Vector files** (`svg.odin`, `pdf.odin`, `truetype.odin`): written from the command list with no GPU; `text_lines` breaks a wrapped text where SDL_ttf does; the PDF has text as glyph outlines (TrueType `glyf` fonts only, CFF text is said and left out).
  - **Blend and clip** are part of a look (hashed); a change of either starts a new batch; one pipeline per (program, blend); `set_clip` keeps the upright box round the transformed corners; `draw_overlay` puts both back first. No `darken` (a minimum colour would turn clear corners black).
  - `renderer.odin`, `png.odin`: pipelines are made on first use and a failure is recorded once; drawing is 4x multisampled, premultiplied. PNG is **sancho** (own repo, 0BSD), vendored as a plain copy in `vendor/sancho` with the commit in `vendor/sancho/SOURCE`: a change is made in sancho and copied with `tools/vendor-sancho.sh [ref]`. Shaders are HLSL in `shaders/` with SPIR-V, Metal and DXIL committed in `shaders/compiled/`; Metal needs texture-upload offsets that are multiples of 16.
- 3D (`roci/gfx/scene3.odin`, `renderer_scene.odin`, `roci/scene3.odin`, `shaders/scene3.hlsl`; the design is in §4.3): the scene is plain data beside the 2D list and the renderer draws it in a pass of its own before the 2D pass. **Trap**: a fragment shader cannot read the vertex stage's uniform block (SDL puts fragment uniforms on another set), so anything the fragment stage needs rides along as a varying; reading it anyway crashed lavapipe inside its JIT with no message. The orbit is `Win.mouse_read`-gated: any verb that reads the mouse must call `read_mouse`.
- `tests/golden`: `scenes.odin` is where a new golden scene goes; `examples.odin` runs the examples at a fixed seed and compares each window with `example_<name>_<window>.png`; an example with no picture goes in `NO_PICTURE` with a reason. A window with no reference is said and does not fail.
- `roci/toml`: the subset of TOML `ui.toml` and `sketch.toml` use (tables, `key = value` with a bare or quoted key, text, whole and decimal numbers, booleans, one-line arrays of numbers), read without a library and written back in the order given; a line it cannot read is a `Problem` with its number and is left out, never an error that stops a sketch. A decimal is always written with a point, so what is read back is the same kind.
- `ui.toml` (`roci/ui_persist.odin`, `roci/ui/persist.odin`): `roci run` of a `sketch.roci` remembers the widgets' values in `ui.toml` beside it (`roci.ui_persist`; a lone file, `--frames` runs, tests and the golden images never read or write one). A table for each window (`[ui]`, `[ui2]`...) and a line for each widget under its readable name (panel and tab path, text, `#n` in a loop); a drop-down, radio group or list is remembered by the item's text, a color as `"#rrggbbaa"`. Values are taken as a widget is first made (`ui.set_loaded`), written when the sketch ends and after a second of stillness (`ui_touch`, `ui_autosave`, `ui_flush`), through a `.part` file and a rename. What the file says of widgets not made this run, and of windows not open, is kept when it is written; `forget ui` drops it. Every `ui_*_value` procedure has to `mark` its kind, or its value is not written.
- `roci/ui` (the interface of one window, package imports `vendor/imgui` and `roci/platform`, no sketch language): `State` is a Dear ImGui context made by the first widget (`roci/ui_window.odin` makes it, feeds it the window's events as ImGui input events, finishes the frame after the window's `draw` and gives the renderer `Renderer.overlay` so the interface is drawn in a pass of its own over the finished frame, effects included, also in `picture`). No ImGui SDL backend: events are fed by hand so a headless window can be clicked by a test; only the SDL_GPU renderer backend is used (made on first draw, again when the device or target format changes). Widgets are procedures that return what the user did and leave a `Record` (role, label, value, rect, focus) for screen readers and tests. Traps: the panel (`rocinante`, top left, autosizing) shows its widgets from its **third** frame; ImGui trickles input, so a click is seen over two or three frames; a test helper must not short-circuit (`ok ||= widget()` skips the widget); a font passed to `create` must outlive the state. A widget that keeps a value (`kept`) holds it in the state by its text, which is what survives a reload. `State.target_scale` is set by `picture` so a window laid out at its own density is drawn across a picture of another scale. An `image button` leaves `IMAGE_TEXTURE_FLAG | picture number` as its texture id and `ui.draw` swaps it (`patch_pictures`, with the renderer's `gfx.image_texture` through `Texture_Of`) just before the pass; a picture with no texture is drawn with zero elements.
  - **Screen-reader tree and actions** (`access.odin`, `actions.odin`; platform-free, the bridge to AccessKit is in `roci/access*.odin` below): `build_tree` turns `State.finished` into a `Tree` of plain `Node`s (role, name, value, state, `actions`, bounds), nesting what is made inside a panel, tab or menu by the record's `path`; node ids are the item ids lifted past the small ones (a line of text has none, so its place in the frame), unique and steady from frame to frame (tested); `dump_tree` is the text the examples' stored trees (`tests/ui-tree`) are compared with, with no positions in it. An action (`push_action`, from any thread, or `roci.ui_access_action` in tests) waits in a locked queue and `begin_frame` makes it the frame's; the widget it names takes it (`take`, `nudge`) before it draws and does what a hand would have: click, step, set a number or text, focus (in `note`), select a tab or radio button or list item, fold a panel. A node's `actions` must only list what a widget really takes.
  - **The screen-reader bridge** (`roci/access.odin`, `access_darwin.odin`, `access_unix.odin`, `access_windows.odin`, `access_other.odin`): `ensure_ui` makes an `Access` (heap, shared with the adapter's callbacks) for a window with a handle when the library is there; `ui_finish` builds the tree, hashes it (`ui.tree_hash`) and calls `platform_access_update` only when the hash changed; `access_factory` serves AccessKit a locked copy of the stored tree, never the live state, and `access_action` queues a request (`asked_of`, `ui.push_action`) for the next frame. Locks are never held across a call into the adapter. macOS: `macos_subclassing_adapter_for_window` on SDL's `NSWindow` (plus the focus forwarder on `SDL3Window`, once). Linux, FreeBSD, OpenBSD: `unix_adapter_new` (AT-SPI over D-Bus; its handlers run on the adapter's own threads, so everything they touch is behind `Access.lock`), told where the window is on every update and move (`platform_access_bounds`). Windows: `windows_subclassing_adapter_new` on the `HWND`, which **must be made before the window is first shown and stops the program if it is visible**, so `platform_access_attach` hides a showing window for the call (one blink at start); bounds there are device pixels, so `Access.scale` multiplies them. Other systems have no adapter (`access_other.odin`). **Traps**: Orca speaks a change only from what it holds as the focus, so a record that does not say it has focus is silent when changed (`orca --replace --debug-file=FILE` shows why), and it speaks a progress bar at most every 10 seconds; AccessKit takes a radio button's state from `checked`, not `selected` (ARIA). Tests cover the tree, the actions and the conversion; a real screen reader is checked by hand (VoiceOver, Orca, Narrator and NVDA all on `examples/ui`; which packages each system needed is in design.md §4.8). On Windows, driving UI Automation from PowerShell (`docs/release-checklist.md`, 4b) checks the tree and actions before anyone listens.
  - **Keyboard** (`input.odin`, `keyboard_test.odin`): an arrow key pressed while a slider, knob, range, pad or number box (not being typed in) has focus is kept from Dear ImGui's navigation (`takes_arrow`) and moves the value (`State.arrows`, `arrow_step`), right and up adding. Traps: `EndGroup` adds an item of no identity, so after any group (ours, or one inside a Dear ImGui widget: `InputScalar` with steps, `ColorEdit4`, `ListBox`) `is_item_focused` is false, so focus is read before the group closes (the number box and color picker are built from their parts for this, and the list calls `end_child`, then `end_group`); a radio group, list or open drop-down gives the item with focus as `Record.focus_item`, and so do a range (its handle) and a pad (its axis, `State.pad_axis`), which the tree shows as a group of two sliders (`part_slider`, `Record.second` the other value); `InvisibleButton` is no stop for the keyboard without `ButtonFlags_EnableNav`; a click on a number box's step leaves Dear ImGui with no focus, so the box claims it (`State.claimed`) until the keyboard focuses something; Tab turns a Dear ImGui slider into a box of text, so ours have `SliderFlags_NoInput`.
  - **Placing**: `ui.place_next` (from the interpreter's `place_widget`, through `roci.ui_place`) says where the next widget or group goes; `place` opens a floating Dear ImGui window for a widget with `at` (closed lazily by the next widget, so a `tip` still finds it) and `begin_container` one for a group (closed by `end_container`); the one panel is opened only by a widget that is not placed (`ensure_frame` no longer opens it). `Win.in_draw` makes `ui_place` apply the transform, and `Interp.block_depth` makes a `ui` statement inside a running block (`draw`, event) run at once instead of registering.
  - **The language side** (`ui [ ]`, `label`, `button`, `toggle`, `slider`): `ui` is the `Draw` statement with `ui` set (parsed by `parse_draw`, run after `draw` by `Win.ui_draw`, the interpreter keeps `Interp.uis` beside `draws`); the widget verbs (`label` to `forget ui`, 28 of them with `ui theme`, containers included: `panel`, `row`, `column`, `tabs`, `tab`, `menu`) are `LANGUAGE_VERBS` rows with no Odin procedure of their own in the registry or C ABI, answered by `interp/widgets.odin` through `roci.ui_*`. all of them and `ui` are reserved words now. Typed text reaches the interface as `platform.Text_Input` (held in the event, 63 bytes at most, cut at a whole character) and a window with a text box in use asks SDL for it (`platform.text_input`); the fonts for other scripts are added to the interface font only when such text is first typed or shown (`add_fallback_fonts`).
- `vendor/imgui` and `tools/imgui`: Dear ImGui as Odin. `imgui.odin` is **generated** (`tools/imgui` reads dear_bindings' JSON; edit the generator's `WANTED` list to bind another procedure, never the file) and `c/` holds the C wrappers dear_bindings made, committed so a build needs no Python (`ui-libs.sh regenerate` rewrites its `reinterpret_cast<T>(NULL)` as `static_cast<T>(nullptr)`, because where `NULL` is `nullptr`, as on OpenBSD, C++ refuses the first); `tools/ui-libs.sh` compiles them with Dear ImGui (fetched at its pinned tag) into `.cache/ui/libroci_ui.a` (on Windows `roci_ui.lib`, with MSVC and `-MT`). Enum values are plain constants (`WindowFlags_NoTitleBar`), flags are `i32`, `ImVec2`/`ImVec4` are `[2]f32`/`[4]f32`, and defaults are written for the plain cases only. Dear ImGui's current-context pointer is `thread_local` (`c/imconfig_roci.h`), so parallel tests may each have a context. **Every program that opens a window links the library**, so `tools/ui-libs.sh` must have run (`ci` runs it when the library is missing; the pipelines run it as a step).
- `vendor/accesskit` and `tools/accesskit`: accesskit-c (Apache-2.0 OR MIT) as Odin. `accesskit.odin` is **generated** from the library's header (`.cache/ui/accesskit/accesskit.h`) by `odin run tools/accesskit` (edit its `WANTED` list, never the file); a C compiler (`cc`) measures every struct so sizes and offsets are `#assert`s (Spike 4's hand-written layouts were wrong), and `ci` writes it again into `output/accesskit` and fails when it differs, except on Windows, which has no `cc`. The library comes from `tools/ui-libs.sh accesskit`: the release archive (macOS, Linux x86_64, and on Windows the static MSVC `accesskit.lib`, opened with `unzip` or PowerShell; sha256 pinned) or a build with git, cmake and cargo (FreeBSD, OpenBSD, arm64 Linux; OpenBSD links no `dl`, and `cargo rustc --release -- --print native-static-libs` in `.cache/ui/accesskit-c-src` lists what Rust needs). Where it cannot be had `ci` skips with a note, and fails when `ROCI_REQUIRE_ACCESSKIT` is set, as both pipelines do. It links on every desktop system (Windows since 2026-11-11). The generated file declares `LIBRARY_PRESENT` (`#exists` of the library) and, when false, a do-nothing stand-in for every procedure, so a build without it still runs (no adapters).
- `tools/ci/`: the install scripts both pipelines use, and `orion.Dockerfile` (a new package for the pipeline goes there and needs a rebuild).

**Shell and tool gotchas** (these have all cost time):
- Fabrizio's `ls` is an alias for `eza` and adds colour codes, so scripts and anything piped must use `command ls`. Use `rg`, not `grep`, in anything written for him; portable scripts that contributors run (hooks, CI) use POSIX tools.
- macOS has no `timeout`, and BSD `sed` (macOS, FreeBSD, OpenBSD) needs `-i ''`. A replacement holding backticks does not survive `sed` in a shell variable: splice the line with `head` and `tail`, or use the edit tool.
- **macOS and lavapipe** (checked 2026-11-05, macOS 26, Apple silicon): `brew install mesa` builds Mesa's software Vulkan (`swrast`, which is lavapipe) and puts its manifest in `/opt/homebrew/share/vulkan/icd.d/lvp_icd.aarch64.json`; the golden step of `ci` finds it there and tells SDL where Homebrew's Vulkan loader is (`SDL_VULKAN_LIBRARY`, because macOS does not look in `/opt/homebrew/lib`), and every reference matched to 0 pixels off against the Linux ones, so references may be drawn on a Mac too. By hand: `VK_DRIVER_FILES=/opt/homebrew/share/vulkan/icd.d/lvp_icd.aarch64.json SDL_VIDEODRIVER=offscreen SDL_VULKAN_LIBRARY=/opt/homebrew/lib/libvulkan.1.dylib odin run tests/golden`. The `kosmickrisp` manifest beside it is Vulkan on Metal, a real GPU, and is not used.
- **FreeBSD and lavapipe**: Mesa's driver manifests are in `/usr/local/share/vulkan/icd.d/` (`lvp_icd.x86_64.json`), not `/usr/share/vulkan/icd.d/`, so the `VK_DRIVER_FILES=$(command ls /usr/share/...)` commands above find nothing there. Set `VK_DRIVER_FILES=/usr/local/share/vulkan/icd.d/lvp_icd.x86_64.json SDL_VIDEODRIVER=offscreen` by hand. **`ci` reports the golden step `ok` when lavapipe is not found** (it skips with a note, and fails only when `ROCI_REQUIRE_LAVAPIPE` is set), so after any change to a drawing default or the renderer run `odin run tests/golden` yourself and read its last line (`golden: N pictures, 0 failed`).
- Odin: write `-target` before `-subtarget`; a literal `{` in an `fmt` format string means something, so pass it as an argument; a procedure cannot return a slice literal (copy it to the heap); a global cannot call a procedure that needs `context`.
- Odin on Apple Silicon guesses the wrong NDK folder, so set `ODIN_ANDROID_NDK_TOOLCHAIN` (to the `darwin-x86_64` toolchain) when building for Android.
- Never test a mobile app on a sleeping or locked phone: Android draws nothing, iOS refuses to launch.
- Odin `dev-2026-10` (fixed in `dev-2026-11`, checked 2026-11-06 with a missing key: it runs and loops zero times): `for x in m[key]` crashed when `key` was missing from the map. Code written to avoid it (`list := m[key]`, then `for x in list`) is still right.
- Odin `dev-2026-10` on Windows (not rechecked on `dev-2026-11`): `os.Walker` leaves the last folder it read open (`walker_destroy` clears the iterator's file first, so `_read_directory_iterator_destroy` returns before `FindClose`), and Windows then refuses to rename or remove that folder; `roci/folder` walks with its own `walk_files` on `os.read_all_directory_by_path` instead (found 2026-11-05, when `roci get` failed with `Permission_Denied`), worth reporting upstream.
- Odin `dev-2026-10` on Windows (not rechecked on `dev-2026-11`): a walker's full paths use backslashes, so code that splits them on `/` must spell them with `/` first (`trim_folder` in `roci/folder`, `slashed` in the `roci/lang` tests). A test that panics on Windows can also leave the parallel test runner spinning on one core forever instead of failing (found 2026-11-05, when `ci` sat on `roci/lang` for 15 minutes); run the package alone with `-define:ODIN_TEST_LOG_STATE_CHANGES=true` to see which test never finishes.
- Windows: an `-out:` path must end in `.exe`, and a running program's file is locked, so nothing may write `build.exe` while `odin run build` runs (`ci` puts test programs in `output/tests/`). A program that needs `SDL3.dll` finds it only next to itself or on `PATH`. To get MSVC's `cl` and `lib` into Git Bash, run `call "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat"` in a plain `cmd`, then `"C:\Program Files\Git\bin\bash.exe" --login -i` in the same window (the Start menu's Native Tools prompt did not set them up on Fabrizio's machine, which has both Build Tools and Community installed). C and C++ code linked into an Odin program is built with `-MT`, because Odin links the static C runtime.
- Odin `dev-2026-10` sometimes crashed in its own checker (`src/checker_global.cpp(1682): Assertion Failure: g->groups[gi].done.load()`, "This is a compiler error"), seen once in Spike 3's generated program during a pre-push `ci`; running it again passed eight times out of eight. Run it again rather than chase it; whether to report it upstream is Fabrizio's call.
- Timing on Fabrizio's CachyOS computer: there is no `time` or `bc`; use `hyperfine -N --warmup 1 --runs 5 '<command>'` (installed 2026-10-29), and subtract a one-frame run to get the cost of a frame.
- `perf` on Fabrizio's CachyOS computer: only user-space sampling opens (`perf record -e cpu-clock:u`), and not with call graphs (`-g` and `--call-graph dwarf` fail with "Failure to open any events"), so profiles are flat; build with `-o:speed -debug` for names and `perf annotate` for lines.
- Python is not a rocinante dependency until the Phase 6 model converters (§4.10), so the repository's scripts use Odin or POSIX tools even on computers that have it. Windows: in Git Bash, a heredoc whose text holds backticks and quotes can fail to parse; write such files with the editor's write tool instead. Line endings are LF everywhere: `.gitattributes` (`* text=auto eol=lf`) overrides `core.autocrlf`, so shell scripts keep working when a Windows clone is used from WSL or copied to a Mac.
- Odin: package-level state shared by tests is a data race (the tests run in parallel), so use `@(thread_local)`; and a constant slice of structs that hold slices is rebuilt on the stack at each use, so keep such tables in a package-level variable (both were found by the first unit tests).
- `odin run tests/golden -- update` writes every reference again, and two lavapipe versions differ by a few edge pixels: keep only the new or changed reference and put the rest back (`git checkout -- tests/golden/*.png`), then run `odin run tests/golden` to see they still pass. Its filter takes picture names (`example_logo_1`), not example names.
- `odin test <dir>` without `-out:` leaves a program named after the folder (`site.bin`) in the folder it runs from; pass `-out:output/tests/<name>` as `ci` does.
- A command that pipes `ci` into `tail` gets `tail`'s exit status, not `ci`'s, so `ci && git commit` through a pipe commits after a failure. Commit only behind `if odin run build -- ci > output/ci.log 2>&1; then ...`.
- `pkill -f` and `pgrep -f` match their own shell's command line, so a pattern that is also in the command (`pkill -f "port 1416"`) kills the shell running it (exit 144). Kill by process ID, or bracket one letter (`pgrep -f 'port 141[6]'`). Fabrizio may have his own `docs serve` running a `hugo server`: stop only the ones you started.
- Anything timed by the wall clock fails on ORION's slow runner before anywhere else: a block's two seconds (`Interp.budget`) once made the test that compares runs with the passes on and off fail there and only there. A test that compares two runs lifts the limit (`p.budget = max(f64)`); a test of the limit itself sets a short one.
- `roci/folder`'s tests expect the repository to be a git repository (a sketch inside one is left to it), so a test copy made with `git archive` fails them; copy with `git clone`.
- Fabrizio's own computers have Podman, not Docker (ORION has Docker). `podman build -f tools/ci/orion.Dockerfile -t rocinante-ci .` and `podman run --rm -v <clone>:/builds/rocinante:Z rocinante-ci sh -c '...'` on a fresh clone reproduce ORION's jobs.
- **A leak or a bad free fails a test** (`ci` passes `-define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true`; without it Odin only prints a warning). The stores that outlive a test on its thread must be stopped by the test that made them, so a test that makes a picture or a canvas does `defer images_stop()` (or `roci.shutdown()`), one that runs the interpreter ends with `finish`, which also forgets the decoded files, and one that reloads ends with `finish_all`; a test that runs a program such as the generator tools uses `context.temp_allocator`. Allocate with the caller's `context.allocator`, never `runtime.heap_allocator()`, so the tests can see it (the fonts are the one exception: `fonts_stop` ends SDL_ttf for every thread). The sketch keeps the allocator it started with (`the.allocator`) and the C functions run with it (`abi_context`), so a window made by a C call is freed by the allocator that made it.
- **Tests run in parallel threads in one process** (`odin test`): a test must never call `SDL_Quit` or `fonts_stop`, start SDL's video system, draw through a real window, or start a process (`os.process_start` forks and is not safe among busy threads). Use `roci.set_graphics_refused(true)`, `roci.set_frame_source(...)`, `start_headless`, and put anything that starts a process in its own package (`roci/movies`). These failed as hangs in SDL's init state, segfaults on ORION only, and a child killed about a run in three. `Bounds check failed` in a test thread that holds a mutex hangs the run: guard indexing.
- `odin test` deletes its program after a pass, so to repeat a flaky test many times pass `-keep-executable` (otherwise a missing file looks like a crash).
- Never `git add -A` here: running an example can copy an installed font into its folder (Apple's Helvetica Neue was committed that way, 2026-11-06). Add files by name and read `git status` first; `ci` fails on a tracked font, `examples/*/assets/fonts/` is ignored, and tests set `folder.system_font_dirs` to an empty folder. A history rewrite (`git filter-branch`) leaves `refs/original` and the reflog holding the old objects: delete them, then `git gc --prune=now`; GitLab also needs Settings > Repository > Repository maintenance > "Remove blobs" and then housekeeping.
- Homebrew replaces Odin with its newest release, which may not be the pin: check `odin version` against `ODIN_VERSION`, and keep the pinned release's archive unpacked in a scratch folder.
- Arch's `odin` package can trail the pin (still `dev-2026-10` on 2026-11-10, with `dev-2026-11` pinned): install the pinned release beside it with `sh tools/ci/install-odin.sh ~/.local/share/odin/dev-2026-11` and put that folder first on `PATH` (`export PATH="$HOME/.local/share/odin/dev-2026-11:$PATH"` in `~/.zshrc`), then check `odin version`.
- ORION runs jobs in the `rocinante-ci` container: files it creates in a mounted clone are owned by root, and git there needs `safe.directory` (without it a folder test fails with `Needs_Identity`).
- A style verb on its own line (`stroke black`, `thickness 48`) lasts until changed, so it also reaches shapes written later that were meant to have none: turn it off (`no stroke`) where it should stop. In a `draw` block it lasts for the frame only, so a style line above the block never reaches what the block draws.
- BSD `sed` (macOS, FreeBSD, OpenBSD) has no `\b` word boundary, so `sed 's/\bplural(/x(/'` does nothing and says nothing: use the plain text, or the edit tool.
- A guide quotes an error message only in a ```` ```message ```` block holding the text of a `.txt` under `tests/errors` exactly (runtime ones included); `tools/site`'s tests fail on any other quotation, and on a message left in a plain block.
- `count`, `item`, `keep`, `find` and the other built-in verbs are reserved, so they cannot be names of a parameter or a variable (an example that used `count` failed the checker): `n` is a safe name.

---

## 1. What rocinante is

An open-source creative coding framework and language.

- **rocinante (the language)**: a small, Logo-inspired language for sketches. The language, the framework and the project share the one name (decided 2026-10-24). No semicolons, no braces around blocks, one predictable shape. File extension `.roci`.
- **The core**: an engine written in **Odin** on SDL3 and its GPU API (Vulkan, Metal, Direct3D 12). It owns windows, rendering, UI, audio, input, I/O and packaging.
- **`roci` (the tool)**: one command-line program to run, watch, check and package sketches. Written in Odin.
- **A public Odin API, with a C ABI,** for power users who want to write sketches or extensions in Odin (or C) directly. Same verbs, same behaviour.

Execution: **interpreted while you work, compiled to native code when you ship** (§4.7). Users never choose or notice; `roci run` interprets, `roci package` compiles.

Target platforms, all first class from the start: FreeBSD, Linux, macOS, OpenBSD, Windows, iOS, Android. Five of them are also **host** platforms, where sketches are written, run (`roci run`) and packaged: FreeBSD, Linux, macOS, OpenBSD and Windows (OpenBSD joined on 2026-11-01). **iOS and Android are targets only** (decided 2026-10-25): `roci` does not run on them, nothing is developed on them, and a sketch gets there as a packaged app. Which hosts can package which targets is in §7. On the desktop, the first stable release covers x86-64 FreeBSD, Linux, OpenBSD and Windows and Apple silicon Macs; other processors are on the roadmap (decided 2026-10-26).

The smallest valid program:

```
circle at 100 100 radius 50
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
8. **Everywhere.** Every commit on `main` builds and passes the full pipeline on Linux (§11). Before every release tag, the other six platforms (FreeBSD, macOS, OpenBSD, Windows, iOS, Android) are checked locally against the release checklist and the results recorded (§11). Mobile targets are also smoke-tested at least once per phase.
9. **Modern dependencies.** No OpenGL anywhere. Use current stable versions of everything. **Windows draws with Direct3D 12 only** (decided 2026-11-11): no Vulkan library, package, SDK or driver is needed or used there, at build time or run time; Linux, FreeBSD, OpenBSD and Android use Vulkan, Apple's systems Metal.
10. **UI is first class.** Buttons, sliders, text boxes, drop-downs and the rest are built-in verbs (§4.8, §5.8), available in every sketch with no add-on, import or setup, on every platform, including screen-reader support.

---

## 3. Working rules for Claude Code

- **Check official documentation before using any API, library, flag or tool.** Do not guess function signatures, command flags or behaviour. If docs are unclear, say so and ask rather than presenting a guess as fact. Cite the doc URL in commit messages or PR descriptions when a decision depends on it.
- **Odin.** The core and `roci` are written in Odin. Pin one Odin release per rocinante release, recorded in the `ODIN_VERSION` file (the one place the version lives), and upgrade deliberately. Follow Odin's own style and idioms; no Rust or C++ habits.
- **Libraries: Odin `vendor:` first, latest upstream when vendor lags.** Use a library from Odin's `vendor:` collection when its version is current. When it lags behind the latest stable upstream release (SDL3 and its satellites especially), write or regenerate bindings for the latest version in the repository's own `vendor/` folder, and offer the update upstream to Odin. C and C++ libraries are used through Odin's foreign system; C++ only behind a C API.
- **Ask before adding a dependency.** State what it does, its licence, its platform support (including FreeBSD, OpenBSD, iOS and Android) and why an existing dependency won't do.
- **Licence policy.** rocinante is 0BSD (§10). Dependencies must be under permissive licences (0BSD, MIT, MIT-0, Apache-2.0, BSD, ISC, zlib, public domain). MPL-2.0 only when there is no permissive alternative, with a source notice shipped by `roci package`. Never GPL or LGPL code in the core, in `roci`, or in packaged sketches. (A GPL/LGPL tool used only to build a dependency, such as a build system, is fine as long as nothing from it is shipped.)
- **No pointers into this file from code** (decided 2026-10-28). Comments in source files, scripts, shaders and grammar say what the code does in plain words; they never mention `CLAUDE.md` or one of its section numbers, because this file changes and a pointer into it goes stale. Do not add "section N" or "non-negotiable N" references either: they go stale the same way, and the 2026-10-28 clean-up removed every one from the code.
- **The name is always lowercase**: rocinante, never "Rocinante", including at the start of a sentence, in titles, docs, UI text, package metadata and commit messages. The same applies to `roci`.
- Fabrizio's tools: `nvim` (never `nano`), `rg` (not `grep`), `eza` (not `ls`). Use these in any instructions, scripts or docs you write for him.
- For FreeBSD ports, build and test in one pass with `poudriere bulk -t`. Use `testport -i` only when debugging inside the jail.
- **All code needs the best possible unit-test coverage** (decided 2026-10-25). Every package ships with `@(test)` procedures (run with `odin test`, §9) written with the code, not after it: every procedure, every branch and every error path, including the edge cases (empty input, zero, the largest and smallest values, malformed text). A change that adds code without tests for it is not finished; if something truly cannot be tested, say why in the commit. Odin has no coverage tool, so coverage is kept by discipline and by review: list the branches of what you wrote and check that each has a test.
- **Every feature gets a showcase example** (decided 2026-10-29). A feature a sketch can see is not finished until an example in `examples/` shows it off, a new one or an existing one extended, in the same branch, with its `sketch.types`, its golden reference (drawn on lavapipe) and, when it reacts to input, an interpreter test that sends it the events.
- Work in small, reviewable steps. Each phase below lists exit criteria; a phase is done only when all of them pass.
- Never weaken a non-negotiable to make a task easier. Flag the conflict instead.
- When you finish something that changes the design, update this file in the same commit.
- **Never push automatically** (decided 2026-10-25). Claude Code does not push to `origin`, `github` or any other remote unless Fabrizio asks for a push in that very message; an earlier "yes" does not carry over. After committing, it says what to run (`git push origin <branch>`), and Fabrizio pushes, opens the merge request and merges it himself. It also never merges into `main` or deletes remote branches on its own; after every successful merge it updates the local `main` and deletes the merged local branches itself (decided 2026-10-28), after checking each has no unmerged commits.
- **Never commit on `main`** (decided 2026-10-26). Before the first commit of any change, create a branch named by kind (`feat/…`, `fix/…`, `docs/…`, `spike/…`, `refactor/…`, §11) and commit there; `main` changes only through a tested GitLab merge request that Fabrizio merges. After he merges, fast-forward the local `main` to `origin/main`, delete every merged local branch with `git branch -d` (after every merge, without being asked, once `git rev-list --count origin/main..<branch>` is 0), and run `git fetch --prune` (GitLab deletes merged branches itself). When `main` moved while a branch waited, rebase the branch onto `origin/main` and tell him to push it with `git push --force-with-lease origin <branch>`.
- **Git** follows §11: short feature branches rebased onto `main` and merged fast-forward, small frequent commits. **Never mention AI, Claude or any assistant in commit messages, branch names, tags or release notes, and never add `Co-Authored-By` trailers or session links.** A commit message says what changed, never whose words, idea or work it is.
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

 roci (cli): new, init, add, get, update, run, check, fmt, test, package <target>, doctor
```

### 4.2 Source layout (initial)

Odin has no package manager and no workspace file: a package is a directory, and every `.odin` file in it belongs to that package. The repository is one Odin collection.

```
rocinante/
  CLAUDE.md            rules, plan, tool, testing, git and CI (this file)
  MANIFESTO.md
  README.md            what rocinante is, project status, how to contribute (§11)
  CONTRIBUTING.md      a pointer to README's Contributing section, for GitHub and GitLab to show
  CODE_OF_CONDUCT.md   the Contributor Covenant 2.1 as published (CC BY 4.0, credited in the file), reports to Fabrizio's address
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
    lang/              lexer, parser, checker, type inference, typed IR (no SDL, no GPU)
    folder/            sketch folders: roci new and init, the assets/ folder and finding a file in it
    interp/            the interpreter: runs the typed IR through the roci API
    codegen/           typed IR → Odin source for `roci package`
  cli/                 the `roci` binary (package main)
  vendor/              sancho (our PNG writer and deflate, copied in by tools/vendor-sancho.sh), our own bindings
                       where Odin's vendor: lags, plus C/C++ sources and
                       prebuilt libraries (Dear ImGui via dear_bindings, accesskit-c, …)
  build/               build script written in Odin (no Make, no CMake for contributors)
  shaders/             internal shaders (HLSL source), compiled at build time
  examples/            .roci and .odin examples, one per feature; each .roci example has a one-line task
                       description and a reference PNG checked by the golden-image harness (§9)
  tests/               golden-image tests, language tests, back-end equivalence tests
  tools/hooks/         pre-push and commit-msg hooks (§11)
  docs/                design.md (architecture details, the language, parity map; imported by CLAUDE.md),
                       logo/rocinante-logo.svg (the logo: the one drawing its copies are made from),
                       grammar.ebnf (the language's grammar, written in Phase 2, §5.14),
                       phases.md (the history of the closed phases; not imported),
                       release checklist and contributor docs
  ODIN_VERSION         the pinned Odin release, read by the build script and both pipelines
  .gitlab-ci.yml       GitLab pipeline (§11)
  .github/workflows/   GitHub pipeline (§11)
```

Package boundaries can change; record the change here.

*§4.3 to §4.12 (rendering, threads, messaging, audio, execution model, user interface, sketch folders, machine learning, video, the documentation site and the CI tools), §5 (the language) and §6 (the feature parity map) live in `docs/design.md`, imported here:*

@docs/design.md

---

## 7. The `roci` tool

```
roci new <name>          create a sketch folder (§4.9) with git and an optional Git LFS setup
roci init                the same, inside an existing folder; never overwrites
roci add <path>          copy a file into the right assets/ subfolder; converts PyTorch and JAX models (§4.10)
roci get <url> [--as n]  vendor a library from a git address into libs/ (§5.10); a short name waits for the public index (Phase 9)
roci update [name]       fetch newer versions of vendored libraries, showing what changed
roci run [file]          interpret with live reload (default: sketch.roci); needs nothing installed.
                         `--frames N --screenshot out.png --errors json` runs headless: N frames, a picture,
                         and errors as data (line, column, message ID, nearest known verb); the tests use it
roci check [file]        parse, check and infer types without running
roci fmt [file]          format a sketch in the house style (§5.1); no options
roci test [folder|file]  run the checks of a sketch or library and compare its picture with the stored one (§5.16);
                         `--accept [--frames N] [--seed N]` stores the picture it draws now
roci package <target>    compile to native code and package; targets: linux, freebsd, macos, windows, android, ios
roci doctor              for each package target, say whether this computer can build it, and if so what is
                         missing, with install steps; `roci doctor ml` checks the PyTorch and JAX converters
```

Packaging notes:

- `roci package` always generates Odin and builds it with the pinned Odin and the user's platform toolchain (§4.7). The user never sees Odin code or compiler output unless they open the saved build log in `output/`; failures are reported in rocinante's plain style, with `roci doctor` as the next step.
- **Toolchain** (§4.7): Odin at the pinned version everywhere, fetched into `roci`'s own cache on first use; MSVC and the Windows SDK on Windows; the Xcode command-line tools on macOS; clang on Linux, FreeBSD and OpenBSD.
- **iOS**: App Store distribution requires a Mac with full Xcode and an Apple Developer Program account. `roci package ios` drives Odin and Xcode's command-line tools, and runs on macOS only; there is no hand-off to another machine.
- **Android**: `roci` fetches and manages the SDK, the NDK and a JDK (Temurin 21) on first use and keeps the signing keystore out of the user's way. It can package from macOS, Linux x86-64 and Windows hosts only, because Google's NDK has no other hosts (§4.7).
- **FreeBSD**: `roci package` uses the `odin-lang` package (port `lang/odin`) when it is the pinned Odin, and builds the pinned release from source otherwise (decided 2026-10-30, §4.7). Produce a package of the sketch; later, a port of `roci` itself (named `roci`, because `sysutils/rocinante` is another project's port) (`poudriere bulk -t`).
- **OpenBSD** (decided 2026-11-01): Odin has neither an archive nor a package there, so `roci package` builds the pinned release from Odin's source tag into its cache, as FreeBSD does when its package is another version (`gmake release-native` with the `llvm%19` package's `llvm-config`, the recipe Fabrizio used for the first OpenBSD run).
- **Hosts and targets** (decided 2026-10-25). Sketches are written, run and packaged on FreeBSD, Linux, macOS, OpenBSD and Windows computers; iOS and Android are targets only. A target can be packaged only on the hosts below. **There is no cross-compilation between desktop systems** (decided 2026-10-25): each desktop system packages for itself. Odin on macOS can cross-build for Intel Macs, can cross-link Windows only with a Windows SDK root and `lld`, and does not link Linux or FreeBSD at all (checked with `dev-2026-10`), and building for macOS needs Apple's SDK and tools on a Mac. The more useful route to artefacts for systems you do not own is to run `roci package` on a machine of that system, such as a CI runner.

  | Target | Can be packaged on | Why |
  |---|---|---|
  | `linux` | Linux | built with the host's clang and linker (§4.7) |
  | `freebsd` | FreeBSD | the same |
  | `openbsd` | OpenBSD | the same |
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

### Phases 0, 1 and 2 (closed)

**Phase 0, foundations** (done 2026-10-27): the repository, the build script and its `ci` command, the hooks, both pipelines, the licence check and the unit tests, and four throwaway spikes that tested the riskiest assumptions (an SDL3 GPU window on every desktop, a shader circle on a real iPhone and Android phone, a typed IR interpreted and turned into Odin, Dear ImGui with a screen reader). **Phase 1, the window and 2D core in Odin** (done 2026-10-27): windows, the renderer with batching and instancing, every 2D shape, style, gradients and transforms, colour, noise and input, the verb registry and the C ABI, headless rendering and golden images; 100,000 circles a frame at about 60 fps, on iOS and Android too. **Phase 2, the language** (done 2026-10-30): the front end, the interpreter, `roci run`, `check`, `fmt`, `man`, sketch folders, libraries, input, the turtle, collision, tweens, tables and an example for every feature, closed after the newcomer test confirmed the design.

What each one built, its measurements and findings, and how it met its exit are in `docs/phases.md`.

**Still open from the earlier phases**: IME on Linux, FreeBSD and OpenBSD (checked by hand only; no test can compose text); `vendor:sdl3` or our own bindings (decide the first time a newer function is needed); the trademark search; the unchecked dependency platform lists; offers to make upstream (Odin's `for x in m[key]` crash on a missing key, its `os.Walker` leaving a folder open on Windows, `SDL_main` as an import in `vendor:sdl3`, the bindings gaps). The text engine (2026-11-02) and the AccessKit adapters (Orca 2026-11-10, Narrator and NVDA 2026-11-11) are done. `spikes/` is throwaway; the packages in §4.2 are created as phases need them.

### Phase 3: Text, UI, images, canvases, shaders
- Text with SDL3_ttf GPU engine (or the alternative chosen at the start of this phase), including copying system fonts into the sketch with the licence check (§4.9).
- `ui` with the full widget set (§5.8) on Dear ImGui: immediate-mode `ui [ ]` blocks, automatic layout, focus and keyboard navigation, text input with IME and on-screen keyboards, touch sizing, theme, value persistence in `ui.toml` (with the `toml` package written for it, §4.9), custom widgets.
- The AccessKit bridge (§4.8) on Windows, macOS, Linux, FreeBSD and OpenBSD, Android and iOS (macOS, Linux, FreeBSD and OpenBSD are checked by hand; Windows is written and not checked; Android and iOS are not).
- Images and pixels, offscreen canvases, blend modes, clipping, masks, image and video fills (§5.9).
- User shaders with hot reload; built-in post effects.
- Export: PNG, frame sequences, SVG/PDF.
- **Exit**: ports of ten classic Processing examples, pixel-compared where meaningful (done 2026-11-12: `bounce`, `sinewave`, `rope`, `life`, `flocking`, `koch`, `mandelbrot`, `noisewave`, `recursion` and `colorwheel`, each with a golden picture drawn on lavapipe, so what is compared is rocinante against itself from run to run; no Processing is run here to compare with, and the sketches are written fresh in the language after the idea of each, never translated line by line); a two-window sketch (control window with every widget, canvas window reacting live; built 2026-11-12 as `examples/studio`, with tests driving it by a screen reader's requests, the keyboard and the mouse, and still to be tried by hand) working with mouse, touch, keyboard only, and a screen reader on at least macOS (VoiceOver), Windows (NVDA or Narrator) and Linux (Orca); text boxes accepting non-Latin input through an IME.

### Phase 4: 3D
- Primitives, meshes, camera with default orbit, nodes, lights, PBR materials, shadows. (Started 2026-11-13: `box`, `sphere`, `plane`, `cone`, `cylinder`, `capsule`, `torus`, `icosphere`, `grid`, `axes` and `arrow` with a depth buffer, one light, the orbit camera and the camera verbs (`camera`, `look at`, `ortho`, `perspective`, `screen point`, `world point`), `examples/solids`, `examples/shapes3d` and `examples/stage`; the rest is next.)
- glTF import (`vendor:cgltf`), SVG import.
- 3D collision detection (§5.13).
- 3D turtle.
- **Exit**: a 3D generative sketch with lights and an imported model running on all six platforms.

### Phase 5: Sound
- SDL3 audio out and in, playback and streaming (miniaudio decoders plus `stb_vorbis`, §4.6), our own synthesis and effects, FFT and level analysis.
- MIDI (`vendor:portmidi` or our own backends) and OSC (our own), including the FreeBSD and OpenBSD MIDI decision.
- Audio-reactive visuals with zero setup (`level`, `fft` usable directly in `draw`).
- **Exit**: an audio-visual sketch controlled by a MIDI controller; latency measured and recorded here.

### Phase 6: The world outside
- Files and data formats, dialogs, network, serial and Firmata, webcam, video playback and recording (§4.11), sensors, gamepads, joysticks, actions and the `controls` widget (§5.12), video recording.
- 2D physics on Box2D v3 worlds (§5.13).
- Machine learning (§4.10): LiteRT bindings, `predict`, the built-in tasks and their chosen models, `roci add` conversion, `roci doctor ml`.
- **Exit**: an installation-style sketch (camera in, OSC out, UI control window, runs for 24 hours without leaks); a webcam sketch driven by `hands` at full frame rate on all six platforms; a game-style sketch played with two different gamepads, remapped by a player through `controls`.

### Phase 7: The compiler
- `codegen`: typed IR → readable Odin source, built with the user's Odin together with the core, on all four desktop OSes.
- Lists of same-shaped records as contiguous arrays (or `#soa`); vector maths as Odin array programming; boxed fallback as tagged unions. The optimisation passes of §4.7 (blocks as plain loops, construction in place, bounds-check elimination, frame-local values on the stack or the arena) run here.
- Source mapping from packaged sketches back to `.roci` lines (§4.7).
- `roci doctor` complete for desktop toolchains.
- Packaging build time measured on each desktop OS, since the core is compiled with every sketch (§4.7); record it here.
- Back-end equivalence suite (§9) running every example in both modes in the Linux pipeline, and locally on the other platforms before each release.
- **Exit**: every example produces identical frames interpreted and compiled; the particle benchmark (100,000 records updated and drawn per frame) holds 60 fps compiled on a mid-range laptop, with the interpreted figure recorded here for comparison. Measure the particle benchmark with each optimisation pass off and on, and record the result here.

### Phase 8: Packaging
- `roci package` for all six targets (generate, build, bundle, sign where needed); `roci doctor` for every target.
- `sketch.toml` (§4.9): the packaging questions, the version schemes checked against each store's limits, and the build number. Apple's version rules are read from its documentation first.
- Mobile behaviour for multiple windows, touch-first defaults, orientation.
- A run on an older or lower-end phone of each system besides the Pixel 9 and the iPhone 13 Pro, with frame rates (carried from Phase 1).
- **Exit**: the same sketch file packaged and installed on all six platforms by someone other than Fabrizio, following only the docs, starting from a machine with nothing installed except what `roci doctor` asked for.

### Phase 9: Community and tooling
- Language server (diagnostics and inferred-type hovers reuse the checker), syntax highlighting for nvim, Helix, VS Code and Zed.
- Documentation site where every verb has a runnable example (started for the alpha, 2026-10-30: `site/`, `tools/site`, `odin run build -- docs`; Phase 9 adds search, versions per release and the language server's hovers from the same data).
- Nature of Code and Generative Design example ports.
- `roci explain` (decided 2026-10-27): describe a line or block in plain words from the typed IR, for learners and for tools.
- Extension mechanism (Odin or C libraries that add verbs through the stable verb ABI, usable with the same `use` line, §5.10), then computer vision and depth cameras as extensions.
- The public library index (§5.10), with a handful of first libraries.
- **Exit**: the first stable release (§11).

---

## 9. Testing

- **Unit tests come first** (decided 2026-10-25): every package is written with `@(test)` procedures from its first commit, aiming for the best possible coverage (§3). `odin test <dir>` runs them, `-define:ODIN_TEST_NAMES=package.test_name` runs one, and `ci` runs every package's tests, so a failing or missing test fails the pipeline. The full `ci` runs them twice, at Odin's default `-o:minimal` and at `-o:speed`, because a result must not depend on how a sketch was built. The kinds of test below are in addition to unit tests, not instead of them.
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
- Checks and snapshots (§5.16): `check` and `expect` parsed, formatted and checked (every message with its sketch); a failed `expect` says what both sides were, each worked out once; checks never run in `roci run`; the names a check makes are its own; `roci test` exit codes and the stored picture (matching, a change said in words, a size change, `--accept`, no graphics) are tested, and `examples/checks` must hold.
- Libraries: multi-file sketches behave identically to the same code in one file; `use` with index names and git URLs; offline runs from vendored `libs/`; every clash rule produces its error message.
- Versions: `sketch.toml` read and written (missing file, hand-edited invalid values), each version scheme checked against every target's limit, and the build number never decreasing (§4.9).
- Toolchain: `roci doctor` tested on machines (or CI images) with each toolchain piece missing, wrong version and present. For every host and target pair, `roci doctor` and `roci package` give the "cannot be built on this computer" message exactly when §7's table says so.
- Performance: benchmark sketches tracked in both modes. Timing is gated only on ORION, whose hardware is fixed (lavapipe and shared GitHub runners are too noisy); elsewhere the pipeline compares work counts (draw calls, batches, allocations), which are exact. A timing regression of more than 10% on ORION fails the build.
- Platforms: Linux in the pipeline on every commit to `main`; every other target through the release checklist before each tag, and at least once per phase (§11).
- Golden images run on Mesa's software Vulkan driver (lavapipe) in the pipeline, so results don't depend on the machine's GPU. `tests/golden` draws every scene in `scenes.odin` offscreen through the real renderer at 2x and compares with the reference picture (on lavapipe a channel may be off by 8 for up to 8 pixels in 120,000 and no pixel by more than 16, measured 2026-11-10 against x86-64 Ubuntu 24.04, Arch and an Apple silicon Mac, whose worst channel was 6, 5 and 3; on any other graphics card the limits are looser, 12, 40 and 64: `Limits` in `tests/golden/main.odin`, chosen by whether the device says llvmpipe); it is a program rather than `odin test` because SDL's video system must start on a Mac's main thread. The full `ci` runs it on lavapipe (`build/golden.odin`), and the references are drawn there: on a Linux computer with a GPU, `VK_DRIVER_FILES=/usr/share/vulkan/icd.d/lvp_icd.json SDL_VIDEODRIVER=offscreen odin run tests/golden -- update` makes them (Arch's package is `vulkan-swrast`), and `VK_LOADER_DEBUG=driver` shows which driver was used.

---

## 10. Decisions and open questions

### Decided

One line per decision; the full text is in the section named, or here when there is none. Newer entries go at the end.

- **2026-10-22, Licence: Zero-Clause BSD (`0BSD`)** for the core, the language, `roci`, the docs and the examples; dependency rules in §3.
- **2026-10-22, Blocks are `[ ]`**, as in Logo, not `end`.
- **2026-10-22, Procedural and data-oriented**: verbs on plain data, no objects (§5.2).
- **2026-10-22, Inferred static typing**, no type syntax, boxed fallback (§5.3).
- **2026-10-23, Odin** for the core and `roci` (replaced Rust); `vendor:` first, our own bindings when it lags (§3, §4).
- **2026-10-23, Interpreted while working, compiled to Odin for release**; one front end and typed IR, no bytecode VM, no JIT (replaced Cranelift; §4.7).
- **2026-10-23, Packaging toolchains are the user's, except Odin and the Android SDK, NDK and JDK, which `roci` fetches**; FreeBSD uses its `odin-lang` package when it is the pin (§4.7, non-negotiable 2).
- **2026-10-23, UI is first class**: immediate-mode widget verbs in `ui [ ]` (§4.8, §5.8, non-negotiable 10).
- **2026-10-23, UI engine: Dear ImGui** through dear_bindings (replaced egui; §4.8).
- **2026-10-23, Screen readers are required for the first stable release**, through our own AccessKit bridge (§4.8).
- **2026-10-23, Audio without Rust**: miniaudio decoders, `stb_vorbis`, our own DSP and OSC, `vendor:portmidi` as the MIDI candidate; this dropped Symphonia's MPL-2.0 (§4.6).
- **2026-10-23, The name is always lowercase** (§3).
- **2026-10-23, Indentation is free and never meaningful**; `roci fmt` keeps it tidy (§5.1).
- **2026-10-23, Style is one vocabulary at three levels** plus named styles; `thickness` for stroke width (§5.9).
- **2026-10-23, Colour channels are 0 to 255, alpha 0 to 100 in the language** (2026-10-29; the Odin API and C ABI keep 0 to 255); `oklch` follows CSS (§5.9).
- **2026-10-23, Keywords are lowercase; all-capital names are deeply immutable constants** (§5.1).
- **2026-10-23, One `assets/` folder, found by name**; only it is bundled; output goes to `output/` (§4.9).
- **2026-10-23, `roci new` and `roci init`** make a git repository and offer Git LFS (§4.9).
- **2026-10-23, Remembered UI values are committed** in `ui.toml` (§4.9).
- **2026-10-23, One folder is one program**; other code through `use`, vendored into `libs/` (§5.10).
- **2026-10-23, Verbs are taught with `learn`**, results with `give` (§5.11).
- **2026-10-23, Sharing**: numbers, vectors, colours and text are copied, lists and records shared, `copy` copies (§5.11).
- **2026-10-23, No `devel` branch**; short branches merged fast-forward (§11).
- **2026-10-23, Commits never mention AI** (§3, §11).
- **2026-10-23, CI on Linux only**: GitLab on ORION and GitHub; GitLab pushes `main` to GitHub after each full pipeline that passes (revised 2026-11-11) (§11, non-negotiable 8).
- **2026-10-23, Calendar versions `YYYY.MINOR.MICRO`**, with `-alpha` or `-beta` before the first stable release (revised 2026-10-30; §11).
- **2026-10-23, One thing per argument**; full expressions after `=`, `give`, in conditions and inside literals; vectors are `{ a, b }` (§5.1, §5.2).
- **2026-10-24, Machine learning out of the box** on LiteRT, inference only (§4.10).
- **2026-10-24, Asset folders** `3d-models/`, `ml-models/` and `videos/`, all lowercase (§4.9).
- **2026-10-24, System fonts are copied into `assets/fonts/`**; the licence is the writer's business, with a warning (revised 2026-11-02; §4.9).
- **2026-10-24, Game controllers**: gamepads, joysticks, actions with `bind`, remapping through `controls`, SDL3's positions under friendlier names (§5.12).
- **2026-10-24, Gradients** are a list of colours in `fill`, `stroke` or `background`, mixed in Oklab (§5.9).
- **2026-10-24, Pictures, video, canvases and the webcam fill any shape**, which acts as a mask (§5.9).
- **2026-10-24, Collision detection built in**; 2D is our own Odin in `roci/collide` (revised 2026-10-29: `vendor:box2d` lags, lacks Linux, FreeBSD and phone libraries and is 32-bit), Box2D comes with physics (§5.13).
- **2026-10-24, User shaders are HLSL** (§4.3); a rocinante shader dialect is on the roadmap.
- **2026-10-24, The language is called rocinante too** (§1).
- **2026-10-24, No web target for now**; on the roadmap (README.md).
- **2026-10-24, The core ships as Odin source**, compiled with each sketch; C and C++ dependencies ship prebuilt (§4.7).
- **2026-10-24, The backtick hides the UI, Tab only moves focus; `ui` blocks may sit inside `draw`** (§5.8).
- **2026-10-24, The library index** is a git repository on GitHub curated by Fabrizio, with listing and removal rules; extensions ship as Odin source and prebuilt desktop libraries (§5.10).
- **2026-10-24, accesskit-c**: its releases cover macOS, Windows, Linux x86, iOS and Android; FreeBSD, OpenBSD and arm64 Linux are built from source (§4.8).
- **2026-10-24, Hot reload rules** (§5.5).
- **2026-10-24, List verbs** `keep`, `skip`, `collect`, `combine`, `find`, `sort … by`, with `it` and `result`; no pipe (§5.2).
- **2026-10-24, Video without FFmpeg**; FFmpeg only as the user's optional install (§4.11).
- **2026-10-24, Record shapes** by creation site, structural verbs, shapes from JSON assets, messages typed from `send` (§5.3).
- **2026-10-24, 2D physics on Box2D v3 worlds**; 3D physics on the roadmap (§5.13).
- **2026-10-24, Connecting words are positional**; multi-word verbs are a fixed table (§5.1, §5.14).
- **2026-10-24, Language details** (§5.15).
- **2026-10-24, A top-level `load` waits; loads in `draw` and events are asynchronous** (§4.4).
- **2026-10-24, UI identity is label, panel and tab path and loop index**; our own `toml` package (§4.8, §4.9).
- **2026-10-24, Files other than `sketch.roci` hold definitions only** (§5.5, §5.10).
- **2026-10-24, Trust and signing**: asking before a native extension, notarisation and SmartScreen, the Android SDK licence, checksummed ML models (§4.10, §5.10, §7).
- **2026-10-24, Keys bind by physical position** (§5.12). Dear ImGui does not shape complex scripts (Arabic, Devanagari): Phase 3 states which scripts the UI supports.
- **2026-10-24, Origin words `as center` and `as corner`**, per element, replace Processing's `*Mode` verbs (§5.9).
- **2026-10-24, Escape does not quit**; it leaves the widgets; Cmd+Q, Ctrl+Q and the close button quit.
- **2026-10-25, No cross-compilation between desktop systems**; iOS needs a Mac, Android macOS, Linux x86-64 or Windows (§7).
- **2026-10-25, Claude Code never pushes automatically** (§3).
- **2026-10-25, All code needs the best possible unit-test coverage** (§3, §9).
- **2026-10-25, iOS and Android are targets only**; `roci` never runs on a phone (§7).
- **2026-10-26, Desktop processors for the first stable release**: x86-64 FreeBSD, Linux, OpenBSD (2026-11-01) and Windows, and Apple silicon; other processors are on the roadmap (§4.7).
- **2026-10-26, Never commit on `main`** (§3).
- **2026-10-26, LF line endings in every clone**, set by `.gitattributes`.
- **2026-10-26, SDL patch releases count as the same SDL** (`docs/phases.md`).
- **2026-10-26, `CHANGELOG.md` and `CONTRIBUTING.md` are pointers** (§4.2, §11).
- **2026-10-27, Plain words, not English sentences**: one canonical form for every construct (§5.1).
- **2026-10-27, `sketch.toml`** for packaging details and the version; `roci` owns the build number (§4.9).
- **2026-10-27, Research notes folded in**: `[ ]` stays a block and a list, sharing stays with a hint; not adopted: call parentheses, value semantics, a `learn shader` subset, quantity suffixes such as `90 degrees`, user-visible effect handlers, live coding on phones (§5.1, §5.11).
- **2026-10-27, Our own vector tessellation** in package geom (§4.3).
- **2026-10-27, GPU debug mode is off unless `ROCI_GPU_DEBUG` is set**; it cost 0.3 ms a frame (code map, `roci/platform`).
- **2026-10-27, Set-up verbs act on the newest window** (code map, `roci`).
- **2026-10-27, No `wait` in the first stable release**: `every`, timers and tweens cover it, and a suspending verb puts non-negotiable 7 at risk in compiled code; it can come later without breaking sketches.
- **2026-10-27, The interpreter walks the typed IR** (§4.7); revisited only if the benchmarks need it, then as a register bytecode on Odin's `#must_tail` with `"preserve/none"` (§12), against a switch fallback.
- **2026-10-27, `roci explain` waits for Phase 9**; the typed IR stays rich enough for it.
- **2026-10-28, Labels for geometry, no commas between arguments** (§5.1).
- **2026-10-28, Window settings are words of `window` and properties changed with `set`** (revised 2026-10-29; §4.5, §5.2).
- **2026-10-28, `//` is a comment and `#` only a colour** (§5.1).
- **2026-10-29, The turtle** starts in the middle facing up, draws in black while the stroke is off, and resets each frame (§5.6).
- **2026-10-29, The mouse cursor is a window setting** (§4.5).
- **2026-10-29, Word arguments are checked against their words** (`registry.WORD_CHOICES`).
- **2026-10-29, `tween` is a statement and `ease` a verb** (§5.15).
- **2026-10-29, Mouse buttons are words, the wheel a value** (§5.15).
- **2026-10-29, A vector and two numbers mix in one geometry call** (§5.1).
- **2026-10-29, Touch is two events, a value and a list** (§5.15).
- **2026-10-29, The optimisation passes are shared by both back ends**; every pass off is the reference (§4.7).
- **2026-10-29, Tables, not maps**; `add`, `remove` and `put` refuse a constant (§5.15).
- **2026-10-29, Wayland first on a Wayland desktop** (Linux, FreeBSD, OpenBSD): SDL is asked for `wayland,x11` unless `SDL_VIDEO_DRIVER` is set, because XWayland lost window settings and density; it costs about 5% on the 100,000-circle benchmark (`docs/phases.md`, Phase 1).
- **2026-10-30, The documentation is a site built from the repository** by Hugo and `tools/site`, at rocinante-lang.org (§4.12).
- **2026-10-30, `background` is always behind everything**, wherever it is written (§5.9).
- **2026-11-01, OpenBSD is a supported platform**, treated as FreeBSD wherever the two share a gap (§1, §4.7, §7).
- **2026-11-02, Text: SDL3_ttf's GPU engine and Inter built in** (§4.3).
- **2026-11-02, The turtle can be read (`turtle`) and shown (`show turtle`)** (§5.6).
- **2026-11-02, Light tests: `check`, `expect` and `roci test`** (§5.16).
- **2026-11-03, Pictures: `load` and `image`**, decoded by `core:image`, drawn through the typeset pipeline (§4.3).
- **2026-11-03, Canvases keep their drawing** from frame to frame, at the density of their window (§4.3).
- **2026-11-03, Picture fills: shapes as masks** (§5.9).
- **2026-11-05, `outline` makes a polygon of a picture's solid part** (§5.13).
- **2026-11-05, `save "name.png"`**, with `#` as the frame number (§4.9, §6).
- **2026-11-05, `blend` and `clip` are style** (§5.9).
- **2026-11-05, A picture paints outlines, texts and backgrounds** (§5.9).
- **2026-11-05, Pictures never change; the pixel verbs make new ones** (§4.3).
- **2026-11-05, Shaders: `effect "wave.hlsl" by { … }`**, translated while the sketch runs (§4.3).
- **2026-11-05, Built-in effects: `effect "glow"`** (§4.3).
- **2026-11-05, Effects on canvases** stay on the canvas (§4.3).
- **2026-11-05, Shaders as fills: `shade`** (§4.3).
- **2026-11-06, `save "shot.svg"` and `save "page.pdf"`**, from the command list with no GPU (§4.3).
- **2026-11-06, `record` makes a movie**: APNG with nothing installed, video through the user's ffmpeg (§4.3).
- **2026-11-06, Odin moves to `dev-2026-11`** (`ODIN_VERSION`). Its rewritten `core:compress` changed `Image.pixels` and the image writers, so the vendored **sancho** was patched in place and must be patched the same way in sancho itself and copied back with `tools/vendor-sancho.sh`; its Android target (`odin bundle android`) is to be weighed before Phase 8.
- **2026-11-06, `font` finds one face of a font collection by its own name** (§4.9).
- **2026-11-11, Windows is Direct3D 12 only** (non-negotiable 9): a sketch's shaders are compiled there by FXC, which is part of Windows; DXC was turned down because it means shipping `dxil.dll`, a closed binary whose licence was not checked (§4.3).
- **2026-11-11, `ui theme dark|light|system`**, with `system` added so a choice can be undone (§4.8, §5.8).

### Later

Ideas that are wanted but not planned for the first stable release live in the Roadmap section of `README.md`, so contributors can see them. When one is taken up, it moves here and into §8.

### Open

Decide these with Fabrizio; move each to "Decided" with the date.

1. Machine learning on FreeBSD and OpenBSD: LiteRT's C runtime built there, or ONNX Runtime as the fallback (§4.10). Settled by the LiteRT spike at the start of Phase 6.
2. ExecuTorch as a second runtime for PyTorch's own `.pte` files, so PyTorch models skip conversion. It is C++ only, so it would need our own C wrapper, and a second runtime is a second behaviour to keep equal (§4.10).
3. Choices inherited from the sections they point to: text engine (§4.3, start of Phase 3); AIFF, Opus and AAC decoding (§4.6, Phase 5); MIDI on FreeBSD, OpenBSD, iOS and Android (§4.6, Phase 5); mobile multi-window behaviour (§4.5, Phase 8); video encoder libraries (§4.11, Phase 6); the Git LFS type list (§4.9, Phase 2); the name of `roci check --why-slow` (§5.3, Phase 2); Box3D for 3D collision (§5.13, Phase 4).
4. The accessible canvas (Phase 3): scene descriptions built from the command records (§4.3), a `describe "…"` verb, a live region that updates only when the scene changes, and colour-contrast checks, extending §4.8 from widgets to the canvas (p5.js does this with `describe` and `textOutput`, §12).
5. Libraries and `sketch.toml` (Phase 9): whether a library keeps its version in the same file, so `roci update` can say "flocking 1.2.0 to 1.3.0" (§4.9).
6. Teaching profiles (Phase 9): lint settings over one stable language, not Hedy-style levels where commands change.
8. **Window settings still not offered** (read from `vendor:sdl3`'s `WindowFlag` and `SDL_SetWindow*` procedures, 3.4.2 bindings): `transparent` (SDL's GPU API refuses to claim a transparent window, "The GPU API doesn't support transparent windows", checked 2026-10-28 on Metal; other systems untried), `UTILITY`, `TOOLTIP` and `POPUP_MENU` (they need a parent and belong with the UI work), `SetWindowIcon` (with packaging) and `FILL_DOCUMENT` (web). `HIGH_PIXEL_DENSITY` is always asked for. Caveats for the ones that are offered: some are only requests on Wayland and tiling window managers (position, topmost, borderless), and the phones ignore most of them (§7).

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
- `github` is the public mirror, `https://github.com/sandbenders/rocinante` (decided 2026-10-24, because the `Rocinante` organisation name is taken). **Pushed by the GitLab pipeline** (decided 2026-11-11, replacing a push by hand about twice a week): the `mirror` job runs after the `full` job passes on `main` and pushes that commit, and `mirror-tag` pushes a `v*` tag after its `release` job passes, so GitHub only ever has commits that passed the full pipeline (GitLab's own push mirroring was the other choice, and was turned down because it pushes before the pipeline has run). They push over SSH with a deploy key that can write only the GitHub repository, kept in the protected File variable `GITHUB_DEPLOY_KEY` (so the `v*` tags must be protected too), with GitHub's published host key written in the job. No `--force`: a push that is not a fast forward, such as an older pipeline finishing after a newer one, is refused and does no harm. Each push also runs GitHub's own pipeline and publishes the documentation site. `git push github main` by hand still works and changes nothing the job relies on.
- Issues and pull requests from the community arrive on GitHub. A pull request is accepted by fetching its branch locally, merging it through the normal GitLab flow, and pushing to GitHub; the README explains this to contributors.

**Pipelines (Linux only).**

- Both pipelines are thin wrappers: install the pinned Odin (read from the `ODIN_VERSION` file), SDL3 and Mesa's software Vulkan, then call the build script's `ci` command. All logic is in the build script, so the two can't drift apart.
- **GitLab** (`.gitlab-ci.yml`, runner on ORION, Arch Linux):
  - **fast check** on merge requests only (`rules: - if: $CI_PIPELINE_SOURCE == "merge_request_event"`): build, unit and language tests, error-message tests, format and licence checks;
  - **full pipeline** on every commit to `main` (`rules: - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH`): everything in the fast check plus golden images, back-end equivalence and benchmarks;
  - **release** on tags matching `v*`: the full pipeline plus the Linux release artefact.
  - **mirror** and **mirror-tag**, after `full` on `main` and `release` on a tag pass: push the commit or the tag to GitHub (Remotes, above).
- **GitHub** (`.github/workflows/ci.yml`, Ubuntu 24.04 runner, pinned so GitHub's `ubuntu-latest` move to 26.04 never changes what we test; we move it on purpose): the full pipeline on push to `main`, and the release job on `v*` tags (`on: push: branches: [main]` and `tags: ['v*']`). No merge-request job. Because GitHub runs Ubuntu and ORION runs Arch, every snapshot is tested on two distributions. SDL3 has no package on Ubuntu 24.04, so the workflow builds the latest stable SDL3 release from source with `tools/ci/install-sdl3.sh` and caches it under a key that holds the release's tag (decided 2026-10-27): a new SDL release rebuilds, an unchanged one is restored from the cache. The same job installs Mesa's software Vulkan for the golden images.
- No GPU is needed: golden images render through lavapipe (§9).

**Releases.**

- **Versions are calendar-based: `YYYY.MINOR.MICRO`** (CalVer; the scheme JetBrains IDEs use). `YYYY` is the year of the release, `MINOR` counts feature releases within that year starting at 1, and `MICRO` counts fix releases of that feature release starting at 0. The first release of 2026 is `2026.1.0`, its first fix `2026.1.1`, the next feature release `2026.2.0`, and the first release of 2027 is `2027.1.0`, whatever the count reached in 2026.
- **Before the first stable release every version carries the project's stage** (decided 2026-10-30), CalVer's optional modifier: `2026.1.0-alpha`, its fix `2026.1.1-alpha`, the next feature release `2026.2.0-alpha`, later `-beta`; the first stable release is the first version without one. The modifier names the stage, not a pre-release of that number, because the first stable release will probably fall in a later year, so `2026.1.0-alpha` is never followed by a plain `2026.1.0`. Numbered pre-releases of one version (`2026.1.0-alpha.1` up to `2026.1.0`) and plain numbers marked only in the notes were the other choices.
- A release is an annotated tag `vYYYY.MINOR.MICRO` on `main`, with its stage before the first stable release (the first is `v2026.1.0-alpha`), so the `v*` tag rules of both pipelines apply unchanged.
- The version does not signal compatibility. Releases before the first stable release are previews, which their stage says, and their release notes repeat. After it, any change that breaks existing sketches, the stable verb ABI or `ui.toml` is listed at the top of the release notes with the fix for each, and `roci check` explains it in plain words when it meets the old form.
- Before tagging, work through the release checklist (`docs/release-checklist.md`): build and run the examples, golden-image and equivalence suites on FreeBSD, macOS, OpenBSD, Windows, iOS and Android, record the results in the checklist's table for that version, and build the FreeBSD, macOS, OpenBSD and Windows downloads locally. The Linux download comes from the tag pipeline. **A release has downloads for the hosts only** (decided 2026-10-30): iOS and Android are targets, checked before each tag, but `roci` never runs there, so they get no download.
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
