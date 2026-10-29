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
	gfx.turtle_forward(&w.list, distance, turtle_home_point(w))
}

// Walks the turtle backwards, without turning it round.
back :: proc(distance: f64) {
	forward(-distance)
}

// Turns the turtle anticlockwise, in degrees.
left :: proc(degrees: f64) {
	gfx.turtle_right(current_list(), -degrees)
}

// Turns the turtle clockwise, in degrees.
right :: proc(degrees: f64) {
	gfx.turtle_right(current_list(), degrees)
}

// Lifts the pen: the turtle moves without drawing.
pen_up :: proc() {
	gfx.turtle_pen(current_list(), false)
}

// Puts the pen down: the turtle draws as it moves.
pen_down :: proc() {
	gfx.turtle_pen(current_list(), true)
}

// Sends the turtle back to the middle of the window, facing up, without drawing.
home :: proc() {
	gfx.turtle_home(current_list())
}

// Where the turtle is in the current window, for tests and tools.
turtle_position :: proc() -> [2]f64 {
	w := current_win()
	return gfx.turtle_position(&w.list, turtle_home_point(w))
}
