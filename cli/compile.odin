// SPDX-License-Identifier: 0BSD
//
// `roci run --compile`: turn the sketch into Odin, build it with the Odin this rocinante was made for, and
// run the program it makes in the terminal. It is for measuring how fast a sketch is when it is compiled, not
// for sharing it (that is `roci package`): the program goes in the `artifacts` folder of the sketch's folder,
// reads the sketch's `assets` where they are, and is not signed or bundled. Compiling builds the core's Odin
// source with the sketch, which is why it needs the source of rocinante beside the `roci` that is running (or
// `ROCI_SOURCE` saying where it is) and the pinned Odin.
package main

import "../roci/codegen"
import "../roci/folder"
import "../roci/interp"
import "../roci/lang"
import "../tools/term"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

// The name of the system and processor in a folder name: macos-arm64, linux-amd64, windows-amd64.
system_folder :: proc() -> string {
	system := "macos" when ODIN_OS == .Darwin else "windows" when ODIN_OS == .Windows else "linux" when ODIN_OS == .Linux else "freebsd" when ODIN_OS == .FreeBSD else "openbsd"
	arch := "arm64" when ODIN_ARCH == .arm64 else "amd64" when ODIN_ARCH == .amd64 else "other"
	return strings.concatenate({system, "-", arch}, context.temp_allocator)
}

// Where the source of rocinante is: `ROCI_SOURCE`, else the folder above the one this program is in that
// has `ODIN_VERSION` and `roci` (a build of the repository puts `roci` in its `output` folder).
find_source :: proc() -> (root: string, ok: bool) {
	if env := os.get_env("ROCI_SOURCE", context.temp_allocator); env != "" {
		return strings.trim_right(env, "/"), is_source(env)
	}
	dir, err := os.get_executable_directory(context.temp_allocator)
	if err != nil {
		return "", false
	}
	for _ in 0 ..< 6 {
		if is_source(dir) {
			return dir, true
		}
		slash := strings.last_index_byte(dir, '/')
		if slash <= 0 {
			break
		}
		dir = dir[:slash]
	}
	return "", false
}

@(private)
is_source :: proc(dir: string) -> bool {
	return os.exists(strings.concatenate({dir, "/ODIN_VERSION"}, context.temp_allocator)) && os.is_directory(strings.concatenate({dir, "/roci"}, context.temp_allocator))
}

// Whether the Odin on the PATH is the release this rocinante is pinned to.
check_odin :: proc(err: ^strings.Builder) -> bool {
	state, stdout, _, run_err := os.process_exec({command = {"odin", "version"}}, context.temp_allocator)
	if run_err != nil || state.exit_code != 0 {
		fmt.sbprintf(err, "I need Odin to compile a sketch, and I cannot run `odin`. Install the release rocinante is pinned to, %s (`roci doctor` says how), and run this again.\n", ODIN_VERSION)
		return false
	}
	if !strings.contains(string(stdout), ODIN_VERSION) {
		fmt.sbprintf(err, "The Odin on this computer is `%s`, and this rocinante is pinned to %s, because a sketch must behave the same however it is made. Install that release and put it first on the PATH.\n", strings.trim_space(string(stdout)), ODIN_VERSION)
		return false
	}
	return true
}

// Compiles the sketch and runs it. `args` are what `roci run` was given, of which the ones a compiled
// program takes go on to it.
run_compile :: proc(parsed: Run_Args, file: string, files: []lang.File_Text, out, err: ^strings.Builder) -> int {
	if parsed.target != "" {
		fmt.sbprintf(err, "Compiling for %s and putting the app on a phone is not built yet. For now `roci run --compile` compiles for this computer.\n", parsed.target)
		return 2
	}
	if len(parsed.inputs) > 0 || parsed.window != 1 || parsed.json {
		fmt.sbprintf(err, "`--press`, `--hold`, `--window` and `--errors` are for the interpreter and do not go with `--compile`.\n")
		return 2
	}
	if !check_odin(err) {
		return 2
	}
	root, found := find_source()
	if !found {
		fmt.sbprintf(err, "I need the source of rocinante next to me to compile a sketch (the folder with `roci` and `ODIN_VERSION` in it), and I cannot find it. Set ROCI_SOURCE to that folder.\n")
		return 2
	}
	p, ok := interp.load_files(files)
	defer interp.destroy(p)
	if len(p.checked.diagnostics) > 0 {
		fmt.sbprintf(err, "%s\n", term.message(lang.render_all(p.src, p.checked.diagnostics, context.temp_allocator), term.err_colour))
	}
	if !ok {
		return 1
	}
	sketch := sketch_name(file)
	generated := codegen.generate(&p.checked.program, p.src, codegen.Options{sketch = sketch, source = file}, context.temp_allocator)
	if len(generated.problems) > 0 {
		say_problems(generated.problems, p.src, err)
		return 4
	}
	mode := "debug" if parsed.debug else "release"
	artifacts := artifacts_folder(file)
	folder_path := strings.concatenate({artifacts, "/", system_folder(), "/", mode}, context.temp_allocator)
	source_folder := strings.concatenate({folder_path, "/source"}, context.temp_allocator)
	if !folder.ensure_directory(source_folder) {
		fmt.sbprintf(err, "I cannot make the folder `%s`.\n", source_folder)
		return 2
	}
	if os.write_entire_file(strings.concatenate({source_folder, "/sketch.odin"}, context.temp_allocator), transmute([]byte)generated.source) != nil {
		fmt.sbprintf(err, "I cannot write the program into `%s`.\n", source_folder)
		return 2
	}
	// `ROCI_COMPILE_CHECK=1` only type-checks the program that was made, which is how a change to the generator is
	// tried on every example in seconds (an example that passes is then built and compared for real).
	if os.get_env("ROCI_COMPILE_CHECK", context.temp_allocator) != "" {
		state, _, check_err, check_run_err := os.process_exec({command = {"odin", "check", source_folder, strings.concatenate({"-collection:rocinante=", root}, context.temp_allocator)}}, context.temp_allocator)
		_ = check_run_err
		if state.exit_code != 0 {
			fmt.sbprintf(err, "The compiler could not build the program.\n%s\n", string(check_err))
			return 5
		}
		fmt.sbprintf(out, "checked\n")
		return 0
	}
	binary := strings.concatenate({folder_path, "/", sketch, ".exe" if ODIN_OS == .Windows else ""}, context.temp_allocator)
	fmt.sbprintf(out, "%s %s\n", term.out("compiling", .Bold_Cyan), term.out(fmt.tprintf("%s (%s) with Odin %s", sketch, mode, ODIN_VERSION), .Cyan))
	if !build(root, source_folder, binary, parsed.debug, folder_path, err) {
		return 5
	}
	fmt.sbprintf(out, "%s %s\n", term.out("made", .Bold_Cyan), term.out(binary, .Cyan))
	// what the program is told: the words of `roci run` it understands, and where its log goes
	// the program runs in the sketch's folder, so every path it is given is made whole first
	whole :: proc(path: string) -> string {
		if filepath.is_abs(path) {
			return path
		}
		cwd, cwd_err := os.get_working_directory(context.temp_allocator)
		if cwd_err != nil {
			return path
		}
		return strings.concatenate({strings.trim_right(cwd, "/"), "/", strings.trim_prefix(path, "./")}, context.temp_allocator)
	}
	command := make([dynamic]string, context.temp_allocator)
	append(&command, whole(binary))
	if parsed.frames > 0 {
		append(&command, "--frames", fmt.tprint(parsed.frames), "--seed", fmt.tprint(parsed.seed))
	}
	if parsed.screenshot != "" {
		append(&command, "--screenshot", whole(parsed.screenshot))
	}
	if parsed.stats {
		append(&command, "--stats", "--log", whole(strings.concatenate({artifacts, "/log.json"}, context.temp_allocator)), "--mode", "compiled debug" if parsed.debug else "compiled")
	}
	if parsed.no_vsync {
		append(&command, "--no-vsync")
	}
	// the sketch's assets are where its folder is
	process, start_err := os.process_start({command = command[:], working_dir = folder.root_of(file), stdout = os.stdout, stderr = os.stderr})
	if start_err != nil {
		fmt.sbprintf(err, "I could not start `%s`.\n", binary)
		return 5
	}
	state, wait_err := os.process_wait(process)
	if wait_err != nil {
		return 5
	}
	return state.exit_code
}

// The name of a sketch's folder, which names the program.
sketch_name :: proc(file: string) -> string {
	dir := folder.root_of(file)
	if dir == "." || dir == "" || dir == "/" {
		// a lone file: its own name without the extension
		base := file[strings.last_index_byte(file, '/') + 1:]
		return strings.trim_suffix(base, ".roci")
	}
	return dir[strings.last_index_byte(dir, '/') + 1:]
}

// Builds the program. The output is kept in `build.log` beside it, and only the first lines of a failure are
// shown, in the same plain style as everything else.
build :: proc(root, source_folder, binary: string, debug: bool, folder_path: string, err: ^strings.Builder) -> bool {
	command := make([dynamic]string, context.temp_allocator)
	append(&command, "odin", "build", source_folder, strings.concatenate({"-collection:rocinante=", root}, context.temp_allocator), strings.concatenate({"-out:", binary}, context.temp_allocator))
	if debug {
		append(&command, "-debug", "-o:none")
	} else if os.get_env("ROCI_COMPILE_FAST", context.temp_allocator) != "" {
		append(&command, "-o:minimal") // for trying many sketches quickly; a program to measure is built without it
	} else {
		append(&command, "-o:speed")
	}
	state, stdout, stderr, run_err := os.process_exec({command = command[:]}, context.temp_allocator)
	log := strings.concatenate({string(stdout), string(stderr)}, context.temp_allocator)
	log_path := strings.concatenate({folder_path, "/build.log"}, context.temp_allocator)
	_ = os.write_entire_file(log_path, transmute([]byte)log)
	if run_err != nil || state.exit_code != 0 {
		fmt.sbprintf(err, "%s\n", term.err("The compiler could not build the program.", .Bold_Red))
		lines := strings.split_lines(log, context.temp_allocator)
		shown := 0
		for l in lines {
			if strings.contains(l, "warning") || strings.trim_space(l) == "" {
				continue
			}
			fmt.sbprintf(err, "  %s\n", l)
			shown += 1
			if shown >= 12 {
				break
			}
		}
		fmt.sbprintf(err, "The whole of it is in %s. The program it was made from is in %s/source, and `roci doctor` checks the tools.\n", log_path, folder_path)
		return false
	}
	return true
}

// What a sketch uses that cannot be compiled yet, a line at a time.
say_problems :: proc(problems: []codegen.Problem, src: lang.Source, err: ^strings.Builder) {
	fmt.sbprintf(err, "%s\n\n", term.err("I cannot compile this sketch yet. It uses:", .Bold_Red))
	shown := 0
	for p in problems {
		line, column := codegen.position(src, p.span)
		// the files of a sketch are joined, so the line is counted from the start of the file it is in
		file := ""
		joined := line
		for part in src.parts {
			if part.start <= p.span.start {
				file = part.name
				line = joined - part.first_line + 1
			}
		}
		if file != "" {
			fmt.sbprintf(err, "  %s, line %d, column %d: %s\n", file, line, column, p.what)
		} else {
			fmt.sbprintf(err, "  line %d, column %d: %s\n", line, column, p.what)
		}
		shown += 1
		if shown >= 20 && len(problems) > 22 {
			fmt.sbprintf(err, "  and %d more\n", len(problems) - shown)
			break
		}
	}
	fmt.sbprintf(err, "\nA sketch runs the same either way, so I would rather say so than compile part of it. `roci run` without `--compile` runs it with the interpreter.\n")
}
