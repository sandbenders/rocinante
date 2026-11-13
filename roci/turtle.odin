// SPDX-License-Identifier: 0BSD
//
// The turtle verbs. Each window has its own turtle, which starts every frame in
// the middle of the window facing up; `right` turns it clockwise, as `turn` turns
// the canvas. Its lines are drawn in the stroke, or in black while the stroke is
// off, and `push` saves where it is (gfx/turtle.odin holds the rules).
package roci

import "gfx"

@(private = "file")
turtle_home_point :: proc(w: ^Win) -> [2]f64 {
	return {f64(w.width) / 2, f64(w.height) / 2}
}

// Walks the turtle forward, drawing a line while the pen is down.
forward :: proc(distance: f64) {
	w := current_win()
	if scene := &w.list.scene; scene.turtle.on {
		gfx.turtle3_forward(scene, distance, f64(w.list.style.thickness), turtle3_ink(&w.list))
		return
	}
	gfx.turtle_forward(&w.list, distance, turtle_home_point(w))
}

// Walks the turtle backwards, without turning it round.
back :: proc(distance: f64) {
	forward(-distance)
}

// Turns the turtle anticlockwise, in degrees.
left :: proc(degrees: f64) {
	if scene := &current_list().scene; scene.turtle.on {
		gfx.turtle3_right(scene, -degrees)
		return
	}
	gfx.turtle_right(current_list(), -degrees)
}

// Turns the turtle clockwise, in degrees.
right :: proc(degrees: f64) {
	if scene := &current_list().scene; scene.turtle.on {
		gfx.turtle3_right(scene, degrees)
		return
	}
	gfx.turtle_right(current_list(), degrees)
}

// Lifts the pen: the turtle moves without drawing.
pen_up :: proc() {
	if scene := &current_list().scene; scene.turtle.on {
		gfx.turtle3_pen(scene, false)
		return
	}
	gfx.turtle_pen(current_list(), false)
}

// Puts the pen down: the turtle draws as it moves.
pen_down :: proc() {
	if scene := &current_list().scene; scene.turtle.on {
		gfx.turtle3_pen(scene, true)
		return
	}
	gfx.turtle_pen(current_list(), true)
}

// Sends the turtle back to the middle of the window, facing up, without drawing.
home :: proc() {
	if scene := &current_list().scene; scene.turtle.on {
		gfx.turtle3_home(scene)
		return
	}
	gfx.turtle_home(current_list())
}

// Where the turtle is in the current window, for tests and tools.
turtle_position :: proc() -> [2]f64 {
	w := current_win()
	return gfx.turtle_position(&w.list, turtle_home_point(w))
}

// Where the turtle is, which way it faces and whether its pen is down: what a
// sketch reads as `turtle`.
Turtle_State :: struct {
	pos:   [2]f64, // in the coordinates shapes are drawn in
	angle: f64,    // degrees clockwise from up, from 0 up to but not including 360
	down:  bool,   // whether moving draws
}

// The current window's turtle.
turtle_state :: proc() -> Turtle_State {
	w := current_win()
	return {
		pos = gfx.turtle_position(&w.list, turtle_home_point(w)),
		angle = gfx.turtle_angle(&w.list),
		down = gfx.turtle_is_down(&w.list),
	}
}

// Draws the turtle itself where it is, pointing the way it faces.
show_turtle :: proc() {
	w := current_win()
	if scene := &w.list.scene; scene.turtle.on {
		gfx.turtle3_show(scene, turtle3_ink(&w.list))
		return
	}
	gfx.turtle_show(&w.list, turtle_home_point(w))
}

// ---- the turtle in space (gfx/turtle3.odin) ----

// What the turtle in space draws with: the stroke, or black while the stroke is off, as the flat one does.
@(private = "file")
turtle3_ink :: proc(list: ^gfx.Command_List) -> Colour {
	return list.style.stroke if list.style.stroke_on else gfx.TURTLE_INK
}

// Makes the window's turtle for the rest of the frame the one that walks the 3D scene, from the origin
// facing up the screen: `forward`, `left`, `right`, `pen up`, `pen down`, `home` and `show turtle` then
// act on it, and `up`, `down` and `roll` turn it in the other ways.
turtle_space :: proc() {
	scene := &current_list().scene
	if !scene.turtle.on {
		scene.turtle = gfx.Turtle3{on = true, pen_up = scene.turtle.pen_up}
	}
}

// Whether the window's turtle is the one in space.
turtle_in_space :: proc() -> bool {
	return current_list().scene.turtle.on
}

// Tips the turtle's nose towards its top, in degrees. Gives false when the turtle is flat, which turns nothing.
turtle_up :: proc(degrees: f64) -> bool {
	scene := &current_list().scene
	if !scene.turtle.on {
		return false
	}
	gfx.turtle3_up(scene, degrees)
	return true
}

// Tips the turtle's nose away from its top.
turtle_down :: proc(degrees: f64) -> bool {
	return turtle_up(-degrees)
}

// Rolls the turtle about the way it faces, its top going to the right, in degrees.
turtle_roll :: proc(degrees: f64) -> bool {
	scene := &current_list().scene
	if !scene.turtle.on {
		return false
	}
	gfx.turtle3_roll(scene, degrees)
	return true
}

// Where the turtle in space is, which way it faces and where its top and right side are, for tests and tools.
turtle3_state :: proc(w: Window) -> (at, heading, top, side: [3]f64) {
	if win := win_for(w); win != nil {
		t := &win.list.scene.turtle
		h, u, s := gfx.turtle3_axes(t)
		return t.at, h, u, s
	}
	return
}
