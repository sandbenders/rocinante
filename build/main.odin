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

USAGE :: `usage: odin run build -- <command>

commands:
  ci [--fast]   run the checks the pipelines run (--fast: the pre-push subset)
  licences      check dependency licences (CLAUDE.md section 3)
  odin          check the installed Odin against ODIN_VERSION
`

main :: proc() {
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
	fmt.printfln("== %s", name)
	state, stdout, stderr, err := os.process_exec({command = command}, context.allocator)
	if err != nil || state.exit_code != 0 {
		fmt.eprintfln("%s failed (%v, exit code %d)", name, err, state.exit_code)
		fmt.eprint(string(stdout))
		fmt.eprint(string(stderr))
		return false
	}
	return true
}

// The pinned Odin lives in ODIN_VERSION. A different local Odin is a warning on
// a developer's machine and an error in the pipelines, which set CI.
check_odin :: proc() -> bool {
	data, read_err := os.read_entire_file("ODIN_VERSION", context.allocator)
	if read_err != nil {
		fmt.eprintfln("cannot read ODIN_VERSION: %v", read_err)
		return false
	}
	pinned := strings.trim_space(string(data))

	state, stdout, _, err := os.process_exec({command = {"odin", "version"}}, context.allocator)
	if err != nil || state.exit_code != 0 {
		fmt.eprintfln("cannot run `odin version`: %v", err)
		return false
	}
	have := strings.trim_space(string(stdout))
	if strings.contains(have, pinned) {
		fmt.printfln("odin: ok (%s)", pinned)
		return true
	}
	fmt.eprintfln("odin: this rocinante release is pinned to %s, but you have '%s'.", pinned, have)
	if os.get_env("CI", context.temp_allocator) != "" {
		return false
	}
	fmt.eprintln("odin: continuing, because this is not a pipeline.")
	return true
}

ci :: proc(fast: bool) -> bool {
	ok := check_odin()
	ok = check_licences(".") && ok
	// Compile-check every Odin package that exists so far.
	ok = check_packages() && ok
	if !fast {
		fmt.println("== golden images, back-end equivalence, benchmarks: not built yet")
	}
	return ok
}

// `odin check` on the build script. Packages under roci/ and cli/ join this list
// as they appear.
check_packages :: proc() -> bool {
	ok := step("check build script", {"odin", "check", "build", "-vet", "-strict-style"})
	// Spike 3: interpret, generate Odin, build it and compare the output.
	ok = step("spike 3: code generation", {"odin", "run", "spikes/codegen", "--", "check"}) && ok
	return ok
}
