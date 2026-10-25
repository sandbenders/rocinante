// SPDX-License-Identifier: 0BSD
//
// The spike's version of `roci doctor` (CLAUDE.md sections 4.7 and 7): find the
// pieces `roci package` needs on this machine and, for each missing one, say
// in plain words how to get it. Only the macOS branch has been run so far; the
// others follow the tools Odin's install guide names and are untested.
package codegen_spike

import "core:fmt"
import "core:os"
import "core:strings"

import "../../tools/term"

// Runs a command and returns its first line of output, or false if it could not run.
probe :: proc(command: ..string) -> (line: string, ok: bool) {
	state, stdout, _, err := os.process_exec({command = command}, context.allocator)
	if err != nil || state.exit_code != 0 {
		return "", false
	}
	text := strings.trim_space(string(stdout))
	first, _, _ := strings.partition(text, "\n")
	return first, true
}

report :: proc(what: string, found: string, ok: bool, fix: string) -> bool {
	if ok {
		fmt.printfln("  %s%s %s: %s", term.out_icon(.Ok), term.out(term.pad("ok", 8), .Green), term.out(what, .Bold), found)
	} else {
		fmt.printfln("  %s%s %s", term.out_icon(.Missing), term.out(term.pad("MISSING", 8), .Bold_Red), term.out(what, .Bold))
		fmt.printfln("  %s         %s", "   " if term.out_colour else "", term.out(fix, .Yellow))
	}
	return ok
}

// Which computers can package which target (CLAUDE.md section 7). iOS and
// Android are targets only; desktop targets are packaged on their own system.
Target :: struct {
	name:  string,
	hosts: []string, // host ids, see host_id
	says:  string,   // the plain-words reason, shown when this computer cannot
}

// A package-level variable, not a constant: a constant slice of structs that
// hold slices is rebuilt on the stack at each use, so a copy of one entry
// returned from a procedure would point at freed memory (found by the tests).
TARGETS := []Target{
	{"linux", {"linux-amd64", "linux-arm64"}, "Linux apps are built on a Linux computer"},
	{"freebsd", {"freebsd-amd64", "freebsd-arm64"}, "FreeBSD apps are built on a FreeBSD computer"},
	{"macos", {"macos-arm64", "macos-amd64"}, "macOS apps are built on a Mac"},
	{"windows", {"windows-amd64"}, "Windows apps are built on a Windows computer"},
	{"android", {"macos-arm64", "macos-amd64", "linux-amd64", "windows-amd64"}, "Android apps are built on a Mac, a Linux x86-64 computer or a Windows computer, because Google's Android tools run nowhere else"},
	{"ios", {"macos-arm64", "macos-amd64"}, "iOS apps can only be built on a Mac, because Apple's tools only run there"},
}

host_id :: proc() -> string {
	os_name: string
	when ODIN_OS == .Darwin {
		os_name = "macos"
	} else when ODIN_OS == .Linux {
		os_name = "linux"
	} else when ODIN_OS == .FreeBSD {
		os_name = "freebsd"
	} else when ODIN_OS == .Windows {
		os_name = "windows"
	} else {
		os_name = "other"
	}
	arch_name := "amd64" if ODIN_ARCH == .amd64 else "arm64"
	return fmt.tprintf("%s-%s", os_name, arch_name)
}

// The host as a person would say it.
host_label :: proc(host: string) -> string {
	switch host {
	case "macos-arm64", "macos-amd64": return "a Mac"
	case "linux-amd64": return "a Linux x86-64 computer"
	case "linux-arm64": return "a Linux arm64 computer"
	case "freebsd-amd64", "freebsd-arm64": return "a FreeBSD computer"
	case "windows-amd64": return "a Windows computer"
	}
	return host
}

can_package :: proc(target: Target, host: string) -> bool {
	for h in target.hosts {
		if h == host {
			return true
		}
	}
	return false
}

// For every target: can this computer build it? Says so first, before any tool
// is looked for, as the section 7 rule asks.
report_targets :: proc(host: string) {
	fmt.printfln("%s", term.out(fmt.tprintf("this computer is %s", host_label(host)), .Bold_Cyan))
	for target in TARGETS {
		if can_package(target, host) {
			fmt.printfln("  %s%s %s", term.out_icon(.Ok), term.out(term.pad("can build", 12), .Green), term.out(target.name, .Bold))
		} else {
			fmt.printfln("  %s%s %s: %s", term.out_icon(.Cannot), term.out(term.pad("cannot build", 12), .Yellow), term.out(target.name, .Bold), term.out(target.says, .Dim))
		}
	}
	fmt.println("")
}

doctor :: proc(pinned_odin: string, pretend_host := "") -> bool {
	ok := true
	host := pretend_host if pretend_host != "" else host_id()
	report_targets(host)
	fmt.printfln("%s", term.out(fmt.tprintf("roci doctor, packaging for this computer (%v %v)", ODIN_OS, ODIN_ARCH), .Bold_Cyan))

	// Odin itself, at the pinned version.
	version, have_odin := probe("odin", "version")
	if have_odin && strings.contains(version, pinned_odin) {
		report("Odin", version, true, "")
	} else if have_odin {
		ok = false
		report("Odin", "", false, fmt.tprintf("You have '%s' but this release is pinned to %s. rocinante will fetch the right one for you.", version, pinned_odin))
	} else {
		ok = false
		report("Odin", "", false, fmt.tprintf("Odin %s was not found. rocinante will fetch it for you.", pinned_odin))
	}

	// The linker toolchain Odin uses on each system.
	when ODIN_OS == .Darwin {
		path, have_tools := probe("xcode-select", "-p")
		ok = report("Xcode command-line tools", path, have_tools, "Run: xcode-select --install") && ok
		clang, have_clang := probe("clang", "--version")
		ok = report("clang", clang, have_clang, "Run: xcode-select --install") && ok
	} else when ODIN_OS == .Linux {
		clang, have_clang := probe("clang", "--version")
		ok = report("clang", clang, have_clang, "Install it with your package manager, for example: sudo apt install clang, sudo pacman -S clang or sudo dnf install clang") && ok
	} else when ODIN_OS == .FreeBSD {
		clang, have_clang := probe("clang", "--version")
		ok = report("clang", clang, have_clang, "It is part of the base system; check that /usr/bin/clang exists") && ok
	} else when ODIN_OS == .Windows {
		// vswhere ships with the Visual Studio installer and finds MSVC and the Windows SDK.
		vswhere := `C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe`
		path, have_msvc := probe(vswhere, "-latest", "-products", "*", "-requires", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64", "-property", "installationPath")
		ok = report("Microsoft C++ build tools and Windows SDK", path, have_msvc, `Install Visual Studio Build Tools and tick "Desktop development with C++"`) && ok
	}
	return ok
}
