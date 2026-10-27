# design.md: rocinante

The architecture details (§4.3 to §4.11), the language (§5) and the feature parity map (§6). It is imported by `CLAUDE.md`; together the two files are the single source of truth. Section numbers are global, so `§5.9` means section 5.9 of this file and `§8` means section 8 of `CLAUDE.md`. When a decision changes, update the file that holds the section, in place.

---

### 4.3 Rendering model

- Immediate-mode verbs (`circle`, `line`, `box`) append to a per-window **command list**. The renderer turns the command list into batched, instanced GPU draws at the end of the frame. Users never see this.
- **Commands describe themselves** (decided 2026-10-27). Each command-list entry keeps its kind, position, size and colour, plus a slot for the `.roci` source span (empty until Phase 2 fills it). Work-count benchmarks (§9), scene descriptions for screen readers (§4.8) and error and highlight locations all read the same records, so they cannot drift from what is drawn.
- **GPU features load lazily** (decided 2026-10-27). Pipelines and shaders are created on first use, and one that fails to build falls back without taking the window down (non-negotiable 3). Shader code that a sketch never uses must never stop it from running on an old GPU (L5 failed this way on a 2009 laptop).
- Geometry that does not change between frames is detected (hash of command + parameters) and cached on the GPU automatically.
- 2D and 3D share one window. A window has a default 2D orthographic projection; using any 3D verb (`box`, `camera`, `light`) switches that draw block to a perspective camera with sensible defaults, including mouse orbit, unless the user sets a camera.
- **SDL3**: Odin's `vendor:sdl3`, `vendor:sdl3/ttf` and `vendor:sdl3/image` exist; use them when current, otherwise our own bindings for the latest SDL3 release (§3).
- **Shaders**: internal shaders are written once in HLSL and compiled offline with SDL_shadercross to SPIR-V, MSL and DXIL, then embedded in the binary. SDL_shadercross takes SPIR-V or HLSL as input and outputs DXBC, DXIL, SPIR-V, MSL or HLSL, and offers both runtime translation and an offline command-line tool. **User-written shaders are HLSL too** (decided 2026-10-24): one shader language for the core and for users. `roci run` translates them at run time through SDL_shadercross, so editing a shader hot-reloads it; `roci package` compiles them offline like the internal ones. A small rocinante shader dialect that compiles to HLSL is on the roadmap (README.md). **Pinned and offline** (decided 2026-10-27): SDL_shadercross has no tags or releases, so the commit that compiles our shaders is pinned in the `SHADERCROSS_COMMIT` file, like `ODIN_VERSION`. Its CLI takes `--source HLSL`, `--dest SPIRV|MSL|DXIL`, `--stage`, `--entrypoint` and `--output` (read from `src/cli.c`). The compiled outputs are committed, so contributors need none of this unless they change a shader, and nothing from shadercross, SPIRV-Cross (Apache-2.0) or DXC (LLVM Release Licence, an NCSA-style licence) is shipped, which keeps all three inside §3 as build tools. Use the CLI's `--msl-version` flag, because it defaults to MSL 1.2.0. **In practice** (decided 2026-10-27): DXC has no macOS build, so on a Mac `shaders/compile.sh` runs shadercross's own steps by hand (HLSL to SPIR-V with glslang, SPIR-V to Metal with SPIRV-Cross), and `shaders/compile-dxil.sh` makes DXIL with `dxc` on Windows; shadercross itself is for computers where DXC exists, and the outputs are committed either way.
- **Text**: SDL3_ttf's GPU text engine (`TTF_CreateGPUTextEngine`, available since SDL_ttf 3.0.0) is the first candidate. Verify shaping, fallback fonts and atlas behaviour before committing.
- **Vector tessellation** (paths, thick strokes, curves): our own Odin implementation (decided 2026-10-27), package geom: flattening, ear clipping with holes and a stroker with caps and joins. Basic shapes stay on the signed-distance shader; what it cannot draw exactly as styled (quads, arcs, mitred or bevelled corners, butt or square ends) is cut into triangles on the CPU, and the frame is drawn multisampled (4x where the GPU can) so mesh edges are smooth, which avoids building an edge fringe by hand.
- **Math**: Odin's built-in array programming, swizzles, matrices and quaternions, plus `core:math/linalg`. No external maths library.

### 4.4 Threads

Users never see threads. The core decides: rendering and windowing stay where SDL requires them (check SDL3 documentation for thread rules per subsystem; `TTF_CreateGPUTextEngine`, for example, must be called on the thread that created the GPU device). Audio runs on its own real-time thread. Asset loading is asynchronous inside `draw` and event blocks (decided 2026-10-24): a sketch using an image before it has loaded draws nothing for that frame rather than blocking. A `load` at the top level of a sketch waits until the file is ready, as Processing's `loadImage` does, so `photo.width` is never 0 in setup code. A file that fails to load yields an empty value (§5.2) in both cases. Machine-learning inference runs on worker threads the same way: a sketch reads the latest finished result and never waits for a model (§4.10). Odin's implicit `context` (allocator, logger) is set up per thread by the core.

### 4.5 Multi-window and messaging

- `window w h` and `window w h at x y` return a window handle.
- Each window has its own `draw [ ... ]` block and command list.
- Windows communicate with `send <window> <value>` and `on <window> receive <name> [ ... ]`. Messages are values (numbers, text, lists, records), delivered on the next frame. Internally: channels, no shared mutable state exposed.
- On mobile, multiple windows become stacked or tabbed views. Decide the exact behaviour in Phase 8 and document it here.

### 4.6 Audio

- Device I/O through SDL3 audio, so one platform layer covers every target. Verify SDL3's audio backend on FreeBSD early.
- Decoding: miniaudio (public domain or MIT-0; in Odin's `vendor:`) has built-in decoders for WAV, FLAC and MP3. Vorbis comes from `stb_vorbis` (also in `vendor:`). AIFF, Opus and AAC: decide in Phase 5 (permissive C libraries or platform APIs).
- Synthesis and DSP: our own Odin DSP library (oscillators, filters, envelopes, effects, FFT), with simple user verbs. Bind a permissive C library only if writing our own proves unreasonable.
- MIDI: candidate `vendor:portmidi` (MIT-style licence, verified 2026-10-24). Its README names Linux (ALSA), a minimal sndio mode for FreeBSD, OpenBSD and NetBSD, Haiku, and says nothing of iOS or Android, so mobile needs our own backends (CoreMIDI on iOS, Android's MIDI API), and FreeBSD's sndio mode lacks timestamped output and virtual devices. Verify its FreeBSD, iOS and Android support before Phase 5; fill gaps with our own backends if needed.
- OSC: our own Odin implementation (OSC is a small protocol).

### 4.7 Execution model (decided 2026-10-22, revised 2026-10-23)

**One front end, two back ends.**

- **Front end (shared).** Lexer, parser, checker and type inference produce a **typed IR**. All errors users see come from here, so they are identical in both modes.
- **Development back end: interpreter.** `roci run` executes the typed IR directly. It owns hot reload, state preservation across saves and the error overlay. It is part of the `roci` binary and needs no toolchain. The core is linked into `roci`, so `roci run` works on a machine with nothing else installed.
- **Release back end: Odin code generation.** `roci package` translates the typed IR into Odin source and builds it, together with the core's Odin source (the core ships as Odin source and is compiled with every sketch, decided 2026-10-24; C and C++ dependencies such as SDL3, Dear ImGui, accesskit-c and LiteRT ship prebuilt per target), using the user's installed Odin compiler (LLVM-based, so the whole program is optimised together), for the chosen target. Odin's Android and iOS subtargets cover mobile. No interpreter ships in released sketches. Generated Odin must be readable: one Odin procedure per verb, names derived from the sketch.
- **Toolchain for packaging only** (decided 2026-10-23, revised 2026-10-24). rocinante does not bundle compilers or linkers. `roci package` needs:
  - **Odin**, at the version pinned by this rocinante release (`ODIN_VERSION`, §3), which `roci` fetches into its own cache on first use, like the Android SDK. It downloads the official release archive from Odin's GitHub releases, checks its checksum and never touches an Odin the user installed. Odin is BSD-3-Clause, so fetching it is within §3. Odin publishes no FreeBSD build, so on FreeBSD `roci` builds the pinned release from Odin's source tag into its cache (decided 2026-10-24), the way Odin's install guide describes for Unix: clone the tag, then `make release-native` (FreeBSD's own `make` is not GNU make, so `gmake` is likely needed; to be confirmed on the first build). That needs git, GNU make, clang and a supported LLVM (17 to 22, with `llvm-config` on the path), all from the ports tree, and `roci doctor` checks for them and prints the `pkg install` line. The build happens once per Odin version on the user's own machine, and the result is cached. The `lang/odin` port is not used by `roci`, because its version lags the pin; The `dev-2026-10` release (checked 2026-10-24) ships archives for Linux amd64 and arm64, macOS arm64 and Windows amd64 only: no FreeBSD, no Windows arm64, and macOS Intel was dropped in that release (`dev-2026-09` still had it). FreeBSD is handled by the source build above. Windows arm64 and macOS Intel are not targets of the first stable release (decided 2026-10-26, §10); they are on the roadmap with arm64 FreeBSD and Linux (README.md). A user-installed Odin of the pinned version is used when it is on the path and the cache is empty, and `roci doctor` says which one is in use;
  - **Windows**: MSVC and the Windows SDK from Visual Studio's "Desktop development with C++" component, which Odin requires;
  - **macOS**: the Xcode command-line tools; **iOS**: full Xcode and an Apple Developer Program account, on a Mac only (§7);
  - **Linux and FreeBSD**: clang, which Odin uses for linking;
  - **Android** (decided 2026-10-25): the SDK, the NDK and a JDK, which `roci` fetches into its cache on first use (§7), like Odin. The JDK is only a build tool, for `javac`, `d8` and `apksigner` (the Android spike, §8), and nothing from it ships in a sketch, so its GPL-with-Classpath-Exception licence (Eclipse Temurin; to be confirmed against its licence file when it is first used) is within §3. Temurin 21 (LTS) has builds for Linux x64 and arm64, macOS x64 and arm64 and Windows x64 and arm64 (checked 2026-10-25). Google's NDK has hosts for Windows, macOS and Linux x86-64 only, so **`roci package android` runs on those three hosts, not on FreeBSD or arm64 Linux**; on those, `roci doctor` says so and suggests packaging on another machine.
  `roci doctor` checks all of this per target and prints the exact install steps for the user's OS. Packaging failures are reported in rocinante's plain style, never as raw compiler output; the raw log is saved to `output/` for the curious.
- **Determinism rules** (non-negotiable 7). Both back ends use the same maths: no fast-math and no contraction of multiply-adds in either (Odin and C flags set once in the build script), one shared implementation of the random generator, noise and the trigonometric functions that both call, and no iteration order that depends on addresses or hashing. **Every run has a seed** (decided 2026-10-27): random unless the sketch sets it with `seed`, shown by `roci run` on request and stored in the metadata of exports, so the same seed gives the same picture. The one random generator and noise implementation live in `roci/` from its first commit. A new built-in that breaks one of these fails the equivalence suite (§9).
- **Stable verb ABI.** Generated code and the interpreter call core verbs through the same functions, so behaviour stays identical (non-negotiable 7). **The verb registry is data** (decided 2026-10-27): the ABI is also a table holding each verb's name, parameters and kinds, connecting words, whether it gives a value, and a one-line description. The checker's "did you mean", the reserved-word list (§5.15), the docs reference and language-server completion are all generated from it, so none can drift from the core.
- **No bytecode VM, no JIT.** A third back end would be one more thing to keep equivalent. Revisit only if the interpreter proves too slow for development use before Phase 7.
- **Source mapping.** Crashes and profiler output in packaged sketches must point at `.roci` lines. Investigate whether Odin can carry line information from generated code; otherwise keep a map from generated Odin lines to `.roci` lines and translate reports.
- **iOS.** Released sketches are ordinary native code, so App Store Review Guideline 2.5.2 (no downloading or executing code that changes the app's functionality) is not an issue for shipped sketches. Nothing runs `.roci` source on the phone: iOS and Android are targets only (§7), so there is no interpreter on a device.

### 4.8 User interface (decided 2026-10-23)

UI elements are first-class citizens: built-in verbs, drawn by Dear ImGui through SDL3, identical on every platform.

- **Immediate mode.** Widgets are verbs called every frame inside a `ui [ ]` block; they return their current value (or `true` on the frame a button is clicked). No callbacks, no widget objects, no syncing between UI state and sketch state. This matches the paradigm in §5.2: widgets are verbs, values are plain data.
- **Engine: Dear ImGui** (MIT). Its official backends `imgui_impl_sdl3` (input, platform) and `imgui_impl_sdlgpu3` (rendering through the SDL3 GPU API) mean no custom renderer integration. UI is drawn last in each window's render pass, so it is exported, recorded and golden-image tested like any other drawing. It always draws on top of the canvas and ignores canvas transforms, cameras and styles. Users only ever see rocinante verbs and rocinante's theme; Dear ImGui never appears in the language, docs or errors.
- **Odin bindings** come from **dear_bindings** (MIT), which generates a C API (`dcimgui.h`) and a JSON description from which we generate Odin bindings. The SDL3 backend is in dear_bindings' tested list; `imgui_impl_sdlgpu3` is not yet, so verify its conversion in Phase 0 and contribute fixes upstream. Generated bindings live in `vendor/`.
- **Accessibility: our own AccessKit bridge** (decided 2026-10-23). Dear ImGui has no screen-reader support, so we build it. Every widget goes through a rocinante verb, so the core always knows each widget's role, label, value, state and focus, even though Dear ImGui doesn't keep them. Each frame, `ui` builds an AccessKit tree from its own widget records plus Dear ImGui's item rectangles and IDs, sends updates only when something changed, and turns AccessKit action requests (focus, press, set value, increment, decrement) into the same changes a mouse or keyboard would make. AccessKit (Apache-2.0 OR MIT; Chromium-derived parts under a BSD-style licence) is used through its C bindings, accesskit-c. Its release workflow publishes prebuilt libraries for macOS (arm64, x86_64), iOS (arm64 and the simulators), Windows (arm64, x86, x86_64), Linux (x86, x86_64) and Android (arm64-v8a, x86_64). It publishes none for FreeBSD or arm64 Linux, although its Unix adapter is compiled for FreeBSD too. accesskit-c is written in Rust, so for those two targets we build it once per release on the release machines (never on users' machines) and offer the targets upstream. AccessKit's adapters cover Windows (UI Automation), macOS (NSAccessibility), Unix (AT-SPI over D-Bus), Android and iOS. Whether the Unix adapter works with screen readers on FreeBSD is unverified: confirm in Phase 3 and record it here. Offer the bridge upstream to Dear ImGui as a reusable piece.
- **Identity** (revised 2026-10-24). Each widget is identified by its label, its enclosing panel and tab path, and the loop index when it is made inside a loop (mapped to Dear ImGui IDs), so values survive hot reload and editing nearby code, and widgets made in a loop (mixer channels) stay apart. Two widgets with the same label and path in the same block are a load-time error with a friendly message.
- **Memory.** Widget values persist across hot reload and are saved in `ui.toml` in the sketch folder, which is committed to git (§4.9), keyed by the readable identity path above. `ui.toml` is written when the sketch exits and after a pause in changes, never on every slider move, so a performance does not leave the working tree dirty. `forget ui` resets them.
- **Text input and IME** use SDL3's text input API through the SDL3 backend: `SDL_StartTextInput` enables text and IME editing events and, on some platforms, shows the on-screen keyboard; `SDL_StartTextInputWithProperties` requests number fields and multi-line input; the IME window is placed with `SDL_SetTextInputArea`. Verify the backend's IME handling against non-Latin input in Phase 0.
- **Input model.** Mouse, touch, pen and keyboard all work. Dear ImGui's keyboard navigation is enabled by default: Tab and Shift+Tab move focus, Enter activates, Escape cancels. Tab never does anything else; hiding the UI has its own key (§5.8). Every widget is usable without a mouse. Touch arrives as mouse input in Dear ImGui; we enlarge hit targets on touch devices through the style scale and handle scrolling by drag ourselves.
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
    images/  sounds/  videos/  fonts/  3d-models/  ml-models/  shaders/  data/
  output/              # saved frames, recordings, exports, build logs; ignored by git
  libs/                # vendored libraries from `use` (§5.10); committed to git
  ui.toml              # remembered UI values; committed to git
  sketch.toml          # optional: packaging details and version; created by `roci package`; committed to git
  .gitignore
  .gitattributes       # only when Git LFS was chosen
```

- **A single file still works.** A lone `.roci` file with no folder runs (non-negotiable 1). `assets/` is where files go once a sketch has any, never a precondition.
- **What goes where.** `images/` (PNG, JPEG, …), `sounds/` (WAV, FLAC, MP3, Ogg), `videos/` (movie files for `movie`), `fonts/` (TTF, OTF, including copied system fonts, below), `3d-models/` (glTF, OBJ, SVG for 3D import, §6), `ml-models/` (LiteRT `.tflite` and `.litertlm` files, §4.10), `shaders/` (user shaders), `data/` (JSON, CSV, text). `roci add` picks the folder from the file type. Folder names are lowercase, like everything else in rocinante (§5.1).
- **Assets are found by name, not path.** `load "cat.png"`, `font "Inter"`, `sound "rain.wav"` search all of `assets/`, subfolders included. The subfolders are a tidy convention, not an address. If two files share a name, the checker says so and asks for the subfolder: `load "images/cat.png"`.
- **Bundled files come only from `assets/`.** A literal path outside it is a load-time error that teaches: "`/Users/…/cat.png` is outside your sketch, so it wouldn't travel with it. Copy it into `assets/`, or run `roci add /Users/…/cat.png` and I'll copy it for you." This is what makes sketches portable: a zip or a `git clone` runs anywhere, and iOS and Android (which can't read arbitrary paths) behave like the desktop.
- **Packaging bundles all of `assets/` and `libs/` (§5.10).** Computed names (`load ("frame" + n + ".png")`) can't be traced, so nothing is dropped. `roci package` lists files that no literal in the sketch mentions, as a hint, without removing them.
- **Live assets.** While `roci run` is going, a changed asset (repainted image, re-exported model, edited shader) reloads in the running sketch.
- **Runtime files are the deliberate exception.** Files chosen while the sketch runs may come from anywhere the platform allows: `ask file`, `ask folder`, dropped files, `files in "~/Pictures"`. They are never bundled, because they belong to whoever is running the sketch. On iOS and Android these go through the system file pickers.
- **Output.** `save`, `record` and exports write to `output/` by default, so renders never clutter the repository. An explicit path is allowed for saving.
- **Remembered UI values** (§4.8) live in `ui.toml` at the top of the sketch folder, written in a readable, stable order so diffs are meaningful. Neither Odin's `core:` nor its `vendor:` collection has a TOML package (checked 2026-10-24 against pkg.odin-lang.org), so rocinante writes its own small `toml` package in `roci/` that reads and writes the subset `ui.toml` and packaging settings use, and offers it upstream to Odin. It is committed to git, so a tuned performance travels with the repository. `forget ui` clears it. Packaged sketches start from the committed values.
- **System fonts are copied into the sketch** (decided 2026-10-24). When `font "Name"` finds no file in `assets/` but finds a font installed on the system, `roci run` copies the font files into `assets/fonts/` the first time and says so in one line, so the sketch looks the same on every machine and in every package. Font licences decide whether a copy may travel: before copying, `roci` reads the font's licence fields (the OpenType `name` table licence description and URL, and the `OS/2` embedding bits). Fonts under licences that allow redistribution (SIL Open Font License, Apache-2.0, the Ubuntu Font Licence and similar) are copied silently apart from the one-line note. Fonts whose licence doesn't allow it, or can't be read (most fonts that ship with macOS, Windows and iOS), are used on this machine but not copied, with a message that teaches: "Helvetica Neue belongs to Apple, so it can't travel with your sketch. It works here; anywhere else your sketch would fall back to rocinante's default font. To share it, put a font you're allowed to share in `assets/fonts/`. Inter is a good start." `roci package` refuses to bundle a font with a restrictive licence and says which one.
- **Packaging details and versions: `sketch.toml`** (decided 2026-10-27). `roci package` creates it beside `sketch.roci` on first use, asking only for what it needs: app name, app id (bundle id), icon, version and build number. Writing it by hand is allowed and never required, and a sketch without it runs exactly the same, so non-negotiable 1 holds. It holds packaging details only, never anything that changes what the sketch does (window size and `fps` stay in the code). It uses the same `toml` package as `ui.toml`, and stays separate from it because `roci` writes `ui.toml` all the time while `sketch.toml` changes only when packaging.
  - **The version people see** is yours to choose: `1.0.1`, a date such as `2026.10.27`, or `version = "date"` to stamp the packaging day. `roci` checks it against each target's limits and explains in plain words when it does not fit (a date as one Windows number, for example).
  - **The build number** belongs to `roci`: it rises by one on every `roci package`, is stored in the file so it never goes down, and users never have to see it. The stores need it: Android's `versionCode` is a positive integer that must increase, at most 2,100,000,000 (Android docs, §12), Windows file and product versions are four numbers of at most 65,535 each (VERSIONINFO, §12), and Apple wants a short version plus a build number (to be read from Apple's documentation before the iOS and macOS packaging is written, because the page did not load when this was decided).
  - **Git tags are a check, not a requirement.** When the current commit has a `v…` tag that disagrees with the file, `roci package` says so and offers to fix one of them.

**`roci new` and `roci init`.** `roci new <name>` creates the folder above; `roci init` does the same in an existing folder without overwriting anything. Both:

- write `sketch.roci` (formatted, with the circle), `assets/` and its subfolders (each with an empty `.keep` file so git keeps them), `output/` and `.gitignore` (ignoring `output/` and roci's local cache);
- if git is installed, run `git init` and make a first commit; without git, say so in one line and carry on;
- **offer Git LFS** for large binary assets. On yes, and if `git lfs` is installed, track common audio, video, 3D, machine-learning and large image types (`*.wav`, `*.aiff`, `*.flac`, `*.mp4`, `*.mov`, `*.glb`, `*.fbx`, `*.tflite`, `*.litertlm`, `*.exr`, `*.psd`, list to be finalised in Phase 2) with `git lfs track`, which writes `.gitattributes`, and commit that file. If Git LFS isn't installed, explain in plain words how to get it and continue without it. Git LFS is a separate, user-installed tool; rocinante neither bundles nor depends on it (§3).

### 4.10 Machine learning (decided 2026-10-24)

Trained models run locally, out of the box, in every sketch and on every platform. No cloud service, no account, no Python while the sketch runs. Users see pictures, numbers and lists, never tensors.

- **One runtime: LiteRT** (Google's on-device runtime, formerly TensorFlow Lite; Apache-2.0), used through its C API. The LiteRT repository (v2.3.0, 2026-10-07) has two: the classic one, `tflite/c/c_api.h`, which the original TensorFlow Lite C API became, and a newer `litert/c/` API built around `CompiledModel`, which Google's docs now lead with. Phase 6's spike picks one and records why; the classic one is the likelier fit for CPU inference with fixed threads (§9). Odin's `vendor:` collection has no machine-learning runtime, so the bindings live in `vendor/` (§3). One runtime keeps one behaviour (non-negotiable 7) and one set of bugs.
- **Three kinds of model, one file format.** LiteRT runs `.tflite` models, with `.litertlm` for language models. The other two sources reach that format through Google's official converters, once, on the author's machine:
  - **LiteRT:** `.tflite` and `.litertlm` files work as they are: drop them in `assets/ml-models/` or run `roci add pose.tflite`.
  - **PyTorch:** converted to `.tflite` with the LiteRT Torch converter.
  - **JAX:** converted with `jax2tf` to a TensorFlow SavedModel, then to `.tflite` with the TFLite converter. Google's docs call `jax2tf` experimental.
  - The converters are Python tools the author installs (non-negotiable 2's second exception). `roci doctor ml` checks for them and prints the install steps. Phase 0 settles which saved PyTorch and JAX files `roci add` can convert by itself and which need the short Python recipe in rocinante's docs.
- **Built-in tasks for the common cases**, in the spirit of ml5.js: `poses`, `hands`, `faces`, `objects`, `labels` (image classification) and `cutout` (person segmentation), each taking an image, a canvas or the webcam and giving plain data (lists of records with named points as vectors, labels as text, masks as images). They use open, permissively licensed models chosen in Phase 6. The first use of a task fetches its model from the URL recorded in rocinante's model list, checks its checksum, and copies it into the sketch's `assets/ml-models/` (so `roci run` needs the network once), like `use` vendors libraries (§5.10), so the sketch runs offline and travels whole.
- **Any other model:** `style = load "style.tflite"` loads it and `out = predict style webcam` runs it. `predict` reads the model's input and output description and converts automatically: images are resized and normalised, numbers and lists become tensors and back, image-shaped outputs come back as images. When a model doesn't describe its inputs well enough, the error teaches and shows how to say it with connecting words.
- **Never blocks a frame.** Inference runs on worker threads (§4.4). `predict` and the task verbs give the latest finished result, and an empty value until the first one arrives (§5.2 useful zero values), so a slow model lowers its own update rate, never the sketch's frame rate.
- **Hardware.** CPU (XNNPACK) everywhere; GPU through LiteRT's Metal (Apple) and WebGPU (desktop) paths; NPUs where LiteRT supports them. Never LiteRT's OpenGL path (non-negotiable 9); on Android that leaves OpenCL, the NPU and the CPU. Users never choose: the core picks the fastest path that works and falls back silently.
- **Equivalence and testing.** Interpreted and compiled sketches call the same runtime through the stable verb ABI. Equivalence and golden tests run models on the CPU with a fixed thread count, where results repeat exactly (§9).
- **Model licences.** Model weights carry their own licences. `roci add` records where a model came from and its licence in a small `.source` file next to it, and `roci package` lists the licences of every bundled model.
- **Platform gaps.** LiteRT's own list covers Android, iOS, Linux, macOS and Windows, but not FreeBSD. FreeBSD's ports tree carries the Python TFLite runtime (`misc/py-tflite`), so building the C runtime there is likely; Phase 0 confirms it. If it fails, the fallback is ONNX Runtime (MIT, `misc/onnxruntime` in ports), decided then and recorded here.
- **Inference only.** Training models inside rocinante is out of scope for the first stable release.

### 4.11 Video (decided 2026-10-24)

Playing and recording video uses no FFmpeg (its licensing conflicts with §3 unless it is an optional, user-installed component).

- **Each platform's own media framework first:** AVFoundation on macOS and iOS, Media Foundation on Windows, MediaCodec on Android. They decode H.264 and HEVC in hardware, and the operating system covers those formats' licensing.
- **Open formats everywhere through permissive libraries:** AV1 with dav1d (BSD-2-Clause), VP8 and VP9 with libvpx (BSD-3-Clause), MPEG-1 with pl_mpeg (MIT). On Linux and FreeBSD, which have no system framework, these are the formats that play. AV1 and VP9 were designed to be royalty-free.
- **Recording** (`record`) writes AV1 or VP9 on every platform, and H.264 where the platform encoder offers it. Encoder libraries are chosen in Phase 6 under §3's rules.
- **FFmpeg as an optional extra:** if the user has installed FFmpeg, `movie` can use it for formats nothing else plays. rocinante never ships it, and `roci doctor` explains how to install it.
- `movie` and `webcam` give frames that work anywhere an image does: drawn, used as fills (§5.9), or passed to `predict` (§4.10).

---

## 5. The language

### 5.1 Design principles

- One statement per line. No terminators. (Decided 2026-10-24: inside a `[ ]` block that fits on one line, statements may be separated by two spaces, as in `[ step p  circle p.pos 3 ]`; `roci fmt` keeps a block on one line only when it is short and otherwise puts one statement per line.)
- One shape: `verb argument argument ...`. Verbs have a fixed number of required arguments, so the parser always knows where a call ends (as in Logo).
- **One thing per argument** (decided 2026-10-23). Each argument of a verb is a single visible item: a number, text, a name (including built-in values such as `width`, `mouse` and `pi`, and verbs that take no arguments such as `anywhere`), a field (`p.pos`), a `{ }` or `[ ]` literal, or a group in round brackets. A call that takes arguments, or a calculation, used as an argument goes in round brackets: `circle (random width) (random height) 5`, `slider "size" 10 (width / 2)`. The rule turns the readable habit into the grammar, so nested calls never depend on the reader counting arities.
  - **Full expressions are free wherever there is no argument list:** after `=`, after `give`, in `if` and `while` conditions, as the count of `repeat`, and between the commas of vector and record literals (§5.2). So `{ random width, 0 }` needs no brackets, and `x = random width + 10` means `(random width) + 10`: calls bind tighter than arithmetic, as in NetLogo.
  - **Connecting words belong to the call whose brackets they sit in**, so `add (random from 1 to 3) to scores` can't confuse its two `to`s.
  - **`roci fmt` adds missing brackets** when the reading is unique (every verb involved has one shape): `circle random width random height 5` becomes `circle (random width) (random height) 5`. It writes subtraction with spaces (`x - 10`) and negative numbers without (`-10`), so the two never look alike.
  - **Without the formatter, a missing bracket is a load-time error that shows the bracketed line** (§5.7). When brackets nest three deep, the checker adds a hint (not an error) suggesting a name on the line above: `x = random width`.
  - No pipes, no dot calls (`width.random`) and no commas between arguments. `.` stays for fields and library names (§5.10). List chains are named steps, not pipes (§5.2).
  - Rationale and sources: Logo, NetLogo, Rebol, Smalltalk, Odin and the paren-free languages surveyed all show that fixed arity solves the parser's problem but not the reader's. No study measures nested-call readability directly, so the Phase 2 newcomer test checks this rule (§8).
- Optional arguments are introduced by small connecting words, never by position: `window 800 600 at 100 100`, `text "hi" at 20 20 size 32`, `image photo at 0 0 width 200`. The connecting words form a short, fixed list (start with: `at`, `size`, `width`, `height`, `from`, `to`, `by`, `in`, `start`, `lines`, `angle`, `stops`, `as`, plus the style words in §5.9: `fill`, `stroke`, `thickness`, `alpha`, `font`, `style`). `to` is only ever a connecting word (`for i from 1 to 10`, `add x to particles`); verbs are defined with `learn` (§5.11).
- **A connecting word is one only after the call's required arguments are filled** (decided 2026-10-24). While a verb still has an open required slot, a word that is also a built-in value or a user name (`width`, `height`, `size`) is read as a value: `rect 0 0 width height fill pattern` reads `width` and `height` as the last two required arguments, then `fill` as a connecting word. The same holds for parameters of `learn` (`learn star size [ … ]`). The checker warns when the other reading would also have been valid.
- **Multi-word verbs** (`pen up`, `no fill`, `look at`, `ask file`, `forget ui`, `on mouse down`, `draw into`, `image button`, `export svg`, `hidden learn`, `for each`) are a fixed table of phrases, matched longest-first before a word is read on its own. The table is part of the core and is listed in the docs; user verbs are always one word.
- **`[ ]` is a block or a list by position** (decided 2026-10-24): where the verb's parameter takes a block (`repeat`, `if`, `draw`, `learn`) it is a block; after `=`, as a verb's list parameter, or as a colour list it is a list. Lists have no commas and vectors do (`[ 1 2 ]` against `{ 1, 2 }`); the Phase 2 newcomer test watches for this mix-up. Logo's brackets held code and data alike, and readers had to work out which; so the checker gives a teaching error whenever a list turns up where a block is expected, and the reverse (decided 2026-10-27).
- Blocks use `[ ]`, as in Logo. Newlines inside blocks are free. (Decided 2026-10-22: `[ ]`, not `end`.)
- **Indentation is free and never changes meaning** (decided 2026-10-23). `[ ]` alone defines blocks; tabs, spaces and pasted code can never break a sketch. Consistency comes from tooling instead:
  - **`roci fmt`** rewrites a sketch in the house style: two spaces per block level, one space inside brackets, one statement per line. Editor plugins run it on save, `roci new` starts formatted, and all docs and examples are formatted with it. It has no options, so there is nothing to argue about.
  - **Indentation as an error hint.** The parser ignores indentation, but when brackets don't balance, the checker compares the brackets with the indentation to find where the mistake is. Example: "Line 7 is indented as if it belongs inside the `repeat` on line 4, but that block closed on line 6. Did you mean to move the `]`?" Never a generic "unexpected end of file".
- **Plain words, not English sentences** (decided 2026-10-27). The words are plain, but the grammar never imitates English. Every construct has one canonical form with a fixed word order: no filler words, no synonyms for the same job, and no wording that changes how a line parses. AppleScript's naturalistic syntax made scripts easy to read and hard to write, and its multi-word terms made the lexer depend on context, which ruined its error messages (Cook, HOPL III, §12). A new construct ships with a rule in the grammar (§5.14), a rule in `roci fmt` and an entry in the error catalogue (§5.7).
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

- **Vector literals.** A vector is written with braces and commas, like Odin's compound literals: `{ x, y }` or `{ x, y, z }`. Braces with `name:` fields are a record; braces without names are a vector. There is no `vec` verb. Each item between commas may be any expression, so `{ random width, 0 }` needs no brackets (§5.1).
- **Array programming.** Vectors and colours support arithmetic directly: `pos = pos + vel`, `c = c * 0.5`, `v * 2 + { 1, 1 }`. Swizzles: `p.xy`, `p.zyx`. These map one to one onto Odin's own array programming in generated code, and `{ a, b }` maps onto Odin's context-typed `{a, b}`.
- **Explicit verb groups.** One verb name may accept several argument shapes (`circle 100 100 50` and `circle p 50`). The shapes are declared together in one place, in the core and in user code. Because every argument is one item (§5.1), the parser finds where a call ends without knowing types; the checker then picks the shape by argument count first, then by argument kinds. Two shapes in one group may not share both count and kinds: declaring them is a load-time error, in the core or in `learn` (decided 2026-10-23).
- **Useful zero values.** A record field that was never set reads as 0 (or empty text, empty list). Reading it is never an error.
- **No exceptions.** A failing operation (missing file, bad URL) shows the error overlay, yields an empty value and lets the sketch continue. Users can test for emptiness (`if photo is empty [ … ]`); there is no try/catch.
- **Implicit context.** Style and transform state (fill, stroke, thickness, transform, font, blend) is an implicit context, reset at the start of every `draw` frame and scoped by `with [ ]` (style, §5.9) and `push [ ]` (style and transforms).

Deliberate differences from Odin:

- **Blocks capture variables.** `every 2 seconds [ size = size + 10 ]` sees `size`. Odin has only non-capturing procedures because capturing closures need automatic memory management; our runtime manages memory, so users never think about it. Generated Odin passes captured variables explicitly.
- **A light functional layer for lists** (decided 2026-10-24), as verbs that take a block. Inside the block, `it` is the current item. Each gives a new list or value and leaves the original alone:

```
alive  = keep particles [ it.life > 0 ]       # the items that pass
calm   = skip particles [ it.speed > 5 ]      # the items that don't
sizes  = collect particles [ it.size * 2 ]    # one new value per item
total  = combine scores from 0 [ result + it ]   # fold: `result` is the running value
big    = find particles [ it.size > 20 ]      # the first match, or empty
order  = sort particles by [ it.size ]        # sorted by what the block gives
```

  There is no pipe: chains are written one named step per line, which reads more clearly and fits one statement per line. `map` stays Processing's number-remapping verb, and `filter` stays an image effect. `collect` and the idea of plain-English list verbs come from Smalltalk. `it` and `result` are keywords, lowercase like all others (§5.1).

### 5.3 Typing: inferred and static (decided 2026-10-22)

- **Users never write a type.** There is no type syntax in sketches.
- **The checker infers every type it can** from literals, verb signatures, field use and assignments: `x = 10` is a number, `p.pos` is a vector, `particles` is a list of records with fields `pos` and `vel`, both vectors.
- **Conflicts are load-time errors in plain words**, never type jargon. For example: "`size` holds a number on line 3 but text on line 12. A name keeps one kind of value; try a new name for the text."
- **Records are shaped by use** (decided 2026-10-24). Three rules, with the error messages written first in Phase 2:
  - **One shape per place a record is made.** A record literal fixes its fields; assigning a field anywhere else in the sketch (`ball.colour = red`) extends the shape for every record made at that place, and the field starts at its zero value.
  - **Verbs take any record that has what they use.** `learn step p [ p.pos = p.pos + p.vel ]` works for every record with `pos` and `vel`, whatever else it holds (structural records, as in Elm). Compiled code gets one plain Odin struct per shape and one version of the verb per shape it is used with.
  - **Data from files gets its shape from the file.** When `load "birds.json"` names a file in `assets/`, the checker reads that file while checking and takes the shape from it, as F#'s JSON type providers do, so `birds.items` and its fields are known before the sketch runs. When the file name is computed, or the data comes from `fetch` or `ask file`, values use the boxed fallback below.
  - **Messages between windows** take their shape from the `send` lines that can reach each `on … receive`; the checker sees the whole program.
- **Fallback, not failure.** Where inference cannot decide (rare in sketches), the value becomes a general boxed value (an Odin tagged union in generated code): slower, still correct, identical behaviour in both back ends. `roci check --why-slow` (name provisional) lists those places so power users can see them; ordinary users never need to.
- Inference is what makes compiled sketches fast: known types become plain Odin structs, floats and arrays instead of runtime kind checks.

### 5.4 Core syntax (draft)

```
# comments start with a hash

x = 10                      # variables: just assign
name = "Ada"
SPEED = 4                   # all capitals: a constant, can never change
COLOURS = [ red orange teal ]   # constant list: readable, never modified
points = [ { 10, 20 } { 30, 40 } ]   # lists
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
for each p in points [ circle p 10 ]

draw [ ... ]                # runs every frame (default window)
draw w [ ... ]              # runs every frame for window w
on key "space" [ ... ]
on mouse down [ ... ]
on touch [ ... ]
on w receive msg [ ... ]
every 2 seconds [ ... ]

v = { 3, 4 }                # vectors: braces and commas, no names
u = v * 2 + { 1, 1 }        # arithmetic and swizzles
circle v.xy 10
circle anywhere 5           # a random point in the window
r = random from 1 to 3      # a random number in a range
c = pick COLOURS            # a random item from a list
```

A complete particle sketch in this style (lists of records, verbs, no objects):

```
particles = []
repeat 200 [ add { pos: { random width, 0 }, vel: { 0, random 3 } } to particles ]

learn step p [ p.pos = p.pos + p.vel ]

draw [
  background 0
  for each p in particles [ step p  circle p.pos 3 ]
]
```

### 5.5 Program model

- Top-level statements run once, in order. If the program has no `draw` block, the window shows the result and stays open. In a multi-file sketch (§5.10), only `sketch.roci` has top-level statements that run; the other files hold definitions.
- If a `draw` block exists, top-level statements act as setup and the block runs every frame.
- **Hot reload** (interpreter only, decided 2026-10-24). On every save:
  - The new code is checked first. If it has an error, the old code keeps running under the error overlay (non-negotiable 3) until the next save fixes it.
  - Every reload says what it did: the console and overlay report "reloaded" (state kept) or "restarted", and name any value that was lost (decided 2026-10-27). Each `learn` body is hashed, so reload knows exactly which verbs changed. A renamed field counts as one removed and one added, so its value is lost and the message says so.
  - If it checks, verbs, `draw` blocks, event blocks and `ui` blocks switch to the new code on the next frame.
  - A top-level variable keeps its running value unless the line that defines it changed, or the kind of value it holds changed; then that line runs again.
  - Records keep their values when their shape gains a field; the new field starts at its zero value (§5.2). When a shape loses a field or a field changes kind, the variables holding those records start again from their defining lines.
  - Constants (all-capital names, §5.1) always take the value written in the source, so editing `SPEED = 4` to `SPEED = 8` takes effect at once while variables keep their running values.
  - UI values are remembered as before (§4.8).
  - `Ctrl+R` in a sketch window (`Cmd+R` on macOS) restarts the sketch from scratch: every variable from its defining line, every top-level statement again. UI values are kept; `forget ui` clears them.

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

```
── This value needs brackets ─────────────────────── sketch.roci:4:8

4 │ circle random width random height 5
  │        ^^^^^^^^^^^^

`random width` works out a number, so when it sits inside `circle`,
wrap it in round brackets so it reads as one thing:

    circle (random width) (random height) 5

Or let `roci fmt` add them for you.
```

The catalogue is data (decided 2026-10-27): each entry has a message ID, the plain explanation and an example fix, so messages can be translated later (§5.15 spelling, Swidan and Hermans in §12). A message must make sense read aloud by a screen reader, so it says "the closing square bracket", never a bare `]` (Hermans, §12). The parser resynchronises at `[ ]` boundaries and reports every error in one pass, not only the first; `roci run` keeps the last good code (§5.5) and `roci package` refuses a sketch that has errors. `roci run --errors json` prints the same entries as data (line, column, message ID, nearest known verb) for tools. Every error class needs an entry in `tests/errors/` with the source that triggers it and the expected message. Error messages are reviewed like features. Because all errors come from the shared front end (§4.7), `roci run` and `roci package` report exactly the same errors.

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
  label ("fps: " + fps)
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
- **Hiding** (decided 2026-10-24, revised): the backtick key (`` ` ``, read by physical key position like `keys w a s d`, §5.12) hides and shows the UI; on phones and tablets a three-finger tap does. `Tab` only moves keyboard focus (§4.8), so no key has two jobs. The key is ignored while a text box has focus, so it never eats typing. `ui key "f1"` (any key name) changes it, and `ui hide` and `ui show` do it from code, so performances can run clean. While the UI is hidden, the screen-reader tree stays and reports "controls hidden, press ` to show" (§4.8), and showing the UI again moves focus to the first widget, so keyboard and screen-reader users reach the widgets in one press.
- **`ui` inside `draw`** (decided 2026-10-24): `ui [ ]` blocks may also sit inside `draw` blocks, for widgets tied to things on the canvas. `at` there takes canvas positions, so `slider "speed" 0 5 at p.pos` follows `p` as it moves. Widgets still draw on top and keep their size and theme; only their position follows the canvas.

Full widget set for the first stable release: `label`, `button`, `toggle`, `checkbox` (alias of toggle), `slider`, `range` (two-handle slider), `knob`, `number`, `textbox`, `dropdown`, `choice`, `colorpicker`, `xypad`, `progress`, `list` (selectable list), `panel`, `row`, `column`, `tabs`/`tab`, `menu`/`item`, `tip`, `separator`, `image button`, `controls` (remapping actions, §5.12). Additions go through this file first.

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
- **Origin** (decided 2026-10-24). `rect`, `circle` (and the other 2D shapes), `image`, `square` and `ellipse` take `as center` or `as corner` to say what their position means: `rect 200 200 80 40 as center` puts the middle of the rectangle at 200, 200; `as corner` is the default for `rect`, `square` and `image`, the top left, as in Processing; `circle`, `ellipse` and `arc` default to `as center`, also as in Processing (decided 2026-10-27). One shared pair of words replaces Processing's `rectMode`, `ellipseMode`, `imageMode` and `shapeMode`, and it is per element, so nothing sticks from one line to the next. `as` already carries fill modes (`fill photo as center`, `fill [ red teal ] as radial`), so the rule is positional (§5.1): an `as` directly after a shape's required arguments is its origin, and an `as` after a `fill` or `stroke` value belongs to that value. `circle 100 100 50 as center fill photo as cover` reads one way: the first `as` is the origin and the second is the fill mode. A circle, an ellipse and an arc are already centred, so `as center` only matters for the shapes that default to a corner, and `as corner` is how to place a circle or an ellipse by its top left.

**Colours** are accepted anywhere a colour goes:

- Names: the CSS named colours (`red`, `orange`, `teal`, …).
- Hex: `#ff8800`, or `#ff880080` with alpha.
- One number for grey: `fill 0`, `background 30`.
- `rgb r g b`, `hsb h s b`, `oklch l c h`; any of them may be followed by `alpha a`.
- **Range: every colour channel is 0–255** (decided 2026-10-23), including grey, `rgb`, `hsb` and `alpha`: `fill red alpha 128` is half transparent. One rule, familiar to Processing users. The only exception is `oklch`, which follows its standard CSS notation (lightness 0–1, chroma, hue in degrees) because its whole point is matching that standard.
- Values outside 0–255 are clamped, with a gentle warning from the checker when it can see the value at load time.
- Colours are values: `c = rgb 255 136 0`, `mix c blue 0.5`, `c * 0.5` (§5.2 array programming).

**Gradients** (decided 2026-10-24). Wherever a colour goes in `fill`, `stroke` or `background`, a list of colours makes a gradient. The colours are spaced evenly unless `stops` says otherwise.

```
fill [ red orange teal ]                      # linear, left to right
fill [ red orange teal ] angle 90             # linear, top to bottom
fill [ red orange teal ] stops [ 0 20 100 ]   # uneven steps, in percent along the way
fill [ white black ] as radial                # from the centre outwards
fill [ white black ] as radial at 30 30       # centre at 30% across, 30% down the shape
fill [ red yellow red ] as conic angle 45     # sweeping round the centre
fill [ red blue ] in rgb                      # mixed in RGB, like Processing
background [ navy black ] angle 90
stroke [ white cyan ]

sunset = gradient [ orange purple ] angle 90  # a gradient is a value
circle 100 100 50 fill sunset
glow = { fill: sunset, stroke: white }        # and works in named styles
```

- **Kinds:** `as linear` (the default), `as radial`, `as conic`.
- **Orientation:** `angle` in degrees. `0` runs left to right and angles turn clockwise, like the turtle's `right`; for `conic`, `angle` sets where the sweep starts.
- **Steps:** any number of colours, each a full colour value (`#ff8800`, `rgb …`, a name, with alpha). `stops` gives each colour's position as a percentage, one per colour.
- **Geometry follows the shape.** Positions are percentages of the element's bounding box, so a gradient fits a circle, a rectangle or a line of text without arithmetic.
- **Mixing:** colours are mixed in Oklab by default, which keeps gradients even and avoids muddy middles; `in rgb` gives Processing's look and `in oklch` mixes along the hue.
- With per-element style words, a bare list works (`circle 100 100 50 fill [ red teal ]`). A gradient with options is named first or wrapped: `fill (gradient [ red teal ] angle 90)`, because connecting words belong to the call they sit in (§5.1).
- Gradients are drawn on the GPU in one pass per element, like solid colours.

**Images, video and canvases as fills** (decided 2026-10-24). `fill` also takes an image, a canvas, a movie or the webcam. The element becomes a mask: the image shows only inside the shape, including text.

```
photo = load "cat.png"
fill photo                       # cover: fill the shape, crop what overflows
circle 200 200 150
square 20 20 100 fill photo as fit       # whole image inside, empty bands if needed
rect 0 0 400 100 fill photo as stretch   # distort to fit exactly
rect 0 0 width height fill pattern as tile size 64   # repeat at 64 pixels
square 50 50 300 fill photo as center   # original size, centred, no scaling
text "rocinante" at 20 200 size 96 fill webcam
```

- **Modes:** `as cover` (the default: scale to fill the shape and crop the overflow), `as fit` (scale to show the whole image inside the shape), `as stretch` (scale each axis to the shape's box), `as tile` (repeat at the image's own size, or `size n`) and `as center` (no scaling, centred). `cover` is CSS's name for "fill"; rocinante uses it because `fill photo as fill` would read badly.
- `at x y` shifts the image inside the shape, in pixels, for `tile` and `center`.
- Image fills work with `stroke` too, and inside `with` blocks and named styles.

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
- **The index** is a plain git repository on GitHub mapping short names to git URLs, curated in the spirit of ofxAddons; Fabrizio curates it at first (decided 2026-10-24). Libraries are listed through a pull request to the index, which Fabrizio reviews (decided 2026-10-24). To be listed, a library:
  - lives in a public git repository under a licence allowed by §3's dependency policy;
  - passes `roci check` on the current rocinante release;
  - has a `README` with at least one example that runs;
  - has a lowercase name that doesn't clash with built-ins or with another listed library;
  - downloads nothing and runs no outside code when it loads;
  - names a maintainer who can be contacted.

  A library is removed from the index when it has been broken for two consecutive releases, or when its licence changes to one §3 doesn't allow. Sketches that already vendored it keep working, because `libs/` is theirs. No central server or registry is needed. Any git URL works without the index.
- **A library is a folder of `.roci` files**, optionally with its own `assets/` (found by name after the sketch's own assets, which always win) and a short `README`. Later (Phase 9) a library can also be an Odin or C extension using the stable verb ABI (§4.7); the `use` line is identical and users can't tell the difference. `roci get` and `roci run` tell the user that a native extension runs code, and ask once before loading one from a git URL (decided 2026-10-24). An extension ships two ways (decided 2026-10-24): as Odin source, which `roci package` compiles together with the core and the sketch (like the core itself, §4.7), and as prebuilt dynamic libraries for the four desktop systems, which `roci run` loads with Odin's `core:dynlib`, so no toolchain is needed while working. `roci` and its interpreter do not run on phones (iOS and Android are targets only, §7), so mobile needs only the source. The index provides a GitHub Actions template that builds an extension's desktop libraries for its authors.
- **Definitions only outside `sketch.roci`** (decided 2026-10-24). Files other than `sketch.roci`, and library files, hold only `learn`, constants, `use` and other definitions, evaluated in dependency order before `sketch.roci` runs, so splitting a sketch into files never changes what it does. A top-level drawing statement or a variable assignment in another file is a load-time error that says to move it into `sketch.roci` or into a verb.
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
  repeat points [ forward size  right (720 / points) ]
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
- **Sharing (decided 2026-10-23).** Numbers, vectors, colours and text are copied when passed or assigned. Lists and records are shared: a verb that changes a record changes the caller's record, which is what makes `learn step p [ p.pos = p.pos + p.vel ]` work, and what Processing users expect from objects and arrays. `b = a` with a record also shares; `b = copy a` makes an independent copy. Passing a constant (§5.1) to a verb that changes it is a load-time error. Because `b = a` sharing is the classic beginner trap, the checker adds a hint, not an error, when it sees a list or record changed through a second name ("`b` and `a` are the same list, so this also changes `a`. Use `copy a` for a separate one"), and the Phase 2 newcomer test probes it (decided 2026-10-27).
- `learn`, `give`, `stop` and `with` are keywords, lowercase like all others (§5.1).

### 5.12 Game controllers and actions (decided 2026-10-24)

Gamepads, joysticks and other controllers work in every sketch with no setup, through SDL3's gamepad and joystick APIs, with hot-plugging on every platform.

```
p = gamepad                       # the first connected gamepad, or empty
circle (p.leftstick.x * 100 + 200) 300 20   # sticks are vectors from -1 to 1
if p.bottom [ jump ]              # buttons are true while held
for each pad in gamepads [ … ]    # every connected gamepad
```

- **Gamepads** follow SDL3's model: buttons are named by where they are on the pad, not by the letter printed on them, because the same position says A on one pad and B or ✕ on another. rocinante gives SDL3's positions friendlier names (decided 2026-10-24):

| rocinante field | SDL3 | What it is |
|---|---|---|
| `bottom`, `right`, `left`, `top` | `SOUTH`, `EAST`, `WEST`, `NORTH` | the four face buttons, by position |
| `leftstick`, `rightstick` | left and right stick axes | vectors from -1 to 1 |
| `leftstickpress`, `rightstickpress` | `LEFT_STICK`, `RIGHT_STICK` | pressing a stick in |
| `leftshoulder`, `rightshoulder` | `LEFT_SHOULDER`, `RIGHT_SHOULDER` | shoulder buttons |
| `lefttrigger`, `righttrigger` | trigger axes | 0 to 1 |
| `dpad` | `DPAD_UP`, `DPAD_DOWN`, `DPAD_LEFT`, `DPAD_RIGHT` | a vector: x and y each -1, 0 or 1 |
| `start`, `back`, `home` | `START`, `BACK`, `GUIDE` | menu buttons |
| `extra` | `MISC1`–`MISC6`, paddles, `TOUCHPAD` | a list of the remaining buttons |

  Input names use the same words: `"pad bottom"`, `"pad leftstick"`, `"pad lefttrigger"`, `"pad dpad"`. The docs show each pad family's printed labels next to the positions.
- **SDL3 knows most pads out of the box.** For unknown pads, rocinante accepts SDL mapping strings, added through SDL's mapping functions, and `roci` keeps a community mapping database up to date.
- **Joysticks** without a gamepad layout (flight sticks, wheels, arcade panels, custom hardware) appear in `joysticks`, each with `axes` and `buttons` lists.
- **Actions, so input can be remapped.** A sketch names what the player does and binds inputs to it, from any device:

```
bind "jump" to "pad bottom"
bind "jump" to "key space"          # several bindings, any of them works
bind "move" to "pad leftstick"
bind "move" to "keys w a s d"       # four keys become a vector, bound by physical position
on press "jump" [ … ]
if held "fire" [ … ]
pos = pos + (direction "move") * SPEED
```

- **Players remap at run time** with the `controls` widget (§5.8): it lists every action and its bindings, and pressing a new button or key rebinds it. Remapped bindings are remembered values, saved in `ui.toml` like any widget (§4.9); `forget ui` restores the sketch's own bindings. Packaged sketches start from the committed ones.
- **Feedback:** `rumble strength seconds` (strength 0 to 1) where the pad supports it. Pad gyroscopes, touchpads and lights come later, through the same SDL3 API.
- **Input names** are text, so one list covers keyboards, mice, gamepads and joysticks: `"key space"`, `"mouse left"`, `"pad bottom"`, `"pad leftstick"`, `"joystick 1 button 3"`. A name that doesn't exist is a load-time error that lists the closest names.

### 5.13 Collision detection (decided 2026-10-24)

Collision is built in. Shapes are plain records (§5.2), recognised by their fields, so the same record can be drawn and tested:

| Record fields | Shape |
|---|---|
| a vector (`{ 10, 20 }`) | point |
| `pos`, `radius` | circle (2D) or sphere (3D vector) |
| `pos`, `size` (and optional `angle`) | rectangle or box, rotated by `angle`; a record that also has `radius` is a circle or sphere |
| `from`, `to` | line segment |
| `points` | polygon (2D) |

A record that matches no row, or matches rows that disagree (for example `points` together with `from`), is a load-time error when it is passed to a collision verb, and the message lists the fields each shape needs (decided 2026-10-24).

```
ball   = { pos: { 200, 100 }, radius: 10, vel: { 2, 3 } }
paddle = { pos: { 180, 380 }, size: { 80, 12 } }

if touching ball paddle [ ball.vel.y = -ball.vel.y ]
c = contact ball paddle            # { point, normal, depth }, or empty
for each b in (hits ball bricks) [ remove b from bricks ]
if inside mouse paddle [ … ]
h = cast { from: eye, to: target } walls   # first thing along a line
```

- **Verbs:** `touching a b` (true or false), `contact a b` (where they touch, the direction to push apart and how far, or empty), `hits a list` (every item in a list that touches `a`), `inside point shape` and `cast segment list` (the first hit along a line, with its point and normal).
- **Fast for many things.** `hits` and `cast` over lists use a broad phase (a dynamic tree) automatically, so a thousand particles against a thousand walls stays cheap.
- **Detection first, simulation when asked for.** Collision answers questions; what happens next is the sketch's choice.
- **2D physics** (decided 2026-10-24) builds on the same records and on Box2D v3's world simulation. Draft verbs: `simulate ball` hands a shape record to the physics world, which then updates its `pos`, `vel` and `angle` every frame; `fixed wall` makes a body that never moves; `gravity { 0, 400 }` sets gravity; `kick ball { 0, -300 }` applies an impulse (not `push`, which scopes style and transforms); `join a b` connects two bodies. A sketch that never calls `simulate` has no physics world at all. 3D physics is on the roadmap (README.md).
- **Implementation:** 2D uses Box2D v3's collision functions through Odin's `vendor:box2d` (MIT). 3D starts with rocinante's own sphere, box, segment and ray tests in Odin; Box3D (Box2D's 3D sibling, MIT, also in `vendor:`) is reconsidered once it has releases and covers iOS and Android.
- Results are identical interpreted and compiled, because both call the same core functions (non-negotiable 7).

### 5.14 Implementation notes

- Hand-written lexer and recursive-descent parser in Odin (for error quality), producing an AST with full source spans. A call collects its arguments greedily until it meets something that can't be an argument: a verb that takes arguments, a verb that gives no value, a connecting word, `]` or the end of the line (§5.1). No types are needed to parse, but the parser does need the verb table: before parsing a file it reads the `learn` headers of the whole program (the sketch's other files and `libs/`), because taught verbs fix argument counts and add their own connecting words. A connecting word is recognised only once the call's required arguments are filled (§5.1). Edge case: a giving verb with no parameters (`anywhere`) is a name, so the checker warns when one follows a complete call on the same line.
- The grammar is written down as `docs/grammar.ebnf` (decided 2026-10-27), kept beside the parser and checked by the parser's tests; it is the grammar itself, not a second design document. It is also what a syntax reference, highlighting grammars and constrained generation for local models are made from.
- Checker and type inference run before anything executes, producing the typed IR (§4.7). Spans are preserved on every AST node, IR node and literal, and carried by every runtime command (§4.3), so runtime errors, highlighting, the source map for generated Odin and later editor features all point at `.roci` lines. This is cheap to build in from the first commit and expensive to add later.
- The interpreter executes the typed IR directly (no separate AST walker). Keep it simple and correct; it is the reference implementation that the code generator is tested against.
- Use Odin's allocators deliberately: an arena per frame for temporary values, a long-lived allocator for sketch state, so hot reload can discard and rebuild cleanly.

### 5.15 Language details (decided 2026-10-24)

The rules below fill the gaps the 2026-10-24 review found. Where they touch another section, that section says so.

- **Operators.** From tightest to loosest: calls (§5.1), unary `-` and `not`, `*` `/` `%`, `+` `-`, comparisons (`<` `<=` `>` `>=` `is` `is not`), `and`, `or`. Equality is written `is`, because `=` is assignment. `%` is modulo. `+` with text on either side joins as text (`"fps: " + fps`). A minus is unary when there is a space before it and none after (`-10`), and subtraction otherwise (`x - 10`); the lexer decides, as `roci fmt` writes it (§5.1).
- **Lists.** Indexing starts at 1, like `for i from 1 to 10`: an item is read with `item 1 of scores` (`of` joins the connecting words). `count scores` gives the length, `add x to scores` and `remove x from scores` change it, and changing a list while `for each` walks it is a load-time error when the checker can see it and an overlay error otherwise. Lists of records from different creation sites unify to the union of their fields, missing fields at zero (§5.3).
- **Maps.** `map` is a second collection for dynamic keys (word counts, lookup tables): `m = map`, `set m "cat" 3`, `get m "cat"`, `keys m`. Reading a missing key gives the zero value (§5.2). Iteration order is insertion order, so both back ends agree (§4.7).
- **Text.** `length`, `split text by ","`, `join list by ","`, `number text` (number from text, 0 if it isn't one), `upper`, `lower`.
- **`print` and logging.** `print value` writes to the console by default, in the interpreter and in packaged sketches. `log value` does the same with a timestamp, and `log to "file.txt"` also sends everything `log` prints to that file (in `output/` unless the path is explicit). Packaged sketches also write runtime errors to a log in the platform's usual place, since they have no overlay (§5.7).
- **Scope.** Assigning a name inside `draw`, `repeat`, `ui` or an `on` block creates a sketch-wide name, unless the name is a verb parameter or local (§5.11). `ui [ size = slider … ]` relies on this.
- **Drawing outside `draw`.** Drawing verbs inside an `on … receive` or other event block go into that window's next frame, in the order they ran.
- **Conventions.** The origin is the top left with y pointing down. Positions and sizes are in logical pixels; HiDPI is automatic. Angles are in degrees everywhere, including `sin`, `cos`, `right` and `angle`; `pi` and `tau` exist for the radians-minded, with `radians` and `degrees` to convert. Time is in seconds. A gamepad stick or `dpad` y of -1 is up, matching the screen.
- **Defaults.** Window 800 × 600, background light grey (230), fill white, stroke off, thickness 1, `fps` 60, font rocinante's default (§4.8). The first `window` call replaces the default window; a sketch that never calls `window` gets the default one.
- **Names.** Every built-in name is reserved, and so are the connecting words. A variable or `learn` parameter named like a built-in verb is a load-time error that suggests another name; `width`, `height` and `size` are the exception, because they are values and connecting words together (§5.1) and may be used as parameter names. The reserved-word list is generated from the core and published in the docs.
- **`copy`** is deep: lists and records inside are copied too (§5.11).
- **Spelling.** Language words use US spelling (`color`, `colorpicker`, `gray`, `center`); prose, comments and docs may use British. The checker accepts `colour` and `grey` as friendly errors that name the right word.
- **Runtime failures** (non-negotiable 3). An index out of range or a division by zero shows the overlay and gives an empty value or 0, and the sketch continues. Recursion deeper than a fixed limit raises an overlay error in both back ends, so compiled code never overflows the stack. In the interpreter a watchdog stops a `draw` block that runs far too long, keeps the last good frame and explains. Packaged sketches log these errors instead of drawing an overlay.
- **Mixed 2D and 3D** (§4.3). In one `draw`, a 2D verb after a 3D verb draws in screen space on top of the 3D scene. The default mouse orbit steps aside while the mouse is over a widget or when the sketch reads the mouse.

---

## 6. Feature parity map

Goal: everything the core and standard add-ons of Processing, openFrameworks (0.12.1) and Cinder do, in rocinante words. The rows below were verified on 2026-10-24 against the official references (see "Verification" after the table); rows are completed phase by phase, and updated here, in place.

| Area | Processing | openFrameworks | Cinder | rocinante (draft verbs) | Phase |
|---|---|---|---|---|---|
| Window, app loop | `size`, `fullScreen`, `windowMove`, `windowTitle`, `windowResizable`, `frameRate`, `settings`, `loop`/`noLoop`, `redraw`, `exit` | `ofAppRunner`, `ofBaseApp`, `ofMainLoop`, multi-window via `ofCreateWindow` | App, Window | `window` (a window can be resized and moved after it opens), `title`, `fullscreen`, `fps`, `vsync`, `draw`, `pause`, `resume`, `quit`; window events `on resize`, `on move`, `on focus`; `fixed step` for a fixed time step (§4.7, §9) | 1 |
| Display | `displayWidth/Height`, `displayDensity`, `pixelDensity`, `cursor`, `noCursor`, `smooth` | screen size, `ofHideCursor` | Display | automatic HiDPI, `screens` (every connected display, with `width`, `height`, `density`), `cursor`, `smooth` (on by default; `no smooth` for pixel art), `orientation` on mobile | 1 |
| 2D primitives | `arc`, `circle`, `ellipse`, `line`, `point`, `quad`, `rect`, `square`, `triangle` | ofGraphics draw functions | 2D Graphics | same names | 1 |
| Style | `fill`, `noFill`, `stroke`, `noStroke`, `strokeWeight`, `strokeCap`, `strokeJoin`, `ellipseMode`, `rectMode`, `push`/`pop` | `ofSetColor`, `ofFill`, `ofSetLineWidth` | gl::color | `fill`, `no fill`, `stroke`, `no stroke`, `thickness`, `alpha`, `caps`, `joins`; per-element style words; `with … [ ]` and `push [ ]` scopes; named styles as records; gradients (`fill [ red teal ] angle 90`, `as radial`, `as conic`) (§5.9) | 1 |
| Color | `color`, `colorMode`, `lerpColor`, `red`/`green`/`blue`/`alpha`, `hue`/`saturation`/`brightness`, `background`, `clear` | `ofColor` | Color | CSS names (`red`), hex (`#ff8800`), grey number, `rgb`, `hsb`, `oklch`, `alpha`, `mix`, `background`, `clear`; channels 0–255 (§5.9). Because `red`, `green` and `blue` are colour names, a colour's channels are read as fields (`c.r`, `c.g`, `c.b`, `c.a`) and `hue c`, `saturation c`, `brightness c` are verbs | 1 |
| Transform | `translate`, `rotate`, `rotateX/Y/Z`, `scale`, `shearX/Y`, `applyMatrix`, `pushMatrix`/`popMatrix`, `resetMatrix` | `ofTranslate`, `ofRotate`, `ofScale`, `ofNode` | gl::translate etc. | `move`, `turn`, `grow`, `shear`, block-scoped with `push [ ]` | 1 |
| Shapes and curves | `beginShape`/`vertex`/`endShape`, contours, `bezier`, `bezierVertex`, `curve`, `curveVertex`, `quadraticVertex`, detail/tightness, `PShape`, `createShape` | `ofPath`, `ofPolyline` | Path2d, Shape2d | `shape [ ]`, `vertex`, `bezier`, `curve`, `hole [ ]`, `path`, `polyline` with resample/smooth/simplify; `point on` a curve or bezier at a position along it, and its direction there (Processing's `bezierPoint`/`bezierTangent`) | 1 to 3 |
| Turtle | (none) | (none) | (none) | `forward`, `back`, `left`, `right`, `pen up/down`, `home`, 3D turtle | 2 |
| Math | `map`, `lerp`, `constrain`, `dist`, `mag`, `norm`, trig, `degrees`/`radians`, `PVector`, constants `PI`/`TAU` | ofMath, glm | Vec, Matrix | `map`, `mix`, `clamp`, `dist`, `{ x, y }` vector literals, the usual number verbs (`abs`, `ceil`, `floor`, `round`, `sqrt`, `pow`, `exp`, `log`, `min`, `max`, `sign`, `fract`), trig, `pi`, `tau`; named vector verbs `dot`, `cross`, `normalize`, `limit`, `heading`, `rotate`, `angle between`; quaternions in 3D (`slerp`) | 1 |
| Randomness, noise | `random`, `randomGaussian`, `randomSeed`, `noise`, `noiseSeed`, `noiseDetail` | `ofRandom`, `ofNoise` | Rand, Perlin | `random`, `random from … to …`, `anywhere`, `pick`, `gaussian`, `seed`, `noise` (Perlin, simplex, 1 to 4D), `fbm` | 1 |
| Time, animation | `millis`, `second`…`year`, `frameCount`, `delay` | `ofGetElapsedTimef`, `ofGetFrameNum` | Timeline, Tween, easing | `time`, `frame`, `clock`, `tween`, `ease`, `every` | 2 |
| Input | mouse vars and callbacks, `pmouseX`, keyboard vars and callbacks, `mouseWheel` | mouse, key, touch, drag-and-drop events | Mouse/Key/Touch events | `mouse`, `pmouse`, `key`, `touches`, `wheel`, `on …`, dropped files | 1 to 2 |
| Events, messages | (none in core) | `ofEvent`, `ofSendMessage` | signals | `send`, `on … receive`, custom events | 2 |
| Typography | `text`, `createFont`, `loadFont`, `textFont`, `textSize`, `textAlign`, `textLeading`, `textWidth`, `textAscent`/`Descent` | `ofTrueTypeFont` | TextBox | `text`, `font`, `align`, `leading`, `measure`, text along a path, text to shapes | 3 |
| Images, pixels | `PImage`, `loadImage`, `requestImage`, `image`, `imageMode`, `tint`, `get`/`set`, `pixels[]`, `filter`, `mask`, `blend`, `copy` | `ofImage`, `ofPixels`, `ofTexture` | Surface, Channel, ImageIo | `image`, `load`, `tint`, `pixel`, `pixels`, `filter`, `mask`, `crop`, `resize` (GPU-side); images, video and canvases as shape fills (`as cover`, `fit`, `stretch`, `tile`, `center`, §5.9) | 3 |
| Offscreen, blending, clipping | `createGraphics`, `PGraphics`, `blendMode`, `clip`/`noClip` | `ofFbo` | gl::Fbo | `canvas`, `draw into c [ ]`, `blend`, `clip` | 3 |
| Shaders | `PShader`, `loadShader`, `shader`, `resetShader` | `ofShader` | GlslProg | `shader` (hot-reloaded), post effects (`blur`, `glow` …) as built-ins | 3 |
| 3D primitives, meshes | `box`, `sphere`, `sphereDetail` | `of3dPrimitive`, box/cone/cylinder/icosphere/plane/sphere, `ofMesh` | geom:: | `box`, `sphere`, `cone`, `cylinder`, `capsule`, `plane`, `icosphere`, `torus`, `mesh` (with `texture`), `wireframe`; helpers `grid`, `axes`, `arrow` (openFrameworks' `ofDrawGrid`, `ofDrawAxis`, `ofDrawArrow`) | 4 |
| Camera | `camera`, `perspective`, `ortho`, `frustum`, `beginCamera`, `screenX/Y/Z`, `modelX/Y/Z` | `ofCamera`, `ofEasyCam`, `ofNode` | CameraPersp, CameraUi | `camera`, `orbit` (default), `look at`, `ortho`, `screen point`, `world point` | 4 |
| Lights, materials | `lights`, `ambientLight`, `directionalLight`, `pointLight`, `spotLight`, falloff, specular, `ambient`, `emissive`, `shininess`, `specular` | `ofLight`, `ofMaterial` | gl lighting via shaders | `light` (ambient/sun/point/spot, with falloff and specular as connecting words), `no lights`, `material` (PBR by default), `shadows` | 4 |
| Model and vector import | `loadShape` (SVG, OBJ) | ofxAssimpModelLoader, ofxSvg | ObjLoader | `model "x.glb"` (glTF first, `vendor:cgltf`), `svg` | 4 |
| Sound | (Sound library) | `ofSoundPlayer`, `ofSoundStream`, `ofSoundBuffer` | audio:: node graph | `sound`, `play`, `loop`, `volume`, `synth`, `listen` (mic), `fft`, `level`, effects | 5 |
| MIDI, OSC | (libraries) | ofxOsc (core add-on), ofxMidi (contributed) | (blocks) | `midi in/out`, `osc send/listen` | 5 |
| Printing, logging, text, maps | `print`, `println`, `join`, `split`, `trim`, `match`, `IntList`/`StringDict`/`FloatDict` | `ofLog`, `ofLogToFile`, `ofSplitString`, `ofJoinString` | `app::console`, `CI_LOG_*` | `print`, `log` (`log to "file.txt"`), text verbs, `map` (§5.15); list verbs `add`, `remove`, `count`, `reverse`, `sort`, `slice` (Processing's `subset`), `join`, `split`, `match`; number formatting `format` (Processing's `nf`, `nfc`, `nfs`, `nfp`), `hex`, `binary` | 2 |
| Files, data | `loadStrings`, `loadBytes`, `loadJSON*`, `loadTable`, `loadXML`, `save*`, `createWriter`, `selectInput`/`Output`/`Folder` | `ofFile`, `ofDirectory`, `ofJson`, `ofXml`, system dialogs | DataSource | `load`, `save` (format from extension), `ask file`, `ask folder`, `files in`, `open` (a URL or file in the system's own program, Processing's `launch`), `clipboard`; JSON, CSV and TSV tables (as lists of records), XML (as records) and plain text all come from `load`, with record shapes taken from the file (§5.3) | 6 |
| Network | (Net library) | ofxNetwork, URL loader | (blocks) | `fetch`, `udp`, `tcp`, `websocket` | 6 |
| Serial, hardware | (Serial library) | `ofSerial`, `ofArduino` (Firmata) | (blocks) | `serial`, `firmata` | 6 |
| Video, camera input | (Video library) | `ofVideoPlayer`, `ofVideoGrabber` | video:: | `movie` (platform frameworks plus dav1d, libvpx, pl_mpeg; §4.11), `webcam` (SDL3 camera API) | 6 |
| UI, parameters | (contributed: controlP5 and others) | ofxGui, `ofParameter`, ofxImGui | params::, Cinder-ImGui | built-in `ui [ ]` blocks with `button`, `slider`, `range`, `knob`, `toggle`, `number`, `textbox`, `dropdown`, `choice`, `colorpicker`, `xypad`, `list`, `progress`, `label`, panels, rows, tabs, menus, tooltips; values remembered per sketch; screen-reader support (§4.8, §5.8) | 3 |
| Sensors, gamepads, joysticks | (none) | iOS/Android add-ons | (platform) | `tilt`, `compass`; `gamepad`, `gamepads`, `joysticks`, `bind`, `press`, `held`, `direction`, `rumble`, `controls` widget (§5.12) | 6 |
| Output, export | `save`, `saveFrame`, `beginRecord`/`beginRaw` (PDF, SVG) | screen grab, Cairo renderer | ImageIo | `save "x.png"`, `record` (frames/video), `export svg`/`pdf` | 3 and 6 |
| Collision | (none in core) | (contributed add-ons) | (blocks) | `touching`, `contact`, `hits`, `inside`, `cast`; 2D physics with `simulate`, `fixed`, `gravity`, `kick`, `join` (§5.13) | 2 (2D), 4 (3D), 6 (physics) |
| Machine learning | (none in core; ml5.js for p5.js) | (contributed add-ons) | (blocks) | `poses`, `hands`, `faces`, `objects`, `labels`, `cutout`, `predict` on LiteRT; PyTorch and JAX models through conversion (§4.10) | 6 |
| Computer vision, depth | (OpenCV library) | ofxOpenCv, ofxKinect | (blocks) | extension libraries, after the first stable release | 9 |

### Verification (2026-10-24)

**What was read.** Processing: the whole reference index (processing.org/reference), every category. openFrameworks: the documentation index (openframeworks.cc/documentation), modules 3d, application, communication, events, gl, glm, graphics, math, sound and types. The `utils` and `video` modules, and the end of `types`, were cut off in the fetch, so those two are checked from knowledge of the library, not from the page; the page also does not state its version, so "0.12.1" is unverified. Cinder: the namespace list and class list (libcinder.org/docs), which have names but no descriptions.

**What the check changed.** The rows above now name the Processing index items that rocinante means to offer, which were missing before: list and text utilities, number formatting, `PVector` methods, curve points and tangents, window events, displays, `launch`, `noLights`, lighting falloff and specular, texturing. From openFrameworks: `ofDrawGrid`, `ofDrawAxis`, `ofDrawArrow`, vertical sync, orientation, clipboard, the fixed time step modes (`ofSetTimeModeFixedRate`). From Cinder: `Capsule`, multiple displays. It also found a clash: Processing's `red(c)`, `green(c)` and `blue(c)` cannot be verbs because `red`, `green` and `blue` are colour names; channels are fields instead.

**Not offered as such, by design.**
- Processing's Java language (classes, `extends`, types, `try`, `null`) and its stream and reader classes (`createInput`, `BufferedReader`, `PrintWriter`): rocinante has `load` and `save` and no types or exceptions (§5.2).
- `thread()` and openFrameworks' `ofThread`: users never see threads (§4.4); the core decides.
- `hint()` and openFrameworks' GL classes (`ofVbo`, `ofBufferObject`, renderers, window-settings classes): GPU details stay out of sight (non-negotiable 2); batching and instancing are automatic.
- Cinder's `cairo`, `qtime`, `dx` and `winrt` namespaces: `export svg`/`pdf` and the platform video frameworks (§4.11) cover them.
- Cinder's `Arcball` and `CameraUi`: the default orbit camera (§4.3). Cinder's `Ray`, `AxisAlignedBox` and frustum types: the collision verbs (§5.13). Cinder's `Teapot`: not offered.

**Decided on the way** (2026-10-24): alignment modes become the origin words `as center` and `as corner` (§5.9), and Escape does not quit a sketch (`ofSetEscapeQuitsApp`), because it already leaves the widgets (§4.8).


