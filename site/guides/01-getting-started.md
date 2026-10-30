---
title: "Getting started"
summary: "Installing rocinante, making a sketch folder, and running it."
weight: 1
---

A rocinante program is called a **sketch**. You write it in a plain text file, `sketch.roci`, and the `roci` program runs it in a window. While it runs, every time you save the file the window changes to match.

## Installing

For the alpha, rocinante is built from its source, on Windows, Linux, FreeBSD or macOS. You need three things: **git**, **Odin** (the language rocinante is written in) at the version named in the repository's `ODIN_VERSION` file, and **SDL3** (windows, input and graphics). `odin version` says which Odin you have.

### Windows

1. Install **Build Tools for Visual Studio** from Microsoft's [Visual Studio downloads](https://visualstudio.microsoft.com/downloads/), with the **Desktop development with C++** workload. Odin needs its compiler and the Windows SDK.
2. Download Odin from its [releases](https://github.com/odin-lang/Odin/releases) (the `windows-amd64` archive of the version in `ODIN_VERSION`), unpack it, and add its folder to your `PATH`.
3. Install git from [git-scm.com](https://git-scm.com/downloads/win) if you do not have it. SDL3 comes with Odin, so there is nothing more to install.

Build it in a terminal (Command Prompt or PowerShell); Odin finds Visual Studio's compiler by itself:

```
git clone https://github.com/sandbenders/rocinante
cd rocinante
odin build cli -out:roci.exe -o:speed
```

A program that opens a window needs SDL3's library beside it on Windows: copy `SDL3.dll` from the `vendor\sdl3` folder inside Odin's folder (`odin root` prints where that is) into the folder that holds `roci.exe`.

### Linux

1. Download Odin from its [releases](https://github.com/odin-lang/Odin/releases) (the `linux-amd64` or `linux-arm64` archive of the version in `ODIN_VERSION`), unpack it, and add its folder to your `PATH`.
2. Install git, clang (which Odin uses to link) and SDL3:

| Distribution | Command |
|---|---|
| Arch, CachyOS, Manjaro | `sudo pacman -S git clang sdl3` |
| Debian 13 or later, Ubuntu 25.04 or later | `sudo apt install git clang libsdl3-dev` |
| Fedora 43 or later | `sudo dnf install git clang SDL3-devel` |

Older releases (Ubuntu 24.04, Debian 12) have no SDL3 package. Build it with the repository's own script, which the pipelines use: `tools/ci/install-sdl3.sh ~/sdl3`, then point the compiler at it with `export LIBRARY_PATH=~/sdl3/lib` and `export LD_LIBRARY_PATH=~/sdl3/lib`. It needs `cmake`, `ninja` and the development packages of X11 or Wayland.

### FreeBSD

Odin has no FreeBSD archive, so it is built from its source, which takes about two minutes:

```
sudo pkg install git gmake llvm19 sdl3
git clone --branch dev-2026-10 https://github.com/odin-lang/Odin
cd Odin
LLVM_CONFIG=llvm-config19 gmake release-native
```

Then add the `Odin` folder to your `PATH`. Use the version in `ODIN_VERSION` as the branch; the `lang/odin` port is usually older than rocinante needs.

### macOS

1. Install Apple's command-line tools, which include git: `xcode-select --install`.
2. Install Odin and SDL3 with [Homebrew](https://brew.sh): `brew install odin sdl3`. Check that `odin version` matches `ODIN_VERSION`; if Homebrew's Odin is newer or older, download the `macos-arm64` archive of the right version from Odin's [releases](https://github.com/odin-lang/Odin/releases) instead.

### Building `roci`

On Linux, FreeBSD and macOS:

```
git clone https://github.com/sandbenders/rocinante
cd rocinante
odin build cli -out:roci -o:speed
```

That makes the program `roci` in the folder (`roci.exe` on Windows). Put it somewhere on your path, or run it from there as `./roci` (`roci` on Windows).

## Your first sketch

```
roci new my-sketch
cd my-sketch
roci run
```

`roci new` makes a folder with a sketch in it, and `roci run` opens a window and draws it. The sketch is one line:

```roci
circle at 100 100 radius 50
```

Open `sketch.roci` in any text editor, put this line under the first one, and save:

```roci
circle at 100 100 radius 50
rect at 200 60 size 160 90 fill orange
```

The window changes straight away; you do not have to run it again. Leave `roci run` going while you work.

## When something is wrong

Make a mistake on purpose: change `circle` to `circel` and save. The window keeps the last good picture and shows, across the top, what went wrong, and the terminal says the same:

```message
── I don't know the word `circel` ────────────────────── sketch.roci:1:1

1 │ circel at 100 100 radius 50
  │ ^^^^^^

A line starts with a verb, a keyword or a name, and I don't know `circel`. Check the spelling, or teach the word with `learn`.

Did you mean:  circle at 100 100 radius 50
```

Every message says where the problem is, what it is in plain words, and shows a line that would work. Put the word right, save, and the picture comes back. The [messages](../../messages/) page lists them all.

## Other things `roci` does

| Command | What it does |
|---|---|
| `roci run sketch.roci` | runs a sketch file, or a folder's `sketch.roci` |
| `roci check sketch.roci` | says what is wrong without opening a window |
| `roci fmt` | rewrites every sketch in the folder in the house style |
| `roci man circle` | shows how a word is written |
| `roci new name`, `roci init` | make a sketch folder, or one here |
| `roci add photo.png` | copies a file into the sketch's `assets` |

Two keys work in every sketch window:

| What it does | Windows, Linux, FreeBSD | macOS |
|---|---|---|
| start the sketch again from its first line | Ctrl+R | Cmd+R |
| close the sketch | Ctrl+Q | Cmd+Q |
