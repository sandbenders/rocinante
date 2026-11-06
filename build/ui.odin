// SPDX-License-Identifier: 0BSD
//
// The user interface libraries: Dear ImGui with its SDL3 and SDL_GPU backends, built by
// tools/ui-libs.sh into .cache/ui. A contributor who has not built them skips the
// steps that need them; the pipelines set ROCI_REQUIRE_UI, so there it is a failure.
package build

import "core:fmt"
import "core:os"

import "../tools/term"

UI_LIBRARY :: ".cache/ui/libroci_ui.a" when ODIN_OS != .Windows else ".cache/ui/roci_ui.lib"

// What the user interface checks do: run when the library is built, skip quietly
// for a contributor who has not built it, fail where it is required.
ui_outcome :: proc(library_built, required: bool) -> Check_Outcome {
	switch {
	case library_built:  return .Passed
	case !required:      return .Skipped
	}
	return .Failed
}

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

// The bindings and their generator are type-checked everywhere; the tests that call
// Dear ImGui need the built library.
check_ui :: proc() -> bool {
	ok := step("check imgui bindings", {"odin", "check", "vendor/imgui", "-no-entry-point", "-vet", "-strict-style"})
	ok = step("check imgui bindings tool", {"odin", "check", "tools/imgui", "-vet", "-strict-style"}) && ok
	name := "unit tests: vendor/imgui"
	fmt.printfln("%s", term.out(fmt.tprintf("== %s", name), .Bold_Cyan))
	required := os.get_env("ROCI_REQUIRE_UI", context.temp_allocator) != ""
	switch ui_outcome(os.exists(UI_LIBRARY), required) {
	case .Passed:
		ok = step("unit tests: vendor/imgui (run)", {"odin", "test", "vendor/imgui", "-vet", "-strict-style", fmt.tprintf("-out:%s", test_binary("vendor/imgui"))}) && ok
	case .Skipped:
		fmt.printfln("   %s", term.out("skipped, the UI libraries are not built (tools/ui-libs.sh; the pipelines require them)", .Dim))
	case .Failed:
		fmt.eprintfln("%s", term.err("the UI libraries are not built and ROCI_REQUIRE_UI is set (run tools/ui-libs.sh)", .Bold_Red))
		ok = false
	}
	return ok
}
