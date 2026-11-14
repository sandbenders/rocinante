// SPDX-License-Identifier: 0BSD
//
// The examples written in the language, run for a fixed number of frames with a
// fixed seed and time step, and their windows compared with reference pictures
// like the scenes are. A window whose reference is missing is said so and does not
// fail the run, so a new example can be added before its picture exists; `update`
// writes it (on the computer that makes the references, where lavapipe is).
package golden

import "core:fmt"
import "core:os"
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

// The pictures of lit 3D scenes and examples. Their light is worked out per pixel with powers and divisions
// that two versions of lavapipe's compiler round differently, so a few pixels, mostly on the edge of
// a highlight, differ by more than the flat pictures ever do: the first pipeline run on another
// computer than the one that drew the references found one pixel 17 off where the Mac had none.
// They get a larger worst channel and allowance than `STRICT`, which a shifted or wrongly lit
// picture still fails.
SHADED :: Limits{tolerance = 12, allowed = 60, worst = 40}
// The ship of `example_model` is lit through a texture and a normal map over a large area, so
// Ubuntu's lavapipe differs from the Mac's on a few hundred pixels by small steps (390 pixels over 12,
// worst channel 40, found by the first run on GitHub). A shifted or wrongly lit ship still fails.
SHADED_MODEL :: Limits{tolerance = 12, allowed = 160, worst = 48}
SHADED_PICTURES := [?]string{"example_solids_1", "example_shapes3d_1", "example_stage_1", "example_lights_1", "example_shadows_1", "example_model_1", "example_turtle3d_1", "example_collide3d_1", "example_voyage_1", "example_textured_1", "example_wireframe_1", "example_lamp_1", "model_pictures", "model_colours"}

// `benchmark` has no picture: 100,000 small circles hardly compress (737 KB), and an
// interpreter test checks the work it does exactly, which is what it promises.
EXAMPLES := [?]Example{
	{"two_windows", 30, {1, 2}},
	{"garden", 30, {1, 2}},
	{"starfield", 5, {1}}, // two files: sketch.roci and palette.roci
	{"constellation", 5, {1}}, // a library: libs/stars
	{"tree", 5, {1}}, // the turtle
	{"compass", 5, {1}}, // the turtle read as a value (turtle.pos, turtle.angle) and drawn with show turtle
	{"checks", 3, {1}}, // verbs with checks beside them (shapes.roci), drawn as a flower of rings
	{"text", 1, {1}}, // real text in two weights, aligned, wrapped and measured
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
	{"circle", 3, {1}}, // the smallest sketch: one line, one circle
	{"images", 5, {1}}, // pictures from assets: sizes, tints, alpha, a turning badge
	{"canvas", 60, {1}}, // a canvas that keeps its drawing: two dots with fading trails
	{"fills", 5, {1}}, // shapes filled with a picture: cover, fit, stretch, tile and center, and an outline over one
	{"outline", 3, {1}}, // the same ball against a picture as a rectangle and as its outline
	{"vector", 20, {1}}, // an SVG badge of paths, curves, arcs, a ring cut out by a hole, groups, a use and a style, drawn at its own size, stretched, turned and growing and shrinking
	{"export", 5, {1}}, // a ring of dots; s and r save pictures, which a golden run never presses
	{"blend", 3, {1}}, // seven blends over the same gray, and a bright wall clipped to a box
	{"paint", 3, {1}}, // a picture as the window, the letters of a text and the outlines of shapes
	{"pixels", 3, {1}}, // pixel, crop, resize and filter: a magnifier and six filtered thumbnails
	{"effects", 3, {1}}, // two shaders of its own over five stripes: a wave with a tint, and a vignette
	{"spiral", 20, {1}}, // shapes filled by one shader: a spiral of black and white bands with an accent arm, in a window-sized rectangle and two circles
	{"neon", 20, {1}}, // the built-in effects: glow, split, grain and vignette over bright rings
	{"smoke", 90, {1}}, // an effect on a canvas: embers whose trails are blurred on the canvas each frame, under a window vignette
	{"glass", 20, {1}}, // a corridor of glowing glass made by one shader as a fill, with motes of light added over it
	{"follow", 8, {1}}, // dots that drift with a slider following each one, and a placed panel with the switch that stops them
	{"imagebuttons", 6, {1}}, // two buttons that show a picture, and the badges they stamp
	{"dials", 6, {1}}, // a color box, a knob, a range with two handles and a pad, steering a line of circles
	{"ui", 6, {1}}, // a slider, a check box and a button in a ui block, drawn over a dot and its ring
	{"tunnel", 20, {1}}, // a raymarched tunnel made by one shader, the sketch's own dots and word laid over it, and a lens effect on top
	{"bounce", 90, {1}}, // Processing's Bounce: a ball turning round at the edges, a shadow and a highlight on it
	{"sinewave", 20, {1}}, // Processing's Sine Wave: a row of dots on a sliding sine, bigger and brighter at the crests
	{"rope", 150, {1}}, // Processing's Follow: a rope of segments that leads itself round the window once the mouse has been still a second
	{"life", 120, {1}}, // Processing's Game of Life: a random grid thirty generations on, wrapping at its edges
	{"flocking", 100, {1}}, // Processing's Flocking: sixty birds with separation, alignment and cohesion, a hundred frames in
	{"koch", 3, {1}}, // Processing's Koch snowflake, drawn by a verb that calls itself with the turtle
	{"mandelbrot", 3, {1}}, // Processing's Mandelbrot: a picture made once from a list of colors and drawn big
	{"noisewave", 60, {1}}, // Processing's Noise Wave: three layers of noise bars and a row of dots, sliding
	{"recursion", 3, {1}}, // Processing's Recursion: circles that draw four smaller circles on their sides
	{"colorwheel", 20, {1}}, // Processing's Hue: wedges filled by hue round the wheel and by saturation in towards the middle
	{"studio", 60, {1, 2}}, // two windows: a control surface with every widget, and a stage of circling dots they steer, with trails on a canvas
	{"solids", 60, {1}}, // the first 3D sketch: a floor, a sphere and a ring of turning boxes, lit and hiding each other, with a line of flat text over them
	{"shapes3d", 60, {1}}, // every solid on a grid with the axes: a cone, a cylinder, a capsule, a torus, an icosphere and a box, turning, and an arrow under them
	{"stage", 60, {1}}, // three boxes on a grid seen by a camera that circles them, their names written over them at their screen points, and a gold ball on the floor under the mouse
	{"lights", 10, {1}}, // lights of its own: ambient, sun, a warm point light and a blue spot light on a floor and four spheres of different materials
	{"shadows", 30, {1}}, // a low sun throwing the shadows of six boxes, a sphere and a turning torus across a floor and onto each other
	{"model", 30, {1}}, // a glTF ship (a box and a cone, a material each, placed by nodes) turning above a floor, lit and casting its shadow
	{"turtle3d", 30, {1}}, // a tree grown by the turtle in space, forking in threes by rolling and tipping up, lit and casting its shadow
	{"collide3d", 40, {1}}, // balls bouncing off pillars in a room by `hits` and `contact`, gold for a moment after each touch, and a laser swept across it that `cast` stops at the first pillar it meets
	{"voyage", 30, {1}}, // a generated city of towers and lanterns lit by a sun, a point light that follows an OBJ ship flying over it, and every shadow
	{"textured", 30, {1}}, // a board of colored squares made by the sketch, painted over a box, a sphere, a cone, a cylinder, a capsule, a torus, an icosphere and a plane by `fill`
	{"lamp", 30, {1}}, // a warm point light circling among six pillars, a sphere and a turning torus, every shadow swinging away from it
	{"wireframe", 30, {1}}, // a star-shaped gem the sketch calculates as triangles, flat shaded and as a wireframe of tubes with no diagonals, turning above a floor and casting their shadows
}

// Examples with a sketch.roci that have no picture to compare, and why.
NO_PICTURE := [?]string{
	"sengen", // its font, Helvetica Neue Condensed Black, comes with a Mac and is not on the pipelines, so the picture would differ
	"benchmark", // 100,000 small circles hardly compress, and an interpreter test checks its work
}

run_examples :: proc(update: bool, only: []string) -> (ran, failures: int) {
	// An example with a sketch has to be in the list (or say why not), so a new one is never left out.
	if entries, err := os.read_all_directory_by_path("examples", context.temp_allocator); err == nil {
		for entry in entries {
			if !os.exists(fmt.tprintf("examples/%s/sketch.roci", entry.name)) || slice.contains(NO_PICTURE[:], entry.name) {
				continue
			}
			listed := false
			for example in EXAMPLES {
				listed ||= example.name == entry.name
			}
			if !listed {
				report(fmt.tprintf("example_%s", entry.name), false, "examples/ has a sketch that is not in EXAMPLES (tests/golden/examples.odin): add it, or add it to NO_PICTURE with a reason")
				failures += 1
			}
		}
	}
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
	// An example runs in its own folder, where an installed font it names would be copied into its
	// assets, which git tracks: the computer's fonts are not looked at.
	folder.system_font_dirs = {"output/golden/no_system_fonts"}
	defer folder.system_font_dirs = nil
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
	// A lit 3D picture is judged by limits of its own on lavapipe (see `SHADED`).
	saved := limits
	defer limits = saved
	if limits == STRICT && slice.contains(SHADED_PICTURES[:], name) {
		limits = SHADED
		if name == "example_model_1" {
			limits = SHADED_MODEL
		}
	}
	diff := gfx.image_diff(picture, reference, limits.tolerance)
	switch {
	case !diff.same_size:
		report(name, false, fmt.tprintf("picture is %d x %d, reference %d x %d", picture.width, picture.height, reference.width, reference.height))
		return false
	}
	if same, why := judge(diff, picture.width * picture.height); !same {
		report(name, false, fmt.tprintf("%s; look at %s", why, actual_path(name)))
		return false
	}
	report(name, true, fmt.tprintf("%d pixels off, worst channel %d", diff.differing_pixels, diff.worst_channel))
	return true
}
