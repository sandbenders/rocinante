// SPDX-License-Identifier: 0BSD
//
// The rocinante build script. Run it with:
//
//     odin run build -- <command>
//
// `ci` runs exactly what both pipelines run, so nothing lives only in YAML
// (CLAUDE.md section 11). `ci --fast` is the part the pre-push hook runs.
package build

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

import "../tools/term"

USAGE :: `usage: odin run build -- <command>

commands:
  ci [--fast]   run the checks the pipelines run (--fast: the pre-push subset)
  licences      check dependency licences (CLAUDE.md section 3)
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
TEST_PACKAGES :: []string{"build", "roci/geom", "roci/gfx", "roci/maths", "roci/platform", "roci/registry", "spikes/codegen", "tools/term"}

// Where `odin test` writes each package's test program. Left to itself it writes
// build.exe to the repository root, the very file `odin run build` is running
// from, which Windows keeps locked.
TEST_OUT_DIR :: "output/tests"

// Odin on Windows refuses an -out: path without .exe.
EXE :: ".exe" when ODIN_OS == .Windows else ""

test_binary :: proc(package_dir: string) -> string {
	name, _ := strings.replace_all(package_dir, "/", "_", context.temp_allocator)
	return fmt.tprintf("%s/%s%s", TEST_OUT_DIR, name, EXE)
}

ci :: proc(fast: bool) -> bool {
	ok := check_odin()
	ok = check_licences(".") && ok
	// Compile-check every Odin package that exists so far.
	ok = check_packages() && ok
	if !fast {
		fmt.printfln("%s %s", term.out("== golden images, back-end equivalence, benchmarks:", .Bold_Cyan), term.out("not built yet", .Dim))
	}
	if ok {
		fmt.printfln("\n%s%s", term.out_icon(.Ok), term.out("ci: all checks passed", .Bold_Green))
	} else {
		fmt.eprintfln("\n%s%s", term.err_icon(.Missing), term.err("ci: FAILED, see the messages above", .Bold_Red))
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
	// ones need their SDKs and are built by hand (CLAUDE.md section 8).
	ok = step("check shapes example", {"odin", "check", "examples/shapes", "-vet", "-strict-style"}) && ok
	ok = step("check golden tests", {"odin", "check", "tests/golden", "-vet", "-strict-style"}) && ok
	ok = step("check window example", {"odin", "check", "examples/window", "-vet", "-strict-style"}) && ok
	ok = step("check spike 2 shared code", {"odin", "check", "spikes/mobile/shared", "-no-entry-point", "-vet", "-strict-style"}) && ok
	// Spike 3: interpret, generate Odin, build it and compare the output.
	ok = step("spike 3: code generation", {"odin", "run", "spikes/codegen", "--", "check"}) && ok
	return ok
}
