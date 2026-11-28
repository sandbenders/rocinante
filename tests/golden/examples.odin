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
	{"tumble", 400, {1}}, // physics: stars and triangles, outlines the physics moves by their points, in a bowl that is a fixed outline
	{"car", 200, {1}}, // physics: a car resting on its wheel joints on the road
	{"pachinko", 200, {1}}, // physics: balls dropped among the pegs, at the places the physics has moved them to by then
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
	{"actions", 2, {1}}, // the ship waiting at the bottom with the three lines of how to steer, fire and boost it (the keys and pads come in the interpreter's test)
	{"memory", 2, {1}}, // the bar, the circle and the three numbers a first run starts with (what it keeps comes in the interpreter's test)
	{"data", 2, {1}}, // the birds, the bars and the poem read from the three files of assets/data (the saved summary comes in the interpreter's test)
	{"city", 2, {1}}, // six buildings, a skyline and the road, every wall and roof a polygon
	{"dialogs", 2, {1}}, // the picture from assets and the line about it (the dialogs are answered in the interpreter's test)
	{"websocket", 2, {1}}, // the invitation to click and the empty list (the messages come in the interpreter's test)
	{"tcp", 2, {1}}, // the invitation to click and the empty list (the connections and their lines come in the interpreter's test)
	{"udp", 2, {1}}, // the invitation to click and the empty list (the datagrams come in the interpreter's test)
	{"movie", 40, {1}}, // a movie of a Mandelbrot zoom two thirds of a second in, drawn as a picture, as the fill of a circle and of a bar, with its place in a bar below (a headless frame is a sixtieth of a second, so the picture is the same everywhere)
	{"webcam", 2, {1}}, // the dark picture a headless run has for the camera, in the mirror, a text filled with it and the invitation to click (the frames and the snapshots come in the interpreter's test)
	{"fetch", 2, {1}}, // the sketch waiting for its answers: a headless run fetches nothing (the answers are given in the interpreter's test)
	{"vault", 2, {1}}, // the level and the coins a first run starts with (what the vault keeps comes in the interpreter's test)
	{"screens", 2, {1}}, // the one 1920 by 1080 screen a headless run has, drawn at a tenth of its size, with the system's name (the screens a computer really has come in the interpreter's test)
	{"gamepad", 2, {1}}, // the invitation to plug a gamepad in (a headless run has none; the panels come in the interpreter's test)
	{"particles", 60, {1}}, // the fountain a second after it starts: 10,000 records
	{"logo", 3, {1}}, // rocinante's logo, drawn from its SVG's own numbers
	{"circle", 3, {1}}, // the smallest sketch: one line, one circle
	{"images", 5, {1}}, // pictures from assets: sizes, tints, alpha, a turning badge
	{"canvas", 60, {1}}, // a canvas that keeps its drawing: two dots with fading trails
	{"canvas_layers", 3, {1}}, // a canvas that shows one made after it, three deep, and one of over two thousand shapes
	{"canvas_text", 3, {1}}, // letters cut out of a canvas
	{"fills", 5, {1}}, // shapes filled with a picture: cover, fit, stretch, tile and center, and an outline over one
	{"outline", 3, {1}}, // the same ball against a picture as a rectangle and as its outline
	{"vector", 20, {1}}, // an SVG badge of paths, curves, arcs, a ring cut out by a hole, groups, a use and a style, drawn at its own size, stretched, turned and growing and shrinking
	{"export", 5, {1}}, // a ring of dots; s and r save pictures, which a golden run never presses
	{"blend", 3, {1}}, // seven blends over the same gray, and a bright wall clipped to a box
	{"project", 3, {1}}, // a ship and its colors read from a file of another folder with use
	{"paint", 3, {1}}, // a picture as the window, the letters of a text and the outlines of shapes
	{"pixels", 3, {1}}, // pixel, crop, resize and filter: a magnifier and six filtered thumbnails
	{"melt", 60, {1}}, // mask by a canvas drawn every frame, made on the graphics card: a landscape and stripes cut by a dripping front, and the front itself
	{"effects", 3, {1}}, // two shaders of its own over five stripes: a wave with a tint, and a vignette
	{"spiral", 20, {1}}, // shapes filled by one shader: a spiral of black and white bands with an accent arm, in a window-sized rectangle and two circles
	{"neon", 20, {1}}, // the built-in effects: glow, split, grain and vignette over bright rings
	{"smoke", 90, {1}}, // an effect on a canvas: embers whose trails are blurred on the canvas each frame, under a window vignette
	{"glass", 20, {1}}, // a corridor of glowing glass made by one shader as a fill, with motes of light added over it
	{"follow", 8, {1}}, // dots that drift with a slider following each one, and a placed panel with the switch that stops them
	{"imagebuttons", 6, {1}}, // two buttons that show a picture, and the badges they stamp
	{"dials", 6, {1}}, // a color box, a knob, a range with two handles and a pad, steering a line of circles
	{"ui", 6, {1}}, // a slider, a check box and a button in a ui block, drawn over a dot and its ring
	{"tunnel", 20, {1}}, // a raymarched tunnel made by one shader, and a lens effect on top
	{"bounce", 90, {1}}, // Processing's Bounce: a ball turning round at the edges, a shadow and a highlight on it
	{"metronome", 30, {1}}, // a second at the 30 frames a second it asks for: the pendulum part way through its swing, the dot and its ghosts a frame's step apart, and the two rates in words
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
	{"pedals", 30, {1}}, // the sixteen switches, overdrive and delay on, and the bars of the chord it starts with
	{"player", 10, {1}}, // the drift track at its start: its name, 0:00 of 3:03, the empty bar and the bars of what plays (headless nothing has played yet)
	{"soundfont", 40, {1}}, // the four notes of the chord it starts with, floating up from the piano
	{"midi", 5, {1}}, // the 61 keys waiting for a MIDI keyboard (the notes come in the interpreter's test)
	{"midiout", 5, {1}}, // the first ring of the arpeggio, the output chooser at the bottom and the notice that no output was found (a headless run has none)
	{"osc", 5, {1}}, // three dots waiting where the sketch put them to start, and the line that says nothing has come (the messages come in the interpreter's test)
	{"swarm", 40, {1}}, // the title screen: the name, the three kinds of enemy with their points, the blinking prompt and the stars falling behind
	{"recorder", 5, {1}}, // the level bar at rest, the unlit dot and the seconds of a take that has not begun
	{"keys", 10, {1}}, // the eight keys and the bands of the C major chord it starts with
	{"music", 60, {1}}, // the bars of a chiptune's pitches a second in, and a ring as big as it is loud
	{"sound", 30, {1}}, // rain as loud as the mouse is high (headless, the mouse is at the top left), and the bar of where it is
	{"wireframe", 30, {1}}, // a star-shaped gem the sketch calculates as triangles, flat shaded and as a wireframe of tubes with no diagonals, turning above a floor and casting their shadows
}

// Examples with a sketch.roci that have no picture to compare, and why.
NO_PICTURE := [?]string{
	"sengen", // its font, Helvetica Neue Condensed Black, comes with a Mac and is not on the pipelines, so the picture would differ
	"benchmark", // 100,000 small circles hardly compress, and an interpreter test checks its work
	"platform", // it draws the mark of the system it runs on, so its picture differs from one pipeline to the next (an interpreter test goes through every mark)
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
	roci.start_headless(1, true)
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
