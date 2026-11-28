# Release checklist

Work through this before tagging `vYYYY.MINOR.MICRO`. Record the results in the table at the bottom, one row per version. A release has a download for each host, FreeBSD, Linux, macOS, OpenBSD and Windows, and none for iOS or Android, which are targets only: `roci` never runs on a phone, so a phone gets a sketch as an app its author packaged. The Linux download comes from the tag pipeline; the other hosts' are built and checked locally, and the phones are checked as targets.

## Before the tag

- [ ] `main` is green on GitLab (Arch) and GitHub (Ubuntu).
- [ ] `ODIN_VERSION` is the Odin release this version was built and tested with.
- [ ] `README.md` status and build instructions are current.
- [ ] Anything that breaks existing sketches, the stable verb ABI or `ui.toml` is written down for the top of the release notes, with the fix for each.

## On each platform

For FreeBSD, macOS, OpenBSD and Windows: build on that system, run every example, run the golden-image suite and the back-end equivalence suite, and build the platform's download. For iOS and Android, which have no download: package from a host that can (a Mac for iOS; macOS, Linux x86-64 or Windows for Android), install on a real device, and run every example there.

Where someone has a mid-range laptop, run `examples/benchmark` on it and note the frame rate (Phase 1 used an older desktop as a stand-in).

On the iPhone, also play `examples/touch` with several fingers: they should be in the right places, numbered in order and never reused, and gone when they lift (checked on the Pixel 9 in Phase 2; the iPhone was moved here when Phase 2 closed).

## Packaging a Mac app

`roci package macos` is only tried by hand (the unit tests cover its plist, names, settings and the libraries it points a program at, not the tools it runs). On a Mac:

- [ ] `output/roci package macos examples/circle --yes` makes `output/package/macos/circle.app` and its zip; `otool -L circle.app/Contents/MacOS/circle` lists only `/System`, `/usr/lib` and `@rpath` libraries; `codesign --verify --deep --strict circle.app` says nothing; double-clicking the app opens the window.
- [x] (2026-11-23, a Mac) `roci package macos --format all` on a copy of `examples/bricks` makes the app, a `.dmg` (mounted: the app and an Applications shortcut, signature verified) and a `.zip`.
- [ ] The disk image signed with a Developer ID, notarised and stapled (`xcrun stapler validate` on it); needs a Developer ID and a notary profile.
- [ ] A sketch with assets, fonts and a vault (a copy of a game) shows its font and its sounds in the app, and its `vault.key` and `memory.toml` appear in `~/Library/Application Support/<its id>` the first time; `save` writes into that folder's `output`.
- [ ] On a terminal, the first `roci package macos` asks the name, the id and the version, writes `sketch.toml`, and the second run asks nothing and raises `build` by one.
- [ ] `roci package macos --icon logo.svg` (a square drawing) puts it in `icons/icon.svg`, makes `icons/macos/<name>.iconset` and the other systems' icons, and the app shows the icon in Apple's rounded square in Finder and the Dock, with no gray frame; a second run makes no icons; a hand-made `icon_16x16.png` is kept; an oblong drawing or a 512-pixel PNG is refused before anything compiles.
- [ ] With a Developer ID in the keychain, the app is signed with it (`codesign -dv` shows the authority and the hardened runtime); with `--notarize <profile>` notarytool says Accepted, the app is stapled, and `spctl --assess --type execute -v` accepts it. Not tried yet: no Developer ID was available when it was written.
- [ ] The app on another Mac (copy the zip, no rocinante installed) opens after Control-click, Open, and asks for the microphone with the sentence in its Info.plist when the sketch uses `mic`.
- [x] (2026-11-23: the plists and entitlements read for `circle`, `music` and `webcam`, all of which started under the hardened runtime; Fabrizio: WILDVEX no longer asks for the microphone) An app of a sketch that never reads `mic` or `webcam` (a copy of `examples/circle`, or WILDVEX) has no `NSMicrophoneUsageDescription` or `NSCameraUsageDescription` in its Info.plist and no entitlement in `codesign -d --entitlements -`, and starts without macOS asking for the microphone or the camera (`log stream --predicate 'subsystem == "com.apple.TCC"'` shows no request); `examples/music` gets the microphone only and `examples/webcam` the camera only.
- [ ] After a change to SDL or SDL_ttf in `tools/package-libs.sh`, delete `.cache/package/macos` so the libraries are built again.

## Packaging a Linux app

`roci package linux` is tried by hand on a real Linux computer (the unit tests cover the names, the control files, the desktop entry and what the libraries are read from; a container under emulation checked the files and a run with no window, 2026-11-21). On CachyOS, and again on an older Debian or Ubuntu with the packages of an older build (see the glibc note it prints):

- [ ] `roci package linux examples/circle --yes --format all --maintainer "Name <you@example.org>"` makes the five files in `output/package/linux`, and says which glibc and libstdc++ they need.
- [ ] The `.tar.gz` unpacked on another computer (no rocinante, no SDL) opens a window with its program, with the picture drawn; Wayland and X11 both.
- [ ] `sudo pacman -U` the Arch package: the app is in the menu with its icon, `circle` starts it, `pacman -Qk circle` is clean and `sudo pacman -R circle` takes it away.
- [ ] `sudo apt install ./circle_1.0.0_amd64.deb` on a Debian or Ubuntu new enough for its `libc6` dependency: the app is in the menu with its icon, `circle` starts it, `apt remove circle` takes it away.
- [ ] `sudo dnf install ./circle-1.0.0-1.x86_64.rpm` on a Fedora new enough for its glibc dependency (an older one refuses it with `nothing provides libc.so.6(GLIBC_…)`, rightly): the app is in the menu with its icon, `circle` starts it, `rpm -V circle` is clean and `sudo dnf remove circle` takes it away.
- [ ] The AppImage: `chmod +x` and run it (with FUSE), and with `APPIMAGE_EXTRACT_AND_RUN=1` without; it opens a window; `--appimage-extract` shows the same files as the tar.
- [ ] A sketch with assets, fonts, sounds and a vault (a copy of a game) shows its font and plays its sounds in each of the five, and its `vault.key` and `memory.toml` appear in `~/.local/share/<its id>` the first time.
- [ ] A sketch that uses `effect "x.hlsl"` or `shade` (so shaderc and SPIRV-Cross are used at run time) works in the tar and the AppImage with none of them installed, and in the Arch package with its dependencies.
- [ ] With `icons/icon.svg`, the `.deb`, RPM and Arch package install every hicolor size and the drawing, and the menu shows the icon sharp at its small and large sizes.
- [ ] `roci package linux --format deb --maintainer oops` is refused with a message about the maintainer; `--format snap` says the formats; a missing tool (`mksquashfs`) is named with how to get it.
- [ ] `tools/package-linux-docker.sh` from a Mac makes the same files from a sketch folder.
- [ ] `tools/ci/package-linux-distros.sh examples/circle` makes the Debian 12, Ubuntu 24.04, Fedora 43 and Arch packages, and each installs and runs on the newest release of its distribution.

## Packaging a FreeBSD app

`roci package freebsd` is tried by hand on a FreeBSD computer (the unit tests cover the names, the manifest, the checksums, the library owners and the tree; written 2026-11-22 and run on FreeBSD 15.1 amd64 up to reading the package back with `pkg info -F` and starting the unpacked program):

- [ ] `roci package freebsd examples/circle --yes --maintainer "Name <you@example.org>"` makes the `.pkg` and the `.tar.gz` in `output/package/freebsd`, and prints the ABI and the packages the app depends on.
- [x] (2026-11-22, FreeBSD 15.1 desktop) `doas pkg add circle-1.0.0.pkg` installs it (with `sdl3`, `sdl3_ttf`, `shaderc` and `spirv-cross` fetched when missing): `pkg info circle` and `pkg info -l circle` list what is expected, `circle` starts it from a terminal, and `pkg check -s circle` and `pkg delete circle` leave nothing behind.
- [x] (2026-11-22, Wayland, icons confirmed; X11 untried) The menu entry and its icon show in a desktop (X11 and Wayland), and the window's app id is the sketch's id.
- [ ] The `.tar.gz` unpacked on a FreeBSD with nothing of rocinante installed runs its program after the `pkg install` line of its `README.txt`.
- [ ] A sketch with assets, fonts, sounds and a vault shows its font and plays its sounds from the package, and its `vault.key` and `memory.toml` appear in `~/.local/share/<its id>` the first time.
- [ ] `roci package freebsd --format rpm` is refused with the formats said; on a computer with `pkg` taken out the missing tool is named.
- [ ] A package made on FreeBSD 15 is refused by `pkg add` on 14 (the ABI), and one made on 14 is tried on 15.

## Packaging an OpenBSD app

`roci package openbsd` is tried by hand on an OpenBSD computer (the unit tests cover the names, the packing list, the ldd lines, the package names and the library numbers; written 2026-11-23 and run on OpenBSD 8.0 amd64 up to the `pkg_add` dry run and starting the unpacked program with no window):

- [x] (2026-11-23, OpenBSD 8.0 amd64) `roci package openbsd examples/circle --yes --maintainer "Name <you@example.org>"` makes the `.tgz` and the `.tar.gz` in `output/package/openbsd` (the first time it builds the SDL3_ttf the app carries, about two minutes), and prints the packages the app depends on.
- [x] (2026-11-23) `pkg_add -n -D unsigned ./circle-1.0.0.tgz` says the package is ok, with `sdl3`, `shaderc` and `spirv-cross` as its dependencies and the libraries it asks for listed.
- [x] (2026-11-23) The `.tar.gz` unpacked in another folder runs its program from a third one with no window, and loads its own `libSDL3_ttf.so.0` from the `lib` beside it and SDL3 from the system.
- [x] (2026-11-23, Fabrizio, OpenBSD 8.0 amd64) `doas pkg_add -D unsigned ./circle-1.0.0.tgz` installs it (from the folder it is in: a bare file name is taken for a package on a mirror) and the app works.
- [ ] `pkg_info circle` and `pkg_info -L circle` list what is expected, and `pkg_delete circle` leaves nothing behind.
- [ ] The menu entry and its icon show in a desktop, and the window's app id is the sketch's id.
- [ ] The `.tar.gz` unpacked on an OpenBSD with nothing of rocinante installed runs its program after the `pkg_add` line of its `README.txt`.
- [x] (2026-11-23, Fabrizio) WILDVEX, with assets, fonts, shaders and a vault, runs in a window from the package. The first package printed that `ripple.hlsl` and the Aileron fonts were not in the assets folder: the app had kept the folder string SDL owns, which SDL frees when a window that fails to start quits it before the retry on X11, and OpenBSD reuses freed memory at once (fixed in `rt.use_home`, which keeps a copy).
- [ ] The sounds of such a sketch play from the package, and its `vault.key` and `memory.toml` appear in `~/.local/share/<its id>` the first time.
- [ ] `roci package openbsd --format rpm` is refused with the formats said; on a computer with `pkg_create` taken out the missing tool is named.
- [ ] A package made on one OpenBSD release is tried on the next (its libraries have other numbers), and one made on arm64 is tried.

## Packaging a Windows app

`roci package windows` is tried by hand on a Windows computer (the unit tests cover the formats, the names, the four-number version, the resource script, the MSIX manifest, the import tables, the certificate list and the choice of a certificate; written 2026-11-23 and run on Windows 11 with a self-signed certificate):

- [x] (2026-11-23, Windows 11) `roci package windows examples/circle --yes` makes the app's folder and `circle-1.0.0-windows-x64.zip` in `output/package/windows`; the folder holds the program, `SDL3.dll`, `SDL3_ttf.dll` and the notices, and the zip holds the folder.
- [x] (2026-11-23) The packaged program, started from another folder (`Start-Process -Wait` with `--frames 2 --screenshot`), draws the sketch; `examples/voyage`'s draws lit, shadowed and with its textured model from the app's `assets`; `(Get-Item x.exe).VersionInfo` says the name and `1.0.0.<build>`, and Explorer shows the icon made for it.
- [x] (2026-11-23) With a code-signing certificate in the user's store (a self-signed one), `roci package windows --format all` finds it without `--sign`; `Get-AuthenticodeSignature` says Valid, time-stamped, for the program, the two DLLs and the MSIX.
- [x] (2026-11-23) With that certificate in `LocalMachine\TrustedPeople`, `Add-AppxPackage` installs the MSIX; the app is in the Start menu, starts from `C:\Program Files\WindowsApps` in a window, and `Remove-AppxPackage` takes it away.
- [ ] The zip unpacked on a Windows computer with nothing of rocinante (no Odin, no Visual Studio) runs by double-clicking the program, and SmartScreen says what `roci package` said it would, unsigned and signed.
- [ ] Opening the `.msix` in Explorer installs it through App Installer (not only `Add-AppxPackage`), and Settings, Apps removes it.
- [ ] A sketch with a vault, fonts and sounds plays its sounds and shows its font from the zip and from the installed MSIX, and its `vault.key` and `memory.toml` appear in `%APPDATA%\<its id>` the first time (the MSIX's are redirected to the package's own folder).
- [ ] A sketch that uses `mic` or `webcam`: the MSIX asks Windows for them, and one that does not is not listed under the microphone in Settings, Privacy.
- [ ] `--sign` with a thumbprint and with a part of a name; `--sign` naming no certificate stops before anything is built; two certificates and no `--sign` stop with the question.
- [ ] A certificate from an authority, and SmartScreen's warning with it; Windows 10; an arm64 Windows (the app is x64 and would run emulated).
- [x] (2026-11-23, Windows 11) The installer (`--format setup`, made by default): `Get-AuthenticodeSignature` says it and its `uninstall.exe` are Valid; `setup.exe /S` from an elevated prompt installs into `C:\Program Files\<name>` with the Start menu shortcut and the entry in `HKLM\...\Uninstall\<id>`; the app starts from the shortcut as the user; a newer version installs over it; installing while the app is open exits 3 and leaves it whole; `uninstall.exe /uninstall /S` removes the folder, the shortcut and the entry.
- [ ] The installer run by double-clicking: Windows asks for an administrator, its question and its message are clear and read by Narrator, and Settings, Apps shows the app with its icon, version, publisher and size, and its Uninstall button asks and removes it.
- [ ] `setup.exe /S /D=D:\Apps\Name` installs there, and uninstalling removes only that folder; `/D=` naming a folder with other files in it stops with the message.
- [ ] An unsigned installer: SmartScreen's warning, and Windows' administrator question showing an unknown publisher.
- [ ] A sketch of a few hundred megabytes of assets installs (the installer reads itself into memory), and how long it takes.

## Packaging an Android app

`roci package android` is tried by hand with a phone (the unit tests cover the id rules, the manifest, the orientation and category words and the key paths, not the SDK's tools). On a Mac, with the phone's tools set up (`tools/mobile-sdl.sh android`) and the Pixel 9 plugged in, unlocked, with USB debugging on:

- [x] (2026-11-23, a Mac, the Pixel 9) `roci package android` on a copy of `examples/bricks` (with an id, `orientation = "portrait"` and `category = "game"`) makes `output/package/android/<name>-<version>-android-arm64.apk`; `aapt2 dump badging` shows its id, versionCode (the build number), versionName, label and adaptive icon, `dump xmltree` the portrait orientation and the game category and no `debuggable`, and `apksigner verify --print-certs` its signature.
- [x] (2026-11-23) `adb install -r` installs it, it starts full-screen in portrait, and its game is in play; installing the next build over it unpacks the sketch's files again (`adb logcat -s rocinante` says how many) and keeps it running, and starting it a second time unpacks nothing.
- [x] (2026-11-23) The first package for an id makes the release key in `~/Library/Application Support/rocinante/android` (a mode-600 password file beside it) and says to keep a copy; the next uses it.
- [x] (2026-11-23) `roci run --compile --target android` still puts a test build on the phone.
- [x] (2026-11-23, Fabrizio, the Pixel 9) WILDVEX, with all its assets, fonts, shaders and vault, packaged with `roci package android`, installs with `adb install -r`, starts and works.
- [ ] The sounds of the sketch are heard on the phone, and WILDVEX keeps its `vault.key` and `memory.toml` in the app's folder across an update; how long the first start of a sketch with hundreds of megabytes of assets takes (not measured).
- [ ] An update signed with the same key replaces the installed app and keeps what it remembered; one signed with another key is refused by the phone (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`).
- [ ] A sketch that uses `mic` or `webcam` has `RECORD_AUDIO` or `CAMERA` in its manifest and the phone asks when it uses them; one that uses neither has neither.
- [ ] `roci package android` on a Linux x86-64 and a Windows computer; on another phone and another Android version.
- [x] (2026-11-23, a Mac, the Android emulator) `roci package android --format all` makes the APK and a `.aab`; bundletool validates it, builds the apps for the emulator from it (`base` and `config.arm64_v8a`), they install, the app starts and unpacks its files.
- [x] (2026-11-26 and 27, a Mac) Target API level 36 (raised from 34): WILDVEX built for it ran on the Pixel 9 (Android 17, API 37, 4 KB pages), and the `.aab` of WILDVEX 0.2.4 says `targetSdkVersion` 36, `minSdkVersion` 28, `versionCode` 35 and one permission (vibrate). bundletool validates it; its five native libraries (`libmain`, SDL3, SDL3_ttf, shaderc, SPIRV-Cross) have `PT_LOAD` segments aligned to 0x4000, which Play asks of an app that targets Android 15 or later since 2025-11-01 (16 KB pages; read from the files, not run: the Pixel 9 uses 4 KB pages, and a 16 KB phone or emulator image is untried); it is signed with the release key (2048-bit RSA, valid to 2054, Play wants 2033 or later) and needs Vulkan 1.0.3 (`android.hardware.vulkan.version` required), which keeps the app off phones without it.
- [ ] The `.aab` uploaded in the Play Console (an internal testing track) and installed from Play, on a paid developer account; what the Console asks for besides the file (the store listing and its graphics, the privacy policy address, the Data safety form, the content rating, the target audience, the news and ads declarations); the app run from Play on the Pixel 9; a Linux and a Windows host (the downloads there are pinned but never run).

## Packaging an iPhone app



`roci package ios` is tried by hand with a phone (the unit tests cover the id, orientation and colour words, the `Info.plist` and the catalog files).



- [x] (2026-11-23, a Mac) `roci package ios` on a copy of `examples/bricks` makes the app and the `.ipa`: its own id, name, version, build, icon pictures and compiled catalog, signed by the development team.

- [x] (2026-11-23, Fabrizio, the iPhone 13 Pro) WILDVEX packaged with `roci package ios` installs and works.
- [ ] The app starts in the orientation asked for and shows the launch colour while it starts; its icon is the sketch's.

- [ ] WILDVEX (all its assets) packaged for the iPhone installs and works; its sounds are heard.

- [ ] A sketch that uses `mic` or `webcam` makes the phone ask; one that uses neither never does.

- [x] (2026-11-23, a Mac, a free account) `roci package ios --app-store` archives the app and the export stops with Xcode's "Team does not have permission to create iOS App Store provisioning profiles", which `roci` explains in plain words.
- [ ] With a paid Apple Developer Program team: `--app-store` makes a signed `.ipa`, `--upload` sends it to App Store Connect, and the build shows under TestFlight; the encryption question; an app record with the bundle id (untried).
## Linux and the BSDs: everything to try (CachyOS, FreeBSD, OpenBSD)

These systems were last tried in full before text, shaders, canvases, export and the whole user interface. Go through all of it on each, and write down what differs in the results table's notes. Everything in the first list must pass before anything else is worth trying.

**1. Setting up and building**
- [ ] The pinned Odin (`odin version` is the `ODIN_VERSION` file; OpenBSD builds it from the source tag, FreeBSD uses the `odin-lang` package when it is that version).
- [ ] SDL3 and SDL3_ttf found by the linker (OpenBSD: the two-number symlink and `ldconfig -m` in the README; `tools/ci/install-sdl3.sh` if a package is old).
- [ ] shaderc and SPIRV-Cross found (`-lshaderc_shared`, the SPIRV-Cross C library). Note the package names on FreeBSD and OpenBSD; the README says they are unconfirmed.
- [ ] `sh tools/ui-libs.sh` builds Dear ImGui with the system's C++ compiler (finds `SDL3/SDL.h` in `/usr/local/include`; the programs link `c++` on FreeBSD and `stdc++` on OpenBSD) and every program that opens a window then links.
- [ ] `sh tools/ui-libs.sh accesskit`: Linux x86-64 downloads the release library; CachyOS arm64 and the BSDs build it from source (`git`, `cmake`, `cargo`, network for Corrosion and crates). Note any system library the link asks for (the generated bindings list `pthread`, `dl`, `m`, and that is a guess beyond Linux x86-64).
- [ ] `odin build cli -out:output/roci -o:speed` links and `output/roci` starts.
- [ ] `odin run build -- ci` passes in full: every package's tests twice (`-o:minimal` and `-o:speed`, but `roci/builds` once), the licence check, the generated bindings equal the committed ones (needs `cc`), the ABI check (`tools/abi-check.sh`), and the golden images on lavapipe (`odin run tests/golden`, last line `N pictures, 0 failed`; FreeBSD's manifest path is `/usr/local/share/vulkan/icd.d/lvp_icd.x86_64.json`). Run a failing test with `-keep-executable` several times to see whether it is flaky.
- [ ] `odin run build -- docs` builds the site (Hugo of the pinned version, drawn on lavapipe).
- [ ] `roci new`, `init`, `get`, `update` with git (and Git LFS if installed), a sketch inside a git repository, and `roci test --accept` then `roci test` on `examples/checks`.

**2. Windows, drawing and text (every example)**
- [ ] Run **every folder in `examples/`** (`roci run examples/<name>`) and compare each with its picture in `tests/golden/`: shapes, style, gradients, transforms, text, pictures, canvases, blend, clip, fills (picture, stroke, text), pixels and filters, `outline`, tweens, tables, the turtle, collision, touch.
- [ ] Wayland and X11 both (CachyOS and FreeBSD: a Wayland session and an X11 one; OpenBSD: X11, and the XWayland fallback on a Wayland session). Window size, `resizable false`, position, borderless, topmost, fullscreen, `ratio`, `cursor none`, several windows, a window `parent` and `modal`, closing one of two windows, Ctrl+Q, the window's close button, Escape not quitting.
- [ ] Display scaling: a scaled display (Wayland fractional scale, X11 `Xft.dpi`) draws sharp at the right size, and `width`, `height`, the mouse and the interface agree.
- [ ] Live reload: save a sketch (and another file of the folder) and it reloads keeping its values; a mistake shows the overlay and the last good frame stays; Ctrl+R restarts.
- [ ] Fonts: Inter is used with no font installed; `font "Name"` finds an installed font (the folders on each system, `.ttc` collections, copying into `assets/fonts` and the `Font_Licence` notice); other scripts through the system's fallback fonts (CJK, Arabic, Devanagari: note which fonts each system has) and emoji.
- [ ] Shaders: the built-in `effect`s, a sketch's own `.hlsl` effect and `shade`, effects on a canvas, hot reload when the shader file is saved, the message when a shader is broken (`examples/neon`, `smoke`, `glass`, `tunnel`). A sketch whose effect begins a few seconds in (`draw [ if time > 3 [ effect "glow" ] ]`) run with `--stats` and with `--compile --stats`: the summary's worst frame stays near the others, on each system and on the phones.
- [ ] Export: `save` to PNG, SVG and PDF (open the SVG and PDF in a viewer), a `#` frame sequence, `record` to `.apng` and, with `ffmpeg` installed, to `.mp4` and `.gif`; the message that teaches how to install ffmpeg when it is missing.
- [ ] macOS fullscreen: `window size 800 600 fullscreen true` with a line at the bottom of the window fills the screen at its first frame with no slide and the line on screen, interpreted, compiled and packaged; `set w fullscreen false` and back work; a sketch without it keeps the green button and the slide.
- [ ] `fps`: `roci run --stats examples/metronome` on a screen of 120 or 144 Hz (and on a 60 Hz one): keys 1 and 2 show about 30 and 60 in the box, 3 the screen's rate, the dot keeps the same speed at 1 and 2 whatever the screen, and on 144 Hz the box says `uneven at 144 Hz`; the same compiled (`--compile --stats`); on the phones, the packaged example at 30 and 60 on the iPhone 13 Pro (ProMotion) and the Pixel 9 (120 Hz); on Windows, whether the frames are even (the summary's slowest hundredth near the average).
- [ ] `examples/benchmark -o:speed` (100,000 circles) frame rate, with and without vsync; and which Vulkan driver was used (`VK_LOADER_DEBUG=driver`). On OpenBSD say whether Vulkan works at all on that GPU or only lavapipe.

**3. The user interface** (`examples/ui`, `dials`, `imagebuttons`, `follow`, and the two-window examples `windows` and `two_windows`)
- [ ] Every widget with the mouse and with the keyboard alone: Tab and Shift+Tab, Enter and Space, arrows (knob, range, pad, drop-down, list), tabs, the menu, the panel folding, tooltips, the colour picker. A placed widget (`at`) is reached with Ctrl+Tab; a widget that follows a dot in `follow` stays on it when the window is resized or moved.
- [ ] Text boxes: typing, selection, the clipboard (copy and paste between the sketch and another program, on X11 and on Wayland), a multi-line box, a number typed outside its range; typing in another script, and an input method (ibus or fcitx on Linux and FreeBSD, whatever OpenBSD has) composing Japanese or Chinese, with the candidate window beside the box.
- [ ] The backtick hides and shows the interface on a US layout and on one where the key sits elsewhere (it is read by position); `ui key "f1"`; the key leaves a text box alone while typing; on a touch screen, three fingers tapping.
- [ ] `ui.toml`: created beside a `sketch.roci` after the first change, written again after a second of stillness and at quit, read back on the next run, not made for a lone file; a read-only folder says nothing and does not crash; `forget ui` resets.
- [ ] `examples/imagebuttons`: the picture shows on the button on the GPU drivers you have.
- [ ] A canvas, an effect and the interface together in one window; the interface drawn over the picture also in `save` and `record`.

**4. The screen reader** (new: the Linux, FreeBSD and OpenBSD adapter, first run with Orca on FreeBSD 15.1 under Wayland on 2026-11-09)
- Found so far on FreeBSD (`orca-47.5_1` is a package; `at-spi2-core`, `espeak-ng` and `speech-dispatcher` were installed): the program appears in the AT-SPI registry only once a reader has made `org.a11y.Status` `IsEnabled` true, and about 15 seconds after it starts; its tree has the names, nesting and roles of `tests/ui-tree/ui.txt`; pressing a button, setting a slider and a spin button and clicking a check box through AT-SPI changed the sketch. A `Label` has no name for AT-SPI unless its words are the node's value (fixed). What Orca says aloud was listened to on 2026-11-10: Fabrizio reported that Orca works on FreeBSD and on OpenBSD (OpenBSD: `espeak`, `speech-dispatcher`, `at-spi2-core`, `orca`; `espeak-ng` is no package there) and that the rest of this checklist passes on both. The boxes below are left for each release to tick; Linux: CachyOS under niri (Wayland), 2026-11-10, with `orca`, `at-spi2-core`, `speech-dispatcher` and `espeak-ng`: Orca reads the widgets. The same run on all three systems found the slider, check box, number box, drop-down, radio buttons and the pulse button not spoken when changed; Orca's debug log (`orca --replace --debug-file=FILE`) showed it speaks a change only from what it holds as the focus, and the tree had no focus on a radio button, a list entry, the number box's steps or an open drop-down, while the arrow keys moved the focus off a slider and a number box (fixed 2026-11-11). The check box was spoken when pressed with Space; a progress bar is spoken at most every 10 seconds (Orca's default), which is why `pulse` seemed to work once, and a line of text that changes (`pulses: 3`) is not spoken (that needs a live region, open question 4).
- [ ] The session has a D-Bus session bus and the AT-SPI service (`at-spi2-core`); on GNOME `gsettings set org.gnome.desktop.interface toolkit-accessibility true`; on FreeBSD and OpenBSD note which packages and which desktop made it work, or that it did not. Say whether Orca exists as a package on each.
- [ ] `accerciser` (or `busctl --user tree`) shows the program with its window and widgets; compare with `tests/ui-tree/ui.txt`. If a program never appears, say so first: that is whether the adapter registers at all.
- [ ] Orca reads the panel, each widget's name and value, the tabs and the progress bar; presses the button, increments the slider, sets a number, types in a text box, chooses in the drop-down, radio buttons and list, selects a tab, folds the panel.
- [ ] The backtick says "controls hidden, press backtick to show", then the first widget when shown again.
- [ ] Where the window is on screen (X11): Orca's mouse review and a click-through land on the right widget; on a scaled display they may be off (node bounds are logical pixels); under Wayland the position is unknown.
- [ ] Orca keeps working while the sketch reloads and restarts, and when a second window opens or closes.

**4a. Direct3D 12 on Windows** (Windows draws with Direct3D 12 only, and nothing of Vulkan may be installed for it)
- [ ] `odin run build -- ci` from Git Bash started inside `vcvars64.bat` (it builds `roci_ui.lib` with MSVC when missing) passes with no Vulkan SDK, shaderc or SPIRV-Cross on the computer.
- [ ] `odin run tests/golden` says `GPU driver direct3d12` even on a computer with a Vulkan driver, and `effects`, `shader_fills` and `example_neon_1`, `example_tunnel_1`, `example_smoke_1` are within its limits (they are a sketch's own shaders, compiled by Windows' FXC).
- [ ] `roci run examples/effects`: editing the shader file while it runs reloads it, and a mistake in it says the line (in FXC's words).

**4b. The screen reader on Windows** (Narrator and NVDA checked on 2026-11-11 with `examples/ui`; `sh tools/ui-libs.sh accesskit` in Git Bash fetches the library, which needs `curl` and `unzip` or PowerShell)
- [ ] The build links: `odin build cli -o:speed -out:output/roci.exe` with the library in `.cache/ui/accesskit/accesskit.lib`. If the link fails, send the messages first (the system libraries of the foreign import, or a clash between the static C runtime Odin links and the one the library was built with, are the things not checked).
- [ ] A sketch with widgets (`examples/ui`) starts: the window blinks once at the start (it is hidden while the adapter is made) and then behaves as it always did. If the program stops with a Rust panic message, say so first.
- [ ] Narrator (Win+Ctrl+Enter) and NVDA each: read the panel, each widget's name and value, the tabs and the progress bar; press the button, increment the slider, set a number, type in a text box, choose in the drop-down, radio buttons and list, select a tab, fold the panel (UI Automation roles are the part most likely to need a change).
- [ ] The backtick says "controls hidden, press backtick to show", then the first widget when shown again.
- [ ] On a display scaled to 150% or 200%: the screen reader's highlight and Narrator's touch exploration land on the right widget (node bounds are the window's device pixels); drag the window to a display of another scale and check again.
- [ ] The reader keeps working while the sketch reloads and restarts, and when a second window opens or closes.
- [ ] Windows: whether Inspect (from the Windows SDK) or Accessibility Insights shows the program with its window and widgets, compared with `tests/ui-tree/ui.txt`.
- [ ] Before listening, with `output\roci.exe run examples/ui` open, the tree and the actions through UI Automation, pasted into PowerShell (it prints each node's role, name, value and bounds, then presses `pulse`, sets the slider, chooses `outline` and reads them back; compare the tree with `tests/ui-tree/ui.txt`, and expect `size 40` and `outline True` at the end, and the window's `pulses` count going up). This is how the radio buttons' missing selection was found on 2026-11-11:

  ```
  Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
  $A = [System.Windows.Automation.AutomationElement]
  $id = (Get-Process roci | Select-Object -First 1).Id
  $win = $A::RootElement.FindFirst('Children', (New-Object System.Windows.Automation.PropertyCondition($A::ProcessIdProperty, $id)))
  $walk = [System.Windows.Automation.TreeWalker]::RawViewWalker
  function Show($e, $d) {
    $c = $e.Current; $v = ''
    try { $v = ' value=' + $e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value } catch {}
    try { $v += ' range=' + $e.GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern).Current.Value } catch {}
    ('  ' * $d) + $c.ControlType.ProgrammaticName + ' "' + $c.Name + '"' + $v + ' ' + $c.BoundingRectangle
    $k = $walk.GetFirstChild($e); while ($k) { Show $k ($d + 1); $k = $walk.GetNextSibling($k) }
  }
  Show $win 0
  function Find($n) { $win.FindFirst('Descendants', (New-Object System.Windows.Automation.PropertyCondition($A::NameProperty, $n))) }
  (Find 'pulse').GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
  (Find 'size').GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern).SetValue(40)
  (Find 'outline').GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
  Start-Sleep -Milliseconds 800
  'size ' + (Find 'size').GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern).Current.Value
  'outline ' + (Find 'outline').GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Current.IsSelected
  ```

**5. Tests that need a real system**
- [ ] IME composition (above), clipboard, a real touch screen (`examples/touch` with several fingers, numbered in order, never reused), a stylus if there is one.
- [ ] Gamepads on each system: `output/roci run` a sketch that prints `gamepads` and what each pad's buttons, sticks, triggers and d-pad read as (a PlayStation, an Xbox and a generic pad if there are any); a pad plugged in and out while it runs; `rumble 100 for 1 player n` shakes the pads that can (the Xbox Series X pad did not on macOS, 2026-11-16); unmapped devices appear in `joysticks`. Done on macOS (2026-11-16, four pads), FreeBSD and Linux (below); OpenBSD and Windows still to try.
  - [x] **Linux (CachyOS, kernel 7.3, niri on Wayland), 2026-11-22, the five pads of FreeBSD's check:** the DualShock 4, the DualSense, the Logitech Dual Action, the PowerA Xbox One pad and the Xbox Series X controller all work, with no fix in `pads.odin` (Linux is SDL's home ground), and `rumble` shakes every one that has motors (all but the Logitech), the first system where the Xbox pads shake. A pad plugged in and out while a sketch runs is found and let go, and the DualShock 4, the DualSense and the Xbox Series X controller work over Bluetooth as well as USB (the Logitech and the PowerA pad are wired only).
  - **FreeBSD 15.1, 2026-11-20, over USB, five pads.** The pad must be readable by the user: its evdev nodes (`/dev/input/event*`) are `root:games`, mode 0660, so the user joins the group once (`pw groupmod games -m <user>` as root, then logs in again); without it SDL sees nothing. The drivers are the kernel's own (`hgame`, `ps4dshock`, loaded by `devmatch`); `roci` needs nothing installed.
  - [x] PlayStation 4 (`054c:05c4`, `ps4dshock` and `hgame`): works once `roci/platform/pads.odin` gives SDL the layout the kernel uses. SDL's own mapping is for Linux's older driver and was wrong three ways: L2 and R2 moved the right stick and the resting right stick read as two half-pressed triggers (axes 2 to 5 are L2, right stick x and y, R2, not the other way round), cross, circle, triangle and square pressed the left, bottom, right and top buttons (the buttons are numbered in key-code order, so cross is 0), and the pad's motion sensors, a second evdev device, were listed as a second gamepad (FreeBSD has no udev to mark them as an accelerometer). A device with no buttons is now skipped. Every button, stick, trigger and the d-pad were reported right in `examples/gamepad`. The second model (`09cc`) shares the driver and the fix and was not tried.
  - [x] PlayStation 5 DualSense (`054c:0ce6`, generic `hgame`): works as is, because the kernel's layout is the one SDL's mapping expects (left stick 0 and 1, right stick 2 and 5, L2 and R2 3 and 4, 15 buttons). One device only; no gyro, touchpad position or light bar, which need a driver.
  - [x] Logitech Dual Action (`046d:c216`, generic `hgame`): works as is; its triggers are buttons, so they read 0 or 1, and it has no motors.
  - [ ] `rumble` on FreeBSD: the DualSense does not shake. Its event node lists no force feedback (`EV_FF`), SDL says `cap rumble = false` and "That operation is not supported", and `rumble` does nothing, as for any pad that cannot shake. The DualShock 4 was not tried (its driver's manual lists the light bar and no rumble), and the Logitech has no motors.
  - [x] Xbox One and Series pads over USB do **not** work: the PowerA XBX Spectra Enhanced (`20d6:4002`) and Microsoft's Xbox Series X controller (`045e:0b12`) are class `ff`, subclass `47`, protocol `d0`, the Xbox One protocol, which no FreeBSD driver covers (`xb360gp` is for the Xbox 360's, `ff`/`5d`/`01`), so the pad is a bare `ugen` and its logo keeps blinking. SDL's own driver for that protocol (`SDL_JOYSTICK_HIDAPI_GIP`, over libusb, tried as root with `SDL_JOYSTICK_HIDAPI_XBOX_ONE=1`) finds the pad and then freezes inside SDL's event handling until the program is killed with `kill -9`, so it is not a way out. An Xbox 360 pad through `xb360gp` (`kldload xb360gp`) was not tried; none was at hand.
- [ ] Movies on each system (the C decoder is built from the same file everywhere and has been run on a Mac only): `output/roci run examples/movie` plays a Mandelbrot zoom as a picture, in a circle and in a bar, space pauses it, R rewinds it and a click on the bar puts it there; on both phones too.
- [ ] `roci/folder`'s tests in a real git clone (they need a repository), and the `roci/movies` tests (they start a process).

**6. Sound** (all five desktop systems, and the phones in Phase 8)
- [ ] `odin run build -- sound-libs` builds the decoders; `examples/sound` plays and loops, `examples/player` streams a long file and seeks, and a file saved again is read again into the same sound.
- [ ] The device and its buffer: sound comes out of the default device with no crackle on a loud chord (`examples/soundfont`, `examples/keys`); `SDL_AUDIO_DEVICE_SAMPLE_FRAMES` overrides the 256 frames; `ROCI_LATENCY=1` prints the figures. The microphone asks for permission and `level mic` moves (`examples/music` style sketches).
- [ ] MIDI in on each system's backend (device files, CoreMIDI, WinMM): notes, controls, bend, program, pressure and a clock into `midi tempo`; hot-plugging a keyboard.
- [ ] MIDI out on each: `examples/midiout` reaches a synth (a software one, hardware, Windows' GS Wavetable, `snd-virmidi` on Linux); notes, bend, program and a steady clock into a tempo-synced program.
- [ ] OSC between two computers (and the firewall), `examples/osc`.
- [ ] `examples/recorder`: a take of the speakers plays back in another program; `record mic`; an mp3 with ffmpeg installed and the message without it.
- [ ] File formats: `tests/sounds/tone.*` (WAV, FLAC, MP3, Ogg, Opus, AIFF, AIFC and the 24-bit and float ones) load as sounds; AAC (`tone.m4a` and `tone.aac`) reads on macOS, iOS and Android (tried on 2026-11-16 on the iPhone 13 Pro and the Pixel 9), on Windows (Media Foundation; `vendor/sound`'s AAC test runs there, passed on Windows 11 on 2026-11-16), and on Linux, FreeBSD and OpenBSD reads with ffmpeg installed and says how to get it without; `tools/fetch-opus.sh` fetches and builds libopus on each system (`cc`, or `cl` on Windows).
- [ ] The SoundFont features: `examples/soundfont` with `set piano bend` and `vibrato` (pitch and modulation wheels), and a General MIDI font (FluidR3) for the filter, LFOs and exclusive classes (hi-hats).
- [ ] `tools/abi-check.sh --run` builds and runs `examples/c/player.c`.

## Results

| Version | FreeBSD | macOS | OpenBSD | Windows | iOS | Android | Notes |
|---|---|---|---|---|---|---|---|
