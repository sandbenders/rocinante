// SPDX-License-Identifier: 0BSD
//
// Draws every shape of the shapes pipeline through packages platform and gfx, by
// hand, until the verb API (package roci) exists. A circle follows the mouse.
//
//     odin run examples/shapes            runs until the window is closed
//     odin run examples/shapes -- 3       runs for 3 seconds, for scripts
//
// Windows (the operating system) needs SDL3.dll beside the program.
package shapes_example

import "core:fmt"
import "core:os"
import "core:strconv"
import sdl "vendor:sdl3"

import "../../roci/gfx"
import "../../roci/maths"
import "../../roci/platform"

main :: proc() {
	if !run() {
		os.exit(1)
	}
}

run :: proc() -> bool {
	seconds := 0
	if len(os.args) > 1 {
		seconds, _ = strconv.parse_int(os.args[1])
	}

	app: platform.App
	if !platform.init(&app) {
		fmt.eprintfln("shapes: %s", app.error)
		return false
	}
	defer platform.shutdown(&app)
	window, ok := platform.create_window(&app, {title = "rocinante shapes", resizable = true})
	if !ok {
		fmt.eprintfln("shapes: %s", app.error)
		return false
	}

	renderer: gfx.Renderer
	gfx.renderer_init(&renderer, app.device)
	defer gfx.renderer_destroy(&renderer)
	list: gfx.Command_List
	defer gfx.destroy(&list)
	batcher: gfx.Batcher
	defer gfx.batcher_destroy(&batcher)

	mouse := [2]f32{400, 300}
	start := sdl.GetTicks()
	frames := 0
	events: [dynamic]platform.Event
	defer delete(events)
	for running := true; running && len(app.windows) > 0; {
		clear(&events)
		platform.poll_events(&events)
		for event in events {
			#partial switch e in event {
			case platform.Quit:
				running = false
			case platform.Close_Requested:
				platform.destroy_window(&app, platform.find_window(&app, e.window))
			case platform.Mouse_Moved:
				mouse = {e.x, e.y}
			}
		}
		if seconds > 0 && sdl.GetTicks() - start > u64(seconds) * 1000 {
			running = false
		}
		if len(app.windows) == 0 {
			break
		}

		time := f32(sdl.GetTicks() - start) / 1000
		draw(&list, time, mouse)
		gfx.build(&batcher, &list)
		m := platform.window_metrics(window)
		if !gfx.render_window(&renderer, window.handle, {f32(m.width), f32(m.height)}, &list, &batcher) {
			fmt.eprintfln("shapes: %s", renderer.error)
			return false
		}
		frames += 1
	}
	fmt.printfln("shapes: ok, %d frames, %d draws, %d instances", frames, batcher.stats.draws, batcher.stats.instances)
	return true
}

draw :: proc(list: ^gfx.Command_List, time: f32, mouse: [2]f32) {
	gfx.begin_frame(list)
	gfx.background(list, maths.grey(235))

	// Filled shapes, no outline.
	gfx.set_fill(list, named("tomato"))
	gfx.circle(list, 120, 120, 60)
	gfx.set_fill(list, named("teal"))
	gfx.ellipse(list, 300, 120, 140, 70)
	gfx.set_fill(list, named("goldenrod"))
	gfx.rect(list, 420, 60, 120, 120)
	gfx.set_fill(list, named("slateblue"))
	gfx.triangle(list, 600, 180, 660, 60, 720, 180)

	// Outlines of several thicknesses.
	gfx.no_fill(list)
	gfx.set_stroke(list, maths.grey(30))
	for i in 0 ..< 5 {
		gfx.set_thickness(list, f32(i) * 2 + 1)
		gfx.circle(list, 80 + f32(i) * 130, 300, 50)
	}

	// Fill and outline together, half transparent.
	gfx.set_fill(list, named("orange"))
	gfx.set_stroke(list, named("navy"))
	gfx.set_thickness(list, 6)
	gfx.set_alpha(list, 170)
	gfx.rect(list, 80, 400, 160, 100)
	gfx.ellipse(list, 340, 450, 160, 100)
	gfx.triangle(list, 480, 500, 560, 400, 640, 500)

	// Lines and points, and a turning square with the transform.
	gfx.set_alpha(list, 255)
	gfx.set_stroke(list, named("crimson"))
	gfx.set_thickness(list, 3)
	for i in 0 ..< 10 {
		gfx.line(list, 30, 540 + f32(i) * 4, 770, 540 + f32(i) * 4 + f32(i) * 2)
	}
	gfx.set_thickness(list, 10)
	gfx.point(list, 760, 300)
	gfx.push(list, .Style_And_Transform)
	gfx.move(list, 700, 400)
	gfx.turn(list, f64(time) * 60)
	gfx.set_fill(list, named("seagreen"))
	gfx.set_stroke(list, maths.grey(0))
	gfx.set_thickness(list, 2)
	gfx.rect(list, 0, 0, 80, 80, .Center)
	gfx.pop(list)

	// Follows the mouse.
	gfx.set_fill(list, maths.rgb(0, 0, 0, 90))
	gfx.no_stroke(list)
	gfx.circle(list, mouse.x, mouse.y, 24)
}

named :: proc(name: string) -> maths.Colour {
	colour, _ := maths.name_lookup(name)
	return colour
}
