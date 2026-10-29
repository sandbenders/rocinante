// SPDX-License-Identifier: 0BSD
//
// The turtle: a pen that walks the canvas, as in Logo. Each command list has
// one, so each window has its own, and it lives beside the style and the
// transform: `begin_frame` sends it home, `push` with the transform saves it and
// `pop` brings it back, so a branch of a tree can wander off and return.
//
// It starts in the middle of the window facing up, and `right` turns it
// clockwise. The list does not know how big its window is, so a turtle that has
// not moved yet is "at home" and the caller says where home is when it moves.
// Its lines are ordinary line commands, so the transform and the style apply to
// them; while the stroke is off it draws in black, so a turtle in a fresh sketch
// is seen.
package gfx

import "../maths"

Turtle :: struct {
	at:      [2]f64, // where it is, in the coordinates shapes are drawn in; meaningful once `placed`
	heading: f64,    // degrees clockwise from up
	placed:  bool,   // false while it is at home, wherever home is
	pen_up:  bool,   // it moves without drawing
}

// What the pen draws with while the stroke is off.
TURTLE_INK :: maths.Colour{0, 0, 0, 255}

// Where the turtle is, given where home is.
turtle_position :: proc "contextless" (list: ^Command_List, home: [2]f64) -> [2]f64 {
	return list.turtle.at if list.turtle.placed else home
}

// Moves the turtle `distance` along its heading (backwards when negative), drawing
// a line when its pen is down. Gives false when the line could not be recorded
// (a number that is not finite); the turtle then stays where it was.
turtle_forward :: proc(list: ^Command_List, distance: f64, home: [2]f64) -> bool {
	t := &list.turtle
	from := turtle_position(list, home)
	sine, cosine := maths.sin_cos_deg(t.heading)
	to := from + distance * [2]f64{sine, -cosine}
	if !finite(f32(to.x), f32(to.y)) {
		return false
	}
	t.at, t.placed = to, true
	if t.pen_up {
		return true
	}
	return turtle_line(list, from, to)
}

// Turns the turtle clockwise by `degrees` (anticlockwise when negative).
turtle_right :: proc(list: ^Command_List, degrees: f64) {
	if degrees * 0 != 0 {
		return // not finite: the heading would be lost for good
	}
	list.turtle.heading += degrees
}

turtle_pen :: proc(list: ^Command_List, down: bool) {
	list.turtle.pen_up = !down
}

// Back to the middle, facing up, without drawing; the pen stays up or down.
turtle_home :: proc(list: ^Command_List) {
	list.turtle = Turtle{pen_up = list.turtle.pen_up}
}

// A line in the stroke, or in the turtle's ink while the stroke is off.
@(private = "file")
turtle_line :: proc(list: ^Command_List, from, to: [2]f64) -> bool {
	if list.style.stroke_on {
		return line(list, f32(from.x), f32(from.y), f32(to.x), f32(to.y))
	}
	style := list.style
	set_stroke(list, TURTLE_INK)
	ok := line(list, f32(from.x), f32(from.y), f32(to.x), f32(to.y))
	list.style, list.look_changed = style, true
	return ok
}
