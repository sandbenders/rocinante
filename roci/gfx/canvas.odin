// SPDX-License-Identifier: 0BSD
//
// Canvases: a picture whose pixels are drawn, not loaded. `draw into c [ ... ]` records
// commands into the canvas's own list; at the end of the frame (before the windows are
// drawn, so a window can show what was just drawn) the renderer draws them onto the
// canvas's texture. A canvas keeps what is on it from frame to frame, so drawing adds to
// it: trails, painting and accumulation work, and `clear` or `background` start it over.
//
// The drawing is multisampled, and a multisampled pass cannot add to a texture it is
// resolving into, so a canvas has two textures: the pass draws the canvas as it was (the
// one the windows show) as a first picture, then the new commands over it, and resolves
// into the other texture, which then becomes the one that is shown. A pass that starts
// with `background` or `clear` leaves the old picture out.
//
// A headless sketch has no graphics to draw with, so the rounds of commands wait in the
// canvas until a picture of a window is asked for (`roci.picture`), which draws them in
// order first.
package gfx

import "core:math"

// One frame's drawing into a canvas, waiting to be drawn onto its texture.
Canvas_Round :: struct {
	list: Command_List,
}

Canvas :: struct {
	list:    Command_List,   // what is being recorded now
	batcher: Batcher,
	rounds:  [dynamic]Canvas_Round, // finished frames not yet drawn, oldest first
	density: f32,            // device pixels for each logical pixel
	pending: bool,           // something was recorded into `list` since the last round was closed
	drawn:   u64,            // how many rounds have been closed: it changes when what the canvas shows will
}

// The side of a canvas texture that has `logical` logical pixels at `density`.
canvas_pixels :: proc(logical: int, density: f32) -> u32 {
	return u32(max(1, int(math.ceil(f32(logical) * max(density, 0.01)))))
}

// Makes a canvas of this logical size, drawn at `density` device pixels for each logical one.
// False for a size that is zero or too big.
image_add_canvas :: proc(width, height: int, density: f32) -> (Image_Id, bool) {
	if width <= 0 || height <= 0 || width > MAX_IMAGE_SIDE || height > MAX_IMAGE_SIDE || density <= 0 || density > 8 {
		return 0, false
	}
	canvas := new(Canvas)
	canvas.density = density
	canvas.list.background = {0, 0, 0, 0}
	canvas.list.style = DEFAULT_STYLE
	canvas.list.transform = IDENTITY
	id, kept := image_put(Image_Data{width = width, height = height, canvas = canvas})
	if !kept {
		canvas_destroy(canvas)
	}
	return id, kept
}

// The canvas a picture number is, or nil for a loaded picture or a number that is not one.
canvas_of :: proc(id: Image_Id) -> ^Canvas {
	if data := image_data(id); data != nil {
		return data.canvas
	}
	return nil
}

// Starts drawing into a canvas: the style, the transform and the turtle are the defaults
// again, as at the start of a frame, and what was drawn stays.
canvas_begin :: proc(c: ^Canvas) {
	c.list.style = DEFAULT_STYLE
	c.list.transform = IDENTITY
	c.list.look_changed = true
	c.list.span = {}
	c.list.turtle = {}
}

// Says something was recorded; the round is closed and drawn at the end of the frame.
canvas_touch :: proc(c: ^Canvas) {
	c.pending = true
}

// Closes the round being recorded: what was drawn into the canvas this frame waits to be
// drawn onto its texture. A round that starts with `background` or `clear` makes every
// round before it that has not been drawn yet useless, so those are let go (a headless
// sketch that clears its canvas every frame never piles rounds up).
canvas_close_round :: proc(c: ^Canvas) {
	if !c.pending {
		return
	}
	if c.list.background_set {
		for &round in c.rounds {
			destroy(&round.list)
		}
		clear(&c.rounds)
	}
	round := Canvas_Round{list = c.list}
	append(&c.rounds, round)
	c.drawn += 1
	// the list goes on with the same style, but with nothing recorded and nothing set
	c.list = Command_List{background = {0, 0, 0, 0}, style = c.list.style, transform = c.list.transform, turtle = c.list.turtle, look_changed = true}
	c.pending = false
}

// Puts the picture of the canvas as it was at the front of a round, unless the round
// starts over with `background` or `clear`, so the commands after it are drawn on top.
// `previous` is the canvas's own number: when its texture is read, it is the old one.
canvas_prepend_previous :: proc(list: ^Command_List, previous: Image_Id, width, height: f32) {
	if list.background_set {
		return
	}
	append(&list.looks, Look{DEFAULT_STYLE, IDENTITY})
	inject_at(&list.commands, 0, Recorded{
		kind = .Image,
		origin = .Corner,
		look = u32(len(list.looks) - 1),
		args = {0, 0, width, height, f32(previous), 0, 0, 0},
		content = u64(previous),
	})
}

canvas_destroy :: proc(c: ^Canvas) {
	for &round in c.rounds {
		destroy(&round.list)
	}
	delete(c.rounds)
	destroy(&c.list)
	batcher_destroy(&c.batcher)
	free(c)
}
