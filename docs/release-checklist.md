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

## Linux and the BSDs: everything to try (CachyOS, FreeBSD, OpenBSD)

These systems were last tried in full before text, shaders, canvases, export and the whole user interface. Go through all of it on each, and write down what differs in the results table's notes. Everything in the first list must pass before anything else is worth trying.

**1. Setting up and building**
- [ ] The pinned Odin (`odin version` is the `ODIN_VERSION` file; OpenBSD builds it from the source tag, FreeBSD uses the `odin-lang` package when it is that version).
- [ ] SDL3 and SDL3_ttf found by the linker (OpenBSD: the two-number symlink and `ldconfig -m` in the README; `tools/ci/install-sdl3.sh` if a package is old).
- [ ] shaderc and SPIRV-Cross found (`-lshaderc_shared`, the SPIRV-Cross C library). Note the package names on FreeBSD and OpenBSD; the README says they are unconfirmed.
- [ ] `sh tools/ui-libs.sh` builds Dear ImGui with the system's C++ compiler (finds `SDL3/SDL.h` in `/usr/local/include`; the programs link `c++` on FreeBSD and `stdc++` on OpenBSD) and every program that opens a window then links.
- [ ] `sh tools/ui-libs.sh accesskit`: Linux x86-64 downloads the release library; CachyOS arm64 and the BSDs build it from source (`git`, `cmake`, `cargo`, network for Corrosion and crates). Note any system library the link asks for (the generated bindings list `pthread`, `dl`, `m`, and that is a guess beyond Linux x86-64).
- [ ] `odin build cli -out:output/roci -o:speed` links and `output/roci` starts.
- [ ] `odin run build -- ci` passes in full: every package's tests twice (`-o:minimal` and `-o:speed`), the licence check, the generated bindings equal the committed ones (needs `cc`), the ABI check (`tools/abi-check.sh`), and the golden images on lavapipe (`odin run tests/golden`, last line `N pictures, 0 failed`; FreeBSD's manifest path is `/usr/local/share/vulkan/icd.d/lvp_icd.x86_64.json`). Run a failing test with `-keep-executable` several times to see whether it is flaky.
- [ ] `odin run build -- docs` builds the site (Hugo of the pinned version, drawn on lavapipe).
- [ ] `roci new`, `init`, `get`, `update` with git (and Git LFS if installed), a sketch inside a git repository, and `roci test --accept` then `roci test` on `examples/checks`.

**2. Windows, drawing and text (every example)**
- [ ] Run **every folder in `examples/`** (`roci run examples/<name>`) and compare each with its picture in `tests/golden/`: shapes, style, gradients, transforms, text, pictures, canvases, blend, clip, fills (picture, stroke, text), pixels and filters, `outline`, tweens, tables, the turtle, collision, touch.
- [ ] Wayland and X11 both (CachyOS and FreeBSD: a Wayland session and an X11 one; OpenBSD: X11, and the XWayland fallback on a Wayland session). Window size, `resizable false`, position, borderless, topmost, fullscreen, `ratio`, `cursor none`, several windows, a window `parent` and `modal`, closing one of two windows, Ctrl+Q, the window's close button, Escape not quitting.
- [ ] Display scaling: a scaled display (Wayland fractional scale, X11 `Xft.dpi`) draws sharp at the right size, and `width`, `height`, the mouse and the interface agree.
- [ ] Live reload: save a sketch (and another file of the folder) and it reloads keeping its values; a mistake shows the overlay and the last good frame stays; Ctrl+R restarts.
- [ ] Fonts: Inter is used with no font installed; `font "Name"` finds an installed font (the folders on each system, `.ttc` collections, copying into `assets/fonts` and the `Font_Licence` notice); other scripts through the system's fallback fonts (CJK, Arabic, Devanagari: note which fonts each system has) and emoji.
- [ ] Shaders: the built-in `effect`s, a sketch's own `.hlsl` effect and `shade`, effects on a canvas, hot reload when the shader file is saved, the message when a shader is broken (`examples/neon`, `smoke`, `glass`, `tunnel`).
- [ ] Export: `save` to PNG, SVG and PDF (open the SVG and PDF in a viewer), a `#` frame sequence, `record` to `.apng` and, with `ffmpeg` installed, to `.mp4` and `.gif`; the message that teaches how to install ffmpeg when it is missing.
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

**4b. The screen reader on Windows** (new: the adapter is written, not yet tried; `sh tools/ui-libs.sh accesskit` in Git Bash fetches the library, which needs `curl` and `unzip` or PowerShell)
- [ ] The build links: `odin build cli -o:speed -out:output/roci.exe` with the library in `.cache/ui/accesskit/accesskit.lib`. If the link fails, send the messages first (the system libraries of the foreign import, or a clash between the static C runtime Odin links and the one the library was built with, are the things not checked).
- [ ] A sketch with widgets (`examples/ui`) starts: the window blinks once at the start (it is hidden while the adapter is made) and then behaves as it always did. If the program stops with a Rust panic message, say so first.
- [ ] Narrator (Win+Ctrl+Enter) and NVDA each: read the panel, each widget's name and value, the tabs and the progress bar; press the button, increment the slider, set a number, type in a text box, choose in the drop-down, radio buttons and list, select a tab, fold the panel (UI Automation roles are the part most likely to need a change).
- [ ] The backtick says "controls hidden, press backtick to show", then the first widget when shown again.
- [ ] On a display scaled to 150% or 200%: the screen reader's highlight and Narrator's touch exploration land on the right widget (node bounds are the window's device pixels); drag the window to a display of another scale and check again.
- [ ] The reader keeps working while the sketch reloads and restarts, and when a second window opens or closes.
- [ ] Windows: whether Inspect (from the Windows SDK) or Accessibility Insights shows the program with its window and widgets, compared with `tests/ui-tree/ui.txt`.

**5. Tests that need a real system**
- [ ] IME composition (above), clipboard, a real touch screen (`examples/touch` with several fingers, numbered in order, never reused), a stylus if there is one.
- [ ] `roci/folder`'s tests in a real git clone (they need a repository), and the `roci/movies` tests (they start a process).

## Results

| Version | FreeBSD | macOS | OpenBSD | Windows | iOS | Android | Notes |
|---|---|---|---|---|---|---|---|
