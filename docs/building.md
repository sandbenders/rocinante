# Building rocinante from source

What you need to build and run rocinante from this repository, system by system, and the commands for trying it. The [getting started guide](https://rocinante-lang.org/guides/01-getting-started/) walks through the same steps for someone who only wants to write sketches.

## What to install

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

On OpenBSD, MIDI keyboards and controllers are read from `/dev/rmidi*`, which belong to the `_sndiop` group: without being in it a sketch hears no MIDI and says nothing (`cat /dev/rmidi0` says `Permission denied`). Run `doas usermod -G _sndiop your-name` once and log in again (found 2026-11-16 with an AKAI MPK mini 3).

A sketch's own shaders (`effect`) are translated while it runs by [shaderc](https://github.com/google/shaderc) and [SPIRV-Cross](https://github.com/KhronosGroup/SPIRV-Cross), which the engine links: `sudo pacman -S shaderc spirv-cross` on Arch, `brew install shaderc spirv-cross` on macOS, `sudo apt install libshaderc-dev` on Debian and Ubuntu, where SPIRV-Cross is too old (it lacks the functions the Metal translation calls) and is built with `tools/ci/install-spirv-cross.sh <folder>`, then put `<folder>/lib` on `LIBRARY_PATH` and `LD_LIBRARY_PATH` (the package names on Fedora, FreeBSD and OpenBSD are still being confirmed). Windows needs neither: it draws with Direct3D 12 only, and a sketch's shaders are compiled there by the shader compiler that is part of Windows, so nothing has to be installed for them.

Fetching from the web (`fetch`) links [libcurl](https://curl.se/) and [mbedTLS](https://github.com/Mbed-TLS/mbedtls), which are built from source once, static and for HTTP and HTTPS only: `odin run build -- net-libs` (or `sh tools/net-libs.sh`) downloads them, checks their checksums and builds them into `.cache/net`; `ci` and `docs` do it when they are missing. It needs `cmake`, `make` and a C compiler (on Windows libcurl uses the system's Schannel and is built with MSVC from Git Bash inside `vcvars64.bat`, which has not been run yet). A sketch needs nothing installed to run. Secure addresses are checked against the computer's own list of trusted sites, found at run time in `/etc/ssl/cert.pem` or the other usual places.

The user interface (work in progress) is drawn by [Dear ImGui](https://github.com/ocornut/imgui), which is C++ and is built from source once: `sh tools/ui-libs.sh` (or `odin run build -- ui-libs`) fetches it at its pinned version and compiles it into `.cache/ui` with `git` and a C++ compiler. Every program that opens a window links it, so run that once before `odin run examples/circle` or any build (`odin run build -- ci` does it for you when it is missing). On Windows it is compiled with MSVC, so run these commands from Git Bash started in a window where the Build Tools' `vcvars64.bat` has run (`call "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat"` in a plain `cmd`, then `"C:\Program Files\Git\bin\bash.exe" --login -i` in the same window).

The screen-reader bridge uses [accesskit-c](https://github.com/AccessKit/accesskit-c), which is Rust: `sh tools/ui-libs.sh accesskit` downloads its release library (macOS, Linux x86-64 and Windows x86-64, the checksum is pinned in the script; needs `curl` and `unzip`, or PowerShell on Windows) into `.cache/ui/accesskit`, and builds it from source with `git`, `cmake` and `cargo` where no library is published (FreeBSD, OpenBSD, arm64 Linux). Without it everything still builds and runs, with no screen-reader support, and `odin run build -- ci` fetches it when it can. It has been checked with a screen reader on every desktop system: macOS (VoiceOver), Linux, FreeBSD and OpenBSD (Orca) and Windows (Narrator and NVDA).

Gamepads on FreeBSD are read through the kernel's own drivers (nothing to install), but only the `games` group may open them: `pw groupmod games -m <you>` as root, then log in again. PlayStation 4 and 5 pads and the Logitech Dual Action work over USB; Xbox One and Series pads have no driver there (the guide on mouse, keys and fingers says what was tried).

Putting a compiled sketch on a phone (`roci run --compile --target ios|android`) needs the phone's own copies of SDL3 and the libraries above, built once from source into `.cache` (ignored by git): `tools/mobile-sdl.sh ios` (SDL 3.4.18 as a static library; Xcode, `cmake`, `ninja`) and then `SDL_IOS_LIB=$PWD/.cache/mobile/ios SDL_IOS_SRC=$PWD/.cache/mobile/SDL3-3.4.18 spikes/mobile/ios/libs.sh` (SDL3_ttf, shaderc, SPIRV-Cross, Dear ImGui, libcurl with mbedTLS and the sound decoders); for Android the same with `android` and `spikes/mobile/android/libs.sh` (`SDL_ANDROID_LIB=$PWD/.cache/mobile/android`), with the Android SDK and NDK `29.0.14206865` from Android Studio. The iPhone is signed by the development team Xcode knows (`TEAM_ID` or `--team` to choose) and must be paired and unlocked, and its developer trusted once; the Android phone needs USB debugging on and the screen unlocked, and gets the sketch's `assets` in the app's own folder (the debug app is debuggable so that `adb shell run-as` can copy them there). A library that is built again after a change in `vendor/sound/c` (the movie decoder was added after the first phone build) is rebuilt by deleting `libroci_sound.a` from `.cache/ios/lib` or `.cache/android/lib` and running `libs.sh` again. The Android emulator (`--target android-emulator`) reuses the phone's libraries and needs only an arm64 virtual device (`emulator -list-avds`); there is no iOS Simulator target, because its Metal device is too small for SDL's GPU API. `roci doctor` checks the tools for this computer.

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

Add `-- 3` to any of these to close the window after three seconds. `examples/c/circle.c` is the same circle through the C API (`include/roci.h`, checked by `tools/abi-check.sh`), and `examples/c/scene.c` is a lit 3D scene with shadows, a picked point on the floor and an SVG badge in C, and `examples/c/controls.c` has widgets, two windows, collision, tweens and events in C, and `examples/c/player.c` is a music player whose songs are read into memory with stdio and streamed from there. Everything the language does is in the C API, except the list and table verbs, which C has its own arrays and maps for.
