---
title: "Making a FreeBSD app"
summary: "Turn a sketch into a package for pkg or a .tar.gz with roci package freebsd: the options, what goes inside, and which FreeBSD it runs on."
weight: 35
---

On a FreeBSD computer, `roci package freebsd` makes an app of a sketch:

```
roci package freebsd
roci package freebsd --format pkg
```

It works in the sketch's folder (or give it a folder), refuses a sketch that has errors as `roci check` does, and asks the name, the id and the version the first time, as the [Mac guide](../32-packaging-a-mac-app/) describes: the answers are kept in `sketch.toml`. The app is made on the computer that packages it: nothing else can make a FreeBSD app, and `roci doctor` says what this computer can build.

## The formats

`--format` takes the names below, with a comma between them, or `all`. With nothing it makes both.

| Word | What it makes | Install it with |
|---|---|---|
| `pkg` | `name-1.0.0.pkg`, a package for FreeBSD's own package manager | `pkg add name-1.0.0.pkg`, as root |
| `tar` | `name-1.0.0-freebsd-amd64.tar.gz`: a folder to unpack anywhere and run | `tar xzf`, then run the program in it |

The package puts the app in `/usr/local/libexec/name`, gives it a command with the app's name in `/usr/local/bin`, and adds its menu entry and icons under `/usr/local/share`, so a desktop shows it. `pkg delete name` takes every file away again. It is made by `roci` itself, in the format `pkg create` writes, so no other tool is needed.

## What goes inside

The program, the sketch's `assets` and `libs`, and the files it starts from (`ui.toml`, `memory.toml`, the vault), as for a Mac app. The program finds its assets beside itself; what it writes (what it remembers, `output/`) goes in `~/.local/share/<id>`, which is made the first time it runs.

Unlike on a Mac or on Linux, **nothing is carried**: a FreeBSD computer installs libraries with `pkg`, and the app uses the same SDL3, SDL3_ttf, shaderc and SPIRV-Cross as everything else on it. The package says it depends on the packages that hold them (`roci package` finds which by asking `pkg`), so `pkg add` fetches them from the repository if they are not there yet. The tar has no such list in it, so it holds a `README.txt` that names the packages to install first.

Before anything is made, the app is run once, for two frames, with no window, to see that it starts.

## Which FreeBSD it runs on

A package made on FreeBSD 15 for an amd64 computer says so (its ABI is `FreeBSD:15:amd64`), and `pkg` will not install it on another release or another kind of processor. **Make the packages on the release you want to reach.** The ABI is on the line `roci package` prints when it starts.

## What the options say

The sketch's description and maintainer are the ones the [Linux guide](../33-packaging-a-linux-app/) describes, given with `--maintainer` and `--description` and kept in `sketch.toml`. The formats have a part of their own:

```
[freebsd]
formats = "pkg, tar"
```

A package names who looks after it, as `Name <address>`; without one it says so, and the line it prints tells you where to add it. The icon is made from a square SVG drawing or a large PNG in the sketch's `icons` folder, as [App icons](../34-app-icons/) explains.

## Signing

Nothing here is signed: FreeBSD does not ask for it. A repository that serves your packages signs them itself (`pkg repo` with a key).
