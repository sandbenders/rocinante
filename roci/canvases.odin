// SPDX-License-Identifier: 0BSD
//
// Canvases: `canvas 300 200` makes a picture that can be drawn into, and `draw into c [ ... ]`
// runs a block whose verbs draw onto it instead of the window. A canvas is a picture like
// a loaded one (`image c at 0 0` shows it, `c.width` reads its size) that keeps what is
// drawn on it from frame to frame. The drawing happens at the end of the frame, before the
// windows (roci/gfx/canvas.odin); a headless sketch keeps the rounds until a picture of a
// window is asked for.
package roci

import "gfx"
import "platform"

// How many device pixels a canvas of a headless sketch has for each logical pixel: what the
// golden pictures and the documentation's pictures are drawn at.
HEADLESS_CANVAS_DENSITY :: f32(2)

// A new canvas of this logical size, as sharp as the window it is made in: the window's
// density, or 2 when there is no real window. Gives false for a size that is zero or too big.
canvas :: proc(width, height: f64) -> (Image, bool) {
	density := HEADLESS_CANVAS_DENSITY
	if w := current_win(); w.handle != nil {
		density = platform.window_metrics(w.handle).density
	}
	made, ok := gfx.image_add_canvas(int(width), int(height), density)
	if ok {
		append(&the.canvases, made)
	}
	return made, ok
}

// Starts drawing into a canvas: until `end_into`, every drawing verb records onto it, from the
// default style. Gives false, and changes nothing, when the picture is not a canvas or one is
// being drawn into already (a canvas cannot be drawn into from inside itself or another).
begin_into :: proc(picture: Image) -> bool {
	canvas := gfx.canvas_of(picture)
	if canvas == nil || the.into != 0 {
		return false
	}
	the.into = picture
	gfx.canvas_begin(canvas)
	return true
}

// Goes back to drawing into the window.
end_into :: proc() {
	canvas := gfx.canvas_of(the.into)
	if canvas != nil && (len(canvas.list.commands) > 0 || canvas.list.background_set) {
		gfx.canvas_touch(canvas)
	}
	the.into = 0
}

// Runs `block` with every drawing verb drawing onto the canvas. Gives false when the picture
// is not a canvas (or one is being drawn into already) and the block was not run.
draw_into :: proc(picture: Image, block: proc()) -> bool {
	if !begin_into(picture) {
		return false
	}
	block()
	end_into()
	return true
}

// Whether a canvas is being drawn into now.
is_drawing_into :: proc() -> bool {
	return the.into != 0
}

// The size of what the verbs draw on now, in logical pixels: the canvas being drawn into, or
// else the current window.
surface_size :: proc() -> [2]f64 {
	if the.into != 0 {
		return image_size(the.into)
	}
	win := current_win()
	return {f64(win.width), f64(win.height)}
}

// The command list verbs record into: the canvas's while one is being drawn into.
@(private)
into_list :: proc() -> ^gfx.Command_List {
	if canvas := gfx.canvas_of(the.into); canvas != nil {
		return &canvas.list
	}
	return nil
}

// Draws what is waiting in every canvas onto its texture, oldest round first, before the
// windows are drawn. With no graphics (a headless sketch) the rounds are only closed, and
// wait for `force`, which `picture` gives once it has a device to draw with.
flush_canvases :: proc(renderer: ^gfx.Renderer = nil) {
	for id in the.canvases {
		canvas := gfx.canvas_of(id)
		if canvas == nil {
			continue
		}
		if renderer != nil && !renderer.failed {
			gfx.render_canvas(renderer, id)
		} else {
			gfx.canvas_close_round(canvas)
		}
	}
}
