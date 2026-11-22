---
title: "Making a Linux app"
summary: "Turn a sketch into a .tar.gz, a .deb, an RPM, an Arch package or an AppImage with roci package linux: the options, what goes inside, and how to try it."
weight: 33
---

On a Linux computer, `roci package linux` makes an app of a sketch in the formats people install from:

```
roci package linux
roci package linux --format deb,rpm,arch
roci package linux --format all
```

It works in the sketch's folder (or give it a folder), refuses a sketch that has errors as `roci check` does, and asks the name, the id and the version the first time, as the [Mac guide](../32-packaging-a-mac-app/) describes: the answers are kept in `sketch.toml`. The app is made on the computer that packages it: a Mac cannot make a Linux app, and `roci doctor` says what this computer can build.

## The formats

`--format` takes the names below, with commas between them, or `all`. With nothing it makes the `.tar.gz`.

| Word | What it makes | Install it with |
|---|---|---|
| `tar` | `name-1.0.0-linux-amd64.tar.gz`: a folder to unpack anywhere and run | `tar xzf`, then run the program in it |
| `deb` | `name_1.0.0_amd64.deb` for Debian, Ubuntu and what comes from them | `sudo apt install ./name_1.0.0_amd64.deb` |
| `rpm` | `name-1.0.0-1.x86_64.rpm` for Fedora, openSUSE, RHEL and what comes from them | `sudo dnf install ./name-1.0.0-1.x86_64.rpm` (openSUSE: `sudo zypper install`) |
| `arch` | `name-1.0.0-1-x86_64.pkg.tar.zst` for Arch, CachyOS and Manjaro | `sudo pacman -U name-1.0.0-1-x86_64.pkg.tar.zst` |
| `appimage` | `Name-1.0.0-x86_64.AppImage`: one file that runs on its own | `chmod +x`, then run it |

A `.deb`, an RPM and an Arch package put the app in the menus with its icon and give it a command with the app's name (`wildvex`). The packages are made with tools every Linux has (`tar`, `ar`, `zstd`, `mksquashfs`), not with `dpkg`, `rpmbuild` or `makepkg`, so any of the five can be made on any of them. Install an RPM with `dnf` rather than `rpm -i`: it is not signed, and Fedora's newest `rpm` refuses an unsigned package on its own, where `dnf` installs it and says it skipped the check. The tools it needs are in `roci doctor`; if one is missing it says which and how to get it.

## What the options say

Everything the sketch does not say can be given as an option, and is kept in a `[linux]` part of `sketch.toml` so it is given once:

```
roci package linux --format deb,arch --maintainer "Ada Lovelace <ada@example.org>" --description "A game about ships" --category "Game;"
```

```
[linux]
maintainer = "Ada Lovelace <ada@example.org>"
description = "A game about ships"
category = "Game;"
formats = "deb, arch"
```

`--maintainer` is who looks after the package: a `.deb`, an RPM and an Arch package name someone, as `Name <address>`. `--description` is the line package managers and menus show. `--category` is where the menus file the app (`Game;`, `Graphics;`, `Graphics;Music;`: the list the desktop entry specification gives). `--icon` is a square PNG, 512 pixels or more; without one the app gets rocinante's mark.

## What goes inside

The program, the sketch's `assets` and `libs`, and the files it starts from (`ui.toml`, `memory.toml`, the vault), as for a Mac app. The program finds its assets beside itself; what it writes (what it remembers, `output/`) goes in `~/.local/share/<id>`, which is made the first time it runs.

It also carries the libraries it needs that a computer cannot be counted on to have: SDL3, SDL3_ttf (made for the purpose, with its own FreeType and HarfBuzz, because the usual one pulls in a library that may not be shipped), and the ones that turn your own shaders into something the graphics card runs. The Arch package asks for Arch's own instead, and says which in its dependencies. The `.deb` and the RPM carry them as the tar does, and ask only for the computer's C and C++ libraries. A library that is not on the list of ones whose licence is known to allow it is never carried: the packaging stops and says so.

Before anything is made, the app is run once, for two frames, with no window, to see that it starts.

## Which Linux it runs on

A program runs on a Linux with the same C library as the one it was built on, or newer. `roci package` says which: "It runs on Linux with glibc 2.35 or newer", and which C++ library. **Make the packages on an older Linux to reach more computers**: a program built on a new Arch asks for a new glibc, and an Ubuntu from two years ago cannot start it. A computer of the age you want to reach, or a container of it, is the place to package.

## AppImages

An AppImage starts with a small program from the AppImage project (their `runtime`, MIT licensed), which `roci package` fetches the first time from AppImage's release page and checks against a sum it knows. That program has libfuse linked into it, which is LGPL-2.1, so the AppImage carries a note beside the app (`AppImage-runtime-licences.txt`) that names it and says where its source is. If an AppImage will not start on a computer, it is usually because the computer lacks FUSE: `APPIMAGE_EXTRACT_AND_RUN=1 ./Name.AppImage` runs it without.

## Signing

Nothing here is signed: Linux does not ask for it. Package managers keep their own keys, and a repository that serves a `.deb`, an RPM or an Arch package signs it itself (`rpmsign --addsign` signs an RPM).
