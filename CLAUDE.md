# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

This file and `docs/design.md` (imported below) are together the single source of truth for rocinante's design, scope and plan. When a decision changes, update the file that holds the section, in place. Do not create other design documents, changelogs of decisions or "notes" files beside them. `MANIFESTO.md` is the public statement of intent; this file is how we build it.

Read `MANIFESTO.md` before starting any work. Every decision below serves it.

## Start here

- `main` moves between sessions and other work lands without this file being re-read: run `git fetch` and read `git log --oneline origin/main -20` before trusting anything below.
- Branch first, never commit on `main`, never push (§3). Fabrizio pushes, opens the merge request and merges. When he says a branch is merged, check `git rev-list --count origin/main..<branch>` is 0, fast-forward `main` and delete every merged local branch with `git branch -d`, without waiting to be asked (decided 2026-10-28).
- Run `odin run build -- ci` before handing a branch over.
- Phase 0 and Phase 1 are closed (§8). Phase 2, the language, is well under way: the front end, checker, interpreter, `roci run` (live reload, overlay), `roci fmt`, `roci man`, sketch folders, sketches of several files, libraries (`use`, `libs/`, `roci get`, `roci update`), input (`pressed`, `held`, mouse buttons by name, `wheel`, the window `cursor`, `on touch down`, `on touch up`, `finger`, `touches`), the turtle, 2D collision, tables, `tween` and `ease` exist; what is still open is running the newcomer test (its materials are ready in `tests/newcomer/`), and the Phase 2 code map below says what each piece does.

## Commands

Everything is driven by the build script in `build/`, written in Odin; there is no Makefile or CMake for contributors. Run it from the repository root with the Odin release named in `ODIN_VERSION` (`odin version` must match it; the build script warns locally and fails in the pipelines when it does not).

```
odin run build -- ci            # exactly what both pipelines run
odin run build -- ci --fast     # the pre-push subset (git config core.hooksPath tools/hooks)
odin run build -- licences      # dependency licence check against tools/licences.txt
odin run build -- odin          # check the installed Odin against ODIN_VERSION
odin run build -- docs          # the documentation site into output/site/public (Hugo, HUGO_VERSION)
odin run build -- docs serve    # preview it with Hugo, rewriting each file of site/ as it is saved (pictures drawn once)
odin check <dir> -vet -strict-style           # type-check one package
odin test <dir>                               # run its @(test) procedures (core:testing)
odin test <dir> -define:ODIN_TEST_NAMES=package.test_name   # run a single test
odin test <dir> -out:output/tests/<name>.exe  # on Windows: keep the test program out of the repository root, as ci does
```

**SDL3 must be installed to run `ci`**: the unit tests of `roci` link it, because the API can start a window even though the tests run headless. Arch has `sdl3`, FreeBSD `pkg install sdl3`, macOS `brew install sdl3`, the GitHub pipeline builds it (§11), and on Windows Odin ships `SDL3.lib` (and `SDL3.dll`, which must sit beside any program that opens a window: `cp "$(odin root)/vendor/sdl3/SDL3.dll" .`, ignored by git). `ci` runs `odin test` on every package listed in `TEST_PACKAGES` in `build/main.odin` (add a package there as soon as it has tests), and a failing test makes `ci` exit with 1. Tests run from the repository root, in parallel threads, and some make fixtures under `output/`. A test file that builds maps or dynamic arrays from literals needs `#+feature dynamic-literals` at the top.

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
odin run cli -- new <name> odin run cli -- get <git address> [--as name] | update [name]   # copy a library into libs/ from git, and fetch newer copies (run in a sketch folder)
| init | add <file>   # a sketch folder, its files in this folder, a file into assets/
ROCI_UPDATE_ERRORS=1 odin test roci/lang      # write tests/errors/**/*.txt, tests/check/*.types and examples/*/sketch.types again (review them like code); roci/interp does the same for tests/errors/runtime
ROCI_GPU_DEBUG=1 odin run examples/shapes     # any program with GPU validation on (off by default)
ROCI_PASSES=off output/roci run <sketch>      # the interpreter with no optimisation pass: the reference the passes are compared with
odin run tests/golden [-- update | scene]     # golden images: scenes drawn offscreen, compared with tests/golden/*.png
odin run tools/header -- include/roci.h       # regenerate the C header from the registry (a test fails when it is stale)
tools/abi-check.sh [--run]                    # build roci as a shared library, check its exports match the header, build examples/c/circle.c
shaders/compile.sh                            # HLSL to SPIR-V and Metal (glslang, spirv-cross); shaders/compile-dxil.sh makes DXIL on Windows
odin run spikes/codegen -- check              # Spike 3: interpret, generate Odin, build it, compare output
odin run spikes/codegen -- doctor [host]      # which targets this computer can build, and the toolchain
odin run spikes/mobile/macos                  # the phones' sketch on the desktop, 5 seconds
spikes/mobile/android/build.sh --install      # needs SDL_ANDROID_LIB and SDL_ANDROID_JAVA
spikes/mobile/ios/build.sh --install          # needs SDL_IOS_LIB, TEAM_ID and DEVICE
spikes/ui/setup.sh                            # Spike 4, once: Dear ImGui, dear_bindings and accesskit-c into .cache/ui (setup-windows.sh with MSVC)
odin run spikes/ui [-- interactive]           # Spike 4: slider, button, text box, and the screen-reader bridge on macOS
```

The phone scripts need SDL 3.4.18 built for the phone, which is not in the repository (the recipe is in the Phase 0 results in §8).

**What `ci` does not cover.** `ci` type-checks and tests the build script, `tools/term`, Spike 3 and every package under `roci/`. The full `ci` (not `--fast`) also runs every package's tests a second time built with `-o:speed`, so the optimiser can never change a result unnoticed (non-negotiable 7), and runs the golden images on lavapipe (`build/golden.odin`), skipping them with a note where lavapipe is missing and failing instead when `ROCI_REQUIRE_LAVAPIPE` is set, as both pipelines do. It type-checks the examples, `tests/golden` and the phones' sketch. It does not run anything else that needs a window, a GPU, a phone, or the libraries `spikes/ui/setup.sh` builds: example runs, golden images on real GPUs, the phone spikes, Spike 4 and the SDL window code are checked by hand, and a change to them needs a hand run on the affected systems before it is called done.

**Terminal output** is coloured through `tools/term`: every command that prints for people, including `doctor`, paints headings, results and errors with it and marks results with ✅, 🚫 and ❌ (`term.out_icon`). Colour is on only when the stream is a terminal and `NO_COLOR` is unset, the words are identical with or without it, and piped output and the pipelines stay plain. New commands use `term.out` and `term.err`, never raw escape codes.

**Where things are.** This file holds the rules, the plan and the decisions; `docs/design.md`, imported below, holds the architecture details, the language and the parity map; section numbers are global, so `§5.9` is in `design.md` and `§8` is here. `spikes/` is throwaway Phase 0 code, not the planned packages. The real packages (§4.2) are created as their phase needs them: `roci` (the public API), `roci/maths`, `roci/registry`, `roci/platform`, `roci/geom`, `roci/gfx`, `roci/lang` (the language front end, started in Phase 2), `roci/interp` (the interpreter), `roci/collide` (2D collision detection), `roci/folder` (sketch folders and their assets) and `cli` (the `roci` binary) exist, all in `TEST_PACKAGES`; `vendor/` and the rest of the language packages come later. Each new package updates this paragraph and the code map below in the same commit, joins `TEST_PACKAGES` and says which spike it replaces. `output/` and `.cache/` are generated and ignored by git.

**The code that exists so far** (only what the code does not say itself: invariants, traps and why. Keep each entry to a few lines when you add one: the code and its tests hold the rest, and this file is loaded every session):
- `build/`: `ci` is a list of `step` calls in `check_packages`, so a new package or spike joins the pipelines there and in `TEST_PACKAGES`; `check_optimised_tests` repeats every package's tests with `-o:speed`. `build/golden.odin` runs `tests/golden` on lavapipe only (the loader gets just the `lvp_icd*.json` manifests, `SDL_VIDEODRIVER=offscreen`, and it fails unless the device says llvmpipe, so another GPU can never pass by accident).
- `spikes/` is throwaway Phase 0 code. `spikes/codegen` is the language pipeline in miniature (one typed IR, two back ends calling the same `verbs` package; `doctor.odin` holds §7's host and target table); `spikes/ui` is not in `ci` (it links what its setup script builds).
- `roci` (the public Odin API, §4.1): the verbs over one thread-local sketch, `the`. Verbs act on the *current window*: the default window while the program sets itself up (made by the first verb, so one circle then `run()` is a whole program), the window whose `draw` block runs during a frame, otherwise the window the last `window` call made (reading order). The first `window` call replaces the default window and keeps what was drawn into it. `run(block, frames)` loops; `step(events, dt)` is one frame and drives a **headless** sketch (`start_headless`, no SDL) in tests, golden scenes and benchmarks. A window with no `draw` block keeps its set-up drawing; with one, each frame starts from the default style. `api_table.odin` says which Odin procedure answers each registry verb (names differ where Odin's builtins clash: `abs` is `absolute`, `map` is `map_range`, `clamp` is `clamp_between`), and a test fails if the registry gains a verb without an entry. Ctrl+Q and Cmd+Q quit; Escape does not.
  - `turtle.odin`: `forward`, `back`, `left`, `right`, `pen_up`, `pen_down`, `home`; home is the middle of the current window, worked out at each move.
  - Mouse buttons are held **per window** (`Win.buttons`): `mouse_down` and `pressed` say whether a button that went down in the current window is still down, and losing focus releases every key and button. The language reads them as `pressed` (any button) and `held "mouse right"` (`MOUSE_BUTTON_NAMES`: left, middle, right, back, forward; `held` with any other name is a key), and `on mouse down right` matches the button name the event log keeps. `wheel` is what the wheel turned during the last frame, summed over its events.
  - `touch.odin`: each window keeps the fingers that went down in it (`Win.fingers`, in that order) and numbers them from `next_finger`, never reusing a number in a run; positions are SDL's fractions of the window times its logical size. `touches` reads them; a finger going down or up is logged with its `Touch`. `platform.start` sets `SDL_HINT_MOUSE_TOUCH_EVENTS` so the left button is a finger on the desktop too (SDL already makes mouse events from fingers).
  - `events.odin`: the frame's log of key presses (not repeats), mouse buttons (with the button's name), fingers going down and up (with the finger) and window changes by window (`happened`), `last_key`, Ctrl/Cmd+R as `Restart`, and `set_frame_hook`, run for each window after its frame begins and before its `draw` block (the interpreter runs `on`, `every` and messages there). `overlay.odin`: `set_overlay` draws an error band over every window after the frame is built and takes it off the command list again (`gfx.mark`, `gfx.rewind`), in the overlay font (ASCII only). `begin_restart` and `end_restart` give the open windows to a sketch that runs again, in order, so windows never jump. `capture.odin`: `picture` draws a window offscreen, starting a device of its own for a headless sketch. `recorded` and `open_windows` are for tests and tools.
  - **Windows**: `window_settings.odin` holds every setting a window can have (resizable, bordered, topmost, visible, focusable, grab, modal, parent, size limits, ratio, alpha), remembered on the `Win` so a headless sketch can be asked, handed to SDL when there is a window, and put back by a restart (`reset_settings`). What the language can read and set is `registry.WINDOW_PROPERTIES`.
- `roci/abi.odin`, `abi_header.odin`, `include/roci.h`, `examples/c/circle.c`: the C ABI, every verb a plain `roci_<verb>` function with no logic (colours four floats 0 to 255, windows `roci_window_id` because `roci_window` is the function, one function per shape, the others suffixed). `ABI_TABLE` lists every function and the registry verb and shape it is; `ABI_NOT_IN_C` lists the shapes with no C form and why. Tests fail when a registry shape has neither, when a parameter type differs from the registry's kinds, when the header is stale (`odin run tools/header -- include/roci.h`) or does not compile as C and C++. `tools/abi-check.sh` compares a shared library's exports with the header (exit 3: cannot run here; `ci` fails instead when `ROCI_REQUIRE_SDL3` is set, as both pipelines do).
- `roci/maths`: colours (RGB, HSB, OKLCH, hex, the CSS names, `mix`), the one random generator (SplittableRandom) and noise (Perlin and simplex, 1 to 4D, Gustavson's constants), and `sin_deg`/`cos_deg`, which reduce the angle exactly to a quarter turn and use a Taylor series, so right angles are exact, -0 never comes out and every system gives the same numbers. Both back ends call all of it (§4.7). `ease.odin`: the ease curves (`ease`, `EASE_NAMES`, which a test keeps equal to the registry's words).
- `roci/registry`: the data the whole language is made from. `VERBS` (what the Odin API and the C header have) and `LANGUAGE_VERBS` (what only the interpreter has) make `ALL_VERBS`, built once at start because lookups return pointers into it; the closed lists of connecting words, keywords, built-in values and events; `labels.odin` (the **label forms**: which words write which inputs of a shape, so the language writes `circle at 100 100 radius 50` while shapes, the header, the IR and the interpreter keep `x y radius`; a verb with rows accepts only the listed shapes, the six-number `triangle` stays C-only); `WINDOW_PROPERTIES` (read, and set when `settable`) and `WINDOW_FREE_WORDS` (words only a window's settings use, which stay free as names); `manual.odin` (`manual_page` and `STATEMENT_DOCS` behind `roci man`). `VERB_SYNONYMS` turns another tool's word for a verb (Logo's `fd`) into the suggestion of an unknown word. `words.odin`: `WORD_CHOICES`, the words each word argument may be (`caps round`, `as center`, `cursor none`; a verb of "" is the shapes' origin words), which the checker holds every word to (`Unknown_Choice`, with the nearest word); a test fails when a word argument has no list or a list has no argument. A new verb is a row in `verbs.odin`, its procedure in `roci`, its entry in `api_table.odin` and a C entry or `ABI_NOT_IN_C` reason.
- `roci/lang` (grammar in `docs/grammar.ebnf`; no GPU): lexer, `prescan` (reads the `learn` headers first so a call may precede the `learn` that teaches it), error-tolerant parser (a `Lex_Problem` still makes a token, an `Error_Stmt` resumes at the next line or block end, so one pass reports every error), checker, typed IR (`ir.odin`), error catalogue (`catalogue.odin`), `report.odin` (the §5.7 format), `json.odin`, `format.odin`. Spans are byte offsets; the files of a sketch folder are **joined into one `Source`** (`join_sources`, each file followed by a line break, `Source.parts` saying where each begins), so the parser, checker and interpreter see one program and only the code that prints a file name or a line asks `place_of` (the file and the line inside it). `order_files` fixes the order: library files, the other files by name, `sketch.roci` last; only `sketch.roci` may hold statements that run (`Definitions_Only`), and a verb taught twice is `Verb_Twice`. `Diagnostic` carries four words (`a` to `d`, `d` the writer's own line fixed). Every message id needs a sketch in `tests/errors/<id>/` with its exact text (runtime ones in `tests/errors/runtime/`, run by `roci/interp`); `ROCI_UPDATE_ERRORS=1 odin test roci/lang` rewrites the `.txt` files, `tests/check/*.types` and `examples/*/sketch.types` (review them like code). The words of a message never hold a bare bracket, and `GRAMMAR_RULES` in `parser.odin` is compared with the grammar file by a test.
  - **How a call ends** (§5.1): at most as many arguments as the verb's largest shape; a connecting word starts an option only once the required arguments are filled (so `width` is a value in `rect 0 0 width height`); a call also ends at the end of the line, at a closing bracket and, in a block written on one line only, at two spaces (`block_is_on_one_line`; spaces mean nothing after `=`). Labels: `at 100 100 radius 50` is read as options (a label word takes as many items as its longest form and stops at another of the verb's words) and `check_labels.odin` builds the ordinary argument list in input order, so `IR_Call` is what the C function takes.
  - **A connecting word the call does not take** (`cos angle`, `print stops`), where the call still needs a value, is read as a value, so the checker says `Reserved_Name` once instead of the call ending early and every bracket after it looking wrong (found 2026-10-29 by writing `examples/particles`); a call nested without brackets still stops at it, since the word is most likely its outer call's. Reading such a word anywhere is `Reserved_Name` with the line renamed, never "give it a value first".
  - **Words that are also verbs**: where a verb takes a word (`caps round`, `joins miter`), the parser takes the word as written, so `round` can be a verb (`round 2.5`) and still be what `caps` and `joins` ask for. The same holds for keywords after a connecting word that takes a word (`cursor hidden` reaches the checker, which says `hidden` is not a cursor).
  - `highlight.odin`: what each piece of a sketch's text is (verb, connecting word, built-in value, colour, number, text, comment, name), from the lexer and the registry; a word that is both a verb and a connecting word (`fill`) is a verb only where a statement starts. The documentation colours its code with it.
  - **Teaching errors the parser builds from the writer's line**: `Needs_Brackets` (a call or calculation in an argument position, including arithmetic after a call's last value, `last_value`), `Word_Outside_Brackets` (`fill (item 1) of colors`; the checker drops its echo on that line), `Index_Brackets` (`colors[1]`), `Unknown_Option` (`color` is `fill`: `OPTION_SYNONYMS`, else the nearest word of the call; `last_call`), `Hash_Comment`, `Colours_Expected` (a list used as a colour that holds something else, such as `[colours]`), `Title_Of_Window` (`title w "x"` is `set w title "x"`), `Labels_Needed`, `Comma_In_Call`. The checker builds `Set_Window` (assigning a window property shows the `set` line).
  - **The checker** runs twice over the tree: the first pass reports nothing and only settles record shapes (one per place a record is made, merged by `unify` when records meet), so a field assigned on a later line is a field above it. Every name assigned anywhere is sketch-wide from the start with a type its first write settles (`No_Value_Yet` for a block that runs where it is written), capitals mean a constant, and an `Error` type fits everything so one mistake gives one message. A `learn` is checked **once for each distinct tuple of argument types** (`IR_Instance`; one version per record shape; the instance is cached before its body is checked, which is how recursion ends); `give` unifies one result variable; `terminates` is the all-paths rule; a verb taught in another file gives a boxed value. Messages sent are typed per window by name in the first pass (`check_messages.odin`). Window properties and the window words are checked from `registry.WINDOW_PROPERTIES`.
  - **The formatter** formats the tree, not the text, keeping every literal as written. Where the style leaves a choice (a block or list or record on one line or several) the sketch's choice stands and only what is too long (`FORMAT_WIDTH`, 100) is broken, so formatting twice changes nothing; a one-line block separates statements with two spaces; a multi-line `learn`, `draw`, `on` or `every` gets a blank line before and after (a comment right above it stays attached). Label words go in the registry's order. Comments and one blank line are kept; a block holding a comment is never put on one line. Parser errors stop it except `Needs_Brackets`, which it fixes with the parser's own fix. A test formats every example and `tests/check` sketch and compares the tree before and after.
- `roci/interp`: a tree walker over the typed IR calling the same `roci` procedures an Odin sketch calls. `load` runs `lang.optimise` (`roci/lang/optimise.odin`, the passes both back ends share) after checking; `fast.odin` works out nodes the typed pass marked as plain `f64` or `bool` (`eval_number`, `eval_bool`, `eval_cond`), each case doing exactly what its general case does, which a test checks by running every example with the passes off and on. A number-typed name, field or `find` can hold the empty value, so only a `Sure_Number` is stored or passed as a plain number. `load` reads and checks (the sketch text is copied into its arena: names in the tree point into it); `start` runs the top-level statements and hands each `draw` block to the app loop through one trampoline (`draw_trampoline`, finding the block by `roci.current_window()` in a thread-local `current`). **Memory**: values made while the sketch sets itself up live in its arena (`long`), values made while a block runs in the temporary allocator, which the app loop frees each frame; `promote` deep-copies a list or record into the arena whenever it is stored in a sketch-wide name or a long list (`keep`), and the `long` flag keeps sharing (`b = a`) true. The program (text, tree, types, bookkeeping) has its own arena (`program_memory`); values have two (`values`), because an arena frees nothing and a `draw` block that replaces a name each frame (`dots = keep dots [ ... ]`) left every old copy behind (48 MB after 1,000 frames of a 1,000-record list, found 2026-10-29). `collect.odin` copies what the roots reach (sketch-wide names, tweens, the collision cache) into the other arena between frames once the one in use holds twice what was live plus a megabyte, with a map from old to new addresses so sharing, ids and stamps survive. `print` keeps its lines only when they are not written to the console (tests). Names: sketch-wide symbols in `globals`, an array by `Symbol.slot` (the name's place in `IR_Program.symbols`; a map cost 7% of a busy frame), parameters, loop names, locals and message names in the current `Frame`, `it` and `result` on two stacks; `give` and `stop` are a `Flow` status passed up, never an exception. Verbs are a switch on the verb's `Verb_Code` (`codes.odin`, looked up once by the verb's place in `registry.ALL_VERBS`; switching on the name compared strings case by case and cost a fifth of a busy frame) and its chosen shape; a test fails when the registry gains a verb with no code. A core verb's arguments are kept on the stack (`ARGS_ON_STACK`). **Runtime failures never stop a sketch**: an item that is not there, a division by zero, recursion 100 deep and a block over its 2-second budget give an empty value or 0 and a `Runtime_Error`, said once per place. `events.odin`: `on`, `every` and `on w receive` only register a `Handler`; the frame hook runs them (messages, then the events of that window, then `every`), and `send` copies the value into one of two message arenas, so no window shares memory with another. `windows.odin`: the window words and `set`.
  - **Libraries**: `use "name"` joins the files of `libs/name/` (and the libraries those `use`) as that library's parts (`Part.library`, `Taught_Verb.library`, `Learn_Decl.library`); verbs are found by `library/name` (`learn_key`), the parser's `taught_for` picks the caller's own library, then the sketch, then a library for a plain name and reads `library.verb` as that library's, and the checker says `Hidden_Verb`, `Library_Clash`, `Shadows_Library`, `Library_Missing` and `Library_Name_Taken`.
  - **Collision** (`collide.odin`): a record is the shape its `{ }` was written with, so a list may mix lines and circles even though their record shapes merge: the checker gives each `IR_Record` a `lang.Shape_Class` from the literal's field names (`check_collide.odin` checks every place a merged shape is written, through `Checker.site_names`) and the interpreter keeps it on the `Record` through `promote`, `copy` and reload. Every `List` has an `id` and a `stamp`, every `Record` a `stamp`, from `Interp.writes` (`next_write`: field assignment, `add`, `remove`, a `for each` write-back that changed an item); `tree_for` keeps a box tree for a list asked about twice unchanged (`SHAPE_CACHE_SIZE` entries, heap memory, freed when dropped and in `destroy`), and checks one by one otherwise, with the same answers in the same order. Empty `contact` and `cast` results are records of zeros.
  - **Tweens** (`tween.odin`): a tween finds its place once when it starts (a sketch-wide symbol, or a long record and the path into it) and keeps that path on the heap, because it outlives the frame that started it; `step_tweens` runs once a frame in the frame hook, before any handler or `draw`, and the last step writes the value exactly. A new interpreter (reload, restart) starts with none.
  - **Tables** (`tables.odin`): a `Table` keeps its names in `keys` and a `map` from name to place, so names come back in the order they were put; `table_copy` is shared by `promote`, `copy` and reload (`convert`, with the new value type). A missing name reads as `zero_value` of the call's type.
  - **Several files**: `load_files` takes the files in joining order; `watch` of a `sketch.roci` watches every file of its folder (the modification times each frame, the folder listing twice a second for files that come or go) and `reload_files` reloads the whole program. A file that is not `sketch.roci` runs alone.
  - **Reload and restart** (`reload.odin`): the file's modification time is polled once a frame; `reload` checks the new text first (errors leave the old sketch running under the overlay; saving back the running text clears them; a sketch that opens with errors still opens a window and waits). Otherwise it makes a **new `Interp`**, retires the old one (freed next frame, since a reload happens inside the old one's hook), and carries values: top-level statements are matched by their text, an unchanged assignment keeps its value (`convert` reshapes it to the new types; `compatible` is false when a record lost a field or a kind changed, so that line runs again), constants always run, `draw`, `on` and `every` register again. A changed, new or removed statement that opens a window or draws while setting up (`is_effect`) cannot run twice, so the sketch **restarts** from its first line instead. Every reload says which it was.
- `roci/folder` also reads a program: `read_program` (every `.roci` file of the folder of a `sketch.roci`, not `assets`, `libs`, `output` or hidden folders, in joining order), `roci_files`, `program_root`; it also reads the libraries a program `use`s from `libs/` (`uses_in`), and `roci new` makes `libs/` with a `.keep`. `libraries.odin`: `get_library` (a shallow `git clone` into `libs/.fetching-<name>`, the `.git` folder dropped, a `source` file with the url and the commit written, then renamed into place; the libraries it `use`s by git address are fetched too and a different source for one already there is only said), `update_library` (the same into a staging folder, compared file by file with the copy, replaced only when something differs), `fetch_missing_libraries`; git is the user's own tool and no test uses the network.
- `roci/folder`: `new_sketch` and `init_sketch` (never overwrite anything; `new` refuses a name that exists), `start_git` (a first commit only when git is installed and the folder is not inside a repository already; Git LFS only when asked and installed; none of it is a dependency), `add_asset` (copies into the folder its type belongs in, refuses a name already anywhere in `assets/`), `find_asset` (the lookup by name the loading verbs will use; two files of a name are `Ambiguous`), `is_outside_assets`. `make_directory_all` reports `.Exist` for a folder that is there, so use `ensure_directory`.
- `cli` (the `roci` binary, §7): `new`, `init`, `add`, `get`, `update`, `run`, `check`, `fmt`, `man`. `get` and `update` (`get.odin`) say in words what `folder.get_library` and `update_library` did; `run` and `check` also fetch a `use` of a git address that is not in `libs/` yet. `run` and `check` take a file or a folder (the `sketch.roci` inside it, which stands for every `.roci` file of that folder: `read_files`); `fmt` reads the verbs the other files of a sketch teach; `run --frames N` is headless and can `--screenshot`; messages go to the console as they happen, coloured through `tools/term`, and `--errors json` prints them as data. `fmt` with no name formats every `.roci` file here except `assets`, `libs`, `output` and hidden folders.
- `site/` and `tools/site` (the documentation, published on GitHub Pages by `.github/workflows/docs.yml`): `site/hugo` is the Hugo project (our own theme, system fonts only, no web fonts), `site/guides/*.md` the hand-written guides, `site/reference/<word>.roci` one example per reference word. `tools/site` copies the Hugo project to `output/site` and writes the rest: a page per word of `registry.REFERENCE_SECTIONS` from the registry (the same data as `roci man`), each example's picture drawn headless in a 400 by 300 window (`roci.set_default_window_size`), the messages page from `tests/errors`, and the guides with every `roci` block coloured by `lang.highlight`. The tab icon and the header's and footer's logo are made from `docs/logo/rocinante-logo.svg` (`write_logo`), never kept by hand. Generated pages are Markdown whose `<pre>` blocks are one line (`one_line`), because a blank line ends an HTML block and Hugo refuses `.html` content by default. Tests fail when a word has no example, an example does not check or is not formatted, or a guide's code block has an error or warning (`check_files_test.odin`); `roci/registry` fails when a word is in no section or two. Hugo is a build tool only, pinned in `HUGO_VERSION` and installed by `tools/ci/install-hugo.sh` (checksum checked). `docs serve` runs `tools/site --watch` (`watch.odin`): it keeps the reference pages already in `output/site`, starts `hugo server` and copies or rewrites only the files of `site/` that change; a change to the registry is Odin code and needs a new start.
- `tools/term`: `out`, `err`, `message` (paints an error message by its parts), `out_icon` and `err_icon`; colour only on a terminal with `NO_COLOR` unset, the words identical either way. `setup` is called first in every `main`.
- `roci/platform`: SDL3 and the GPU device. On a Wayland desktop (Linux, FreeBSD) it asks SDL for `wayland,x11` unless `SDL_VIDEO_DRIVER` is set (`video_driver_hint`), because XWayland on niri lost window sizes. SDL is shared by every `App` (a program's and the picture device a headless sketch starts), so only the last `shutdown` calls `SDL_Quit` and the others `SDL_QuitSubSystem`; quitting it under a live device crashed the golden program on lavapipe. High pixel density is always requested; `set_vsync` tries immediate, then mailbox, else vsync. **On Android SDL counts window sizes in pixels**, so `window_metrics` and `input_scale` divide by the content scale there (`WINDOW_IS_IN_PIXELS`). The device always has clip distances off (a Mali GPU needs it) and SDL's debug mode off unless `ROCI_GPU_DEBUG` is set (it costs every sketch about 0.3 ms a frame). `translate` and the size sums are pure and tested; the SDL calls are checked by hand with `examples/window`.
- `roci/collide`: 2D collision in pure `f64` (no Box2D until physics, Phase 6). Shapes become convex `Piece`s of at most four corners plus a radius (polygons through `geom.triangulate`); `contact` takes the deepest pair of pieces (SAT where the corner parts overlap, closest points where they do not), so a concave polygon's inner edges can give a sideways normal. `Tree` is a box tree built once per list (splits ordered by centre, then by place) and must answer exactly what checking every shape answers, in list order; a test compares the two on random shapes.
- `roci/geom`: plane geometry, pure `f64`, our own tessellation (no library): curves flatten within a tolerance, `triangulate` is ear clipping with Eberly bridges and even-odd nesting (never loops on a self-crossing outline), `stroke_polyline` does caps and joins and joins the inside of a corner so a translucent stroke does not darken there.
- `roci/gfx`: the drawing model, no GPU. A `Command_List` per window stores 64-byte `Recorded` commands pointing into `looks` (style and transform stored once per run); style and transform change only through setters (`look_changed`). Non-finite numbers drop the command, negative sizes are made positive, `push` has two scopes. `Batcher.build` makes instances for one signed-distance "shapes" pipeline (a run of circles, ellipses, rects, lines, points and triangles is one draw); what that shader cannot draw as styled (`needs_mesh`: quads, arcs, mitred or bevelled corners, butt or square ends) is cut into triangles by geom in the shape's own space, so an outline's width follows the transform. Circles, ellipses and arcs are centred, rect and square start at their corner. `command_hash` (spans excluded) lets an unchanged batch reuse its GPU buffer; `mark` and `rewind` take back what was recorded after a point.
  - `turtle.odin`: the turtle lives on the list beside the transform (`begin_frame` sends it home, a `.Style_And_Transform` push saves it, `mark` keeps it). The list does not know its window's size, so an unmoved turtle is "at home" and the caller passes home with each move. While the stroke is off its lines are drawn in `TURTLE_INK`, the style put back straight after.
  - `gradient.odin`: up to 16 colours, baked on the CPU into 256-colour ramps in a `Gradient_Atlas` (256 gradients a frame, then it starts again once and the rest draw in their first colour); positions are fractions of the shape's own box. `font.odin`: the overlay font, a public-domain 8x8 bitmap font (printable ASCII, whole-number sizes) so the overlay needs no font file; real text is Phase 3.
  - `renderer.odin`, `png.odin`: pipelines are made on first use and a failure is recorded once, never retried per frame; drawing is 4x multisampled and resolved, premultiplied blending, uploads skipped when a batch hashes the same as last frame's. `render_offscreen` reads a frame back; `png_encode` is our own writer (Odin only reads PNG): `Png_Filters` chooses between each row's filter by libpng's rule and no filter, by default making both and keeping the smaller (flat colours with hard edges compress better unfiltered); `deflate.odin` is our own compressor (hash chains of 128 and lazy matching, as zlib's level 6, which it matches in size; each block the smallest of its own Huffman codes, the fixed ones or stored; the same pixels always give the same bytes), tested by inflating with Odin's reader, generated inputs included. The same compressor and writer are published on their own as sancho (https://github.com/sandbenders/sancho, 0BSD; it also writes grey and 16-bit pictures): a fix in one belongs in the other. Shaders are HLSL in `shaders/` with SPIR-V, Metal and DXIL outputs committed in `shaders/compiled/`. Metal needs texture-upload offsets that are multiples of 16.
- `tests/golden`: `scenes.odin` is where a new golden scene goes; `examples.odin` runs the examples written in the language at a fixed seed and compares each window with `example_<name>_<window>.png`. A window with no reference yet is said so and does not fail: the references are drawn on lavapipe, so run `odin run tests/golden -- update` where it is, look at the pictures, and commit them.
- `tools/ci/`: `install-odin.sh` installs the release in `ODIN_VERSION` for both pipelines; `install-sdl3.sh` builds the latest stable SDL3 for GitHub (GitLab's Arch image has `sdl3`, `diffutils` and `vulkan-swrast` as packages, GitHub gets lavapipe from Ubuntu's `mesa-vulkan-drivers`).

**Shell and tool gotchas** (these have all cost time):
- Fabrizio's `ls` is an alias for `eza` and adds colour codes, so scripts and anything piped must use `command ls`. Use `rg`, not `grep`, in anything written for him; portable scripts that contributors run (hooks, CI) use POSIX tools.
- macOS has no `timeout`, and BSD `sed` needs `-i ''`.
- Odin: write `-target` before `-subtarget`; a literal `{` in an `fmt` format string means something, so pass it as an argument; a procedure cannot return a slice literal (copy it to the heap); a global cannot call a procedure that needs `context`.
- Odin on Apple Silicon guesses the wrong NDK folder, so set `ODIN_ANDROID_NDK_TOOLCHAIN` (to the `darwin-x86_64` toolchain) when building for Android.
- Never test a mobile app on a sleeping or locked phone: Android draws nothing, iOS refuses to launch.
- Odin `dev-2026-10`: `for x in m[key]` crashes when `key` is missing from the map, so copy the value to a local first (`list := m[key]`, then `for x in list`); found in Spike 3, worth reporting upstream.
- Windows: an `-out:` path must end in `.exe`, and a running program's file is locked, so nothing may write `build.exe` while `odin run build` runs (`ci` puts test programs in `output/tests/`). A program that needs `SDL3.dll` finds it only next to itself or on `PATH`. To get MSVC's `cl` and `lib` into Git Bash, run `call "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat"` in a plain `cmd`, then `"C:\Program Files\Git\bin\bash.exe" --login -i` in the same window (the Start menu's Native Tools prompt did not set them up on Fabrizio's machine, which has both Build Tools and Community installed). C and C++ code linked into an Odin program is built with `-MT`, because Odin links the static C runtime.
- Odin `dev-2026-10` sometimes crashes in its own checker (`src/checker_global.cpp(1682): Assertion Failure: g->groups[gi].done.load()`, "This is a compiler error"), seen once in Spike 3's generated program during a pre-push `ci`; running it again passed eight times out of eight. Run it again rather than chase it; whether to report it upstream is Fabrizio's call.
- Timing on Fabrizio's CachyOS computer: there is no `time` or `bc`; use `hyperfine -N --warmup 1 --runs 5 '<command>'` (installed 2026-10-29), and subtract a one-frame run to get the cost of a frame.
- `perf` on Fabrizio's CachyOS computer: only user-space sampling opens (`perf record -e cpu-clock:u`), and not with call graphs (`-g` and `--call-graph dwarf` fail with "Failure to open any events"), so profiles are flat; build with `-o:speed -debug` for names and `perf annotate` for lines.
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
    lang/              lexer, parser, checker, type inference, typed IR (no SDL, no GPU)
    folder/            sketch folders: roci new and init, the assets/ folder and finding a file in it
    interp/            the interpreter: runs the typed IR through the roci API
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
                       logo/rocinante-logo.svg (the logo: the one drawing its copies are made from),
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
roci get <url> [--as n]  vendor a library from a git address into libs/ (§5.10); a short name waits for the public index (Phase 9)|url>      vendor a library into libs/ (§5.10)
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
- **FreeBSD**: `roci package` uses the `odin-lang` package (port `lang/odin`) when it is the pinned Odin, and builds the pinned release from source otherwise (decided 2026-10-30, §4.7). Produce a package of the sketch; later, a port of `roci` itself (named `roci`, because `sysutils/rocinante` is another project's port) (`poudriere bulk -t`).
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

Phase 0 built the repository, the build script with its `ci` command, the hooks, both pipelines, the licence check and the unit-test setup (§9, §11), and tested the riskiest assumptions with four throwaway spikes in `spikes/`: (1) an SDL3 window and GPU device on every desktop system, FreeBSD on Vulkan through Mesa included; (2) an Odin and SDL3 program drawing a shader circle on a real iPhone and a real Android phone; (3) a hand-written typed IR run by an interpreter and turned into Odin, with a stand-in `roci doctor`; (4) Dear ImGui through dear_bindings with the SDL3 and SDL_GPU backends, a text box with IME, and an AccessKit adapter read by a screen reader. It also checked every dependency, the name, the parity map (§6) and Odin's target coverage. What later phases need is below; per-platform run details are in git history.

**Phase 0 results** (recorded 2026-10-24 to 2026-10-27):

- **Odin:** pinned to `dev-2026-10`. Official archives cover Linux amd64 and arm64, macOS arm64 and Windows amd64 only (§4.7). Homebrew's `dev-2026-07` (LLVM 23) failed to compile any program; its `dev-2026-10` (LLVM 22.1.8) works. On FreeBSD (15.1) the pinned release builds from source in about 2 minutes with `LLVM_CONFIG=llvm-config19 gmake release-native` (it needs `gmake`, git and the ports package `llvm19`, because the base system's clang has no `llvm-config`, so `roci` must find it under its versioned name) and reports the same commit as the official archives.
- **`vendor:sdl3`:** its bindings are for SDL 3.4.2 while the latest release is 3.4.18. Patch releases keep the ABI, so the bindings load the newer library, but functions added after 3.4.2 are missing; nothing so far needed one. Results from SDL 3.4.2, 3.4.16 and 3.4.18 count as the same SDL (decided 2026-10-26).
- **Name check** (2026-10-24; registries and GitHub queried directly, no legal search): FreeBSD already has a port `sysutils/rocinante` (BastilleBSD's tool), so ours is named `roci`; `roci` is free as a command on Homebrew, the AUR and Repology (a small crates.io library, an npm package and a dormant PyPI package use the name, none a creative-coding tool); `rocinante` is taken on npm and PyPI by unrelated web frameworks and free on crates.io and Homebrew (we publish to none); the GitHub organisation `Rocinante` is taken, so the mirror is `github.com/sandbenders/rocinante`; no creative-coding project of either name was found (not exhaustive). `rocinante.dev`, `.org`, `.io`, `.run` and `roci.dev` resolve; `rocinante.art`, `.studio`, `.codes` and `roci.sh` did not. **Still to do by hand:** a trademark search for software classes (EUIPO, WIPO, USPTO) and a manual web search.
- **Dependency checks** (2026-10-24, from each project's own repository, releases and licence files):

  | Dependency | Licence | Latest release | Finding |
  |---|---|---|---|
  | SDL3 | Zlib | 3.4.18 (2026-10-02) | `vendor:sdl3` bindings are 3.4.2 (see above) |
  | SDL_ttf | Zlib | 3.2.2 (2025-03-31) | `TTF_CreateGPUTextEngine` exists since 3.0.0 and must run on the device's thread; the last release is 19 months old, though commits continue (2026-10-17) |
  | SDL_shadercross | Zlib | none (no tags or releases) | takes HLSL or SPIR-V; needs SPIRV-Cross (Apache-2.0) and, for DXIL, DXC (LLVM Release Licence, permissive) shipped beside it; DXBC needs vkd3d off Windows, which we don't need. No release means pinning a commit |
  | Dear ImGui | MIT | 1.93.0 (2026-10-14) | active |
  | dear_bindings | MIT | 0.26 for ImGui 1.93.0 (2026-10-18) | its tested list has SDL3 but not `imgui_impl_sdlgpu3`; Spike 4 verified it |
  | accesskit-c | Apache-2.0 or MIT (BSD parts from Chromium) | 0.23.1 (2026-09-26) | active; its README lists no platforms, so the release-workflow list in §4.8 stands as the source |
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

  Still unchecked: the platform lists of dav1d, libvpx and AccessKit's FreeBSD adapter (Phase 3 and 6), and every library's behaviour on iOS and Android.
- **Spike 1, desktop** (now `roci/platform` and `examples/window`): passed on macOS (Metal), FreeBSD 15.1 and CachyOS Linux (Vulkan, so GPU rendering works on FreeBSD even though SDL does not list it) and Windows 11 (Direct3D 12; Odin's `vendor/sdl3/SDL3.dll` must sit beside the program).
- **Spike 3, code generation** (`spikes/codegen`): passes on all four desktop systems; the interpreter and the generated Odin print identical output and both call the same `verbs` procedures. Generated code names variables after the sketch, comments each statement with its `.roci` line and declares every assigned name once at the top (how the §5.15 scope rule maps onto Odin); each record shape becomes a plain struct, a list a `[dynamic]` array and `for each` a `for &p in` loop (the layout §5.2 promises). Found: on Windows the generated program's `-out:` path must end in `.exe`, and without the Visual Studio C++ workload Odin stops with "VS library path not found" (Build Tools via `winget install --id Microsoft.VisualStudio.BuildTools` with the `Microsoft.VisualStudio.Workload.VCTools` workload; `doctor` finds them through `vswhere`).
- **Spike 4, UI** (`spikes/ui`; Dear ImGui v1.93.0, dear_bindings v0.26 and accesskit-c 0.23.1 built into `.cache/ui` by `setup.sh` and `setup-windows.sh`, nothing committed): dear_bindings generated the C API for `imgui.h` and for **both `imgui_impl_sdl3` and `imgui_impl_sdlgpu3`**; a slider, a button and a text box draw through them with keyboard navigation on all four desktop systems. accesskit-c builds from source (CMake and cargo); on macOS its adapter attaches to SDL's window and the tree is built from rocinante's own widget records. **Checked by hand (2026-10-26):** VoiceOver reads and drives the three widgets; IME composition works on macOS and with the Microsoft Japanese IME on Windows (Dear ImGui's default font has no Japanese glyphs until Phase 3 brings real fonts). Found: dear_bindings needs Python and `ply` only to generate (a throwaway virtual environment; Python stays out of the build until Phase 6); `imgui_demo.cpp` must be compiled because `dcimgui.cpp` wraps its functions; accesskit-c's enumerators are one byte wide and its struct layouts differ from a guess, so real bindings must be generated from `accesskit.h`; its SDL example is for SDL2, so SDL3 needs `SDL_PROP_WINDOW_COCOA_WINDOW_POINTER`; on Windows Odin links the static C runtime, so C++ libraries are built with `-MT` (and dear_bindings under Windows Python needs Windows paths, `cygpath -m`); Dear ImGui writes `imgui.ini` in the working folder (ignored by git). **Not verified:** the Windows (UI Automation), Linux and FreeBSD (AT-SPI) adapters, and IME on Linux and FreeBSD; FreeBSD's screen-reader support stays an open question (§4.8).
- **Spike 2, Android** (Pixel 9, Android 16, Mali-G715) drew a shader circle at 60 fps on Vulkan from an Odin shared library inside SDL's Java activity. Findings that shape the core and `roci package android`: SDL's Vulkan backend requires `shaderClipDistance` by default and the Mali reports it unsupported, so the core creates the device with `SDL_PROP_GPU_DEVICE_CREATE_FEATURE_CLIP_DISTANCE_BOOLEAN` off and shaders may not use clip distances (`adb shell cmd gpu vkjson` shows a phone's features); `vendor:sdl3` declares `SDL_main` as an import, so the core exports its own `rocinante_main` and the Java activity overrides `getMainFunction()` (worth offering upstream); Odin always links the NDK's `native_app_glue`, which needs an exported do-nothing `android_main`; on Apple Silicon `ODIN_ANDROID_NDK_TOOLCHAIN` must point at the NDK's `darwin-x86_64` toolchain, which Odin does not guess; a new debug key on each build makes the phone refuse the update (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`), so the key must be kept; `javac`, `d8` and `apksigner` need a JDK, which `roci` fetches (§4.7); the APK is assembled by hand with `aapt`, `zipalign` and `apksigner` because `odin bundle android` cannot add Java code; a locked or sleeping phone fails with `VK_ERROR_SURFACE_LOST_KHR` or draws nothing.
- **Spike 2, iOS** (iPhone 13 Pro, iOS 26.6.2, Xcode 27.1, a free Apple ID) drew the same circle at 60 fps on Metal (the shader goes SPIR-V to Metal through `spirv-cross`, which renames the entry point `main0`). No Xcode GUI: SDL as a static `libSDL3.a`, Odin builds the sketch with `-target:darwin_arm64 -subtarget:iphone -build-mode:lib`, `clang` links, a tiny generated Xcode project only wraps and signs it, `xcrun devicectl` installs and launches. Findings: Odin's own link step puts Homebrew's macOS `libSDL3.dylib` ahead of the iPhone library, so the core builds a static library and links separately; `codesign` refuses the bundle until extended attributes are stripped (`xattr -cr`); a free Apple ID's apps stay untrusted until the user taps Trust and the signature lasts 7 days; the phone needs Developer Mode, unlocked and trusted for the Mac; an iOS app does not quit itself, so the core runs until the system asks and offers no `quit` there; `sdl.RunApp(0, nil, main_func, nil)` starts UIKit and calls the sketch's main on SDL's thread.

**Phase 0 exit** (2026-10-27). Every criterion is met: both pipelines green (GitLab on ORION, Arch; GitHub on Ubuntu 24.04, pinned) from the same `main`, running `odin run build -- ci`; spikes 1 to 4 pass as above; the parity map was verified against the three references (2026-10-24); Odin is pinned with its target coverage and gaps recorded (§4.7); hosts and targets are decided (§7).

**Carried into later phases** (none blocked Phase 1): the text engine choice (§4.3, start of Phase 3: SDL3_ttf's GPU engine was not tried); `vendor:sdl3` or our own bindings (decide the first time a newer function is needed); the AccessKit adapters for Windows, Linux and FreeBSD and IME on Linux and FreeBSD (Phase 3; the spike's hand-declared bindings are replaced by generated ones); the trademark search; the unchecked dependency platform lists; and offers to make upstream (Odin's `for x in m[key]` crash on a missing key, `SDL_main` as an import in `vendor:sdl3`, the bindings gaps). `spikes/` is throwaway; the packages in §4.2 are created as phases need them.

### Phase 1: Window and 2D core (Odin API) (done 2026-10-27)
- App loop, `window` with optional position, multiple windows, HiDPI.
- A minimal text path for the error overlay and debug output (a built-in bitmap font), so Phase 2 can show errors before Phase 3 brings real text (§4.3).
- Internal shader pipeline: HLSL → SPIR-V, Metal and DXIL, committed (below).
- Command list, batching, instancing, geometry cache.
- 2D primitives, style, colour, gradients (§5.9), transforms, basic shapes (including the tessellation decision, §4.3), math, random, noise, mouse and keyboard.
- First version of the stable verb ABI (§4.7), with its C ABI, and the verb registry it is generated with.
- Commands that describe themselves, lazy pipeline creation with a fallback, one seed per run with the single random and noise implementation (§4.7).
- Headless rendering and the golden-image harness (render offscreen, compare against reference PNGs with tolerance), which Phase 2 exposes as `roci run --frames`.
- Mobile: the Phase 1 examples running on an iOS device and an Android device.
- **Demo sketch**: `examples/garden`: a palette window sends tagged messages to a garden window with a gradient sky, noise-twinkling stars, a moon with radial and conic gradients, rainbow arcs, a quad hill, grass in a noise wind, flowers of turned gradient petals, a firefly on the mouse, clicks that plant and keys that calm and clear.
- **Exit**: `examples/circle.odin` and a 100,000-circle benchmark at 60 fps on every desktop at hand, with invictus (Xeon X5675 from 2010, the slowest computer at hand, standing in for a mid-range laptop) accepted at 57.8 (§10); drawing at a pixel density above 1 checked through the system's display scaling; two windows exchanging a message; runs on iOS and Android at 60.2 and 60.0 fps (2026-10-27).

**Phase 1 results** (all 2026-10-27; run-by-run detail is in git history):

- **Shaders:** SDL_shadercross has no tags or releases and is pinned at `1ff05bec573988a98ef9e0260b4da44f512b8367` in `SHADERCROSS_COMMIT`; its HLSL path needs DXC, which Microsoft ships only for Windows and x86-64 Linux, so on a Mac `shaders/compile.sh` runs the same steps by hand (HLSL to SPIR-V with glslang, SPIR-V to Metal with SPIRV-Cross) and `shaders/compile-dxil.sh` makes DXIL with `dxc` on Windows; both write the committed `shaders/compiled/`. Used only as build tools, so nothing is shipped. Its own `AGENTS.md` forbids AI-generated contributions (§3).
- **PNG output:** Odin's `core:image/png` only reads PNG, so the golden harness writes it with a small writer of our own (CRC-32 and Adler-32 from `core:hash`; at first in stored deflate blocks, compressed since 2026-10-29, which took the references from 14 MB to 400 KB), tested by reading its files back. `@(export, link_name = "...")` on a `proc "c"` works for the C ABI (the Odin overview does not say so; Spike 2's `rocinante_main` shows it).
- **API and C ABI:** `examples/circle`, `two_windows`, `garden` and the C example (`tools/abi-check.sh --run`, `-Wall -Wextra -Werror`) run with no errors on every desktop. The ABI check's first run found a real clash (a typedef and a function both named `roci_window`) and a missing Odin verb (`mix` of numbers).
- **Benchmark** (`examples/benchmark`, 100,000 circles a frame through the public API, `-o:speed`): the work counts are exact and tested everywhere (one draw, 100,000 instances, no allocations after the first frame). Frames a second in a window, before and after the speed-ups: Apple M4 Pro (Metal) 60.3 vsync, 123 uncapped; i7-9800X with an RTX 2080 Ti 63.5 on Windows (D3D12) and 64.7 then 116 on CachyOS (Vulkan); invictus (RX 580, Vulkan) 36.7 then 57.8 (17.3 ms against 16.6, accepted for a processor from 2010). The frame is bound by one CPU core on every x86 computer measured. The speed-ups, found with `perf`: the batch hash works out each style and transform once and hashes a whole word at a time (eight multiplies a value cost 11.7 ms headless against 5.6); `finite` checks numbers without branches; `sin` and `cos` use our own kernel; commands are 64 bytes with their looks stored once (184 bytes a command made memory traffic a third of the frame on invictus). SDL's GPU debug mode cost about 0.3 ms a frame and is off by default.
- **Renderer and golden images:** the nineteen golden scenes draw correctly on Metal, Vulkan (NVIDIA, RADV, lavapipe) and Direct3D 12. Against Metal references the other drivers differ only on smoothed edges, and two different Vulkan drivers agreed, so the references were remade on lavapipe and the full `ci` compares lavapipe with lavapipe (exact there, NVIDIA within two steps of a channel). DXIL was made on Windows with the SDK's `dxc` 1.9.2602. Miter is the default join and round the default cap, as in Processing; multisampling replaced a hand-built edge fringe (§4.3).
- **Platform:** runs on macOS, FreeBSD, Windows 11 and CachyOS Linux (niri on Wayland) with no errors. **Higher density** (standing in for a Retina display, §10) was checked with niri at scale 2 and `SDL_VIDEO_DRIVER=wayland`: density 2, everything sharp. SDL 3.4.18 does not use Wayland on niri by default (no `fifo-v1` protocol, so it falls back to XWayland), where a scaled display reports density 1; since 2026-10-29 rocinante asks for Wayland first (§10).
- **Mobile:** `spikes/mobile/sketch` runs through the public API on a Pixel 9 (all three pipelines, touch moves the circle) and an iPhone 13 Pro (Metal validation on, no errors). SDL on Android counts window sizes in device pixels, so `roci/platform` divides by the content scale there only. An older or lower-end phone moved to Phase 8 (§10).

### Phase 2: The language
- Lexer, parser, checker, type inference, typed IR, interpreter (§4.7, §5).
- Inference error messages written before the inference rules are final (§5.3).
- `circle at 100 100 radius 50` as a whole program.
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
- The typed IR carries what Phase 7's optimisation passes need (§4.7): each block's call site and captures, record shapes per creation site, lists changed inside loops, and whether a value leaves its frame. The interpreter uses them through the shared optimisation passes (§4.7); with the passes off it ignores them, and that run is the reference the others are compared with.
- **Where it stands** (2026-10-29): done are the front end, interpreter, `roci run` and `roci check` and `roci fmt` and `roci man`, sketch folders, several files and libraries with `roci get` and `roci update`, list verbs, events, `every`, window messaging, window settings and `set`, `pressed`, `held`, the rounding verbs, the 2D turtle (`examples/tree`), 2D collision with its broad phase (`examples/bricks`), `tween` and `ease` (`examples/ease`), tables, the window `cursor`, mouse buttons by name with the wheel (`examples/mouse`), and touch (`examples/touch`). Every feature so far has an example: `rays` (`cast`, `inside`, mixed shapes), `sorting` (the list verbs), `tally` (tables), `style` (mixing, stops, joins, caps, named styles, `with`, `oklch`, `shear`), `landscape` (`fbm`, `gaussian`, simplex noise, `every … frames`, `while`) and `windows` (`set`, window properties, `on resize`, `on move`, `on focus`, `on mouse up`) joined the earlier ones on 2026-10-29. Every Phase 1 example is now also written in rocinante (`shapes` and `benchmark` joined on 2026-10-29); `examples/window` stays Odin only, because it tests `roci/platform` itself (raw events, the N, F and V keys), and the language's window settings have `examples/windows`. **The interpreter's speed** (2026-10-29, i7-9800X, RTX 2080 Ti, CachyOS, `roci` built `-o:speed`): `examples/benchmark/sketch.roci` draws its 100,000 circles at 9.7 frames a second, about 100 ms a frame, against 98 frames a second (vsync at 100 Hz, a 3.7 ms draw block) for `main.odin`: roughly 1 µs a loop turn of five statements, 27 times the Odin time. Profiled the same day (`perf`, flat): a fifth of the time went to comparing verb names and a tenth to the map of sketch-wide names and to allocating argument arrays; with verb codes, slots and arguments on the stack a headless frame went from 101 to 61 ms (13 to 14 frames a second in a window). What is left is the tree walk itself (`eval`, nearly half) and real drawing work, so going further means changing how values or nodes are represented, which waits for the benchmark sketches to ask for it (2026-10-27). Later the same day: a copying collector for the sketch's values fixed a memory leak (below, in the code map), calls without style words stopped building a 776-byte look, and the shared optimisation passes (§4.7) gave numbers and conditions a typed path; a headless frame went to 33 ms (53 ms with `ROCI_PASSES=off`; `hyperfine`, five runs, start-up subtracted). What the profile shows now: the typed number path (30%), `sin` and `cos` (17%), drawing (14%), and finding loop names and locals by searching the frame (8%), which numbered frame slots from the checker would remove. The second benchmark, `examples/particles` (10,000 records moved by a taught verb, filtered with `keep` and topped up every frame), runs at 10.6 ms a frame headless and about 60 frames a second in a window; its largest cost outside the walk is finding fields by name (`field_index`, `read_field`, `assign_path`, about 15%), which numbered field indices from the checker would remove. Interpretation speed is closed for Phase 2 (2026-10-29): both figures leave room for working sketches, and released sketches are compiled. Phase 7 compares the compiled sketch with these figures. Open: running the newcomer test; everything for it is in `tests/newcomer/` (`README.md` is the protocol, decided 2026-10-30) (every example has its golden reference picture, drawn on lavapipe 2026-10-29; a headless run has the mouse at 0, 0, so the mouse-following circles sit in the corner). Checked by hand on 2026-10-29: the examples run on Windows, FreeBSD and Linux, and `roci get` works against a real repository. Hand runs still to do on Linux and Windows (checked on macOS only): a change to a second file or a library while a sketch runs, `set` on a window (resizing, fullscreen, moving), the wind bar and the space bar in `examples/garden`, and `roci update` against a real repository. On every system: playing `examples/bricks` with the mouse, `examples/mouse` with a mouse that has side buttons and a wheel, the keys of `examples/windows` (its settings are only requests on Wayland), and `examples/touch` on a touch screen (with the mouse standing in for a finger it works on niri, checked 2026-10-29). Touch on the Pixel 9 was checked through the phone spike, which draws `roci.touches()` (2026-10-29, built on CachyOS with SDK and NDK 29.0.14206865 in `~/Android/Sdk` and SDL 3.4.18 built for Android in `.cache/sdl-android`): four fingers at once in the right places at 60.2 fps, numbered in order and never reused, the count back to 0 when they lift, and a finger moving the mouse. The iPhone is still to do (both have only run headless, under tests that send them events, and in a window for a few seconds on Linux).
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
- Libraries: multi-file sketches behave identically to the same code in one file; `use` with index names and git URLs; offline runs from vendored `libs/`; every clash rule produces its error message.
- Versions: `sketch.toml` read and written (missing file, hand-edited invalid values), each version scheme checked against every target's limit, and the build number never decreasing (§4.9).
- Toolchain: `roci doctor` tested on machines (or CI images) with each toolchain piece missing, wrong version and present. For every host and target pair, `roci doctor` and `roci package` give the "cannot be built on this computer" message exactly when §7's table says so.
- Performance: benchmark sketches tracked in both modes. Timing is gated only on ORION, whose hardware is fixed (lavapipe and shared GitHub runners are too noisy); elsewhere the pipeline compares work counts (draw calls, batches, allocations), which are exact. A timing regression of more than 10% on ORION fails the build.
- Platforms: Linux in the pipeline on every commit to `main`; every other target through the release checklist before each tag, and at least once per phase (§11).
- Golden images run on Mesa's software Vulkan driver (lavapipe) in the pipeline, so results don't depend on the machine's GPU. `tests/golden` draws every scene in `scenes.odin` offscreen through the real renderer at 2x and compares with the reference picture (a few pixels of difference allowed, `TOLERANCE` per channel); it is a program rather than `odin test` because SDL's video system must start on a Mac's main thread. The full `ci` runs it on lavapipe (`build/golden.odin`), and the references are drawn there: on a Linux computer with a GPU, `VK_DRIVER_FILES=/usr/share/vulkan/icd.d/lvp_icd.json SDL_VIDEODRIVER=offscreen odin run tests/golden -- update` makes them (Arch's package is `vulkan-swrast`), and `VK_LOADER_DEBUG=driver` shows which driver was used.

---

## 10. Decisions and open questions

### Decided

- **2026-10-22, Licence: Zero-Clause BSD (SPDX `0BSD`).** The most permissive OSI-approved licence: an unconditional grant to use, copy, modify and distribute for any purpose, plus a warranty disclaimer, with no attribution requirement. Applies to the core, the language, `roci`, the docs and all examples. Dependency rules are in §3.
- **2026-10-22, Blocks: `[ ]`**, as in Logo. Not `end`.
- **2026-10-22, Paradigm: procedural and data-oriented**, verbs on plain data, no objects; Odin-inspired array programming, verb groups, useful zero values, no exceptions, implicit style context; capturing blocks and a light functional layer for lists. Full text in §5.2.
- **2026-10-22, Typing: inferred static typing**, no type syntax for users, plain-language conflict errors, boxed fallback where inference cannot decide. Full text in §5.3.
- **2026-10-23, Implementation language: Odin** (replaces Rust). Core and `roci` in Odin; `vendor:` libraries first, our own bindings to the latest upstream when they lag; C and C++ libraries through Odin's foreign system; fixes contributed upstream. Full text in §3 and §4.
- **2026-10-23, Execution: interpreted in development, compiled ahead of time for release by generating Odin source** built with the pinned Odin compiler that `roci` fetches (replaces the Cranelift plan). One shared front end and typed IR; no bytecode VM, no JIT. Full text in §4.7.
- **2026-10-23, Toolchain for packaging is user-installed, except Odin** (revised 2026-10-24: `roci` fetches the pinned Odin into its own cache, checks its checksum, and on FreeBSD builds it from source; revised 2026-10-25: Android also needs a JDK, fetched the same way; revised 2026-10-30: on FreeBSD the system's `odin-lang` package comes first when it is the pinned version): MSVC on Windows, Xcode on Apple platforms, clang on Linux and FreeBSD; `roci doctor` guides installation; `roci run` needs none of it. Android SDK, NDK and JDK are managed by `roci`. Full text in §4.7; non-negotiable 2.
- **2026-10-23, UI is first class**: immediate-mode widget verbs in `ui [ ]` blocks, values remembered per sketch, keyboard, touch, IME and screen-reader support. Full text in §4.8 and §5.8; non-negotiable 10.
- **2026-10-23, UI engine: Dear ImGui** (replaces egui) with its official SDL3 and SDL_GPU backends, Odin bindings generated through dear_bindings. Full text in §4.8.
- **2026-10-23, Screen readers are required for the first stable release**, through our own AccessKit bridge for Dear ImGui built from rocinante's widget records, using accesskit-c. Full text in §4.8.
- **2026-10-23, Audio stack without Rust**: miniaudio decoders plus `stb_vorbis`, our own DSP and OSC, `vendor:portmidi` as the MIDI candidate. This also removes the MPL-2.0 dependency (Symphonia). Full text in §4.6.
- **2026-10-23, Name**: always lowercase, rocinante (§3).
- **2026-10-23, Indentation: free, never meaningful**; `roci fmt` keeps sketches tidy and the checker uses indentation only to explain bracket mistakes. Full text in §5.1.
- **2026-10-23, Style: one vocabulary at three levels** (sticky style verbs, per-element style words, `with [ ]` groups) plus named styles as records; `thickness` for stroke width. Full text in §5.9.
- **2026-10-23, Colour range: 0–255 for every channel** (grey, `rgb`, `hsb`); `oklch` alone follows its CSS notation. **Alpha is a percentage, 0 to 100** (2026-10-29), in the language only (the Odin API and the C ABI keep 0–255). Full text in §5.9.
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
- **2026-10-24, Collision detection built in**: shapes as records, `touching`, `contact`, `hits`, `inside`, `cast`; Box2D v3 collision functions for 2D, our own Odin tests for 3D. Full text in §5.13. (revised 2026-10-29: detection is our own Odin, package `roci/collide`, and Box2D comes in with physics in Phase 6, because `vendor:box2d` lags, has no Linux, FreeBSD or phone libraries, is 32-bit and takes only small convex polygons; §5.13)
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
- **2026-10-24, `roci` fetches the pinned Odin** into its own cache, and on FreeBSD, where Odin has no official archive, builds it from the source tag (revised 2026-10-30: FreeBSD's own `odin-lang` package is used when its version is the pin, which it was that day, and the source build only when it is not). Full text in §4.7.
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
- **2026-10-27, Vector tessellation is our own**: package geom flattens curves, cuts outlines with holes into triangles by ear clipping and strokes with caps and joins, in Odin with no library; basic shapes stay on the signed-distance shader and frames are drawn 4x multisampled. Full text in §4.3 (this closes the tessellation item of open question 3).
- **2026-10-27, GPU debug mode is off by default**: SDL turns its debug mode (validation) on unless told otherwise, which cost every sketch about 0.3 ms a frame on the i7-9800X with one draw; rocinante turns it off, and `ROCI_GPU_DEBUG=1` turns it back on for working on rocinante. Full text in the `roci/platform` entry of the code map.
- **2026-10-28, Labels for geometry, no commas between arguments**: `circle at 100 100 radius 50` is the smallest program; geometry verbs are written with labels (any order, one canonical order for `roci fmt`), calls take no commas, `window` takes `size`, `at` and `title`, `title w "t"` names its window, and a record field on its own line needs no comma. Full text and the evidence in §5.1.
- **2026-10-28, Window settings are connecting words of `window` and properties, not a verb each** (revised 2026-10-29: changed later with `set`, not by assigning): `window size 300 200 resizable false bordered false topmost true smallest 100 50 largest 800 600 ratio 1.5 alpha 80 focusable false visible false fullscreen false grab true parent main modal true`, and each is a property that is read as a field (`w.width`) and changed with `set`, which takes the same words (`set control resizable false`, `set main_window width 400`, `set w maximized true`, `set w focused true` brings it to the front); assigning one (`w.width = 400`) is a teaching error that shows the `set` line, `title` takes no window (`set w title "t"`), and `mouse`, `hovered` and `covered` are read-only (`registry.WINDOW_PROPERTIES`, `roci man window`). A verb for each setting (`resizable w false`, `show w`, `hide w`, `ratio w 1.5`) was written first and dropped, because every verb takes a word from the sketch writer (`show`, `ratio`, `parent` and `visible` are ordinary names), and `set` is one new word for all of them, as the dot assignment was first chosen to avoid (revised 2026-10-29, because the dot made a window look like a record and `set` reuses the words of `window`; the rule for any handle is in §5.2). The words only a window uses (`WINDOW_FREE_WORDS`) stay free as names, and the parser reads one as a connecting word only where a window call is due one.
- **2026-10-28, Comments are `//`, and `#` is only a colour**: the old rule (a hash is a colour when 3, 4, 6 or 8 hex digits follow, otherwise a comment) made every tool repeat it, and an editor could not tell `x = #a9b8f2` from `x = # a9b8f2`. A `#` that is not a colour is a teaching error that shows the line with `//`; every example, test and document was migrated. Full text in §5.1.
- **2026-10-27, Set-up verbs act on the newest window**: outside any block, verbs act on the window the last `window` call made, not on the first window, so `w = window 800 600` then `title "garden"` names `w`, as a sketch reads (since 2026-10-28 a title is better given in the call, `window size 800 600 title "garden"`, or to a named window, `set w title "garden"`; the rule for set-up drawing stays). Found by `examples/garden`, whose second title landed on the first window (and `examples/two_windows` had the same fault). Full text in the `roci` entry of the code map.
- **2026-10-27, Phase 1 exit stand-ins** for hardware not at hand. The benchmark's "mid-range laptop" is replaced by invictus (Xeon X5675 from 2010): every x86 computer measured is bound by the CPU on one core, which is slower there than on any current mid-range laptop, so 60 fps on invictus implies it on such a laptop; the laptop run itself goes to the release checklist. Revised the same day: after the speed-ups invictus reached 57.8 fps in a window (17.3 ms against 16.6), and that is accepted for a processor from 2010 rather than shrinking the GPU instance, which would change the shaders on every system for the last 0.7 ms; the other desktops hold 60 with room to spare. High pixel density is checked through each system's display scaling (Windows at 200%, a scaled HiDPI mode on macOS, a Wayland output scale of 2), which takes the same code path as a Retina panel. A second, lower-end phone is not a Phase 1 exit criterion and moves to Phase 8; frame rates are measured on the Pixel 9 and the iPhone 13 Pro. Full text in §8.
- **2026-10-29, The turtle starts in the middle facing up, draws in black while the stroke is off, and resets each frame like the style**, with `push [ ]` saving it and `home` going back without drawing. Full text in §5.6.
- **2026-10-29, The mouse cursor is a window setting**: `cursor` is a word of `window` and `set` and a property (`window size 480 360 cursor none`, `set w cursor arrow`, `w.cursor`), taking a name: `arrow` (the default) and `none` now, more shapes later (`roci.Cursor`). SDL has one cursor for the whole program, so each frame it takes the setting of the window the mouse is over (`apply_cursor`). Verbs (`no cursor`, as in Processing) and a true-or-false setting were the other choices.
- **2026-10-29, Word arguments are checked against their words**: every argument that takes a word (`caps`, `joins`, `as`, `in`, `cursor`) has a fixed list in `registry.WORD_CHOICES`, and any other word is a load-time error that lists them and suggests the nearest (`centre` gives `center`), where before it was silently ignored.
- **2026-10-29, Tweens are a statement and `ease` a verb**: `tween place to value over seconds as curve` moves a sketch-wide name or a field over time, and `ease amount as curve` is the curve alone; a tween value remembered per call site was the other choice. Full text in §5.15.
- **2026-10-29, Mouse buttons are words, the wheel a value**: `on mouse down right`, `held "mouse right"`, `wheel`. Full text in §5.15.
- **2026-10-29, A vector and two numbers mix in one geometry call**: `rect at p size 80 40` and `line from mouse to 10 20` draw what the all-numbers call draws; the checker turns the two numbers into the vector of the shape's vector form, so each value is worked out once. Found writing `examples/windows`. Full text in §5.1.
- **2026-10-29, Touch is two events, a value and a list**: `on touch down` and `on touch up`, with `finger` the finger inside them (only there; a teaching error elsewhere, and a taught verb is passed it); `touches` the fingers down now, each a record of `id`, `pos`, `start` and `pressure`; mouse and fingers stand in for each other both ways. Naming the finger in the event (`on touch down f`) and a single `on touch` with only `touches` were the other choices. Full text in §5.15.
- **2026-10-30, The documentation is a site built from the repository**: published on GitHub Pages from the mirror (`sandbenders.github.io/rocinante` until there is a domain), built by Hugo with a theme of our own, fed by `tools/site`, which writes the reference from the registry with an example and its picture for every word, the messages from the catalogue's tests and the guides with code coloured by rocinante's own lexer; the GitHub Wiki was the other choice, and was turned down because it is unreviewed, not tied to a release and copied by hand from the registry. The alpha has the full reference and twelve guides. Hugo (Apache-2.0, all four desktop hosts) is a build tool, never shipped. The structure follows Processing's reference (an index by topic; each entry with an example and its picture, its forms, what it gives, related words) and the guides of openFrameworks and Cinder.
- **2026-10-30, How the newcomer test runs**: eight people, four per group, in each group two who have never programmed and two with a little experience; group A reads three sketches with one thing per argument and group B the same sketches in bare Logo nesting (a test keeps B equal to A without its round brackets), then everyone builds in the real `roci run`, because bare nesting is an error in rocinante; in person, one at a time, thinking aloud, recorded only with consent, in English. Building in two styles, or a hidden mode that accepts bare nesting, were the other choices. The protocol is `tests/newcomer/README.md`.
- **2026-10-29, The optimisation passes are shared by both back ends**: they run over the typed IR after the checker, the interpreter runs the result, and `codegen` will generate Odin from it; each pass can be switched off, and the interpreter with every pass off is the reference, compared frame by frame with the passes on for every example. Proposed by an independent review of the interpreter's speed. Full text in §4.7.
- **2026-10-29, Tables, not maps** (closes the old open question 9): `counts = table`, `put counts "cat" 3`, `get counts "cat"`, `keys counts`, `count counts`, `remove "cat" from counts`; text names, one kind of value, insertion order. Full text in §5.15. Found on the way: `add` and `remove` let a constant list change, against §5.1; they, and `put`, now refuse it.
- **2026-10-27, No `wait` in the first stable release**: `every`, timers and tweens cover the cases. A suspending verb needs fibers or a state-machine transform in compiled code, which puts non-negotiable 7 at risk. A loop that never ends stays a teaching error (§5.15), and `wait` can come later without breaking sketches.
- **2026-10-27, The interpreter walks the typed IR** (§4.7, §5.14), with no bytecode VM. It is revisited only if the benchmark sketches show it is too slow, and the candidate is then a register bytecode on Odin's `#must_tail` with the `"preserve/none"` calling convention (Odin newsletter 2026 Q1, §12; check its docs first), benchmarked against a switch fallback on every Odin upgrade.
- **2026-10-27, `roci explain` is postponed to Phase 9** (name provisional): it describes a line or block in plain words from the typed IR, for learners and for tools. No work is done for it now; the typed IR stays rich enough to support it.
- **2026-10-23, Sharing: numbers, vectors, colours and text are copied; lists and records are shared**; `copy` makes an independent copy. Full text in §5.11.

- **2026-10-29, Wayland first on a Wayland desktop** (closes the old open question 7): on Linux and FreeBSD, when `WAYLAND_DISPLAY` is set and the user has not set `SDL_VIDEO_DRIVER`, rocinante asks SDL for `wayland,x11` before it starts (`platform.video_driver_hint`). SDL 3.4 otherwise falls back to XWayland on compositors without the `fifo-v1` protocol, and on niri 26.04 through `xwayland-satellite` that lost window settings: `examples/bricks` (480 by 360, `resizable false`) opened floating at 1701 by 1382, and at exactly 480 by 360 on Wayland; scaled displays also drew at density 1 (Phase 1 results). The cost SDL warns about was measured on the i7-9800X and RTX 2080 Ti at 100 Hz: the 100,000-circle benchmark ran at 95 frames a second on Wayland against 100.6 through XWayland, and 1,000 circles at full rate either way. Windows cannot place themselves on Wayland, so `at` stays a request there. **Mango on invictus (FreeBSD 15.1)** was not an X11 problem: SDL was on Wayland there, but a window is made resizable and `resizable false` comes after, and mango answers the new window with a configure of its own size (1495 by 1022, no states, from `no_size_hint`); SDL pinned whatever size the window had when it was fixed. `roci.set_resizable` now sets the window back to its own size before fixing it (checked with `WAYLAND_DEBUG=1`: mango configures 480 by 360). This is a hand-checked path, since headless windows have no SDL handle.

### Later

Ideas that are wanted but not planned for the first stable release live in the Roadmap section of `README.md`, so contributors can see them. When one is taken up, it moves here and into §8.

### Open

Decide these with Fabrizio; move each to "Decided" with the date.

1. Machine learning on FreeBSD: LiteRT's C runtime built there, or ONNX Runtime as the FreeBSD fallback (§4.10). Settled by the LiteRT spike at the start of Phase 6.
2. ExecuTorch as a second runtime for PyTorch's own `.pte` files, so PyTorch models skip conversion. It is C++ only, so it would need our own C wrapper, and a second runtime is a second behaviour to keep equal (§4.10).
3. Choices inherited from the sections they point to: text engine (§4.3, start of Phase 3); AIFF, Opus and AAC decoding (§4.6, Phase 5); MIDI on FreeBSD, iOS and Android (§4.6, Phase 5); mobile multi-window behaviour (§4.5, Phase 8); video encoder libraries (§4.11, Phase 6); the Git LFS type list (§4.9, Phase 2); the name of `roci check --why-slow` (§5.3, Phase 2); Box3D for 3D collision (§5.13, Phase 4); AccessKit on FreeBSD (§4.8, Phase 3).
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
