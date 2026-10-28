// SPDX-License-Identifier: 0BSD
//
// Two windows that talk: a small control window and a
// canvas. Every frame the control window sends the mouse position over it to the
// canvas, which draws a circle there; clicking in the control window sends the
// word "flash", which makes the canvas background light up for a moment.
//
//     odin run examples/two_windows
package two_windows_example

import "core:os"
import "core:strconv"
import "../../roci"

// What the canvas has heard, kept where its two procedures can both see it.
Heard :: struct {
	at:    [2]f64,
	flash: f64, // seconds of flash left
}
heard: Heard

control, canvas: roci.Window

main :: proc() {
	control = roci.window(300, 200, [2]int{60, 120})
	roci.title("control")
	canvas = roci.window(520, 420, [2]int{400, 80})
	roci.title("canvas")

	roci.draw(control, draw_control)
	roci.draw(canvas, draw_canvas)
	roci.on_receive(canvas, hear)
	// `odin run examples/two_windows -- 3` shows them for 3 seconds, for scripts.
	seconds := 0
	if len(os.args) > 1 {
		seconds, _ = strconv.parse_int(os.args[1])
	}
	roci.run(frames = seconds * 60)
}

draw_control :: proc() {
	roci.background_grey(40)
	roci.fill(roci.grey(230))
	roci.debug_text("move the mouse here,\nclick to flash the canvas", 10, 10, 1)
	// Send the pointer's place, scaled to the canvas, and a flash on a click.
	where_it_is := roci.mouse()
	roci.send(canvas, [2]f64{where_it_is.x / roci.width() * 520, where_it_is.y / roci.height() * 420})
	if roci.mouse_down() {
		roci.send(canvas, "flash")
	}
	roci.circle(where_it_is, 6, roci.Look{fill = roci.named("orange")})
}

hear :: proc(message: roci.Value) {
	#partial switch value in message {
	case [2]f64:
		heard.at = value
	case string:
		if value == "flash" {
			heard.flash = 0.3
		}
	}
}

draw_canvas :: proc() {
	heard.flash = max(heard.flash - 1.0 / 60, 0)
	roci.background_grey(245 if heard.flash > 0 else 30)
	roci.fill(roci.named("tomato"))
	roci.circle(heard.at, 24)
	roci.fill(roci.grey(120))
	roci.debug_text("canvas", 10, 10, 2)
}
