// SPDX-License-Identifier: 0BSD
//
// The user interface libraries: Dear ImGui with its SDL3 and SDL_GPU backends, built by
// tools/ui-libs.sh into .cache/ui.
package build

import "core:fmt"
import "core:os"

import "../tools/term"

UI_LIBRARY :: ".cache/ui/libroci_ui.a" when ODIN_OS != .Windows else ".cache/ui/roci_ui.lib"
ACCESSKIT_LIBRARY :: ".cache/ui/accesskit/libaccesskit.a" when ODIN_OS != .Windows else ".cache/ui/accesskit/accesskit.lib"
ACCESSKIT_HEADER :: ".cache/ui/accesskit/accesskit.h"

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
	// This runs before any other step, so a fresh clone has no folder for the test program yet.
	if err := os.make_directory_all(TEST_OUT_DIR); err != nil && err != .Exist {
		fmt.eprintfln("%s", term.err(fmt.tprintf("cannot make the folder %s: %v", TEST_OUT_DIR, err), .Bold_Red))
		return false
	}
	ok := step("check imgui bindings", {"odin", "check", "vendor/imgui", "-no-entry-point", "-vet", "-strict-style"})
	ok = step("check imgui bindings tool", {"odin", "check", "tools/imgui", "-vet", "-strict-style"}) && ok
	ok = step("unit tests: vendor/imgui", {"odin", "test", "vendor/imgui", "-vet", "-strict-style", fmt.tprintf("-out:%s", test_binary("vendor/imgui"))}) && ok
	return ok
}

// The screen-reader bridge's library, accesskit-c, fetched by `tools/ui-libs.sh accesskit` (its own
// release library where there is one for this computer, a build from source otherwise). Where it
// cannot be had the step says so and passes, unless ROCI_REQUIRE_ACCESSKIT is set, as it is in both
// pipelines. The bindings are written again into output/ and must equal the committed file, so a
// header or generator change that was not committed fails here.
check_accesskit :: proc() -> bool {
	required := os.get_env("ROCI_REQUIRE_ACCESSKIT", context.temp_allocator) != ""
	when ODIN_OS == .Windows {
		fmt.printfln("%s", term.out("== accesskit: skipped, the Windows library is not fetched by a script yet", .Bold_Cyan))
		return !required
	}
	if !os.exists(ACCESSKIT_LIBRARY) {
		fmt.printfln("%s", term.out("== fetching accesskit-c (tools/ui-libs.sh accesskit)", .Bold_Cyan))
		state, stdout, stderr, err := os.process_exec({command = {"sh", "tools/ui-libs.sh", "accesskit"}}, context.allocator)
		fmt.print(string(stdout))
		if err != nil || state.exit_code != 0 {
			fmt.eprint(string(stderr))
			message := "accesskit-c could not be fetched or built (needs curl and unzip, or git, cmake and cargo)"
			if required {
				fmt.eprintfln("%s", term.err(message, .Bold_Red))
				return false
			}
			fmt.printfln("%s", term.out(fmt.tprintf("accesskit: skipped, %s", message), .Bold_Cyan))
			return true
		}
	}
	ok := step("check accesskit bindings", {"odin", "check", "vendor/accesskit", "-no-entry-point", "-vet", "-strict-style"})
	ok = step("check accesskit bindings tool", {"odin", "check", "tools/accesskit", "-vet", "-strict-style"}) && ok
	ok = step("unit tests: vendor/accesskit", {"odin", "test", "vendor/accesskit", "-vet", "-strict-style", fmt.tprintf("-out:%s", test_binary("vendor/accesskit"))}) && ok
	// the bindings are made again and compared with the committed file
	if os.exists(ACCESSKIT_HEADER) {
		fresh := "output/accesskit/accesskit.odin"
		ok = step("accesskit bindings are up to date", {"odin", "run", "tools/accesskit", fmt.tprintf("-out:%s", test_binary("tools/accesskit")), "--", ACCESSKIT_HEADER, fresh}) && ok
		have, have_err := os.read_entire_file("vendor/accesskit/accesskit.odin", context.temp_allocator)
		made, made_err := os.read_entire_file(fresh, context.temp_allocator)
		if have_err != nil || made_err != nil || string(have) != string(made) {
			fmt.eprintfln("%s", term.err("vendor/accesskit/accesskit.odin is not what tools/accesskit makes: run `odin run tools/accesskit` and commit it", .Bold_Red))
			ok = false
		}
	}
	return ok
}
