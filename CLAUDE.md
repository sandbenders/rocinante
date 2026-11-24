# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

This file and `docs/design.md` (read the section a task touches: it is not imported, see the index below) are together the single source of truth for rocinante's design, scope and plan. When a decision changes, update the file that holds the section, in place. Do not create other design documents, changelogs of decisions or "notes" files beside them. `docs/phases.md` is the one exception, and holds no decisions: the history of the closed phases (what they built, measured and found), kept out of this file so it stays short. `MANIFESTO.md` is the public statement of intent; this file is how we build it.

Read `MANIFESTO.md` before starting any work. Every decision below serves it.

## Start here

- `main` moves between sessions and other work lands without this file being re-read: run `git fetch` and read `git log --oneline origin/main -20` before trusting anything below.
- Branch first, never commit on `main`, never push (§3). Fabrizio pushes, opens the merge request and merges. When he says a branch is merged, check `git rev-list --count origin/main..<branch>` is 0, fast-forward `main` and delete every merged local branch with `git branch -d`, without waiting to be asked (decided 2026-10-28).
- Run `odin run build -- ci --fast` before handing a branch over; the full `ci` (the `-o:speed` repeat, golden images, the C ABI build) is left to the pipeline (decided 2026-11-14), except that a change to the renderer or a drawing default still needs `odin run tests/golden` by hand.
- Phases 0 to 5 are closed (§8; `docs/phases.md` has what each built and measured); the code map is `§4.13` in `docs/design.md`, and Odin is `dev-2026-11`.
- **Known unverified**, so do not call them done on this Mac's say-so: `rumble` on macOS and FreeBSD (no pad shakes on either, while every pad with motors shakes on Linux), gamepads on Windows and, on OpenBSD, any pad but the Logitech Dual Action (checked 2026-11-23 on OpenBSD 8.0: sticks, triggers and buttons work, the d-pad does not, because SDL's OpenBSD joystick driver sets a hat switch and at once sets it back to the middle; `docs/building.md` has it) (the Mac was checked 2026-11-16 with four pads, FreeBSD 2026-11-20 with five over USB: PS4 needed a mapping fix, PS5 and Logitech work, none of them shakes, and Xbox One and Series pads get no driver there; Linux 2026-11-22 with the same five on CachyOS: all work and every one with motors shakes), the phones' MIDI, microphone, recording, on-screen keyboard and screen readers (Phase 8), and `fps` (2026-11-24) on a 120 or 144 Hz screen of each system, on the phones and the evenness of its sleep on Windows. The release checklist lists the hand checks.
- To run one test, `odin test <dir> -define:ODIN_TEST_NAMES=<package>.<test_name> -out:output/tests/<name>`: the package name is the one on the test file's `package` line, which is not always the folder (`cli` is `main`).

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
odin run cli -- run examples/garden/sketch.roci [--frames N --screenshot out.png --window 2 --seed N --errors json --stats --no-vsync --compile [--debug] [--target ios|android [--device id] [--team id]]]   # run a sketch in the language (a folder runs its sketch.roci; --stats times the frames, shows a box with the frame and the frame rate and adds a line to artifacts/log.json, and --no-vsync lets a window run as fast as it can; --compile turns the sketch into Odin, builds it with the pinned Odin and runs that program in the terminal, from `artifacts/<system>/<release|debug>/`: Phase 7's compiler, for the subset of the language `roci/codegen` covers, and it refuses a sketch that uses more); with --frames, headless
odin run cli -- check <file or folder> [--types --tree --errors json]   # parse and check, and say every mistake
odin run cli -- fmt [file or folder]          # write sketches in the house style; no name means every .roci file here
odin run cli -- man [word]                    # how a verb or statement is written, made from the registry
odin run cli -- test [folder or file] [--accept [--frames N] [--seed N]]   # run the checks of a sketch and compare its picture with tests/snapshot-1.png; --accept stores the picture
odin run cli -- package macos [folder] [--name n --id id --version v --icon file --sign identity --notarize profile --format dmg,zip|all --yes]   # make a Mac app of a sketch in output/package/macos (a disk image by default, since 2026-11-23; --format zip or all): asks name, id and version once (sketch.toml), makes every system's icons from icons/icon.svg or icon.png into icons/ (--icon puts a picture there), builds the libraries it carries (tools/package-libs.sh macos, once), compiles, bundles, signs, tries it and zips it
odin run cli -- package linux [folder] [--format tar,deb,rpm,arch,appimage|all --maintainer "Name <address>" --description text --category Game; --name n --id id --version v --icon file --yes]   # make a Linux app of a sketch in output/package/linux: a .tar.gz, a .deb, an RPM, an Arch package or an AppImage (by --format, the plain tar by default); only on Linux, and tried in a container from a Mac with `docker run --platform linux/amd64 rocinante-linux` (see docs/building.md)
odin run cli -- package freebsd [folder] [--format pkg,tar|all --maintainer "Name <address>" --description text; --name n --id id --version v --icon file --yes]   # make a FreeBSD app of a sketch in output/package/freebsd: a .pkg for `pkg add` and a .tar.gz (both by default); only on FreeBSD, nothing carried (the package depends on the ports holding SDL3, SDL3_ttf, shaderc and SPIRV-Cross)
odin run cli -- package openbsd [folder] [--format pkg,tar|all --maintainer "Name <address>" --description text; --name n --id id --version v --icon file --yes]   # make an OpenBSD app of a sketch in output/package/openbsd: a .tgz for `pkg_add -D unsigned` (made by the base system's pkg_create) and a .tar.gz (both by default); only on OpenBSD; the app carries its own SDL3_ttf (no package exists for it; built once by tools/package-libs.sh openbsd) and the package depends on the packages holding SDL3, shaderc and SPIRV-Cross
odin run cli -- package android [folder] [--name n --id id --version v --icon file --format apk,aab|all --yes]   # make an Android app of a sketch in output/package/android: a signed APK to `adb install -r` (and with `--format aab` or `all` the Android App Bundle for Google Play, made with bundletool and Google's aapt2, fetched by `tools/fetch-bundle-tools.sh` with their checksums checked), with its id, name, version and icon, and the orientation and category of sketch.toml (`orientation = "portrait"`, `[android] category = "game"`); its release key is made once in rocinante's own folder outside the sketch (keep a copy: only it can sign an update); needs the phone's tools as `--target android` does (the SDK and NDK, `tools/mobile-sdl.sh android`); the App Bundle for Google Play comes later
odin run cli -- package ios [folder] [--name n --id id --version v --icon file --team id --app-store --upload --yes]   # make an iPhone app of a sketch in output/package/ios: the app and an .ipa, with its id, name, version, icon, orientation and `launch-colour` of sketch.toml, signed by Xcode with the development team (a free account works: seven days); only on a Mac, needs Xcode and the phone's libraries (built on first use)
odin run cli -- package windows [folder] [--format setup,zip,msix|all --sign certificate --description text; --name n --id id --version v --icon file --yes]   # make a Windows app of a sketch in output/package/windows: an installer for everyone (setup.exe, rocinante's own, roci/install; /S installs silently) and a zip by default, of the app's folder (no console, icon, version and manifest inside, SDL3.dll and SDL3_ttf.dll from the pinned Odin) zipped, and with `--format msix` an MSIX made by makeappx; signed by signtool with the code-signing certificate in the user's store (or the one --sign names); only on Windows
tools/ci/package-linux-distros.sh <sketch folder> [debian] [ubuntu] [fedora] [arch] [-- options]   # the Linux packages made on Debian 12 (.deb and AppImage), Ubuntu 24.04 (.deb), Fedora 43 (RPM) and Arch (its package) in Podman or Docker, the first three for older computers, into the sketch's output/package/linux-<name>
odin run cli -- new <name> | init | add <file>   # a sketch folder, its files in this folder, a file into assets/
odin run cli -- get <git address> [--as name] | update [name]   # copy a library into libs/ from git, and fetch newer copies (run in a sketch folder)
ROCI_UPDATE_TREES=1 odin test roci/interp      # write tests/ui-tree/*.txt again: the screen-reader trees of the examples that have widgets (review them like code)
ROCI_UPDATE_ERRORS=1 odin test roci/lang      # write tests/errors/**/*.txt, tests/check/*.types and examples/*/sketch.types again (review them like code); roci/interp does the same for tests/errors/runtime (run both after a message changes, as a runtime message such as `Expect_Failed` is rendered by interp)
ROCI_GPU_DEBUG=1 odin run examples/shapes     # any program with GPU validation on (off by default)
ROCI_PASSES=off output/roci run <sketch>      # the interpreter with no optimisation pass: the reference the passes are compared with
odin run tests/golden [-- update | scene]     # golden images: scenes drawn offscreen, compared with tests/golden/*.png
odin run tools/header -- include/roci.h       # regenerate the C header from the registry (a test fails when it is stale)
odin run tools/site -- --logo                 # write the README's wordmark pictures and the logo's 192-pixel PNGs again from docs/logo/rocinante-logo.svg (a test fails when they are stale)
tools/abi-check.sh [--run]                    # build roci as a shared library, check its exports match the header, build the examples/c programs
shaders/compile.sh                            # HLSL to SPIR-V and Metal (glslang, spirv-cross); shaders/compile-dxil.sh makes DXIL on Windows
odin run spikes/codegen -- check              # Spike 3: interpret, generate Odin, build it, compare output
odin run spikes/codegen -- doctor [host]      # which targets this computer can build, and the toolchain
odin run spikes/mobile/macos                  # the phones' sketch on the desktop, 5 seconds
spikes/mobile/android/build.sh --install      # needs SDL_ANDROID_LIB and SDL_ANDROID_JAVA
SDL_ANDROID_LIB=... SDL_ANDROID_SRC=... spikes/mobile/android/libs.sh   # Dear ImGui, SDL3_ttf, shaderc, SPIRV-Cross, libcurl and the sound decoders for arm64 Android into .cache/android/lib (git, cmake, ninja), each built when missing or when a stamp in .cache/android/stamps says its sources changed; tools/mobile-android.sh runs it every time
SDL_IOS_LIB=... SDL_IOS_SRC=... spikes/mobile/ios/libs.sh   # the same for the iPhone into .cache/ios/lib (git, cmake, ninja, Xcode); tools/mobile-ios.sh runs it every time
spikes/mobile/ios/build.sh --install          # needs SDL_IOS_LIB, TEAM_ID and DEVICE
odin run build -- sound-libs                  # the sound decoders (miniaudio's and stb_vorbis from the vendor folder of the Odin on the PATH, and libopus fetched by tools/fetch-opus.sh with curl and tar) into .cache/sound; ci and docs build them when missing (needs cc, or MSVC on Windows)
odin run build -- net-libs                    # (tools/net-libs.sh ios | android builds them for the phones; the phones' libs.sh call it) libcurl and mbedTLS, static, HTTP(S) and web sockets only, fetched by tools/fetch-net.sh (curl and tar; checksums checked) and built by tools/net-libs.sh into .cache/net (needs cmake and cc; Windows uses Schannel and MSVC, not yet run); ci and docs build them when missing
sh tools/ui-libs.sh accesskit                 # fetch accesskit-c into .cache/ui/accesskit (curl and unzip; cargo and cmake where no release library exists); odin run tools/accesskit writes vendor/accesskit again
spikes/ui/setup.sh                            # Spike 4, once: Dear ImGui, dear_bindings and accesskit-c into .cache/ui (setup-windows.sh with MSVC)
odin run spikes/ui [-- interactive]           # Spike 4: slider, button, text box, and the screen-reader bridge on macOS
```

The phone scripts need SDL 3.4.18 built for the phone, which is not in the repository (the recipe is in the Phase 0 results in `docs/phases.md`).

**What `ci` does not cover.** `ci` type-checks and tests the build script, `tools/term`, Spike 3 and every package under `roci/`. The full `ci` (not `--fast`) also runs every package's tests a second time built with `-o:speed`, so the optimiser can never change a result unnoticed (non-negotiable 7), and runs the golden images and `roci test examples/checks` on lavapipe (`build/golden.odin`), skipping them with a note where lavapipe is missing and failing instead when `ROCI_REQUIRE_LAVAPIPE` is set, as both pipelines do. It type-checks the examples, `tests/golden` and the phones' sketch. It does not run anything else that needs a window, a GPU, a phone, or the libraries `spikes/ui/setup.sh` builds: example runs, golden images on real GPUs, the phone spikes, Spike 4 and the SDL window code are checked by hand, and a change to them needs a hand run on the affected systems before it is called done.

**On Windows** (Direct3D 12 only; no Vulkan SDK, shaderc or SPIRV-Cross is ever installed there): run `ci` and `ui-libs` from Git Bash started inside `vcvars64.bat` (the recipe is in the Windows gotcha below), because `ci` builds `.cache/ui/roci_ui.lib` with MSVC when it is missing and a plain `cmd` has no `sh`. After an Odin upgrade copy its `vendor/sdl3/SDL3.dll` into the repository root again (and beside `output/roci.exe` to run that). Lavapipe does not exist there, so `ci` skips the golden step and `roci test examples/checks` with a note; `odin run tests/golden` by hand draws on Direct3D 12 against the looser limits for a real GPU, and a few dozen edge pixels off in a dozen or so pictures (and thousands in `example_rays_1`, whose hairlines make a moiré) is the GPU, not a fault; read the scenes that matter for the change (`effects`, `shader_fills`) and check its first line says `direct3d12`.

**Terminal output** is coloured through `tools/term`: every command that prints for people, including `doctor`, paints headings, results and errors with it and marks results with ✅, 🚫 and ❌ (`term.out_icon`). Colour is on only when the stream is a terminal and `NO_COLOR` is unset, the words are identical with or without it, and piped output and the pipelines stay plain. New commands use `term.out` and `term.err`, never raw escape codes, and anything that takes more than a moment (compiling, packaging, building libraries, putting a sketch on a phone) shows its steps through `term.progress_*` (the code map entry for `tools/term`), naming them in plain words with no tool's name in them.

**Where things are.** This file holds the rules, the plan and the decisions; `docs/design.md` holds the architecture details, the language and the parity map; section numbers are global, so `§5.9` is in `design.md` and `§8` is here. `spikes/` is throwaway Phase 0 code, not the planned packages. The real packages (§4.2) are created as their phase needs them: `roci` (the public API), `roci/maths`, `roci/registry`, `roci/platform`, `roci/geom`, `roci/gfx`, `roci/lang` (the language front end, started in Phase 2), `roci/interp` (the interpreter), `roci/collide` (2D collision detection), `roci/audio` (the mixer), `roci/osc` (OSC packets), `roci/folder` (sketch folders and their assets), `roci/install` (the Windows installer's archive and words; its program is `roci/install/setup`) and `cli` (the `roci` binary) exist, all in `TEST_PACKAGES`; `vendor/` holds sancho (above) and our own bindings (`vendor/sound` is the sound decoders); the rest of the language packages come later. Each new package updates this paragraph and the code map below in the same commit, joins `TEST_PACKAGES` and says which spike it replaces. `output/` and `.cache/` are generated and ignored by git.

**The code map** (the invariants, traps and why of every package: read the entry of a package before changing it) is `§4.13` in `docs/design.md`. The packages are `roci` (the public API and C ABI), `roci/maths`, `roci/registry` (the data the language is made from), `roci/lang` (front end, no GPU), `roci/interp`, `roci/gfx` (drawing, no GPU), `roci/platform` (SDL), `roci/audio`, `roci/ui`, `roci/collide`, `roci/geom`, `roci/folder`, `roci/osc`, `roci/toml`, `roci/install`, `cli`, `vendor/` (our own bindings and the sound decoders) and `tools/` (the site, the header, the generators). A new package updates that section and `TEST_PACKAGES` in the same commit.

**Shell and tool gotchas** (these have all cost time):
- Fabrizio's `ls` is an alias for `eza` and adds colour codes, so scripts and anything piped must use `command ls`. Use `rg`, not `grep`, in anything written for him; portable scripts that contributors run (hooks, CI) use POSIX tools.
- macOS has no `timeout`, and BSD `sed` (macOS, FreeBSD, OpenBSD) needs `-i ''`. A replacement holding backticks does not survive `sed` in a shell variable: splice the line with `head` and `tail`, or use the edit tool.
- **macOS and lavapipe** (checked 2026-11-05, macOS 26, Apple silicon): `brew install mesa` builds Mesa's software Vulkan (`swrast`, which is lavapipe) and puts its manifest in `/opt/homebrew/share/vulkan/icd.d/lvp_icd.aarch64.json`; the golden step of `ci` finds it there and tells SDL where Homebrew's Vulkan loader is (`SDL_VULKAN_LIBRARY`, because macOS does not look in `/opt/homebrew/lib`), and every reference matched to 0 pixels off against the Linux ones, so references may be drawn on a Mac too. By hand: `VK_DRIVER_FILES=/opt/homebrew/share/vulkan/icd.d/lvp_icd.aarch64.json SDL_VIDEODRIVER=offscreen SDL_VULKAN_LIBRARY=/opt/homebrew/lib/libvulkan.1.dylib odin run tests/golden`. The `kosmickrisp` manifest beside it is Vulkan on Metal, a real GPU, and is not used.
- **FreeBSD and lavapipe**: Mesa's driver manifests are in `/usr/local/share/vulkan/icd.d/` (`lvp_icd.x86_64.json`), not `/usr/share/vulkan/icd.d/`, so the `VK_DRIVER_FILES=$(command ls /usr/share/...)` commands above find nothing there. Set `VK_DRIVER_FILES=/usr/local/share/vulkan/icd.d/lvp_icd.x86_64.json SDL_VIDEODRIVER=offscreen` by hand. **`ci` reports the golden step `ok` when lavapipe is not found** (it skips with a note, and fails only when `ROCI_REQUIRE_LAVAPIPE` is set), so after any change to a drawing default or the renderer run `odin run tests/golden` yourself and read its last line (`golden: N pictures, 0 failed`).
- **FreeBSD and gamepads** (checked 2026-11-20): SDL reads them from `/dev/input/event*`, which are `root:games` mode 0660, so the user must be in `games` (`pw groupmod games -m <user>` as root, then log in again) or SDL sees nothing. SDL's own mapping for a pad can be wrong for FreeBSD's kernel drivers (the DualShock 4's was): read the real layout with `EVIOCGABS` and `EVIOCGBIT` on the node, since SDL numbers axes and buttons in key-code order, and `roci/platform/pads.odin` holds the fix. **Never run SDL as root with an Xbox One or Series pad plugged in and `SDL_JOYSTICK_HIDAPI_XBOX_ONE=1`**: its driver freezes the program inside the event handling, Ctrl+C does nothing (SDL turns it into a quit event) and only `kill -9` ends it; wrap any such experiment in `timeout -s KILL 30`.
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
- **A string SDL gives is SDL's, not ours**: `SDL_GetBasePath` returns a string that `SDL_Quit` frees, and a window that fails to start quits SDL before the retry on another video driver (on OpenBSD, Wayland and then X11), so a program that keeps one for its whole run keeps a copy first (`rt.use_home` does, since 2026-11-23). It showed on OpenBSD 8.0 as every font, shader and picture of a packaged app "not in the assets folder", because the string then read `MAIL` and the path of the user's mailbox, memory that OpenBSD's allocator had reused; a headless run never starts a window, so it never showed there. Whether another system kept reading the freed text by luck was not checked.
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
- Only keywords and grammar words are reserved (`roci man words`); a name that is also a verb or value (`count`, `row`, `start`) reads as the name where a value is due and the verb still wins at the start of a line, so after `count = 0` a `count herd` in a value position is no longer the verb (an error says so): keep to `n` when a sketch also uses the verb.

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
  README.md            what rocinante is and where its documentation is: a short page that links, never lists (§11)
  CONTRIBUTING.md      a pointer to README's Building and contributing section, for GitHub and GitLab to show
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
    install/           the Windows installer: its archive and words (package install) and its program (install/setup)
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
  docs/                design.md (architecture details, the language, parity map, the code map; not imported),
                       logo/rocinante-logo.svg (the logo: the one drawing its copies are made from),
                       grammar.ebnf (the language's grammar, written in Phase 2, §5.14),
                       phases.md (the history of the closed phases; not imported),
                       building.md (what to install on each system, and the commands for trying rocinante),
                       release checklist and contributor docs
  ODIN_VERSION         the pinned Odin release, read by the build script and both pipelines
  .gitlab-ci.yml       GitLab pipeline (§11)
  .github/workflows/   GitHub pipeline (§11)
```

Package boundaries can change; record the change here.

**Where the sections of `docs/design.md` are** (section numbers are global; this file is §1 to §4.2 and §7 to §12):

| § | Topic |
|---|---|
| 4.3 | rendering: commands, shaders, text, pictures, pixels, export, vector tessellation, 3D |
| 4.4, 4.5 | threads; windows and messaging |
| 4.6 | audio: files and formats, analysis, instruments, MIDI, OSC, effects, recording |
| 4.7 | the execution model: front end, interpreter, code generation, optimisation passes |
| 4.8 | the interface: Dear ImGui, widgets, screen readers |
| 4.9, 4.10, 4.11 | sketch folders and assets; machine learning; video |
| 4.12 | the documentation site and the CI tools |
| 4.13 | the code map, package by package |
| 5.1 to 5.19 | the language: syntax, paradigm, typing, program model, turtle, errors, widgets, style and color, libraries, `learn`, controllers, collision, notes, details, checks, remembering, scenes, data files |
| 6 | the feature parity map |

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

  When this computer cannot build a target, `roci doctor` says so first, in plain words, before looking for tools, and names the computers that can: for example, "iOS apps can only be built on a Mac, because Apple's tools only run there." (The line above it already says what this computer is, so the message does not repeat it.) `roci package <target>` refuses with the same message instead of failing halfway through, and `roci doctor` marks each of the seven targets as ready, missing something (with the install steps), or not buildable here. Phase 8 tests this for every host and target pair (§9).
- **Signing and trust** (decided 2026-10-24). macOS packages are signed with a Developer ID and notarised, and Windows packages are signed where the user has a certificate; `roci package` says plainly what SmartScreen or Gatekeeper will still show when they have none. `roci` shows the Android SDK licence and asks for acceptance before fetching it.
- Every target bundles the compiled sketch, all of `assets/` and `libs/`, `ui.toml` and compiled shaders (§4.9), under the name, id, icon and version in `sketch.toml`, whose build number `roci package` raises by one each time. No network access needed at runtime.

---

## 8. Phases

Each phase ends with a demo sketch, a green Linux pipeline (§11), the release-checklist run on the other platforms that the phase touches, and an update to this file.

### Phases 0 to 4 (closed)

**Phase 0, foundations** (done 2026-10-27): the repository, the build script and its `ci` command, the hooks, both pipelines, the licence check and the unit tests, and four throwaway spikes that tested the riskiest assumptions (an SDL3 GPU window on every desktop, a shader circle on a real iPhone and Android phone, a typed IR interpreted and turned into Odin, Dear ImGui with a screen reader). **Phase 1, the window and 2D core in Odin** (done 2026-10-27): windows, the renderer with batching and instancing, every 2D shape, style, gradients and transforms, colour, noise and input, the verb registry and the C ABI, headless rendering and golden images; 100,000 circles a frame at about 60 fps, on iOS and Android too. **Phase 2, the language** (done 2026-10-30): the front end, the interpreter, `roci run`, `check`, `fmt`, `man`, sketch folders, libraries, input, the turtle, collision, tweens, tables and an example for every feature, closed after the newcomer test confirmed the design. **Phase 3, text, UI, images, canvases, shaders** (done 2026-11-14): text on SDL_ttf, pictures, pixels, canvases, fills, `blend`, `clip`, user and built-in shaders, export to PNG, SVG, PDF and movies, the widgets with `ui.toml`, and screen readers on every desktop; closed with ten Processing ports and `examples/studio` checked by hand with screen readers, touch and an input method. **Phase 4, 3D** (done 2026-11-14): the solids, the camera, lights, materials and shadows, glTF and OBJ models, pictures on solids, the turtle in space, collision in space, `mesh` with wireframes and SVG import, all in C too; closed with `examples/voyage` on the five desktop systems, the phones moved to Phase 8.

What each one built, its measurements and findings, and how it met its exit are in `docs/phases.md`.

**Still open from the earlier phases** (Phase 5's are in its summary above): `vendor:sdl3` or our own bindings (decide the first time a newer function is needed); the trademark search; the unchecked dependency platform lists; offers to make upstream (Odin's `for x in m[key]` crash on a missing key, its `os.Walker` leaving a folder open on Windows, `SDL_main` as an import in `vendor:sdl3`, the bindings gaps). From Phase 3: video and webcam fills (with Phase 6's video), shaped clips and masks beyond `mask by`, named styles holding a picture, the `ui` accent, font and size verbs, and custom widgets. From Phase 4: nodes, `wireframe` on the solids and models, per-corner colors and textures on a mesh and indexed meshes, a shape's alpha in 3D, a gradient on a solid, 3D inside `draw into`, reading the space turtle, an extruded `svg` and text as outlines. The phones' parts of both are in Phase 8. `spikes/` is throwaway; the packages in §4.2 are created as phases need them.

### Phase 5: Sound (closed)

**Phase 5, sound** (done 2026-11-15): sound files decoded whole or, past 30 seconds, streamed from the disk or memory with a buffer size per sound; `level`, `bands` and `mic`; instruments (`synth`) with an envelope and SoundFonts; sixteen effects; MIDI in and out (our own backends on every desktop system); OSC; and recording what plays to a file (`record speakers "take.wav"`, WAV by rocinante, the other formats through the user's ffmpeg); all in the C API too. Exit met: a MIDI controller drives an audio-visual sketch, about 8.7 ms from a key to its sound on Linux (measured, in `docs/phases.md`). All of it is our own code over miniaudio's decoders; `vendor:portmidi` was turned down. Carried on: MIDI, the microphone and recording on the phones (Phase 8; their sound plays), and checking by hand what could not be run here (WinMM and the BSDs' MIDI out, the Windows AAC decoder). Afterwards (2026-11-16): AIFF, Opus and AAC files and the whole SoundFont filter, LFO and modulator set.

### Phase 6: The world outside
Taken in this order (decided 2026-11-16):
1. Gamepads, joysticks, actions and the `controls` widget (§5.12): they sit on SDL3, which we already use, and they feed the exit game sketch.
2. Files and data formats, dialogs, network.
3. Webcam, video playback and recording (§4.11).
4. Serial and Firmata, sensors.
5. 2D physics on Box2D v3 worlds (§5.13).
6. The LiteRT spike (open question 1).
7. Machine learning (§4.10): LiteRT bindings, `predict`, the built-in tasks and their chosen models, `roci add` conversion, `roci doctor ml`.
- **Exit**: an installation-style sketch (camera in, OSC out, UI control window, runs for 24 hours without leaks); a webcam sketch driven by `hands` at full frame rate on all seven platforms; a game-style sketch played with two different gamepads, remapped by a player through `controls`.

### Phase 7: The compiler
**Started 2026-11-19**: `roci/codegen`, `roci/rt` and `roci run --compile` cover numbers, vectors, colours, text, lists, records, the control statements, taught verbs, `draw`, `every`, `on key` and `on mouse`, shapes, style and maths (scenes, messages between windows, the events of MIDI, OSC, UDP, TCP and web sockets and their verbs were added after; what is left is in `docs/design.md`'s code map); the equivalence suite compiles `tests/compile/*.roci` and compares what they print with the interpreter (`roci/builds`), and the golden harness compiles seven examples and judges their pictures against the interpreter's references. all 92 examples compile, byte-identical to the interpreted pictures (values of mixed kinds are boxes: `docs/design.md`'s code map entry for `roci/codegen`).
- `codegen`: typed IR → readable Odin source, built with the user's Odin together with the core, on all four desktop OSes.
- Lists of same-shaped records as contiguous arrays (or `#soa`); vector maths as Odin array programming; boxed fallback as tagged unions. The optimisation passes of §4.7 (blocks as plain loops, construction in place, bounds-check elimination, frame-local values on the stack or the arena) run here.
- Source mapping from packaged sketches back to `.roci` lines (§4.7).
- `roci doctor` complete for desktop toolchains.
- Packaging build time measured on each desktop OS, since the core is compiled with every sketch (§4.7); record it here.
- Back-end equivalence suite (§9) running every example in both modes in the Linux pipeline, and locally on the other platforms before each release.
- **Exit**: every example produces identical frames interpreted and compiled; the particle benchmark (100,000 records updated and drawn per frame) holds 60 fps compiled on a mid-range laptop, with the interpreted figure recorded here for comparison. Measure the particle benchmark with each optimisation pass off and on, and record the result here.
- **Measured 2026-11-19** (Apple M4 Pro, headless, so the CPU's share of a frame; 100,000 records, each moved, tested against the window's edges and drawn as a circle): interpreted 20.8 ms a frame with the passes on and 24.2 ms with them off; compiled 4.9 ms either way (the code generator does not read the passes' marks, since Odin does the work they exist for). `roci doctor` now says which targets this computer can build and which tools compiling a sketch lacks (`cli/doctor.odin`); packaging build times, source mapping into packaged sketches and the other desktop systems wait for Phase 8 and the release checklist.

### Phase 8: Packaging
- `roci package` for all seven targets (generate, build, bundle, sign where needed); `roci doctor` for every target.
  - **Linux next (2026-11-21):** `roci package linux` makes a `.tar.gz`, a `.deb`, an RPM (2026-11-22), an Arch package and an AppImage (`--format`), tried in a container; see the code map entry in `docs/design.md` for what was and was not tried.
  - **FreeBSD (2026-11-22):** `roci package freebsd` makes a `.pkg` (written by `roci` in `pkg create`'s format) and a `.tar.gz`, depending on the ports' libraries instead of carrying any; installed with `pkg add` and working with its icons and command (Fabrizio, 2026-11-22); another release and arm64 are untried (`docs/design.md` code map). Windows, Android and iOS are next.
  - **OpenBSD (2026-11-23):** `roci package openbsd` makes a `.tgz` (made by the base system's `pkg_create` from a packing list `roci` writes; unsigned, so `pkg_add -D unsigned`) and a `.tar.gz`; the app depends on the sdl3, shaderc and spirv-cross packages and carries its own SDL3_ttf in `lib`, since OpenBSD has no package for it. Made on OpenBSD 8.0 amd64 with `examples/circle` and `examples/bricks` (assets and sounds): `pkg_add -n -D unsigned` says it is ok and the unpacked program runs; Fabrizio then installed it with `pkg_add -D unsigned` as root and reported that it works (2026-11-23); **untried: `pkg_delete` after it, the menu entry and icons, the tar on a computer with nothing of rocinante, another release and arm64** (`docs/design.md` code map, `docs/release-checklist.md`). WILDVEX (assets, fonts, shaders, a vault) runs in a window from its package once the app keeps a copy of the folder SDL names as the program's (`rt.use_home`; the first package lost its assets to a freed string, found 2026-11-23). Done for OpenBSD amd64 on 8.0.
  - **Android (2026-11-23, the first target of issue 56):** `roci package android` makes a signed APK with the sketch's own name, id, version, icon, orientation and category (`orientation` and `[android] category` in `sketch.toml`), its files carried inside for the activity to unpack, and a release key of its own made once outside the sketch's folder; built by `tools/mobile-android.sh`, which also puts the test builds on a phone. Tried on a Mac and the Pixel 9: `examples/bricks` installed, started full-screen in portrait with its game in play, updated over itself and unpacked its sounds, and Fabrizio's WILDVEX (all its assets) installed and worked; **untried: the sounds heard on the phone, the first-start time of a big sketch, a Linux or Windows host, another phone or Android, the microphone and the camera on a phone, and the App Bundle that Google Play asks for (next)** (`docs/design.md` code map, `docs/release-checklist.md`). iOS and
  - **Windows (2026-11-23, the third target of issue 56):** `roci package windows` makes an installer of rocinante's own for everyone on the computer (`setup.exe`: Program Files, the Start menu, Settings, Apps, an `uninstall.exe`; `/S` and `/D=`), the app's folder and a zip, and with `--format msix` an MSIX package, signed with `signtool` when the user's certificate store has a code-signing certificate (`--sign` names one, kept in `[windows] certificate`). Tried on Windows 11 with `examples/circle`, `examples/voyage` and `examples/sound`: each packaged program started from another folder and drew (voyage lit, shadowed and with its textured model), the version resource and the icon are in the `.exe`, and with a self-signed certificate trusted on the machine the signatures were valid and time-stamped, the MSIX installed with `Add-AppxPackage`, showed in the Start menu, ran from `WindowsApps` and was removed; the installer installed silently, upgraded 1.0.0 to 1.0.1, refused while the app was open and uninstalled cleanly; **untried: a certificate from an authority (SmartScreen's reputation), the installer's message boxes clicked through by hand and with Narrator, the MSIX in the Microsoft Store (which wants the fourth number 0), another Windows computer with nothing of rocinante, Windows 10, and arm64** (`docs/design.md` code map, `docs/release-checklist.md`).
  - **iPhone (2026-11-23, the second target of issue 56):** `roci package ios` makes the app and a `.ipa` on a Mac, with the sketch's own id, name, version, build, icon, orientation and `launch-colour`, signed by Xcode with the development team (so it runs on the phones that signature knows; a free account's lasts seven days); built by `tools/mobile-ios.sh`. Made on a Mac with a copy of `examples/bricks`; and WILDVEX installed and worked on the iPhone 13 Pro; **the App Store build (`--app-store`, `--upload`) is written but untried, for want of a paid account** (`docs/design.md` code map, `docs/release-checklist.md`).
  - **Started 2026-11-20 with the Mac**: `roci package macos` and `sketch.toml` are built (app, ad-hoc or Developer ID signature, notarisation, zip; `docs/design.md`'s code map entry for packaging says what was found); untried: a Developer ID and notarisation, another Mac, other processors. The other five targets are next.
- `sketch.toml` (§4.9): the packaging questions, the version schemes checked against each store's limits, and the build number. Apple's version rules are read from its documentation first.
- Mobile behaviour for multiple windows, touch-first defaults, orientation.
- A run on an older or lower-end phone of each system besides the Pixel 9 and the iPhone 13 Pro, with frame rates (carried from Phase 1).
- 3D on iOS and Android (carried from Phase 4): `examples/voyage`, lit, with shadows and its imported model, packaged and run on the Pixel 9 and the iPhone 13 Pro, with frame rates.
- The interface on iOS and Android (carried from Phase 3): the AccessKit bridge with VoiceOver on the iPhone and TalkBack on Android, the on-screen keyboard for text boxes, and touch-sized widgets.
- **Exit**: the same sketch file packaged and installed on all seven platforms by someone other than Fabrizio, following only the docs, starting from a machine with nothing installed except what `roci doctor` asked for.

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
- **2026-11-14, Sound words**: `rain = load "rain.wav"` (`load` by the file's extension, not a `sound` verb); a sound is one player: `play` (once, from where it is), `loop`, `pause` (`play` goes on), `rewind [by n]`, `forward rain by n` (shared with the turtle's `forward`), `set rain at volume pan speed loop` and the fields `playing`, `at`, `length`, `volume`, `pan`, `speed`, `loop`; volume 0 to 100 and pan -100 to 100 everywhere, the Odin API and C included; `stop` stays a keyword, and `loop` is a verb because a connecting word always takes a value (§4.6).
- **2026-11-14, Drawing with sound**: `level` (0 to 100) and `bands` (a list 0 to 100, low pitches first, 16 or as many as asked) are verbs whose source is optional: nothing for everything that plays, a sound, or `mic`, the microphone as a built-in value; `bands` and not `fft`, because the word must not be technical (§4.6). `level` became a reserved word, so `examples/sorting`, `garden`, `landscape`, `recursion`, `benchmark` and the `map` reference example renamed their variables.
- **2026-11-14, Instruments**: `piano = synth triangle` (or `sine`, `square`, `saw`, `noise`) is a sound the sketch makes, played with the same verbs; `play piano note 60 for 0.5` (`note` as MIDI numbers, 60 is middle C, fractions allowed; `pitch` in hertz; `for` seconds, otherwise held), and one instrument plays many notes at once: `pause piano note 60` lets one go, `pause piano` all of them. Note names (`"C4"`) and a `beep` verb were the other choices (§4.6).
- **2026-11-14, MIDI in**: our own backends (raw device files on Linux, FreeBSD and OpenBSD, CoreMIDI, WinMM; Android and iOS in Phase 8), not `vendor:portmidi`, which is a system library on Linux and the BSDs that `roci` would need at start and has no phone support; `on midi down`, `on midi up` and `on midi control` with the record `midi` (`note`, `velocity` 0 to 100, `channel`, `control`, `value` 0 to 100), and `midi control n`, the latest value of a controller, readable anywhere (§4.6).
- **2026-11-15, SoundFonts**: `synth "piano.sf2"` makes an instrument from a SoundFont 2 file in the assets, `preset` choosing one by number or name (a missing one is the warning `Preset_Missing` and the first plays); read by our own reader, no library. The repository holds `tests/sounds/tiny.sf2` (11 KB, made by `tools/soundfont`) and, in `examples/soundfont`, FreePats' CC0 Upright Piano KW cut down to 1.4 MB (every other sample, 22 kHz, three seconds each); FluidR3_GM (MIT, about 141 MB) is the General MIDI set to try by hand (§4.6).
- **2026-11-15, Sound effects**: `effect guitar "delay" by { time: 0.3 }` (the picture effects' verb with a sound first; again changes it, `no effect` takes it off) and `speakers`, the whole mix, as a value; sixteen effects (overdrive, fuzz, delay, reverb, chorus, flanger, phaser, tremolo, compressor, eq, rotary, filter, bitcrush, ring, wah, limiter), our own code; amounts 0 to 100, seconds, times a second, hertz, eq bands -100 to 100, no decibels shown (§4.6).
- **2026-11-15, Streaming**: a sound file longer than 30 seconds is read as it plays (from a path or from the bytes of a file, which are copied) from a ring of eight seconds filled by a thread of the mixer (a five-minute song is about 3 MB, and `load` does not wait for a decode); shorter ones are decoded whole, so sound effects keep exact positions; no new word (§4.6).
- **2026-11-17, Remembering**: `remember "name" value`, `recall "name" start v` and `forget "name"` / `forget memory` keep values in `memory.toml` beside the sketch; the name is text written in the sketch and a name keeps one kind, both checked at load time; written after a pause and at exit, ignored by git, read and never written by headless runs (§5.17).
- **2026-11-17, The vault**: `in vault` on `remember`, `recall` and `forget` keeps values in a sealed binary file (`vault.bin`, XChaCha20-Poly1305, key in a gitignored `vault.key`), for what a player must not edit; `roci vault show|set|forget` looks inside; honest players only, and the docs say so (§5.17).
- **2026-11-17, Scenes**: `scene "name" [ ... ]` holds the `draw`, `on`, `every` and `ui` blocks of one part of a sketch (with `on enter` and `on leave`), `go`, `visit` and `return` change scene at the end of the frame and `visit` keeps the scene underneath on the screen, stopped; scene names are checked before the sketch runs; blocks outside every scene run in all of them; levels stay data (§5.18).
- **2026-11-17, Data files**: `load "birds.json"` (also CSV, TSV, TOML and text, from `assets/data`) gives a record or list shaped by the file, read by the checker so a field is known before the sketch runs; `save value "name.json"` writes a value in the kind its name ends in; `lines` and `files in` are the small verbs around them (§5.19). Decided with it: file dialogs are blocks that run when a player chooses (no verb suspends), `fetch` goes through libcurl, and images from a URL, Excel and ODT files come after (Phase 6 item 2).
- **2026-11-17, Dialogs, `read`, `open` and the clipboard**: `ask file "png jpg" [ ... ]`, `ask folder [ ... ]` and `ask save "name" [ ... ]` show the system's dialog and run their block when the player has chosen, with `chosen` the path; nothing waits, at most four are open, and a closed dialog runs nothing. A chosen path is the only one outside `assets/` that `load`, `read` and `open` take. `read` gives a file's text, `open` hands an address or file to the system, `clipboard` and `copy to clipboard` are the clipboard; `chosen`, `clipboard`, `read` and `open` are reserved words (§5.19).
- **2026-11-17, `polygon [ corners ]`**: a filled shape through any number of corners, drawn as the path SVG import uses; the corners are a list of vectors, or (2026-11-18) a list of such lists, the contours of one shape, where a contour inside another is a hole; a contour crossing itself is filled whole, not holed. C has `roci_polygon` and `roci_polygons`.
- **2026-11-18, Contextual words** (#42): only the 25 keywords and the 8 grammar words (`as at by from in of over to`) cannot be names; every other word of the language is a word only where the grammar expects it and a sketch's own name elsewhere, per file group so libraries keep the language's meaning; `Name_Hides_Verb` is the error where a name hides a verb that was probably meant (`docs/design.md`, Names).
- **2026-11-18, `fetch`**: `fetch "url" [ ... ]`, `fetch picture "url" [ ... ]` and `post "url" "text" [ ... ] header "line"` get and send over HTTP(S) on a thread, run their block when the answer has come, and give it the record `reply` (`status`, `ok`, `text`, `problem`, `picture`); nothing waits, at most eight are open, a headless run fetches nothing. libcurl 8.23.0 with mbedTLS 4.3.0, static and HTTP(S)-only, built by `tools/net-libs.sh` (Schannel on Windows), approved by Fabrizio 2026-11-18; the phones' libraries are built by `tools/net-libs.sh ios` and `android`, and iOS carries Mozilla's CA list (MPL-2.0 data in `vendor/curl`, chosen by Fabrizio 2026-11-18), none of it tried on a phone yet (§4.12 code map entry `vendor/curl`, `docs/design.md` §5.19).
- **2026-11-18, UDP**: `on udp 9200 [ ... ]` with the record `packet` (`text`, `bytes`, `from`, `port`) and `udp send "text" to "host" port n` (or a list of bytes); `port` is required, listening starts with the block, at most 16 ports, on OSC's sockets; a headless run hears and sends nothing; C has `roci_udp_send`, `roci_udp_listen` and `roci_on` with "udp" (`docs/design.md` §5.19). Next: `tcp`, then `websocket`.
- **2026-11-18, TCP**: connections named by a text label: `tcp connect "chat" to "host" port n`, `tcp listen "server" port n`, `tcp send "chat" "text"` (a line; a list of numbers goes as bytes; `to n` answers one client of a server) and `tcp close`, heard by `on tcp "chat"` (a line), `on tcp open` and `on tcp close` with the record `received` (`text`, `from`, `client`); one thread per connection, at most 8 connections and 16 clients, a headless run opens nothing; C has `roci_tcp_connect`, `roci_tcp_listen`, `roci_tcp_send`, `roci_tcp_close` (`docs/design.md` §5.19). Chosen over a `socket` value and `socket.send`, which the language has no syntax for. Next: `websocket`.
- **2026-11-18, Web sockets**: `websocket connect "feed" to "wss://..."`, `websocket send "feed" "text"` (a list of numbers goes as binary) and `websocket close`, heard by `on websocket "feed"` (a message), `on websocket open` and `on websocket close` with the record `received` (`text`, `from`), on libcurl's WebSocket support and the trusted certificates of `fetch`; client side only, at most 8, a headless run opens nothing; C has `roci_websocket_connect`, `roci_websocket_send`, `roci_websocket_close`. That ends Phase 6's second item (`docs/design.md` §5.19).
- **2026-11-19, Webcam**: `webcam` is a built-in value that is a picture of what the first camera sees now (SDL3's camera API, nothing new to install), so `image webcam`, `fill webcam`, `flip webcam` and `snapshot = webcam` need no new syntax; the camera opens the first time a sketch with a window reads it, one picture for the whole frame, a kept one stays as it was, and until a frame comes, with no camera or headless it is a 640 by 480 picture of gray 64 (so goldens and `roci test` are exact); `webcam cameras` lists the cameras by name and `webcam pick` (a number from 1, or part of a name) chooses one, the word `pick` because `webcam to` made `add webcam to shots` read as a verb; no camera, a refusal, a pick that is not there or pictures that cannot be read is the warning `Webcam_Unavailable`, said once; C has `roci_webcam` and the camera functions. First step of Phase 6 item 3; movies and recording follow. Checked by hand on a Mac with two cameras on 2026-11-19; the other systems and the phones are untried (`docs/design.md` §4.11, code map, Webcam).
- **2026-11-15, OSC**: `on osc "/fader/*" [ ... ]` with the record `osc` (`address`, `value` the first number with true as 1, `text` the first text, `args` every number, `from` the sender), `osc send "/note" [ 60 "hi" true [ 1 2 3 ] ] to "host" port 9000` (to and port start as this computer and 9000; a list of numbers is a blob of bytes; `osc send [ [ "/a" 1 ] [ "/b" ] ]` sends a bundle), `osc listen 8000` and `osc value "/fader/1"`; our own packet reader in `roci/osc` and UDP from Odin's `core:net`, no library; listening starts at the first `on osc` on port 9000; numbers, text, true/false and blobs are kept, `osc.args` is everything in order, and timetags and the rest are left out and said once (§4.6).

- **2026-11-16, Sound formats and the SoundFont features that were left out**: AIFF and AIFF-C and Opus (libopus 1.6.1, BSD-3-Clause, added with Fabrizio's approval, and our own Ogg reader) are read by backends of our own beside miniaudio's decoders; AAC (`.m4a`, `.aac`) by each system's decoder (AudioToolbox, Media Foundation, MediaCodec) and the user's ffmpeg elsewhere, since no permissive AAC decoder exists; SoundFont filter, modulation envelope, LFOs, exclusive classes and modulators are read, and `set piano bend 50 vibrato 30` moves the two wheels (§4.6).
- **2026-11-15, Phase 5 closed**: sound files stream past 30 seconds with `buffer` choosing the ring; instruments have `attack`, `decay`, `sustain` and `release` (a floor over a SoundFont's own, no filter word: `effect piano "filter"` is the filter); MIDI out is `midi note`, `release`, `set`, `bend`, `program`, `to`, `outputs`, `clock` and `stop`, and MIDI in also reads bend, program, pressure, start and stop, with an incoming clock as `midi tempo`; recording is `record speakers|sound|mic "name"` (WAV always, mp3, ogg, flac and m4a through the user's ffmpeg), `no record speakers` ends it; the speakers go through a limiter inside `mix` so a take is what is heard (§4.6, `docs/phases.md`).
- **2026-11-16, Text holes**: `"you have {lives} left"` puts the value of an expression in curly brackets into the text, as `+` would, the same in both back ends; `\{` and `\}` write the brackets themselves and a lone `}` is plain text (§5.1, `docs/grammar.ebnf`).
- **2026-11-19, `platform` and `screens`**: `platform` is the system's name as lowercase text (`"macos"`, `"windows"`, `"linux"`, `"freebsd"`, `"openbsd"`, `"ios"`, `"android"`) and `screens` is a list of records, the main screen first (`name`, `pos`, `width`, `height` in the units a window is sized in, `density`, `refresh`, `main`), the name `screens` being the one the parity map already held; a headless run has one stand-in screen of 1920 by 1080 so pictures do not depend on the computer; C has `roci_platform` and `roci_screen_*` (`docs/design.md` code map, Screens and platform).
- **2026-11-19, Movies**: `clip = load "zoom.mpg"` is a picture that plays, decoded by pl_mpeg (MIT, MPEG-1 only, approved by Fabrizio the same day, along with dav1d and libvpx for later), moved with the sound verbs' words (`play`, `loop`, `pause`, `rewind`, `forward by`, `set clip at speed loop`) and read with `clip.playing`, `at`, `length`, `speed` and `loop`; the picture only, no sound yet; the checker types a movie as a picture and every picture verb asks for the picture of the moment, so a movie value is the movie and not a snapshot; C has `roci_load_movie`, `roci_movie_frame` and the verbs (`docs/design.md` §4.11 and the code map, Movies).
- **2026-11-19, The compiler begins** (Phase 7's first slice, pulled forward to measure compiled speed): `roci run --compile [--debug]` generates Odin from the typed IR (`roci/codegen`), builds it with the pinned Odin together with the core's Odin source and runs the program in the terminal; the program goes in `artifacts/<system>/<release|debug>/` of the sketch's folder (git leaves `artifacts/` out, `roci new` and `roci init` see to it), `--stats` times the frames in either back end (a box with the frame and the frame rate, a summary, and a line in `artifacts/log.json`) and `--no-vsync` lets a window run as fast as it can. A sketch that uses what the generator does not cover yet is refused, every line named, never half compiled. `--target ios|android` puts the compiled sketch on a phone that is plugged in (2026-11-19, see the phones entry below). Measured on this Mac: the 100,000-circle benchmark builds its frame in 5.2 ms compiled against 18.2 interpreted, the particles in 1.2 ms against 4.9 (docs/design.md §4.7, code map entries `roci/codegen`, `roci/rt`, `roci/builds`).

- **2026-11-19, Compiled sketches on phones**: `roci run --compile --target ios|android [--device id] [--team id]` makes the program with `codegen.Options.target` (the program ends in SDL's `sdl_main` and `RunApp` on iOS and in the exported `rocinante_main` and `android_main` on Android, where the desktop's ends in `main`), then `tools/mobile-ios.sh` or `tools/mobile-android.sh` build it as a static or shared library, link it with SDL3 and the libraries `spikes/mobile/*/libs.sh` built, make the app (iOS: an Xcode project that only signs, with the team Xcode knows; Android: an APK with the debug key `output/spike-debug.keystore`), carry the sketch's `assets` (iOS: inside the app; Android: copied into the app's own folder with `adb shell run-as`, which works because the debug app is debuggable; a push to the shared storage is owned by the shell user and the app cannot read it, so no asset loaded (fixed 2026-11-20, a font checked on the Pixel 9)), install, and start; `rt.use_home` points the program at them. SDL 3.4.18 for the phones is built by `tools/mobile-sdl.sh` into `.cache/mobile`. The app is `org.rocinante.sketch`, so a new sketch replaces the last, and a free Apple account's signature lasts seven days. It is not `roci package` (no store, no signing for others, one phone). Checked on the iPhone 13 Pro with `examples/circle` and a game of 20 files with sound (running, the screen looked at by Fabrizio); the Android APK was installed on the Pixel 9 on 2026-11-20 (`docs/design.md` code map, `tools/mobile-*.sh`).

- **2026-11-20, `--target android-emulator`, and no iOS Simulator**: `roci run --compile --target android-emulator [--device avd-or-serial]` puts the same arm64 APK on Android's emulator (`EMULATOR=1` for `tools/mobile-android.sh`, which uses a running emulator, else starts the virtual device named by `AVD` or the first `emulator -list-avds` gives, and waits for `sys.boot_completed`); checked on an arm64 Pixel image on this Mac (the sketch ran and drew, with the Pixel 9 plugged in too), for layout only. **An iOS Simulator target was built and does not work**: SDL, the libraries and the app all build for `arm64-apple-ios-simulator` and install, but `SDL_CreateGPUDevice` fails with "Device does not meet the hardware requirements for SDL_GPU Metal", because the simulator's device ("Apple iOS simulator GPU") reports only `MTLGPUFamilyApple1` and `Apple2` on the iOS 26.3, 26.5 and 27.0 runtimes (Apple silicon, 2026-11-20) and SDL's Metal driver wants `Apple3`. Only a change inside SDL would get past it, which Claude Code does not write (§3), so the target was dropped; it comes back if a later SDL accepts that device.

- **2026-11-20, Phones: the background and `vibrate`**: when the system says the app is leaving (`WILL_ENTER_BACKGROUND`, `DID_ENTER_BACKGROUND`, `TERMINATING`) `roci/away.odin` notes the moment (plain atomics, because Android says it from its own thread) and the remembered values are saved as before; while it is away `roci.run` builds and draws nothing (it found an Android emulator crashing inside SDL's Vulkan swapchain code when a sketch kept drawing into a window whose surface the system had taken) and only waits for events, and when `WILL_ENTER_FOREGROUND` or `DID_ENTER_FOREGROUND` says it is back the time away is left out of the sketch's clock (`time`, tweens and every frame's seconds), so a sketch comes back where it was. `vibrate` and `vibrate seconds` (0.2 by default, at most 5; C has `roci_vibrate` and `roci_vibrate_for`) buzz the phone: on Android through SDL's haptic device `VIBRATOR_SERVICE`, which needs `android.permission.VIBRATE` in the manifest (without it Android throws and the app aborts), on an iPhone through `AudioServicesPlaySystemSound(4095)`, whose length the system chooses; a computer and a headless run do nothing. Checked on the Android emulator (the app's buzzes show in its vibrator service, and a trip to the background and back keeps the app running, with `time` going 5 to 8 and the frame count not counting the 20 seconds away); a real Android vibrator (Pixel 9) and an iPhone 13 Pro were both felt by Fabrizio on 2026-11-20.

- **2026-11-20, Android draws edge to edge**: `SketchActivity` (`tools/mobile/android`) lets the window reach under the status bar, the navigation bar and the camera's cut-out (`setDecorFitsSystemWindows(false)` from Android 11, the layout flags before; transparent bars with `FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS` set and the translucent flags cleared, without which the system painted the bars black; the cut-out mode `ALWAYS`, `SHORT_EDGES` before Android 11), as an iPhone's window always does, and SDL then reports the insets, so `safe` is real there: on the Pixel 9 (portrait) top 78, bottom 32 and left and right 29.7 in the window's units, which are the larger of the bar and the system's gesture strips (SDL's choice). Checked on the Pixel 9 with a red background reaching under both bars; landscape, an older Android and light bar icons on a light picture (the icons stay white) are not checked.

- **2026-11-22, App icons from one picture**: `icons/icon.svg` (a square view box) or `icons/icon.png` (square, 1024 pixels or more), or `roci package --icon file`, which checks it and copies it there; `roci new` and `roci init` make `icons/`. `roci package` makes every system's icons from it into `icons/` in WILDVEX's layout and each system's shape (the Mac's rounded square at 824 of 1024, the iPhone's opaque square, Windows' PNGs and `.ico`, Linux's hicolor sizes and the drawing, Android's rounded, round and adaptive icons), painted with no GPU by `roci/gfx/raster.odin` over roci's own SVG reader, which now reads gradients, fill rules and clip paths for it (the `svg` verb draws the gradients, fill rules and clip paths too, on the GPU, the same day); a file there that roci did not make, or that changed after (`icons/.made`), is the person's own and is never written over; a picture that is not square or too small stops the packaging before it compiles; `sketch.toml`'s `icon` is no longer read. Chosen by Fabrizio over nanosvg and a PNG-only first step (`docs/design.md` §4.9, code map entries for packaging icons and `roci/gfx`).
- **2026-11-22, `roci package freebsd`**: a `.pkg` and a `.tar.gz`, both by default (`--format`, kept in sketch.toml's `[freebsd]`), made on FreeBSD only. Nothing is carried: the program links the computer's SDL3, SDL3_ttf, shaderc and SPIRV-Cross, and the package depends on the packages that own them (found with `pkg which` and `pkg query`), as FreeBSD packages do; a self-contained tar would need its own SDL3_ttf build and was set aside. The `.pkg` is written by `roci` (a zstd tar of `+COMPACT_MANIFEST`, `+MANIFEST` and the files, with `pkg`'s own BLAKE2 checksums, as `pkg create` 2.9.2 writes it; no `pkg-create`), made for the release it was built on (`FreeBSD:15:amd64`). Chosen by Fabrizio over a `.pkg` alone and over carrying the libraries (`docs/design.md` code map, `site/guides/35-packaging-a-freebsd-app.md`).
- **2026-11-23, `roci package openbsd`**: a `.tgz` and a `.tar.gz`, both by default (`--format`, kept in sketch.toml's `[openbsd]`), made on OpenBSD only. The package is made by the base system's `pkg_create` from a packing list `roci` writes (`@bin` for the program, `@so` for the library it carries, `-P` and `-W` for the dependencies and library numbers found with `readelf`, `ldd` and `pkg_info`), not written byte by byte as the FreeBSD `.pkg` is, because `pkg_add` is strict about a package's list and checksums and `pkg_create` checks the libraries as well. SDL3, shaderc and SPIRV-Cross are packages the app depends on, but OpenBSD has no package for SDL3_ttf, so the app carries one built by `tools/package-libs.sh openbsd` (FreeType and HarfBuzz inside, as Linux's), which the program finds through `$ORIGIN/lib` in its RUNPATH (OpenBSD's loader honours it, tested with a moved folder). The package is unsigned and the tool says to install it with `pkg_add -D unsigned`; signing with `signify` is left to a repository of one's own. Chosen by Fabrizio (2026-11-23) over writing the `.tgz` itself and over signing from the start (`docs/design.md` code map, `site/guides/36-packaging-an-openbsd-app.md`).
- **2026-11-23, `roci package windows`**: an installer and the app's folder zipped by default, and an MSIX with `--format msix` or `all` (kept in sketch.toml's `[windows]`), made on Windows only with the Windows SDK's tools, which Odin already needs (`rc` through Odin's `-resource:`, `makeappx`, `signtool`) and Windows' own `tar` for the zip: no new dependency, no installer of our own, no WiX. The program is built with `-subsystem:windows` (no console) and a resource script for its icon (`icons/windows/<slug>.ico`), its four-number version (the three of `version`, then the build, each at most 65,535) and a manifest (Windows 10 and 11, per-monitor DPI); it carries `SDL3.dll` and `SDL3_ttf.dll` from the pinned Odin's `vendor/sdl3`, found by reading the import tables of the program and of what it carries, and any other DLL that is not Windows' own stops the packaging. Signing: the code-signing certificate `--sign` names (thumbprint or part of its name), else the one the user's store has, else unsigned with SmartScreen explained; SHA-256, time-stamped by DigiCert. The MSIX's publisher is the certificate's subject, its logos are made with the other icons (`icons/windows/msix`), and it asks for the microphone and the camera only when the sketch uses them. The installer (`--format setup`) is rocinante's own (`roci/install`): a small Odin program, compiled at each package with the app's icon and a manifest asking for an administrator, with the app's files appended as a deflated archive before it is signed; it installs into Program Files for everyone with a Start menu shortcut and an entry in Settings, Apps, and carries itself as `uninstall.exe`. Chosen by Fabrizio (2026-11-23) over a zip alone and over an MSI with WiX; the installer was asked for the same day, so Windows packages install system-wide like the other systems' (chosen by Fabrizio over an MSI made with WiX, a new dependency, and over provisioning the MSIX for every user) (`docs/design.md` code map, `site/guides/39-packaging-a-windows-app.md`).
- **2026-11-23, `roci package android`**: a signed APK, made on a Mac, a Linux x86-64 or a Windows computer (tried on a Mac), by the script that puts a test build on a phone, told by `roci` to make the app of its own: the manifest `roci` writes (its id with a hyphen made an underscore, its name, version, build as `versionCode`, icon from `icons/android/res`, `orientation`, `[android] category`, the microphone and the camera only when the sketch uses them), the sketch's `assets`, `libs` and starting files inside the APK for `SketchActivity` to unpack into the app's folder after every install, and a release key per id that `roci` makes once outside the sketch's folder (`~/Library/Application Support/rocinante/android` on a Mac) and tells the person to keep, with its password in a mode-600 file beside it; a key of the person's own is not read yet. Chosen by Fabrizio (2026-11-23): Android first of the phones, an APK first and the Android App Bundle for Google Play later (it needs `bundletool`, and cannot be tried on a phone directly) (`docs/design.md` code map, `site/guides/37-packaging-an-android-app.md`).
- **2026-11-23, The Android App Bundle**: `roci package android --format aab|all` (kept in the `[android]` part of sketch.toml as `formats`) makes the `.aab` Google Play asks for, with the release key of the APK (`jarsigner`), by bundletool 1.18.3 (Apache-2.0) and the `aapt2` Google publishes for bundles, both fetched into `.cache/android/tools` by `tools/fetch-bundle-tools.sh` with SHA-256 checked, approved by Fabrizio (2026-11-23); tried on an emulator through bundletool, not yet uploaded to Play (`docs/design.md` code map, `site/guides/37-packaging-an-android-app.md`).
- **2026-11-20, `roci package macos`**: makes `Name.app` and a disk image `slug-version-macos-arm64.dmg` (a zip too with `--format zip` or `all`; the disk image holds the app and an Applications shortcut, is signed with the Developer ID and notarised and stapled on its own after the app, changed from a zip 2026-11-23 at Fabrizio's asking) in `output/package/macos` of the sketch's folder. `sketch.toml` (name, id, icon, version, build, and `[macos]` identity, notary-profile and category) is made by the first package after asking on a terminal, and holds the build number, which rises by one only when an app was made; Apple's version rule is up to three whole numbers, `date` stamps `YYYY.M.D`. The app carries SDL3 and SDL3_ttf built by `tools/package-libs.sh` (Homebrew's SDL3_ttf is not carried: it needs glib, which is LGPL), the program is pointed at them with `install_name_tool` because Odin's own `-L` order cannot be overridden, assets and libs are in `Resources`, what the app writes goes in `~/Library/Application Support/<id>` where the sketch folder's starting files are copied once, `Info.plist` gives the microphone and camera sentences, and the app the entitlements for them, only for what the sketch uses (a Mac app of a sketch that never listened asked for the microphone, 2026-11-23), and it is signed ad hoc unless a Developer ID is named or found, with the hardened runtime on every signature, and notarised when `notary-profile` or `--notarize` says. An app asks for the macOS of the Mac that made it, because the static libraries are built for that system. Checked here: examples/circle, WILDVEX (assets, fonts, vault, microphone sentence, a headless picture through the packaged program), and the questions through a terminal; not checked: a Developer ID signature and notarisation, another Mac.
- **2026-11-23, `roci package ios`**: an app and a `.ipa`, made on a Mac by `tools/mobile-ios.sh` told by `roci` to make the app of its own: the `Info.plist` and asset catalog `roci` writes (icon from `icons/ios`, `launch-colour` in sketch.toml for the launch screen, `orientation`, the microphone and camera sentences only when used), signed by Xcode with the development team (`--team` when Xcode knows several), so for the phones that signature knows; `--app-store` makes the distribution-signed `.ipa` and `--upload` sends it to App Store Connect, written from Apple's documentation and untried until Fabrizio has a paid Apple Developer Program account. Chosen by Fabrizio (2026-11-23) as the next target after Android (`docs/design.md` code map, `site/guides/38-packaging-an-ios-app.md`).
- **2026-11-24, `fps`: a frame rate a sketch can ask for**: `window size 720 1280 fps 60`, `set w fps 30` and `w.fps` (0 for no limit, at least 1 otherwise) keep the sketch at most at that many frames a second, sleeping after each frame until the next is due, in the interpreter, compiled sketches (both go through `roci.run`) and C (`roci_set_window_fps`, `roci_window_fps`), because a window otherwise draws at its screen's refresh and WILDVEX, which counts its time in frames as most sketches do, ran faster on 120 and 144 Hz screens. Chosen by Fabrizio the same day: the exact rate on average where the refresh is not a whole multiple (60 on 144 Hz: frames two and three refreshes apart, said by `--stats`; snapping to 72 would change a frame-counted sketch's speed), a headless frame of one frame at the rate (a sixtieth without one), the lowest limit of the open windows holding the sketch with `w.fps` the window's own and bare `fps` still the measured rate, and `--no-vsync` not lifting it. A `delta` value for moving by time is left for later; every sketch written by frames would still need the limit (`docs/design.md` §4.5 and the code map entry Frame rate, `site/guides/10-windows.md`, `examples/metronome`).
- **2026-11-24, Shaders ready before the first frame**: every shader an `effect` or `shade` line names by its own text is translated before the sketch's top level runs, interpreted and compiled, and the renderer makes their pipelines in a window's format before that window's frame is drawn, because a first use stopped a frame for about a tenth of a second (WILDVEX's logo melt and title pour, 24 November, which WILDVEX had worked around by running each shader once in a small canvas); a problem with one is still said when its line first runs, and a name made while the sketch runs or a canvas's first frame with a shader still waits once. Packaged apps translate at start as `roci run` does; compiling the shaders in `roci package` is not done (`docs/design.md` §4.3 User shaders and the code map entries for effects, `site/guides/17-shaders.md`).
- **2026-11-24, A kept word given as a name is said the same way everywhere**: an assignment, a `for` or `for each` loop's name and an `on w receive` message's name that is a keyword or a grammar word all give "`x` is already a word" (`Reserved_Name`) at the word, once, where `hidden = 1` said "learn needs a name", `repeat = 2` "I did not expect this here" and a loop or message name went unsaid; `it` and `result` as a loop's name are refused too; and after `learn post [ ... ]` or `learn repeat [ ... ]` a later line calling it says nothing more (`docs/design.md` §5, Names).

### Later

Ideas that are wanted but not planned for the first stable release live in the Roadmap section of `README.md`, so contributors can see them. When one is taken up, it moves here and into §8.

### Open

Decide these with Fabrizio; move each to "Decided" with the date.

1. Machine learning on FreeBSD and OpenBSD: LiteRT's C runtime built there, or ONNX Runtime as the fallback (§4.10). Settled by the LiteRT spike, sixth in Phase 6's order, after the physics.
2. ExecuTorch as a second runtime for PyTorch's own `.pte` files, so PyTorch models skip conversion. It is C++ only, so it would need our own C wrapper, and a second runtime is a second behaviour to keep equal (§4.10).
3. Choices inherited from the sections they point to: HE-AAC where the system has no decoder (§4.6); MIDI and the microphone on iOS and Android (§4.6, Phase 8); mobile multi-window behaviour (§4.5, Phase 8); video encoder libraries (§4.11, Phase 6); the name of `roci check --why-slow` (§5.3, Phase 2); Box3D for 3D collision, once it has releases and covers the phones (§5.13).
4. The accessible canvas (planned for Phase 3 and not done there; still to be placed): scene descriptions built from the command records (§4.3), a `describe "…"` verb, a live region that updates only when the scene changes, and colour-contrast checks, extending §4.8 from widgets to the canvas (p5.js does this with `describe` and `textOutput`, §12).
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
