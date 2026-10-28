// SPDX-License-Identifier: 0BSD
//
// `roci run`: read a sketch, check it, and run it. With `--frames N` it runs
// headless, N frames with a fixed time step, and can save a picture of the last
// one: that is how scripts and tests run a sketch. Without it the windows open and
// the sketch runs until it is closed.
package main

import "../roci"
import "../roci/gfx"
import "../roci/interp"
import "../roci/lang"
import "../tools/term"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

RUN_USAGE :: `roci run [file] [--frames N] [--screenshot out.png] [--window N] [--seed N] [--errors json]

  file        the sketch to run; sketch.roci when left out
  --frames N  run N frames with no window, then stop
  --screenshot out.png
              with --frames, save a picture of the last frame
  --window N  which window the picture is of, counting from 1 (the first by default)
  --seed N    the seed of the random numbers when the sketch gives none (1 by default)
  --errors json
              print every message as one line of JSON on standard output (and what the
              sketch prints on standard error), for tools`

Run_Args :: struct {
	file:       string,
	frames:     int,
	screenshot: string,
	json:       bool, // messages as lines of JSON
	window:     int, // which window the picture is of, counting from 1
	seed:       u64,
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
			}
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
) -> Run_Result {
	roci.start_headless(seed)
	defer roci.shutdown()
	p, ok := interp.load(name, text)
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
	for _ in 0 ..< frames {
		roci.step()
	}
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
	data, read_err := os.read_entire_file(file, context.temp_allocator)
	if read_err != nil {
		fmt.sbprintf(
			err,
			"I cannot read `%s`. Check the name, or run roci run in the folder that holds it.\n",
			file,
		)
		return 2
	}
	if parsed.frames == 0 {
		return run_windows(file, string(data), parsed.json, out, err)
	}
	result := run_text(
		file,
		string(data),
		parsed.frames,
		parsed.seed,
		parsed.screenshot != "",
		parsed.window,
	)
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
run_windows :: proc(name, text: string, json: bool, out, err: ^strings.Builder) -> int {
	p, ok := interp.load(name, text)
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
	if !json {
		fmt.eprintfln(
			"%s %s",
			term.err("rocinante:", .Bold_Cyan),
			term.err(HOT_RELOAD_HINT(name), .Cyan),
		)
	}
	interp.watch(p, name)
	interp.start(p)
	defer interp.shutdown()
	if !roci.run() {
		fmt.sbprintf(err, "I could not open a window on this computer.\n")
		return 3
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
		"running %s. Save the source file and the sketch reloads, keeping its values where it can. %s runs it again from the first line, and %s quits.\nIt also auto recovers from errors.",
		file,
		reload_key,
		quit_key,
	)
}
