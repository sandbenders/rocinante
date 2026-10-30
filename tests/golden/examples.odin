// SPDX-License-Identifier: 0BSD
//
// The examples written in the language, run for a fixed number of frames with a
// fixed seed and time step, and their windows compared with reference pictures
// like the scenes are. A window whose reference is missing is said so and does not
// fail the run, so a new example can be added before its picture exists; `update`
// writes it (on the computer that makes the references, where lavapipe is).
package golden

import "core:fmt"
import "core:slice"

import "../../roci"
import "../../roci/folder"
import "../../roci/gfx"
import "../../roci/interp"

Example :: struct {
	name:    string,
	frames:  int,
	windows: []int, // which windows to take a picture of, counting from 1
}

// `benchmark` has no picture: 100,000 small circles hardly compress (737 KB), and an
// interpreter test checks the work it does exactly, which is what it promises.
EXAMPLES := [?]Example{
	{"two_windows", 30, {1, 2}},
	{"garden", 30, {1, 2}},
	{"starfield", 5, {1}}, // two files: sketch.roci and palette.roci
	{"constellation", 5, {1}}, // a library: libs/stars
	{"tree", 5, {1}}, // the turtle
	{"bricks", 120, {1}}, // collision: a brick broken by then
	{"mouse", 5, {1}}, // the canvas before any input: the starting dots and the grid
	{"ease", 200, {1}}, // ease and tween: a dot past its end, the ball on its way
	{"rays", 30, {1}}, // cast and inside on a list of every kind of shape
	{"sorting", 200, {1}}, // list verbs: the bars after the first shuffle has settled
	{"tally", 5, {1}}, // tables: the tiles and a bar for each colour name
	{"style", 40, {1}}, // mixing, stops, joins, caps, named styles, with, as center, oklch, shear
	{"landscape", 100, {1}}, // fbm hills, gaussian stars, simplex clouds, a shooting star
	{"windows", 5, {1, 2}}, // the map of both windows and the lamps of their settings
	{"shapes", 30, {1}}, // every basic shape, as the Odin example draws them
	{"touch", 5, {1}}, // the two rings it starts with; fingers come from a touch screen or the mouse
	{"particles", 60, {1}}, // the fountain a second after it starts: 10,000 records
	{"logo", 3, {1}}, // rocinante's logo, drawn from its SVG's own numbers
}

// How many pixels may differ for a picture of this many: the scenes allow
// ALLOWED_PIXELS in 120,000.
allowed_pixels :: proc(img: gfx.Image) -> int {
	return max(ALLOWED_PIXELS, ALLOWED_PIXELS * img.width * img.height / 120000)
}

run_examples :: proc(update: bool, only: []string) -> (ran, failures: int) {
	for example in EXAMPLES {
		for number in example.windows {
			name := fmt.tprintf("example_%s_%d", example.name, number)
			if len(only) > 0 && !slice.contains(only, name) {
				continue
			}
			ran += 1
			if !run_example(example, number, name, update) {
				failures += 1
			}
		}
	}
	return
}

@(private = "file")
run_example :: proc(example: Example, number: int, name: string, update: bool) -> bool {
	program, problem := folder.read_program(fmt.tprintf("examples/%s/sketch.roci", example.name))
	if problem != "" || len(program.files) == 0 {
		report(name, false, "cannot read the sketch")
		return false
	}
	roci.start_headless(1)
	defer roci.shutdown()
	p, ok := interp.load_files(program.files)
	defer interp.destroy(p)
	if !ok {
		report(name, false, "the sketch has errors")
		return false
	}
	interp.start(p)
	for _ in 0 ..< example.frames {
		roci.step()
	}
	if len(p.errors) > 0 {
		report(name, false, fmt.tprintf("the sketch hit a runtime error:\n%s", interp.report(p, context.temp_allocator)))
		return false
	}
	windows := roci.open_windows()
	if number > len(windows) {
		report(name, false, fmt.tprintf("the sketch has no window %d", number))
		return false
	}
	picture, drawn := roci.picture(windows[number - 1])
	if !drawn {
		report(name, false, fmt.tprintf("could not draw: %s", roci.last_error()))
		return false
	}
	defer gfx.image_destroy(&picture)
	write_png(actual_path(name), picture)
	if update {
		if write_png(reference_path(name), picture) {
			report(name, true, "reference written")
			return true
		}
		report(name, false, "cannot write the reference")
		return false
	}
	reference, found := load_reference(reference_path(name))
	if !found {
		report(name, true, fmt.tprintf("no reference picture yet; look at %s, then run with: -- update", actual_path(name)))
		return true
	}
	defer gfx.image_destroy(&reference)
	diff := gfx.image_diff(picture, reference, TOLERANCE)
	switch {
	case !diff.same_size:
		report(name, false, fmt.tprintf("picture is %d x %d, reference %d x %d", picture.width, picture.height, reference.width, reference.height))
		return false
	case diff.differing_pixels > allowed_pixels(picture):
		report(name, false, fmt.tprintf("%d pixels differ by more than %d (worst channel %d); look at %s", diff.differing_pixels, TOLERANCE, diff.worst_channel, actual_path(name)))
		return false
	}
	report(name, true, fmt.tprintf("%d pixels off, worst channel %d", diff.differing_pixels, diff.worst_channel))
	return true
}
