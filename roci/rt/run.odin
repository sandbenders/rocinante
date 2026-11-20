// SPDX-License-Identifier: 0BSD
//
// How a compiled sketch runs: the words it takes on its command line (the same the interpreter's
// `roci run` takes where they mean the same: `--frames`, `--seed`, `--screenshot`, `--stats`,
// `--no-vsync`), the loop, and what a timed run says when it ends. `roci run --compile` starts the program
// with them.
package rt

import "core:fmt"
import "core:os"
import "core:strconv"
import "../"
import "../gfx"

// What a compiled program was asked to do.
Run :: struct {
	sketch:     string, // the name of its folder, for the log
	odin:       string, // the Odin release it was built with
	frames:     int,    // more than 0: no window, this many frames of a sixtieth of a second
	seed:       u64,
	stats:      bool,
	no_vsync:   bool,
	log:        string, // where a timed run adds its line
	mode:       string, // compiled, or compiled debug
	screenshot: string,
}

RUN_USAGE :: `This program was made by roci from a sketch. It takes:
  --frames N         run N frames with no window, then stop
  --seed N           the seed of the random numbers in a run with --frames (1 by default)
  --screenshot out.png   with --frames, save a picture of the last frame
  --stats            time the frames: show the frame and the frame rate in a box, and say how fast it was
  --no-vsync         with --stats and a window, do not wait for the display
  --log file.json    with --stats, add a line about the run to this file
  --mode text        what the log calls this program (compiled, or compiled debug)`

// Whether words the program does not know are left alone: a packaged app is started by the system, which may add its own.
lenient_args := false

// Reads the command line.
read_run :: proc(sketch, odin: string) -> Run {
	run := Run{sketch = sketch, odin = odin, seed = 1, mode = "compiled"}
	args := os.args[1:] if len(os.args) > 0 else nil // a phone starts the program with none
	for i := 0; i < len(args); i += 1 {
		arg := args[i]
		needs_value := arg == "--frames" || arg == "--seed" || arg == "--screenshot" || arg == "--log" || arg == "--mode"
		if needs_value && i + 1 >= len(args) {
			fmt.eprintfln("I need a value after `%s`.\n\n%s", arg, RUN_USAGE)
			os.exit(2)
		}
		switch arg {
		case "--frames":
			n, ok := strconv.parse_int(args[i + 1])
			if !ok || n < 1 {
				fmt.eprintfln("`--frames` takes a number of frames, 1 or more, not `%s`.\n\n%s", args[i + 1], RUN_USAGE)
				os.exit(2)
			}
			run.frames = n
			i += 1
		case "--seed":
			n, ok := strconv.parse_u64(args[i + 1])
			if !ok {
				fmt.eprintfln("`--seed` takes a number, not `%s`.\n\n%s", args[i + 1], RUN_USAGE)
				os.exit(2)
			}
			run.seed = n
			i += 1
		case "--screenshot":
			run.screenshot = args[i + 1]
			i += 1
		case "--log":
			run.log = args[i + 1]
			i += 1
		case "--mode":
			run.mode = args[i + 1]
			i += 1
		case "--stats":
			run.stats = true
		case "--no-vsync":
			run.no_vsync = true
		case:
			if lenient_args {
				continue
			}
			fmt.eprintfln("I don't know `%s`.\n\n%s", arg, RUN_USAGE)
			os.exit(2)
		}
	}
	if run.screenshot != "" && run.frames == 0 {
		fmt.eprintfln("`--screenshot` needs `--frames`.\n\n%s", RUN_USAGE)
		os.exit(2)
	}
	if run.no_vsync && (!run.stats || run.frames > 0) {
		fmt.eprintfln("`--no-vsync` goes with `--stats` and a window.\n\n%s", RUN_USAGE)
		os.exit(2)
	}
	return run
}

// Runs the program: `setup` is the sketch's own first lines (it opens the windows and registers what runs
// every frame), then the frames, then the report. Never returns.
execute :: proc(run: Run, setup: proc(), roots: proc(), hook: proc(w: roci.Window) = nil) {
	if run.frames > 0 {
		roci.start_headless(run.seed, run.screenshot != "")
	}
	if run.stats {
		roci.stats_start(run.frames == 0, run.no_vsync)
	}
	// what `remember` keeps goes in the sketch's folder, which is where the program runs (a headless run reads and never writes)
	roci.keep_beside(HOME, run.frames == 0)
	collector_roots = roots
	roci.set_end_hook(end_of_frame)
	if hook != nil {
		roci.set_frame_hook(hook)
	}
	setup()
	scene_start()
	code := 0
	if run.frames > 0 {
		for _ in 0 ..< run.frames {
			roci.step()
		}
		if run.screenshot != "" {
			code = save_picture(run.screenshot)
		}
		roci.shutdown()
	} else if !roci.run() {
		fmt.eprintfln("I could not open a window on this computer.")
		code = 3
	}
	if run.stats {
		report(run)
	}
	os.exit(code)
}

@(thread_local) @(private) collector_roots: proc()

// Run as every frame ends, when no verb is running: the moment the collector may free what nothing holds.
@(private)
end_of_frame :: proc() {
	step_fetches()
	step_asks()
	scene_apply()
	say_record_results()
	if collector_roots != nil {
		maybe_collect(all_roots)
	}
}

// What the collector starts from: the names of the sketch, and the records tweens are moving.
@(private)
all_roots :: proc() {
	collector_roots()
	mark_tweens()
	mark_data()
}

// The picture of the first window, as a PNG file. 0 when it was made, 3 when it was not.
@(private)
save_picture :: proc(path: string) -> int {
	windows := roci.open_windows()
	if len(windows) == 0 {
		fmt.eprintfln("The sketch has no window to take a picture of.")
		return 3
	}
	image, drawn := roci.picture(windows[0])
	if !drawn {
		fmt.eprintfln("The picture could not be drawn: %s.", roci.last_error())
		return 3
	}
	defer delete(image.pixels)
	png, encoded := gfx.png_encode(image)
	if !encoded {
		fmt.eprintfln("The picture could not be saved.")
		return 3
	}
	defer delete(png)
	if os.write_entire_file(path, png) != nil {
		fmt.eprintfln("I cannot write `%s`.", path)
		return 3
	}
	return 0
}

// What a timed run measured, said and added to the log.
@(private)
report :: proc(run: Run) {
	summary := roci.stats_last()
	fmt.printfln("speed: %s", roci.stats_text(summary))
	if gc := gc_stats(); gc.collections > 0 || gc.objects > 0 {
		fmt.printfln("memory: %d objects, %.1f MB held, %d collections that freed %.1f MB", gc.objects, f64(gc.live) / 1048576, gc.collections, f64(gc.freed) / 1048576)
	}
	if summary.frames == 0 || run.log == "" {
		return
	}
	if roci.stats_log(run.log, run.mode, run.sketch, summary, !run.no_vsync && run.frames == 0) {
		fmt.printfln("log: %s", run.log)
	} else {
		fmt.eprintfln("I could not write `%s`.", run.log)
	}
}
