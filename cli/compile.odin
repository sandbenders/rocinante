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
	if parsed.target != "" && (parsed.frames > 0 || parsed.screenshot != "" || parsed.stats || parsed.no_vsync || parsed.debug) {
		fmt.sbprintf(err, "`--frames`, `--screenshot`, `--stats`, `--no-vsync` and `--debug` are for a program on this computer and do not go with `--target`.\n")
		return 2
	}
	if len(parsed.inputs) > 0 || parsed.window != 1 || parsed.json {
		fmt.sbprintf(err, "`--press`, `--hold`, `--touch`, `--drag`, `--window` and `--errors` are for the interpreter and do not go with `--compile`.\n")
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
	sketch := sketch_name(file)
	mode := "debug" if parsed.debug else "release"
	artifacts := artifacts_folder(file)
	folder_path := strings.concatenate({artifacts, "/", system_folder(), "/", mode}, context.temp_allocator)
	if parsed.target != "" {
		folder_path = strings.concatenate({artifacts, "/", parsed.target, "-source"}, context.temp_allocator)
	}
	// what has been said so far comes first, then the steps, drawn as they go
	fmt.print(strings.to_string(out^))
	strings.builder_reset(out)
	p: term.Progress
	title := sketch_title(file)
	if parsed.target != "" {
		term.progress_begin(&p, .Phone, fmt.tprintf("Putting %s on %s", title, phone_name(parsed.target)))
	} else {
		term.progress_begin(&p, .Compile, fmt.tprintf("Compiling %s%s", title, " for debugging" if parsed.debug else ""))
	}
	term.progress_step(&p, .Check, "Reading the sketch")
	source_folder, code := make_source(file, files, phone_system(parsed.target), "", "", folder_path, err)
	if code != 0 {
		term.progress_fail(&p)
		return code
	}
	if parsed.target != "" {
		return put_on_phone(&p, parsed, root, title, source_folder, folder.root_of(file), err)
	}
	// `ROCI_COMPILE_CHECK=1` only type-checks the program that was made, which is how a change to the generator is
	// tried on every example in seconds (an example that passes is then built and compared for real).
	if os.get_env("ROCI_COMPILE_CHECK", context.temp_allocator) != "" {
		term.progress_step(&p, .Check, "Checking the program")
		state, _, check_err, check_run_err := os.process_exec({command = {"odin", "check", source_folder, strings.concatenate({"-collection:rocinante=", root}, context.temp_allocator)}}, context.temp_allocator)
		_ = check_run_err
		if state.exit_code != 0 {
			term.progress_fail(&p)
			fmt.sbprintf(err, "The compiler could not build the program.\n%s\n", string(check_err))
			return 5
		}
		term.progress_finish(&p, "Checked")
		return 0
	}
	binary := strings.concatenate({folder_path, "/", sketch, ".exe" if ODIN_OS == .Windows else ""}, context.temp_allocator)
	term.progress_step(&p, .Compile, "Compiling the sketch")
	if !build(root, source_folder, binary, parsed.debug, folder_path, err) {
		term.progress_fail(&p)
		return 5
	}
	term.progress_finish(&p)
	term.progress_result(&p, "program", binary)
	fmt.println()
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

// Checks a sketch, turns it into the Odin source of its program and writes it as `source/sketch.odin` in `folder_path`, which it
// makes. `target` is "", "ios", "android", or "macos", "linux", "freebsd" or "openbsd" for an app, whose `app_id` names the folder it keeps its files in
// and its windows, and whose `app_name` is what volume controls show. Gives the folder the source is in, and 0, or what went wrong
// said in `err` and a code to exit with: 1 the sketch has errors, 4 it uses what cannot be compiled yet, 2 the files could not be written.
make_source :: proc(file: string, files: []lang.File_Text, target, app_id, app_name, folder_path: string, err: ^strings.Builder) -> (source_folder: string, code: int) {
	p, ok := interp.load_files(files)
	defer interp.destroy(p)
	if len(p.checked.diagnostics) > 0 {
		fmt.sbprintf(err, "%s\n", term.message(lang.render_all(p.src, p.checked.diagnostics, context.temp_allocator), term.err_colour))
	}
	if !ok {
		return "", 1
	}
	generated := codegen.generate(&p.checked.program, p.src, codegen.Options{sketch = sketch_name(file), source = file, target = target, app_id = app_id, app_name = app_name}, context.temp_allocator)
	if len(generated.problems) > 0 {
		say_problems(generated.problems, p.src, err)
		return "", 4
	}
	source_folder = strings.concatenate({folder_path, "/source"}, context.temp_allocator)
	if !folder.ensure_directory(source_folder) {
		fmt.sbprintf(err, "I cannot make the folder `%s`.\n", source_folder)
		return "", 2
	}
	if os.write_entire_file(strings.concatenate({source_folder, "/sketch.odin"}, context.temp_allocator), transmute([]byte)generated.source) != nil {
		fmt.sbprintf(err, "I cannot write the program into `%s`.\n", source_folder)
		return "", 2
	}
	return source_folder, 0
}

// The name a sketch is called by in what roci says: its folder's when the file is the `sketch.roci` of a folder (run as
// `roci run` inside it, the file has no folder in its name), else the file's own.
sketch_title :: proc(file: string) -> string {
	name := sketch_name(file)
	if name != "sketch" {
		return name
	}
	whole, abs_err := filepath.abs(folder.root_of(file), context.temp_allocator)
	if abs_err != nil {
		return name
	}
	whole = strings.trim_right(whole, "/")
	if slash := strings.last_index_byte(whole, '/'); slash >= 0 && slash + 1 < len(whole) {
		return whole[slash + 1:]
	}
	return name
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
build :: proc(root, source_folder, binary: string, debug: bool, folder_path: string, err: ^strings.Builder, extra: []string = nil) -> bool {
	command := make([dynamic]string, context.temp_allocator)
	append(&command, "odin", "build", source_folder, strings.concatenate({"-collection:rocinante=", root}, context.temp_allocator), strings.concatenate({"-out:", binary}, context.temp_allocator))
	if debug {
		append(&command, "-debug", "-o:none")
	} else if os.get_env("ROCI_COMPILE_FAST", context.temp_allocator) != "" {
		append(&command, "-o:minimal") // for trying many sketches quickly; a program to measure is built without it
	} else {
		append(&command, "-o:speed")
	}
	append(&command, ..extra)
	state, stdout, stderr, run_err := os.process_exec({command = command[:]}, context.temp_allocator)
	log := strings.concatenate({string(stdout), string(stderr)}, context.temp_allocator)
	if (run_err != nil || state.exit_code != 0) && strings.trim_space(log) == "" {
		log = compiler_silent(state, run_err)
	}
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

// What to say when the compiler failed without a word: it could not be started, or the system ended it, which on Linux is
// most often for taking all the memory (a signal's number is its exit code then, 9 for the kill the out-of-memory killer sends).
compiler_silent :: proc(state: os.Process_State, run_err: os.Error) -> string {
	if run_err != nil {
		return fmt.tprintf("The compiler could not be started (%v). `roci doctor` says whether Odin is installed and on the PATH.\n", run_err)
	}
	if state.exit_code == 9 || state.exit_code == 137 {
		return "The compiler was stopped by the system before it said anything, most often because it ran out of memory. Close other programs and try again; if it happens again, it is a bug worth reporting with this sketch.\n"
	}
	return fmt.tprintf("The compiler stopped with code %d and said nothing.\n", state.exit_code)
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

// The system a phone target is for: `android-emulator` is an Android program.
phone_system :: proc(target: string) -> string {
	switch target {
	case "android-emulator":
		return "android"
	}
	return target
}

// The variable of the phone script that `--device` fills: an iPhone for iOS, a connected phone
// (`ANDROID_SERIAL`) or an emulator's virtual device, found by its name (`AVD`), for Android; a serial that
// begins with `emulator-` is a running emulator.
device_variable :: proc(target, device: string) -> string {
	switch target {
	case "ios":
		return "DEVICE"
	case "android-emulator":
		return "ANDROID_SERIAL" if strings.has_prefix(device, "emulator-") else "AVD"
	}
	return "ANDROID_SERIAL"
}

// The phone a target names, for the line that says where the sketch is going.
phone_name :: proc(target: string) -> string {
	switch target {
	case "ios":
		return "the iPhone"
	case "android":
		return "the Android phone"
	case "android-emulator":
		return "the Android emulator"
	}
	return target
}

// One line the phone script says: a step it starts, something it made, its last word, what went wrong, or anything
// else, which is what one of the tools it runs said (kept in the log).
Phone_Line_Kind :: enum {
	Other,
	Step,
	Result,
	Finished,
	Problem,
}

Phone_Line :: struct {
	kind: Phone_Line_Kind,
	step: term.Step_Kind,
	name: string, // a result's name
	text: string,
}

parse_phone_line :: proc(line: string) -> Phone_Line {
	word, rest := line, ""
	if space := strings.index_byte(line, ' '); space >= 0 {
		word, rest = line[:space], line[space + 1:]
	}
	switch word {
	case "step":
		kind_word, words := rest, ""
		if space := strings.index_byte(rest, ' '); space >= 0 {
			kind_word, words = rest[:space], rest[space + 1:]
		}
		kind: term.Step_Kind
		switch kind_word {
		case "libraries": kind = .Libraries
		case "phone": kind = .Phone
		case "compile": kind = .Compile
		case "bundle": kind = .Bundle
		case "sign": kind = .Sign
		case "install": kind = .Install
		case "start": kind = .Start
		case: return {kind = .Other, text = line}
		}
		if words != "" {
			return {kind = .Step, step = kind, text = words}
		}
	case "result":
		if space := strings.index_byte(rest, ' '); space > 0 {
			return {kind = .Result, name = rest[:space], text = rest[space + 1:]}
		}
	case "finished":
		if rest != "" {
			return {kind = .Finished, text = rest}
		}
	case "problem":
		if rest != "" {
			return {kind = .Problem, text = rest}
		}
	}
	return {kind = .Other, text = line}
}

// The script that builds the program for a phone, installs it and starts it. What it says comes through a pipe: its
// steps are drawn in `p` as they come, and what the tools it runs say is kept in the sketch's `artifacts/<target>.log`,
// shown only when something goes wrong.
put_on_phone :: proc(p: ^term.Progress, parsed: Run_Args, root, sketch, source_folder, sketch_folder: string, err: ^strings.Builder) -> int {
	system := phone_system(parsed.target)
	script := strings.concatenate({root, "/tools/mobile-", system, ".sh"}, context.temp_allocator)
	command := make([dynamic]string, context.temp_allocator)
	append(&command, "env")
	append(&command, strings.concatenate({"ROCI_ROOT=", root}, context.temp_allocator))
	if parsed.target == "android-emulator" {
		append(&command, "EMULATOR=1")
	}
	if parsed.device != "" {
		append(&command, strings.concatenate({device_variable(parsed.target, parsed.device), "=", parsed.device}, context.temp_allocator))
	}
	if parsed.team != "" {
		append(&command, strings.concatenate({"TEAM_ID=", parsed.team}, context.temp_allocator))
	}
	whole := source_folder
	if !filepath.is_abs(whole) {
		cwd, _ := os.get_working_directory(context.temp_allocator)
		whole = strings.concatenate({strings.trim_right(cwd, "/"), "/", strings.trim_prefix(whole, "./")}, context.temp_allocator)
	}
	sketch_whole := sketch_folder
	if !filepath.is_abs(sketch_whole) {
		cwd, _ := os.get_working_directory(context.temp_allocator)
		sketch_whole = strings.concatenate({strings.trim_right(cwd, "/"), "/", strings.trim_prefix(sketch_folder, "./")}, context.temp_allocator)
	}
	// without a `/./` in them, since the paths the script makes from them are shown
	if cleaned, clean_err := filepath.clean(whole, context.temp_allocator); clean_err == nil {
		whole = cleaned
	}
	if cleaned, clean_err := filepath.clean(sketch_whole, context.temp_allocator); clean_err == nil {
		sketch_whole = cleaned
	}
	append(&command, "sh", script, whole, sketch_whole, sketch)
	_ = folder.ensure_directory(strings.concatenate({sketch_whole, "/artifacts"}, context.temp_allocator))
	log_path := strings.concatenate({sketch_whole, "/artifacts/", parsed.target, ".log"}, context.temp_allocator)
	if cleaned, clean_err := filepath.clean(log_path, context.temp_allocator); clean_err == nil {
		log_path = cleaned
	}
	log, log_err := os.create(log_path)
	defer if log_err == nil {
		os.close(log)
	}
	reader, writer, pipe_err := os.pipe()
	if pipe_err != nil {
		term.progress_fail(p)
		fmt.sbprintf(err, "I could not start `%s`.\n", script)
		return 5
	}
	defer os.close(reader)
	process, start_err := os.process_start({command = command[:], stdout = writer, stderr = writer})
	os.close(writer) // the script holds its own end now, so the reading ends when it does
	if start_err != nil {
		term.progress_fail(p)
		fmt.sbprintf(err, "I could not start `%s`.\n", script)
		return 5
	}
	problems := make([dynamic]string, context.temp_allocator)
	results := make([dynamic]Phone_Line, context.temp_allocator)
	tail := make([dynamic]string, context.temp_allocator) // the last lines the tools said, for a failure
	finished := ""
	handle :: proc(line: string, p: ^term.Progress, log: ^os.File, problems, tail: ^[dynamic]string, results: ^[dynamic]Phone_Line, finished: ^string) {
		said := parse_phone_line(line)
		switch said.kind {
		case .Step:
			term.progress_step(p, said.step, said.text)
		case .Result:
			append(results, Phone_Line{kind = .Result, name = strings.clone(said.name, context.temp_allocator), text = strings.clone(said.text, context.temp_allocator)})
		case .Finished:
			finished^ = strings.clone(said.text, context.temp_allocator)
		case .Problem:
			append(problems, strings.clone(said.text, context.temp_allocator))
		case .Other:
			if log != nil {
				_, _ = os.write_string(log, line)
				_, _ = os.write_string(log, "\n")
			}
			append(tail, strings.clone(line, context.temp_allocator))
			if len(tail) > 15 {
				ordered_remove(tail, 0)
			}
		}
	}
	pending := strings.builder_make(context.temp_allocator)
	buffer: [4096]byte
	for {
		n, read_err := os.read(reader, buffer[:])
		if n > 0 {
			strings.write_bytes(&pending, buffer[:n])
			text := strings.to_string(pending)
			for {
				newline := strings.index_byte(text, '\n')
				if newline < 0 {
					break
				}
				handle(text[:newline], p, log if log_err == nil else nil, &problems, &tail, &results, &finished)
				text = text[newline + 1:]
			}
			rest := strings.clone(text, context.temp_allocator)
			strings.builder_reset(&pending)
			strings.write_string(&pending, rest)
		}
		if read_err != nil || n == 0 {
			break
		}
	}
	if left := strings.to_string(pending); left != "" {
		handle(left, p, log if log_err == nil else nil, &problems, &tail, &results, &finished)
	}
	state, wait_err := os.process_wait(process)
	if wait_err != nil || state.exit_code != 0 {
		term.progress_fail(p)
		for problem in problems {
			fmt.sbprintf(err, "%s\n", problem)
		}
		if len(problems) == 0 {
			fmt.sbprintf(err, "Something went wrong on the way to the phone. The last of what the tools said:\n")
			for line in tail {
				fmt.sbprintf(err, "  %s\n", line)
			}
		}
		// the log holds what the tools said, worth pointing at only when they said something
		if len(tail) > 0 {
			fmt.sbprintf(err, "The whole of it is in %s.\n", log_path)
		}
		return state.exit_code if state.exit_code != 0 else 5
	}
	term.progress_finish(p)
	for r in results {
		term.progress_result(p, r.name, r.text)
	}
	if finished != "" {
		fmt.printfln("\n%s", finished)
	}
	return 0
}
