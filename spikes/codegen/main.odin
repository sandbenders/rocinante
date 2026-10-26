// SPDX-License-Identifier: 0BSD
//
// Spike 3 (CLAUDE.md section 8, Phase 0): a hand-written typed-IR fragment is
// run by a small interpreter and turned into Odin source, which is built with
// the pinned Odin and run. Both must print exactly the same thing, which is
// non-negotiable 7 in miniature. Run it from the repository root:
//
//     odin run spikes/codegen -- check     interpret, generate, build, compare
//     odin run spikes/codegen -- doctor    say which targets this computer can build, and look for the toolchain
package codegen_spike

import "core:fmt"
import "core:os"
import "core:strings"
import "verbs"
import "../../tools/term"

OUT_DIR :: "output/codegen"

// Odin on Windows refuses an -out: path without .exe.
EXE :: ".exe" when ODIN_OS == .Windows else ""

// The generated program's path inside its folder.
binary_path :: proc(dir: string) -> string {
	return fmt.tprintf("%s/sketch%s", dir, EXE)
}

main :: proc() {
	command := "check"
	if len(os.args) > 1 {
		command = os.args[1]
	}
	term.setup()
	ok: bool
	switch command {
	case "check":
		ok = run_check()
	case "doctor":
		// `doctor <host>` pretends to be another computer, to see its messages.
		ok = doctor(pinned_odin(), os.args[2] if len(os.args) > 2 else "")
	case:
		fmt.eprintln("usage: odin run spikes/codegen -- check | doctor")
	}
	if !ok {
		os.exit(1)
	}
}

pinned_odin :: proc() -> string {
	data, err := os.read_entire_file("ODIN_VERSION", context.allocator)
	if err != nil {
		return ""
	}
	return strings.trim_space(string(data))
}

run_check :: proc() -> bool {
	ok := true
	for program in ([]Program{program_circle(), program_loop(), program_records()}) {
		ok = check_one(program) && ok
	}
	return ok
}

check_one :: proc(p: Program) -> bool {
	fmt.printfln("%s", term.out(fmt.tprintf("== %s", p.name), .Bold_Cyan))

	errors := check_program(p)
	if len(errors) > 0 {
		for message in errors {
			fmt.eprintln(term.err(message, .Red))
		}
		return false
	}

	// 1. The interpreter, capturing what the verbs print.
	captured: strings.Builder
	strings.builder_init(&captured)
	verbs.sink = &captured
	interpret(p)
	verbs.sink = nil
	expected := strings.to_string(captured)

	// 2. Generate Odin into its own folder, next to a copy of the verbs.
	dir := fmt.tprintf("%s/%s", OUT_DIR, p.name)
	if err := os.make_directory_all(fmt.tprintf("%s/verbs", dir)); err != nil && err != .Exist {
		fmt.eprintfln("cannot create %s: %v", dir, err)
		return false
	}
	verbs_source, read_err := os.read_entire_file("spikes/codegen/verbs/verbs.odin", context.allocator)
	if read_err != nil {
		fmt.eprintfln("cannot read the verbs: %v", read_err)
		return false
	}
	source := generate(p)
	if err := os.write_entire_file(fmt.tprintf("%s/main.odin", dir), source); err != nil {
		fmt.eprintfln("cannot write the generated source: %v", err)
		return false
	}
	if err := os.write_entire_file(fmt.tprintf("%s/verbs/verbs.odin", dir), verbs_source); err != nil {
		fmt.eprintfln("cannot write the verbs: %v", err)
		return false
	}
	fmt.print(source)

	// 3. Build it with the same Odin that built this program.
	binary := binary_path(dir)
	build_command := []string{"odin", "build", dir, "-vet", "-strict-style", fmt.tprintf("-out:%s", binary)}
	state, _, build_stderr, build_err := os.process_exec({command = build_command}, context.allocator)
	if build_err != nil || state.exit_code != 0 {
		fmt.eprintfln("the generated Odin did not build (%v, exit code %d):", build_err, state.exit_code)
		fmt.eprint(string(build_stderr))
		return false
	}

	// 4. Run the generated program and compare.
	run_state, run_stdout, _, run_err := os.process_exec({command = {binary}}, context.allocator)
	if run_err != nil || run_state.exit_code != 0 {
		fmt.eprintfln("the generated program failed (%v, exit code %d)", run_err, run_state.exit_code)
		return false
	}
	if string(run_stdout) != expected {
		fmt.eprintln(term.err("MISMATCH between the interpreter and the generated program", .Bold_Red))
		fmt.eprintfln("interpreter:\n%s", expected)
		fmt.eprintfln("generated:\n%s", string(run_stdout))
		return false
	}
	fmt.printfln("   %s", term.out(fmt.tprintf("identical output, %d lines", strings.count(expected, "\n")), .Green))
	return true
}
