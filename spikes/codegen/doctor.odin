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
		fmt.printfln("  ok       %s: %s", what, found)
	} else {
		fmt.printfln("  MISSING  %s", what)
		fmt.printfln("           %s", fix)
	}
	return ok
}

doctor :: proc(pinned_odin: string) -> bool {
	ok := true
	fmt.printfln("roci doctor, packaging for this computer (%v %v)", ODIN_OS, ODIN_ARCH)

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
