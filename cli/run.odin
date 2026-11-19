// SPDX-License-Identifier: 0BSD
//
// `roci run`: read a sketch, check it, and run it. With `--frames N` it runs
// headless, N frames with a fixed time step, and can save a picture of the last
// one: that is how scripts and tests run a sketch. Without it the windows open and
// the sketch runs until it is closed.
package main

import "../roci"
import "../roci/folder"
import "../roci/gfx"
import "../roci/interp"
import "../roci/lang"
import "../tools/term"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

RUN_USAGE :: `roci run [file] [--frames N] [--screenshot out.png] [--window N] [--seed N] [--errors json]
             [--press key@frame] [--hold key@from-to] [--stats] [--no-vsync]

  file        the sketch to run; sketch.roci when left out
  --frames N  run N frames with no window, then stop
  --screenshot out.png
              with --frames, save a picture of the last frame
  --window N  which window the picture is of, counting from 1 (the first by default)
  --seed N    the seed of the random numbers when the sketch gives none (1 by default)
  --press key@frame
              with --frames, press a key in that frame, as 'on key' names keys and the first frame is
              0: --press "space@120". It can be given many times
  --hold key@from-to
              with --frames, hold a key down from one frame to another, both included:
              --hold "right@200-260"
  --stats     time the frames: a black box in the top left corner of each window shows the frame
              and the frame rate, and when the run ends a line says how fast it was and is added
              to artifacts/log.json in the sketch's folder (with --frames there is no window, so no box)
  --no-vsync  with a window, do not wait for the display, so the frame rate is what the computer can
              do and not what the screen allows (it goes with --stats)
  --errors json
              print every message as one line of JSON on standard output, for tools; with
              --frames what the sketch prints goes to standard error, and in a window each
              print is a line of JSON too, {"event":"print","text":"..."}, on standard output`

Run_Args :: struct {
	file:       string,
	frames:     int,
	screenshot: string,
	json:       bool, // messages as lines of JSON
	window:     int, // which window the picture is of, counting from 1
	seed:       u64,
	stats:      bool, // time the frames, show the box, and log the run
	no_vsync:   bool,
	inputs:     [dynamic]Input_Step, // the keys to press, from --press and --hold
	ok:         bool,
	bad:        string, // the word it did not understand, or what is missing after a flag
}

parse_run_args :: proc(args: []string) -> Run_Args {
	result := Run_Args {
		file   = "sketch.roci",
		seed   = 1,
		window = 1,
		ok     = true,
	}
	have_file := false
	i := 0
	for i < len(args) {
		arg := args[i]
		switch {
		case arg == "--frames" ||
		     arg == "--screenshot" ||
		     arg == "--seed" ||
		     arg == "--window" ||
		     arg == "--press" ||
		     arg == "--hold" ||
		     arg == "--errors":
			if i + 1 >= len(args) {
				return Run_Args{ok = false, bad = arg}
			}
			value := args[i + 1]
			i += 1
			switch arg {
			case "--frames":
				n, parsed := strconv.parse_int(value)
				if !parsed || n < 1 {
					return Run_Args{ok = false, bad = value}
				}
				result.frames = n
			case "--errors":
				if value != "json" {
					return Run_Args{ok = false, bad = value}
				}
				result.json = true
			case "--window":
				n, parsed := strconv.parse_int(value)
				if !parsed || n < 1 {
					return Run_Args{ok = false, bad = value}
				}
				result.window = n
			case "--seed":
				n, parsed := strconv.parse_u64(value)
				if !parsed {
					return Run_Args{ok = false, bad = value}
				}
				result.seed = n
			case "--screenshot":
				result.screenshot = value
			case "--press", "--hold":
				step, bad, step_ok := parse_input_step(value, arg == "--hold")
				if !step_ok {
					return Run_Args{ok = false, bad = bad}
				}
				if result.inputs == nil {
					result.inputs = make([dynamic]Input_Step, context.temp_allocator)
				}
				append(&result.inputs, step)
			}
		case arg == "--stats":
			result.stats = true
		case arg == "--no-vsync":
			result.no_vsync = true
		case strings.has_prefix(arg, "-"):
			return Run_Args{ok = false, bad = arg}
		case have_file:
			return Run_Args{ok = false, bad = arg}
		case:
			result.file = arg
			have_file = true
		}
		i += 1
	}
	if result.screenshot != "" && result.frames == 0 {
		return Run_Args{ok = false, bad = "--screenshot needs --frames"}
	}
	if result.no_vsync && result.frames > 0 {
		return Run_Args{ok = false, bad = "--no-vsync needs a window, so it does not go with --frames"}
	}
	if result.no_vsync && !result.stats {
		return Run_Args{ok = false, bad = "--no-vsync goes with --stats"}
	}
	if len(result.inputs) > 0 && result.frames == 0 {
		return Run_Args{ok = false, bad = "--press and --hold need --frames"}
	}
	return result
}

// What running a sketch gave: its printed lines, the messages, and the picture.
Run_Result :: struct {
	code:    int, // 0 ran, 1 the sketch has errors, 3 it ran and hit a runtime error
	json:    string, // the same messages, a line of JSON each
	report:  string, // check messages, then runtime errors, ready to print
	printed: []string,
	picture: []u8, // a PNG of the last frame, when asked for and the graphics could draw it
	problem: string, // why a picture could not be made
}

// Runs `text` headless for `frames` frames. The caller frees nothing: everything
// is made with the allocator given, which should be the temporary one.
run_text :: proc(
	name, text: string,
	frames: int,
	seed: u64,
	want_picture: bool,
	window := 1,
	allocator := context.temp_allocator,
	inputs: []Input_Step = nil,
	stats := false,
) -> Run_Result {
	return run_files({lang.File_Text{name = name, text = text}}, frames, seed, want_picture, window, allocator, inputs, stats)
}

// The same for a program of several files, given in the order they are joined.
run_files :: proc(
	files: []lang.File_Text,
	frames: int,
	seed: u64,
	want_picture: bool,
	window := 1,
	allocator := context.temp_allocator,
	inputs: []Input_Step = nil,
	stats := false,
) -> Run_Result {
	roci.start_headless(seed, true)
	defer roci.shutdown()
	if stats {
		roci.stats_start(false)
	}
	if len(files) > 0 && is_sketch_file(files[0].name) {
		roci.keep_beside(folder.root_of(files[0].name), false)
	}
	p, ok := interp.load_files(files)
	defer interp.destroy(p)
	result := Run_Result{}
	if len(p.checked.diagnostics) > 0 {
		result.report = lang.render_all(p.src, p.checked.diagnostics, allocator)
		result.json = lang.diagnostics_json(p.src, p.checked.diagnostics, allocator)
	}
	if !ok {
		result.code = 1
		return result
	}
	interp.start(p)
	step_frames(frames, inputs)
	if want_picture {
		windows := roci.open_windows()
		if window > len(windows) {
			result.problem = fmt.tprintf(
				"the sketch has no window %d to take a picture of",
				window,
			)
		} else if image, drawn := roci.picture(windows[window - 1]); drawn {
			defer delete(image.pixels)
			if png, encoded := gfx.png_encode(image, allocator); encoded {
				result.picture = png
			} else {
				result.problem = "the picture could not be saved"
			}
		} else {
			result.problem = fmt.tprintf("the picture could not be drawn: %s", roci.last_error())
		}
	}
	result.printed = make([]string, len(p.printed), allocator)
	for line, i in p.printed {
		result.printed[i] = strings.clone(line, allocator)
	}
	if len(p.errors) > 0 {
		result.report = strings.concatenate(
			{result.report, interp.report(p, allocator)},
			allocator,
		)
		runtime := make([]lang.Diagnostic, len(p.errors), allocator)
		for e, i in p.errors {
			runtime[i] = lang.Diagnostic {
				id   = e.id,
				span = e.span,
				args = e.args,
			}
		}
		result.json = strings.concatenate(
			{result.json, lang.diagnostics_json(p.src, runtime, allocator)},
			allocator,
		)
		result.code = 3
	}
	return result
}

// Runs `roci run`. Exit codes: 0 it ran, 1 the sketch has errors and did not run,
// 2 it could not be read or the words were wrong, 3 it ran but something failed
// while it did (a runtime error, or a picture that could not be made).
run_run :: proc(args: []string, out, err: ^strings.Builder) -> int {
	parsed := parse_run_args(args)
	if !parsed.ok {
		fmt.sbprintf(err, "I don't know `%s`.\n\n%s\n", parsed.bad, RUN_USAGE)
		return 2
	}
	file, found := sketch_file(parsed.file, err)
	if !found {
		return 2
	}
	files, read_ok := read_files(file, "roci run", err)
	if !read_ok {
		return 2
	}
	if parsed.frames == 0 {
		return run_windows(file, files, parsed.json, parsed.stats, parsed.no_vsync, out, err)
	}
	result := run_files(
		files,
		parsed.frames,
		parsed.seed,
		parsed.screenshot != "",
		parsed.window,
		inputs = parsed.inputs[:],
		stats = parsed.stats,
	)
	if parsed.stats {
		// the run has shut down, so what it measured is what the core kept
		report_stats(file, "interpreted", true, out, err)
	}
	// With JSON the messages are the output, so what the sketch prints moves aside.
	lines_to := err if parsed.json else out
	for line in result.printed {
		fmt.sbprintf(lines_to, "%s\n", line)
	}
	if parsed.json {
		fmt.sbprintf(out, "%s", result.json)
	} else if result.report != "" {
		fmt.sbprintf(err, "%s\n", term.message(result.report, term.err_colour))
	}
	code := result.code
	if parsed.screenshot != "" {
		switch {
		case result.picture != nil:
			if os.write_entire_file(parsed.screenshot, result.picture) != nil {
				fmt.sbprintf(err, "I cannot write `%s`.\n", parsed.screenshot)
				code = 3
			}
		case result.code == 0 || result.code == 3:
			fmt.sbprintf(err, "%s.\n", result.problem)
			code = 3
		}
	}
	return code
}

// Opens the windows and runs until they are closed.
@(private)
run_windows :: proc(name: string, files: []lang.File_Text, json: bool, stats, no_vsync: bool, out, err: ^strings.Builder) -> int {
	p, ok := interp.load_files(files)
	if len(p.checked.diagnostics) > 0 && (ok || json) {
		if json {
			fmt.sbprintf(
				out,
				"%s",
				lang.diagnostics_json(p.src, p.checked.diagnostics, context.temp_allocator),
			)
		} else {
			fmt.sbprintf(
				err,
				"%s\n",
				term.message(
					lang.render_all(p.src, p.checked.diagnostics, context.temp_allocator),
					term.err_colour,
				),
			)
		}
	}
	if !ok && json {
		interp.destroy(p)
		return 1
	}
	// The sketch is watched: saving the file reloads it, and Ctrl+R or Cmd+R runs it again.
	// Messages go to the console as they happen, so there is nothing to print at the end.
	p.echo = !json
	p.print_json = json // each `print` is a line of JSON on stdout, not a line kept for ever
	if !json {
		fmt.eprintfln(
			"%s %s",
			term.err("rocinante:", .Bold_Cyan),
			term.err(HOT_RELOAD_HINT(name), .Cyan),
		)
	}
	interp.watch(p, name)
	// The values of the widgets are remembered in the ui.toml of a sketch folder, and nowhere for a lone file.
	if is_sketch_file(name) {
		roci.ui_persist(fmt.tprintf("%s/ui.toml", folder.root_of(name)))
		roci.keep_beside(folder.root_of(name))
	}
	if stats {
		roci.stats_start(true, no_vsync)
	}
	interp.start(p)
	defer interp.shutdown()
	if !roci.run() {
		fmt.sbprintf(err, "I could not open a window on this computer.\n")
		return 3
	}
	if stats {
		report_stats(name, "interpreted", !no_vsync, out, err)
	}
	if running := interp.active(); running != nil {
		if running.has_errors {
			return 1 // it was never fixed
		}
		if len(running.errors) > 0 {
			return 3
		}
	}
	return 0
}

// The files of the program a sketch file stands for: a `sketch.roci` is the program of
// every .roci file in its folder (one folder is one program), and any other file runs
// alone. Says what is wrong when one cannot be read.
read_files :: proc(file: string, command: string, err: ^strings.Builder) -> (files: []lang.File_Text, ok: bool) {
	if is_sketch_file(file) {
		program, problem := folder.read_program(file)
		if problem != "" {
			fmt.sbprintf(err, "%s\n", problem)
			return nil, false
		}
		// A `use` of a git address that is not in libs/ yet is fetched the first time.
		if fetched := folder.fetch_missing_libraries(folder.root_of(file), program.files); len(fetched) > 0 {
			for library in fetched {
				fmt.eprintfln("%s %s", term.err("rocinante:", .Bold_Cyan), term.err(fmt.tprintf("fetched libs/%s from %s (commit %s)", library.name, library.url, short(library.commit)), .Cyan))
			}
			program, problem = folder.read_program(file)
			if problem != "" {
				fmt.sbprintf(err, "%s\n", problem)
				return nil, false
			}
		}
		if len(program.files) > 0 {
			return program.files, true
		}
	}
	data, read_err := os.read_entire_file(file, context.temp_allocator)
	if read_err != nil {
		fmt.sbprintf(err, "I cannot read `%s`. Check the name, or run %s in the folder that holds it.\n", file, command)
		return nil, false
	}
	single := make([]lang.File_Text, 1, context.temp_allocator)
	single[0] = lang.File_Text{name = file, text = string(data)}
	return single, true
}

is_sketch_file :: proc(file: string) -> bool {
	return file == "sketch.roci" || strings.has_suffix(file, "/sketch.roci")
}

// The sketch a name stands for: a file is itself, and a folder is the sketch.roci
// inside it (one folder is one program). Says what is missing when there is none.
sketch_file :: proc(name: string, err: ^strings.Builder) -> (file: string, ok: bool) {
	if !os.is_directory(name) {
		return name, true
	}
	file = strings.concatenate({strings.trim_right(name, "/"), "/sketch.roci"}, context.temp_allocator)
	if !os.exists(file) {
		fmt.sbprintf(err, "There is no sketch.roci in `%s`. A folder is run through its sketch.roci.\n", name)
		return "", false
	}
	return file, true
}

// What `roci run` tells you when the windows open.
HOT_RELOAD_HINT :: proc(file: string) -> string {
	reload_key := "Cmd+R" when ODIN_OS == .Darwin else "Ctrl+R"
	quit_key := "Cmd+Q" when ODIN_OS == .Darwin else "Ctrl+Q"
	return fmt.tprintf(
		"running %s. Save the source file (any file of the sketch) and the sketch reloads, keeping its values where it can. %s runs it again from the first line, and %s quits.\nIt also auto recovers from errors.",
		file,
		reload_key,
		quit_key,
	)
}

// Where a sketch's artifacts go: the `artifacts` folder of its folder (git leaves it out), for a lone file
// the one beside it.
artifacts_folder :: proc(file: string) -> string {
	return strings.concatenate({folder.root_of(file), "/artifacts"}, context.temp_allocator)
}

// What the run that ended last measured, said in words and added to `artifacts/log.json`.
report_stats :: proc(file, mode: string, vsync: bool, out, err: ^strings.Builder) {
	summary := roci.stats_last()
	fmt.sbprintf(out, "%s %s\n", term.out("speed:", .Bold_Cyan), roci.stats_text(summary))
	if summary.frames == 0 {
		return
	}
	name := folder.root_of(file)
	if name == "." || name == "" {
		name = "sketch"
	} else if slash := strings.last_index_byte(name, '/'); slash >= 0 {
		name = name[slash + 1:]
	}
	log := strings.concatenate({artifacts_folder(file), "/log.json"}, context.temp_allocator)
	if roci.stats_log(log, mode, name, summary, vsync) {
		fmt.sbprintf(out, "%s %s\n", term.out("log:", .Bold_Cyan), log)
	} else {
		fmt.sbprintf(err, "I could not write `%s`.\n", log)
	}
}
