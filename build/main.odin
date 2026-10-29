// SPDX-License-Identifier: 0BSD
//
// The rocinante build script. Run it with:
//
//     odin run build -- <command>
//
// `ci` runs exactly what both pipelines run, so nothing lives only in YAML.
// `ci --fast` is the part the pre-push hook runs.
package build

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

import "../tools/term"

USAGE :: `usage: odin run build -- <command>

commands:
  ci [--fast]   run the checks the pipelines run (--fast: the pre-push subset)
  licences      check dependency licences
  odin          check the installed Odin against ODIN_VERSION
`

main :: proc() {
	term.setup()
	args := os.args[1:]
	if len(args) == 0 {
		fmt.eprint(USAGE)
		os.exit(2)
	}
	ok: bool
	switch args[0] {
	case "ci":
		fast := len(args) > 1 && args[1] == "--fast"
		ok = ci(fast)
	case "licences":
		ok = check_licences(".")
	case "odin":
		ok = check_odin()
	case:
		fmt.eprint(USAGE)
		os.exit(2)
	}
	os.exit(0 if ok else 1)
}

// Runs one named step and prints what it printed if it fails.
step :: proc(name: string, command: []string) -> bool {
	fmt.printfln("%s", term.out(fmt.tprintf("== %s", name), .Bold_Cyan))
	started := time.now()
	state, stdout, stderr, err := os.process_exec({command = command}, context.allocator)
	if err != nil || state.exit_code != 0 {
		fmt.eprintfln("%s", term.err(fmt.tprintf("%s failed (%v, exit code %d)", name, err, state.exit_code), .Bold_Red))
		fmt.eprint(string(stdout))
		fmt.eprint(string(stderr))
		return false
	}
	fmt.printfln("   %s%s", term.out_icon(.Ok), term.out(fmt.tprintf("ok, %.1f s", time.duration_seconds(time.since(started))), .Green))
	return true
}

// The pinned Odin lives in ODIN_VERSION. A different local Odin is a warning on
// a developer's machine and an error in the pipelines, which set CI.
check_odin :: proc() -> bool {
	data, read_err := os.read_entire_file("ODIN_VERSION", context.allocator)
	if read_err != nil {
		fmt.eprintfln("%s", term.err(fmt.tprintf("cannot read ODIN_VERSION: %v", read_err), .Bold_Red))
		return false
	}
	pinned := strings.trim_space(string(data))

	state, stdout, _, err := os.process_exec({command = {"odin", "version"}}, context.allocator)
	if err != nil || state.exit_code != 0 {
		fmt.eprintfln("%s", term.err(fmt.tprintf("cannot run `odin version`: %v", err), .Bold_Red))
		return false
	}
	have := strings.trim_space(string(stdout))
	if strings.contains(have, pinned) {
		fmt.printfln("%s %s", term.out("odin:", .Bold), term.out(fmt.tprintf("ok (%s)", pinned), .Green))
		return true
	}
	fmt.eprintfln("%s this rocinante release is pinned to %s, but you have '%s'.", term.err("odin:", .Bold_Red), pinned, have)
	if os.get_env("CI", context.temp_allocator) != "" {
		return false
	}
	fmt.eprintfln("%s continuing, because this is not a pipeline.", term.err("odin:", .Yellow))
	return true
}

// Packages whose @(test) procedures `ci` runs, from the repository root (some
// tests make fixtures under output/). Add each package here as it gets tests.
TEST_PACKAGES :: []string{"build", "roci/geom", "roci/collide", "roci", "roci/folder", "roci/gfx", "roci/interp", "roci/lang", "roci/maths", "roci/platform", "roci/registry", "cli", "spikes/codegen", "tools/term"}

// Where `odin test` writes each package's test program. Left to itself it writes
// build.exe to the repository root, the very file `odin run build` is running
// from, which Windows keeps locked.
TEST_OUT_DIR :: "output/tests"

// Odin on Windows refuses an -out: path without .exe.
EXE :: ".exe" when ODIN_OS == .Windows else ""

// `variant` keeps the optimised build of a package's tests apart from the default one.
test_binary :: proc(package_dir: string, variant := "") -> string {
	name, _ := strings.replace_all(package_dir, "/", "_", context.temp_allocator)
	return fmt.tprintf("%s/%s%s%s", TEST_OUT_DIR, name, variant, EXE)
}

ci :: proc(fast: bool) -> bool {
	ok := check_odin()
	ok = check_licences(".") && ok
	// Compile-check every Odin package that exists so far.
	ok = check_packages() && ok
	if !fast {
		ok = check_optimised_tests() && ok
		ok = check_abi() && ok
		ok = check_golden() && ok
		fmt.printfln("%s %s", term.out("== back-end equivalence, benchmarks:", .Bold_Cyan), term.out("not built yet", .Dim))
	}
	if ok {
		fmt.printfln("\n%s%s", term.out_icon(.Ok), term.out("ci: all checks passed", .Bold_Green))
	} else {
		fmt.eprintfln("\n%s%s", term.err_icon(.Missing), term.err("ci: FAILED, see the messages above", .Bold_Red))
	}
	return ok
}

// The unit tests again, built optimised (-o:speed, as the benchmark is measured):
// a sketch must behave the same however it was built, so the
// optimiser must not change a result, which holds only while nothing uses
// fast-math. The full `ci` only, because building every package optimised takes
// about a minute.
OPTIMISED_TEST_FLAG :: "-o:speed"

check_optimised_tests :: proc() -> bool {
	ok := true
	for package_dir in TEST_PACKAGES {
		out := fmt.tprintf("-out:%s", test_binary(package_dir, "_speed"))
		ok = step(fmt.tprintf("unit tests, optimised: %s", package_dir), {"odin", "test", package_dir, OPTIMISED_TEST_FLAG, "-vet", "-strict-style", out}) && ok
	}
	return ok
}

// `odin check` on the build script. Packages under roci/ and cli/ join this list
// as they appear.
check_packages :: proc() -> bool {
	ok := step("check build script", {"odin", "check", "build", "-vet", "-strict-style"})
	if err := os.make_directory_all(TEST_OUT_DIR); err != nil && err != .Exist {
		fmt.eprintfln("%s", term.err(fmt.tprintf("cannot make the folder %s: %v", TEST_OUT_DIR, err), .Bold_Red))
		return false
	}
	for package_dir in TEST_PACKAGES {
		out := fmt.tprintf("-out:%s", test_binary(package_dir))
		ok = step(fmt.tprintf("unit tests: %s", package_dir), {"odin", "test", package_dir, "-vet", "-strict-style", out}) && ok
	}
	// The spikes that build on any machine are type-checked; the Android and iOS
	// ones need their SDKs and are built by hand.
	ok = step("check roci command", {"odin", "check", "cli", "-vet", "-strict-style"}) && ok
	ok = step("check header tool", {"odin", "check", "tools/header", "-vet", "-strict-style"}) && ok
	ok = step("check benchmark example", {"odin", "check", "examples/benchmark", "-vet", "-strict-style"}) && ok
	ok = step("check circle example", {"odin", "check", "examples/circle", "-vet", "-strict-style"}) && ok
	ok = step("check two windows example", {"odin", "check", "examples/two_windows", "-vet", "-strict-style"}) && ok
	ok = step("check garden example", {"odin", "check", "examples/garden", "-vet", "-strict-style"}) && ok
	ok = step("check shapes example", {"odin", "check", "examples/shapes", "-vet", "-strict-style"}) && ok
	ok = step("check golden tests", {"odin", "check", "tests/golden", "-vet", "-strict-style"}) && ok
	ok = step("check window example", {"odin", "check", "examples/window", "-vet", "-strict-style"}) && ok
	ok = step("check phone sketch", {"odin", "check", "spikes/mobile/sketch", "-no-entry-point", "-vet", "-strict-style"}) && ok
	// Spike 3: interpret, generate Odin, build it and compare the output.
	ok = step("spike 3: code generation", {"odin", "run", "spikes/codegen", "--", "check"}) && ok
	return ok
}

// tools/abi-check.sh gives this when it cannot run here: no C compiler, or no SDL3
// to link against.
ABI_CHECK_UNAVAILABLE :: 3

Check_Outcome :: enum {
	Passed,
	Skipped, // not possible on this computer, which is fine for a contributor
	Failed,
}

// What an exit code of the C ABI check means. The pipelines set ROCI_REQUIRE_SDL3,
// so for them "cannot run" is a failure, never a quiet skip.
abi_outcome :: proc(exit_code: int, required: bool) -> Check_Outcome {
	switch {
	case exit_code == 0:                                   return .Passed
	case exit_code == ABI_CHECK_UNAVAILABLE && !required:  return .Skipped
	}
	return .Failed
}

// The C ABI check (tools/abi-check.sh): builds roci as a shared library and compares
// what it exports with include/roci.h. It needs a Unix shell, a C compiler and SDL3,
// so on Windows and on computers without SDL3 it is skipped, unless
// ROCI_REQUIRE_SDL3 is set, as it is in both pipelines.
check_abi :: proc() -> bool {
	name := "C ABI: include/roci.h against the shared library"
	fmt.printfln("%s", term.out(fmt.tprintf("== %s", name), .Bold_Cyan))
	when ODIN_OS == .Windows {
		fmt.printfln("   %s", term.out("skipped, it needs a Unix shell", .Dim))
		return true
	}
	started := time.now()
	state, stdout, stderr, err := os.process_exec({command = {"sh", "tools/abi-check.sh"}}, context.allocator)
	required := os.get_env("ROCI_REQUIRE_SDL3", context.temp_allocator) != ""
	outcome := abi_outcome(state.exit_code if err == nil else -1, required)
	switch outcome {
	case .Passed:
		fmt.printfln("   %s%s", term.out_icon(.Ok), term.out(fmt.tprintf("ok, %.1f s", time.duration_seconds(time.since(started))), .Green))
		return true
	case .Skipped:
		fmt.printfln("   %s", term.out("skipped, no C compiler or SDL3 here (the pipelines require them)", .Dim))
		return true
	case .Failed:
		fmt.eprintfln("%s", term.err(fmt.tprintf("%s failed (%v, exit code %d)", name, err, state.exit_code), .Bold_Red))
		fmt.eprint(string(stdout))
		fmt.eprint(string(stderr))
		return false
	}
	return false
}
