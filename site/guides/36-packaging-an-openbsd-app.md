---
title: "Making an OpenBSD app"
summary: "Turn a sketch into a package for pkg_add or a .tar.gz with roci package openbsd: the options, what goes inside, and which OpenBSD it runs on."
weight: 36
---

On an OpenBSD computer, `roci package openbsd` makes an app of a sketch:

```
roci package openbsd
roci package openbsd --format pkg
```

It works in the sketch's folder (or give it a folder), refuses a sketch that has errors as `roci check` does, and asks the name, the id and the version the first time, as the [Mac guide](../32-packaging-a-mac-app/) describes: the answers are kept in `sketch.toml`. The app is made on the computer that packages it: nothing else can make an OpenBSD app, and `roci doctor` says what this computer can build and whether the tools are there.

## The formats

`--format` takes the names below, with a comma between them, or `all`. With nothing it makes both.

| Word | What it makes | Install it with |
|---|---|---|
| `pkg` | `name-1.0.0.tgz`, a package for OpenBSD's own package tools | `pkg_add -D unsigned name-1.0.0.tgz`, as root |
| `tar` | `name-1.0.0-openbsd-amd64.tar.gz`: a folder to unpack anywhere and run | `tar xzf`, then run the program in it |

The package puts the app in `/usr/local/libexec/name`, gives it a command with the app's name in `/usr/local/bin`, and adds its menu entry and icons under `/usr/local/share`, so a desktop shows it. `pkg_delete name` takes every file away again. It is made by OpenBSD's own `pkg_create`, from a list of the files that `roci` writes, so what `pkg_add` checks of it was checked by the tool that knows.

## What goes inside

The program, the sketch's `assets` and `libs`, and the files it starts from (`ui.toml`, `memory.toml`, the vault), as for a Mac app. The program finds its assets beside itself; what it writes (what it remembers, `output/`) goes in `~/.local/share/<id>`, which is made the first time it runs.

OpenBSD has packages for SDL3, shaderc and SPIRV-Cross, and the app uses those, so the package says it depends on them (`roci package` finds which by asking `pkg_info`) and `pkg_add` fetches them if they are not there yet. It has **no package for SDL3_ttf**, which draws the text, so **the app carries its own copy**, in the folder `lib` beside the program, where the program looks first. The copy is built from source the first time, with the FreeType and HarfBuzz it needs inside it (`tools/package-libs.sh openbsd`: it needs `cmake`, `git` and `curl`, and SDL3 with its headers, `doas pkg_add sdl3`). The tar names the packages to add first in a `README.txt`.

Before anything is made, the app is run once, for two frames, with no window, to see that it starts.

## Which OpenBSD it runs on

`pkg_add` checks that the libraries the program asks for are there, by name and number, and the numbers change between releases: a package made on OpenBSD 8.0 for an amd64 computer is for that release and that processor. **Make the packages on the release you want to reach.** The line `roci package` prints when it finishes says what the package was made for.

## What the options say

The sketch's description and maintainer are the ones the [Linux guide](../33-packaging-a-linux-app/) describes, given with `--maintainer` and `--description` and kept in `sketch.toml`. The formats have a part of their own:

```
[openbsd]
formats = "pkg, tar"
```

A package names who looks after it, as `Name <address>`; without one it says so, and the line it prints tells you where to add it. The icon is made from a square SVG drawing or a large PNG in the sketch's `icons` folder, as [App icons](../34-app-icons/) explains.

## Signing

The package is not signed. `pkg_add` refuses an unsigned package unless it is told `-D unsigned`, which is why the command above has it. A repository of your own signs its packages with `signify`, and the people who use it install its public key.
