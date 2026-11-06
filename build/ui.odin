// SPDX-License-Identifier: 0BSD
//
// The user interface libraries: Dear ImGui with its SDL3 and SDL_GPU backends, built by
// tools/ui-libs.sh into .cache/ui.
package build

import "core:fmt"
import "core:os"

import "../tools/term"

UI_LIBRARY :: ".cache/ui/libroci_ui.a" when ODIN_OS != .Windows else ".cache/ui/roci_ui.lib"

// Builds the libraries (`ui-libs`) or builds them and writes the bindings again
// (`ui-libs regenerate`).
ui_libs :: proc(regenerate: bool) -> bool {
	when ODIN_OS == .Windows {
		fmt.eprintfln("%s", term.err("ui-libs: the Windows build is not written yet (it needs MSVC and -MT, see spikes/ui/setup-windows.sh)", .Bold_Red))
		return false
	}
	command := []string{"sh", "tools/ui-libs.sh", "regenerate"} if regenerate else []string{"sh", "tools/ui-libs.sh"}
	state, stdout, stderr, err := os.process_exec({command = command}, context.allocator)
	fmt.print(string(stdout))
	if err != nil || state.exit_code != 0 {
		fmt.eprint(string(stderr))
		fmt.eprintfln("%s", term.err("ui-libs failed", .Bold_Red))
		return false
	}
	return true
}

// Every program that opens a window links Dear ImGui, so the library has to be built before
// anything else is: `ci` builds it when it is missing (the pipelines build it as a step of their
// own first, which makes this a no-op there). The bindings and their generator are
// type-checked, and the tests that call Dear ImGui run in `check_packages`.
check_ui :: proc() -> bool {
	if !os.exists(UI_LIBRARY) {
		fmt.printfln("%s", term.out("== building the user interface libraries (tools/ui-libs.sh)", .Bold_Cyan))
		if !ui_libs(false) {
			return false
		}
	}
	ok := step("check imgui bindings", {"odin", "check", "vendor/imgui", "-no-entry-point", "-vet", "-strict-style"})
	ok = step("check imgui bindings tool", {"odin", "check", "tools/imgui", "-vet", "-strict-style"}) && ok
	ok = step("unit tests: vendor/imgui", {"odin", "test", "vendor/imgui", "-vet", "-strict-style", fmt.tprintf("-out:%s", test_binary("vendor/imgui"))}) && ok
	return ok
}
