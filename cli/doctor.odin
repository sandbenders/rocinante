// SPDX-License-Identifier: 0BSD
//
// `roci doctor`: for each target, whether this computer can build it, and for this computer which of the tools that
// compiling a sketch needs are there, with the plain words that say how to get each one that is not. It looks at
// the Odin release this rocinante is pinned to, the linker toolchain of the system, the SDL libraries and the source
// of rocinante that a compiled sketch is built together with.
package main

import "../tools/term"
import "core:fmt"
import "core:os"
import "core:strings"

// A target, the computers that can build it and why the others cannot, in the words a person would use.
Doctor_Target :: struct {
	name:  string,
	hosts: []string, // host ids, see `host_id`
	says:  string,
}

// A package-level variable, not a constant: a constant slice of structs that hold slices is rebuilt on the stack at
// each use, so a copy of one entry returned from a procedure would point at freed memory.
DOCTOR_TARGETS := []Doctor_Target{
	{"linux", {"linux-amd64", "linux-arm64"}, "Linux apps are built on a Linux computer"},
	{"freebsd", {"freebsd-amd64", "freebsd-arm64"}, "FreeBSD apps are built on a FreeBSD computer"},
	{"openbsd", {"openbsd-amd64"}, "OpenBSD apps are built on an OpenBSD computer"},
	{"macos", {"macos-arm64", "macos-amd64"}, "macOS apps are built on a Mac"},
	{"windows", {"windows-amd64"}, "Windows apps are built on a Windows computer"},
	{"android", {"macos-arm64", "macos-amd64", "linux-amd64", "windows-amd64"}, "Android apps are built on a Mac, a Linux x86-64 computer or a Windows computer, because Google's Android tools run nowhere else"},
	{"ios", {"macos-arm64", "macos-amd64"}, "iOS apps can only be built on a Mac, because Apple's tools only run there"},
}

// The system and processor of this computer as `macos-arm64`, `linux-amd64`.
host_id :: proc() -> string {
	return system_folder()
}

// A computer as a person would say it.
host_label :: proc(host: string) -> string {
	switch host {
	case "macos-arm64", "macos-amd64":     return "a Mac"
	case "linux-amd64":                    return "a Linux x86-64 computer"
	case "linux-arm64":                    return "a Linux arm64 computer"
	case "freebsd-amd64", "freebsd-arm64": return "a FreeBSD computer"
	case "openbsd-amd64":                  return "an OpenBSD computer"
	case "windows-amd64":                  return "a Windows computer"
	}
	return host
}

can_build :: proc(target: Doctor_Target, host: string) -> bool {
	for h in target.hosts {
		if h == host {
			return true
		}
	}
	return false
}

// For every target: can this computer build it? Said first, before any tool is looked for.
target_lines :: proc(host: string, allocator := context.temp_allocator) -> string {
	b := strings.builder_make(allocator)
	fmt.sbprintf(&b, "%s\n", term.out(fmt.tprintf("this computer is %s", host_label(host)), .Bold_Cyan))
	for target in DOCTOR_TARGETS {
		if can_build(target, host) {
			fmt.sbprintf(&b, "  %s%s %s\n", term.out_icon(.Ok), term.out(term.pad("can build", 12), .Green), term.out(target.name, .Bold))
		} else {
			fmt.sbprintf(&b, "  %s%s %s: %s\n", term.out_icon(.Cannot), term.out(term.pad("cannot build", 12), .Yellow), term.out(target.name, .Bold), term.out(target.says, .Dim))
		}
	}
	return strings.to_string(b)
}

// Runs a command and gives the first line of what it says, or false when it could not run.
probe :: proc(command: ..string) -> (line: string, ok: bool) {
	state, stdout, _, err := os.process_exec({command = command}, context.temp_allocator)
	if err != nil || state.exit_code != 0 {
		return "", false
	}
	first, _, _ := strings.partition(strings.trim_space(string(stdout)), "\n")
	return first, true
}

// One line of the report: what was looked for, what was found or how to get it.
tool_line :: proc(b: ^strings.Builder, what, found: string, ok: bool, fix: string) {
	if ok {
		fmt.sbprintf(b, "  %s%s %s: %s\n", term.out_icon(.Ok), term.out(term.pad("ok", 8), .Green), term.out(what, .Bold), found)
		return
	}
	fmt.sbprintf(b, "  %s%s %s\n", term.out_icon(.Missing), term.out(term.pad("MISSING", 8), .Bold_Red), term.out(what, .Bold))
	fmt.sbprintf(b, "  %s         %s\n", "   " if term.out_colour else "", term.out(fix, .Yellow))
}

// What Odin says about itself, compared with the release this rocinante is pinned to.
odin_line :: proc(b: ^strings.Builder, version: string, have: bool) -> bool {
	switch {
	case have && strings.contains(version, ODIN_VERSION):
		tool_line(b, "Odin", version, true, "")
		return true
	case have:
		tool_line(b, "Odin", "", false, fmt.tprintf("You have `%s`, and this rocinante is pinned to %s, because a sketch must behave the same however it is made. Install that release and put it first on the PATH.", version, ODIN_VERSION))
	case:
		tool_line(b, "Odin", "", false, fmt.tprintf("Odin %s was not found. Install it (https://odin-lang.org/docs/install/) and put it on the PATH.", ODIN_VERSION))
	}
	return false
}

// The rest of the report is for the computer this runs on.
run_doctor :: proc(args: []string, out, err: ^strings.Builder) -> int {
	host := host_id()
	if len(args) > 1 || (len(args) == 1 && args[0] == "--help") {
		fmt.sbprintf(out, "roci doctor            say which targets this computer can build and which tools it lacks\nroci doctor <host>     the same as another computer would see it: macos-arm64, linux-amd64, windows-amd64\n")
		return 0 if len(args) == 1 else 2
	}
	pretend := len(args) == 1
	if pretend {
		host = args[0]
	}
	fmt.sbprintf(out, "%s\n", target_lines(host))
	if pretend {
		return 0 // the tools of another computer cannot be looked at from here
	}
	fmt.sbprintf(out, "%s\n", term.out(fmt.tprintf("compiling a sketch on this computer (%v %v)", ODIN_OS, ODIN_ARCH), .Bold_Cyan))
	ok := true
	version, have := probe("odin", "version")
	ok = odin_line(out, version, have) && ok
	when ODIN_OS == .Darwin {
		path, have_tools := probe("xcode-select", "-p")
		tool_line(out, "Xcode command-line tools", path, have_tools, "Run: xcode-select --install")
		ok = have_tools && ok
		_, have_sdl := probe("pkg-config", "--exists", "sdl3")
		if !have_sdl {
			have_sdl = os.exists("/opt/homebrew/lib/libSDL3.dylib") || os.exists("/usr/local/lib/libSDL3.dylib")
		}
		tool_line(out, "SDL3", "found", have_sdl, "Run: brew install sdl3 sdl3_ttf")
		ok = have_sdl && ok
	} else when ODIN_OS == .Windows {
		vswhere := `C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe`
		path, have_msvc := probe(vswhere, "-latest", "-products", "*", "-requires", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64", "-property", "installationPath")
		tool_line(out, "Microsoft C++ build tools and Windows SDK", path, have_msvc, `Install Visual Studio Build Tools and tick "Desktop development with C++"`)
		ok = have_msvc && ok
	} else {
		clang, have_clang := probe("clang", "--version")
		tool_line(out, "clang", clang, have_clang, "Install it with your package manager, for example: sudo apt install clang, sudo pacman -S clang or sudo dnf install clang (on FreeBSD it is part of the base system)")
		ok = have_clang && ok
		sdl, have_sdl := probe("pkg-config", "--modversion", "sdl3")
		tool_line(out, "SDL3", sdl, have_sdl, "Install SDL3 and SDL3_ttf with your package manager, for example: sudo pacman -S sdl3 sdl3_ttf")
		ok = have_sdl && ok
	}
	root, found := find_source()
	tool_line(out, "the source of rocinante", root, found, "A compiled sketch is built together with the core: keep the folder with `roci` and `ODIN_VERSION` next to this program, or set ROCI_SOURCE to it.")
	ok = found && ok
	if !ok {
		fmt.sbprintf(err, "Something is missing: the lines above say what, and how to get it.\n")
		return 1
	}
	fmt.sbprintf(out, "\nEverything a compiled sketch needs is here.\n")
	return 0
}
