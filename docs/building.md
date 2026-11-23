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

OpenBSD 8.0 (checked 2026-11-23) changed two things that the pinned Odin, `dev-2026-11`, does not know: the C library no longer exports `__sF` for `stdin`, `stdout` and `stderr` (it has `__stdin`, `__stdout` and `__stderr`), so every Odin program fails to link with `undefined symbol: __sF`, and the values of `WEXITED`, `WNOWAIT` and `WCONTINUED` changed, so `os.process_wait` fails with `EINVAL` and the build script cannot run any program. Odin's `master` fixed both on 2026-11-17 (commit `5598075b1`, "Fix building and testing Odin on OpenBSD 8.0"), and no release has it yet; `master` itself moved the `core:compress` and `core:encoding/xml` names rocinante uses, so it does not build rocinante. Until a release carries the fix, copy the installed Odin folder (`cp -R /usr/local/lib/odin ~/odin-8`), change the OpenBSD part of `core/c/libc/stdio.odin` to use `__stdin`, `__stdout` and `__stderr`, and the OpenBSD part of `core/sys/posix/sys_wait.odin` to `WCONTINUED :: 0x08`, `WEXITED :: 0x04` and `WNOWAIT :: 0x10`, and run with `ODIN_ROOT=$HOME/odin-8 PATH=$HOME/odin-8:$PATH`. With that, `odin run build -- ci --fast` passes on OpenBSD 8.0. There is no lavapipe there, so the golden images draw on the computer's own graphics card (an AMD RX 580 here): 35 of 137 pictures were outside the limits for a real card on 2026-11-23, ten of them by a pixel more than 64 (mostly thin lines: tree, koch, spiral, flocking, swarm), which is probably the card's edge pixels but was not compared against lavapipe, so it is unchecked.

Gamepads on OpenBSD (checked 2026-11-23 with a Logitech Dual Action over USB, SDL 3.4.20): the pad is `/dev/ujoy/0`, readable by everyone and opened by one program at a time ("Device busy" for a second one), and every control works except the d-pad. SDL's OpenBSD joystick driver (`src/joystick/bsd/SDL_bsdjoystick.c`, `BSD_JoystickUpdate`) has a block that rebuilds the hat from four separate d-pad usages, and it runs for every Generic Desktop item instead of only those four, so the hat switch the Dual Action uses is set and at once sent back to the middle (every press is a hat event with its direction and then one with value 0, at the same nanosecond). The code is the same in SDL's `main`, so until SDL fixes it a pad with a hat-switch d-pad has none on OpenBSD; rocinante cannot read the pad itself beside SDL, because the device opens only once.

On OpenBSD, MIDI keyboards and controllers are read from `/dev/rmidi*`, which belong to the `_sndiop` group: without being in it a sketch hears no MIDI and says nothing (`cat /dev/rmidi0` says `Permission denied`). Run `doas usermod -G _sndiop your-name` once and log in again (found 2026-11-16 with an AKAI MPK mini 3).

A sketch's own shaders (`effect`) are translated while it runs by [shaderc](https://github.com/google/shaderc) and [SPIRV-Cross](https://github.com/KhronosGroup/SPIRV-Cross), which the engine links: `sudo pacman -S shaderc spirv-cross` on Arch, `brew install shaderc spirv-cross` on macOS, `sudo apt install libshaderc-dev` on Debian and Ubuntu, where SPIRV-Cross is too old (it lacks the functions the Metal translation calls) and is built with `tools/ci/install-spirv-cross.sh <folder>`, then put `<folder>/lib` on `LIBRARY_PATH` and `LD_LIBRARY_PATH` (the package names on Fedora, FreeBSD and OpenBSD are still being confirmed). Windows needs neither: it draws with Direct3D 12 only, and a sketch's shaders are compiled there by the shader compiler that is part of Windows, so nothing has to be installed for them.

Fetching from the web (`fetch`) links [libcurl](https://curl.se/) and [mbedTLS](https://github.com/Mbed-TLS/mbedtls), which are built from source once, static and for HTTP and HTTPS only: `odin run build -- net-libs` (or `sh tools/net-libs.sh`) downloads them, checks their checksums and builds them into `.cache/net`; `ci` and `docs` do it when they are missing. It needs `cmake`, `make` and a C compiler (on Windows libcurl uses the system's Schannel and is built with MSVC and the `cmake` that Visual Studio Build Tools carry, from Git Bash inside `vcvars64.bat`; first built there 2026-11-23). A sketch needs nothing installed to run. Secure addresses are checked against the computer's own list of trusted sites, found at run time in `/etc/ssl/cert.pem` or the other usual places.

The user interface (work in progress) is drawn by [Dear ImGui](https://github.com/ocornut/imgui), which is C++ and is built from source once: `sh tools/ui-libs.sh` (or `odin run build -- ui-libs`) fetches it at its pinned version and compiles it into `.cache/ui` with `git` and a C++ compiler. Every program that opens a window links it, so run that once before `odin run examples/circle` or any build (`odin run build -- ci` does it for you when it is missing). On Windows it is compiled with MSVC, so run these commands from Git Bash started in a window where the Build Tools' `vcvars64.bat` has run (`call "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat"` in a plain `cmd`, then `"C:\Program Files\Git\bin\bash.exe" --login -i` in the same window).

The screen-reader bridge uses [accesskit-c](https://github.com/AccessKit/accesskit-c), which is Rust: `sh tools/ui-libs.sh accesskit` downloads its release library (macOS, Linux x86-64 and Windows x86-64, the checksum is pinned in the script; needs `curl` and `unzip`, or PowerShell on Windows) into `.cache/ui/accesskit`, and builds it from source with `git`, `cmake` and `cargo` where no library is published (FreeBSD, OpenBSD, arm64 Linux). Without it everything still builds and runs, with no screen-reader support, and `odin run build -- ci` fetches it when it can. It has been checked with a screen reader on every desktop system: macOS (VoiceOver), Linux, FreeBSD and OpenBSD (Orca) and Windows (Narrator and NVDA).

Gamepads on FreeBSD are read through the kernel's own drivers (nothing to install), but only the `games` group may open them: `pw groupmod games -m <you>` as root, then log in again. PlayStation 4 and 5 pads and the Logitech Dual Action work over USB; Xbox One and Series pads have no driver there (the guide on mouse, keys and fingers says what was tried).

Making a Mac app (`roci package macos`) builds, once, the two libraries the app carries: `tools/package-libs.sh macos` (SDL3 and SDL3_ttf from source into `.cache/package/macos/lib`; it needs `cmake`, `ninja`, git and curl, and `roci package` runs it when they are missing). Homebrew's `sdl3_ttf` is not carried because it depends on HarfBuzz's glib, which is LGPL; the copy built here has its own FreeType and HarfBuzz inside. An app is signed so it runs on the Mac that made it, or with a Developer ID when the keychain has one.

Making a Linux app (`roci package linux`) needs, on the Linux computer that makes it, `tar`, `readelf` and `ar` (binutils), and for the formats asked for `zstd` (the RPM and the Arch package) and `mksquashfs` (squashfs-tools, the AppImage) and `curl` (once, for the AppImage runtime); it builds SDL3_ttf once with `tools/package-libs.sh linux` (cmake, git, curl, a C++ compiler and SDL3 with its headers; SDL3_ttf has the C++ library linked into it, which on Fedora needs `libstdc++-static`). From a Mac or a Windows computer, `tools/package-linux-docker.sh <sketch folder> [options]` does it in a container (Podman, or Docker running; the image is built the first time from `tools/ci/package-linux.Dockerfile`, x86-64, so an Apple silicon Mac runs it under emulation and it is slow); the packages come out in the sketch's own `output/package/linux`. To reach older computers, `tools/ci/package-linux-distros.sh <sketch folder> [debian] [ubuntu] [fedora] [arch]` makes the packages on Debian 12 (the `.deb` and the AppImage), Ubuntu 24.04 (a `.deb`), Fedora 43 (the RPM) and Arch (the Arch package) in containers (Podman or Docker, and rsync), into the sketch's `output/package/linux-debian`, `linux-ubuntu`, `linux-fedora` and `linux-arch`; the images are built the first time, a few minutes each.

Making a FreeBSD app (`roci package freebsd`) needs only what FreeBSD has: `pkg`, `tar`, `readelf` and `ldd`, and the libraries you already build with (`pkg install sdl3 sdl3_ttf shaderc spirv-cross`); nothing is carried, so the package depends on those ports and `pkg add` fetches them where they are missing. A package says the release it was made on (`FreeBSD:15:amd64`) and `pkg` installs it only there.

Making an OpenBSD app (`roci package openbsd`) needs what OpenBSD has: `pkg_create`, `pkg_info`, `tar`, `readelf` and `ldd`, and the packages you already build with (`doas pkg_add sdl3 shaderc spirv-cross`). OpenBSD has no package for SDL3_ttf, so the app carries one: the first package builds it with `tools/package-libs.sh openbsd` into `.cache/package/openbsd/lib` (about two minutes; it needs `cmake`, `git` and `curl`, `doas pkg_add cmake git curl`, and SDL3 with its headers), with FreeType and HarfBuzz inside it, so the app asks the computer for SDL3 and the base system only. A package says the processor it was made on and `pkg_add` checks the libraries it asks for by name and number, so make it on the release you want to reach. It is not signed: install it with `pkg_add -D unsigned`.

Making a Windows app (`roci package windows`) needs nothing beyond what compiling needs there (the installer is a small Odin program of rocinante's own, `roci/install/setup`, compiled with the pinned Odin at each package): the Windows SDK of Visual Studio Build Tools has `signtool` and `makeappx`, the two libraries the app carries (`SDL3.dll` and `SDL3_ttf.dll`) are the ones the pinned Odin ships in `vendor/sdl3`, and the zip is made by the `tar` Windows itself has. To sign, a code-signing certificate in the user's certificate store (`--sign` names one when there are several); signing asks DigiCert's time-stamp server, so it needs the internet.

Making an Android app (`roci package android`) needs what putting a test build on a phone needs: the Android SDK and NDK from Android Studio (`ANDROID_HOME` if they are not in the usual place), a JDK (`javac` and `keytool`), and the phone's copy of SDL (`tools/mobile-sdl.sh android`, once); `roci` builds the rest itself, and a phone is needed only to try the APK it makes (`adb install -r`). The first package for an app's id makes its release key in `~/Library/Application Support/rocinante/android` (`~/.local/share/rocinante/android` on Linux): keep a copy of it and of the password file beside it, because only that key can sign an update.

Putting a compiled sketch on a phone (`roci run --compile --target ios|android`) needs the phone's own copies of SDL3 and the libraries above, built once from source into `.cache` (ignored by git): `tools/mobile-sdl.sh ios` (SDL 3.4.18 as a static library; Xcode, `cmake`, `ninja`) and then `SDL_IOS_LIB=$PWD/.cache/mobile/ios SDL_IOS_SRC=$PWD/.cache/mobile/SDL3-3.4.18 spikes/mobile/ios/libs.sh` (SDL3_ttf, shaderc, SPIRV-Cross, Dear ImGui, libcurl with mbedTLS and the sound decoders); for Android the same with `android` and `spikes/mobile/android/libs.sh` (`SDL_ANDROID_LIB=$PWD/.cache/mobile/android`), with the Android SDK and NDK `29.0.14206865` from Android Studio. The iPhone is signed by the development team Xcode knows (`TEAM_ID` or `--team` to choose) and must be paired and unlocked, and its developer trusted once; the Android phone needs USB debugging on and the screen unlocked, and gets the sketch's `assets` in the app's own folder (the debug app is debuggable so that `adb shell run-as` can copy them there). `roci run --compile --target` runs `libs.sh` itself each time, and `libs.sh` builds a library when it is missing or when what it is made from changed: a pinned tag or build setting in the script, or our own files it compiles (`vendor/sound/c`, `vendor/imgui/c`, the scripts naming libcurl's and libopus's versions), recorded in a stamp per library in `.cache/ios/stamps` or `.cache/android/stamps`; with nothing changed it costs a few checksums. Each fetched source sits in a folder named after its tag, so a new tag is fetched afresh. The Android emulator (`--target android-emulator`) reuses the phone's libraries and needs only an arm64 virtual device (`emulator -list-avds`); there is no iOS Simulator target, because its Metal device is too small for SDL's GPU API. `roci doctor` checks the tools for this computer.

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
